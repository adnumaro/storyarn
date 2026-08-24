defmodule Storyarn.Versioning.ProjectSnapshotRestoreLifecycle do
  @moduledoc """
  Durable request and execution lifecycle for exact full-project restores.

  This module owns authorization, idempotency, delivery ownership and
  generation fencing. Archive reading and project materialization live behind
  the executor callback and aren't part of the lifecycle contract.
  """

  import Ecto.Query

  alias Storyarn.Accounts.Scope
  alias Storyarn.Assets.StorageKeyLock
  alias Storyarn.Billing
  alias Storyarn.Billing.StorageReservation
  alias Storyarn.Collaboration
  alias Storyarn.Platform.Shared.TimeHelpers
  alias Storyarn.Projects
  alias Storyarn.Projects.Project
  alias Storyarn.Repo
  alias Storyarn.Versioning.ProjectSnapshot
  alias Storyarn.Versioning.ProjectSnapshotRestore
  alias Storyarn.Versioning.ProjectSnapshotRestoreExecutor
  alias Storyarn.Versioning.RestorePolicy
  alias Storyarn.Workers.RestoreProjectSnapshotWorker

  @restore_worker inspect(RestoreProjectSnapshotWorker)
  @restore_queue "snapshot_restores"
  @sha256 ~r/\A[0-9a-f]{64}\z/
  @terminal_statuses ~w(completed failed)
  @phase_successors %{
    "preflight" => "staging",
    "staging" => "materializing",
    "materializing" => "verifying"
  }
  @generic_failure_message "The project snapshot restore could not be completed."
  @settlement_snooze_seconds 30
  @delivery_recovery_batch_size 50
  @delivery_recovery_quarantine_seconds 2 * 60 * 60
  @active_restore_statuses ~w(queued running retrying)
  @terminal_delivery_job_states ~w(cancelled completed discarded)

  defguardp is_positive_integer(value) when is_integer(value) and value > 0

  @type perform_result ::
          {:ok, ProjectSnapshotRestore.t()}
          | {:retry, atom()}
          | {:snooze, pos_integer()}
          | {:discard, atom()}

  @type abandoned_delivery_candidate :: %{
          restore_id: pos_integer(),
          workspace_id: pos_integer(),
          project_id: pos_integer(),
          restore_status: String.t(),
          restore_phase: String.t(),
          restore_generation: pos_integer(),
          restore_attempt: pos_integer(),
          restore_state_updated_at: DateTime.t(),
          restore_oban_job_id: pos_integer() | nil,
          restore_reservation_id: pos_integer() | nil,
          restore_reservation_generation: pos_integer() | nil,
          restore_reservation_lease_token: Ecto.UUID.t() | nil,
          job_id: pos_integer() | nil,
          job_state: String.t() | nil,
          job_attempt: non_neg_integer() | nil,
          job_max_attempts: pos_integer() | nil,
          job_attempted_at: DateTime.t() | nil,
          job_completed_at: DateTime.t() | nil,
          job_discarded_at: DateTime.t() | nil,
          job_cancelled_at: DateTime.t() | nil,
          reservation_id: pos_integer() | nil,
          reservation_status: String.t() | nil,
          reservation_generation: pos_integer() | nil,
          reservation_lease_token: Ecto.UUID.t() | nil,
          reservation_storage_started_at: DateTime.t() | nil,
          reservation_cleanup_inventory_digest: String.t() | nil,
          reservation_cleanup_inventory_count: non_neg_integer() | nil,
          recovery_cutoff: DateTime.t()
        }

  @doc "Persists and enqueues one authorized, exact restore request atomically."
  @spec request(Scope.t(), Project.t(), ProjectSnapshot.t() | pos_integer(), map()) ::
          {:ok, ProjectSnapshotRestore.t()} | {:error, term()}
  def request(%{user: %{id: user_id}} = scope, %Project{id: project_id}, snapshot, attrs)
      when is_integer(user_id) and user_id > 0 and is_integer(project_id) and project_id > 0 and is_map(attrs) do
    with :ok <- RestorePolicy.ensure_enabled({:project_snapshot_restore, "full"}),
         {:ok, snapshot_id} <- snapshot_id(snapshot),
         {:ok, idempotency_key} <- normalize_idempotency_key(attrs),
         {:ok, %Project{id: ^project_id, workspace_id: workspace_id, deleted_at: nil}, _membership} <-
           Projects.authorize(scope, project_id, :manage_project) do
      workspace_id
      |> request_transaction(project_id, scope, user_id, snapshot_id, idempotency_key)
      |> normalize_request_result(project_id, user_id, snapshot_id, idempotency_key)
    else
      {:ok, %Project{}, _membership} -> {:error, :unauthorized}
      {:error, reason} when reason in [:not_found, :unauthorized] -> {:error, :unauthorized}
      {:error, _reason} = error -> error
    end
  end

  def request(_scope, _project, _snapshot, _attrs), do: {:error, :invalid_project_snapshot_restore_request}

  @doc "Returns one durable restore operation without loading its associations."
  @spec get(pos_integer()) :: ProjectSnapshotRestore.t() | nil
  def get(restore_id) when is_integer(restore_id) and restore_id > 0, do: Repo.get(ProjectSnapshotRestore, restore_id)

  def get(_restore_id), do: nil

  @doc "Lists recent restore operations for one project in stable reverse chronology."
  @spec list_for_project(pos_integer(), keyword()) :: [ProjectSnapshotRestore.t()]
  def list_for_project(project_id, opts \\ [])

  def list_for_project(project_id, opts) when is_integer(project_id) and project_id > 0 and is_list(opts) do
    limit = opts |> Keyword.get(:limit, 20) |> max(1) |> min(100)

    Repo.all(
      from restore in ProjectSnapshotRestore,
        where: restore.project_id == ^project_id,
        order_by: [desc: restore.inserted_at, desc: restore.id],
        limit: ^limit
    )
  end

  def list_for_project(_project_id, _opts), do: []

  @doc false
  @spec subscribe(pos_integer()) :: :ok | {:error, :invalid_project_id}
  def subscribe(project_id) when is_integer(project_id) and project_id > 0 do
    Phoenix.PubSub.subscribe(Storyarn.PubSub, topic(project_id))
  end

  def subscribe(_project_id), do: {:error, :invalid_project_id}

  @doc false
  @spec claim(pos_integer(), pos_integer(), keyword()) ::
          {:ok, {:claimed | :completed | :failed, ProjectSnapshotRestore.t()}}
          | {:error, term()}
  def claim(restore_id, requested_generation, opts)
      when is_positive_integer(restore_id) and is_positive_integer(requested_generation) and is_list(opts) do
    with {:ok, job_id, attempt} <- job_identity(opts) do
      fn ->
        restore_id
        |> lock_restore()
        |> claim_locked(requested_generation, job_id, attempt)
      end
      |> Repo.transact()
      |> broadcast_result()
    end
  end

  def claim(_restore_id, _requested_generation, _opts), do: {:error, :invalid_project_snapshot_restore_job}

  @doc false
  @spec complete(pos_integer(), pos_integer(), map()) ::
          {:ok, ProjectSnapshotRestore.t()} | {:error, term()}
  def complete(restore_id, expected_generation, result)
      when is_integer(restore_id) and restore_id > 0 and is_integer(expected_generation) and expected_generation > 0 and
             is_map(result) do
    with {:ok, result} <- normalize_executor_result(result) do
      fn ->
        restore_id
        |> lock_restore()
        |> complete_locked(expected_generation, result)
      end
      |> Repo.transact()
      |> broadcast_result()
    end
  end

  def complete(_restore_id, _expected_generation, _result), do: {:error, :invalid_project_snapshot_restore_result}

  @doc false
  @spec fail(pos_integer(), pos_integer(), term()) ::
          {:ok, ProjectSnapshotRestore.t()} | {:error, term()}
  def fail(restore_id, expected_generation, reason)
      when is_integer(restore_id) and restore_id > 0 and is_integer(expected_generation) and expected_generation > 0 do
    fn ->
      restore_id
      |> lock_restore()
      |> fail_locked(expected_generation, reason)
    end
    |> Repo.transact()
    |> broadcast_result()
  end

  def fail(_restore_id, _expected_generation, _reason), do: {:error, :invalid_project_snapshot_restore_failure}

  @doc false
  @spec advance_phase(pos_integer(), pos_integer(), String.t()) ::
          {:ok, ProjectSnapshotRestore.t()} | {:error, term()}
  def advance_phase(restore_id, expected_generation, phase)
      when is_integer(restore_id) and restore_id > 0 and is_integer(expected_generation) and expected_generation > 0 and
             is_binary(phase) do
    if phase in ProjectSnapshotRestore.running_phases() do
      fn ->
        restore_id
        |> lock_restore()
        |> advance_phase_locked(expected_generation, phase)
      end
      |> Repo.transact()
      |> broadcast_result()
    else
      {:error, :invalid_project_snapshot_restore_phase}
    end
  end

  def advance_phase(_restore_id, _expected_generation, _phase), do: {:error, :invalid_project_snapshot_restore_phase}

  @doc false
  @spec bind_reservation(pos_integer(), pos_integer(), StorageReservation.t()) ::
          {:ok, ProjectSnapshotRestore.t()} | {:error, term()}
  def bind_reservation(restore_id, expected_generation, %StorageReservation{} = reservation)
      when is_integer(restore_id) and restore_id > 0 and is_integer(expected_generation) and expected_generation > 0 do
    fn ->
      restore_id
      |> lock_restore()
      |> bind_reservation_locked(expected_generation, reservation)
    end
    |> Repo.transact()
    |> broadcast_result()
  end

  def bind_reservation(_restore_id, _expected_generation, _reservation),
    do: {:error, :invalid_project_snapshot_restore_reservation}

  @doc false
  @spec reserve_and_bind(pos_integer(), pos_integer(), map(), keyword()) ::
          {:ok, {ProjectSnapshotRestore.t(), StorageReservation.t()}} | {:error, term()}
  def reserve_and_bind(restore_id, expected_generation, reservation_attrs, opts \\ [])

  def reserve_and_bind(restore_id, expected_generation, reservation_attrs, opts)
      when is_positive_integer(restore_id) and is_positive_integer(expected_generation) and is_map(reservation_attrs) do
    with %ProjectSnapshotRestore{} = restore <- get(restore_id),
         true <- is_list(opts) and Keyword.keyword?(opts),
         after_reserve when is_function(after_reserve, 2) <-
           Keyword.get(opts, :after_reserve, fn _restore, _reservation -> :ok end) do
      reserve_and_bind_with_workspace_lock(
        restore,
        expected_generation,
        reservation_attrs,
        after_reserve
      )
    else
      nil -> {:error, :project_snapshot_restore_not_found}
      _invalid -> {:error, :invalid_project_snapshot_restore_reservation}
    end
  end

  def reserve_and_bind(_restore_id, _expected_generation, _reservation_attrs, _opts),
    do: {:error, :invalid_project_snapshot_restore_reservation}

  defp reserve_and_bind_with_workspace_lock(restore, expected_generation, reservation_attrs, after_reserve) do
    Billing.transact_with_workspace_lock(restore.workspace_id, fn _workspace ->
      restore
      |> reserve_and_bind_locked(expected_generation, reservation_attrs, after_reserve)
      |> normalize_reserve_and_bind_result()
    end)
  end

  defp normalize_reserve_and_bind_result({:error, reason, details}), do: {:error, {reason, details}}
  defp normalize_reserve_and_bind_result(result), do: result

  @doc false
  @spec perform(pos_integer(), pos_integer(), keyword()) :: perform_result()
  def perform(restore_id, requested_generation, opts)
      when is_positive_integer(restore_id) and is_positive_integer(requested_generation) and is_list(opts) do
    with %ProjectSnapshotRestore{} = restore <- get(restore_id),
         {:ok, executor} <- executor(opts) do
      perform_restore(restore, requested_generation, executor, opts)
    else
      nil -> {:discard, :project_snapshot_restore_not_found}
      {:error, reason} -> {:discard, reason}
    end
  end

  def perform(_restore_id, _requested_generation, _opts), do: {:discard, :invalid_project_snapshot_restore_job}

  @doc false
  @spec delivery_recovery_high_watermark() :: non_neg_integer()
  def delivery_recovery_high_watermark do
    Repo.one(
      from restore in ProjectSnapshotRestore,
        where: restore.status in ^@active_restore_statuses,
        select: coalesce(max(restore.id), 0)
    )
  end

  @doc false
  @spec delivery_recovery_quarantine_seconds() :: pos_integer()
  def delivery_recovery_quarantine_seconds, do: @delivery_recovery_quarantine_seconds

  @doc false
  @spec list_abandoned_delivery_candidates(keyword()) :: [abandoned_delivery_candidate()]
  def list_abandoned_delivery_candidates(opts \\ [])

  def list_abandoned_delivery_candidates(opts) when is_list(opts) do
    limit = opts |> Keyword.get(:limit, @delivery_recovery_batch_size) |> min(@delivery_recovery_batch_size) |> max(1)
    after_id = Keyword.get(opts, :after_id, 0)
    through_id = Keyword.get_lazy(opts, :through_id, &delivery_recovery_high_watermark/0)
    recovery_cutoff = DateTime.add(TimeHelpers.now(), -@delivery_recovery_quarantine_seconds, :second)
    abandoned_job = abandoned_delivery_job_dynamic(recovery_cutoff)

    Repo.all(
      from restore in ProjectSnapshotRestore,
        left_join: job in Oban.Job,
        on: job.id == restore.oban_job_id,
        left_join: reservation in StorageReservation,
        on: reservation.id == restore.storage_reservation_id,
        where:
          restore.id > ^after_id and restore.id <= ^through_id and
            restore.status in ^@active_restore_statuses and
            (is_nil(restore.storage_reservation_id) or reservation.status in ["active", "released"]),
        where: ^abandoned_job,
        order_by: [asc: restore.id],
        limit: ^limit,
        select: %{
          restore_id: restore.id,
          workspace_id: restore.workspace_id,
          project_id: restore.project_id,
          restore_status: restore.status,
          restore_phase: restore.phase,
          restore_generation: restore.generation,
          restore_attempt: restore.attempt,
          restore_state_updated_at: restore.state_updated_at,
          restore_oban_job_id: restore.oban_job_id,
          restore_reservation_id: restore.storage_reservation_id,
          restore_reservation_generation: restore.storage_reservation_generation,
          restore_reservation_lease_token: restore.storage_reservation_lease_token,
          job_id: job.id,
          job_state: job.state,
          job_attempt: job.attempt,
          job_max_attempts: job.max_attempts,
          job_attempted_at: job.attempted_at,
          job_completed_at: job.completed_at,
          job_discarded_at: job.discarded_at,
          job_cancelled_at: job.cancelled_at,
          reservation_id: reservation.id,
          reservation_status: reservation.status,
          reservation_generation: reservation.generation,
          reservation_lease_token: reservation.lease_token,
          reservation_storage_started_at: reservation.storage_started_at,
          reservation_cleanup_inventory_digest: reservation.cleanup_inventory_digest,
          reservation_cleanup_inventory_count: reservation.cleanup_inventory_count,
          recovery_cutoff: type(^recovery_cutoff, :utc_datetime)
        }
    )
  end

  def list_abandoned_delivery_candidates(_opts), do: []

  @doc false
  @spec recover_abandoned_delivery(abandoned_delivery_candidate(), keyword()) ::
          {:ok, :recovered | :stale} | {:error, term()}
  def recover_abandoned_delivery(candidate, opts \\ [])

  def recover_abandoned_delivery(%{} = candidate, opts) when is_list(opts) do
    with {:ok, project_id} <- candidate_positive_integer(candidate, :project_id),
         {:ok, timeout} <- recovery_lock_timeout(opts) do
      "project-snapshot-restore:#{project_id}"
      |> StorageKeyLock.with_session_lock(
        fn -> recover_abandoned_delivery_locked(candidate, opts) end,
        acquisition_timeout: timeout
      )
      |> normalize_delivery_recovery_lock_result()
    end
  end

  def recover_abandoned_delivery(_candidate, _opts), do: {:error, :invalid_project_snapshot_restore_delivery_candidate}

  defp abandoned_delivery_job_dynamic(recovery_cutoff) do
    missing_job = dynamic([_restore, job, _reservation], is_nil(job.id))
    exact_delivery = exact_abandoned_delivery_dynamic()
    terminal_job = terminal_abandoned_delivery_dynamic()
    stale_executing_job = stale_executing_delivery_dynamic(recovery_cutoff)

    dynamic(
      [_restore, _job, _reservation],
      ^missing_job or (^exact_delivery and (^terminal_job or ^stale_executing_job))
    )
  end

  defp exact_abandoned_delivery_dynamic do
    dynamic(
      [restore, job, _reservation],
      job.worker == ^@restore_worker and job.queue == ^@restore_queue and
        fragment("?->>'restore_id' = CAST(? AS text)", job.args, restore.id) and
        fragment(
          "?->>'generation' = CAST(CASE WHEN ? = 'queued' THEN ? ELSE ? - 1 END AS text)",
          job.args,
          restore.status,
          restore.generation,
          restore.generation
        )
    )
  end

  defp terminal_abandoned_delivery_dynamic do
    dynamic(
      [_restore, job, _reservation],
      job.state in ^@terminal_delivery_job_states
    )
  end

  defp stale_executing_delivery_dynamic(recovery_cutoff) do
    dynamic(
      [restore, job, _reservation],
      job.state == "executing" and not is_nil(job.attempted_at) and
        job.attempted_at <= ^recovery_cutoff and restore.state_updated_at <= ^recovery_cutoff
    )
  end

  defp perform_restore(%ProjectSnapshotRestore{status: "completed"} = restore, _generation, _executor, _opts) do
    replay_completed_side_effects(restore)
    terminal_perform_result(restore)
  end

  defp perform_restore(%ProjectSnapshotRestore{status: "failed"} = restore, _generation, _executor, _opts),
    do: terminal_perform_result(restore)

  defp perform_restore(restore, requested_generation, executor, opts) do
    "project-snapshot-restore:#{restore.project_id}"
    |> StorageKeyLock.with_session_lock(fn ->
      perform_locked(restore.id, requested_generation, executor, opts)
    end)
    |> normalize_lock_result()
  end

  defp recover_abandoned_delivery_locked(candidate, opts) do
    case revalidate_abandoned_delivery(candidate) do
      {:ok, :stale} ->
        {:ok, :stale}

      {:ok, %ProjectSnapshotRestore{} = restore} ->
        with :ok <- settle_abandoned_delivery(restore, opts) do
          terminalize_abandoned_delivery(candidate)
        end

      {:error, _reason} = error ->
        error
    end
  end

  defp revalidate_abandoned_delivery(candidate) do
    Repo.transact(fn ->
      with {:ok, restore_id} <- candidate_positive_integer(candidate, :restore_id),
           %ProjectSnapshotRestore{} = restore <- lock_restore(restore_id),
           job = lock_job(restore.oban_job_id),
           reservation = lock_reservation(restore.storage_reservation_id),
           true <- abandoned_delivery_matches?(candidate, restore, job, reservation) do
        {:ok, restore}
      else
        _changed -> {:ok, :stale}
      end
    end)
  end

  defp settle_abandoned_delivery(restore, opts) do
    settle_fun =
      Keyword.get(
        opts,
        :settle_bound_reservation,
        &ProjectSnapshotRestoreExecutor.settle_bound_reservation/2
      )

    settlement_opts = Keyword.drop(opts, [:settle_bound_reservation, :session_lock_timeout_ms])

    case settle_fun.(restore, settlement_opts) do
      :ok -> :ok
      {:error, _reason} = error -> error
      _invalid -> {:error, :project_snapshot_restore_delivery_settlement_failed}
    end
  rescue
    _error -> {:error, :project_snapshot_restore_delivery_settlement_failed}
  catch
    _kind, _reason -> {:error, :project_snapshot_restore_delivery_settlement_failed}
  end

  defp terminalize_abandoned_delivery(candidate) do
    fn ->
      with {:ok, restore_id} <- candidate_positive_integer(candidate, :restore_id),
           %ProjectSnapshotRestore{} = restore <- lock_restore(restore_id) do
        job = lock_job(restore.oban_job_id)
        reservation = lock_reservation(restore.storage_reservation_id)
        terminalize_revalidated_abandoned_delivery(candidate, restore, job, reservation)
      else
        _changed -> {:ok, :stale}
      end
    end
    |> Repo.transact()
    |> broadcast_abandoned_delivery_result()
  end

  defp terminalize_revalidated_abandoned_delivery(candidate, restore, job, reservation) do
    cond do
      restore.status in @terminal_statuses ->
        {:ok, :stale}

      not abandoned_restore_and_job_match?(candidate, restore, job) ->
        {:ok, :stale}

      abandoned_reservation_still_active?(candidate, restore, reservation) ->
        {:error, :project_snapshot_restore_delivery_settlement_incomplete}

      not settled_abandoned_reservation_matches?(candidate, restore, reservation) ->
        {:ok, :stale}

      true ->
        with {:ok, _job} <- cancel_abandoned_executing_job(job),
             {:ok, failed} <- fail_abandoned_restore_locked(restore) do
          {:ok, {:recovered, failed}}
        end
    end
  end

  defp abandoned_delivery_matches?(candidate, restore, job, reservation) do
    abandoned_restore_and_job_match?(candidate, restore, job) and
      abandoned_reservation_matches?(candidate, restore, reservation)
  end

  defp abandoned_restore_and_job_match?(candidate, restore, job) do
    restore.status in @active_restore_statuses and
      valid_recovery_cutoff?(candidate) and
      candidate_values_match?(candidate, [
        {:restore_id, restore.id},
        {:workspace_id, restore.workspace_id},
        {:project_id, restore.project_id},
        {:restore_status, restore.status},
        {:restore_phase, restore.phase},
        {:restore_generation, restore.generation},
        {:restore_attempt, restore.attempt},
        {:restore_state_updated_at, restore.state_updated_at},
        {:restore_oban_job_id, restore.oban_job_id},
        {:restore_reservation_id, restore.storage_reservation_id},
        {:restore_reservation_generation, restore.storage_reservation_generation},
        {:restore_reservation_lease_token, restore.storage_reservation_lease_token}
      ]) and
      abandoned_job_matches?(candidate, restore, job)
  end

  defp abandoned_job_matches?(candidate, %ProjectSnapshotRestore{oban_job_id: nil}, nil) do
    candidate_values_match?(candidate, empty_job_candidate_values())
  end

  defp abandoned_job_matches?(candidate, restore, %Oban.Job{} = job) do
    restore.oban_job_id == job.id and
      candidate_values_match?(candidate, [
        {:job_id, job.id},
        {:job_state, job.state},
        {:job_attempt, job.attempt},
        {:job_max_attempts, job.max_attempts},
        {:job_attempted_at, job.attempted_at},
        {:job_completed_at, job.completed_at},
        {:job_discarded_at, job.discarded_at},
        {:job_cancelled_at, job.cancelled_at}
      ]) and
      job.worker == @restore_worker and job.queue == @restore_queue and
      job.args["restore_id"] == restore.id and
      restore_job_generation_matches?(restore, job) and
      abandoned_job_state?(candidate, restore, job)
  end

  defp abandoned_job_matches?(_candidate, _restore, _job), do: false

  defp empty_job_candidate_values do
    [
      {:job_id, nil},
      {:job_state, nil},
      {:job_attempt, nil},
      {:job_max_attempts, nil},
      {:job_attempted_at, nil},
      {:job_completed_at, nil},
      {:job_discarded_at, nil},
      {:job_cancelled_at, nil}
    ]
  end

  defp restore_job_generation_matches?(%ProjectSnapshotRestore{status: "queued"} = restore, job) do
    requested_generation = job.args["generation"]
    is_integer(requested_generation) and restore.generation == requested_generation
  end

  defp restore_job_generation_matches?(restore, job) do
    requested_generation = job.args["generation"]
    is_integer(requested_generation) and restore.generation == requested_generation + 1
  end

  defp abandoned_job_state?(_candidate, _restore, %Oban.Job{state: state}) when state in @terminal_delivery_job_states,
    do: true

  defp abandoned_job_state?(candidate, restore, %Oban.Job{state: "executing", attempted_at: attempted_at}) do
    cutoff = Map.get(candidate, :recovery_cutoff)
    old_enough?(attempted_at, cutoff) and old_enough?(restore.state_updated_at, cutoff)
  end

  defp abandoned_job_state?(_candidate, _restore, _job), do: false

  defp abandoned_reservation_matches?(candidate, %ProjectSnapshotRestore{storage_reservation_id: nil} = restore, nil) do
    is_nil(restore.storage_reservation_generation) and is_nil(restore.storage_reservation_lease_token) and
      candidate_values_match?(candidate, [
        {:reservation_id, nil},
        {:reservation_status, nil},
        {:reservation_generation, nil},
        {:reservation_lease_token, nil},
        {:reservation_storage_started_at, nil},
        {:reservation_cleanup_inventory_digest, nil},
        {:reservation_cleanup_inventory_count, nil}
      ])
  end

  defp abandoned_reservation_matches?(candidate, restore, %StorageReservation{} = reservation) do
    reservation.status in ["active", "released"] and
      abandoned_reservation_owner_matches?(candidate, restore, reservation) and
      candidate_values_match?(candidate, reservation_candidate_values(reservation))
  end

  defp abandoned_reservation_matches?(_candidate, _restore, _reservation), do: false

  defp settled_abandoned_reservation_matches?(
         candidate,
         %ProjectSnapshotRestore{storage_reservation_id: nil} = restore,
         nil
       ) do
    abandoned_reservation_matches?(candidate, restore, nil)
  end

  defp settled_abandoned_reservation_matches?(candidate, restore, %StorageReservation{} = reservation) do
    abandoned_reservation_owner_matches?(candidate, restore, reservation) and
      settled_reservation_generation_matches?(candidate, reservation) and
      candidate_values_match?(candidate, [
        {:reservation_storage_started_at, reservation.storage_started_at},
        {:reservation_cleanup_inventory_digest, reservation.cleanup_inventory_digest},
        {:reservation_cleanup_inventory_count, reservation.cleanup_inventory_count}
      ])
  end

  defp settled_abandoned_reservation_matches?(_candidate, _restore, _reservation), do: false

  defp abandoned_reservation_still_active?(candidate, restore, %StorageReservation{status: "active"} = reservation) do
    Map.get(candidate, :reservation_status) == "active" and
      abandoned_reservation_owner_matches?(candidate, restore, reservation) and
      candidate_values_match?(candidate, reservation_candidate_values(reservation))
  end

  defp abandoned_reservation_still_active?(_candidate, _restore, _reservation), do: false

  defp settled_reservation_generation_matches?(candidate, reservation) do
    case {Map.get(candidate, :reservation_status), Map.get(candidate, :reservation_generation)} do
      {"active", generation} when is_integer(generation) ->
        reservation.status == "released" and reservation.generation == generation + 1

      {"released", generation} when is_integer(generation) ->
        reservation.status == "released" and reservation.generation == generation

      _invalid ->
        false
    end
  end

  defp reservation_candidate_values(reservation) do
    [
      {:reservation_status, reservation.status},
      {:reservation_generation, reservation.generation},
      {:reservation_storage_started_at, reservation.storage_started_at},
      {:reservation_cleanup_inventory_digest, reservation.cleanup_inventory_digest},
      {:reservation_cleanup_inventory_count, reservation.cleanup_inventory_count}
    ]
  end

  defp abandoned_reservation_owner_matches?(candidate, restore, reservation) do
    candidate_values_match?(candidate, [
      {:reservation_id, reservation.id},
      {:reservation_lease_token, reservation.lease_token}
    ]) and
      restore.storage_reservation_id == reservation.id and
      restore.storage_reservation_lease_token == reservation.lease_token and
      reservation.kind == "restore_staging" and
      reservation.workspace_id_snapshot == restore.workspace_id and
      reservation.project_id_snapshot == restore.project_id and
      reservation.project_snapshot_id_snapshot == restore.project_snapshot_id
  end

  defp cancel_abandoned_executing_job(%Oban.Job{state: "executing"} = job) do
    now = %{TimeHelpers.now() | microsecond: {0, 6}}

    job
    |> Ecto.Changeset.change(state: "cancelled", cancelled_at: now)
    |> Repo.update()
  end

  defp cancel_abandoned_executing_job(%Oban.Job{} = job), do: {:ok, job}
  defp cancel_abandoned_executing_job(nil), do: {:ok, nil}

  defp fail_abandoned_restore_locked(%ProjectSnapshotRestore{status: "queued"} = restore) do
    restore
    |> ProjectSnapshotRestore.abandoned_changeset(
      failure_attrs(:project_snapshot_restore_delivery_abandoned),
      TimeHelpers.now()
    )
    |> Repo.update()
  end

  defp fail_abandoned_restore_locked(%ProjectSnapshotRestore{} = restore) do
    fail_locked(restore, restore.generation, :project_snapshot_restore_delivery_abandoned)
  end

  defp valid_recovery_cutoff?(candidate) do
    case Map.get(candidate, :recovery_cutoff) do
      %DateTime{} = cutoff ->
        latest = DateTime.add(TimeHelpers.now(), -@delivery_recovery_quarantine_seconds, :second)
        DateTime.compare(cutoff, latest) in [:lt, :eq]

      _invalid ->
        false
    end
  end

  defp old_enough?(%DateTime{} = timestamp, %DateTime{} = cutoff), do: DateTime.compare(timestamp, cutoff) in [:lt, :eq]

  defp old_enough?(_timestamp, _cutoff), do: false

  defp candidate_values_match?(candidate, expected) do
    Enum.all?(expected, fn {key, value} -> Map.get(candidate, key) == value end)
  end

  defp candidate_positive_integer(candidate, key) do
    case Map.get(candidate, key) do
      value when is_integer(value) and value > 0 -> {:ok, value}
      _invalid -> {:error, :invalid_project_snapshot_restore_delivery_candidate}
    end
  end

  defp recovery_lock_timeout(opts) do
    case Keyword.get(opts, :session_lock_timeout_ms, 0) do
      timeout when is_integer(timeout) and timeout >= 0 -> {:ok, timeout}
      _invalid -> {:error, :invalid_project_snapshot_restore_delivery_recovery_options}
    end
  end

  defp normalize_delivery_recovery_lock_result({:error, :session_lock_timeout}),
    do: {:error, :project_snapshot_restore_delivery_busy}

  defp normalize_delivery_recovery_lock_result(result), do: result

  defp broadcast_abandoned_delivery_result({:ok, {:recovered, %ProjectSnapshotRestore{} = restore}}) do
    broadcast(restore)
    {:ok, :recovered}
  end

  defp broadcast_abandoned_delivery_result(result), do: result

  defp request_transaction(workspace_id, project_id, scope, user_id, snapshot_id, idempotency_key) do
    Billing.transact_with_workspace_lock(workspace_id, fn _workspace ->
      with %Project{} = project <- lock_active_project(project_id),
           true <- project.workspace_id == workspace_id,
           {:ok, %Project{id: ^project_id, deleted_at: nil}, _membership} <-
             Projects.authorize(scope, project_id, :manage_project),
           true <- project.workspace_id > 0 do
        request_locked(project, user_id, snapshot_id, idempotency_key)
      else
        nil -> {:error, :unauthorized}
        false -> {:error, :invalid_project_snapshot_restore_request}
        {:error, reason} when reason in [:not_found, :unauthorized] -> {:error, :unauthorized}
      end
    end)
  end

  defp request_locked(project, user_id, snapshot_id, idempotency_key) do
    case restore_by_idempotency(project.workspace_id, idempotency_key) do
      %ProjectSnapshotRestore{} = restore ->
        replay_or_conflict(restore, project.id, snapshot_id, user_id)

      nil ->
        create_locked_request(project, user_id, snapshot_id, idempotency_key)
    end
  end

  defp create_locked_request(project, user_id, snapshot_id, idempotency_key) do
    with %ProjectSnapshot{} = snapshot <- lock_snapshot(snapshot_id, project.id),
         :ok <- validate_restorable_snapshot(snapshot),
         {:ok, restore} <- insert_restore(project, user_id, snapshot, idempotency_key),
         {:ok, job} <- enqueue_restore(restore),
         {:ok, restore} <-
           restore
           |> ProjectSnapshotRestore.bind_job_changeset(job.id)
           |> Repo.update() do
      {:ok, restore}
    else
      nil -> {:error, :project_snapshot_not_found}
      {:error, %Ecto.Changeset{} = changeset} -> {:error, changeset}
      {:error, _reason} = error -> error
    end
  end

  defp insert_restore(project, user_id, snapshot, idempotency_key) do
    %ProjectSnapshotRestore{}
    |> ProjectSnapshotRestore.request_changeset(%{
      workspace_id: project.workspace_id,
      project_id: project.id,
      project_snapshot_id: snapshot.id,
      requested_by_id: user_id,
      idempotency_key: idempotency_key,
      snapshot_lifecycle_generation: snapshot.lifecycle_generation,
      snapshot_accounting_generation: snapshot.accounting_generation,
      archive_storage_key: snapshot.archive_storage_key,
      archive_size_bytes: snapshot.archive_size_bytes,
      archive_checksum: snapshot.archive_checksum,
      manifest_storage_key: snapshot.manifest_storage_key,
      manifest_size_bytes: snapshot.manifest_size_bytes,
      manifest_checksum: snapshot.manifest_checksum,
      requested_at: TimeHelpers.now()
    })
    |> Repo.insert()
  end

  defp enqueue_restore(restore) do
    %{restore_id: restore.id, generation: restore.generation}
    |> RestoreProjectSnapshotWorker.new(queue: :snapshot_restores)
    |> Oban.insert()
  end

  defp normalize_request_result(
         {:error, %Ecto.Changeset{} = changeset},
         project_id,
         user_id,
         snapshot_id,
         idempotency_key
       ) do
    cond do
      constraint_error?(changeset, :idempotency_key) ->
        workspace_id = Ecto.Changeset.get_field(changeset, :workspace_id)

        normalize_idempotency_collision(
          workspace_id,
          project_id,
          idempotency_key,
          user_id,
          snapshot_id
        )

      constraint_error?(changeset, :project_id) ->
        {:error, :project_snapshot_restore_in_progress}

      true ->
        {:error, changeset}
    end
  end

  defp normalize_request_result(
         {:ok, %ProjectSnapshotRestore{} = restore},
         _project_id,
         _user_id,
         _snapshot_id,
         _idempotency_key
       ) do
    broadcast(restore)
    {:ok, restore}
  end

  defp normalize_request_result(result, _project_id, _user_id, _snapshot_id, _idempotency_key), do: result

  defp normalize_idempotency_collision(workspace_id, project_id, idempotency_key, user_id, snapshot_id) do
    case restore_by_idempotency(workspace_id, idempotency_key) do
      %ProjectSnapshotRestore{} = restore ->
        replay_or_conflict(restore, project_id, snapshot_id, user_id)

      nil ->
        {:error, :project_snapshot_restore_idempotency_conflict}
    end
  end

  defp replay_or_conflict(restore, project_id, snapshot_id, user_id) do
    if restore.project_id == project_id and restore.project_snapshot_id == snapshot_id and
         restore.requested_by_id == user_id do
      {:ok, restore}
    else
      {:error, :project_snapshot_restore_idempotency_conflict}
    end
  end

  defp constraint_error?(changeset, field), do: Keyword.has_key?(changeset.errors, field)

  defp perform_locked(restore_id, requested_generation, executor, opts) do
    case claim(restore_id, requested_generation, opts) do
      {:ok, {:completed, restore}} ->
        replay_completed_side_effects(restore)
        {:ok, restore}

      {:ok, {:failed, _restore}} ->
        {:discard, :project_snapshot_restore_failed}

      {:ok, {:claimed, restore}} ->
        execute_claimed(restore, executor, opts)

      {:error, reason} ->
        {:discard, normalize_discard_reason(reason)}
    end
  end

  defp execute_claimed(restore, executor, opts) do
    with :ok <- RestorePolicy.ensure_enabled({:project_snapshot_restore, "full"}),
         :ok <- reauthorize_claim(restore),
         :ok <- revalidate_target(restore) do
      restore
      |> execute_safely(executor, Keyword.delete(opts, :executor))
      |> settle_execution(restore, opts)
    else
      {:error, reason} -> terminalize_claim(restore, reason, opts)
    end
  end

  defp execute_safely(restore, executor, opts) do
    {:returned, executor.(restore, opts)}
  rescue
    _error -> {:raised, :project_snapshot_restore_executor_exception}
  catch
    _kind, _reason -> {:raised, :project_snapshot_restore_executor_exception}
  end

  defp settle_execution({:returned, {:ok, result}}, restore, opts) when is_map(result) do
    after_ownership_settlement(restore, opts, fn ->
      case complete(restore.id, restore.generation, result) do
        {:ok, completed} ->
          replay_completed_side_effects(completed)
          {:ok, completed}

        {:error, reason} ->
          {:discard, normalize_discard_reason(reason)}
      end
    end)
  end

  defp settle_execution({:returned, {:retry, reason}}, restore, opts) do
    if final_attempt?(opts) do
      terminalize_claim(restore, reason, opts)
    else
      case mark_retrying(restore.id, restore.generation, reason) do
        {:ok, _restore} -> {:retry, normalize_retry_reason(reason)}
        {:error, failure} -> {:discard, normalize_discard_reason(failure)}
      end
    end
  end

  defp settle_execution({:returned, {:snooze, seconds}}, _restore, _opts) when is_integer(seconds) and seconds > 0,
    do: {:snooze, seconds}

  defp settle_execution({:returned, {:error, reason}}, restore, opts), do: terminalize_claim(restore, reason, opts)

  defp settle_execution({:raised, reason}, restore, opts) do
    settle_execution({:returned, {:retry, reason}}, restore, opts)
  end

  defp settle_execution(_invalid, restore, opts),
    do: terminalize_claim(restore, :invalid_project_snapshot_restore_executor_result, opts)

  defp terminalize_claim(restore, reason, opts) do
    after_ownership_settlement(restore, opts, fn ->
      case fail(restore.id, restore.generation, reason) do
        {:ok, _failed} -> {:discard, normalize_discard_reason(reason)}
        {:error, failure} -> {:discard, normalize_discard_reason(failure)}
      end
    end)
  end

  defp after_ownership_settlement(restore, opts, terminal_fun) do
    settle_fun =
      Keyword.get(
        opts,
        :settle_bound_reservation,
        &ProjectSnapshotRestoreExecutor.settle_bound_reservation/2
      )

    settlement_opts = Keyword.delete(opts, :settle_bound_reservation)

    case settle_fun.(restore, settlement_opts) do
      :ok -> terminal_fun.()
      {:error, _reason} -> {:snooze, @settlement_snooze_seconds}
      _invalid -> {:snooze, @settlement_snooze_seconds}
    end
  rescue
    _error -> {:snooze, @settlement_snooze_seconds}
  catch
    _kind, _reason -> {:snooze, @settlement_snooze_seconds}
  end

  defp mark_retrying(restore_id, expected_generation, reason) do
    fn ->
      case lock_restore(restore_id) do
        %ProjectSnapshotRestore{status: "retrying", generation: ^expected_generation} = restore ->
          {:ok, restore}

        %ProjectSnapshotRestore{status: "running", generation: ^expected_generation} = restore ->
          restore
          |> ProjectSnapshotRestore.retrying_changeset(failure_attrs(reason), TimeHelpers.now())
          |> Repo.update()

        %ProjectSnapshotRestore{} ->
          {:error, :stale_project_snapshot_restore_generation}

        nil ->
          {:error, :project_snapshot_restore_not_found}
      end
    end
    |> Repo.transact()
    |> broadcast_result()
  end

  defp claim_locked(nil, _requested_generation, _job_id, _attempt), do: {:error, :project_snapshot_restore_not_found}

  defp claim_locked(%ProjectSnapshotRestore{status: "completed"} = restore, _generation, _job_id, _attempt),
    do: {:ok, {:completed, restore}}

  defp claim_locked(%ProjectSnapshotRestore{status: "failed"} = restore, _generation, _job_id, _attempt),
    do: {:ok, {:failed, restore}}

  defp claim_locked(
         %ProjectSnapshotRestore{status: "queued", generation: generation} = restore,
         generation,
         job_id,
         attempt
       ) do
    with :ok <- validate_executing_job(restore, generation, job_id, attempt),
         {:ok, claimed} <-
           restore
           |> ProjectSnapshotRestore.claim_changeset(attempt, TimeHelpers.now())
           |> Repo.update() do
      {:ok, {:claimed, claimed}}
    end
  end

  defp claim_locked(
         %ProjectSnapshotRestore{status: "retrying", generation: generation} = restore,
         requested_generation,
         job_id,
         attempt
       )
       when generation == requested_generation + 1 do
    with :ok <- validate_executing_job(restore, requested_generation, job_id, attempt),
         {:ok, claimed} <-
           restore
           |> ProjectSnapshotRestore.claim_changeset(attempt, TimeHelpers.now())
           |> Repo.update() do
      {:ok, {:claimed, claimed}}
    end
  end

  defp claim_locked(
         %ProjectSnapshotRestore{status: "running", generation: generation, attempt: recorded_attempt} = restore,
         requested_generation,
         job_id,
         attempt
       )
       when generation == requested_generation + 1 and attempt >= recorded_attempt do
    with :ok <- validate_executing_job(restore, requested_generation, job_id, attempt) do
      resume_running_claim(restore, attempt)
    end
  end

  defp claim_locked(%ProjectSnapshotRestore{}, _generation, _job_id, _attempt),
    do: {:error, :stale_project_snapshot_restore_generation}

  defp resume_running_claim(%ProjectSnapshotRestore{attempt: attempt} = restore, attempt), do: {:ok, {:claimed, restore}}

  defp resume_running_claim(restore, attempt) do
    case restore
         |> ProjectSnapshotRestore.resume_changeset(attempt, TimeHelpers.now())
         |> Repo.update() do
      {:ok, resumed} -> {:ok, {:claimed, resumed}}
      {:error, _changeset} = error -> error
    end
  end

  defp complete_locked(nil, _generation, _result), do: {:error, :project_snapshot_restore_not_found}

  defp complete_locked(%ProjectSnapshotRestore{status: "completed"} = restore, _generation, _result), do: {:ok, restore}

  defp complete_locked(%ProjectSnapshotRestore{status: "failed"}, _generation, _result),
    do: {:error, :project_snapshot_restore_already_failed}

  defp complete_locked(%ProjectSnapshotRestore{status: "running", generation: generation} = restore, generation, result) do
    restore
    |> ProjectSnapshotRestore.complete_changeset(result, TimeHelpers.now())
    |> Repo.update()
  end

  defp complete_locked(%ProjectSnapshotRestore{}, _generation, _result),
    do: {:error, :stale_project_snapshot_restore_generation}

  defp fail_locked(nil, _generation, _reason), do: {:error, :project_snapshot_restore_not_found}

  defp fail_locked(%ProjectSnapshotRestore{status: status} = restore, _generation, _reason)
       when status in @terminal_statuses, do: {:ok, restore}

  defp fail_locked(%ProjectSnapshotRestore{status: status, generation: generation} = restore, generation, reason)
       when status in ["running", "retrying"] do
    restore
    |> ProjectSnapshotRestore.fail_changeset(failure_attrs(reason), TimeHelpers.now())
    |> Repo.update()
  end

  defp fail_locked(%ProjectSnapshotRestore{}, _generation, _reason),
    do: {:error, :stale_project_snapshot_restore_generation}

  defp advance_phase_locked(nil, _generation, _phase), do: {:error, :project_snapshot_restore_not_found}

  defp advance_phase_locked(
         %ProjectSnapshotRestore{status: "running", generation: generation, phase: phase} = restore,
         generation,
         phase
       ), do: {:ok, restore}

  defp advance_phase_locked(
         %ProjectSnapshotRestore{status: "running", generation: generation, phase: current_phase} = restore,
         generation,
         next_phase
       ) do
    if Map.get(@phase_successors, current_phase) == next_phase do
      restore
      |> ProjectSnapshotRestore.phase_changeset(next_phase, TimeHelpers.now())
      |> Repo.update()
    else
      {:error, :invalid_project_snapshot_restore_phase_transition}
    end
  end

  defp advance_phase_locked(%ProjectSnapshotRestore{}, _generation, _phase),
    do: {:error, :stale_project_snapshot_restore_generation}

  defp bind_reservation_locked(nil, _generation, _reservation), do: {:error, :project_snapshot_restore_not_found}

  defp bind_reservation_locked(%ProjectSnapshotRestore{generation: generation} = restore, generation, reservation) do
    with :ok <- validate_reservation_owner(restore, reservation) do
      restore
      |> ProjectSnapshotRestore.bind_reservation_changeset(reservation)
      |> Repo.update()
    end
  end

  defp bind_reservation_locked(%ProjectSnapshotRestore{}, _generation, _reservation),
    do: {:error, :stale_project_snapshot_restore_generation}

  defp reserve_and_bind_locked(restore_hint, expected_generation, reservation_attrs, after_reserve) do
    with %Project{id: project_id, deleted_at: nil} <- lock_active_project(restore_hint.project_id),
         %ProjectSnapshotRestore{} = restore <- lock_restore(restore_hint.id),
         true <- project_id == restore.project_id and restore.workspace_id == restore_hint.workspace_id,
         :ok <- validate_reservation_bind_state(restore, expected_generation, reservation_attrs),
         {:ok, %StorageReservation{} = reservation} <- Billing.reserve_storage(reservation_attrs),
         :ok <- after_reserve.(restore, reservation),
         {:ok, %ProjectSnapshotRestore{} = bound} <-
           bind_reservation_locked(restore, expected_generation, reservation) do
      {:ok, {bound, reservation}}
    else
      nil -> {:error, :project_snapshot_restore_target_not_found}
      false -> {:error, :project_snapshot_restore_reservation_mismatch}
      {:error, _reason, _details} = error -> error
      {:error, _reason} = error -> error
      _invalid -> {:error, :project_snapshot_restore_reservation_mismatch}
    end
  end

  defp validate_reservation_bind_state(
         %ProjectSnapshotRestore{status: "running", phase: "staging", generation: generation} = restore,
         generation,
         reservation_attrs
       ) do
    requested_lease = reservation_attr(reservation_attrs, :lease_token)
    requested_key = "project-snapshot-restore:#{restore.id}:lease:#{requested_lease}"

    with true <- reservation_attr(reservation_attrs, :workspace_id) == restore.workspace_id,
         true <- reservation_attr(reservation_attrs, :project_id) == restore.project_id,
         true <- reservation_attr(reservation_attrs, :project_snapshot_id) == restore.project_snapshot_id,
         true <- reservation_attr(reservation_attrs, :kind) == "restore_staging",
         :ok <-
           validate_existing_reservation_binding(
             restore,
             reservation_attr(reservation_attrs, :idempotency_key),
             requested_key
           ) do
      :ok
    else
      false -> {:error, :project_snapshot_restore_reservation_mismatch}
      {:error, _reason} = error -> error
    end
  end

  defp validate_reservation_bind_state(%ProjectSnapshotRestore{}, _generation, _attrs),
    do: {:error, :stale_project_snapshot_restore_generation}

  defp validate_existing_reservation_binding(
         %ProjectSnapshotRestore{storage_reservation_id: nil},
         reservation_key,
         requested_key
       ) do
    if reservation_key == requested_key,
      do: :ok,
      else: {:error, :project_snapshot_restore_reservation_mismatch}
  end

  defp validate_existing_reservation_binding(
         %ProjectSnapshotRestore{storage_reservation_id: reservation_id},
         reservation_key,
         requested_key
       ) do
    case Repo.get(StorageReservation, reservation_id) do
      %StorageReservation{status: "active", idempotency_key: ^reservation_key} ->
        :ok

      %StorageReservation{status: "active"} ->
        {:error, :project_snapshot_restore_reservation_requires_recovery}

      %StorageReservation{} ->
        if reservation_key == requested_key,
          do: :ok,
          else: {:error, :project_snapshot_restore_reservation_mismatch}

      nil ->
        if reservation_key == requested_key,
          do: :ok,
          else: {:error, :project_snapshot_restore_reservation_mismatch}
    end
  end

  defp reservation_attr(attrs, key), do: Map.get(attrs, key, Map.get(attrs, Atom.to_string(key)))

  defp validate_reservation_owner(restore, reservation) do
    valid? =
      Enum.all?([
        restore.status in ["running", "retrying"],
        reservation.kind == "restore_staging",
        reservation.status == "active",
        reservation.workspace_id_snapshot == restore.workspace_id,
        reservation.project_id_snapshot == restore.project_id,
        reservation.project_snapshot_id_snapshot == restore.project_snapshot_id,
        positive_integer?(reservation.generation),
        is_binary(reservation.lease_token)
      ])

    if valid?, do: :ok, else: {:error, :project_snapshot_restore_reservation_mismatch}
  end

  defp reauthorize_claim(restore) do
    restore = Repo.preload(restore, :requested_by)

    with %{id: actor_id} = actor <- restore.requested_by,
         true <- actor_id == restore.requested_by_id,
         {:ok, %Project{workspace_id: workspace_id, deleted_at: nil}, _membership} <-
           Projects.authorize(%{user: actor}, restore.project_id, :manage_project),
         true <- workspace_id == restore.workspace_id do
      :ok
    else
      _invalid -> {:error, :project_snapshot_restore_unauthorized}
    end
  end

  defp revalidate_target(restore) do
    case Repo.get(ProjectSnapshot, restore.project_snapshot_id) do
      %ProjectSnapshot{} = snapshot ->
        with :ok <- validate_restorable_snapshot(snapshot),
             true <- target_identity_matches?(restore, snapshot) do
          :ok
        else
          _invalid -> {:error, :project_snapshot_restore_target_changed}
        end

      nil ->
        {:error, :project_snapshot_restore_target_changed}
    end
  end

  @doc false
  def restorable_snapshot_identity(%ProjectSnapshot{} = snapshot) do
    with :ok <- validate_restorable_snapshot(snapshot) do
      {:ok,
       %{
         lifecycle_generation: snapshot.lifecycle_generation,
         accounting_generation: snapshot.accounting_generation,
         archive_storage_key: snapshot.archive_storage_key,
         archive_size_bytes: snapshot.archive_size_bytes,
         archive_checksum: snapshot.archive_checksum,
         manifest_storage_key: snapshot.manifest_storage_key,
         manifest_size_bytes: snapshot.manifest_size_bytes,
         manifest_checksum: snapshot.manifest_checksum
       }}
    end
  end

  def restorable_snapshot_identity(_snapshot), do: {:error, :project_snapshot_not_restorable}

  defp validate_restorable_snapshot(snapshot) do
    valid? =
      Enum.all?([
        snapshot.format_version == 2,
        snapshot.restore_contract_version == 1,
        snapshot.mode == "full",
        snapshot.lifecycle_state == "ready",
        snapshot.integrity_state == "verified",
        snapshot.accounting_version == 1,
        positive_integer?(snapshot.accounting_generation),
        positive_integer?(snapshot.lifecycle_generation),
        nonempty_binary?(snapshot.archive_storage_key),
        positive_integer?(snapshot.archive_size_bytes),
        valid_digest?(snapshot.archive_checksum),
        nonempty_binary?(snapshot.manifest_storage_key),
        positive_integer?(snapshot.manifest_size_bytes),
        valid_digest?(snapshot.manifest_checksum)
      ])

    if valid?, do: :ok, else: {:error, :project_snapshot_not_restorable}
  end

  defp target_identity_matches?(restore, snapshot) do
    snapshot.project_id == restore.project_id and
      snapshot.lifecycle_generation == restore.snapshot_lifecycle_generation and
      snapshot.accounting_generation == restore.snapshot_accounting_generation and
      snapshot.archive_storage_key == restore.archive_storage_key and
      snapshot.archive_size_bytes == restore.archive_size_bytes and
      snapshot.archive_checksum == restore.archive_checksum and
      snapshot.manifest_storage_key == restore.manifest_storage_key and
      snapshot.manifest_size_bytes == restore.manifest_size_bytes and
      snapshot.manifest_checksum == restore.manifest_checksum
  end

  defp validate_executing_job(restore, requested_generation, job_id, attempt) do
    with true <- restore.oban_job_id == job_id,
         %Oban.Job{} = job <- lock_job(job_id),
         true <- job.worker == @restore_worker,
         true <- job.queue == @restore_queue,
         true <- job.state == "executing",
         true <- job.attempt == attempt,
         true <- job.args["restore_id"] == restore.id,
         true <- job.args["generation"] == requested_generation do
      :ok
    else
      _invalid -> {:error, :project_snapshot_restore_job_not_executing}
    end
  end

  defp job_identity(opts) do
    job_id = Keyword.get(opts, :job_id)
    attempt = Keyword.get(opts, :attempt)

    if is_integer(job_id) and job_id > 0 and is_integer(attempt) and attempt > 0 do
      {:ok, job_id, attempt}
    else
      {:error, :invalid_project_snapshot_restore_job}
    end
  end

  defp executor(opts) do
    candidate = Keyword.get(opts, :executor, &ProjectSnapshotRestoreExecutor.execute/2)
    if is_function(candidate, 2), do: {:ok, candidate}, else: {:error, :invalid_project_snapshot_restore_executor}
  end

  defp normalize_executor_result(result) do
    digest = value(result, :result_digest)
    reservation_id = value(result, :reservation_id)

    if valid_digest?(digest) and valid_completion_side_effects?(result) and
         (is_nil(reservation_id) or (is_integer(reservation_id) and reservation_id > 0)) do
      with {:ok, encoded} <- Jason.encode(result),
           {:ok, normalized} when is_map(normalized) <- Jason.decode(encoded) do
        {:ok, normalized}
      else
        _invalid -> {:error, :invalid_project_snapshot_restore_result}
      end
    else
      {:error, :invalid_project_snapshot_restore_result}
    end
  end

  defp failure_attrs(reason) do
    code = failure_code(reason)

    %{
      failure_code: Atom.to_string(code),
      failure_message: @generic_failure_message,
      failure_details: %{"reason" => Atom.to_string(code)}
    }
  end

  defp valid_completion_side_effects?(result) do
    case value(result, :content_replaced) do
      nil ->
        true

      false ->
        true

      true ->
        Enum.all?(
          [:replaced_sheet_ids, :replaced_flow_ids, :replaced_scene_ids],
          fn key -> result |> value(key) |> valid_entity_ids?() end
        )

      _invalid ->
        false
    end
  end

  defp failure_code(reason) when is_atom(reason), do: bounded_failure_code(reason)
  defp failure_code({reason, _details}) when is_atom(reason), do: bounded_failure_code(reason)
  defp failure_code(_reason), do: :project_snapshot_restore_failed

  defp bounded_failure_code(reason) do
    if reason |> Atom.to_string() |> byte_size() <= 100,
      do: reason,
      else: :project_snapshot_restore_failed
  end

  defp normalize_retry_reason(reason) when is_atom(reason), do: reason
  defp normalize_retry_reason({reason, _details}) when is_atom(reason), do: reason
  defp normalize_retry_reason(_reason), do: :project_snapshot_restore_failed

  defp normalize_discard_reason(reason) when is_atom(reason), do: reason
  defp normalize_discard_reason({reason, _details}) when is_atom(reason), do: reason
  defp normalize_discard_reason(_reason), do: :project_snapshot_restore_failed

  defp final_attempt?(opts) do
    attempt = Keyword.get(opts, :attempt, 1)
    max_attempts = Keyword.get(opts, :max_attempts, attempt)
    is_integer(attempt) and is_integer(max_attempts) and attempt >= max_attempts
  end

  defp terminal_perform_result(%ProjectSnapshotRestore{status: "completed"} = restore), do: {:ok, restore}

  defp terminal_perform_result(%ProjectSnapshotRestore{status: "failed"}),
    do: {:discard, :project_snapshot_restore_failed}

  defp normalize_lock_result({:error, :session_lock_timeout}), do: {:snooze, 30}
  defp normalize_lock_result(result), do: result

  defp lock_active_project(project_id) do
    Repo.one(
      from project in Project,
        where: project.id == ^project_id and is_nil(project.deleted_at),
        lock: "FOR UPDATE"
    )
  end

  defp lock_snapshot(snapshot_id, project_id) do
    Repo.one(
      from snapshot in ProjectSnapshot,
        where: snapshot.id == ^snapshot_id and snapshot.project_id == ^project_id,
        lock: "FOR SHARE"
    )
  end

  defp lock_restore(restore_id) do
    Repo.one(
      from restore in ProjectSnapshotRestore,
        where: restore.id == ^restore_id,
        lock: "FOR UPDATE"
    )
  end

  defp lock_job(nil), do: nil

  defp lock_job(job_id) do
    Repo.one(from job in Oban.Job, where: job.id == ^job_id, lock: "FOR UPDATE")
  end

  defp lock_reservation(nil), do: nil

  defp lock_reservation(reservation_id) do
    Repo.one(
      from reservation in StorageReservation,
        where: reservation.id == ^reservation_id,
        lock: "FOR UPDATE"
    )
  end

  defp restore_by_idempotency(workspace_id, idempotency_key) do
    Repo.get_by(ProjectSnapshotRestore,
      workspace_id: workspace_id,
      idempotency_key: idempotency_key
    )
  end

  defp normalize_idempotency_key(attrs) do
    attrs
    |> value(:idempotency_key)
    |> Ecto.UUID.cast()
    |> case do
      {:ok, idempotency_key} -> {:ok, idempotency_key}
      :error -> {:error, :invalid_project_snapshot_restore_request}
    end
  end

  defp snapshot_id(%ProjectSnapshot{id: snapshot_id}) when is_integer(snapshot_id) and snapshot_id > 0,
    do: {:ok, snapshot_id}

  defp snapshot_id(snapshot_id) when is_integer(snapshot_id) and snapshot_id > 0, do: {:ok, snapshot_id}

  defp snapshot_id(_snapshot), do: {:error, :invalid_project_snapshot_restore_request}

  defp positive_integer?(value), do: is_integer(value) and value > 0
  defp nonempty_binary?(value), do: is_binary(value) and value != ""
  defp valid_digest?(digest), do: is_binary(digest) and Regex.match?(@sha256, digest)

  defp value(attrs, key), do: Map.get(attrs, key, Map.get(attrs, Atom.to_string(key)))

  defp replay_completed_side_effects(%ProjectSnapshotRestore{status: "completed"} = restore) do
    if value(restore.result, :content_replaced) == true do
      project_id = restore.project_id
      shell_topic = "project:#{project_id}:shell"

      Collaboration.broadcast_dashboard_change(project_id, :all)
      Collaboration.broadcast_change({:project, project_id}, :tree_changed, %{})
      Collaboration.broadcast_change({:assets, project_id}, :asset_library_restored, %{})

      broadcast_replaced_entities(shell_topic, :sheet, value(restore.result, :replaced_sheet_ids))
      broadcast_replaced_entities(shell_topic, :flow, value(restore.result, :replaced_flow_ids))
      broadcast_replaced_entities(shell_topic, :scene, value(restore.result, :replaced_scene_ids))
      Phoenix.PubSub.broadcast(Storyarn.PubSub, shell_topic, {:languages_changed, nil})
      Phoenix.PubSub.broadcast(Storyarn.PubSub, shell_topic, {:project_restored, restore.id})
    end

    :ok
  end

  defp broadcast_replaced_entities(topic, type, ids) when is_list(ids) do
    if ids != [] and valid_entity_ids?(ids) do
      Phoenix.PubSub.broadcast(Storyarn.PubSub, topic, {:entities_deleted, type, ids})
    end

    :ok
  end

  defp broadcast_replaced_entities(_topic, _type, _ids), do: :ok

  defp valid_entity_ids?(ids) when is_list(ids) do
    length(ids) <= 100_000 and Enum.all?(ids, &(is_integer(&1) and &1 > 0)) and
      length(ids) == length(Enum.uniq(ids))
  end

  defp valid_entity_ids?(_ids), do: false

  defp broadcast_result({:ok, %ProjectSnapshotRestore{} = restore} = result) do
    broadcast(restore)
    result
  end

  defp broadcast_result({:ok, {_state, %ProjectSnapshotRestore{} = restore}} = result) do
    broadcast(restore)
    result
  end

  defp broadcast_result(result), do: result

  defp broadcast(%ProjectSnapshotRestore{} = restore) do
    Phoenix.PubSub.broadcast(
      Storyarn.PubSub,
      topic(restore.project_id),
      {:project_snapshot_restore_updated, restore.id}
    )

    :ok
  end

  defp topic(project_id), do: "project_snapshot_restores:#{project_id}"
end
