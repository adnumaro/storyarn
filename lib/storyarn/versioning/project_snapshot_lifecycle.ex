defmodule Storyarn.Versioning.ProjectSnapshotLifecycle do
  @moduledoc """
  Generation-fenced deletion, retention, and durable cleanup for project snapshots.

  Every destructive path first records the exact canonical and staging object
  inventory in an immutable cleanup intent and the shared storage ownership
  receipt. Only then may reservations, publication claims, snapshot rows, or
  parent projects/workspaces be removed.
  """

  import Ecto.Query, warn: false

  alias Storyarn.Accounts.Scope
  alias Storyarn.Assets.Storage
  alias Storyarn.Assets.StorageCleanupRequest
  alias Storyarn.Assets.StorageCompensation
  alias Storyarn.Billing
  alias Storyarn.Billing.StorageReservation
  alias Storyarn.Platform.Shared.TimeHelpers
  alias Storyarn.Projects
  alias Storyarn.Projects.Persistence.WorkspaceRecord, as: Workspace
  alias Storyarn.Projects.Project
  alias Storyarn.Repo
  alias Storyarn.Versioning.ProjectSnapshot
  alias Storyarn.Versioning.ProjectSnapshotPolicy
  alias Storyarn.Versioning.ProjectSnapshotRestore
  alias Storyarn.Versioning.SnapshotArchiveStorage
  alias Storyarn.Versioning.SnapshotCleanupIntent
  alias Storyarn.Versioning.SnapshotObjectPublicationClaim
  alias Storyarn.Workers.CleanupProjectSnapshotWorker

  # R2 lists at most 1,000 objects per page. Matching that provider bound keeps
  # a maximum snapshot to 21 durable row transitions per delete pass instead
  # of repeatedly validating the 20k-key receipt hundreds of times.
  @batch_size 1_000
  @retention_batch_size 50
  @deletable_user_states ~w(ready failed cancelled)
  @retention_states ~w(ready failed cancelled)
  @expirable_build_states ~w(pending building verifying failed)
  @terminal_job_states ~w(completed discarded cancelled)
  @active_job_states ~w(available scheduled executing retryable)
  @cleanup_worker inspect(CleanupProjectSnapshotWorker)
  @build_worker "Storyarn.Workers.BuildProjectSnapshotWorker"
  @archive_build_queue "snapshot_archives"
  @build_recovery_quarantine_seconds 15 * 60
  @cleanup_job_rescue_after_seconds 3 * 60 * 60
  @maintenance_workers [
    "Storyarn.Workers.ProjectSnapshotRetentionWorker",
    "Storyarn.Workers.ReconcileProjectSnapshotCleanupWorker"
  ]
  @maintenance_job_stale_after_seconds 30 * 60
  @hard_delete_reasons ~w(project_hard_delete workspace_hard_delete)a
  @replayable_cleanup_errors ~w(
    storage_provider_failure namespace_still_owned
    provider_namespace_changed provider_namespace_unavailable
  )
  @provider_namespace_pattern ~r/\A[0-9a-f]{64}\z/
  @replay_expectation_fields [
    :cleanup_intent_id_snapshot,
    :workspace_id_snapshot,
    :project_id_snapshot,
    :project_snapshot_id_snapshot,
    :lifecycle_generation,
    :object_prefix,
    :expected_size_bytes,
    :error_code,
    :reason,
    :retry_count,
    :processing_generation
  ]
  @active_replay_identity_fields [
    :cleanup_intent_id_snapshot,
    :workspace_id_snapshot,
    :project_id_snapshot,
    :project_snapshot_id_snapshot,
    :lifecycle_generation,
    :object_prefix,
    :expected_size_bytes,
    :reason
  ]

  @type retention_candidate :: %{
          snapshot_id: pos_integer(),
          project_id: pos_integer(),
          workspace_id: pos_integer(),
          lifecycle_generation: pos_integer(),
          lifecycle_state: String.t(),
          mode: String.t(),
          origin: String.t(),
          expires_at: DateTime.t()
        }

  @type expired_build_candidate :: %{
          snapshot_id: pos_integer(),
          project_id: pos_integer(),
          workspace_id: pos_integer(),
          lifecycle_generation: pos_integer(),
          lifecycle_state: String.t(),
          build_job_id: pos_integer() | nil,
          build_job_state: String.t() | nil,
          build_job_completed_at: DateTime.t() | nil,
          build_job_discarded_at: DateTime.t() | nil,
          build_job_cancelled_at: DateTime.t() | nil,
          build_state_updated_at: DateTime.t(),
          reservation_id: pos_integer(),
          reservation_generation: pos_integer(),
          reservation_expires_at: DateTime.t()
        }

  @type cleanup_process_result ::
          {:ok,
           :completed
           | :more
           | :already_completed
           | :stale_claim
           | :terminal
           | {:deferred, pos_integer()}}
          | {:error, :storage_provider_failure | term()}

  @doc "Authorizes and durably deletes one user-visible snapshot."
  @spec delete(Scope.t(), Project.t(), pos_integer()) ::
          {:ok, SnapshotCleanupIntent.t()} | {:error, term()}
  def delete(%{user: %{id: user_id}} = scope, %Project{} = project, snapshot_id)
      when is_integer(user_id) and is_integer(snapshot_id) and snapshot_id > 0 do
    case Projects.authorize(scope, project.id, :manage_project) do
      {:ok, %Project{} = authorized_project, _membership} ->
        result =
          Billing.transact_with_workspace_lock(authorized_project.workspace_id, fn _workspace ->
            delete_user_snapshot_locked(authorized_project, snapshot_id, user_id)
          end)

        publish_deleted_snapshot(result, authorized_project.id, snapshot_id)

      {:error, reason} when reason in [:not_found, :unauthorized] ->
        {:error, :unauthorized}

      {:error, reason} ->
        {:error, reason}
    end
  end

  def delete(_scope, _project, _snapshot_id), do: {:error, :invalid_snapshot_delete_request}

  @doc false
  @spec prepare_abandoned_import_snapshot_cleanup_in_transaction(
          ProjectSnapshot.t(),
          pos_integer()
        ) :: {:ok, SnapshotCleanupIntent.t()} | {:error, term()}
  def prepare_abandoned_import_snapshot_cleanup_in_transaction(%ProjectSnapshot{} = snapshot, workspace_id)
      when is_integer(workspace_id) and workspace_id > 0 do
    cond do
      not Repo.in_transaction?() ->
        {:error, :snapshot_cleanup_transaction_required}

      not Billing.workspace_lock_held?(workspace_id) ->
        {:error, :snapshot_cleanup_workspace_lock_required}

      snapshot.lifecycle_state not in @deletable_user_states ->
        {:error, :snapshot_not_deletable}

      true ->
        with :ok <- Billing.settle_expired_snapshot_export_leases_locked(snapshot, workspace_id),
             :ok <- ensure_no_active_snapshot_operations(snapshot.id) do
          create_cleanup_and_delete(snapshot, workspace_id, :abandoned_import, :system)
        end
    end
  end

  def prepare_abandoned_import_snapshot_cleanup_in_transaction(_snapshot, _workspace_id),
    do: {:error, :invalid_snapshot_cleanup_scope}

  @doc false
  @spec prepare_project_hard_delete(Project.t()) ::
          {:ok, [SnapshotCleanupIntent.t()]} | {:error, term()}
  def prepare_project_hard_delete(%Project{} = project) do
    prepare_project_hard_delete(project, :project_hard_delete)
  end

  @doc false
  @spec prepare_workspace_hard_delete(Workspace.t()) ::
          {:ok, [SnapshotCleanupIntent.t()]} | {:error, term()}
  def prepare_workspace_hard_delete(%{id: workspace_id}) when is_integer(workspace_id) do
    if Billing.workspace_lock_held?(workspace_id) do
      prepare_workspace_hard_delete_locked(workspace_id)
    else
      {:error, :snapshot_cleanup_workspace_lock_required}
    end
  end

  def prepare_workspace_hard_delete(_workspace), do: {:error, :invalid_workspace_cleanup_scope}

  defp prepare_workspace_hard_delete_locked(workspace_id) do
    with {:ok, project_ids} <- bounded_workspace_snapshot_project_ids(workspace_id) do
      Enum.reduce_while(project_ids, {:ok, []}, &prepare_workspace_project(workspace_id, &1, &2))
    end
  end

  defp prepare_workspace_project(workspace_id, project_id, {:ok, intents}) do
    project = lock_workspace_project(workspace_id, project_id)

    case prepare_project_hard_delete(project, :workspace_hard_delete) do
      {:ok, project_intents} -> {:cont, {:ok, project_intents ++ intents}}
      {:error, reason} -> {:halt, {:error, reason}}
    end
  end

  @doc false
  @spec publish_committed_cleanup_intents([SnapshotCleanupIntent.t()]) :: :ok
  def publish_committed_cleanup_intents(intents) when is_list(intents) do
    Enum.each(intents, fn
      %SnapshotCleanupIntent{} = intent ->
        emit_cleanup_intent(intent)
        broadcast_snapshot_updated(intent.project_id_snapshot, intent.project_snapshot_id_snapshot)

      _invalid ->
        :ok
    end)

    :ok
  end

  @doc "Lists one bounded, stable page of expired snapshot candidates."
  @spec list_retention_candidates(DateTime.t(), keyword()) :: [retention_candidate()]
  def list_retention_candidates(%DateTime{} = now, opts \\ []) do
    limit = opts |> Keyword.get(:limit, @retention_batch_size) |> min(@retention_batch_size) |> max(1)
    after_id = Keyword.get(opts, :after_id, 0)
    through_id = Keyword.get_lazy(opts, :through_id, &lifecycle_high_watermark/0)

    Repo.all(
      from(snapshot in ProjectSnapshot,
        join: project in Project,
        on: project.id == snapshot.project_id,
        join: workspace in Workspace,
        on: workspace.id == project.workspace_id,
        where:
          snapshot.id > ^after_id and snapshot.id <= ^through_id and
            snapshot.lifecycle_state in ^@retention_states and
            not is_nil(snapshot.expires_at) and snapshot.expires_at <= ^now and
            is_nil(project.deleted_at),
        order_by: [asc: snapshot.id],
        limit: ^limit,
        select: %{
          snapshot_id: snapshot.id,
          project_id: project.id,
          workspace_id: workspace.id,
          lifecycle_generation: snapshot.lifecycle_generation,
          lifecycle_state: snapshot.lifecycle_state,
          mode: snapshot.mode,
          origin: snapshot.origin,
          expires_at: snapshot.expires_at
        }
      )
    )
  end

  @doc false
  @spec delete_retention_candidate(retention_candidate()) ::
          {:ok, SnapshotCleanupIntent.t()} | {:error, term()}
  def delete_retention_candidate(%{} = candidate) do
    case Map.get(candidate, :workspace_id) do
      workspace_id when is_integer(workspace_id) ->
        result =
          Billing.transact_with_workspace_lock(workspace_id, fn _workspace ->
            delete_retention_candidate_locked(candidate, database_clock_now())
          end)

        publish_deleted_snapshot(result, Map.get(candidate, :project_id), Map.get(candidate, :snapshot_id))

      _invalid ->
        {:error, :retention_candidate_changed}
    end
  end

  def delete_retention_candidate(_candidate), do: {:error, :retention_candidate_changed}

  @doc "Lists abandoned builds whose reservation expired and whose owning job cannot still write."
  @spec list_expired_build_candidates(DateTime.t(), keyword()) :: [expired_build_candidate()]
  def list_expired_build_candidates(%DateTime{} = now, opts \\ []) do
    limit = opts |> Keyword.get(:limit, @retention_batch_size) |> min(@retention_batch_size) |> max(1)
    after_id = Keyword.get(opts, :after_id, 0)
    through_id = Keyword.get_lazy(opts, :through_id, &lifecycle_high_watermark/0)
    quiesced_before = DateTime.add(now, -@build_recovery_quarantine_seconds, :second)
    quiescent_job = quiescent_build_job_dynamic(quiesced_before)

    Repo.all(
      from(snapshot in ProjectSnapshot,
        join: project in Project,
        on: project.id == snapshot.project_id,
        join: reservation in StorageReservation,
        on:
          reservation.project_snapshot_id_snapshot == snapshot.id and
            reservation.kind == "snapshot_build" and reservation.status == "active",
        left_join: job in Oban.Job,
        on: job.id == snapshot.build_job_id,
        where:
          snapshot.id > ^after_id and snapshot.id <= ^through_id and
            snapshot.lifecycle_state in ^@expirable_build_states and
            reservation.expires_at <= ^now,
        where: ^quiescent_job,
        order_by: [asc: snapshot.id],
        limit: ^limit,
        select: %{
          snapshot_id: snapshot.id,
          project_id: project.id,
          workspace_id: project.workspace_id,
          lifecycle_generation: snapshot.lifecycle_generation,
          lifecycle_state: snapshot.lifecycle_state,
          build_job_id: snapshot.build_job_id,
          build_job_state: job.state,
          build_job_completed_at: job.completed_at,
          build_job_discarded_at: job.discarded_at,
          build_job_cancelled_at: job.cancelled_at,
          build_state_updated_at: snapshot.state_updated_at,
          reservation_id: reservation.id,
          reservation_generation: reservation.generation,
          reservation_expires_at: reservation.expires_at
        }
      )
    )
  end

  defp quiescent_build_job_dynamic(quiesced_before) do
    missing_job =
      dynamic(
        [snapshot, _project, _reservation, job],
        is_nil(job.id) and snapshot.state_updated_at <= ^quiesced_before
      )

    terminal_job = quiescent_terminal_build_job_dynamic(quiesced_before)

    dynamic([_snapshot, _project, _reservation, _job], ^missing_job or ^terminal_job)
  end

  defp quiescent_terminal_build_job_dynamic(quiesced_before) do
    terminal_timestamp = quiescent_terminal_timestamp_dynamic(quiesced_before)

    matching_queue =
      dynamic(
        [snapshot, _project, _reservation, job],
        snapshot.format_version == 2 and job.queue == ^@archive_build_queue
      )

    dynamic(
      [_snapshot, _project, _reservation, job],
      job.worker == ^@build_worker and ^matching_queue and ^terminal_timestamp
    )
  end

  defp quiescent_terminal_timestamp_dynamic(quiesced_before) do
    dynamic(
      [_snapshot, _project, _reservation, job],
      (job.state == "completed" and job.completed_at <= ^quiesced_before) or
        (job.state == "discarded" and job.discarded_at <= ^quiesced_before) or
        (job.state == "cancelled" and job.cancelled_at <= ^quiesced_before)
    )
  end

  @doc false
  def build_recovery_quarantine_seconds, do: @build_recovery_quarantine_seconds

  @doc false
  @spec delete_expired_build_candidate(expired_build_candidate()) ::
          {:ok, SnapshotCleanupIntent.t()} | {:error, term()}
  def delete_expired_build_candidate(%{} = candidate) do
    do_delete_expired_build_candidate(candidate, :current)
  end

  def delete_expired_build_candidate(_candidate), do: {:error, :expired_build_candidate_changed}

  @doc false
  @spec delete_expired_build_candidate(expired_build_candidate(), String.t()) ::
          {:ok, SnapshotCleanupIntent.t()} | {:error, term()}
  def delete_expired_build_candidate(%{} = candidate, expected_provider_namespace_fingerprint)
      when is_binary(expected_provider_namespace_fingerprint) do
    do_delete_expired_build_candidate(candidate, {:expected, expected_provider_namespace_fingerprint})
  end

  def delete_expired_build_candidate(_candidate, _expected_provider_namespace_fingerprint),
    do: {:error, :expired_build_candidate_changed}

  defp do_delete_expired_build_candidate(%{} = candidate, namespace_expectation) do
    case Map.get(candidate, :workspace_id) do
      workspace_id when is_integer(workspace_id) ->
        result =
          Billing.transact_with_workspace_lock(workspace_id, fn _workspace ->
            delete_expired_build_candidate_locked(candidate, database_clock_now(), namespace_expectation)
          end)

        publish_deleted_snapshot(result, Map.get(candidate, :project_id), Map.get(candidate, :snapshot_id))

      _invalid ->
        {:error, :expired_build_candidate_changed}
    end
  end

  @doc false
  @spec lifecycle_high_watermark() :: non_neg_integer()
  def lifecycle_high_watermark do
    Repo.one(from(snapshot in ProjectSnapshot, select: coalesce(max(snapshot.id), 0)))
  end

  @doc false
  @spec cleanup_recovery_high_watermark() :: non_neg_integer()
  def cleanup_recovery_high_watermark do
    Repo.one(
      from(intent in SnapshotCleanupIntent,
        where: intent.status in ["pending", "processing", "retrying"],
        select: coalesce(max(intent.id), 0)
      )
    )
  end

  @doc false
  @spec discard_stale_maintenance_jobs() :: %{discarded_count: non_neg_integer()}
  def discard_stale_maintenance_jobs do
    now = %{database_clock_now() | microsecond: {0, 6}}
    cutoff = DateTime.add(now, -@maintenance_job_stale_after_seconds, :second)

    {discarded_count, _jobs} =
      Oban.Job
      |> where(
        [job],
        job.worker in ^@maintenance_workers and job.queue == "snapshots_maintenance" and
          job.state == "executing" and
          job.attempted_at < ^cutoff
      )
      |> Repo.update_all(set: [state: "discarded", discarded_at: now])

    %{discarded_count: discarded_count}
  end

  @doc false
  @spec rescue_stale_cleanup_jobs() :: %{discarded_count: non_neg_integer(), rescued_count: non_neg_integer()}
  def rescue_stale_cleanup_jobs do
    now = %{database_clock_now() | microsecond: {0, 6}}
    cutoff = DateTime.add(now, -@cleanup_job_rescue_after_seconds, :second)

    stale_jobs =
      from(job in Oban.Job,
        where:
          job.worker == ^@cleanup_worker and job.queue == "storage_cleanup" and
            job.state == "executing" and
            job.attempted_at < ^cutoff
      )

    {rescued_count, _jobs} =
      stale_jobs
      |> where([job], job.attempt < job.max_attempts)
      |> Repo.update_all(set: [state: "available"])

    {discarded_count, _jobs} =
      stale_jobs
      |> where([job], job.attempt >= job.max_attempts)
      |> Repo.update_all(set: [state: "discarded", discarded_at: now])

    %{rescued_count: rescued_count, discarded_count: discarded_count}
  end

  @doc false
  @spec list_cleanup_recovery_candidates(keyword()) :: [pos_integer()]
  def list_cleanup_recovery_candidates(opts \\ []) do
    limit = opts |> Keyword.get(:limit, @retention_batch_size) |> min(@retention_batch_size) |> max(1)
    after_id = Keyword.get(opts, :after_id, 0)
    through_id = Keyword.get_lazy(opts, :through_id, &cleanup_recovery_high_watermark/0)

    Repo.all(
      from(intent in SnapshotCleanupIntent,
        where:
          intent.id > ^after_id and intent.id <= ^through_id and
            intent.status in ["pending", "processing", "retrying"] and
            fragment(
              "NOT EXISTS (SELECT 1 FROM oban_jobs AS cleanup_job WHERE cleanup_job.worker = ? AND cleanup_job.queue = 'storage_cleanup' AND cleanup_job.state IN ('available', 'scheduled', 'executing', 'retryable') AND (cleanup_job.args->>'intent_id') = (?::text))",
              ^@cleanup_worker,
              intent.id
            ),
        order_by: [asc: intent.id],
        limit: ^limit,
        select: intent.id
      )
    )
  end

  @doc false
  @spec recover_cleanup_intent(pos_integer()) ::
          {:ok, :recovered | :already_active | :already_completed | :terminal} | {:error, term()}
  def recover_cleanup_intent(intent_id) when is_integer(intent_id) and intent_id > 0 do
    Repo.transact(fn -> intent_id |> lock_cleanup_intent() |> recover_locked_cleanup_intent() end)
  end

  def recover_cleanup_intent(_intent_id), do: {:error, :invalid_snapshot_cleanup_intent}

  @doc "Replays a terminal cleanup intent after an operator has remediated its provider failure."
  @spec replay_terminal_cleanup_intent(pos_integer()) ::
          {:ok, SnapshotCleanupIntent.t() | :already_completed | :already_active} | {:error, term()}
  def replay_terminal_cleanup_intent(intent_id) when is_integer(intent_id) and intent_id > 0 do
    result =
      Repo.transact(fn -> intent_id |> lock_cleanup_intent() |> replay_locked_cleanup_intent() end)

    emit_cleanup_replay(result)
  end

  def replay_terminal_cleanup_intent(_intent_id), do: {:error, :invalid_snapshot_cleanup_intent}

  @doc false
  @spec replay_terminal_cleanup_intent(pos_integer(), map()) ::
          {:ok, SnapshotCleanupIntent.t() | :already_completed | :already_active} | {:error, term()}
  def replay_terminal_cleanup_intent(intent_id, expectations)
      when is_integer(intent_id) and intent_id > 0 and is_map(expectations) do
    if exact_replay_expectations?(expectations) do
      result =
        Repo.transact(fn ->
          intent_id
          |> lock_cleanup_intent()
          |> replay_locked_cleanup_intent(expectations)
        end)

      emit_cleanup_replay(result)
    else
      {:error, :invalid_snapshot_cleanup_replay_expectations}
    end
  end

  def replay_terminal_cleanup_intent(_intent_id, _expectations),
    do: {:error, :invalid_snapshot_cleanup_replay_expectations}

  defp exact_replay_expectations?(expectations) do
    expectations
    |> Map.keys()
    |> MapSet.new()
    |> MapSet.equal?(MapSet.new(@replay_expectation_fields))
  end

  defp replay_expectations(intent) do
    %{
      cleanup_intent_id_snapshot: intent.id,
      workspace_id_snapshot: intent.workspace_id_snapshot,
      project_id_snapshot: intent.project_id_snapshot,
      project_snapshot_id_snapshot: intent.project_snapshot_id_snapshot,
      lifecycle_generation: intent.deletion_generation,
      object_prefix: intent.ready_prefix,
      expected_size_bytes: intent.estimated_cleanup_bytes,
      error_code: intent.last_error_code,
      reason: intent.reason,
      retry_count: intent.retry_count,
      processing_generation: intent.processing_generation
    }
  end

  @doc false
  def cleanup_operator_action(intent_id) when is_integer(intent_id) and intent_id > 0 do
    case Repo.get(SnapshotCleanupIntent, intent_id) do
      %SnapshotCleanupIntent{status: "terminal", last_error_code: code}
      when code in @replayable_cleanup_errors ->
        {:ok, :replay}

      %SnapshotCleanupIntent{status: "terminal", last_error_code: code} ->
        {:ok, {:manual_repair_required, code || "missing_error_code"}}

      %SnapshotCleanupIntent{} ->
        {:error, :snapshot_cleanup_intent_not_terminal}

      nil ->
        {:error, :snapshot_cleanup_intent_not_found}
    end
  end

  def cleanup_operator_action(_intent_id), do: {:error, :invalid_snapshot_cleanup_intent}

  defp recover_locked_cleanup_intent(nil), do: {:error, :snapshot_cleanup_intent_not_found}
  defp recover_locked_cleanup_intent(%SnapshotCleanupIntent{status: "completed"}), do: {:ok, :already_completed}
  defp recover_locked_cleanup_intent(%SnapshotCleanupIntent{status: "terminal"}), do: {:ok, :terminal}

  defp recover_locked_cleanup_intent(%SnapshotCleanupIntent{} = intent) do
    ensure_cleanup_job(intent)
  end

  defp replay_locked_cleanup_intent(nil), do: {:error, :snapshot_cleanup_intent_not_found}
  defp replay_locked_cleanup_intent(%SnapshotCleanupIntent{status: "completed"}), do: {:ok, :already_completed}

  defp replay_locked_cleanup_intent(%SnapshotCleanupIntent{status: status})
       when status in ["pending", "processing", "retrying"], do: {:ok, :already_active}

  defp replay_locked_cleanup_intent(%SnapshotCleanupIntent{status: "terminal", last_error_code: code})
       when code not in @replayable_cleanup_errors, do: {:error, {:snapshot_cleanup_manual_repair_required, code}}

  defp replay_locked_cleanup_intent(%SnapshotCleanupIntent{status: "terminal"} = intent) do
    with :ok <- SnapshotCleanupIntent.validate_persisted_inventory(intent),
         :ok <- validate_cleanup_intent_ownership(intent),
         :ok <- validate_current_provider_namespace(intent),
         :ok <- ensure_cleanup_namespace_unowned(intent),
         {:ok, replaying} <- reopen_terminal_cleanup_intent(intent),
         {:ok, _job} <- enqueue_cleanup_replay(replaying.id) do
      {:ok, replaying}
    end
  end

  defp replay_locked_cleanup_intent(nil, _expectations), do: {:error, :snapshot_cleanup_intent_not_found}

  defp replay_locked_cleanup_intent(%SnapshotCleanupIntent{status: "terminal"} = intent, expectations) do
    if replay_expectations(intent) == expectations,
      do: replay_locked_cleanup_intent(intent),
      else: {:error, :snapshot_cleanup_intent_changed}
  end

  defp replay_locked_cleanup_intent(%SnapshotCleanupIntent{status: status} = intent, expectations)
       when status in ["pending", "processing", "retrying"] do
    with true <- active_replay_matches?(intent, expectations),
         :ok <- SnapshotCleanupIntent.validate_persisted_inventory(intent),
         :ok <- validate_cleanup_intent_ownership(intent),
         :ok <- validate_current_provider_namespace(intent) do
      {:ok, :already_active}
    else
      false -> {:error, :snapshot_cleanup_intent_changed}
      {:error, _reason} = error -> error
    end
  end

  defp replay_locked_cleanup_intent(%SnapshotCleanupIntent{}, _expectations),
    do: {:error, :snapshot_cleanup_intent_changed}

  defp active_replay_matches?(intent, expectations) do
    current_identity = intent |> replay_expectations() |> Map.take(@active_replay_identity_fields)
    expected_identity = Map.take(expectations, @active_replay_identity_fields)

    current_identity == expected_identity and expectations.error_code in @replayable_cleanup_errors and
      is_integer(expectations.retry_count) and expectations.retry_count >= 0 and
      intent.retry_count >= expectations.retry_count and is_integer(expectations.processing_generation) and
      expectations.processing_generation >= 0 and
      intent.processing_generation >= expectations.processing_generation
  end

  @doc false
  @spec process_cleanup_intent(pos_integer(), keyword()) :: cleanup_process_result()
  def process_cleanup_intent(intent_id, opts \\ [])

  def process_cleanup_intent(intent_id, opts) when is_integer(intent_id) and intent_id > 0 and is_list(opts) do
    final_attempt? = Keyword.get(opts, :final_attempt?, false) == true
    delete_fun = Keyword.get(opts, :delete_fun, &StorageCompensation.delete_storage_keys_with_evidence/1)
    verify_fun = Keyword.get(opts, :verify_fun, &verify_cleanup_namespace_empty/1)

    if valid_cleanup_process_options?(opts, delete_fun, verify_fun) do
      case claim_cleanup_intent(intent_id) do
        {:ok, claimed} ->
          process_claimed_cleanup(claimed, delete_fun, verify_fun, final_attempt?)

        {:error, reason} ->
          handle_predelete_failure(intent_id, reason, final_attempt?)
      end
    else
      {:error, :invalid_snapshot_cleanup_options}
    end
  end

  def process_cleanup_intent(_intent_id, _opts), do: {:error, :invalid_snapshot_cleanup_intent}

  defp valid_cleanup_process_options?(opts, delete_fun, verify_fun) do
    allowed = [:delete_fun, :final_attempt?, :verify_fun]

    Enum.all?(Keyword.keys(opts), &(&1 in allowed)) and is_function(delete_fun, 1) and
      is_function(verify_fun, 1)
  end

  @doc "Returns operational cleanup backlog gauges without changing quota."
  @spec cleanup_backlog() :: map()
  def cleanup_backlog do
    now = TimeHelpers.now()

    stats =
      Repo.one!(
        from(intent in SnapshotCleanupIntent,
          select: %{
            backlog_count: filter(count(intent.id), intent.status in ["pending", "processing", "retrying"]),
            backlog_bytes:
              type(
                coalesce(
                  filter(sum(intent.estimated_cleanup_bytes), intent.status in ["pending", "processing", "retrying"]),
                  0
                ),
                :integer
              ),
            retry_count:
              type(
                coalesce(filter(sum(intent.retry_count), intent.status in ["pending", "processing", "retrying"]), 0),
                :integer
              ),
            terminal_failures: filter(count(intent.id), intent.status == "terminal"),
            terminal_retry_count:
              type(
                coalesce(filter(sum(intent.retry_count), intent.status == "terminal"), 0),
                :integer
              ),
            repeated_terminal_failures: filter(count(intent.id), intent.status == "terminal" and intent.retry_count > 1),
            oldest_requested_at: filter(min(intent.requested_at), intent.status in ["pending", "processing", "retrying"])
          }
        )
      )

    Map.put(
      stats,
      :oldest_age_seconds,
      if(stats.oldest_requested_at, do: max(DateTime.diff(now, stats.oldest_requested_at, :second), 0), else: 0)
    )
  end

  defp delete_user_snapshot_locked(project, snapshot_id, user_id) do
    with %Project{} <- lock_active_project(project.id, project.workspace_id),
         %ProjectSnapshot{} = snapshot <- lock_snapshot(project.id, snapshot_id),
         true <- snapshot.lifecycle_state in @deletable_user_states,
         :ok <- Billing.settle_expired_snapshot_export_leases_locked(snapshot, project.workspace_id),
         :ok <- ensure_no_active_snapshot_operations(snapshot.id),
         {:ok, intent} <- create_cleanup_and_delete(snapshot, project.workspace_id, :user_delete, {:user, user_id}) do
      {:ok, {:created, intent}}
    else
      nil -> tag_existing_intent(existing_intent_or_error(project.id, snapshot_id))
      false -> {:error, :snapshot_not_deletable}
      {:error, reason} -> {:error, reason}
    end
  end

  defp prepare_project_hard_delete(%Project{id: project_id, workspace_id: workspace_id}, reason)
       when reason in @hard_delete_reasons and is_integer(project_id) and is_integer(workspace_id) do
    if Billing.workspace_lock_held?(workspace_id) do
      prepare_project_hard_delete_locked(project_id, workspace_id, reason)
    else
      {:error, :snapshot_cleanup_workspace_lock_required}
    end
  end

  defp prepare_project_hard_delete(_project, _reason), do: {:error, :invalid_project_cleanup_scope}

  defp prepare_project_hard_delete_locked(project_id, workspace_id, reason) do
    with {:ok, snapshots} <- bounded_project_snapshots(project_id) do
      Enum.reduce_while(snapshots, {:ok, []}, &prepare_hard_delete_snapshot(&1, &2, workspace_id, reason))
    end
  end

  defp prepare_hard_delete_snapshot(snapshot, {:ok, intents}, workspace_id, reason) do
    with :ok <- Billing.settle_expired_snapshot_export_leases_locked(snapshot, workspace_id),
         :ok <- ensure_hard_delete_operations_supported(snapshot),
         {:ok, intent} <- create_cleanup_and_delete(snapshot, workspace_id, reason, :system) do
      {:cont, {:ok, [intent | intents]}}
    else
      {:error, cleanup_reason} -> {:halt, {:error, cleanup_reason}}
    end
  end

  defp bounded_workspace_snapshot_project_ids(workspace_id) do
    limit = hard_delete_snapshot_limit()

    project_ids =
      Repo.all(
        from(snapshot in ProjectSnapshot,
          join: project in Project,
          on: project.id == snapshot.project_id,
          where: project.workspace_id == ^workspace_id,
          order_by: [asc: snapshot.id],
          limit: ^(limit + 1),
          select: project.id
        )
      )

    if length(project_ids) > limit do
      {:error, :snapshot_parent_cleanup_limit_exceeded}
    else
      {:ok, Enum.uniq(project_ids)}
    end
  end

  defp bounded_project_snapshots(project_id) do
    limit = hard_delete_snapshot_limit()

    snapshots =
      Repo.all(
        from(snapshot in ProjectSnapshot,
          where: snapshot.project_id == ^project_id,
          order_by: [asc: snapshot.id],
          limit: ^(limit + 1),
          lock: "FOR UPDATE"
        )
      )

    if length(snapshots) > limit,
      do: {:error, :snapshot_parent_cleanup_limit_exceeded},
      else: {:ok, snapshots}
  end

  defp lock_workspace_project(workspace_id, project_id) do
    Repo.one!(
      from(project in Project,
        where: project.id == ^project_id and project.workspace_id == ^workspace_id,
        lock: "FOR UPDATE"
      )
    )
  end

  defp hard_delete_snapshot_limit do
    :storyarn
    |> Application.fetch_env!(:snapshot_lifecycle)
    |> Keyword.fetch!(:hard_delete_snapshot_limit)
  end

  defp delete_retention_candidate_locked(candidate, now) do
    snapshot_id = Map.get(candidate, :snapshot_id)
    project_id = Map.get(candidate, :project_id)

    with %Project{} = project <- lock_active_project(project_id, Map.get(candidate, :workspace_id)),
         %ProjectSnapshot{} = snapshot <- lock_snapshot(project_id, snapshot_id),
         :ok <- revalidate_retention_candidate(snapshot, project, candidate, now),
         :ok <- Billing.settle_expired_snapshot_export_leases_locked(snapshot, project.workspace_id),
         :ok <- ensure_no_active_snapshot_operations(snapshot.id) do
      snapshot
      |> create_cleanup_and_delete(project.workspace_id, :retention, :system)
      |> tag_created_intent()
    else
      nil -> {:error, :retention_candidate_changed}
      {:error, reason} -> {:error, reason}
    end
  end

  defp delete_expired_build_candidate_locked(candidate, now, namespace_expectation) do
    project_id = Map.get(candidate, :project_id)
    snapshot_id = Map.get(candidate, :snapshot_id)

    with %Project{} = project <- lock_existing_project(project_id, Map.get(candidate, :workspace_id)),
         %ProjectSnapshot{} = snapshot <- lock_snapshot(project_id, snapshot_id),
         %StorageReservation{} = reservation <- lock_build_reservation(snapshot_id, candidate),
         :ok <- revalidate_expired_build_candidate(snapshot, project, reservation, candidate, now),
         :ok <- Billing.settle_expired_snapshot_export_leases_locked(snapshot, project.workspace_id),
         :ok <- ensure_expired_build_operation_supported(snapshot, reservation) do
      snapshot
      |> create_cleanup_and_delete(project.workspace_id, :expired_build, :system, namespace_expectation)
      |> tag_created_intent()
    else
      nil -> {:error, :expired_build_candidate_changed}
      {:error, reason} -> {:error, reason}
    end
  end

  defp revalidate_expired_build_candidate(snapshot, project, reservation, candidate, now) do
    job = lock_build_job(snapshot.build_job_id)
    quiesced_before = DateTime.add(now, -@build_recovery_quarantine_seconds, :second)

    facts = {
      snapshot.id,
      snapshot.project_id,
      project.workspace_id,
      snapshot.lifecycle_generation,
      snapshot.lifecycle_state,
      snapshot.build_job_id,
      job && job.state,
      job && job.completed_at,
      job && job.discarded_at,
      job && job.cancelled_at,
      snapshot.state_updated_at,
      reservation.id,
      reservation.generation,
      reservation.expires_at
    }

    expected = {
      Map.get(candidate, :snapshot_id),
      Map.get(candidate, :project_id),
      Map.get(candidate, :workspace_id),
      Map.get(candidate, :lifecycle_generation),
      Map.get(candidate, :lifecycle_state),
      Map.get(candidate, :build_job_id),
      Map.get(candidate, :build_job_state),
      Map.get(candidate, :build_job_completed_at),
      Map.get(candidate, :build_job_discarded_at),
      Map.get(candidate, :build_job_cancelled_at),
      Map.get(candidate, :build_state_updated_at),
      Map.get(candidate, :reservation_id),
      Map.get(candidate, :reservation_generation),
      Map.get(candidate, :reservation_expires_at)
    }

    with true <- facts == expected,
         true <- snapshot.lifecycle_state in @expirable_build_states,
         true <- reservation.status == "active" and reservation.kind == "snapshot_build",
         true <- DateTime.compare(reservation.expires_at, now) in [:lt, :eq],
         true <- quiescent_build_job?(snapshot, job, quiesced_before) do
      :ok
    else
      _invalid -> {:error, :expired_build_candidate_changed}
    end
  end

  defp quiescent_build_job?(snapshot, nil, quiesced_before) do
    old_enough?(snapshot.state_updated_at, quiesced_before)
  end

  defp quiescent_build_job?(snapshot, %Oban.Job{worker: @build_worker, state: state} = job, quiesced_before)
       when state in @terminal_job_states do
    build_job_queue_matches?(snapshot, job) and
      state
      |> terminal_job_timestamp(job)
      |> old_enough?(quiesced_before)
  end

  defp quiescent_build_job?(_snapshot, _job, _quiesced_before), do: false

  defp build_job_queue_matches?(%ProjectSnapshot{format_version: 2}, %Oban.Job{queue: @archive_build_queue}), do: true

  defp build_job_queue_matches?(_snapshot, _job), do: false

  defp terminal_job_timestamp("completed", job), do: job.completed_at
  defp terminal_job_timestamp("discarded", job), do: job.discarded_at
  defp terminal_job_timestamp("cancelled", job), do: job.cancelled_at

  defp old_enough?(%DateTime{} = timestamp, %DateTime{} = cutoff), do: DateTime.compare(timestamp, cutoff) in [:lt, :eq]

  defp old_enough?(_timestamp, _cutoff), do: false

  defp revalidate_retention_candidate(snapshot, project, candidate, now) do
    facts = {
      snapshot.id,
      snapshot.project_id,
      project.workspace_id,
      snapshot.lifecycle_generation,
      snapshot.lifecycle_state,
      snapshot.mode,
      snapshot.origin,
      snapshot.expires_at
    }

    expected = {
      Map.get(candidate, :snapshot_id),
      Map.get(candidate, :project_id),
      Map.get(candidate, :workspace_id),
      Map.get(candidate, :lifecycle_generation),
      Map.get(candidate, :lifecycle_state),
      Map.get(candidate, :mode),
      Map.get(candidate, :origin),
      Map.get(candidate, :expires_at)
    }

    with true <- facts == expected,
         true <- is_nil(project.deleted_at),
         true <- snapshot.lifecycle_state in @retention_states,
         %DateTime{} = expires_at <- snapshot.expires_at,
         true <- DateTime.compare(expires_at, now) in [:lt, :eq],
         {:ok, policy} <- ProjectSnapshotPolicy.policy(snapshot.origin),
         true <- policy.retention != :explicit_delete,
         :ok <- ensure_supported_mode(snapshot.mode) do
      :ok
    else
      {:error, reason} -> {:error, reason}
      _invalid -> {:error, :retention_candidate_changed}
    end
  end

  defp create_cleanup_and_delete(snapshot, workspace_id, reason, authority),
    do: create_cleanup_and_delete(snapshot, workspace_id, reason, authority, :current)

  defp create_cleanup_and_delete(snapshot, workspace_id, reason, authority, namespace_expectation) do
    with :ok <- ensure_supported_mode(snapshot.mode),
         {:ok, scope} <- snapshot_cleanup_scope(snapshot),
         {:ok, provider_namespace_fingerprint} <-
           cleanup_provider_namespace_fingerprint(namespace_expectation),
         now = TimeHelpers.now(),
         {:ok, deleting} <- snapshot |> ProjectSnapshot.deletion_changeset(now) |> Repo.update(),
         :ok <- release_no_write_build_reservations(deleting),
         owner_token = Ecto.UUID.generate(),
         {:ok, cleanup_request} <-
           StorageCompensation.persist_snapshot_lifecycle_cleanup(
             scope.storage_keys,
             owner_token,
             provider_namespace_fingerprint
           ),
         {:ok, intent} <-
           insert_cleanup_intent(
             deleting,
             workspace_id,
             reason,
             authority,
             scope,
             cleanup_request.id,
             provider_namespace_fingerprint,
             now
           ),
         :ok <- settle_active_build_reservations(deleting, cleanup_request.id, scope),
         :ok <- delete_publication_claim(deleting),
         {:ok, _deleted_snapshot} <- Repo.delete(deleting),
         {:ok, _job} <- enqueue_cleanup(intent.id) do
      {:ok, intent}
    end
  end

  defp snapshot_cleanup_scope(%ProjectSnapshot{format_version: 2} = snapshot) do
    SnapshotArchiveStorage.cleanup_scope_from_snapshot(snapshot)
  end

  defp snapshot_cleanup_scope(%ProjectSnapshot{}), do: {:error, :unsupported_snapshot_cleanup_format}

  defp cleanup_provider_namespace_fingerprint(:current), do: current_provider_namespace_fingerprint()

  defp cleanup_provider_namespace_fingerprint({:expected, expected_fingerprint}) do
    case current_provider_namespace_fingerprint() do
      {:ok, ^expected_fingerprint} -> {:ok, expected_fingerprint}
      {:ok, _different_fingerprint} -> {:error, :snapshot_cleanup_provider_namespace_changed}
      {:error, _reason} = error -> error
    end
  end

  defp insert_cleanup_intent(
         snapshot,
         workspace_id,
         reason,
         authority,
         scope,
         cleanup_request_id,
         provider_namespace_fingerprint,
         now
       ) do
    {authority_kind, actor_id} = authority_fields(authority)

    attrs = %{
      project_snapshot_id: snapshot.id,
      cleanup_request_id: cleanup_request_id,
      workspace_id_snapshot: workspace_id,
      project_id_snapshot: snapshot.project_id,
      project_snapshot_id_snapshot: snapshot.id,
      deletion_generation: snapshot.lifecycle_generation,
      mode: snapshot.mode,
      origin: snapshot.origin,
      reason: Atom.to_string(reason),
      authority_kind: authority_kind,
      authority_actor_id: actor_id,
      ready_prefix: scope.ready_prefix,
      staging_prefix: scope.staging_prefix,
      storage_keys: scope.storage_keys,
      inventory_digest: scope.inventory_digest,
      object_count: length(scope.storage_keys),
      estimated_cleanup_bytes: scope.estimated_cleanup_bytes,
      provider_namespace_fingerprint: provider_namespace_fingerprint,
      requested_at: now
    }

    %SnapshotCleanupIntent{}
    |> SnapshotCleanupIntent.create_changeset(attrs)
    |> Repo.insert()
  end

  defp authority_fields({:user, user_id}), do: {"user", user_id}
  defp authority_fields(:system), do: {"system", nil}

  defp settle_active_build_reservations(snapshot, cleanup_request_id, scope) do
    reservations =
      Repo.all(
        from(reservation in StorageReservation,
          where: reservation.project_snapshot_id_snapshot == ^snapshot.id and reservation.status == "active",
          order_by: [asc: reservation.id],
          lock: "FOR UPDATE"
        )
      )

    Enum.reduce_while(reservations, :ok, fn reservation, :ok ->
      case release_build_reservation(reservation, cleanup_request_id, scope) do
        :ok -> {:cont, :ok}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp release_no_write_build_reservations(snapshot) do
    reservations =
      Repo.all(
        from(reservation in StorageReservation,
          where:
            reservation.project_snapshot_id_snapshot == ^snapshot.id and
              reservation.status == "active" and reservation.kind == "snapshot_build" and
              is_nil(reservation.storage_started_at),
          order_by: [asc: reservation.id],
          lock: "FOR UPDATE"
        )
      )

    Enum.reduce_while(reservations, :ok, fn reservation, :ok ->
      with :ok <- prepare_publication_claim_for_release(reservation),
           {:ok, _released} <-
             Billing.release_storage_reservation(
               reservation.id,
               reservation.lease_token,
               reservation.generation,
               %{
                 reason: "snapshot_deleted_before_storage_started",
                 cleanup_status: "not_required",
                 cleanup_proof: %{
                   type: "storage_not_started",
                   storage_namespace: reservation.storage_namespace
                 }
               }
             ) do
        {:cont, :ok}
      else
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp release_build_reservation(
         %StorageReservation{kind: "snapshot_build", storage_started_at: %DateTime{}} = reservation,
         cleanup_request_id,
         scope
       ) do
    with :ok <- prepare_publication_claim_for_release(reservation) do
      attrs = %{
        reason: "snapshot_deleted",
        cleanup_status: "owned",
        cleanup_request_id: cleanup_request_id,
        cleanup_scope: Map.put(scope, :cleanup_request_id, cleanup_request_id)
      }

      case Billing.release_storage_reservation(
             reservation.id,
             reservation.lease_token,
             reservation.generation,
             attrs
           ) do
        {:ok, _released} -> :ok
        {:error, reason} -> {:error, reason}
      end
    end
  end

  defp release_build_reservation(_reservation, _cleanup_request_id, _scope),
    do: {:error, :snapshot_active_operation_blocks_deletion}

  defp prepare_publication_claim_for_release(%StorageReservation{id: reservation_id, storage_started_at: nil}) do
    case lock_claim_by_reservation(reservation_id) do
      nil -> :ok
      %SnapshotObjectPublicationClaim{status: "staging"} = claim -> delete_claim(claim)
      _claim -> {:error, :snapshot_publication_claim_conflict}
    end
  end

  defp prepare_publication_claim_for_release(%StorageReservation{id: reservation_id}) do
    case lock_claim_by_reservation(reservation_id) do
      %SnapshotObjectPublicationClaim{status: "poisoned"} ->
        :ok

      %SnapshotObjectPublicationClaim{status: status} = claim
      when status in ["staging", "staged", "publishing"] ->
        case claim |> SnapshotObjectPublicationClaim.status_changeset("poisoned") |> Repo.update() do
          {:ok, _claim} -> :ok
          {:error, reason} -> {:error, reason}
        end

      %SnapshotObjectPublicationClaim{status: "published"} ->
        :ok

      nil ->
        {:error, :snapshot_publication_claim_missing}
    end
  end

  defp delete_publication_claim(snapshot) do
    case Repo.one(
           from(claim in SnapshotObjectPublicationClaim,
             where: claim.object_prefix == ^snapshot.object_prefix,
             lock: "FOR UPDATE"
           )
         ) do
      nil -> :ok
      claim -> delete_claim(claim)
    end
  end

  defp delete_claim(claim) do
    case Repo.delete(claim) do
      {:ok, _claim} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp lock_claim_by_reservation(reservation_id) do
    Repo.one(
      from(claim in SnapshotObjectPublicationClaim,
        where: claim.storage_reservation_id_snapshot == ^reservation_id,
        lock: "FOR UPDATE"
      )
    )
  end

  defp ensure_no_active_snapshot_operations(snapshot_id) do
    if active_snapshot_reservation?(snapshot_id) or active_snapshot_restore?(snapshot_id),
      do: {:error, :snapshot_active_operation_blocks_deletion},
      else: :ok
  end

  defp active_snapshot_reservation?(snapshot_id) do
    Repo.exists?(
      from(reservation in StorageReservation,
        where: reservation.project_snapshot_id_snapshot == ^snapshot_id and reservation.status == "active"
      )
    )
  end

  defp active_snapshot_restore?(snapshot_id) do
    Repo.exists?(
      from(restore in ProjectSnapshotRestore,
        where:
          restore.project_snapshot_id == ^snapshot_id and
            restore.status in ^ProjectSnapshotRestore.active_statuses()
      )
    )
  end

  defp ensure_hard_delete_operations_supported(%ProjectSnapshot{} = snapshot) do
    active_reservations =
      Repo.all(
        from(reservation in StorageReservation,
          where: reservation.project_snapshot_id_snapshot == ^snapshot.id and reservation.status == "active",
          order_by: [asc: reservation.id],
          lock: "FOR UPDATE"
        )
      )

    if active_reservations == [] and not active_snapshot_restore?(snapshot.id),
      do: :ok,
      else: {:error, :snapshot_active_operation_blocks_deletion}
  end

  defp ensure_expired_build_operation_supported(%ProjectSnapshot{} = snapshot, %StorageReservation{
         id: expected_reservation_id
       }) do
    active_reservations =
      Repo.all(
        from(reservation in StorageReservation,
          where: reservation.project_snapshot_id_snapshot == ^snapshot.id and reservation.status == "active",
          order_by: [asc: reservation.id],
          lock: "FOR UPDATE"
        )
      )

    case active_reservations do
      [%StorageReservation{id: ^expected_reservation_id, kind: "snapshot_build"}] ->
        if active_snapshot_restore?(snapshot.id),
          do: {:error, :snapshot_active_operation_blocks_deletion},
          else: :ok

      _reservations ->
        {:error, :snapshot_active_operation_blocks_deletion}
    end
  end

  defp ensure_supported_mode("full"), do: :ok
  defp ensure_supported_mode(_mode), do: {:error, :unsupported_snapshot_mode}

  defp claim_cleanup_intent(intent_id) do
    Repo.transact(fn ->
      now = database_clock_now()
      intent_id |> lock_cleanup_intent() |> claim_locked_cleanup_intent(now)
    end)
  end

  defp database_clock_now do
    %Postgrex.Result{rows: [[now]]} = Repo.query!("SELECT clock_timestamp()")
    DateTime.truncate(now, :second)
  end

  defp claim_locked_cleanup_intent(nil, _now), do: {:error, :snapshot_cleanup_intent_not_found}

  defp claim_locked_cleanup_intent(%SnapshotCleanupIntent{status: "completed"}, _now), do: {:ok, :already_completed}

  defp claim_locked_cleanup_intent(%SnapshotCleanupIntent{status: "terminal"}, _now), do: {:ok, :terminal}

  defp claim_locked_cleanup_intent(%SnapshotCleanupIntent{} = intent, now) do
    with :ok <- SnapshotCleanupIntent.validate_persisted_inventory(intent),
         :ok <- validate_cleanup_intent_ownership(intent) do
      if delete_pass_deferred?(intent, now) do
        {:ok, {:deferred, seconds_until(intent.next_delete_pass_at, now)}}
      else
        intent |> SnapshotCleanupIntent.processing_changeset(now) |> Repo.update()
      end
    end
  end

  defp delete_pass_deferred?(%SnapshotCleanupIntent{next_delete_pass_at: %DateTime{} = next_at}, now),
    do: DateTime.after?(next_at, now)

  defp delete_pass_deferred?(_intent, _now), do: false

  defp seconds_until(next_at, now), do: max(DateTime.diff(next_at, now, :second), 1)

  defp validate_cleanup_intent_ownership(intent) do
    request =
      Repo.one(
        from(request in StorageCleanupRequest,
          where: request.id == ^intent.cleanup_request_id,
          lock: "FOR SHARE"
        )
      )

    case request do
      %StorageCleanupRequest{
        owner_kind: "snapshot_lifecycle",
        owner_token: owner_token,
        storage_keys: storage_keys,
        provider_namespace_fingerprint: provider_namespace_fingerprint
      }
      when is_binary(owner_token) and storage_keys == intent.storage_keys and
             provider_namespace_fingerprint == intent.provider_namespace_fingerprint ->
        :ok

      _invalid ->
        {:error, :invalid_snapshot_cleanup_ownership}
    end
  end

  defp process_claimed_cleanup(:already_completed, _delete_fun, _verify_fun, _final_attempt?),
    do: {:ok, :already_completed}

  defp process_claimed_cleanup(:terminal, _delete_fun, _verify_fun, _final_attempt?), do: {:ok, :terminal}

  defp process_claimed_cleanup({:deferred, seconds}, _delete_fun, _verify_fun, _final_attempt?),
    do: {:ok, {:deferred, seconds}}

  defp process_claimed_cleanup(%SnapshotCleanupIntent{} = intent, delete_fun, verify_fun, final_attempt?) do
    batch = Enum.take(intent.remaining_storage_keys, @batch_size)

    with :ok <- validate_cleanup_intent_ownership(intent),
         :ok <- validate_current_provider_namespace(intent),
         :ok <- ensure_cleanup_namespace_unowned(intent) do
      case StorageCompensation.delete_cleanup_request_keys(intent.cleanup_request_id, batch, delete_fun: delete_fun) do
        :ok ->
          finish_verified_batch(intent, batch, verify_fun, final_attempt?)

        {:deferred, seconds} ->
          emit_cleanup_stop(intent, :deferred, 0)
          {:ok, {:deferred, seconds}}

        {:error, failed_keys} ->
          finish_failed_batch(intent, batch, failed_keys, final_attempt?)
      end
    else
      {:error, reason} ->
        handle_predelete_failure(intent, reason, final_attempt?)
    end
  end

  defp finish_verified_batch(intent, batch, verify_fun, final_attempt?) do
    if batch == intent.remaining_storage_keys do
      case safe_verify(verify_fun, intent) do
        :ok -> finish_successful_batch(intent, batch)
        {:error, _reason} -> finish_failed_batch(intent, batch, batch, final_attempt?)
      end
    else
      finish_successful_batch(intent, batch)
    end
  end

  defp verify_cleanup_namespace_empty(intent) do
    with :ok <- validate_current_provider_namespace(intent),
         {:ok, remaining_keys} <- list_cleanup_namespace_keys(intent),
         :ok <- validate_listed_cleanup_keys(remaining_keys, intent.storage_keys) do
      delete_listed_cleanup_keys(remaining_keys, intent)
    end
  end

  defp delete_listed_cleanup_keys([], _intent), do: :ok

  defp delete_listed_cleanup_keys(keys, intent) do
    with :ok <- validate_cleanup_intent_ownership(intent),
         :ok <- validate_current_provider_namespace(intent) do
      case StorageCompensation.delete_storage_keys(keys) do
        :ok -> {:error, :snapshot_cleanup_verification_recheck_required}
        {:error, _failed_keys} -> {:error, :snapshot_cleanup_verification_delete_failed}
      end
    end
  end

  defp list_cleanup_namespace_keys(intent) do
    Enum.reduce_while([intent.ready_prefix, intent.staging_prefix], {:ok, []}, fn prefix, {:ok, keys} ->
      prefix
      |> then(&Storage.list_prefix(&1 <> "/", limit: @batch_size))
      |> reduce_cleanup_inventory_response(keys)
    end)
  end

  defp reduce_cleanup_inventory_response({:ok, %{objects: [], cursor: nil}}, keys), do: {:cont, {:ok, keys}}

  defp reduce_cleanup_inventory_response({:ok, %{objects: [], cursor: _invalid_cursor}}, _keys),
    do: {:halt, {:error, :invalid_snapshot_cleanup_inventory_response}}

  defp reduce_cleanup_inventory_response({:ok, %{objects: objects, cursor: cursor}}, keys)
       when is_list(objects) and objects != [] and (is_nil(cursor) or is_binary(cursor)) do
    case listed_storage_keys(objects) do
      {:ok, listed_keys} -> {:cont, {:ok, listed_keys ++ keys}}
      {:error, reason} -> {:halt, {:error, reason}}
    end
  end

  defp reduce_cleanup_inventory_response({:error, reason}, _keys), do: {:halt, {:error, reason}}

  defp reduce_cleanup_inventory_response(_invalid, _keys),
    do: {:halt, {:error, :invalid_snapshot_cleanup_inventory_response}}

  defp listed_storage_keys(objects) do
    Enum.reduce_while(objects, {:ok, []}, fn
      %{key: key}, {:ok, keys} when is_binary(key) -> {:cont, {:ok, [key | keys]}}
      _invalid, _keys -> {:halt, {:error, :invalid_snapshot_cleanup_inventory_response}}
    end)
  end

  defp validate_listed_cleanup_keys(listed_keys, owned_keys) do
    owned = MapSet.new(owned_keys)

    if Enum.all?(listed_keys, &MapSet.member?(owned, &1)),
      do: :ok,
      else: {:error, :snapshot_cleanup_namespace_contains_unowned_objects}
  end

  defp safe_verify(verify_fun, intent) do
    case verify_fun.(intent) do
      :ok -> :ok
      {:error, reason} -> {:error, reason}
      _invalid -> {:error, :invalid_snapshot_cleanup_verification_result}
    end
  rescue
    exception -> {:error, {:snapshot_cleanup_verification_raised, exception.__struct__}}
  catch
    kind, _reason -> {:error, {:snapshot_cleanup_verification_caught, kind}}
  end

  defp handle_predelete_failure(intent_or_id, reason, true)
       when reason in [
              :invalid_snapshot_cleanup_inventory,
              :invalid_snapshot_cleanup_ownership,
              :snapshot_cleanup_namespace_still_owned,
              :snapshot_cleanup_provider_namespace_changed,
              :snapshot_cleanup_provider_namespace_unavailable
            ] do
    terminalize_predelete_failure(intent_or_id, reason)
  end

  defp handle_predelete_failure(_intent_or_id, reason, _final_attempt?), do: {:error, reason}

  defp terminalize_predelete_failure(intent_or_id, reason) do
    result =
      Repo.transact(fn ->
        intent_or_id
        |> cleanup_intent_id()
        |> lock_cleanup_intent()
        |> terminalize_locked_predelete_failure(intent_or_id, reason)
      end)

    case result do
      {:ok, %SnapshotCleanupIntent{} = intent} ->
        emit_cleanup_stop(intent, :terminal, 0)
        {:ok, :terminal}

      {:ok, status} when status in [:already_completed, :stale_claim, :terminal] ->
        {:ok, status}

      {:error, terminal_reason} ->
        {:error, terminal_reason}
    end
  end

  defp cleanup_intent_id(%SnapshotCleanupIntent{id: id}), do: id
  defp cleanup_intent_id(intent_id), do: intent_id

  defp terminalize_locked_predelete_failure(nil, _intent_or_id, _reason), do: {:error, :snapshot_cleanup_intent_not_found}

  defp terminalize_locked_predelete_failure(%SnapshotCleanupIntent{status: "completed"}, _intent_or_id, _reason),
    do: {:ok, :already_completed}

  defp terminalize_locked_predelete_failure(%SnapshotCleanupIntent{status: "terminal"}, _intent_or_id, _reason),
    do: {:ok, :terminal}

  defp terminalize_locked_predelete_failure(%SnapshotCleanupIntent{} = intent, intent_or_id, reason) do
    with :ok <- validate_terminal_cleanup_claim(intent, intent_or_id),
         :ok <- revalidate_predelete_failure(intent, reason) do
      intent
      |> SnapshotCleanupIntent.terminal_predelete_changeset(predelete_error_code(reason))
      |> Repo.update()
    end
  end

  defp validate_terminal_cleanup_claim(_current, intent_id) when is_integer(intent_id), do: :ok

  defp validate_terminal_cleanup_claim(current, %SnapshotCleanupIntent{} = claimed) do
    if current_cleanup_claim?(current, claimed), do: :ok, else: {:ok, :stale_claim}
  end

  defp revalidate_predelete_failure(intent, :invalid_snapshot_cleanup_inventory) do
    case SnapshotCleanupIntent.validate_persisted_inventory(intent) do
      {:error, :invalid_snapshot_cleanup_inventory} -> :ok
      :ok -> {:error, :snapshot_cleanup_failure_changed}
    end
  end

  defp revalidate_predelete_failure(intent, :invalid_snapshot_cleanup_ownership) do
    case validate_cleanup_intent_ownership(intent) do
      {:error, :invalid_snapshot_cleanup_ownership} -> :ok
      :ok -> {:error, :snapshot_cleanup_failure_changed}
    end
  end

  defp revalidate_predelete_failure(intent, :snapshot_cleanup_namespace_still_owned) do
    case ensure_cleanup_namespace_unowned(intent) do
      {:error, :snapshot_cleanup_namespace_still_owned} -> :ok
      :ok -> {:error, :snapshot_cleanup_failure_changed}
    end
  end

  defp revalidate_predelete_failure(intent, :snapshot_cleanup_provider_namespace_changed) do
    revalidate_provider_namespace_failure(intent, :snapshot_cleanup_provider_namespace_changed)
  end

  defp revalidate_predelete_failure(intent, :snapshot_cleanup_provider_namespace_unavailable) do
    revalidate_provider_namespace_failure(intent, :snapshot_cleanup_provider_namespace_unavailable)
  end

  defp revalidate_provider_namespace_failure(intent, reason) do
    case validate_current_provider_namespace(intent) do
      {:error, ^reason} -> :ok
      _changed -> {:error, :snapshot_cleanup_failure_changed}
    end
  end

  defp predelete_error_code(:invalid_snapshot_cleanup_inventory), do: "invalid_inventory"
  defp predelete_error_code(:invalid_snapshot_cleanup_ownership), do: "invalid_ownership"
  defp predelete_error_code(:snapshot_cleanup_namespace_still_owned), do: "namespace_still_owned"
  defp predelete_error_code(:snapshot_cleanup_provider_namespace_changed), do: "provider_namespace_changed"

  defp predelete_error_code(:snapshot_cleanup_provider_namespace_unavailable), do: "provider_namespace_unavailable"

  defp validate_current_provider_namespace(intent) do
    case current_provider_namespace_fingerprint() do
      {:ok, fingerprint} when fingerprint == intent.provider_namespace_fingerprint ->
        :ok

      {:ok, _different_fingerprint} ->
        {:error, :snapshot_cleanup_provider_namespace_changed}

      {:error, :snapshot_cleanup_provider_namespace_unavailable} = error ->
        error
    end
  end

  defp current_provider_namespace_fingerprint do
    case Storage.namespace_fingerprint() do
      {:ok, fingerprint} when is_binary(fingerprint) ->
        if Regex.match?(@provider_namespace_pattern, fingerprint),
          do: {:ok, fingerprint},
          else: {:error, :snapshot_cleanup_provider_namespace_unavailable}

      _unavailable ->
        {:error, :snapshot_cleanup_provider_namespace_unavailable}
    end
  rescue
    _exception -> {:error, :snapshot_cleanup_provider_namespace_unavailable}
  catch
    _kind, _reason -> {:error, :snapshot_cleanup_provider_namespace_unavailable}
  end

  defp ensure_cleanup_namespace_unowned(intent) do
    snapshot_owner? =
      Repo.exists?(
        from(snapshot in ProjectSnapshot,
          where: snapshot.object_prefix == ^intent.ready_prefix
        )
      )

    publication_owner? =
      Repo.exists?(
        from(claim in SnapshotObjectPublicationClaim,
          where: claim.object_prefix == ^intent.ready_prefix
        )
      )

    if snapshot_owner? or publication_owner?,
      do: {:error, :snapshot_cleanup_namespace_still_owned},
      else: :ok
  end

  defp finish_successful_batch(intent, batch) do
    result = Repo.transact(fn -> update_successful_batch(intent, batch) end)
    handle_successful_batch_result(result, length(batch))
  end

  defp update_successful_batch(claimed, batch) do
    current = lock_cleanup_intent(claimed.id)

    cond do
      is_nil(current) ->
        {:error, :snapshot_cleanup_intent_not_found}

      current.status == "completed" ->
        {:ok, :already_completed}

      current.status == "terminal" ->
        {:ok, :terminal}

      not current_cleanup_claim?(current, claimed) ->
        {:ok, :stale_claim}

      current.remaining_storage_keys -- batch == [] ->
        finish_delete_pass(current)

      true ->
        remaining = current.remaining_storage_keys -- batch
        current |> SnapshotCleanupIntent.progress_changeset(remaining) |> Repo.update()
    end
  end

  defp finish_delete_pass(current) do
    now = database_clock_now()

    if current.completed_delete_passes + 1 < current.required_delete_passes do
      with {:ok, _updated} <- current |> SnapshotCleanupIntent.next_delete_pass_changeset() |> Repo.update() do
        {:ok, Repo.get!(SnapshotCleanupIntent, current.id)}
      end
    else
      current |> SnapshotCleanupIntent.completed_changeset(now) |> Repo.update()
    end
  end

  defp current_cleanup_claim?(current, claimed) do
    current.status == "processing" and
      current.processing_generation == claimed.processing_generation and
      current.completed_delete_passes == claimed.completed_delete_passes and
      current.retry_count == claimed.retry_count and
      current.remaining_storage_keys == claimed.remaining_storage_keys
  end

  defp handle_successful_batch_result({:ok, %SnapshotCleanupIntent{status: "completed"} = intent}, deleted_count) do
    emit_cleanup_stop(intent, :completed, deleted_count)
    {:ok, :completed}
  end

  defp handle_successful_batch_result(
         {:ok,
          %SnapshotCleanupIntent{status: "retrying", next_delete_pass_at: %DateTime{} = next_delete_pass_at} = intent},
         deleted_count
       ) do
    emit_cleanup_stop(intent, :deferred, deleted_count)
    {:ok, {:deferred, seconds_until(next_delete_pass_at, database_clock_now())}}
  end

  defp handle_successful_batch_result({:ok, %SnapshotCleanupIntent{} = intent}, deleted_count) do
    emit_cleanup_stop(intent, :more, deleted_count)
    {:ok, :more}
  end

  defp handle_successful_batch_result({:ok, result}, _deleted_count)
       when result in [:already_completed, :stale_claim, :terminal], do: {:ok, result}

  defp handle_successful_batch_result({:error, reason}, _deleted_count), do: {:error, reason}

  defp finish_failed_batch(intent, batch, failed_keys, final_attempt?) do
    failed_set = MapSet.new(failed_keys)
    successful = Enum.reject(batch, &MapSet.member?(failed_set, &1))

    result = Repo.transact(fn -> update_failed_batch(intent, successful, final_attempt?) end)
    handle_failed_batch_result(result, final_attempt?, length(successful))
  end

  defp update_failed_batch(claimed, successful, final_attempt?) do
    current = lock_cleanup_intent(claimed.id)

    cond do
      is_nil(current) -> {:error, :snapshot_cleanup_intent_not_found}
      current.status == "completed" -> {:ok, :already_completed}
      current.status == "terminal" -> {:ok, :terminal}
      not current_cleanup_claim?(current, claimed) -> {:ok, :stale_claim}
      true -> update_retry_inventory(current, successful, final_attempt?)
    end
  end

  defp update_retry_inventory(current, successful, final_attempt?) do
    remaining = current.remaining_storage_keys -- successful
    code = "storage_provider_failure"

    changeset =
      if final_attempt?,
        do: SnapshotCleanupIntent.terminal_changeset(current, remaining, code),
        else: SnapshotCleanupIntent.retry_changeset(current, remaining, code)

    Repo.update(changeset)
  end

  defp handle_failed_batch_result({:ok, result}, _final_attempt?, _deleted_count)
       when result in [:already_completed, :stale_claim, :terminal], do: {:ok, result}

  defp handle_failed_batch_result({:ok, intent}, final_attempt?, deleted_count) do
    emit_cleanup_stop(intent, if(final_attempt?, do: :terminal, else: :retrying), deleted_count)

    if final_attempt?,
      do: {:ok, :terminal},
      else: {:error, :storage_provider_failure}
  end

  defp handle_failed_batch_result({:error, reason}, _final_attempt?, _deleted_count), do: {:error, reason}

  defp existing_intent_or_error(project_id, snapshot_id) do
    case Repo.one(
           from(intent in SnapshotCleanupIntent,
             where:
               intent.project_id_snapshot == ^project_id and
                 intent.project_snapshot_id_snapshot == ^snapshot_id
           )
         ) do
      %SnapshotCleanupIntent{} = intent -> {:ok, intent}
      nil -> {:error, :project_snapshot_not_found}
    end
  end

  defp enqueue_cleanup(intent_id) do
    %{intent_id: intent_id}
    |> CleanupProjectSnapshotWorker.new()
    |> Oban.insert()
  end

  defp enqueue_cleanup_replay(intent_id) do
    %{intent_id: intent_id, replay_token: Ecto.UUID.generate()}
    |> CleanupProjectSnapshotWorker.new()
    |> Oban.insert()
    |> case do
      {:ok, %Oban.Job{conflict?: false} = job} -> {:ok, job}
      {:ok, %Oban.Job{conflict?: true}} -> {:error, :snapshot_cleanup_replay_conflict}
      {:error, reason} -> {:error, reason}
    end
  end

  defp ensure_cleanup_job(intent) do
    if cleanup_job_active?(intent.id) do
      {:ok, :already_active}
    else
      case enqueue_cleanup(intent.id) do
        {:ok, _job} -> {:ok, :recovered}
        {:error, reason} -> {:error, reason}
      end
    end
  end

  defp cleanup_job_active?(intent_id) do
    intent_id = Integer.to_string(intent_id)

    Repo.exists?(
      from(job in Oban.Job,
        where:
          job.worker == ^@cleanup_worker and job.queue == "storage_cleanup" and
            job.state in ^@active_job_states and
            fragment("(?->>'intent_id') = ?", job.args, ^intent_id)
      )
    )
  end

  defp reopen_terminal_cleanup_intent(intent) do
    intent
    |> Ecto.Changeset.change(
      status: "retrying",
      last_error_code: "operator_replay",
      completed_at: nil,
      terminal_at: nil
    )
    |> Repo.update()
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

  defp lock_existing_project(project_id, workspace_id) do
    Repo.one(
      from(project in Project,
        where: project.id == ^project_id and project.workspace_id == ^workspace_id,
        lock: "FOR UPDATE"
      )
    )
  end

  defp lock_snapshot(project_id, snapshot_id) do
    Repo.one(
      from(snapshot in ProjectSnapshot,
        where: snapshot.project_id == ^project_id and snapshot.id == ^snapshot_id,
        lock: "FOR UPDATE"
      )
    )
  end

  defp lock_build_reservation(snapshot_id, candidate) do
    Repo.one(
      from(reservation in StorageReservation,
        where:
          reservation.id == ^Map.get(candidate, :reservation_id) and
            reservation.project_snapshot_id_snapshot == ^snapshot_id,
        lock: "FOR UPDATE"
      )
    )
  end

  defp lock_build_job(nil), do: nil

  defp lock_build_job(job_id) do
    Repo.one(from(job in Oban.Job, where: job.id == ^job_id, lock: "FOR UPDATE"))
  end

  defp lock_cleanup_intent(intent_id) do
    Repo.one(
      from(intent in SnapshotCleanupIntent,
        where: intent.id == ^intent_id,
        lock: "FOR UPDATE"
      )
    )
  end

  defp tag_existing_intent({:ok, %SnapshotCleanupIntent{} = intent}), do: {:ok, {:existing, intent}}
  defp tag_existing_intent(result), do: result

  defp tag_created_intent({:ok, %SnapshotCleanupIntent{} = intent}), do: {:ok, {:created, intent}}
  defp tag_created_intent(result), do: result

  defp publish_deleted_snapshot({:ok, {:created, %SnapshotCleanupIntent{} = intent}}, project_id, snapshot_id) do
    emit_cleanup_intent(intent)
    broadcast_snapshot_updated(project_id, snapshot_id)
    {:ok, intent}
  end

  defp publish_deleted_snapshot({:ok, {:existing, %SnapshotCleanupIntent{} = intent}}, _project_id, _snapshot_id),
    do: {:ok, intent}

  defp publish_deleted_snapshot(result, _project_id, _snapshot_id), do: result

  defp broadcast_snapshot_updated(project_id, snapshot_id) do
    Phoenix.PubSub.broadcast(
      Storyarn.PubSub,
      "project_snapshots:#{project_id}",
      {:project_snapshot_updated, snapshot_id}
    )
  end

  defp emit_cleanup_intent(intent) do
    :telemetry.execute(
      [:storyarn, :snapshot, :cleanup, :intent],
      %{count: 1, object_count: intent.object_count, estimated_cleanup_bytes: intent.estimated_cleanup_bytes},
      %{reason: intent.reason, mode: intent.mode, authority_kind: intent.authority_kind}
    )
  end

  defp emit_cleanup_stop(intent, status, deleted_count) do
    :telemetry.execute(
      [:storyarn, :snapshot, :cleanup, :stop],
      %{
        deleted_count: deleted_count,
        retry_count: if(status == :retrying, do: 1, else: 0),
        terminal_failure_count: if(status == :terminal, do: 1, else: 0)
      },
      %{status: status, reason: intent.reason, error_code: intent.last_error_code || "none"}
    )
  end

  defp emit_cleanup_replay({:ok, %SnapshotCleanupIntent{} = intent} = result) do
    :telemetry.execute(
      [:storyarn, :snapshot, :cleanup, :replay],
      %{count: 1},
      %{status: :enqueued, reason: intent.reason}
    )

    result
  end

  defp emit_cleanup_replay(result), do: result
end
