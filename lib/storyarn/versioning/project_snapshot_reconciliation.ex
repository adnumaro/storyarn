defmodule Storyarn.Versioning.ProjectSnapshotReconciliation do
  @moduledoc """
  Bounded, observation-only inspection of project snapshot durability.

  The inspector persists a versioned cursor and immutable findings, but never
  mutates snapshots, reservations, publication claims, cleanup ownership, quota
  accounting, or provider objects. Findings are evidence for a later fenced
  repair pass, never repair authority by themselves.
  """

  import Ecto.Query

  alias Ecto.Multi
  alias Storyarn.Assets.Storage
  alias Storyarn.Assets.StorageCleanupOwnershipReceipt
  alias Storyarn.Billing
  alias Storyarn.Billing.StorageReservation
  alias Storyarn.Platform.Shared.TimeHelpers
  alias Storyarn.Projects.Project
  alias Storyarn.Repo
  alias Storyarn.Versioning.ProjectSnapshot
  alias Storyarn.Versioning.ProjectSnapshotLifecycle
  alias Storyarn.Versioning.ProjectSnapshotReconciliationFinding
  alias Storyarn.Versioning.ProjectSnapshotReconciliationRun
  alias Storyarn.Versioning.SnapshotArchiveStorage
  alias Storyarn.Versioning.SnapshotCleanupIntent
  alias Storyarn.Versioning.SnapshotObjectPublicationClaim
  alias Storyarn.Workers.InspectProjectSnapshotsWorker

  require Logger

  @contract_version 1
  @default_max_objects_per_step 100
  @default_max_bytes_per_step 256 * 1024 * 1024
  @default_max_findings 10_000
  @default_provider_page_size 250
  @default_max_provider_objects 1_000_000
  @default_max_provider_bytes 10 * 1024 * 1024 * 1024 * 1024
  @max_cleanup_receipts_per_subject 100
  @max_cleanup_receipt_keys 20_004
  @max_bigint 9_223_372_036_854_775_807
  @inventory_digest_seed String.duplicate("0", 64)
  @provider_prefix "projects/"
  @build_worker "Storyarn.Workers.BuildProjectSnapshotWorker"
  @archive_build_queue "snapshot_archives"
  @inspection_worker "Storyarn.Workers.InspectProjectSnapshotsWorker"
  @active_build_job_states ~w(available scheduled executing retryable)
  @finding_insert_fields ProjectSnapshotReconciliationFinding.__schema__(:fields) -- [:id]
  @snapshot_key_pattern ~r<\Aprojects/([1-9]\d*)/snapshots/archives/v2/(ready|staging)/([A-Za-z0-9_-]{16})/(.+)\z>
  @reservation_key_pattern ~r<\Aprojects/([1-9]\d*)/storage-reservations/v1/(snapshot-build|restore-staging|snapshot-export)/([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})/(.+)\z>

  @type advance_result ::
          {:ok, :completed | :failed}
          | {:ok, :continue | :stale, pos_integer()}
          | {:error, term()}

  @doc "Starts or returns the active dry-run for the configured provider namespace."
  @spec start(keyword()) :: {:ok, ProjectSnapshotReconciliationRun.t()} | {:error, term()}
  def start(opts \\ [])

  def start(opts) when is_list(opts) do
    with true <- Keyword.keyword?(opts),
         {:ok, namespace_fingerprint} <- Storage.namespace_fingerprint(),
         :ok <- validate_run_options(opts) do
      Multi.new()
      |> Multi.run(:attrs, fn repo, _changes -> capture_run_attrs(repo, namespace_fingerprint, opts) end)
      |> Multi.insert(:run, fn %{attrs: attrs} ->
        ProjectSnapshotReconciliationRun.create_changeset(%ProjectSnapshotReconciliationRun{}, attrs)
      end)
      |> Multi.run(:job, fn _repo, %{run: run} ->
        run.id
        |> inspection_job(run.cursor_generation)
        |> Oban.insert()
      end)
      |> Repo.transaction()
      |> case do
        {:ok, %{run: run}} ->
          emit_started(run)
          {:ok, run}

        {:error, :run, %Ecto.Changeset{} = failed_changeset, _changes} ->
          existing_active_run(namespace_fingerprint, failed_changeset)

        {:error, :attrs, :snapshot_reconciliation_boundary_busy, _changes} ->
          existing_active_run(namespace_fingerprint, :snapshot_reconciliation_boundary_busy)

        {:error, _operation, reason, _changes} ->
          {:error, reason}
      end
    else
      false -> {:error, :invalid_snapshot_reconciliation_options}
      {:error, _reason} = error -> error
    end
  end

  def start(_opts), do: {:error, :invalid_snapshot_reconciliation_options}

  @doc "Returns one persisted dry-run."
  @spec get_run(pos_integer()) :: ProjectSnapshotReconciliationRun.t() | nil
  def get_run(run_id) when is_integer(run_id) and run_id > 0, do: Repo.get(ProjectSnapshotReconciliationRun, run_id)

  def get_run(_run_id), do: nil

  @doc "Lists immutable findings for a run in stable ID order."
  @spec list_findings(pos_integer(), keyword()) :: [ProjectSnapshotReconciliationFinding.t()]
  def list_findings(run_id, opts \\ [])

  def list_findings(run_id, opts) when is_integer(run_id) and run_id > 0 and is_list(opts) do
    case normalize_finding_page(opts) do
      {:ok, after_id, limit} -> query_findings(run_id, after_id, limit)
      :error -> []
    end
  end

  def list_findings(_run_id, _opts), do: []

  defp normalize_finding_page(opts) do
    after_id = Keyword.get(opts, :after_id, 0)
    requested_limit = Keyword.get(opts, :limit, 100)

    if Keyword.keyword?(opts) and is_integer(after_id) and after_id >= 0 and
         is_integer(requested_limit) and requested_limit > 0 do
      {:ok, after_id, min(requested_limit, 500)}
    else
      :error
    end
  end

  defp query_findings(run_id, after_id, limit) do
    Repo.all(
      from(finding in ProjectSnapshotReconciliationFinding,
        where: finding.run_id == ^run_id and finding.id > ^after_id,
        order_by: [asc: finding.id],
        limit: ^limit
      )
    )
  end

  @doc false
  @spec advance(pos_integer(), pos_integer()) :: advance_result()
  def advance(run_id, expected_generation)
      when is_integer(run_id) and run_id > 0 and is_integer(expected_generation) and expected_generation > 0 do
    with %ProjectSnapshotReconciliationRun{} = run <- Repo.get(ProjectSnapshotReconciliationRun, run_id),
         :ok <- validate_runnable(run, expected_generation),
         :ok <- validate_namespace(run.provider_namespace_fingerprint) do
      advance_phase(run)
    else
      nil -> {:error, :snapshot_reconciliation_run_not_found}
      {:terminal, "completed"} -> {:ok, :completed}
      {:terminal, "failed"} -> {:ok, :failed}
      {:stale, generation} -> {:ok, :stale, generation}
      {:error, _reason} = error -> error
    end
  end

  def advance(_run_id, _expected_generation), do: {:error, :invalid_snapshot_reconciliation_cursor}

  @doc false
  @spec fail(pos_integer(), pos_integer(), term()) ::
          {:ok, :completed | :failed | :stale} | {:error, term()}
  def fail(run_id, expected_generation, reason) do
    fn ->
      run = lock_run(run_id)

      cond do
        is_nil(run) ->
          Repo.rollback(:snapshot_reconciliation_run_not_found)

        run.status in ["completed", "failed"] ->
          {:terminal, String.to_existing_atom(run.status)}

        run.cursor_generation != expected_generation ->
          {:terminal, :stale}

        true ->
          now = TimeHelpers.now()

          updated =
            run
            |> ProjectSnapshotReconciliationRun.progress_changeset(%{
              status: "failed",
              cursor_generation: run.cursor_generation + 1,
              last_error_code: error_code(reason),
              started_at: run.started_at || now,
              finished_at: now
            })
            |> Repo.update!()

          {:failed, updated}
      end
    end
    |> Repo.transaction()
    |> case do
      {:ok, {:failed, run}} ->
        emit_finished(run, :failed)
        {:ok, :failed}

      {:ok, {:terminal, status}} ->
        {:ok, status}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp advance_phase(%ProjectSnapshotReconciliationRun{phase: "ready_snapshots"} = run), do: inspect_ready_snapshot(run)

  defp advance_phase(%ProjectSnapshotReconciliationRun{phase: "stale_reservations"} = run),
    do: inspect_stale_reservations(run)

  defp advance_phase(%ProjectSnapshotReconciliationRun{phase: "publication_claims"} = run),
    do: inspect_publication_claims(run)

  defp advance_phase(%ProjectSnapshotReconciliationRun{phase: "cleanup_intents"} = run), do: inspect_cleanup_intents(run)

  defp advance_phase(%ProjectSnapshotReconciliationRun{phase: "provider_objects"} = run), do: inspect_provider_page(run)

  defp advance_phase(%ProjectSnapshotReconciliationRun{phase: "completed"}), do: {:ok, :completed}
  defp advance_phase(_run), do: {:error, :invalid_snapshot_reconciliation_phase}

  defp inspect_ready_snapshot(run) do
    case current_ready_snapshot(run) do
      nil when is_integer(run.active_snapshot_id) ->
        run.id
        |> fail(run.cursor_generation, :snapshot_reconciliation_ready_candidate_changed)
        |> normalize_fail_result(run.id)

      nil ->
        transition_to_stale_reservations(run)

      %{snapshot: snapshot} = candidate ->
        inspect_ready_candidate(run, candidate, snapshot)
    end
  end

  defp current_ready_snapshot(%ProjectSnapshotReconciliationRun{active_snapshot_id: snapshot_id} = run)
       when is_integer(snapshot_id) do
    snapshot_candidate(
      snapshot_id,
      run.active_snapshot_generation,
      run.active_snapshot_accounting_generation
    )
  end

  defp current_ready_snapshot(run) do
    Repo.one(
      from(snapshot in ProjectSnapshot,
        left_join: project in Project,
        on: project.id == snapshot.project_id and is_nil(project.deleted_at),
        where:
          snapshot.id > ^run.snapshot_after_id and snapshot.id <= ^run.snapshot_high_watermark and
            snapshot.lifecycle_state == "ready",
        order_by: [asc: snapshot.id],
        limit: 1,
        select: %{snapshot: snapshot, workspace_id: project.workspace_id}
      )
    )
  end

  defp snapshot_candidate(snapshot_id, generation, accounting_generation) do
    Repo.one(
      from(snapshot in ProjectSnapshot,
        left_join: project in Project,
        on: project.id == snapshot.project_id and is_nil(project.deleted_at),
        where:
          snapshot.id == ^snapshot_id and snapshot.lifecycle_generation == ^generation and
            snapshot.accounting_generation == ^accounting_generation and
            snapshot.lifecycle_state == "ready",
        select: %{snapshot: snapshot, workspace_id: project.workspace_id}
      )
    )
  end

  defp inspect_ready_candidate(run, candidate, snapshot) do
    opts = [
      start_index: run.active_object_index,
      max_inspection_objects: run.max_objects_per_step,
      max_inspection_bytes: run.max_bytes_per_step
    ]

    case inspect_ready_snapshot(snapshot, opts) do
      {:ok, batch} ->
        inspect_verified_batch(run, candidate, batch)

      {:limit, manifest, max_bytes, archive_size_bytes} ->
        handle_ready_verification_limit(run, candidate, manifest, max_bytes, archive_size_bytes)

      {:error, {:snapshot_inspection_object_failed, failure}} ->
        handle_object_integrity_failure(run, candidate, failure)

      {:error, reason} ->
        handle_manifest_failure(run, candidate, reason)
    end
  end

  defp inspect_ready_snapshot(%ProjectSnapshot{format_version: 2} = snapshot, opts) do
    with {:ok, inspection} <- validate_archive_inspection_options(opts) do
      case inspection.start_index do
        0 -> inspect_ready_archive_payload(snapshot, inspection.max_bytes)
        1 -> inspect_ready_archive_manifest(snapshot)
      end
    end
  end

  defp inspect_ready_snapshot(%ProjectSnapshot{}, _opts), do: {:error, :unsupported_snapshot_reconciliation_format}

  defp validate_archive_inspection_options(opts) when is_list(opts) do
    start_index = Keyword.get(opts, :start_index, 0)
    max_objects = Keyword.get(opts, :max_inspection_objects, 100)
    max_bytes = Keyword.get(opts, :max_inspection_bytes, 256 * 1024 * 1024)

    if Keyword.keyword?(opts) and start_index in [0, 1] and is_integer(max_objects) and max_objects > 0 and
         max_objects <= 1_000 and is_integer(max_bytes) and max_bytes >= 128 * 1024 * 1024 and
         max_bytes <= 1024 * 1024 * 1024,
       do: {:ok, %{start_index: start_index, max_bytes: max_bytes}},
       else: {:error, :invalid_snapshot_inspection_limits}
  end

  defp validate_archive_inspection_options(_opts), do: {:error, :invalid_snapshot_inspection_limits}

  defp inspect_ready_archive_payload(snapshot, max_bytes) when snapshot.archive_size_bytes > max_bytes do
    case SnapshotArchiveStorage.inspect_ready_manifest(snapshot) do
      {:ok, manifest} -> {:limit, manifest, max_bytes, snapshot.archive_size_bytes}
      {:error, _reason} = error -> error
    end
  end

  defp inspect_ready_archive_payload(snapshot, _max_bytes) do
    case SnapshotArchiveStorage.inspect_ready_archive(snapshot) do
      {:ok, %{manifest: manifest}} ->
        {:ok,
         %{
           manifest: manifest,
           next_index: nil,
           verified_objects: 1,
           verified_bytes: snapshot.archive_size_bytes
         }}

      {:error, _reason} = error ->
        error
    end
  end

  defp inspect_ready_archive_manifest(snapshot) do
    case SnapshotArchiveStorage.inspect_ready_manifest(snapshot) do
      {:ok, manifest} ->
        {:ok, %{manifest: manifest, next_index: nil, verified_objects: 0, verified_bytes: 0}}

      {:error, _reason} = error ->
        error
    end
  end

  defp handle_ready_verification_limit(run, candidate, manifest, max_bytes, archive_size_bytes) do
    finding =
      finding(candidate, "ready_verification_limit_exceeded", "warning",
        storage_key: candidate.snapshot.archive_storage_key,
        expected_size_bytes: max_bytes,
        observed_size_bytes: archive_size_bytes,
        error_code: "ready_verification_limit_exceeded",
        details: %{
          "archive_size_bytes" => archive_size_bytes,
          "max_inspection_bytes" => max_bytes
        }
      )

    begin_ready_inventory(run, candidate, manifest,
      findings: [finding],
      inspected_objects: 0,
      inspected_bytes: 0
    )
  end

  defp inspect_verified_batch(run, candidate, batch) do
    cond do
      is_binary(run.active_inventory_digest) ->
        inspect_ready_inventory_page(run, candidate, batch.manifest)

      is_integer(batch.next_index) ->
        commit_snapshot_result(run, candidate,
          findings: [],
          complete?: false,
          next_index: batch.next_index,
          inspected_objects: batch.verified_objects,
          inspected_bytes: batch.verified_bytes
        )

      true ->
        begin_ready_inventory(run, candidate, batch.manifest,
          inspected_objects: batch.verified_objects,
          inspected_bytes: batch.verified_bytes
        )
    end
  end

  defp handle_object_integrity_failure(run, candidate, failure) do
    if reportable_integrity_reason?(failure.reason) do
      commit_object_integrity_failure(run, candidate, failure)
    else
      {:error, failure.reason}
    end
  end

  defp reportable_integrity_reason?(reason), do: integrity_reason?(reason) or missing_object_reason?(reason)

  defp commit_object_integrity_failure(run, candidate, failure) do
    finding =
      finding(candidate, integrity_failure_category(failure.path, failure.reason), "critical",
        storage_key: candidate.snapshot.object_prefix <> "/" <> failure.path,
        error_code: error_code(failure.reason),
        details: %{"path" => failure.path}
      )

    opts = [
      findings: [finding],
      inspected_objects: integrity_failure_inspected_objects(candidate.snapshot, failure),
      inspected_bytes: failure.verified_bytes
    ]

    commit_object_integrity_failure_result(run, candidate, failure, opts)
  end

  defp integrity_failure_category("manifest.json", reason) do
    if missing_object_reason?(reason), do: "ready_manifest_missing", else: "ready_manifest_corrupt"
  end

  defp integrity_failure_category(_path, reason) do
    if missing_object_reason?(reason), do: "ready_object_missing", else: "ready_object_corrupt"
  end

  defp integrity_failure_inspected_objects(%ProjectSnapshot{format_version: 2}, %{
         path: "manifest.json",
         verified_objects: verified_objects
       }), do: verified_objects

  defp integrity_failure_inspected_objects(%ProjectSnapshot{}, %{verified_objects: verified_objects}),
    do: verified_objects + 1

  defp commit_object_integrity_failure_result(
         run,
         %{snapshot: %ProjectSnapshot{format_version: 2}} = candidate,
         %{failed_index: 0},
         opts
       ) do
    commit_snapshot_result(
      run,
      candidate,
      opts
      |> Keyword.put(:complete?, false)
      |> Keyword.put(:next_index, 1)
    )
  end

  defp commit_object_integrity_failure_result(
         run,
         %{snapshot: %ProjectSnapshot{format_version: 2}} = candidate,
         _failure,
         opts
       ), do: commit_snapshot_result(run, candidate, Keyword.put(opts, :complete?, true))

  defp handle_manifest_failure(run, candidate, reason) do
    cond do
      missing_object_reason?(reason) ->
        finding =
          finding(candidate, "ready_manifest_missing", "critical",
            storage_key: candidate.snapshot.manifest_storage_key,
            error_code: error_code(reason)
          )

        commit_snapshot_result(run, candidate, findings: [finding], complete?: true)

      integrity_reason?(reason) ->
        finding =
          finding(candidate, "ready_manifest_corrupt", "critical",
            storage_key: candidate.snapshot.manifest_storage_key,
            error_code: error_code(reason)
          )

        commit_snapshot_result(run, candidate, findings: [finding], complete?: true)

      true ->
        {:error, reason}
    end
  end

  defp begin_ready_inventory(run, candidate, manifest, opts) do
    commit_run_progress(
      run,
      [
        findings: Keyword.get(opts, :findings, []),
        status: "running",
        active_snapshot_id: candidate.snapshot.id,
        active_snapshot_generation: candidate.snapshot.lifecycle_generation,
        active_snapshot_accounting_generation: candidate.snapshot.accounting_generation,
        active_object_index: inspected_object_index(candidate.snapshot, manifest),
        active_inventory_cursor: nil,
        active_inventory_digest: @inventory_digest_seed,
        active_inventory_last_key: nil,
        active_inventory_object_count: 0,
        active_inventory_bytes: 0,
        inspected_object_count: run.inspected_object_count + Keyword.get(opts, :inspected_objects, 0),
        inspected_bytes: run.inspected_bytes + Keyword.get(opts, :inspected_bytes, 0)
      ],
      candidate
    )
  end

  defp inspected_object_index(%ProjectSnapshot{format_version: 2}, _manifest), do: 1

  defp inspect_ready_inventory_page(run, candidate, manifest) do
    prefix = candidate.snapshot.object_prefix <> "/"
    page_size = min(run.provider_page_size, run.max_objects_per_step)

    with {:ok, page, next_cursor} <-
           list_ready_inventory_page(prefix, page_size, run.active_inventory_cursor),
         :ok <- validate_provider_page(page, next_cursor, run.active_inventory_cursor, prefix, page_size),
         :ok <- validate_provider_key_order(page, run.active_inventory_last_key),
         {:ok, digest} <- extend_inventory_digest(run.active_inventory_digest, page) do
      object_count = run.active_inventory_object_count + length(page)
      bytes = run.active_inventory_bytes + Enum.reduce(page, 0, &(&1.size + &2))
      expected_count = expected_physical_object_count(candidate.snapshot, manifest)

      cond do
        bytes > @max_bigint ->
          {:error, :snapshot_reconciliation_inventory_limit_exceeded}

        not is_nil(next_cursor) and object_count > expected_count ->
          findings =
            database_manifest_findings(candidate, manifest) ++
              [
                finding(candidate, "ready_inventory_mismatch", "critical",
                  error_code: "ready_inventory_mismatch",
                  details: %{"expected_count" => expected_count, "observed_count_at_least" => object_count}
                )
              ]

          commit_snapshot_result(run, candidate,
            findings: findings,
            complete?: true,
            inspected_objects: length(page),
            inspected_bytes: 0
          )

        is_nil(next_cursor) ->
          expected = expected_inventory(candidate.snapshot, manifest)

          findings =
            database_manifest_findings(candidate, manifest) ++
              inventory_findings(candidate, expected, digest, object_count, bytes)

          commit_snapshot_result(run, candidate,
            findings: findings,
            complete?: true,
            inspected_objects: length(page),
            inspected_bytes: 0
          )

        true ->
          commit_run_progress(
            run,
            [
              status: "running",
              active_inventory_cursor: next_cursor,
              active_inventory_digest: digest,
              active_inventory_last_key: page |> List.last() |> Map.fetch!(:key),
              active_inventory_object_count: object_count,
              active_inventory_bytes: bytes,
              inspected_object_count: run.inspected_object_count + length(page)
            ],
            candidate
          )
      end
    else
      {:error, _reason} = error -> error
    end
  end

  defp expected_physical_object_count(%ProjectSnapshot{format_version: 2}, _manifest), do: 2

  defp list_ready_inventory_page(prefix, page_size, cursor) do
    case Storage.list_prefix_metadata(prefix, limit: page_size, cursor: cursor) do
      {:ok, %{objects: page, cursor: next_cursor}} ->
        {:ok, page, next_cursor}

      {:error, reason} ->
        {:error, {:snapshot_reconciliation_provider_list_failed, reason}}

      _invalid ->
        {:error, :invalid_snapshot_reconciliation_provider_page}
    end
  end

  defp expected_inventory(%ProjectSnapshot{format_version: 2} = snapshot, _manifest) do
    objects =
      Enum.sort_by(
        [
          %{key: snapshot.archive_storage_key, size: snapshot.archive_size_bytes},
          %{key: snapshot.manifest_storage_key, size: snapshot.manifest_size_bytes}
        ],
        & &1.key
      )

    %{
      bytes: Enum.reduce(objects, 0, &(&1.size + &2)),
      count: 2,
      digest: inventory_digest(objects)
    }
  end

  defp database_manifest_findings(candidate, manifest) do
    case manifest_mismatches(candidate.snapshot, manifest) do
      [] ->
        []

      fields ->
        [
          finding(candidate, "ready_database_manifest_mismatch", "critical",
            error_code: "ready_database_manifest_mismatch",
            details: %{"fields" => Enum.join(fields, ",")}
          )
        ]
    end
  end

  defp inventory_findings(candidate, expected, observed_digest, observed_count, observed_bytes) do
    inventory_findings =
      if expected.digest == observed_digest and expected.count == observed_count do
        []
      else
        [
          finding(candidate, "ready_inventory_mismatch", "critical",
            error_code: "ready_inventory_mismatch",
            details: %{"expected_count" => expected.count, "observed_count" => observed_count}
          )
        ]
      end

    if expected.bytes == candidate.snapshot.accounted_size_bytes and
         observed_bytes == candidate.snapshot.accounted_size_bytes do
      inventory_findings
    else
      [
        finding(candidate, "ready_accounting_mismatch", "warning",
          expected_size_bytes: candidate.snapshot.accounted_size_bytes,
          observed_size_bytes: observed_bytes,
          error_code: "ready_accounting_mismatch",
          details: %{"manifest_bytes" => expected.bytes}
        )
        | inventory_findings
      ]
    end
  end

  defp inventory_digest(objects) do
    {:ok, digest} = extend_inventory_digest(@inventory_digest_seed, objects)
    digest
  end

  defp extend_inventory_digest(digest, objects) do
    case Base.decode16(digest, case: :lower) do
      {:ok, initial} ->
        result =
          Enum.reduce(objects, initial, fn object, accumulator ->
            :crypto.hash(
              :sha256,
              [accumulator, <<byte_size(object.key)::unsigned-32>>, object.key, <<object.size::unsigned-64>>]
            )
          end)

        {:ok, Base.encode16(result, case: :lower)}

      :error ->
        {:error, :invalid_snapshot_reconciliation_inventory_digest}
    end
  end

  defp transition_to_stale_reservations(run) do
    commit_run_progress(run,
      status: "running",
      phase: "stale_reservations",
      snapshot_after_id: run.snapshot_high_watermark,
      active_snapshot_id: nil,
      active_snapshot_generation: nil,
      active_snapshot_accounting_generation: nil,
      active_object_index: 0,
      active_inventory_cursor: nil,
      active_inventory_digest: nil,
      active_inventory_last_key: nil,
      active_inventory_object_count: 0,
      active_inventory_bytes: 0
    )
  end

  defp inspect_stale_reservations(run) do
    now = TimeHelpers.now()

    quiesced_before =
      DateTime.add(now, -ProjectSnapshotLifecycle.build_recovery_quarantine_seconds(), :second)

    limit = database_page_limit(run)

    rows =
      Repo.all(
        from(reservation in StorageReservation,
          left_join: snapshot in ProjectSnapshot,
          on: snapshot.id == reservation.project_snapshot_id_snapshot,
          left_join: job in Oban.Job,
          on: job.id == snapshot.build_job_id,
          where:
            reservation.kind == "snapshot_build" and reservation.status == "active" and
              reservation.expires_at <= ^now and reservation.id > ^run.reservation_after_id and
              reservation.id <= ^run.reservation_high_watermark,
          order_by: [asc: reservation.id],
          limit: ^limit,
          select: {reservation, snapshot, job}
        )
      )

    findings =
      Enum.flat_map(rows, fn {reservation, snapshot, job} ->
        case stale_reservation_reason(reservation, snapshot, job, quiesced_before) do
          nil -> []
          reason -> [stale_reservation_finding(reservation, snapshot, reason)]
        end
      end)

    complete? = length(rows) < limit

    after_id =
      if complete?,
        do: run.reservation_high_watermark,
        else: rows |> List.last() |> elem(0) |> Map.fetch!(:id)

    commit_run_progress(run,
      findings: findings,
      status: "running",
      phase: if(complete?, do: "publication_claims", else: "stale_reservations"),
      reservation_after_id: after_id
    )
  end

  defp stale_reservation_reason(_reservation, nil, _job, _quiesced_before), do: "snapshot_missing"

  defp stale_reservation_reason(reservation, snapshot, _job, _quiesced_before)
       when snapshot.storage_reservation_id != reservation.id, do: "snapshot_reservation_mismatch"

  defp stale_reservation_reason(_reservation, snapshot, nil, quiesced_before) do
    if old_enough?(snapshot.state_updated_at, quiesced_before), do: "owning_job_missing"
  end

  defp stale_reservation_reason(_reservation, snapshot, %Oban.Job{worker: @build_worker} = job, quiesced_before) do
    if build_job_queue_matches?(snapshot, job),
      do: terminal_build_job_reason(job, quiesced_before),
      else: mismatched_build_job_reason(snapshot, job, quiesced_before)
  end

  defp stale_reservation_reason(_reservation, snapshot, %Oban.Job{}, quiesced_before),
    do: invalid_build_job_reason(snapshot, quiesced_before)

  defp invalid_build_job_reason(snapshot, quiesced_before) do
    if old_enough?(snapshot.state_updated_at, quiesced_before), do: "owning_job_invalid"
  end

  defp mismatched_build_job_reason(snapshot, job, quiesced_before) do
    if terminal_build_job_reason(job, quiesced_before),
      do: "owning_job_invalid",
      else: invalid_build_job_reason(snapshot, quiesced_before)
  end

  defp terminal_build_job_reason(%Oban.Job{state: "completed", completed_at: completed_at}, before),
    do: if(old_enough?(completed_at, before), do: "owning_job_completed")

  defp terminal_build_job_reason(%Oban.Job{state: "discarded", discarded_at: discarded_at}, before),
    do: if(old_enough?(discarded_at, before), do: "owning_job_discarded")

  defp terminal_build_job_reason(%Oban.Job{state: "cancelled", cancelled_at: cancelled_at}, before),
    do: if(old_enough?(cancelled_at, before), do: "owning_job_cancelled")

  defp terminal_build_job_reason(%Oban.Job{state: state}, _before) when state in @active_build_job_states, do: nil
  defp terminal_build_job_reason(%Oban.Job{}, _before), do: nil

  defp inspect_publication_claims(run) do
    if run.claim_sequence_high_watermark == 0 do
      transition_to_cleanup_intents(run)
    else
      inspect_publication_claim_page(run)
    end
  end

  defp inspect_publication_claim_page(run) do
    now = TimeHelpers.now()
    quiesced_before = DateTime.add(now, -ProjectSnapshotLifecycle.build_recovery_quarantine_seconds(), :second)
    limit = database_page_limit(run)

    rows = Repo.all(publication_claim_query(run, limit))

    findings =
      Enum.flat_map(rows, fn {claim, reservation, snapshot, job} ->
        case failed_finalization_reason(claim, reservation, snapshot, job, now, quiesced_before) do
          nil -> []
          reason -> [failed_finalization_finding(claim, reservation, snapshot, reason)]
        end
      end)

    complete? = length(rows) < limit

    after_sequence =
      if complete?,
        do: run.claim_sequence_high_watermark,
        else: rows |> List.last() |> elem(0) |> Map.fetch!(:reconciliation_sequence)

    commit_run_progress(run,
      findings: findings,
      status: "running",
      phase: if(complete?, do: "cleanup_intents", else: "publication_claims"),
      claim_after_sequence: after_sequence
    )
  end

  defp publication_claim_query(run, limit) do
    query =
      from(claim in SnapshotObjectPublicationClaim,
        left_join: reservation in StorageReservation,
        on: reservation.id == claim.storage_reservation_id_snapshot,
        left_join: snapshot in ProjectSnapshot,
        on: snapshot.object_prefix == claim.object_prefix,
        left_join: job in Oban.Job,
        on: job.id == snapshot.build_job_id,
        where: claim.reconciliation_sequence <= ^run.claim_sequence_high_watermark,
        order_by: [asc: claim.reconciliation_sequence],
        limit: ^limit,
        select: {claim, reservation, snapshot, job}
      )

    if run.claim_after_sequence > 0,
      do: where(query, [claim], claim.reconciliation_sequence > ^run.claim_after_sequence),
      else: query
  end

  defp transition_to_cleanup_intents(run) do
    commit_run_progress(run,
      status: "running",
      phase: "cleanup_intents",
      claim_after_sequence: run.claim_sequence_high_watermark
    )
  end

  defp failed_finalization_reason(
         %SnapshotObjectPublicationClaim{status: "poisoned"} = claim,
         reservation,
         snapshot,
         _job,
         _now,
         _before
       ) do
    if resolved_poisoned_claim?(claim, reservation, snapshot),
      do: nil,
      else: "publication_claim_poisoned"
  end

  defp failed_finalization_reason(
         %SnapshotObjectPublicationClaim{status: "published"} = claim,
         reservation,
         snapshot,
         job,
         _now,
         before
       ) do
    valid? =
      match?(%ProjectSnapshot{lifecycle_state: "ready"}, snapshot) and
        match?(%StorageReservation{status: "committed"}, reservation) and
        snapshot.storage_reservation_id == reservation.id and
        snapshot.publication_claim_token == claim.claim_token and
        claim.storage_reservation_lease_token == reservation.lease_token and
        SnapshotObjectPublicationClaim.inventory_digest(snapshot) == claim.inventory_digest

    if not valid? and not live_build_job?(snapshot, job) and old_enough?(claim.updated_at, before),
      do: "published_claim_ownership_mismatch"
  end

  defp failed_finalization_reason(claim, _reservation, snapshot, job, now, before)
       when claim.status in ["staging", "staged", "publishing"] do
    expired? = is_nil(claim.lease_expires_at) or DateTime.compare(claim.lease_expires_at, now) != :gt

    if expired? and not live_build_job?(snapshot, job) and old_enough?(claim.updated_at, before),
      do: "publication_claim_lease_expired"
  end

  defp resolved_poisoned_claim?(
         %SnapshotObjectPublicationClaim{} = claim,
         %StorageReservation{status: "released", cleanup_status: "owned", cleanup_reference: cleanup_reference} =
           reservation,
         %ProjectSnapshot{lifecycle_state: lifecycle_state} = snapshot
       ) do
    with true <- lifecycle_state in ["failed", "cancelled", "deleting"],
         true <- claim.storage_reservation_id_snapshot == reservation.id,
         true <- claim.storage_reservation_lease_token == reservation.lease_token,
         true <- snapshot.storage_reservation_id == reservation.id,
         true <- snapshot.publication_claim_token == claim.claim_token,
         true <- claim.object_prefix == reservation.cleanup_object_prefix,
         true <- snapshot.id == reservation.project_snapshot_id_snapshot,
         true <- snapshot.object_prefix == claim.object_prefix,
         {:ok, cleanup_request_id} <- cleanup_request_id(cleanup_reference),
         {:ok, receipt_keys} <- StorageCleanupOwnershipReceipt.storage_keys(cleanup_request_id),
         {:ok, scope} <- reconciliation_cleanup_scope(snapshot) do
      reservation.cleanup_inventory_count == length(scope.storage_keys) and
        reservation.cleanup_inventory_digest == scope.inventory_digest and
        same_string_inventory?(receipt_keys, scope.storage_keys)
    else
      _invalid -> false
    end
  end

  defp resolved_poisoned_claim?(_claim, _reservation, _snapshot), do: false

  defp reconciliation_cleanup_scope(%ProjectSnapshot{format_version: 2} = snapshot) do
    SnapshotArchiveStorage.cleanup_scope_from_snapshot(snapshot)
  end

  defp reconciliation_cleanup_scope(%ProjectSnapshot{}), do: {:error, :unsupported_snapshot_reconciliation_format}

  defp cleanup_request_id("storage_cleanup_request:" <> encoded_id) do
    case Integer.parse(encoded_id) do
      {cleanup_request_id, ""} when cleanup_request_id > 0 -> {:ok, cleanup_request_id}
      _invalid -> {:error, :invalid_cleanup_reference}
    end
  end

  defp cleanup_request_id(_cleanup_reference), do: {:error, :invalid_cleanup_reference}

  defp same_string_inventory?(left, right) when is_list(left) and is_list(right) do
    length(left) == length(right) and MapSet.equal?(MapSet.new(left), MapSet.new(right))
  end

  defp same_string_inventory?(_left, _right), do: false

  defp inspect_cleanup_intents(run) do
    limit = database_page_limit(run)

    rows =
      Repo.all(
        from(intent in SnapshotCleanupIntent,
          where:
            intent.status == "terminal" and intent.id > ^run.cleanup_intent_after_id and
              intent.id <= ^run.cleanup_intent_high_watermark,
          order_by: [asc: intent.id],
          limit: ^limit,
          select: %{
            id: intent.id,
            workspace_id_snapshot: intent.workspace_id_snapshot,
            project_id_snapshot: intent.project_id_snapshot,
            project_snapshot_id_snapshot: intent.project_snapshot_id_snapshot,
            deletion_generation: intent.deletion_generation,
            ready_prefix: intent.ready_prefix,
            estimated_cleanup_bytes: intent.estimated_cleanup_bytes,
            last_error_code: intent.last_error_code,
            processing_generation: intent.processing_generation,
            reason: intent.reason,
            retry_count: intent.retry_count
          }
        )
      )

    complete? = length(rows) < limit

    after_id =
      if complete?,
        do: run.cleanup_intent_high_watermark,
        else: rows |> List.last() |> Map.fetch!(:id)

    commit_run_progress(run,
      findings: Enum.map(rows, &terminal_cleanup_finding/1),
      status: "running",
      phase: if(complete?, do: "provider_objects", else: "cleanup_intents"),
      cleanup_intent_after_id: after_id
    )
  end

  defp database_page_limit(run), do: run.max_objects_per_step

  defp live_build_job?(snapshot, %Oban.Job{worker: @build_worker, state: state} = job),
    do: state in @active_build_job_states and build_job_queue_matches?(snapshot, job)

  defp live_build_job?(_snapshot, _job), do: false

  defp build_job_queue_matches?(%ProjectSnapshot{format_version: 2}, %Oban.Job{queue: @archive_build_queue}), do: true

  defp build_job_queue_matches?(_snapshot, _job), do: false

  defp old_enough?(%DateTime{} = value, %DateTime{} = before), do: DateTime.compare(value, before) != :gt
  defp old_enough?(_value, _before), do: false

  defp inspect_provider_page(run) do
    case Storage.list_prefix_metadata(@provider_prefix, limit: run.provider_page_size, cursor: run.provider_cursor) do
      {:ok, %{objects: objects, cursor: next_cursor}} ->
        inspect_provider_page(run, objects, next_cursor)

      {:error, reason} ->
        {:error, {:snapshot_reconciliation_provider_list_failed, reason}}

      _invalid ->
        {:error, :invalid_snapshot_reconciliation_provider_page}
    end
  end

  defp inspect_provider_page(run, objects, next_cursor) do
    with :ok <-
           validate_provider_page(
             objects,
             next_cursor,
             run.provider_cursor,
             @provider_prefix,
             run.provider_page_size
           ),
         :ok <- validate_provider_key_order(objects, run.provider_last_key),
         {:ok, page_bytes} <- provider_page_budget(run, objects) do
      persist_provider_page(run, objects, next_cursor, page_bytes)
    else
      {:error, :snapshot_reconciliation_provider_inventory_limit_exceeded} ->
        fail_provider_limit(run)

      {:error, _reason} = error ->
        error
    end
  end

  defp persist_provider_page(run, objects, next_cursor, page_bytes) do
    completed? = is_nil(next_cursor)

    case classify_provider_objects(objects) do
      {:ok, findings} ->
        commit_run_progress(run,
          findings: findings,
          status: if(completed?, do: "completed", else: "running"),
          phase: if(completed?, do: "completed", else: "provider_objects"),
          provider_cursor: next_cursor,
          provider_last_key: provider_last_key(objects, run.provider_last_key),
          provider_object_count: run.provider_object_count + length(objects),
          provider_bytes: run.provider_bytes + page_bytes,
          provider_scan_completed: completed?,
          finished_at: if(completed?, do: TimeHelpers.now())
        )

      {:error, :snapshot_reconciliation_cleanup_evidence_limit_exceeded} ->
        fail_provider_limit(run, :snapshot_reconciliation_cleanup_evidence_limit_exceeded)

      {:error, _reason} = error ->
        error
    end
  end

  defp fail_provider_limit(run, reason \\ :snapshot_reconciliation_provider_inventory_limit_exceeded) do
    case fail(run.id, run.cursor_generation, reason) do
      {:ok, :failed} -> {:ok, :failed}
      {:ok, :stale} -> stale_advance_result(run.id)
      other -> other
    end
  end

  defp classify_provider_objects(objects) do
    subjects = Enum.map(objects, &provider_subject/1)

    with {:ok, evidence} <- ownership_evidence(subjects) do
      findings =
        Enum.flat_map(Enum.zip(objects, subjects), fn {object, subject} ->
          classify_provider_object(object, subject, provider_evidence(evidence, subject))
        end)

      {:ok, findings}
    end
  end

  defp ownership_evidence(subjects) do
    case Repo.repeatable_read(fn -> collect_ownership_evidence(subjects) end) do
      {:ok, result} -> result
      {:error, reason} -> {:error, {:snapshot_reconciliation_ownership_read_failed, reason}}
    end
  end

  defp collect_ownership_evidence(subjects) do
    canonical = Enum.reject(subjects, &(&1.kind in [:unsafe, :unrelated]))
    prefixes = canonical |> Enum.map(& &1.prefix) |> Enum.uniq()
    ready_prefixes = canonical |> Enum.map(& &1.ready_prefix) |> Enum.reject(&is_nil/1) |> Enum.uniq()

    index =
      %{}
      |> add_project_evidence(canonical)
      |> add_snapshot_evidence(ready_prefixes, canonical)
      |> add_reservation_evidence(ready_prefixes, prefixes, canonical)
      |> add_claim_evidence(ready_prefixes, canonical)

    add_cleanup_evidence(index, canonical)
  end

  defp add_cleanup_evidence(index, []), do: {:ok, index}

  defp add_cleanup_evidence(index, subjects) do
    prefixes = Enum.map(subjects, & &1.prefix)
    storage_keys = Enum.map(subjects, & &1.storage_key)

    %{rows: rows} =
      Repo.query!(
        """
        WITH subjects(object_prefix, storage_key) AS (
          SELECT * FROM unnest($1::text[], $2::text[])
        ),
        raw_evidence AS (
          SELECT subjects.object_prefix,
                 subjects.storage_key,
                 ownership.cleanup_request_id,
                 ownership.receipt_keys,
                 ownership.owner_kind,
                 ownership.request_keys,
                 ownership.intent_status,
                 ownership.remaining_keys
          FROM subjects
          LEFT JOIN LATERAL (
            SELECT namespaces.cleanup_request_id,
                   receipts.storage_keys AS receipt_keys,
                   requests.owner_kind,
                   requests.storage_keys AS request_keys,
                   intents.status AS intent_status,
                   intents.remaining_storage_keys AS remaining_keys
            FROM storage_cleanup_ownership_namespaces AS namespaces
            JOIN storage_cleanup_ownership_receipts AS receipts
              ON receipts.cleanup_request_id = namespaces.cleanup_request_id
            LEFT JOIN storage_cleanup_requests AS requests
              ON requests.id = namespaces.cleanup_request_id
            LEFT JOIN snapshot_cleanup_intents AS intents
              ON intents.cleanup_request_id = namespaces.cleanup_request_id
            WHERE namespaces.object_prefix = subjects.object_prefix
            LIMIT $3
          ) AS ownership ON true
        ),
        evidence AS (
          SELECT object_prefix,
                 storage_key,
                 cleanup_request_id,
                 cardinality(receipt_keys) > $4 OR
                   COALESCE(cardinality(request_keys) > $4, false) OR
                   COALESCE(cardinality(remaining_keys) > $4, false) AS oversized,
                 CASE
                   WHEN cardinality(receipt_keys) <= $4
                     THEN storage_key = ANY(receipt_keys)
                   ELSE false
                 END AS matched,
                 CASE
                   WHEN owner_kind = 'snapshot_lifecycle' AND
                        intent_status IN ('pending', 'processing', 'retrying', 'terminal') AND
                        COALESCE(cardinality(remaining_keys) <= $4, false)
                     THEN storage_key = ANY(remaining_keys)
                   WHEN owner_kind = 'storage_compensation' AND
                        COALESCE(cardinality(request_keys) <= $4, false)
                     THEN storage_key = ANY(request_keys)
                   ELSE false
                 END AS active
          FROM raw_evidence
        )
        SELECT object_prefix,
               storage_key,
               COUNT(cleanup_request_id),
               COALESCE(bool_or(oversized), false),
               COALESCE(bool_or(matched AND active), false),
               COALESCE(bool_or(matched AND NOT active), false)
        FROM evidence
        GROUP BY object_prefix, storage_key
        """,
        [
          prefixes,
          storage_keys,
          @max_cleanup_receipts_per_subject + 1,
          @max_cleanup_receipt_keys
        ]
      )

    reduce_cleanup_evidence(rows, index)
  end

  defp reduce_cleanup_evidence(rows, index) do
    Enum.reduce_while(rows, {:ok, index}, fn
      [_prefix, _storage_key, receipt_count, oversized?, _active?, _historical?], _acc
      when receipt_count > @max_cleanup_receipts_per_subject or oversized? ->
        {:halt, {:error, :snapshot_reconciliation_cleanup_evidence_limit_exceeded}}

      [prefix, storage_key, _receipt_count, _oversized?, active?, historical?], {:ok, acc} ->
        evidence = cleanup_states(active?, historical?)
        updated = Enum.reduce(evidence, acc, &put_key_evidence(&2, prefix, storage_key, &1))
        {:cont, {:ok, updated}}
    end)
  end

  defp cleanup_states(active?, historical?) do
    []
    |> maybe_add_cleanup_state(active?, {:cleanup, :aggregated, :active})
    |> maybe_add_cleanup_state(historical?, {:cleanup, :aggregated, :historical})
  end

  defp maybe_add_cleanup_state(states, true, state), do: [state | states]
  defp maybe_add_cleanup_state(states, false, _state), do: states

  defp provider_page_budget(run, objects) do
    page_bytes = Enum.reduce(objects, 0, &(&1.size + &2))

    if run.provider_object_count + length(objects) <= run.max_provider_objects and
         run.provider_bytes + page_bytes <= run.max_provider_bytes do
      {:ok, page_bytes}
    else
      {:error, :snapshot_reconciliation_provider_inventory_limit_exceeded}
    end
  end

  defp provider_subject(%{key: key}) do
    with true <- Storage.canonical_key?(key),
         [_, project_id_string, namespace, token, path] <- Regex.run(@snapshot_key_pattern, key),
         {:ok, project_id} <- parse_project_id(project_id_string) do
      %{
        kind: snapshot_namespace_atom(namespace),
        path: path,
        prefix: "projects/#{project_id}/snapshots/archives/v2/#{namespace}/#{token}",
        project_id: project_id,
        ready_prefix: "projects/#{project_id}/snapshots/archives/v2/ready/#{token}",
        storage_key: key
      }
    else
      _invalid -> reservation_subject(key)
    end
  end

  defp reservation_subject(key) do
    with true <- Storage.canonical_key?(key),
         [_, project_id_string, kind, lease_token, path] <- Regex.run(@reservation_key_pattern, key),
         {:ok, project_id} <- parse_project_id(project_id_string) do
      %{
        kind: :reservation,
        operation_kind: String.replace(kind, "-", "_"),
        lease_token: lease_token,
        path: path,
        prefix: "projects/#{project_id}/storage-reservations/v1/#{kind}/#{lease_token}",
        project_id: project_id,
        ready_prefix: nil,
        storage_key: key
      }
    else
      _invalid ->
        if String.contains?(key, ["/snapshots/object-sets/", "/snapshots/archives/", "/storage-reservations/"]),
          do: %{kind: :unsafe, prefix: nil, project_id: nil, ready_prefix: nil, storage_key: key},
          else: %{kind: :unrelated, prefix: nil, project_id: nil, ready_prefix: nil, storage_key: key}
    end
  end

  defp add_project_evidence(index, []), do: index

  defp add_project_evidence(index, subjects) do
    project_ids = subjects |> Enum.map(& &1.project_id) |> Enum.uniq()

    workspaces =
      from(project in Project,
        where: project.id in ^project_ids and is_nil(project.deleted_at),
        select: {project.id, project.workspace_id}
      )
      |> Repo.all()
      |> Map.new()

    Enum.reduce(subjects, index, fn subject, acc ->
      case Map.fetch(workspaces, subject.project_id) do
        {:ok, workspace_id} -> put_evidence(acc, subject.prefix, {:project, subject.project_id, workspace_id})
        :error -> acc
      end
    end)
  end

  defp add_snapshot_evidence(index, [], _subjects), do: index

  defp add_snapshot_evidence(index, ready_prefixes, subjects) do
    rows =
      Repo.all(
        from(snapshot in ProjectSnapshot,
          left_join: project in Project,
          on: project.id == snapshot.project_id and is_nil(project.deleted_at),
          where: snapshot.object_prefix in ^ready_prefixes,
          select: {snapshot.object_prefix, snapshot, project.workspace_id}
        )
      )

    Enum.reduce(rows, index, fn {ready_prefix, snapshot, workspace_id}, acc ->
      put_ready_evidence(acc, subjects, ready_prefix, {:snapshot, snapshot, workspace_id})
    end)
  end

  defp add_reservation_evidence(index, [], [], _subjects), do: index

  defp add_reservation_evidence(index, ready_prefixes, prefixes, subjects) do
    rows =
      Repo.all(
        from(reservation in StorageReservation,
          where:
            reservation.cleanup_object_prefix in ^ready_prefixes or
              reservation.storage_namespace in ^prefixes
        )
      )

    Enum.reduce(rows, index, fn reservation, acc ->
      acc
      |> put_ready_evidence(subjects, reservation.cleanup_object_prefix, {:reservation, reservation})
      |> put_evidence(reservation.storage_namespace, {:reservation, reservation})
    end)
  end

  defp add_claim_evidence(index, [], _subjects), do: index

  defp add_claim_evidence(index, ready_prefixes, subjects) do
    from(claim in SnapshotObjectPublicationClaim,
      where: claim.object_prefix in ^ready_prefixes
    )
    |> Repo.all()
    |> Enum.reduce(index, fn claim, acc ->
      put_ready_evidence(acc, subjects, claim.object_prefix, {:claim, claim})
    end)
  end

  defp put_ready_evidence(index, subjects, ready_prefix, evidence) when is_binary(ready_prefix) do
    subjects
    |> Enum.filter(&(&1.ready_prefix == ready_prefix))
    |> Enum.reduce(index, fn subject, acc -> put_evidence(acc, subject.prefix, evidence) end)
  end

  defp put_ready_evidence(index, _subjects, _ready_prefix, _evidence), do: index

  defp put_evidence(index, prefix, evidence) when is_binary(prefix),
    do: Map.update(index, {:prefix, prefix}, [evidence], &[evidence | &1])

  defp put_evidence(index, _prefix, _evidence), do: index

  defp put_key_evidence(index, prefix, storage_key, evidence) when is_binary(prefix) and is_binary(storage_key),
    do: Map.update(index, {:key, prefix, storage_key}, [evidence], &[evidence | &1])

  defp provider_evidence(index, subject) do
    prefix = subject_prefix(subject)
    storage_key = Map.get(subject, :storage_key)

    Map.get(index, {:prefix, prefix}, []) ++ Map.get(index, {:key, prefix, storage_key}, [])
  end

  defp classify_provider_object(_object, %{kind: :unrelated}, _evidence), do: []

  defp classify_provider_object(object, %{kind: :unsafe}, evidence) do
    [
      provider_finding(object, nil, evidence, "unsafe_snapshot_storage_key", "critical",
        error_code: "unsafe_snapshot_storage_key"
      )
    ]
  end

  defp classify_provider_object(object, subject, evidence) do
    cond do
      conflicting_live_and_cleanup?(subject, evidence) ->
        [
          provider_finding(object, subject, evidence, "ambiguous_storage_object", "critical",
            error_code: "snapshot_storage_object_has_conflicting_owners"
          )
        ]

      valid_provider_owner?(subject, evidence) ->
        []

      historical_cleanup?(evidence) ->
        [
          provider_finding(object, subject, evidence, "ambiguous_storage_object", "critical",
            error_code: "snapshot_storage_object_reappeared_after_cleanup"
          )
        ]

      abandoned_temporary?(subject, evidence) ->
        [
          provider_finding(object, subject, evidence, "abandoned_temporary_object", "warning",
            error_code: "snapshot_temporary_object_is_not_live"
          )
        ]

      true ->
        [
          provider_finding(object, subject, evidence, "ambiguous_storage_object", "critical",
            error_code: "snapshot_storage_object_has_no_compatible_owner"
          )
        ]
    end
  end

  defp conflicting_live_and_cleanup?(%{kind: :ready} = subject, evidence),
    do: active_cleanup?(evidence) and ready_owner?(subject, evidence)

  defp conflicting_live_and_cleanup?(%{kind: :staging} = subject, evidence),
    do: active_cleanup?(evidence) and coherent_staging_owner?(subject, evidence)

  defp conflicting_live_and_cleanup?(%{kind: :reservation} = subject, evidence),
    do: active_cleanup?(evidence) and coherent_reservation_owner?(subject, evidence)

  defp conflicting_live_and_cleanup?(_subject, _evidence), do: false

  defp valid_provider_owner?(%{kind: :ready} = subject, evidence) do
    active_cleanup?(evidence) or ready_owner?(subject, evidence)
  end

  defp valid_provider_owner?(%{kind: :staging} = subject, evidence) do
    active_cleanup?(evidence) or coherent_staging_owner?(subject, evidence)
  end

  defp valid_provider_owner?(%{kind: :reservation} = subject, evidence) do
    active_cleanup?(evidence) or coherent_reservation_owner?(subject, evidence)
  end

  defp coherent_staging_owner?(subject, evidence) do
    snapshots = for {:snapshot, snapshot, _workspace_id} <- evidence, do: snapshot
    reservations = for {:reservation, reservation} <- evidence, do: reservation
    claims = for {:claim, claim} <- evidence, do: claim

    for_result =
      for(snapshot <- snapshots, reservation <- reservations, claim <- claims, do: {snapshot, reservation, claim})

    Enum.any?(for_result, &coherent_staging_tuple?(subject, &1))
  end

  defp coherent_staging_tuple?(
         subject,
         {%ProjectSnapshot{} = snapshot, %StorageReservation{} = reservation, %SnapshotObjectPublicationClaim{} = claim}
       ) do
    staging_snapshot_matches?(snapshot, reservation, claim, subject) and
      staging_reservation_matches?(reservation, snapshot, subject) and
      staging_claim_matches?(claim, reservation, subject) and
      operation_prefixes_match?(reservation, subject)
  end

  defp staging_snapshot_matches?(snapshot, reservation, claim, subject) do
    snapshot.lifecycle_state in ["building", "verifying"] and
      is_nil(snapshot.cancel_requested_at) and
      snapshot.project_id == subject.project_id and
      snapshot.object_prefix == subject.ready_prefix and
      snapshot.storage_reservation_id == reservation.id and
      snapshot.publication_claim_token == claim.claim_token
  end

  defp staging_reservation_matches?(reservation, snapshot, subject) do
    reservation.status == "active" and
      reservation.kind == "snapshot_build" and
      not is_nil(reservation.storage_started_at) and
      reservation.project_id_snapshot == subject.project_id and
      reservation.project_snapshot_id_snapshot == snapshot.id
  end

  defp staging_claim_matches?(claim, reservation, subject) do
    claim.status in ["staging", "staged", "publishing"] and
      claim.object_prefix == subject.ready_prefix and
      claim.storage_reservation_id_snapshot == reservation.id and
      claim.storage_reservation_lease_token == reservation.lease_token
  end

  defp coherent_reservation_owner?(subject, evidence) do
    Enum.any?(evidence, fn
      {:reservation, %StorageReservation{} = reservation} ->
        reservation.status == "active" and
          not is_nil(reservation.storage_started_at) and
          reservation.kind == subject.operation_kind and
          reservation.project_id_snapshot == subject.project_id and
          reservation.storage_namespace == subject.prefix and
          reservation.lease_token == subject.lease_token and
          operation_prefix_owned?(reservation, subject.prefix)

      _evidence ->
        false
    end)
  end

  defp operation_prefixes_match?(reservation, subject) do
    case Billing.storage_reservation_object_prefixes(reservation) do
      {:ok, %{staging: staging, ready: ready}} ->
        staging == subject.prefix and ready == subject.ready_prefix

      _invalid ->
        false
    end
  end

  defp operation_prefix_owned?(reservation, prefix) do
    case Billing.storage_reservation_object_prefixes(reservation) do
      {:ok, prefixes} -> prefix in Map.values(prefixes)
      _invalid -> false
    end
  end

  defp ready_owner?(subject, evidence) do
    Enum.any?(evidence, fn
      {:snapshot, %ProjectSnapshot{lifecycle_state: "ready", object_prefix: prefix}, _workspace_id} ->
        prefix == subject.prefix

      _evidence ->
        false
    end) or in_flight_ready_owner?(subject, evidence)
  end

  defp in_flight_ready_owner?(subject, evidence) do
    snapshots =
      for {:snapshot,
           %ProjectSnapshot{
             lifecycle_state: "verifying",
             cancel_requested_at: nil,
             object_prefix: prefix
           } = snapshot, _workspace_id} <- evidence,
          prefix == subject.prefix,
          snapshot.project_id == subject.project_id,
          do: snapshot

    reservations =
      for {:reservation,
           %StorageReservation{status: "active", kind: "snapshot_build", storage_started_at: started_at} = reservation} <-
            evidence,
          not is_nil(started_at),
          reservation.cleanup_object_prefix == subject.prefix,
          reservation.project_id_snapshot == subject.project_id,
          do: reservation

    claims =
      for {:claim, %SnapshotObjectPublicationClaim{status: status} = claim} <- evidence,
          status in ["publishing", "published"],
          do: claim

    Enum.any?(snapshots, fn snapshot ->
      Enum.any?(reservations, fn reservation ->
        reservation.project_snapshot_id_snapshot == snapshot.id and
          snapshot.storage_reservation_id == reservation.id and
          Enum.any?(claims, fn claim ->
            claim.object_prefix == subject.prefix and
              claim.storage_reservation_id_snapshot == reservation.id and
              claim.storage_reservation_lease_token == reservation.lease_token and
              snapshot.publication_claim_token == claim.claim_token
          end)
      end)
    end)
  end

  defp active_cleanup?(evidence), do: Enum.any?(evidence, &match?({:cleanup, _id, :active}, &1))
  defp historical_cleanup?(evidence), do: Enum.any?(evidence, &match?({:cleanup, _id, :historical}, &1))

  defp abandoned_temporary?(%{kind: kind}, evidence) when kind in [:staging, :reservation] do
    cleanup? = active_cleanup?(evidence)

    terminal_owner? =
      Enum.any?(evidence, fn
        {:claim, %SnapshotObjectPublicationClaim{status: status}} when status in ["published", "poisoned"] ->
          true

        {:reservation, %StorageReservation{status: status}} when status in ["committed", "released"] ->
          true

        _evidence ->
          false
      end)

    not cleanup? and terminal_owner?
  end

  defp abandoned_temporary?(_subject, _evidence), do: false

  defp commit_snapshot_result(run, candidate, attrs) do
    complete? = Keyword.fetch!(attrs, :complete?)

    progress = [
      findings: Keyword.get(attrs, :findings, []),
      status: "running",
      inspected_object_count: run.inspected_object_count + Keyword.get(attrs, :inspected_objects, 0),
      inspected_bytes: run.inspected_bytes + Keyword.get(attrs, :inspected_bytes, 0)
    ]

    progress =
      if complete? do
        progress ++
          [
            snapshot_after_id: candidate.snapshot.id,
            active_snapshot_id: nil,
            active_snapshot_generation: nil,
            active_snapshot_accounting_generation: nil,
            active_object_index: 0,
            active_inventory_cursor: nil,
            active_inventory_digest: nil,
            active_inventory_last_key: nil,
            active_inventory_object_count: 0,
            active_inventory_bytes: 0,
            inspected_snapshot_count: run.inspected_snapshot_count + 1
          ]
      else
        progress ++
          [
            active_snapshot_id: candidate.snapshot.id,
            active_snapshot_generation: candidate.snapshot.lifecycle_generation,
            active_snapshot_accounting_generation: candidate.snapshot.accounting_generation,
            active_object_index: Keyword.fetch!(attrs, :next_index)
          ]
      end

    commit_run_progress(run, progress, candidate)
  end

  defp commit_run_progress(run, attrs, candidate \\ nil) do
    findings = Keyword.get(attrs, :findings, [])

    fn ->
      run.id
      |> lock_run()
      |> commit_locked_progress(run, attrs, candidate, findings)
    end
    |> Repo.transaction()
    |> normalize_commit_result()
  end

  defp commit_locked_progress(nil, _run, _attrs, _candidate, _findings) do
    Repo.rollback(:snapshot_reconciliation_run_not_found)
  end

  defp commit_locked_progress(%{status: status}, _run, _attrs, _candidate, _findings)
       when status in ["completed", "failed"], do: {:terminal, status}

  defp commit_locked_progress(
         %{cursor_generation: locked_generation},
         %{cursor_generation: expected_generation},
         _attrs,
         _candidate,
         _findings
       )
       when locked_generation != expected_generation, do: {:stale, locked_generation}

  defp commit_locked_progress(locked, _run, attrs, candidate, findings) do
    if candidate_current?(candidate) do
      persist_findings_and_progress(locked, attrs, findings)
    else
      persist_changed_snapshot_failure(locked)
    end
  end

  defp candidate_current?(nil), do: true
  defp candidate_current?(%{snapshot: snapshot}), do: same_ready_snapshot?(snapshot)

  defp persist_findings_and_progress(locked, attrs, findings) do
    new_findings = new_findings(locked.id, findings)

    if locked.finding_count + length(new_findings) > locked.max_findings do
      persist_finding_limit_failure(locked)
    else
      persist_progress(locked, attrs, new_findings)
    end
  end

  defp persist_progress(run, attrs, findings) do
    inserted_count = insert_findings(run.id, findings)
    now = TimeHelpers.now()

    changes =
      attrs
      |> Map.new()
      |> Map.delete(:findings)
      |> Map.put(:cursor_generation, run.cursor_generation + 1)
      |> Map.put(:finding_count, run.finding_count + inserted_count)
      |> Map.put(:started_at, run.started_at || now)

    updated =
      run
      |> ProjectSnapshotReconciliationRun.progress_changeset(changes)
      |> Repo.update!()

    if updated.status == "running", do: persist_continuation!(updated)

    status = if updated.status == "completed", do: :completed, else: :continue
    {:progress, status, updated, inserted_count}
  end

  defp normalize_commit_result({:ok, {:progress, :continue, run, inserted_count}}) do
    emit_page(run, inserted_count)
    {:ok, :continue, run.cursor_generation}
  end

  defp normalize_commit_result({:ok, {:progress, :completed, run, inserted_count}}) do
    emit_page(run, inserted_count)
    emit_finished(run, :completed)
    {:ok, :completed}
  end

  defp normalize_commit_result({:ok, {:progress, :failed, run, _inserted_count}}) do
    emit_finished(run, :failed)
    {:ok, :failed}
  end

  defp normalize_commit_result({:ok, {:continue, generation}}), do: {:ok, :continue, generation}
  defp normalize_commit_result({:ok, {:stale, generation}}), do: {:ok, :stale, generation}
  defp normalize_commit_result({:ok, {:terminal, "completed"}}), do: {:ok, :completed}
  defp normalize_commit_result({:ok, {:terminal, "failed"}}), do: {:ok, :failed}
  defp normalize_commit_result({:error, reason}), do: {:error, reason}

  defp persist_changed_snapshot_failure(run) do
    now = TimeHelpers.now()

    updated =
      run
      |> ProjectSnapshotReconciliationRun.progress_changeset(%{
        status: "failed",
        cursor_generation: run.cursor_generation + 1,
        last_error_code: "snapshot_reconciliation_ready_candidate_changed",
        started_at: run.started_at || now,
        finished_at: now
      })
      |> Repo.update!()

    {:progress, :failed, updated, 0}
  end

  defp stale_advance_result(run_id) do
    case Repo.get(ProjectSnapshotReconciliationRun, run_id) do
      %ProjectSnapshotReconciliationRun{cursor_generation: generation} -> {:ok, :stale, generation}
      nil -> {:error, :snapshot_reconciliation_run_not_found}
    end
  end

  defp normalize_fail_result({:ok, :stale}, run_id), do: stale_advance_result(run_id)
  defp normalize_fail_result(result, _run_id), do: result

  defp persist_continuation!(run) do
    run.id
    |> inspection_job(run.cursor_generation)
    |> Oban.insert!()
  end

  defp persist_finding_limit_failure(run) do
    now = TimeHelpers.now()

    updated =
      run
      |> ProjectSnapshotReconciliationRun.progress_changeset(%{
        status: "failed",
        cursor_generation: run.cursor_generation + 1,
        last_error_code: "snapshot_reconciliation_finding_limit_exceeded",
        started_at: run.started_at || now,
        finished_at: now
      })
      |> Repo.update!()

    {:progress, :failed, updated, 0}
  end

  defp new_findings(_run_id, []), do: []

  defp new_findings(run_id, findings) do
    findings = Enum.uniq_by(findings, & &1.fingerprint)
    fingerprints = Enum.map(findings, & &1.fingerprint)

    existing =
      from(finding in ProjectSnapshotReconciliationFinding,
        where: finding.run_id == ^run_id and finding.fingerprint in ^fingerprints,
        select: finding.fingerprint
      )
      |> Repo.all()
      |> MapSet.new()

    Enum.reject(findings, &MapSet.member?(existing, &1.fingerprint))
  end

  defp insert_findings(_run_id, []), do: 0

  defp insert_findings(run_id, findings) do
    inserted_at = TimeHelpers.now()
    entries = Enum.map(findings, &finding_insert_entry(&1, run_id, inserted_at))

    {inserted_count, _returning} =
      Repo.insert_all(ProjectSnapshotReconciliationFinding, entries,
        on_conflict: :nothing,
        conflict_target: [:run_id, :fingerprint]
      )

    inserted_count
  end

  defp finding_insert_entry(attrs, run_id, inserted_at) do
    changeset =
      ProjectSnapshotReconciliationFinding.create_changeset(
        %ProjectSnapshotReconciliationFinding{},
        Map.put(attrs, :run_id, run_id)
      )

    case Ecto.Changeset.apply_action(changeset, :insert) do
      {:ok, finding} ->
        finding
        |> Map.from_struct()
        |> Map.take(@finding_insert_fields)
        |> Map.put(:inserted_at, inserted_at)

      {:error, invalid_changeset} ->
        Repo.rollback(invalid_changeset)
    end
  end

  defp same_ready_snapshot?(%ProjectSnapshot{format_version: 2} = snapshot) do
    snapshot
    |> same_ready_snapshot_query()
    |> Repo.one()
    |> is_nil()
    |> Kernel.not()
  end

  defp same_ready_snapshot?(%ProjectSnapshot{}), do: false

  defp same_ready_snapshot_query(snapshot) do
    ProjectSnapshot
    |> where([current], current.id == ^snapshot.id)
    |> where([current], current.lifecycle_state == "ready")
    |> where([current], current.lifecycle_generation == ^snapshot.lifecycle_generation)
    |> where([current], current.accounting_generation == ^snapshot.accounting_generation)
    |> where([current], current.manifest_checksum == ^snapshot.manifest_checksum)
    |> where([current], current.manifest_storage_key == ^snapshot.manifest_storage_key)
    |> where([current], current.manifest_size_bytes == ^snapshot.manifest_size_bytes)
    |> where([current], current.object_prefix == ^snapshot.object_prefix)
    |> same_ready_storage_query(snapshot)
    |> select([current], current.id)
    |> lock("FOR SHARE")
  end

  defp same_ready_storage_query(query, %ProjectSnapshot{format_version: 2} = snapshot) do
    query
    |> where([current], current.format_version == 2)
    |> where([current], current.archive_storage_key == ^snapshot.archive_storage_key)
    |> where([current], current.archive_size_bytes == ^snapshot.archive_size_bytes)
    |> where([current], current.archive_checksum == ^snapshot.archive_checksum)
  end

  defp manifest_mismatches(%ProjectSnapshot{format_version: 2} = snapshot, manifest) do
    project = manifest["project"]
    counts = manifest["counts"]
    asset_blob_size = manifest["payload_size_bytes"] - project["size_bytes"]
    total_size = snapshot.archive_size_bytes + snapshot.manifest_size_bytes

    row_mismatches =
      Enum.flat_map(
        [
          {:format_version, snapshot.format_version, 2},
          {:archive_storage_key, snapshot.archive_storage_key,
           SnapshotArchiveStorage.archive_key(snapshot.object_prefix)},
          {:manifest_storage_key, snapshot.manifest_storage_key,
           SnapshotArchiveStorage.manifest_key(snapshot.object_prefix)},
          {:project_size_bytes, snapshot.project_size_bytes, project["size_bytes"]},
          {:project_checksum, snapshot.project_checksum, project["sha256"]},
          {:total_size_bytes, snapshot.total_size_bytes, total_size},
          {:accounted_size_bytes, snapshot.accounted_size_bytes, total_size},
          {:asset_blob_size_bytes, snapshot.asset_blob_size_bytes, asset_blob_size},
          {:object_count, snapshot.object_count, 2},
          {:asset_count, snapshot.asset_count, counts["assets"]},
          {:blob_count, snapshot.blob_count, counts["blobs"]},
          {:accounting_version, snapshot.accounting_version, 1}
        ],
        fn {field, actual, expected} ->
          if actual == expected, do: [], else: [Atom.to_string(field)]
        end
      )

    row_mismatches ++ ownership_mismatches(snapshot)
  end

  defp ownership_mismatches(snapshot) do
    claim = Repo.get(SnapshotObjectPublicationClaim, snapshot.object_prefix)
    reservation = if snapshot.storage_reservation_id, do: Repo.get(StorageReservation, snapshot.storage_reservation_id)
    expected_digest = SnapshotObjectPublicationClaim.inventory_digest(snapshot)
    reservation_lease_token = optional_field(reservation, :lease_token)

    claim_mismatch? =
      not match?(
        %SnapshotObjectPublicationClaim{
          status: "published",
          claim_token: claim_token,
          inventory_digest: ^expected_digest,
          storage_reservation_id_snapshot: reservation_id,
          storage_reservation_lease_token: claim_lease_token
        }
        when claim_token == snapshot.publication_claim_token and reservation_id == snapshot.storage_reservation_id and
               claim_lease_token == reservation_lease_token,
        claim
      )

    reservation_mismatch? =
      not match?(
        %StorageReservation{
          id: reservation_id,
          kind: "snapshot_build",
          status: "committed",
          project_id_snapshot: project_id,
          project_snapshot_id_snapshot: snapshot_id,
          actual_bytes: actual_bytes,
          cleanup_object_prefix: object_prefix,
          accounting_version: accounting_version
        }
        when reservation_id == snapshot.storage_reservation_id and snapshot_id == snapshot.id and
               project_id == snapshot.project_id and actual_bytes == snapshot.accounted_size_bytes and
               object_prefix == snapshot.object_prefix and accounting_version == snapshot.accounting_version,
        reservation
      )

    []
    |> maybe_add_mismatch(claim_mismatch?, "publication_claim")
    |> maybe_add_mismatch(reservation_mismatch?, "storage_reservation")
  end

  defp maybe_add_mismatch(fields, true, field), do: [field | fields]
  defp maybe_add_mismatch(fields, false, _field), do: fields

  defp finding(candidate, category, severity, opts) do
    snapshot = candidate.snapshot
    storage_key = Keyword.get(opts, :storage_key)
    error_code = Keyword.get(opts, :error_code)

    attrs = %{
      category: category,
      severity: severity,
      workspace_id_snapshot: candidate.workspace_id,
      project_id_snapshot: snapshot.project_id,
      project_snapshot_id_snapshot: snapshot.id,
      lifecycle_generation: snapshot.lifecycle_generation,
      accounting_generation: snapshot.accounting_generation,
      object_prefix: snapshot.object_prefix,
      storage_key: storage_key,
      expected_size_bytes: Keyword.get(opts, :expected_size_bytes),
      observed_size_bytes: Keyword.get(opts, :observed_size_bytes),
      error_code: error_code,
      details: Keyword.get(opts, :details, %{})
    }

    Map.put(attrs, :fingerprint, finding_fingerprint(attrs))
  end

  defp provider_finding(object, subject, ownership, category, severity, opts) do
    evidence = subject_evidence(subject, ownership)
    raw_storage_key = object.key
    {storage_key, storage_key_encoding} = provider_storage_key_evidence(raw_storage_key)
    raw_path = if is_nil(storage_key_encoding), do: subject_path(subject)

    details = maybe_put_storage_key_encoding(%{"path" => safe_evidence_string(raw_path, 1_024)}, storage_key_encoding)

    attrs = %{
      category: category,
      severity: severity,
      workspace_id_snapshot: evidence.workspace_id,
      project_id_snapshot: evidence.project_id,
      project_snapshot_id_snapshot: evidence.snapshot_id,
      storage_reservation_id_snapshot: evidence.reservation_id,
      lifecycle_generation: evidence.lifecycle_generation,
      accounting_generation: evidence.accounting_generation,
      reservation_generation: evidence.reservation_generation,
      object_prefix: subject_prefix(subject),
      storage_key: storage_key,
      observed_size_bytes: object.size,
      error_code: Keyword.get(opts, :error_code),
      details: details
    }

    fingerprint_attrs = %{attrs | storage_key: raw_storage_key}
    Map.put(attrs, :fingerprint, finding_fingerprint(fingerprint_attrs))
  end

  defp subject_evidence(subject, ownership) do
    snapshot_evidence = Enum.find(ownership, &match?({:snapshot, _snapshot, _workspace_id}, &1))
    reservation_evidence = Enum.find(ownership, &match?({:reservation, _reservation}, &1))
    project_evidence = Enum.find(ownership, &match?({:project, _project_id, _workspace_id}, &1))

    snapshot = optional_evidence(snapshot_evidence, 1)
    snapshot_workspace_id = optional_evidence(snapshot_evidence, 2)
    reservation = optional_evidence(reservation_evidence, 1)
    project_id = optional_evidence(project_evidence, 1)
    project_workspace_id = optional_evidence(project_evidence, 2)

    %{
      workspace_id:
        first_present([
          snapshot_workspace_id,
          optional_field(reservation, :workspace_id_snapshot),
          project_workspace_id
        ]),
      project_id:
        first_present([
          optional_field(snapshot, :project_id),
          optional_field(reservation, :project_id_snapshot),
          project_id,
          subject_project_id(subject)
        ]),
      snapshot_id:
        first_present([
          optional_field(snapshot, :id),
          optional_field(reservation, :project_snapshot_id_snapshot)
        ]),
      reservation_id: optional_field(reservation, :id),
      lifecycle_generation: optional_field(snapshot, :lifecycle_generation),
      accounting_generation: optional_field(snapshot, :accounting_generation),
      reservation_generation: optional_field(reservation, :generation)
    }
  end

  defp optional_evidence(tuple, index) when is_tuple(tuple), do: elem(tuple, index)
  defp optional_evidence(_tuple, _index), do: nil
  defp subject_project_id(%{project_id: project_id}), do: project_id
  defp subject_project_id(_subject), do: nil

  defp subject_prefix(%{prefix: prefix}), do: prefix
  defp subject_prefix(_subject), do: nil
  defp subject_path(%{path: path}), do: path
  defp subject_path(_subject), do: nil

  defp stale_reservation_finding(reservation, snapshot, reason) do
    attrs = %{
      category: "stale_reservation",
      severity: "warning",
      workspace_id_snapshot: reservation.workspace_id_snapshot,
      project_id_snapshot: reservation.project_id_snapshot,
      project_snapshot_id_snapshot: reservation.project_snapshot_id_snapshot,
      storage_reservation_id_snapshot: reservation.id,
      lifecycle_generation: optional_field(snapshot, :lifecycle_generation),
      accounting_generation: optional_field(snapshot, :accounting_generation),
      reservation_generation: reservation.generation,
      object_prefix: reservation.cleanup_object_prefix,
      expected_size_bytes: reservation.reserved_bytes,
      error_code: "active_storage_reservation_expired",
      details: %{"kind" => reservation.kind, "reason" => reason}
    }

    Map.put(attrs, :fingerprint, finding_fingerprint(attrs))
  end

  defp failed_finalization_finding(claim, reservation, snapshot, reason) do
    project_id =
      case provider_subject(%{key: claim.object_prefix <> "/manifest.json"}) do
        %{project_id: id} -> id
        _subject -> nil
      end

    attrs = %{
      category: "failed_snapshot_finalization",
      severity: "critical",
      workspace_id_snapshot: optional_field(reservation, :workspace_id_snapshot),
      project_id_snapshot:
        first_present([
          optional_field(snapshot, :project_id),
          optional_field(reservation, :project_id_snapshot),
          project_id
        ]),
      project_snapshot_id_snapshot:
        first_present([
          optional_field(snapshot, :id),
          optional_field(reservation, :project_snapshot_id_snapshot)
        ]),
      storage_reservation_id_snapshot: claim.storage_reservation_id_snapshot,
      lifecycle_generation: optional_field(snapshot, :lifecycle_generation),
      accounting_generation: optional_field(snapshot, :accounting_generation),
      reservation_generation: optional_field(reservation, :generation),
      object_prefix: claim.object_prefix,
      error_code: reason,
      details: %{
        "claim_status" => claim.status,
        "reservation_status" => optional_field(reservation, :status),
        "snapshot_state" => optional_field(snapshot, :lifecycle_state)
      }
    }

    Map.put(attrs, :fingerprint, finding_fingerprint(attrs))
  end

  defp optional_field(nil, _field), do: nil
  defp optional_field(source, field), do: Map.fetch!(source, field)

  defp first_present(values), do: Enum.find(values, &(not is_nil(&1)))

  defp terminal_cleanup_finding(intent) do
    attrs = %{
      category: "terminal_cleanup_failure",
      severity: "critical",
      workspace_id_snapshot: intent.workspace_id_snapshot,
      project_id_snapshot: intent.project_id_snapshot,
      project_snapshot_id_snapshot: intent.project_snapshot_id_snapshot,
      cleanup_intent_id_snapshot: intent.id,
      lifecycle_generation: intent.deletion_generation,
      object_prefix: intent.ready_prefix,
      expected_size_bytes: intent.estimated_cleanup_bytes,
      error_code: safe_evidence_string(intent.last_error_code, 255),
      details: %{
        "processing_generation" => intent.processing_generation,
        "reason" => intent.reason,
        "retry_count" => intent.retry_count
      }
    }

    Map.put(attrs, :fingerprint, finding_fingerprint(attrs))
  end

  defp finding_fingerprint(attrs) do
    [
      attrs.category,
      attrs[:workspace_id_snapshot],
      attrs[:project_id_snapshot],
      attrs[:project_snapshot_id_snapshot],
      attrs[:storage_reservation_id_snapshot],
      attrs[:cleanup_intent_id_snapshot],
      attrs[:lifecycle_generation],
      attrs[:accounting_generation],
      attrs[:reservation_generation],
      attrs[:object_prefix],
      attrs[:storage_key],
      attrs[:expected_size_bytes],
      attrs[:observed_size_bytes],
      attrs[:severity],
      attrs[:error_code],
      attrs[:details]
    ]
    |> :erlang.term_to_binary([:deterministic])
    |> then(&:crypto.hash(:sha256, &1))
    |> Base.encode16(case: :lower)
  end

  defp validate_provider_page(page, next_cursor, current_cursor, prefix, page_size)
       when is_list(page) and length(page) <= page_size do
    with true <- Enum.all?(page, &valid_provider_object?(&1, prefix)),
         true <- valid_provider_cursor?(next_cursor, current_cursor, page),
         true <- unique_provider_keys?(page) do
      :ok
    else
      _invalid -> {:error, :invalid_snapshot_reconciliation_provider_page}
    end
  end

  defp validate_provider_page(_page, _next_cursor, _current_cursor, _prefix, _page_size),
    do: {:error, :invalid_snapshot_reconciliation_provider_page}

  defp valid_provider_object?(%{key: key, size: size}, prefix) do
    valid_provider_key?(key, prefix) and is_integer(size) and size >= 0 and size <= @max_bigint
  end

  defp valid_provider_object?(_object, _prefix), do: false

  defp valid_provider_key?(key, prefix) when is_binary(key) do
    String.valid?(key) and byte_size(key) <= 2_048 and String.starts_with?(key, prefix)
  end

  defp valid_provider_key?(_key, _prefix), do: false

  defp valid_provider_cursor?(nil, _current_cursor, _page), do: true

  defp valid_provider_cursor?(next_cursor, current_cursor, page) when is_binary(next_cursor) do
    String.valid?(next_cursor) and next_cursor != "" and byte_size(next_cursor) <= 4_096 and
      not String.contains?(next_cursor, <<0>>) and next_cursor != current_cursor and page != []
  end

  defp valid_provider_cursor?(_next_cursor, _current_cursor, _page), do: false

  defp unique_provider_keys?(page) do
    keys = Enum.map(page, & &1.key)
    MapSet.size(MapSet.new(keys)) == length(keys)
  end

  defp validate_provider_key_order([], _last_key), do: :ok

  defp validate_provider_key_order(objects, last_key) do
    keys = Enum.map(objects, & &1.key)
    forward_from_cursor? = is_nil(last_key) or hd(keys) > last_key

    strictly_increasing? =
      keys
      |> Enum.chunk_every(2, 1, :discard)
      |> Enum.all?(fn [left, right] -> left < right end)

    if forward_from_cursor? and strictly_increasing?,
      do: :ok,
      else: {:error, :invalid_snapshot_reconciliation_provider_page}
  end

  defp provider_last_key([], previous), do: previous
  defp provider_last_key(objects, _previous), do: objects |> List.last() |> Map.fetch!(:key)

  defp validate_runnable(%ProjectSnapshotReconciliationRun{status: status}, _expected)
       when status in ["completed", "failed"], do: {:terminal, status}

  defp validate_runnable(%ProjectSnapshotReconciliationRun{cursor_generation: generation}, expected)
       when generation != expected, do: {:stale, generation}

  defp validate_runnable(%ProjectSnapshotReconciliationRun{}, _expected), do: :ok

  defp validate_namespace(expected) do
    case Storage.namespace_fingerprint() do
      {:ok, ^expected} -> :ok
      {:ok, _different} -> {:error, :snapshot_reconciliation_namespace_changed}
      {:error, reason} -> {:error, {:snapshot_reconciliation_namespace_unavailable, reason}}
    end
  end

  defp validate_run_options(opts) do
    allowed_options = [
      :max_objects_per_step,
      :max_bytes_per_step,
      :max_findings,
      :provider_page_size,
      :max_provider_objects,
      :max_provider_bytes
    ]

    if Keyword.keys(opts) -- allowed_options == [],
      do: :ok,
      else: {:error, :invalid_snapshot_reconciliation_options}
  end

  defp build_run_attrs(namespace_fingerprint, opts) do
    attrs = %{
      provider_namespace_fingerprint: namespace_fingerprint,
      snapshot_high_watermark: snapshot_high_watermark(),
      reservation_high_watermark: reservation_high_watermark(),
      claim_sequence_high_watermark: claim_sequence_high_watermark(),
      cleanup_intent_high_watermark: cleanup_intent_high_watermark(),
      max_objects_per_step: Keyword.get(opts, :max_objects_per_step, @default_max_objects_per_step),
      max_bytes_per_step: Keyword.get(opts, :max_bytes_per_step, @default_max_bytes_per_step),
      max_findings: Keyword.get(opts, :max_findings, @default_max_findings),
      provider_page_size: Keyword.get(opts, :provider_page_size, @default_provider_page_size),
      max_provider_objects: Keyword.get(opts, :max_provider_objects, @default_max_provider_objects),
      max_provider_bytes: Keyword.get(opts, :max_provider_bytes, @default_max_provider_bytes)
    }

    changeset = ProjectSnapshotReconciliationRun.create_changeset(%ProjectSnapshotReconciliationRun{}, attrs)

    if changeset.valid?, do: {:ok, attrs}, else: {:error, changeset}
  end

  defp snapshot_high_watermark do
    Repo.one(from(snapshot in ProjectSnapshot, select: max(snapshot.id))) || 0
  end

  defp reservation_high_watermark do
    Repo.one(from(reservation in StorageReservation, select: max(reservation.id))) || 0
  end

  defp claim_sequence_high_watermark do
    Repo.one(from(claim in SnapshotObjectPublicationClaim, select: max(claim.reconciliation_sequence))) || 0
  end

  defp cleanup_intent_high_watermark do
    Repo.one(from(intent in SnapshotCleanupIntent, select: max(intent.id))) || 0
  end

  defp capture_run_attrs(repo, namespace_fingerprint, opts) do
    with :ok <- lock_reconciliation_boundary(repo) do
      build_run_attrs(namespace_fingerprint, opts)
    end
  end

  # SHARE conflicts with every source-table writer's ROW EXCLUSIVE lock. Taking
  # all four locks before reading the high-watermarks ensures that an insert
  # cannot allocate an earlier identity, remain invisible, and commit behind a
  # cursor that has already advanced past it. NOWAIT keeps this operator-only
  # inspection from joining application lock chains; a busy boundary fails
  # closed and can be retried.
  defp lock_reconciliation_boundary(repo) do
    case repo.query("""
         LOCK TABLE project_snapshots,
                    workspace_storage_reservations,
                    snapshot_object_publication_claims,
                    snapshot_cleanup_intents
         IN SHARE MODE NOWAIT
         """) do
      {:ok, _result} ->
        :ok

      {:error, %Postgrex.Error{postgres: %{code: code}}}
      when code in [:lock_not_available, :deadlock_detected, "55P03", "40P01"] ->
        {:error, :snapshot_reconciliation_boundary_busy}

      {:error, reason} ->
        {:error, {:snapshot_reconciliation_boundary_unavailable, reason}}
    end
  end

  defp existing_active_run(namespace_fingerprint, failed_changeset) do
    fn ->
      case Repo.one(
             from(run in ProjectSnapshotReconciliationRun,
               where:
                 run.provider_namespace_fingerprint == ^namespace_fingerprint and
                   run.status in ["pending", "running"],
               limit: 1,
               lock: "FOR UPDATE"
             )
           ) do
        %ProjectSnapshotReconciliationRun{} = run ->
          recover_stale_inspection_delivery(run)
          persist_continuation!(run)
          run

        nil ->
          Repo.rollback(failed_changeset)
      end
    end
    |> Repo.transaction()
    |> case do
      {:ok, run} -> {:ok, run}
      {:error, %Ecto.Changeset{} = changeset} -> {:error, changeset}
      {:error, reason} -> {:error, reason}
    end
  end

  defp inspection_job(run_id, cursor_generation) do
    InspectProjectSnapshotsWorker.new(%{
      run_id: run_id,
      cursor_generation: cursor_generation,
      contract_version: @contract_version
    })
  end

  defp recover_stale_inspection_delivery(run) do
    now = %{database_clock_now() | microsecond: {0, 6}}
    cutoff = DateTime.add(now, -InspectProjectSnapshotsWorker.recovery_after_seconds(), :second)

    expected_args = %{
      "contract_version" => run.contract_version,
      "cursor_generation" => run.cursor_generation,
      "run_id" => run.id
    }

    stale_jobs =
      from(job in Oban.Job,
        where:
          job.worker == ^@inspection_worker and job.queue == "snapshots_maintenance" and
            job.state == "executing" and job.attempted_at < ^cutoff and
            job.args == ^expected_args
      )

    stale_jobs
    |> where([job], job.attempt < job.max_attempts)
    |> Repo.update_all(set: [state: "available"])

    stale_jobs
    |> where([job], job.attempt >= job.max_attempts)
    |> Repo.update_all(set: [state: "discarded", discarded_at: now])

    :ok
  end

  defp database_clock_now do
    %Postgrex.Result{rows: [[now]]} = Repo.query!("SELECT clock_timestamp()")
    now
  end

  defp lock_run(run_id) do
    Repo.one(
      from(run in ProjectSnapshotReconciliationRun,
        where: run.id == ^run_id,
        lock: "FOR UPDATE"
      )
    )
  end

  defp missing_object_reason?(:enoent), do: true
  defp missing_object_reason?({:http_error, 404, _response}), do: true
  defp missing_object_reason?(_reason), do: false

  defp integrity_reason?({:http_error, status, _response}) when status >= 500, do: false
  defp integrity_reason?({:http_error, status, _response}) when status in [401, 403, 408, 429], do: false
  defp integrity_reason?({:snapshot_reconciliation_provider_list_failed, _reason}), do: false
  defp integrity_reason?({:snapshot_manifest_validation_failed, _reason}), do: true
  defp integrity_reason?({:snapshot_object_size_mismatch, _path, _expected, _actual}), do: true
  defp integrity_reason?({:snapshot_object_content_type_mismatch, _path, _expected, _actual}), do: true
  defp integrity_reason?({:snapshot_object_checksum_mismatch, _expected, _actual}), do: true
  defp integrity_reason?({:invalid_snapshot_object_stat, _path, _stat}), do: true
  defp integrity_reason?({:unsupported_snapshot_object_format, _version}), do: true
  defp integrity_reason?({:unsupported_snapshot_object_type, _type}), do: true
  defp integrity_reason?({:invalid_json, _path}), do: true
  defp integrity_reason?({tag, _value}) when is_atom(tag), do: integrity_tag?(tag)
  defp integrity_reason?({tag, _first, _second}) when is_atom(tag), do: integrity_tag?(tag)
  defp integrity_reason?({tag, _first, _second, _third}) when is_atom(tag), do: integrity_tag?(tag)

  defp integrity_reason?(reason) when is_atom(reason) do
    integrity_tag?(reason) or
      reason in [:asset_blob_inventory_mismatch, :project_descriptor_inventory_mismatch]
  end

  defp integrity_reason?(_reason), do: false

  defp error_code(:enoent), do: "storage_object_missing"
  defp error_code({:http_error, status, _response}) when is_integer(status), do: "storage_http_#{status}"
  defp error_code({:snapshot_inspection_object_failed, %{reason: reason}}), do: error_code(reason)
  defp error_code({:snapshot_manifest_validation_failed, reason}), do: error_code(reason)
  defp error_code({:snapshot_object_size_mismatch, _path, _expected, _actual}), do: "snapshot_object_size_mismatch"

  defp error_code({:snapshot_object_content_type_mismatch, _path, _expected, _actual}),
    do: "snapshot_object_content_type_mismatch"

  defp error_code({:snapshot_object_checksum_mismatch, _expected, _actual}), do: "snapshot_object_checksum_mismatch"

  defp error_code({:invalid_snapshot_object_stat, _path, _stat}), do: "invalid_snapshot_object_stat"
  defp error_code({:unsupported_snapshot_object_format, _version}), do: "unsupported_snapshot_object_format"
  defp error_code({:unsupported_snapshot_object_type, _type}), do: "unsupported_snapshot_object_type"
  defp error_code({:invalid_json, _path}), do: "invalid_snapshot_json"

  defp error_code({:snapshot_reconciliation_provider_list_failed, _reason}),
    do: "snapshot_reconciliation_provider_list_failed"

  defp error_code({tag, _value}) when is_atom(tag), do: error_code(tag)
  defp error_code({tag, _first, _second}) when is_atom(tag), do: error_code(tag)
  defp error_code({tag, _first, _second, _third}) when is_atom(tag), do: error_code(tag)

  defp error_code(reason) when is_atom(reason), do: reason |> Atom.to_string() |> String.slice(0, 255)
  defp error_code(_reason), do: "snapshot_reconciliation_unknown_error"

  defp integrity_tag?(tag) do
    name = Atom.to_string(tag)

    Enum.any?(
      ["invalid_", "unsafe_", "unsupported_", "duplicate_", "missing_", "snapshot_object_"],
      &String.starts_with?(name, &1)
    )
  end

  defp snapshot_namespace_atom("ready"), do: :ready
  defp snapshot_namespace_atom("staging"), do: :staging

  defp parse_project_id(value) do
    case Integer.parse(value) do
      {project_id, ""} when project_id > 0 and project_id <= @max_bigint ->
        {:ok, project_id}

      _invalid ->
        {:error, :invalid_project_id}
    end
  end

  defp safe_evidence_string(nil, _maximum), do: nil

  defp safe_evidence_string(value, maximum) when is_binary(value) do
    if String.valid?(value) and byte_size(value) <= maximum and not String.contains?(value, <<0>>), do: value
  end

  defp safe_evidence_string(_value, _maximum), do: nil

  defp provider_storage_key_evidence(value) do
    case safe_evidence_string(value, 2_048) do
      safe when is_binary(safe) ->
        if ProjectSnapshotReconciliationFinding.safe_storage_key_evidence?(safe),
          do: {safe, nil},
          else: encoded_provider_storage_key(value)

      nil ->
        encoded_provider_storage_key(value)
    end
  end

  defp encoded_provider_storage_key(value), do: {"base64url:" <> Base.url_encode64(value, padding: false), "base64url"}

  defp maybe_put_storage_key_encoding(details, nil), do: details

  defp maybe_put_storage_key_encoding(details, encoding), do: Map.put(details, "storage_key_encoding", encoding)

  defp emit_started(run) do
    :telemetry.execute(
      [:storyarn, :snapshot, :reconciliation, :start],
      %{count: 1},
      %{contract_version: run.contract_version, mode: :dry_run}
    )
  end

  defp emit_page(run, finding_count) do
    :telemetry.execute(
      [:storyarn, :snapshot, :reconciliation, :page],
      %{
        finding_count: finding_count,
        inspected_bytes: run.inspected_bytes,
        inspected_object_count: run.inspected_object_count,
        inspected_snapshot_count: run.inspected_snapshot_count,
        provider_bytes: run.provider_bytes,
        provider_object_count: run.provider_object_count
      },
      %{phase: phase_tag(run.phase), status: status_tag(run.status)}
    )
  end

  defp emit_finished(run, status) do
    :telemetry.execute(
      [:storyarn, :snapshot, :reconciliation, :stop],
      %{
        count: 1,
        finding_count: run.finding_count,
        inspected_bytes: run.inspected_bytes,
        inspected_object_count: run.inspected_object_count,
        inspected_snapshot_count: run.inspected_snapshot_count,
        provider_bytes: run.provider_bytes,
        provider_object_count: run.provider_object_count
      },
      %{
        error_code: run.last_error_code || "none",
        multipart_inventory_state: multipart_inventory_tag(run.multipart_inventory_state),
        status: status
      }
    )

    if status == :failed do
      Logger.error("Snapshot reconciliation inspection failed error_code=#{run.last_error_code}")
    end

    if status == :completed, do: emit_summary(run)

    run
  end

  defp emit_summary(run) do
    findings =
      Repo.all(
        from(finding in ProjectSnapshotReconciliationFinding,
          where: finding.run_id == ^run.id,
          select: %{
            category: finding.category,
            project_snapshot_id_snapshot: finding.project_snapshot_id_snapshot,
            expected_size_bytes: finding.expected_size_bytes,
            observed_size_bytes: finding.observed_size_bytes,
            details: finding.details
          }
        )
      )

    :telemetry.execute(
      [:storyarn, :snapshot, :reconciliation, :summary],
      reconciliation_summary(findings),
      %{
        contract_version: run.contract_version,
        mode: :dry_run,
        multipart_inventory_state: multipart_inventory_tag(run.multipart_inventory_state)
      }
    )
  end

  defp reconciliation_summary(findings) do
    missing_categories = MapSet.new(~w(ready_manifest_missing ready_object_missing))
    corrupt_categories = MapSet.new(~w(ready_manifest_corrupt ready_object_corrupt))

    findings
    |> Enum.reduce(
      %{
        stale_reservation_bytes: 0,
        orphan_object_bytes: 0,
        missing_ready_snapshot_ids: MapSet.new(),
        corrupt_ready_snapshot_ids: MapSet.new(),
        terminal_cleanup_failure_count: 0,
        terminal_cleanup_retry_count: 0
      },
      fn finding, summary ->
        summary
        |> add_summary_bytes(finding)
        |> add_summary_snapshot(finding, missing_categories, :missing_ready_snapshot_ids)
        |> add_summary_snapshot(finding, corrupt_categories, :corrupt_ready_snapshot_ids)
        |> add_cleanup_summary(finding)
      end
    )
    |> then(fn summary ->
      summary
      |> Map.put(:missing_ready_snapshot_count, MapSet.size(summary.missing_ready_snapshot_ids))
      |> Map.put(:corrupt_ready_snapshot_count, MapSet.size(summary.corrupt_ready_snapshot_ids))
      |> Map.drop([:missing_ready_snapshot_ids, :corrupt_ready_snapshot_ids])
    end)
  end

  defp add_summary_bytes(summary, %{category: "stale_reservation", expected_size_bytes: bytes})
       when is_integer(bytes) and bytes >= 0, do: Map.update!(summary, :stale_reservation_bytes, &(&1 + bytes))

  defp add_summary_bytes(summary, %{category: "abandoned_temporary_object", observed_size_bytes: bytes})
       when is_integer(bytes) and bytes >= 0, do: Map.update!(summary, :orphan_object_bytes, &(&1 + bytes))

  defp add_summary_bytes(summary, _finding), do: summary

  defp add_summary_snapshot(summary, finding, categories, accumulator) do
    if MapSet.member?(categories, finding.category) and is_integer(finding.project_snapshot_id_snapshot) do
      Map.update!(summary, accumulator, &MapSet.put(&1, finding.project_snapshot_id_snapshot))
    else
      summary
    end
  end

  defp add_cleanup_summary(summary, %{category: "terminal_cleanup_failure", details: details}) do
    retry_count = if is_map(details) and is_integer(details["retry_count"]), do: details["retry_count"], else: 0

    summary
    |> Map.update!(:terminal_cleanup_failure_count, &(&1 + 1))
    |> Map.update!(:terminal_cleanup_retry_count, &(&1 + max(retry_count, 0)))
  end

  defp add_cleanup_summary(summary, _finding), do: summary

  defp phase_tag("ready_snapshots"), do: :ready_snapshots
  defp phase_tag("stale_reservations"), do: :stale_reservations
  defp phase_tag("publication_claims"), do: :publication_claims
  defp phase_tag("cleanup_intents"), do: :cleanup_intents
  defp phase_tag("provider_objects"), do: :provider_objects
  defp phase_tag("completed"), do: :completed

  defp status_tag("pending"), do: :pending
  defp status_tag("running"), do: :running
  defp status_tag("completed"), do: :completed
  defp status_tag("failed"), do: :failed

  defp multipart_inventory_tag("unsupported"), do: :unsupported
  defp multipart_inventory_tag("complete"), do: :complete
  defp multipart_inventory_tag("incomplete"), do: :incomplete
end
