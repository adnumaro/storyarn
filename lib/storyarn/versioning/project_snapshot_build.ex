defmodule Storyarn.Versioning.ProjectSnapshotBuild do
  @moduledoc """
  Durable request and execution lifecycle for full project snapshots.

  Requests materialize one immutable database capture and reserve its exact
  expected object-set size before an Oban job is inserted in the same
  transaction. Workers consume only that capture, never current project rows.
  """

  import Ecto.Query, warn: false

  alias Storyarn.Accounts.Scope
  alias Storyarn.Assets
  alias Storyarn.Billing
  alias Storyarn.Billing.StorageReservation
  alias Storyarn.Projects
  alias Storyarn.Projects.Project
  alias Storyarn.Repo
  alias Storyarn.Shared.TimeHelpers
  alias Storyarn.Versioning.Builders.ProjectSnapshotBuilder
  alias Storyarn.Versioning.ProjectSnapshot
  alias Storyarn.Versioning.ProjectSnapshotCapture
  alias Storyarn.Versioning.ProjectSnapshotCrud
  alias Storyarn.Versioning.ProjectSnapshotPolicy
  alias Storyarn.Versioning.SnapshotObjectStorage
  alias Storyarn.Versioning.SnapshotStorage
  alias Storyarn.Workers.BuildProjectSnapshotWorker

  require Logger

  @capture_timeout to_timeout(minute: 5)
  @progress_checkpoint_bytes 8 * 1024 * 1024
  @progress_checkpoint_ms 2_000
  @safe_failure_messages %{
    "build_failed" => "The snapshot could not be created. No incomplete snapshot was published.",
    "source_missing" => "A required asset was unavailable. No incomplete snapshot was published.",
    "source_corrupt" => "A required asset failed integrity verification. No incomplete snapshot was published.",
    "storage_limit_reached" => "The workspace no longer has enough storage for this snapshot.",
    "cleanup_unowned" => "The build stopped safely and requires storage reconciliation before it can continue."
  }

  @type request_result ::
          {:ok, ProjectSnapshot.t()}
          | {:error, :snapshot_limit_reached, map()}
          | {:error, :limit_reached, map()}
          | {:error, term()}

  @doc """
  Persists and enqueues a user-created full snapshot.

  `mode` defaults to `"full"`; no capacity or runtime condition may select a
  different mode. The idempotency key must be a UUID generated for the user
  action and is unique within the project.
  """
  @spec request(Scope.t(), Project.t(), map()) :: request_result()
  def request(%Scope{user: %{id: user_id}} = scope, %Project{} = project, attrs)
      when is_integer(user_id) and is_map(attrs) do
    with {:ok, request} <- normalize_request(attrs),
         {:ok, %Project{} = authorized_project, _membership} <-
           Projects.authorize(scope, project.id, :manage_project) do
      run_request_transaction(authorized_project, user_id, request)
    else
      {:error, reason} when reason in [:not_found, :unauthorized] -> {:error, :unauthorized}
      {:error, reason} -> {:error, reason}
    end
  end

  def request(_scope, _project, _attrs), do: {:error, :invalid_snapshot_request}

  @doc false
  @spec perform(pos_integer(), keyword()) ::
          {:ok, ProjectSnapshot.t() | atom()}
          | {:retry, atom()}
          | {:snooze, pos_integer()}
          | {:discard, atom()}
  def perform(snapshot_id, opts) when is_integer(snapshot_id) and snapshot_id > 0 and is_list(opts) do
    job_id = Keyword.get(opts, :job_id)
    attempt = Keyword.get(opts, :attempt, 1)
    max_attempts = Keyword.get(opts, :max_attempts, 1)

    with true <- is_integer(job_id) and job_id > 0,
         true <- is_integer(attempt) and attempt > 0,
         true <- is_integer(max_attempts) and max_attempts >= attempt,
         {:ok, claim} <- claim_build(snapshot_id, job_id, attempt) do
      perform_claim(claim, attempt, max_attempts)
    else
      false -> {:discard, :invalid_snapshot_build_job}
      {:error, :snapshot_build_owned_by_another_job} -> {:snooze, 30}
      {:error, :project_snapshot_not_found} -> settle_orphaned_build(snapshot_id, :project_snapshot_not_found)
      {:error, reason} -> {:discard, safe_error_code(reason)}
    end
  end

  def perform(_snapshot_id, _opts), do: {:discard, :invalid_snapshot_build_job}

  @doc "Authorizes and requests cooperative cancellation without killing an active storage writer."
  @spec cancel(Scope.t(), Project.t(), pos_integer()) ::
          {:ok, ProjectSnapshot.t()} | {:error, term()}
  def cancel(%Scope{} = scope, %Project{} = project, snapshot_id) when is_integer(snapshot_id) and snapshot_id > 0 do
    case Projects.authorize(scope, project.id, :manage_project) do
      {:ok, %Project{} = authorized_project, _membership} ->
        cancel_authorized(authorized_project, snapshot_id)

      {:error, reason} when reason in [:not_found, :unauthorized] ->
        {:error, :unauthorized}

      {:error, reason} ->
        {:error, reason}
    end
  end

  def cancel(_scope, _project, _snapshot_id), do: {:error, :invalid_snapshot_cancel_request}

  @doc false
  def subscribe(project_id) when is_integer(project_id) and project_id > 0 do
    Phoenix.PubSub.subscribe(Storyarn.PubSub, topic(project_id))
  end

  def subscribe(_project_id), do: {:error, :invalid_project_id}

  defp run_request_transaction(project, user_id, request) do
    result =
      Repo.repeatable_read(
        fn ->
          Billing.transact_with_workspace_lock(project.workspace_id, fn _workspace ->
            request_locked(project, user_id, request)
          end)
        end,
        timeout: @capture_timeout
      )

    case result do
      {:ok, {:ok, %ProjectSnapshot{} = snapshot}} ->
        broadcast(snapshot)
        {:ok, snapshot}

      {:ok, {:error, reason}} ->
        normalize_request_error(reason)

      {:error, reason} ->
        normalize_request_error(reason)
    end
  rescue
    exception ->
      Logger.error("Project snapshot request failed safely: #{Exception.message(exception)}")
      {:error, :snapshot_capture_failed}
  end

  defp request_locked(project, user_id, request) do
    case snapshot_by_idempotency(project.id, request.idempotency_key) do
      %ProjectSnapshot{} = snapshot ->
        {:ok, snapshot}

      nil ->
        create_request_locked(project, user_id, request)
    end
  end

  defp create_request_locked(project, user_id, request) do
    with %Project{} <- lock_active_project(project.id, project.workspace_id),
         project_snapshot = ProjectSnapshotBuilder.build_snapshot_in_transaction(project.id),
         assets = Assets.list_assets_for_export(project.id),
         {:ok, prepared} <-
           SnapshotObjectStorage.prepare(project.id, project_snapshot, assets, source_key_mode: :protected_blob),
         {:ok, snapshot} <- insert_pending_snapshot(project, user_id, request, project_snapshot, prepared),
         {:ok, _capture} <- insert_capture(snapshot, prepared),
         {:ok, reservation} <- reserve_build(project, snapshot, prepared.total_size_bytes, 1),
         {:ok, job} <- enqueue_build(snapshot.id),
         {:ok, snapshot} <- bind_request(snapshot, reservation.id, job.id) do
      {:ok, snapshot}
    else
      nil -> Repo.rollback(:project_not_found)
      %Project{} -> Repo.rollback(:project_not_active)
      {:error, reason} -> Repo.rollback(reason)
      {:error, reason, details} -> Repo.rollback({reason, details})
    end
  end

  defp insert_pending_snapshot(project, user_id, request, project_snapshot, prepared) do
    token = SnapshotStorage.unique_key_suffix()
    object_prefix = SnapshotObjectStorage.ready_prefix(project.id, token)
    now = TimeHelpers.now()

    attrs = %{
      project_id: project.id,
      version_number: ProjectSnapshotCrud.next_version_number(project.id),
      title: request.title,
      description: request.description,
      created_by_id: user_id,
      is_auto: false,
      mode: "full",
      object_prefix: object_prefix,
      project_size_bytes: prepared.project_size_bytes,
      project_checksum: prepared.project_checksum,
      manifest_size_bytes: prepared.manifest_size_bytes,
      manifest_checksum: prepared.manifest_checksum,
      total_size_bytes: prepared.total_size_bytes,
      object_count: prepared.object_count,
      asset_count: prepared.asset_count,
      blob_count: prepared.blob_count,
      entity_counts: Map.get(project_snapshot, "entity_counts", %{}),
      idempotency_key: request.idempotency_key,
      capture_boundary: Ecto.UUID.generate(),
      capture_digest: prepared.capture_digest,
      captured_at: now,
      progress_total_bytes: prepared.total_size_bytes,
      state_updated_at: now
    }

    %ProjectSnapshot{}
    |> ProjectSnapshot.pending_object_set_changeset(attrs)
    |> Repo.insert()
  end

  defp insert_capture(snapshot, prepared) do
    attrs = %{
      project_snapshot_id: snapshot.id,
      capture_boundary: snapshot.capture_boundary,
      capture_digest: prepared.capture_digest,
      project_json: prepared.project_json,
      manifest_json: prepared.manifest_json,
      source_keys: prepared.source_keys,
      project_size_bytes: prepared.project_size_bytes,
      manifest_size_bytes: prepared.manifest_size_bytes,
      asset_blob_size_bytes: prepared.asset_blob_size_bytes,
      total_size_bytes: prepared.total_size_bytes,
      object_count: prepared.object_count,
      asset_count: prepared.asset_count,
      blob_count: prepared.blob_count,
      captured_at: snapshot.captured_at
    }

    %ProjectSnapshotCapture{}
    |> ProjectSnapshotCapture.create_changeset(attrs)
    |> Repo.insert()
  end

  defp reserve_build(project, snapshot, bytes, operation_attempt) do
    Billing.reserve_storage(%{
      workspace_id: project.workspace_id,
      project_id: project.id,
      project_snapshot_id: snapshot.id,
      idempotency_key: reservation_key(snapshot.id, operation_attempt),
      kind: "snapshot_build",
      reserved_bytes: bytes
    })
  end

  defp enqueue_build(snapshot_id) do
    %{snapshot_id: snapshot_id}
    |> BuildProjectSnapshotWorker.new()
    |> Oban.insert()
  end

  defp bind_request(snapshot, reservation_id, job_id) do
    snapshot
    |> ProjectSnapshot.build_state_changeset(%{
      storage_reservation_id: reservation_id,
      build_job_id: job_id,
      state_updated_at: TimeHelpers.now()
    })
    |> Repo.update()
  end

  defp claim_build(snapshot_id, job_id, attempt) do
    Repo.transact(fn ->
      case lock_snapshot(snapshot_id) do
        nil ->
          {:error, :project_snapshot_not_found}

        %ProjectSnapshot{lifecycle_state: state} = snapshot when state in ["ready", "failed", "cancelled", "deleting"] ->
          {:ok, {:terminal, snapshot}}

        %ProjectSnapshot{build_job_id: owner_job_id} when owner_job_id != job_id ->
          {:error, :snapshot_build_owned_by_another_job}

        %ProjectSnapshot{lifecycle_state: "pending"} = snapshot ->
          now = TimeHelpers.now()

          snapshot
          |> ProjectSnapshot.build_state_changeset(%{
            lifecycle_state: "building",
            progress_phase: "copying",
            build_attempt: attempt,
            building_started_at: snapshot.building_started_at || now,
            state_updated_at: now
          })
          |> Repo.update()
          |> wrap_claim()

        %ProjectSnapshot{lifecycle_state: state} = snapshot when state in ["building", "verifying"] ->
          snapshot
          |> ProjectSnapshot.build_state_changeset(%{
            build_attempt: max(snapshot.build_attempt, attempt),
            state_updated_at: TimeHelpers.now()
          })
          |> Repo.update()
          |> wrap_claim()
      end
    end)
  end

  defp wrap_claim({:ok, snapshot}), do: {:ok, {:claimed, snapshot}}
  defp wrap_claim({:error, changeset}), do: {:error, changeset}

  defp perform_claim({:terminal, snapshot}, _attempt, _max_attempts), do: {:ok, snapshot}

  defp perform_claim({:claimed, snapshot}, attempt, max_attempts) do
    case load_build_inputs(snapshot.id) do
      {:ok, build} ->
        if build.snapshot.cancel_requested_at do
          settle_cancelled(build.snapshot)
        else
          execute_build(build, attempt, max_attempts)
        end

      {:error, reason} ->
        finish_failure(snapshot.id, reason, attempt, max_attempts)
    end
  end

  defp execute_build(build, attempt, max_attempts) do
    token = object_token(build.snapshot)

    opts = [
      token: token,
      storage_reservation: build.reservation,
      before_stage: &authorize_stage(build.snapshot.id, &1),
      before_publish: &authorize_publication(build.snapshot.id, &1),
      on_progress: copy_progress_callback(build.snapshot.id, build.snapshot.total_size_bytes)
    ]

    with token when is_binary(token) <- token,
         {:ok, staged} <- SnapshotObjectStorage.stage_prepared(build.snapshot.project_id, build.prepared, opts),
         {:ok, _snapshot} <- mark_verifying(build.snapshot.id, staged.total_size_bytes),
         {:ok, stored} <- SnapshotObjectStorage.publish(staged, &authorize_publication(build.snapshot.id, &1)),
         {:ok, snapshot} <- commit_ready(build.snapshot.id, stored) do
      broadcast(snapshot)
      {:ok, snapshot}
    else
      nil -> finish_failure(build.snapshot.id, :invalid_snapshot_object_prefix, attempt, max_attempts)
      {:error, reason} -> finish_failure(build.snapshot.id, reason, attempt, max_attempts)
    end
  end

  defp authorize_stage(snapshot_id, staged) do
    with workspace_id when is_integer(workspace_id) <- snapshot_workspace_id(snapshot_id),
         {:ok, reservation} <-
           Billing.transact_with_workspace_lock(workspace_id, fn _workspace ->
             authorize_stage_locked(snapshot_id, staged)
           end) do
      {:ok, reservation}
    else
      nil -> {:error, :project_snapshot_not_found}
      {:error, reason} -> {:error, reason}
    end
  end

  defp authorize_stage_locked(snapshot_id, staged) do
    snapshot = lock_snapshot(snapshot_id)
    reservation = lock_reservation(staged.storage_reservation_id)

    with %ProjectSnapshot{cancel_requested_at: nil, storage_reservation_id: reservation_id} <- snapshot,
         %StorageReservation{id: ^reservation_id, status: "active"} <- reservation,
         {:ok, _snapshot} <-
           snapshot
           |> ProjectSnapshot.build_state_changeset(%{
             publication_claim_token: staged.publication_claim_token,
             state_updated_at: TimeHelpers.now()
           })
           |> Repo.update(),
         {:ok, started} <-
           Billing.mark_storage_reservation_started(
             reservation.id,
             reservation.lease_token,
             reservation.generation,
             staged.cleanup
           ) do
      {:ok, started}
    else
      %ProjectSnapshot{} -> {:error, :snapshot_build_cancelled}
      nil -> {:error, :snapshot_build_state_missing}
      {:error, reason} -> {:error, reason}
      _invalid -> {:error, :snapshot_build_state_conflict}
    end
  end

  defp mark_verifying(snapshot_id, progress_bytes) do
    update_build_state(snapshot_id, fn snapshot ->
      now = TimeHelpers.now()
      progress_phase = if snapshot.progress_phase == "finalizing", do: "finalizing", else: "verifying"

      ProjectSnapshot.build_state_changeset(snapshot, %{
        lifecycle_state: "verifying",
        progress_phase: progress_phase,
        progress_bytes: progress_bytes,
        verifying_started_at: snapshot.verifying_started_at || now,
        state_updated_at: now
      })
    end)
  end

  defp copy_progress_callback(snapshot_id, total_bytes) do
    checkpoint = :atomics.new(2, signed: true)
    :atomics.put(checkpoint, 1, 0)
    :atomics.put(checkpoint, 2, System.monotonic_time(:millisecond))

    fn completed_bytes ->
      last_bytes = :atomics.get(checkpoint, 1)
      last_at = :atomics.get(checkpoint, 2)
      now = System.monotonic_time(:millisecond)

      if progress_checkpoint_due?(completed_bytes, total_bytes, last_bytes, last_at, now) do
        persist_progress_checkpoint(snapshot_id, completed_bytes, checkpoint, now)
      else
        :ok
      end
    end
  end

  defp progress_checkpoint_due?(completed_bytes, total_bytes, last_bytes, last_at, now) do
    completed_bytes >= total_bytes or completed_bytes - last_bytes >= @progress_checkpoint_bytes or
      now - last_at >= @progress_checkpoint_ms
  end

  defp persist_progress_checkpoint(snapshot_id, completed_bytes, checkpoint, now) do
    with :ok <- persist_copy_progress(snapshot_id, completed_bytes) do
      :atomics.put(checkpoint, 1, completed_bytes)
      :atomics.put(checkpoint, 2, now)
      :ok
    end
  end

  defp persist_copy_progress(snapshot_id, completed_bytes) do
    result =
      Repo.transact(fn ->
        case lock_snapshot(snapshot_id) do
          %ProjectSnapshot{cancel_requested_at: %DateTime{}} ->
            {:error, :snapshot_build_cancelled}

          %ProjectSnapshot{lifecycle_state: "building"} = snapshot ->
            snapshot
            |> ProjectSnapshot.build_state_changeset(%{
              progress_phase: "copying",
              progress_bytes: max(snapshot.progress_bytes, completed_bytes),
              state_updated_at: TimeHelpers.now()
            })
            |> Repo.update()

          %ProjectSnapshot{} ->
            {:error, :snapshot_build_state_conflict}

          nil ->
            {:error, :project_snapshot_not_found}
        end
      end)

    case result do
      {:ok, %ProjectSnapshot{} = snapshot} ->
        broadcast(snapshot)
        :ok

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp authorize_publication(snapshot_id, staged) do
    with workspace_id when is_integer(workspace_id) <- snapshot_workspace_id(snapshot_id),
         {:ok, reservation} <-
           Billing.transact_with_workspace_lock(workspace_id, fn _workspace ->
             authorize_publication_locked(snapshot_id, staged)
           end) do
      {:ok, reservation}
    else
      nil -> {:error, :project_snapshot_not_found}
      {:error, reason} -> {:error, reason}
    end
  end

  defp authorize_publication_locked(snapshot_id, staged) do
    snapshot = lock_snapshot(snapshot_id)
    reservation = snapshot && lock_reservation(snapshot.storage_reservation_id)

    with %ProjectSnapshot{cancel_requested_at: nil} <- snapshot,
         %StorageReservation{status: "active"} <- reservation,
         {:ok, extended} <-
           Billing.extend_storage_reservation(
             reservation.id,
             reservation.lease_token,
             reservation.generation,
             staged.total_size_bytes
           ),
         {:ok, _snapshot} <-
           snapshot
           |> ProjectSnapshot.build_state_changeset(%{
             lifecycle_state: "verifying",
             progress_phase: "finalizing",
             progress_bytes: staged.total_size_bytes,
             verifying_started_at: snapshot.verifying_started_at || TimeHelpers.now(),
             state_updated_at: TimeHelpers.now()
           })
           |> Repo.update() do
      {:ok, extended}
    else
      %ProjectSnapshot{} -> {:error, :snapshot_build_cancelled}
      nil -> {:error, :snapshot_build_state_missing}
      {:error, reason} -> {:error, reason}
      _invalid -> {:error, :snapshot_build_state_conflict}
    end
  end

  defp commit_ready(snapshot_id, stored) do
    snapshot = Repo.get(ProjectSnapshot, snapshot_id)
    reservation = snapshot && Repo.get(StorageReservation, snapshot.storage_reservation_id)
    now = TimeHelpers.now()

    with %ProjectSnapshot{} <- snapshot,
         %StorageReservation{} <- reservation,
         {:ok, %{result: %ProjectSnapshot{} = ready_snapshot}} <-
           Billing.commit_storage_reservation(
             reservation.id,
             reservation.lease_token,
             reservation.generation,
             stored.total_size_bytes,
             fn _reservation ->
               ProjectSnapshotCrud.finalize_object_set(
                 snapshot.id,
                 0,
                 Map.merge(stored, %{
                   progress_phase: "complete",
                   progress_bytes: stored.total_size_bytes,
                   progress_total_bytes: stored.total_size_bytes,
                   verifying_started_at: snapshot.verifying_started_at || now,
                   ready_at: now,
                   state_updated_at: now
                 })
               )
             end
           ) do
      {:ok, ready_snapshot}
    else
      nil -> {:error, :snapshot_build_state_missing}
      {:error, reason} -> {:error, reason}
    end
  end

  defp finish_failure(snapshot_id, reason, attempt, max_attempts) do
    snapshot = Repo.get(ProjectSnapshot, snapshot_id)

    cond do
      is_nil(snapshot) ->
        settle_orphaned_build(snapshot_id, reason)

      snapshot.lifecycle_state == "ready" ->
        {:ok, snapshot}

      cancelled_reason?(reason) or not is_nil(snapshot.cancel_requested_at) ->
        settle_cancelled(snapshot, reason)

      true ->
        settle_failed_build(snapshot, reason, attempt, max_attempts)
    end
  end

  defp settle_failed_build(snapshot, reason, attempt, max_attempts) do
    cleanup_scope = cleanup_scope(reason)

    snapshot
    |> settle_active_reservation(reason, cleanup_scope)
    |> handle_failed_settlement(snapshot, reason, attempt, max_attempts)
  end

  defp handle_failed_settlement({:ok, :released}, snapshot, reason, attempt, max_attempts) do
    if attempt < max_attempts and retryable?(reason),
      do: retry_failed_snapshot(snapshot, reason, attempt + 1),
      else: fail_snapshot(snapshot.id, reason)
  end

  defp handle_failed_settlement({:ok, :committed}, _snapshot, reason, attempt, max_attempts) when attempt < max_attempts,
    do: {:retry, safe_error_code(reason)}

  defp handle_failed_settlement({:ok, :active_unowned}, snapshot, _reason, _attempt, _max_attempts),
    do: fail_snapshot(snapshot.id, :cleanup_unowned)

  defp handle_failed_settlement({:ok, :committed}, snapshot, _reason, _attempt, _max_attempts),
    do: fail_snapshot(snapshot.id, :cleanup_unowned)

  defp handle_failed_settlement({:error, settlement_reason}, snapshot, _reason, _attempt, _max_attempts),
    do: fail_snapshot(snapshot.id, settlement_reason)

  defp retry_failed_snapshot(snapshot, reason, operation_attempt) do
    case allocate_retry(snapshot, operation_attempt) do
      {:ok, retried} ->
        broadcast(retried)
        {:retry, safe_error_code(reason)}

      {:error, retry_reason} ->
        fail_snapshot(snapshot.id, retry_reason)
    end
  end

  defp settle_active_reservation(snapshot, reason, cleanup_scope) do
    case Repo.get(StorageReservation, snapshot.storage_reservation_id) do
      %StorageReservation{status: "released"} ->
        {:ok, :released}

      %StorageReservation{status: "committed"} ->
        {:ok, :committed}

      %StorageReservation{status: "active", storage_started_at: nil} = reservation ->
        release_reservation(reservation, reason, :storage_not_started)

      %StorageReservation{status: "active"} = reservation when is_map(cleanup_scope) ->
        release_reservation(reservation, reason, {:owned, cleanup_scope})

      %StorageReservation{status: "active"} ->
        {:ok, :active_unowned}

      nil ->
        {:error, :storage_reservation_not_found}
    end
  end

  defp settle_orphaned_build(snapshot_id, reason) do
    reservation =
      Repo.one(
        from(reservation in StorageReservation,
          where:
            reservation.project_snapshot_id_snapshot == ^snapshot_id and
              reservation.kind == "snapshot_build" and reservation.status == "active",
          limit: 1
        )
      )

    settle_orphaned_reservation(reservation, reason)
  end

  defp settle_orphaned_reservation(%StorageReservation{storage_started_at: nil} = reservation, reason) do
    release_orphaned_reservation(reservation, reason, :storage_not_started)
  end

  defp settle_orphaned_reservation(%StorageReservation{} = reservation, reason) do
    case cleanup_scope(reason) do
      cleanup_scope when is_map(cleanup_scope) ->
        release_orphaned_reservation(reservation, reason, {:owned, cleanup_scope})

      nil ->
        {:discard, :cleanup_unowned}
    end
  end

  defp settle_orphaned_reservation(nil, _reason), do: {:discard, :project_snapshot_not_found}

  defp release_orphaned_reservation(reservation, reason, cleanup_authority) do
    case release_reservation(reservation, reason, cleanup_authority) do
      {:ok, :released} -> {:discard, :project_snapshot_not_found}
      {:error, release_reason} -> {:discard, safe_error_code(release_reason)}
    end
  end

  defp release_reservation(reservation, reason, cleanup_authority) do
    attrs = release_attrs(reservation, reason, cleanup_authority)

    case Billing.release_storage_reservation(
           reservation.id,
           reservation.lease_token,
           reservation.generation,
           attrs
         ) do
      {:ok, _released} -> {:ok, :released}
      {:error, release_reason} -> {:error, release_reason}
    end
  end

  defp allocate_retry(snapshot, operation_attempt) do
    case snapshot_workspace_id(snapshot.id) do
      workspace_id when is_integer(workspace_id) ->
        Billing.transact_with_workspace_lock(workspace_id, fn _workspace ->
          allocate_retry_locked(snapshot, operation_attempt, workspace_id)
        end)

      _missing ->
        {:error, :project_snapshot_not_found}
    end
  end

  defp allocate_retry_locked(snapshot, operation_attempt, workspace_id) do
    retried = lock_snapshot(snapshot.id)
    token = SnapshotStorage.unique_key_suffix()
    object_prefix = SnapshotObjectStorage.ready_prefix(snapshot.project_id, token)
    now = TimeHelpers.now()

    with %ProjectSnapshot{lifecycle_state: state} when state in ["building", "verifying"] <- retried,
         {:ok, retried} <- reset_snapshot_for_retry(retried, object_prefix, now),
         {:ok, reservation} <- reserve_retry_storage(retried, workspace_id, operation_attempt),
         {:ok, retried} <- attach_retry_reservation(retried, reservation) do
      {:ok, retried}
    else
      nil -> {:error, :project_snapshot_not_found}
      %ProjectSnapshot{} -> {:error, :invalid_snapshot_retry_state}
      {:error, reason} -> {:error, reason}
      {:error, reason, details} -> {:error, {reason, details}}
    end
  end

  defp reset_snapshot_for_retry(snapshot, object_prefix, now) do
    snapshot
    |> ProjectSnapshot.build_state_changeset(%{
      object_prefix: object_prefix,
      project_storage_key: object_prefix <> "/project.json",
      manifest_storage_key: object_prefix <> "/manifest.json",
      storage_reservation_id: nil,
      publication_claim_token: nil,
      lifecycle_state: "pending",
      integrity_state: "unknown",
      progress_phase: "retrying",
      progress_bytes: 0,
      failure_code: nil,
      failure_message: nil,
      failed_at: nil,
      state_updated_at: now
    })
    |> Repo.update()
  end

  defp reserve_retry_storage(snapshot, workspace_id, operation_attempt) do
    Billing.reserve_storage(%{
      workspace_id: workspace_id,
      project_id: snapshot.project_id,
      project_snapshot_id: snapshot.id,
      idempotency_key: reservation_key(snapshot.id, operation_attempt),
      kind: "snapshot_build",
      reserved_bytes: snapshot.total_size_bytes
    })
  end

  defp attach_retry_reservation(snapshot, reservation) do
    snapshot
    |> ProjectSnapshot.build_state_changeset(%{
      storage_reservation_id: reservation.id,
      state_updated_at: TimeHelpers.now()
    })
    |> Repo.update()
  end

  defp fail_snapshot(snapshot_id, reason) do
    code = safe_error_code(reason)
    now = TimeHelpers.now()

    case update_build_state(snapshot_id, fn snapshot ->
           ProjectSnapshot.build_state_changeset(snapshot, %{
             lifecycle_state: "failed",
             integrity_state: failure_integrity(reason),
             progress_phase: "failed",
             failure_code: Atom.to_string(code),
             failure_message: failure_message(code),
             failed_at: now,
             state_updated_at: now
           })
         end) do
      {:ok, failed} ->
        broadcast(failed)
        {:discard, code}

      {:error, _reason} ->
        {:discard, :snapshot_failure_state_not_persisted}
    end
  end

  defp settle_cancelled(snapshot, reason \\ :snapshot_build_cancelled) do
    cleanup_scope = cleanup_scope(reason)

    case settle_active_reservation(snapshot, :snapshot_build_cancelled, cleanup_scope) do
      {:ok, :released} -> mark_cancelled(snapshot.id)
      {:ok, :committed} -> {:retry, :snapshot_build_cancelled_after_publish}
      {:ok, :active_unowned} -> fail_snapshot(snapshot.id, :cleanup_unowned)
      {:error, settlement_reason} -> fail_snapshot(snapshot.id, settlement_reason)
    end
  end

  defp mark_cancelled(snapshot_id) do
    now = TimeHelpers.now()

    case update_build_state(snapshot_id, fn snapshot ->
           ProjectSnapshot.build_state_changeset(snapshot, %{
             lifecycle_state: "cancelled",
             integrity_state: "unknown",
             progress_phase: "cancelled",
             failure_code: nil,
             failure_message: nil,
             failed_at: nil,
             cancelled_at: now,
             state_updated_at: now
           })
         end) do
      {:ok, cancelled} ->
        broadcast(cancelled)
        {:ok, cancelled}

      {:error, reason} ->
        {:discard, safe_error_code(reason)}
    end
  end

  defp cancel_locked(project_id, snapshot_id) do
    case lock_snapshot(project_id, snapshot_id) do
      nil ->
        {:error, :project_snapshot_not_found}

      %ProjectSnapshot{lifecycle_state: state} = snapshot
      when state in ["ready", "failed", "cancelled", "deleting"] ->
        {:ok, snapshot}

      %ProjectSnapshot{progress_phase: "finalizing"} ->
        {:error, :snapshot_finalization_in_progress}

      %ProjectSnapshot{lifecycle_state: "pending"} = snapshot ->
        cancel_pending_snapshot(snapshot)

      %ProjectSnapshot{} = snapshot ->
        {:ok, request_cancel(snapshot)}
    end
  end

  defp cancel_pending_snapshot(snapshot) do
    snapshot = request_cancel(snapshot)

    case Repo.get(StorageReservation, snapshot.storage_reservation_id) do
      %StorageReservation{status: "active", storage_started_at: nil} = reservation ->
        release_and_cancel_pending_snapshot(reservation, snapshot)

      _reservation ->
        {:ok, snapshot}
    end
  end

  defp release_and_cancel_pending_snapshot(reservation, snapshot) do
    with {:ok, :released} <-
           release_reservation(
             reservation,
             :snapshot_build_cancelled,
             :storage_not_started
           ) do
      mark_cancelled_in_transaction(snapshot)
    end
  end

  defp cancel_authorized(project, snapshot_id) do
    result =
      case snapshot_workspace_id(project.id, snapshot_id) do
        workspace_id when is_integer(workspace_id) ->
          Billing.transact_with_workspace_lock(workspace_id, fn _workspace ->
            cancel_locked(project.id, snapshot_id)
          end)

        nil ->
          {:error, :project_snapshot_not_found}
      end

    case result do
      {:ok, %ProjectSnapshot{} = snapshot} = success ->
        broadcast(snapshot)
        success

      other ->
        other
    end
  end

  defp request_cancel(snapshot) do
    now = TimeHelpers.now()

    snapshot
    |> ProjectSnapshot.build_state_changeset(%{
      cancel_requested_at: snapshot.cancel_requested_at || now,
      state_updated_at: now
    })
    |> Repo.update!()
  end

  defp mark_cancelled_in_transaction(snapshot) do
    now = TimeHelpers.now()

    snapshot
    |> ProjectSnapshot.build_state_changeset(%{
      lifecycle_state: "cancelled",
      integrity_state: "unknown",
      progress_phase: "cancelled",
      cancelled_at: now,
      state_updated_at: now
    })
    |> Repo.update()
  end

  defp load_build_inputs(snapshot_id) do
    snapshot =
      case Repo.get(ProjectSnapshot, snapshot_id) do
        %ProjectSnapshot{} = snapshot -> Repo.preload(snapshot, [:capture, :storage_reservation, :project])
        nil -> nil
      end

    with %ProjectSnapshot{capture: %ProjectSnapshotCapture{} = capture} <- snapshot,
         %StorageReservation{} = reservation <- snapshot.storage_reservation,
         true <- capture.capture_boundary == snapshot.capture_boundary,
         true <- capture.capture_digest == snapshot.capture_digest do
      {:ok,
       %{
         snapshot: snapshot,
         reservation: reservation,
         prepared: %{
           capture_digest: capture.capture_digest,
           project_json: capture.project_json,
           manifest_json: capture.manifest_json,
           source_keys: capture.source_keys,
           project_size_bytes: capture.project_size_bytes,
           project_checksum: snapshot.project_checksum,
           manifest_size_bytes: capture.manifest_size_bytes,
           manifest_checksum: snapshot.manifest_checksum,
           total_size_bytes: capture.total_size_bytes,
           asset_blob_size_bytes: capture.asset_blob_size_bytes,
           object_count: capture.object_count,
           asset_count: capture.asset_count,
           blob_count: capture.blob_count
         }
       }}
    else
      false -> {:error, :snapshot_capture_identity_mismatch}
      nil -> {:error, :snapshot_capture_missing}
      _invalid -> {:error, :snapshot_build_input_invalid}
    end
  end

  defp update_build_state(snapshot_id, changeset_fun) do
    Repo.transact(fn ->
      case lock_snapshot(snapshot_id) do
        %ProjectSnapshot{} = snapshot -> snapshot |> changeset_fun.() |> Repo.update()
        nil -> {:error, :project_snapshot_not_found}
      end
    end)
  end

  defp lock_active_project(project_id, workspace_id) do
    Repo.one(
      from(project in Project,
        where:
          project.id == ^project_id and project.workspace_id == ^workspace_id and
            is_nil(project.deleted_at),
        lock: "FOR UPDATE"
      )
    )
  end

  defp lock_snapshot(snapshot_id) do
    Repo.one(from(snapshot in ProjectSnapshot, where: snapshot.id == ^snapshot_id, lock: "FOR UPDATE"))
  end

  defp lock_snapshot(project_id, snapshot_id) do
    Repo.one(
      from(snapshot in ProjectSnapshot,
        where: snapshot.id == ^snapshot_id and snapshot.project_id == ^project_id,
        lock: "FOR UPDATE"
      )
    )
  end

  defp lock_reservation(reservation_id) when is_integer(reservation_id) do
    Repo.one(from(reservation in StorageReservation, where: reservation.id == ^reservation_id, lock: "FOR UPDATE"))
  end

  defp lock_reservation(_reservation_id), do: nil

  defp snapshot_by_idempotency(project_id, idempotency_key) do
    Repo.one(
      from(snapshot in ProjectSnapshot,
        where: snapshot.project_id == ^project_id and snapshot.idempotency_key == ^idempotency_key,
        preload: [:created_by]
      )
    )
  end

  defp snapshot_workspace_id(snapshot_id) do
    Repo.one(
      from(snapshot in ProjectSnapshot,
        join: project in Project,
        on: project.id == snapshot.project_id,
        where: snapshot.id == ^snapshot_id,
        select: project.workspace_id
      )
    )
  end

  defp snapshot_workspace_id(project_id, snapshot_id) do
    Repo.one(
      from(snapshot in ProjectSnapshot,
        join: project in Project,
        on: project.id == snapshot.project_id,
        where: snapshot.id == ^snapshot_id and snapshot.project_id == ^project_id,
        select: project.workspace_id
      )
    )
  end

  defp object_token(%ProjectSnapshot{project_id: project_id, object_prefix: object_prefix}) do
    expected_prefix = "projects/#{project_id}/snapshots/object-sets/v1/ready/"

    if is_binary(object_prefix) and String.starts_with?(object_prefix, expected_prefix) do
      String.replace_prefix(object_prefix, expected_prefix, "")
    end
  end

  defp cleanup_scope(reason), do: cleanup_scope(reason, 0)

  defp cleanup_scope(_reason, depth) when depth > 12, do: nil

  defp cleanup_scope(%{cleanup_request_id: id, storage_keys: keys} = scope, _depth)
       when is_integer(id) and id > 0 and is_list(keys), do: scope

  defp cleanup_scope(%{"cleanup_request_id" => id, "storage_keys" => keys} = scope, _depth)
       when is_integer(id) and id > 0 and is_list(keys), do: scope

  defp cleanup_scope(map, depth) when is_map(map) do
    Enum.find_value(map, fn {_key, value} -> cleanup_scope(value, depth + 1) end)
  end

  defp cleanup_scope(tuple, depth) when is_tuple(tuple) do
    tuple
    |> Tuple.to_list()
    |> cleanup_scope(depth + 1)
  end

  defp cleanup_scope(list, depth) when is_list(list) do
    Enum.find_value(list, &cleanup_scope(&1, depth + 1))
  end

  defp cleanup_scope(_reason, _depth), do: nil

  defp cancelled_reason?(reason), do: contains_reason?(reason, :snapshot_build_cancelled)

  defp retryable?(reason) do
    not Enum.any?(
      [
        :limit_reached,
        :snapshot_limit_reached,
        :snapshot_build_cancelled,
        :prepared_snapshot_capture_mismatch,
        :prepared_snapshot_source_inventory_mismatch,
        :missing_snapshot_blob_source,
        :snapshot_object_checksum_mismatch,
        :snapshot_object_size_mismatch,
        :snapshot_object_content_type_mismatch
      ],
      &contains_reason?(reason, &1)
    )
  end

  defp contains_reason?(reason, target) when reason == target, do: true

  defp contains_reason?(map, target) when is_map(map) do
    Enum.any?(map, fn {key, value} -> contains_reason?(key, target) or contains_reason?(value, target) end)
  end

  defp contains_reason?(tuple, target) when is_tuple(tuple) do
    tuple |> Tuple.to_list() |> Enum.any?(&contains_reason?(&1, target))
  end

  defp contains_reason?(list, target) when is_list(list), do: Enum.any?(list, &contains_reason?(&1, target))

  defp contains_reason?(_reason, _target), do: false

  defp failure_integrity(reason) do
    cond do
      contains_reason?(reason, :missing_snapshot_blob_source) or contains_reason?(reason, :enoent) -> "missing"
      contains_reason?(reason, :snapshot_object_checksum_mismatch) -> "corrupt"
      true -> "incomplete"
    end
  end

  defp safe_error_code(reason) do
    cond do
      reason == :cleanup_unowned ->
        :cleanup_unowned

      contains_reason?(reason, :limit_reached) ->
        :storage_limit_reached

      contains_reason?(reason, :missing_snapshot_blob_source) or contains_reason?(reason, :enoent) ->
        :source_missing

      contains_reason?(reason, :snapshot_object_checksum_mismatch) or
        contains_reason?(reason, :snapshot_object_size_mismatch) or
          contains_reason?(reason, :snapshot_object_content_type_mismatch) ->
        :source_corrupt

      true ->
        :build_failed
    end
  end

  defp failure_message(code), do: Map.fetch!(@safe_failure_messages, Atom.to_string(code))

  defp normalize_request(attrs) do
    mode = value(attrs, :mode) || "full"
    idempotency_key = value(attrs, :idempotency_key)

    with {:ok, %{mode: "full"}} <- ProjectSnapshotPolicy.policy(:user),
         "full" <- mode,
         {:ok, idempotency_key} <- Ecto.UUID.cast(idempotency_key) do
      {:ok,
       %{
         mode: "full",
         idempotency_key: idempotency_key,
         title: blank_to_nil(value(attrs, :title)),
         description: blank_to_nil(value(attrs, :description))
       }}
    else
      _invalid -> {:error, :invalid_snapshot_request}
    end
  end

  defp normalize_request_error({:limit_reached, details}), do: {:error, :limit_reached, details}
  defp normalize_request_error({:snapshot_limit_reached, details}), do: {:error, :snapshot_limit_reached, details}
  defp normalize_request_error(reason), do: {:error, reason}

  defp value(attrs, key), do: Map.get(attrs, key, Map.get(attrs, Atom.to_string(key)))

  defp blank_to_nil(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp blank_to_nil(_value), do: nil

  defp reservation_key(snapshot_id, attempt), do: "snapshot-build/#{snapshot_id}/#{attempt}"

  defp release_attrs(reservation, reason, :storage_not_started) do
    %{
      reason: Atom.to_string(safe_error_code(reason)),
      cleanup_status: "not_required",
      cleanup_proof: %{
        type: "storage_not_started",
        storage_namespace: reservation.storage_namespace
      }
    }
  end

  defp release_attrs(_reservation, reason, {:owned, cleanup_scope}) do
    %{
      reason: Atom.to_string(safe_error_code(reason)),
      cleanup_status: "owned",
      cleanup_request_id: value(cleanup_scope, :cleanup_request_id),
      cleanup_scope: cleanup_scope
    }
  end

  defp broadcast(%ProjectSnapshot{} = snapshot) do
    Phoenix.PubSub.broadcast(Storyarn.PubSub, topic(snapshot.project_id), {:project_snapshot_updated, snapshot.id})
    :ok
  end

  defp topic(project_id), do: "project_snapshots:#{project_id}"
end
