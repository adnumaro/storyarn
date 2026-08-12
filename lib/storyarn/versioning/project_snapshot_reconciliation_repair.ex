defmodule Storyarn.Versioning.ProjectSnapshotReconciliationRepair do
  @moduledoc """
  Explicit, generation-fenced repairs for immutable snapshot findings.

  A finding is never mutation authority by itself. Every action reloads the
  current database and provider facts, uses the common workspace lock before a
  database mutation or cleanup handoff, and records one immutable outcome.
  """

  import Ecto.Query

  alias Storyarn.Assets.Storage
  alias Storyarn.Assets.StorageCleanupRequest
  alias Storyarn.Assets.StorageKeyLock
  alias Storyarn.Billing
  alias Storyarn.Billing.StorageReservation
  alias Storyarn.Projects.Project
  alias Storyarn.Repo
  alias Storyarn.Shared.TimeHelpers
  alias Storyarn.Versioning.ProjectSnapshot
  alias Storyarn.Versioning.ProjectSnapshotLifecycle
  alias Storyarn.Versioning.ProjectSnapshotReconciliationFinding
  alias Storyarn.Versioning.ProjectSnapshotReconciliationRepairAction
  alias Storyarn.Versioning.ProjectSnapshotReconciliationRun
  alias Storyarn.Versioning.SnapshotArchiveStorage
  alias Storyarn.Versioning.SnapshotCleanupIntent
  alias Storyarn.Workers.RepairProjectSnapshotFindingWorker

  @contract_version 1
  @default_limit 50
  @max_limit 100
  @repair_terminal_statuses ~w(repaired resolved manual failed)
  @repair_worker "Storyarn.Workers.RepairProjectSnapshotFindingWorker"
  @repair_queue "snapshots_maintenance"
  @active_repair_job_states ~w(available scheduled executing retryable)
  @recoverable_terminal_job_states ~w(discarded cancelled)
  @recoverable_repair_job_states @active_repair_job_states ++ @recoverable_terminal_job_states
  @default_recovery_limit 50
  @max_recovery_limit 100

  @type plan_result :: %{
          actions: [ProjectSnapshotReconciliationRepairAction.t()],
          complete?: boolean(),
          next_after_id: non_neg_integer()
        }

  @doc "Persists and enqueues one bounded page of repair actions from a completed dry-run."
  @spec plan(pos_integer(), keyword()) :: {:ok, plan_result()} | {:error, term()}
  def plan(run_id, opts \\ [])

  def plan(run_id, opts) when is_integer(run_id) and run_id > 0 and is_list(opts) do
    with {:ok, after_id, limit} <- normalize_plan_options(opts),
         %ProjectSnapshotReconciliationRun{} = run <- Repo.get(ProjectSnapshotReconciliationRun, run_id),
         :ok <- validate_completed_run(run),
         :ok <- validate_namespace(run.provider_namespace_fingerprint) do
      plan_page(run, after_id, limit)
    else
      nil -> {:error, :snapshot_reconciliation_run_not_found}
      {:error, _reason} = error -> error
    end
  end

  def plan(_run_id, _opts), do: {:error, :invalid_snapshot_reconciliation_repair_options}

  @doc "Returns one durable repair action."
  @spec get_action(pos_integer()) :: ProjectSnapshotReconciliationRepairAction.t() | nil
  def get_action(action_id) when is_integer(action_id) and action_id > 0,
    do: Repo.get(ProjectSnapshotReconciliationRepairAction, action_id)

  def get_action(_action_id), do: nil

  @doc "Lists repair outcomes for one inspection run in stable action order."
  @spec list_actions(pos_integer(), keyword()) :: [ProjectSnapshotReconciliationRepairAction.t()]
  def list_actions(run_id, opts \\ [])

  def list_actions(run_id, opts) when is_integer(run_id) and run_id > 0 and is_list(opts) do
    case normalize_list_options(opts) do
      {:ok, after_id, limit} ->
        Repo.all(
          from(action in ProjectSnapshotReconciliationRepairAction,
            join: finding in ProjectSnapshotReconciliationFinding,
            on: finding.id == action.source_finding_id,
            where: finding.run_id == ^run_id and action.id > ^after_id,
            order_by: [asc: action.id],
            limit: ^limit
          )
        )

      :error ->
        []
    end
  end

  def list_actions(_run_id, _opts), do: []

  @doc false
  @spec repair_page_limit() :: pos_integer()
  def repair_page_limit, do: @max_limit

  @doc false
  @spec repair_delivery_recovery_high_watermark() :: non_neg_integer()
  def repair_delivery_recovery_high_watermark do
    Repo.one(
      from(action in ProjectSnapshotReconciliationRepairAction,
        where: action.status == "pending",
        select: coalesce(max(action.id), 0)
      )
    )
  end

  @doc false
  @spec recover_repair_delivery_page(keyword()) :: {:ok, map()} | {:error, term()}
  def recover_repair_delivery_page(opts \\ [])

  def recover_repair_delivery_page(opts) when is_list(opts) do
    with {:ok, after_id, through_id, limit} <- normalize_recovery_options(opts) do
      action_ids = pending_repair_action_ids(after_id, through_id, limit)

      counts =
        Enum.reduce(action_ids, empty_recovery_counts(), &recover_repair_delivery_count/2)

      next_after_id = List.last(action_ids) || after_id

      {:ok,
       counts
       |> Map.put(:next_after_id, next_after_id)
       |> Map.put(:complete?, action_ids == [] or length(action_ids) < limit or next_after_id >= through_id)}
    end
  end

  def recover_repair_delivery_page(_opts), do: {:error, :invalid_snapshot_reconciliation_repair_recovery_options}

  defp recover_repair_delivery_count(action_id, counts) do
    case recover_repair_delivery(action_id) do
      {:ok, status} -> increment_recovery_count(counts, status)
      {:error, _reason} -> Map.update!(counts, :failure_count, &(&1 + 1))
    end
  end

  @doc false
  @spec perform(pos_integer()) :: {:ok, atom()} | {:error, term()}
  def perform(action_id) when is_integer(action_id) and action_id > 0 do
    perform_with_lock(action_id, &StorageKeyLock.with_session_lock/2)
  end

  def perform(_action_id), do: {:error, :invalid_snapshot_reconciliation_repair_action}

  @doc false
  @spec perform_with_lock(pos_integer(), (String.t(), (-> term()) -> term())) ::
          {:ok, atom()} | {:error, term()}
  def perform_with_lock(action_id, lock_fun) when is_integer(action_id) and action_id > 0 and is_function(lock_fun, 2) do
    with {:ok, action} <- record_attempt(action_id) do
      continue_recorded_action(action, action_id, lock_fun)
    end
  end

  def perform_with_lock(_action_id, _lock_fun), do: {:error, :invalid_snapshot_reconciliation_repair_action}

  defp continue_recorded_action(%{status: status}, _action_id, _lock_fun) when status in @repair_terminal_statuses,
    do: {:ok, String.to_existing_atom(status)}

  defp continue_recorded_action(_action, action_id, lock_fun) do
    lock_fun.("snapshot-reconciliation-repair:#{action_id}", fn ->
      perform_recorded_action(action_id)
    end)
  end

  @doc false
  @spec fail(pos_integer(), term()) :: {:ok, atom()} | {:error, term()}
  def fail(action_id, reason) when is_integer(action_id) and action_id > 0 do
    case finish_action(action_id, "failed", error_code(reason), %{}) do
      {:ok, action, transitioned?} ->
        maybe_emit_action(action, transitioned?, 0)
        {:ok, String.to_existing_atom(action.status)}

      {:error, _reason} = error ->
        error
    end
  end

  def fail(_action_id, _reason), do: {:error, :invalid_snapshot_reconciliation_repair_action}

  defp recover_repair_delivery(action_id) do
    result =
      Repo.transact(fn ->
        case lock_action(action_id) do
          nil ->
            {:ok, {:already_terminal, nil}}

          %ProjectSnapshotReconciliationRepairAction{status: status}
          when status in @repair_terminal_statuses ->
            {:ok, {:already_terminal, nil}}

          %ProjectSnapshotReconciliationRepairAction{} = action ->
            recover_locked_repair_delivery(action)
        end
      end)

    case result do
      {:ok, {:exhausted, action}} ->
        maybe_emit_action(action, true, 0)
        {:ok, :exhausted}

      {:ok, {status, _action}} ->
        {:ok, status}

      {:error, _reason} = error ->
        error
    end
  end

  defp recover_locked_repair_delivery(action) do
    now = %{database_clock_now() | microsecond: {0, 6}}
    cutoff = DateTime.add(now, -RepairProjectSnapshotFindingWorker.recovery_after_seconds(), :second)
    jobs = exact_repair_delivery_jobs(action)
    active_jobs = Enum.filter(jobs, &(&1.state in @active_repair_job_states))

    case active_jobs do
      [job] -> recover_active_repair_delivery(action, job, cutoff, now)
      [] -> recover_inactive_repair_delivery(action, List.first(jobs), now)
      _multiple -> {:error, :ambiguous_snapshot_reconciliation_repair_delivery}
    end
  end

  defp recover_active_repair_delivery(action, %Oban.Job{state: "executing"} = job, cutoff, now) do
    if stale_repair_delivery?(job, cutoff) do
      if repair_delivery_exhausted?(action, job) do
        job
        |> Ecto.Changeset.change(state: "discarded", discarded_at: now)
        |> Repo.update!()

        fail_exhausted_action(action)
      else
        job |> Ecto.Changeset.change(state: "available") |> Repo.update!()
        {:ok, {:requeued, nil}}
      end
    else
      {:ok, {:already_active, nil}}
    end
  end

  defp recover_active_repair_delivery(_action, %Oban.Job{}, _cutoff, _now), do: {:ok, {:already_active, nil}}

  defp recover_inactive_repair_delivery(action, %Oban.Job{state: state} = job, _now)
       when state in @recoverable_terminal_job_states do
    if repair_delivery_exhausted?(action, job) do
      fail_exhausted_action(action)
    else
      job
      |> Ecto.Changeset.change(state: "available", cancelled_at: nil, discarded_at: nil)
      |> Repo.update!()

      {:ok, {:requeued, nil}}
    end
  end

  defp recover_inactive_repair_delivery(action, nil, _now) do
    max_attempts = repair_worker_max_attempts()

    if action.attempt_count >= max_attempts do
      fail_exhausted_action(action)
    else
      remaining_attempts = max(max_attempts - action.attempt_count, 1)

      case action.id |> repair_job(max_attempts: remaining_attempts, unique: false) |> Oban.insert() do
        {:ok, %Oban.Job{}} -> {:ok, {:reenqueued, nil}}
        {:error, reason} -> {:error, reason}
      end
    end
  end

  defp fail_exhausted_action(action) do
    with {:ok, attempted} <- ensure_recorded_attempt(action),
         {:ok, finished} <-
           attempted
           |> ProjectSnapshotReconciliationRepairAction.outcome_changeset(%{
             status: "failed",
             result_code: "repair_delivery_exhausted"
           })
           |> Repo.update() do
      {:ok, {:exhausted, finished}}
    end
  end

  defp ensure_recorded_attempt(%ProjectSnapshotReconciliationRepairAction{attempt_count: 0} = action) do
    action |> ProjectSnapshotReconciliationRepairAction.attempt_changeset() |> Repo.update()
  end

  defp ensure_recorded_attempt(%ProjectSnapshotReconciliationRepairAction{} = action), do: {:ok, action}

  defp exact_repair_delivery_jobs(action) do
    expected_args = %{
      "action_id" => action.id,
      "contract_version" => action.contract_version
    }

    Repo.all(
      from(job in Oban.Job,
        where:
          job.worker == ^@repair_worker and job.queue == ^@repair_queue and
            job.state in ^@recoverable_repair_job_states and
            job.args == ^expected_args,
        order_by: [desc: job.id],
        limit: 3,
        lock: "FOR UPDATE"
      )
    )
  end

  defp stale_repair_delivery?(%Oban.Job{attempted_at: %DateTime{} = attempted_at}, cutoff),
    do: DateTime.before?(attempted_at, cutoff)

  defp stale_repair_delivery?(_job, _cutoff), do: false

  defp repair_delivery_exhausted?(action, job) do
    action.attempt_count >= repair_worker_max_attempts() or job.attempt >= job.max_attempts
  end

  defp repair_worker_max_attempts do
    Keyword.fetch!(RepairProjectSnapshotFindingWorker.__opts__(), :max_attempts)
  end

  defp plan_page(run, after_id, limit) do
    Repo.transact(fn ->
      locked_run = lock_run(run.id)

      with :ok <- validate_completed_run(locked_run) do
        findings = page_findings(run.id, after_id, limit)

        actions = Enum.map(findings, &plan_action!(&1, locked_run))

        next_after_id = finding_page_cursor(findings, after_id)

        {:ok,
         %{
           actions: actions,
           complete?: length(findings) < limit,
           next_after_id: next_after_id
         }}
      end
    end)
  end

  defp finding_page_cursor([], after_id), do: after_id
  defp finding_page_cursor(findings, _after_id), do: findings |> List.last() |> Map.fetch!(:id)

  defp page_findings(run_id, after_id, limit) do
    Repo.all(
      from(finding in ProjectSnapshotReconciliationFinding,
        where: finding.run_id == ^run_id and finding.id > ^after_id,
        order_by: [asc: finding.id],
        limit: ^limit,
        lock: "FOR SHARE"
      )
    )
  end

  defp plan_action!(finding, run) do
    attrs = %{
      source_finding_id: finding.id,
      provider_namespace_fingerprint_snapshot: run.provider_namespace_fingerprint,
      subject_fingerprint: finding.fingerprint,
      action_kind: action_kind(finding)
    }

    {action, inserted?} =
      %ProjectSnapshotReconciliationRepairAction{}
      |> ProjectSnapshotReconciliationRepairAction.plan_changeset(attrs)
      |> Repo.insert!(
        on_conflict: :nothing,
        conflict_target: [:source_finding_id, :contract_version]
      )
      |> resolve_action_conflict!(finding.id)

    if inserted? do
      action.id
      |> repair_job()
      |> Oban.insert!()
    end

    action
  end

  defp resolve_action_conflict!(%ProjectSnapshotReconciliationRepairAction{id: id} = action, _finding_id)
       when is_integer(id), do: {action, true}

  defp resolve_action_conflict!(%ProjectSnapshotReconciliationRepairAction{}, finding_id) do
    action =
      Repo.get_by!(ProjectSnapshotReconciliationRepairAction,
        contract_version: @contract_version,
        source_finding_id: finding_id
      )

    {action, false}
  end

  defp perform_recorded_action(action_id) do
    case Repo.get(ProjectSnapshotReconciliationRepairAction, action_id) do
      nil ->
        {:error, :snapshot_reconciliation_repair_action_not_found}

      %ProjectSnapshotReconciliationRepairAction{status: status}
      when status in @repair_terminal_statuses ->
        {:ok, String.to_existing_atom(status)}

      %ProjectSnapshotReconciliationRepairAction{} = action ->
        execute_pending_action(action)
    end
  end

  defp record_attempt(action_id) do
    Repo.transact(fn ->
      case lock_action(action_id) do
        nil ->
          {:error, :snapshot_reconciliation_repair_action_not_found}

        %ProjectSnapshotReconciliationRepairAction{status: status} = action
        when status in @repair_terminal_statuses ->
          {:ok, action}

        %ProjectSnapshotReconciliationRepairAction{} = action ->
          action
          |> ProjectSnapshotReconciliationRepairAction.attempt_changeset()
          |> Repo.update()
      end
    end)
  end

  defp execute_pending_action(action) do
    with %ProjectSnapshotReconciliationFinding{} = finding <-
           Repo.get(ProjectSnapshotReconciliationFinding, action.source_finding_id),
         %ProjectSnapshotReconciliationRun{} = run <- Repo.get(ProjectSnapshotReconciliationRun, finding.run_id),
         :ok <- validate_action_identity(action, finding, run),
         {:ok, outcome, result_code, attrs} <- dispatch_with_namespace(run, action, finding),
         {:ok, finished, transitioned?} <- finish_action(action.id, outcome, result_code, attrs) do
      bytes = repair_bytes(finding, action.action_kind, outcome)
      maybe_emit_action(finished, transitioned?, bytes)
      {:ok, String.to_existing_atom(finished.status)}
    else
      nil -> {:error, :snapshot_reconciliation_repair_evidence_not_found}
      {:error, _reason} = error -> error
    end
  end

  defp dispatch_with_namespace(run, action, finding) do
    case Storage.namespace_fingerprint() do
      {:ok, fingerprint} when fingerprint == run.provider_namespace_fingerprint ->
        dispatch(action.action_kind, finding, run.provider_namespace_fingerprint)

      {:ok, _different} ->
        {:ok, "manual", "provider_namespace_changed", %{}}

      {:error, reason} ->
        {:error, {:snapshot_reconciliation_namespace_unavailable, reason}}
    end
  end

  defp dispatch("mark_missing", finding, provider_namespace_fingerprint),
    do: repair_integrity(finding, provider_namespace_fingerprint)

  defp dispatch("mark_corrupt", finding, provider_namespace_fingerprint),
    do: repair_integrity(finding, provider_namespace_fingerprint)

  defp dispatch("cleanup_expired_build", finding, provider_namespace_fingerprint),
    do: repair_expired_build(finding, provider_namespace_fingerprint)

  defp dispatch("replay_cleanup", finding, _provider_namespace_fingerprint), do: replay_cleanup(finding)

  defp dispatch("report_only", finding, _provider_namespace_fingerprint),
    do: {:ok, "manual", "manual_review_#{finding.category}", %{}}

  defp repair_integrity(finding, provider_namespace_fingerprint) do
    with :ok <- validate_integrity_finding_identity(finding),
         %ProjectSnapshot{} = observed_snapshot <- get_ready_snapshot(finding),
         {:ok, observed_integrity} <- current_integrity(observed_snapshot, finding) do
      finding.workspace_id_snapshot
      |> Billing.transact_with_workspace_lock(fn _workspace ->
        repair_integrity_locked(
          finding,
          observed_snapshot,
          observed_integrity,
          provider_namespace_fingerprint
        )
      end)
      |> flatten_repair_result()
    else
      nil -> resolve_missing_integrity_subject(finding)
      {:error, _reason} = error -> error
    end
  end

  defp resolve_missing_integrity_subject(finding) do
    finding.workspace_id_snapshot
    |> Billing.transact_with_workspace_lock(fn _workspace ->
      {:ok, {"resolved", "integrity_finding_stale", %{}}}
    end)
    |> flatten_repair_result()
  end

  defp repair_integrity_locked(finding, observed_snapshot, observed_integrity, provider_namespace_fingerprint) do
    case Storage.namespace_fingerprint() do
      {:ok, ^provider_namespace_fingerprint} ->
        apply_locked_integrity(finding, observed_snapshot, observed_integrity)

      {:ok, _different} ->
        {:ok, {"manual", "provider_namespace_changed", %{}}}

      {:error, reason} ->
        {:error, {:snapshot_reconciliation_namespace_unavailable, reason}}
    end
  end

  defp apply_locked_integrity(finding, observed_snapshot, observed_integrity) do
    case lock_ready_snapshot(finding, observed_snapshot) do
      nil -> {:ok, {"resolved", "integrity_finding_stale", %{}}}
      snapshot -> apply_current_integrity(snapshot, observed_integrity)
    end
  end

  defp apply_current_integrity(snapshot, current_integrity) do
    case current_integrity do
      :healthy ->
        {:ok, {"resolved", "storage_object_now_verified", %{}}}

      target when target in [:missing, :corrupt] ->
        apply_integrity_target(snapshot, Atom.to_string(target))

      :finding_stale ->
        {:ok, {"resolved", "integrity_finding_stale", %{}}}
    end
  end

  defp apply_integrity_target(%ProjectSnapshot{integrity_state: target}, target),
    do: {:ok, {"repaired", "integrity_already_marked_#{target}", %{}}}

  defp apply_integrity_target(snapshot, target) do
    snapshot
    |> ProjectSnapshot.reconciliation_integrity_changeset(target)
    |> Repo.update()
    |> case do
      {:ok, _snapshot} -> {:ok, {"repaired", "integrity_marked_#{target}", %{}}}
      {:error, changeset} -> {:error, changeset}
    end
  end

  defp current_integrity(snapshot, %{category: category})
       when snapshot.format_version == 2 and
              category in [
                "ready_manifest_missing",
                "ready_manifest_corrupt",
                "ready_object_missing",
                "ready_object_corrupt"
              ] do
    snapshot
    |> SnapshotArchiveStorage.inspect_ready_archive()
    |> classify_integrity_result()
  end

  defp current_integrity(%ProjectSnapshot{}, _finding), do: {:error, :unsupported_snapshot_reconciliation_format}

  @doc false
  def classify_integrity_result({:ok, _value}), do: {:ok, :healthy}

  def classify_integrity_result({:error, :snapshot_inspection_object_not_found}), do: {:ok, :finding_stale}

  def classify_integrity_result({:error, reason}) do
    cond do
      missing_storage_reason?(reason) -> {:ok, :missing}
      corrupt_storage_reason?(reason) -> {:ok, :corrupt}
      true -> {:error, reason}
    end
  end

  defp repair_expired_build(finding, provider_namespace_fingerprint) do
    with true <- is_integer(finding.project_snapshot_id_snapshot),
         true <- is_integer(finding.storage_reservation_id_snapshot),
         true <- is_integer(finding.lifecycle_generation),
         true <- is_integer(finding.reservation_generation) do
      now = TimeHelpers.now()
      snapshot_id = finding.project_snapshot_id_snapshot

      candidate = expired_build_candidate(now, snapshot_id, finding)
      repair_expired_build_candidate(candidate, finding, provider_namespace_fingerprint)
    else
      false -> {:ok, "manual", "expired_build_identity_incomplete", %{}}
    end
  end

  defp expired_build_candidate(now, snapshot_id, finding) do
    now
    |> ProjectSnapshotLifecycle.list_expired_build_candidates(
      after_id: snapshot_id - 1,
      through_id: snapshot_id,
      limit: 1
    )
    |> Enum.find(&expired_candidate_matches?(&1, finding))
  end

  defp repair_expired_build_candidate(nil, finding, provider_namespace_fingerprint),
    do: classify_changed_reservation(finding, provider_namespace_fingerprint)

  defp repair_expired_build_candidate(candidate, finding, provider_namespace_fingerprint) do
    case ProjectSnapshotLifecycle.delete_expired_build_candidate(candidate, provider_namespace_fingerprint) do
      {:ok, %SnapshotCleanupIntent{}} ->
        {:ok, "repaired", "expired_build_cleanup_scheduled", %{}}

      {:error, :expired_build_candidate_changed} ->
        classify_changed_reservation(finding, provider_namespace_fingerprint)

      {:error, :snapshot_cleanup_provider_namespace_changed} ->
        {:ok, "manual", "provider_namespace_changed", %{}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp expired_candidate_matches?(candidate, finding) do
    candidate.workspace_id == finding.workspace_id_snapshot and
      candidate.project_id == finding.project_id_snapshot and
      candidate.snapshot_id == finding.project_snapshot_id_snapshot and
      candidate.lifecycle_generation == finding.lifecycle_generation and
      candidate.reservation_id == finding.storage_reservation_id_snapshot and
      candidate.reservation_generation == finding.reservation_generation
  end

  defp classify_changed_reservation(finding, provider_namespace_fingerprint) do
    finding.workspace_id_snapshot
    |> Billing.transact_with_workspace_lock(fn _workspace ->
      reservation = lock_reservation(finding.storage_reservation_id_snapshot)

      if exact_expired_build_cleanup?(reservation, finding, provider_namespace_fingerprint) do
        {:ok, {"repaired", "expired_build_cleanup_already_scheduled", %{}}}
      else
        {:ok, {"manual", "expired_build_no_longer_repairable", %{}}}
      end
    end)
    |> flatten_repair_result()
  end

  defp lock_reservation(reservation_id) do
    Repo.one(
      from(reservation in StorageReservation,
        where: reservation.id == ^reservation_id,
        lock: "FOR SHARE"
      )
    )
  end

  defp exact_expired_build_cleanup?(
         %StorageReservation{status: "released", kind: "snapshot_build"} = reservation,
         finding,
         provider_namespace_fingerprint
       ) do
    expected_reservation_generation = finding.reservation_generation + 1
    expected_deletion_generation = finding.lifecycle_generation + 1

    with true <- reservation.workspace_id_snapshot == finding.workspace_id_snapshot,
         true <- reservation.project_id_snapshot == finding.project_id_snapshot,
         true <- reservation.project_snapshot_id_snapshot == finding.project_snapshot_id_snapshot,
         true <- reservation.generation == expected_reservation_generation,
         true <- reservation.cleanup_object_prefix == finding.object_prefix,
         {%SnapshotCleanupIntent{} = intent, %StorageCleanupRequest{} = request} <-
           exact_expired_build_cleanup_intent(
             finding,
             expected_deletion_generation,
             provider_namespace_fingerprint
           ),
         :ok <- SnapshotCleanupIntent.validate_persisted_inventory(intent) do
      exact_reservation_cleanup?(reservation, intent) and request.owner_kind == "snapshot_lifecycle" and
        is_binary(request.owner_token) and
        request.provider_namespace_fingerprint == provider_namespace_fingerprint and
        request.storage_keys == intent.storage_keys
    else
      _mismatch -> false
    end
  end

  defp exact_expired_build_cleanup?(_reservation, _finding, _provider_namespace_fingerprint), do: false

  defp exact_reservation_cleanup?(%StorageReservation{cleanup_status: "owned"} = reservation, intent) do
    reservation.release_reason == "snapshot_deleted" and
      reservation.cleanup_reference == "storage_cleanup_request:#{intent.cleanup_request_id}" and
      reservation.cleanup_inventory_digest == intent.inventory_digest and
      reservation.cleanup_inventory_count == intent.object_count
  end

  defp exact_reservation_cleanup?(%StorageReservation{cleanup_status: "not_required"} = reservation, _intent) do
    reservation.release_reason == "snapshot_deleted_before_storage_started" and
      is_nil(reservation.storage_started_at) and is_nil(reservation.cleanup_inventory_digest) and
      is_nil(reservation.cleanup_inventory_count) and
      reservation.cleanup_reference == "storage_not_started:#{reservation.storage_namespace}"
  end

  defp exact_reservation_cleanup?(_reservation, _intent), do: false

  defp exact_expired_build_cleanup_intent(finding, deletion_generation, provider_namespace_fingerprint) do
    Repo.one(
      from(intent in SnapshotCleanupIntent,
        join: request in StorageCleanupRequest,
        on: request.id == intent.cleanup_request_id,
        where:
          intent.workspace_id_snapshot == ^finding.workspace_id_snapshot and
            intent.project_id_snapshot == ^finding.project_id_snapshot and
            intent.project_snapshot_id_snapshot == ^finding.project_snapshot_id_snapshot and
            intent.reason == "expired_build" and intent.authority_kind == "system" and
            intent.deletion_generation == ^deletion_generation and
            intent.ready_prefix == ^finding.object_prefix and
            intent.provider_namespace_fingerprint == ^provider_namespace_fingerprint,
        select: {intent, request},
        lock: "FOR SHARE"
      )
    )
  end

  defp replay_cleanup(%{cleanup_intent_id_snapshot: intent_id, details: details} = finding)
       when is_integer(intent_id) and intent_id > 0 and is_map(details) do
    expectations = %{
      cleanup_intent_id_snapshot: intent_id,
      workspace_id_snapshot: finding.workspace_id_snapshot,
      project_id_snapshot: finding.project_id_snapshot,
      project_snapshot_id_snapshot: finding.project_snapshot_id_snapshot,
      lifecycle_generation: finding.lifecycle_generation,
      object_prefix: finding.object_prefix,
      expected_size_bytes: finding.expected_size_bytes,
      error_code: finding.error_code,
      reason: details["reason"],
      retry_count: details["retry_count"],
      processing_generation: details["processing_generation"]
    }

    intent_id
    |> ProjectSnapshotLifecycle.replay_terminal_cleanup_intent(expectations)
    |> normalize_cleanup_replay_result()
  end

  defp replay_cleanup(_finding), do: {:ok, "manual", "cleanup_intent_identity_missing", %{}}

  defp normalize_cleanup_replay_result({:ok, %SnapshotCleanupIntent{}}),
    do: {:ok, "repaired", "cleanup_intent_replayed", %{}}

  defp normalize_cleanup_replay_result({:ok, :already_completed}), do: {:ok, "resolved", "cleanup_intent_completed", %{}}

  defp normalize_cleanup_replay_result({:ok, :already_active}),
    do: {:ok, "repaired", "cleanup_intent_already_active", %{}}

  defp normalize_cleanup_replay_result({:error, {:snapshot_cleanup_manual_repair_required, _code}}),
    do: {:ok, "manual", "cleanup_intent_manual_repair_required", %{}}

  defp normalize_cleanup_replay_result({:error, :snapshot_cleanup_provider_namespace_changed}),
    do: {:ok, "manual", "cleanup_intent_provider_namespace_changed", %{}}

  defp normalize_cleanup_replay_result({:error, :snapshot_cleanup_namespace_still_owned}),
    do: {:ok, "manual", "cleanup_intent_namespace_still_owned", %{}}

  defp normalize_cleanup_replay_result({:error, :snapshot_cleanup_intent_changed}),
    do: {:ok, "resolved", "cleanup_intent_changed", %{}}

  defp normalize_cleanup_replay_result({:error, :snapshot_cleanup_intent_not_found}),
    do: {:ok, "resolved", "cleanup_intent_no_longer_exists", %{}}

  defp normalize_cleanup_replay_result({:error, reason}), do: {:error, reason}

  defp validate_integrity_finding_identity(finding) do
    valid? =
      finding.category in [
        "ready_manifest_missing",
        "ready_manifest_corrupt",
        "ready_object_missing",
        "ready_object_corrupt"
      ] and is_integer(finding.workspace_id_snapshot) and is_integer(finding.project_id_snapshot) and
        is_integer(finding.project_snapshot_id_snapshot) and is_integer(finding.lifecycle_generation) and
        is_integer(finding.accounting_generation) and is_binary(finding.object_prefix) and
        is_binary(finding.storage_key)

    if valid?, do: :ok, else: {:error, :invalid_snapshot_integrity_finding}
  end

  defp get_ready_snapshot(finding), do: Repo.one(ready_snapshot_query(finding))

  defp lock_ready_snapshot(finding, observed_snapshot) do
    format_fence = integrity_storage_fence(observed_snapshot)

    Repo.one(
      from(snapshot in ready_snapshot_query(finding),
        where:
          snapshot.integrity_state == ^observed_snapshot.integrity_state and
            snapshot.manifest_storage_key == ^observed_snapshot.manifest_storage_key and
            snapshot.manifest_checksum == ^observed_snapshot.manifest_checksum and
            snapshot.manifest_size_bytes == ^observed_snapshot.manifest_size_bytes,
        where: ^format_fence,
        lock: "FOR UPDATE"
      )
    )
  end

  defp integrity_storage_fence(%ProjectSnapshot{format_version: 2} = observed) do
    dynamic(
      [snapshot],
      snapshot.format_version == 2 and
        snapshot.archive_storage_key == ^observed.archive_storage_key and
        snapshot.archive_size_bytes == ^observed.archive_size_bytes and
        snapshot.archive_checksum == ^observed.archive_checksum
    )
  end

  defp integrity_storage_fence(%ProjectSnapshot{}), do: dynamic([_snapshot], false)

  defp ready_snapshot_query(finding) do
    from(snapshot in ProjectSnapshot,
      join: project in Project,
      on: project.id == snapshot.project_id,
      where:
        snapshot.id == ^finding.project_snapshot_id_snapshot and
          snapshot.project_id == ^finding.project_id_snapshot and
          project.workspace_id == ^finding.workspace_id_snapshot and snapshot.mode == "full" and
          snapshot.lifecycle_state == "ready" and
          snapshot.lifecycle_generation == ^finding.lifecycle_generation and
          snapshot.accounting_generation == ^finding.accounting_generation and
          snapshot.object_prefix == ^finding.object_prefix
    )
  end

  defp flatten_repair_result({:ok, {status, result_code, attrs}}), do: {:ok, status, result_code, attrs}

  defp flatten_repair_result({:error, :workspace_not_found}), do: {:ok, "resolved", "workspace_no_longer_exists", %{}}

  defp flatten_repair_result({:error, _reason} = error), do: error

  defp finish_action(action_id, status, result_code, attrs) do
    fn ->
      case lock_action(action_id) do
        nil ->
          {:error, :snapshot_reconciliation_repair_action_not_found}

        %ProjectSnapshotReconciliationRepairAction{status: current} = action
        when current in @repair_terminal_statuses ->
          {:ok, {action, false}}

        %ProjectSnapshotReconciliationRepairAction{} = action ->
          persist_action_outcome(action, status, result_code, attrs)
      end
    end
    |> Repo.transact()
    |> case do
      {:ok, {action, transitioned?}} -> {:ok, action, transitioned?}
      {:error, _reason} = error -> error
    end
  end

  defp persist_action_outcome(action, status, result_code, attrs) do
    outcome_attrs = Map.merge(attrs, %{status: status, result_code: result_code})

    action
    |> ProjectSnapshotReconciliationRepairAction.outcome_changeset(outcome_attrs)
    |> Repo.update()
    |> case do
      {:ok, finished} -> {:ok, {finished, true}}
      {:error, reason} -> {:error, reason}
    end
  end

  defp validate_action_identity(action, finding, run) do
    expected_kind = action_kind(finding)

    if action.contract_version == @contract_version and
         action.provider_namespace_fingerprint_snapshot == run.provider_namespace_fingerprint and
         action.subject_fingerprint == finding.fingerprint and action.action_kind == expected_kind,
       do: :ok,
       else: {:error, :invalid_snapshot_reconciliation_repair_identity}
  end

  defp action_kind(%{category: category}) when category in ["ready_manifest_missing", "ready_object_missing"],
    do: "mark_missing"

  defp action_kind(%{category: category}) when category in ["ready_manifest_corrupt", "ready_object_corrupt"],
    do: "mark_corrupt"

  defp action_kind(%{category: "stale_reservation", details: %{"reason" => reason}})
       when reason in ["owning_job_missing", "owning_job_completed", "owning_job_discarded", "owning_job_cancelled"],
       do: "cleanup_expired_build"

  defp action_kind(%{category: "terminal_cleanup_failure"}), do: "replay_cleanup"
  defp action_kind(%{category: "failed_snapshot_finalization"}), do: "cleanup_expired_build"
  defp action_kind(_finding), do: "report_only"

  defp repair_job(action_id, opts \\ []) do
    RepairProjectSnapshotFindingWorker.new(
      %{
        action_id: action_id,
        contract_version: @contract_version
      },
      opts
    )
  end

  defp repair_bytes(finding, "cleanup_expired_build", "repaired"), do: non_negative(finding.expected_size_bytes)
  defp repair_bytes(_finding, _action_kind, _outcome), do: 0

  defp non_negative(value) when is_integer(value) and value >= 0, do: value
  defp non_negative(_value), do: 0

  defp maybe_emit_action(_action, false, _bytes), do: :ok

  defp maybe_emit_action(action, true, bytes) do
    :telemetry.execute(
      [:storyarn, :snapshot, :reconciliation, :repair, :stop],
      %{count: 1, bytes: bytes},
      %{action: action_tag(action.action_kind), outcome: outcome_tag(action.status)}
    )
  end

  defp action_tag("mark_missing"), do: :mark_missing
  defp action_tag("mark_corrupt"), do: :mark_corrupt
  defp action_tag("cleanup_expired_build"), do: :cleanup_expired_build
  defp action_tag("replay_cleanup"), do: :replay_cleanup
  defp action_tag("report_only"), do: :report_only

  defp outcome_tag("repaired"), do: :repaired
  defp outcome_tag("resolved"), do: :resolved
  defp outcome_tag("manual"), do: :manual
  defp outcome_tag("failed"), do: :failed

  defp normalize_plan_options(opts) do
    if Keyword.keyword?(opts) do
      after_id = Keyword.get(opts, :after_id, 0)
      limit = Keyword.get(opts, :limit, @default_limit)

      if Keyword.keys(opts) -- [:after_id, :limit] == [] and is_integer(after_id) and after_id >= 0 and
           is_integer(limit) and limit > 0 do
        {:ok, after_id, min(limit, @max_limit)}
      else
        {:error, :invalid_snapshot_reconciliation_repair_options}
      end
    else
      {:error, :invalid_snapshot_reconciliation_repair_options}
    end
  end

  defp normalize_list_options(opts) do
    case normalize_plan_options(opts) do
      {:ok, after_id, limit} -> {:ok, after_id, limit}
      {:error, _reason} -> :error
    end
  end

  defp normalize_recovery_options(opts) do
    if Keyword.keyword?(opts) do
      after_id = Keyword.get(opts, :after_id, 0)
      through_id = Keyword.get_lazy(opts, :through_id, &repair_delivery_recovery_high_watermark/0)
      limit = Keyword.get(opts, :limit, @default_recovery_limit)

      if Keyword.keys(opts) -- [:after_id, :through_id, :limit] == [] and is_integer(after_id) and after_id >= 0 and
           is_integer(through_id) and through_id >= after_id and is_integer(limit) and limit > 0 do
        {:ok, after_id, through_id, min(limit, @max_recovery_limit)}
      else
        {:error, :invalid_snapshot_reconciliation_repair_recovery_options}
      end
    else
      {:error, :invalid_snapshot_reconciliation_repair_recovery_options}
    end
  end

  defp pending_repair_action_ids(after_id, through_id, limit) do
    Repo.all(
      from(action in ProjectSnapshotReconciliationRepairAction,
        where: action.status == "pending" and action.id > ^after_id and action.id <= ^through_id,
        order_by: [asc: action.id],
        limit: ^limit,
        select: action.id
      )
    )
  end

  defp empty_recovery_counts do
    %{
      requeued_count: 0,
      reenqueued_count: 0,
      already_active_count: 0,
      terminalized_count: 0,
      already_terminal_count: 0,
      failure_count: 0
    }
  end

  defp increment_recovery_count(counts, :requeued), do: Map.update!(counts, :requeued_count, &(&1 + 1))
  defp increment_recovery_count(counts, :reenqueued), do: Map.update!(counts, :reenqueued_count, &(&1 + 1))

  defp increment_recovery_count(counts, :already_active), do: Map.update!(counts, :already_active_count, &(&1 + 1))

  defp increment_recovery_count(counts, :exhausted), do: Map.update!(counts, :terminalized_count, &(&1 + 1))

  defp increment_recovery_count(counts, :already_terminal), do: Map.update!(counts, :already_terminal_count, &(&1 + 1))

  defp validate_completed_run(%ProjectSnapshotReconciliationRun{status: "completed"}), do: :ok
  defp validate_completed_run(%ProjectSnapshotReconciliationRun{}), do: {:error, :snapshot_reconciliation_run_incomplete}
  defp validate_completed_run(nil), do: {:error, :snapshot_reconciliation_run_not_found}

  defp validate_namespace(expected) do
    case Storage.namespace_fingerprint() do
      {:ok, ^expected} -> :ok
      {:ok, _different} -> {:error, :snapshot_reconciliation_namespace_changed}
      {:error, reason} -> {:error, {:snapshot_reconciliation_namespace_unavailable, reason}}
    end
  end

  defp lock_run(run_id) do
    Repo.one(
      from(run in ProjectSnapshotReconciliationRun,
        where: run.id == ^run_id,
        lock: "FOR SHARE"
      )
    )
  end

  defp lock_action(action_id) do
    Repo.one(
      from(action in ProjectSnapshotReconciliationRepairAction,
        where: action.id == ^action_id,
        lock: "FOR UPDATE"
      )
    )
  end

  defp database_clock_now do
    %Postgrex.Result{rows: [[now]]} = Repo.query!("SELECT clock_timestamp()")
    now
  end

  defp missing_storage_reason?(:enoent), do: true
  defp missing_storage_reason?({:http_error, 404, _response}), do: true

  defp missing_storage_reason?({:snapshot_inspection_object_failed, %{reason: reason}}),
    do: missing_storage_reason?(reason)

  defp missing_storage_reason?(_reason), do: false

  defp corrupt_storage_reason?({:snapshot_manifest_validation_failed, _reason}), do: true
  defp corrupt_storage_reason?({:snapshot_object_size_mismatch, _storage_key}), do: true
  defp corrupt_storage_reason?({:snapshot_object_size_mismatch, _path, _expected, _actual}), do: true

  defp corrupt_storage_reason?({:snapshot_object_content_type_mismatch, _path, _expected, _actual}), do: true

  defp corrupt_storage_reason?({:snapshot_object_checksum_mismatch, _storage_key}), do: true
  defp corrupt_storage_reason?({:snapshot_object_checksum_mismatch, _expected, _actual}), do: true
  defp corrupt_storage_reason?({:invalid_snapshot_object_stat, _path, _stat}), do: true
  defp corrupt_storage_reason?({:invalid_snapshot_object_json, _path, _reason}), do: true
  defp corrupt_storage_reason?({:unsupported_project_format, _version}), do: true
  defp corrupt_storage_reason?({:snapshot_object_size_limit_exceeded, _label, _limit}), do: true
  defp corrupt_storage_reason?({:json_object_size_limit_exceeded, _limit}), do: true
  defp corrupt_storage_reason?({:unsafe_project_metadata_key, _key}), do: true
  defp corrupt_storage_reason?(:invalid_project_object), do: true
  defp corrupt_storage_reason?(:invalid_json_value), do: true

  defp corrupt_storage_reason?({:snapshot_inspection_object_failed, %{reason: reason}}),
    do: corrupt_storage_reason?(reason)

  defp corrupt_storage_reason?(_reason), do: false

  defp error_code(reason) when is_atom(reason), do: reason |> Atom.to_string() |> String.slice(0, 255)
  defp error_code({reason, _detail}) when is_atom(reason), do: error_code(reason)
  defp error_code({reason, _first, _second}) when is_atom(reason), do: error_code(reason)
  defp error_code(_reason), do: "snapshot_reconciliation_repair_failed"
end
