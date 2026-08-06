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
  alias Storyarn.Assets.StorageCleanupOwnershipReceipt
  alias Storyarn.Assets.StorageCompensation
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
  alias Storyarn.Versioning.SnapshotObjectPublicationClaim
  alias Storyarn.Versioning.SnapshotObjectStorage
  alias Storyarn.Versioning.SnapshotStorage
  alias Storyarn.Workers.BuildProjectSnapshotWorker

  require Logger

  @capture_timeout to_timeout(minute: 5)
  @active_build_states ~w(pending building verifying)
  @terminal_job_states ~w(completed discarded cancelled)
  @releasable_waiting_job_states ~w(available scheduled retryable)
  @build_worker inspect(BuildProjectSnapshotWorker)
  @stale_build_batch_size 50
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
      {:error, :snapshot_build_owned_by_another_job} -> {:discard, :snapshot_build_owned_by_another_job}
      {:error, :project_snapshot_not_found} -> settle_orphaned_build(snapshot_id, :project_snapshot_not_found)
      {:error, reason} -> {:discard, safe_error_code(reason)}
    end
  end

  def perform(_snapshot_id, _opts), do: {:discard, :invalid_snapshot_build_job}

  @doc false
  @spec heartbeat(pos_integer(), pos_integer()) :: :ok | {:error, :snapshot_build_not_active}
  def heartbeat(snapshot_id, job_id)
      when is_integer(snapshot_id) and snapshot_id > 0 and is_integer(job_id) and job_id > 0 do
    now = database_clock_now()

    {updated_count, _rows} =
      ProjectSnapshot
      |> join(:inner, [snapshot], job in Oban.Job, on: job.id == snapshot.build_job_id)
      |> where([snapshot, _job], snapshot.id == ^snapshot_id)
      |> where([snapshot, _job], snapshot.build_job_id == ^job_id)
      |> where([snapshot, _job], snapshot.lifecycle_state in ^@active_build_states)
      |> where([snapshot, _job], is_nil(snapshot.cancel_requested_at))
      |> where([_snapshot, job], job.worker == ^@build_worker)
      |> where([_snapshot, job], job.queue == "snapshots")
      |> where([_snapshot, job], job.state == "executing")
      |> Repo.update_all(set: [state_updated_at: now])

    if updated_count == 1, do: :ok, else: {:error, :snapshot_build_not_active}
  end

  def heartbeat(_snapshot_id, _job_id), do: {:error, :snapshot_build_not_active}

  @doc false
  @spec reconcile_stale_builds() :: %{
          failure_count: non_neg_integer(),
          orphaned_count: non_neg_integer(),
          settled_count: non_neg_integer()
        }
  def reconcile_stale_builds do
    stale_build_heartbeat_seconds = stale_build_heartbeat_seconds()
    advisory_now = database_clock_now()
    stale_before = DateTime.add(advisory_now, -stale_build_heartbeat_seconds, :second)

    advisory_now
    |> stale_build_candidates(stale_before)
    |> Enum.reduce(
      %{failure_count: 0, orphaned_count: 0, settled_count: 0},
      &reconcile_stale_build_candidate(&1, &2, stale_build_heartbeat_seconds)
    )
  end

  defp stale_build_candidates(now, stale_before) do
    active_orphan = active_orphan_dynamic(now, stale_before)
    released_gap = released_gap_dynamic(stale_before)
    recovery_candidate = dynamic([_snapshot, _project, _reservation, _job], ^active_orphan or ^released_gap)

    Repo.all(
      from(snapshot in ProjectSnapshot,
        join: project in Project,
        on: project.id == snapshot.project_id,
        join: reservation in StorageReservation,
        on: reservation.id == snapshot.storage_reservation_id,
        left_join: job in Oban.Job,
        on: job.id == snapshot.build_job_id,
        where:
          snapshot.lifecycle_state in ^@active_build_states and is_nil(project.deleted_at) and
            reservation.kind == "snapshot_build" and reservation.status in ["active", "released"],
        where: ^recovery_candidate,
        order_by: [asc: snapshot.id],
        limit: ^@stale_build_batch_size,
        select: %{
          snapshot_id: snapshot.id,
          workspace_id: project.workspace_id,
          reservation_id: reservation.id,
          job_id: job.id
        }
      )
    )
  end

  defp active_orphan_dynamic(now, stale_before) do
    active_orphan =
      dynamic(
        [snapshot, _project, reservation, job],
        reservation.status == "active" and reservation.expires_at <= ^now and
          job.worker == ^@build_worker and job.queue == "snapshots" and
          job.state == "executing" and job.attempted_at <= ^stale_before and
          snapshot.state_updated_at <= ^stale_before
      )

    active_orphan
  end

  defp released_gap_dynamic(stale_before) do
    released_job = released_job_dynamic(stale_before)

    dynamic(
      [_snapshot, _project, reservation, _job],
      reservation.status == "released" and ^released_job
    )
  end

  defp released_job_dynamic(stale_before) do
    waiting_or_terminal = released_waiting_or_terminal_dynamic()
    stale_executing = released_stale_executing_dynamic(stale_before)

    dynamic(
      [_snapshot, _project, _reservation, job],
      is_nil(job.id) or ^waiting_or_terminal or ^stale_executing
    )
  end

  defp released_waiting_or_terminal_dynamic do
    dynamic(
      [_snapshot, _project, _reservation, job],
      job.worker == ^@build_worker and job.queue == "snapshots" and
        job.state in ^(@terminal_job_states ++ @releasable_waiting_job_states)
    )
  end

  defp released_stale_executing_dynamic(stale_before) do
    dynamic(
      [snapshot, _project, _reservation, job],
      job.worker == ^@build_worker and job.queue == "snapshots" and
        job.state == "executing" and job.attempted_at <= ^stale_before and
        snapshot.state_updated_at <= ^stale_before
    )
  end

  defp reconcile_stale_build_candidate(candidate, counts, stale_build_heartbeat_seconds) do
    result =
      Billing.transact_with_workspace_lock(candidate.workspace_id, fn _workspace ->
        now = database_clock_now()
        stale_before = DateTime.add(now, -stale_build_heartbeat_seconds, :second)
        reconcile_stale_build_candidate_locked(candidate, now, stale_before)
      end)

    case result do
      {:ok, {:orphaned, _snapshot_id}} ->
        Map.update!(counts, :orphaned_count, &(&1 + 1))

      {:ok, {:settled, %ProjectSnapshot{} = snapshot}} ->
        broadcast(snapshot)
        Map.update!(counts, :settled_count, &(&1 + 1))

      {:error, :snapshot_build_recovery_candidate_changed} ->
        counts

      {:error, _reason} ->
        Map.update!(counts, :failure_count, &(&1 + 1))
    end
  end

  defp reconcile_stale_build_candidate_locked(candidate, now, stale_before) do
    snapshot = lock_snapshot(candidate.snapshot_id)
    reservation = lock_reservation(candidate.reservation_id)
    job = lock_build_job(candidate.job_id)

    with :ok <- validate_stale_build_identity(candidate, snapshot, reservation, job) do
      reconcile_stale_build_status(snapshot, reservation, job, now, stale_before)
    end
  end

  defp validate_stale_build_identity(
         candidate,
         %ProjectSnapshot{
           id: snapshot_id,
           project_id: project_id,
           object_prefix: object_prefix,
           storage_reservation_id: reservation_id,
           build_job_id: job_id,
           lifecycle_state: lifecycle_state
         },
         %StorageReservation{
           id: reservation_id,
           workspace_id_snapshot: workspace_id,
           project_id_snapshot: project_id,
           project_snapshot_id_snapshot: snapshot_id,
           cleanup_object_prefix: object_prefix,
           kind: "snapshot_build"
         },
         job
       ) do
    valid_job? =
      case {candidate.job_id, job} do
        {nil, nil} -> true
        {^job_id, %Oban.Job{id: ^job_id}} -> true
        _job -> false
      end

    if snapshot_id == candidate.snapshot_id and reservation_id == candidate.reservation_id and
         workspace_id == candidate.workspace_id and lifecycle_state in @active_build_states and valid_job?,
       do: :ok,
       else: {:error, :snapshot_build_recovery_candidate_changed}
  end

  defp validate_stale_build_identity(_candidate, _snapshot, _reservation, _job),
    do: {:error, :snapshot_build_recovery_candidate_changed}

  defp reconcile_stale_build_status(
         %ProjectSnapshot{} = snapshot,
         %StorageReservation{status: "active"} = reservation,
         %Oban.Job{} = job,
         now,
         stale_before
       ) do
    claim = lock_publication_claim_for_reservation(reservation.id)

    with true <- DateTime.compare(reservation.expires_at, now) in [:lt, :eq],
         :ok <- validate_stale_executing_job(snapshot, job, stale_before),
         :ok <- validate_inactive_publication_claim(reservation, claim, now, stale_before),
         {:ok, _job} <- discard_orphaned_build_job(job, now) do
      {:ok, {:orphaned, snapshot.id}}
    else
      false -> {:error, :snapshot_build_recovery_candidate_changed}
      {:error, _reason} = error -> error
    end
  end

  defp reconcile_stale_build_status(
         %ProjectSnapshot{} = snapshot,
         %StorageReservation{status: "released"} = reservation,
         job,
         now,
         stale_before
       ) do
    with :ok <- validate_released_cleanup_proof(snapshot, reservation),
         :ok <- settle_released_build_job(snapshot, job, now, stale_before),
         {:ok, terminal} <- terminalize_released_build(snapshot, reservation, now) do
      {:ok, {:settled, terminal}}
    end
  end

  defp reconcile_stale_build_status(_snapshot, _reservation, _job, _now, _stale_before),
    do: {:error, :snapshot_build_recovery_candidate_changed}

  defp validate_stale_executing_job(snapshot, %Oban.Job{} = job, stale_before) do
    stale? =
      job.id == snapshot.build_job_id and job.worker == @build_worker and job.queue == "snapshots" and
        job.state == "executing" and old_enough?(job.attempted_at, stale_before) and
        old_enough?(snapshot.state_updated_at, stale_before)

    if stale?, do: :ok, else: {:error, :snapshot_build_recovery_candidate_changed}
  end

  defp validate_inactive_publication_claim(%StorageReservation{storage_started_at: nil}, nil, _now, _stale_before),
    do: :ok

  defp validate_inactive_publication_claim(
         %StorageReservation{storage_started_at: nil} = reservation,
         %SnapshotObjectPublicationClaim{status: "staging"} = claim,
         now,
         stale_before
       ) do
    validate_expired_claim_binding(reservation, claim, now, stale_before)
  end

  defp validate_inactive_publication_claim(
         %StorageReservation{storage_started_at: %DateTime{}} = reservation,
         %SnapshotObjectPublicationClaim{status: status} = claim,
         now,
         stale_before
       )
       when status in ["staging", "publishing"] do
    validate_expired_claim_binding(reservation, claim, now, stale_before)
  end

  defp validate_inactive_publication_claim(
         %StorageReservation{storage_started_at: %DateTime{}} = reservation,
         %SnapshotObjectPublicationClaim{status: status} = claim,
         _now,
         stale_before
       )
       when status in ["staged", "published"] do
    with :ok <- validate_claim_binding(reservation, claim),
         true <- old_enough?(claim.updated_at, stale_before) do
      :ok
    else
      _invalid -> {:error, :snapshot_build_recovery_candidate_changed}
    end
  end

  defp validate_inactive_publication_claim(
         %StorageReservation{} = reservation,
         %SnapshotObjectPublicationClaim{status: "poisoned"} = claim,
         _now,
         stale_before
       ) do
    with :ok <- validate_claim_binding(reservation, claim),
         true <- old_enough?(claim.updated_at, stale_before) do
      :ok
    else
      _invalid -> {:error, :snapshot_build_recovery_candidate_changed}
    end
  end

  defp validate_inactive_publication_claim(_reservation, _claim, _now, _stale_before),
    do: {:error, :snapshot_build_recovery_candidate_changed}

  defp validate_expired_claim_binding(reservation, claim, now, stale_before) do
    with :ok <- validate_claim_binding(reservation, claim),
         %DateTime{} = lease_expires_at <- claim.lease_expires_at,
         true <- DateTime.compare(lease_expires_at, now) in [:lt, :eq],
         true <- old_enough?(claim.updated_at, stale_before) do
      :ok
    else
      _invalid -> {:error, :snapshot_build_recovery_candidate_changed}
    end
  end

  defp validate_claim_binding(
         %StorageReservation{id: reservation_id, lease_token: lease_token, cleanup_object_prefix: object_prefix},
         %SnapshotObjectPublicationClaim{
           object_prefix: object_prefix,
           storage_reservation_id_snapshot: reservation_id,
           storage_reservation_lease_token: lease_token
         }
       ), do: :ok

  defp validate_claim_binding(_reservation, _claim), do: {:error, :snapshot_build_recovery_candidate_changed}

  defp validate_released_cleanup_proof(_snapshot, %StorageReservation{
         cleanup_status: "not_required",
         storage_started_at: nil,
         storage_namespace: storage_namespace,
         cleanup_reference: "storage_not_started:" <> storage_namespace
       }), do: :ok

  defp validate_released_cleanup_proof(
         %ProjectSnapshot{} = snapshot,
         %StorageReservation{cleanup_status: "owned", cleanup_reference: cleanup_reference} = reservation
       ) do
    with {:ok, cleanup_request_id} <- cleanup_request_id(cleanup_reference),
         {:ok, receipt_keys} <- StorageCleanupOwnershipReceipt.storage_keys(cleanup_request_id),
         %ProjectSnapshotCapture{} = capture <- Repo.get(ProjectSnapshotCapture, snapshot.id),
         {:ok, scope} <-
           SnapshotObjectStorage.cleanup_scope_from_capture(
             snapshot.project_id,
             snapshot.object_prefix,
             capture.manifest_json
           ),
         true <- reservation.cleanup_inventory_count == length(scope.storage_keys),
         true <- reservation.cleanup_inventory_digest == scope.inventory_digest,
         true <- same_cleanup_inventory?(receipt_keys, scope.storage_keys) do
      :ok
    else
      _invalid -> {:error, :snapshot_build_recovery_candidate_changed}
    end
  end

  defp validate_released_cleanup_proof(_snapshot, _reservation), do: {:error, :snapshot_build_recovery_candidate_changed}

  defp cleanup_request_id("storage_cleanup_request:" <> encoded_id) do
    case Integer.parse(encoded_id) do
      {cleanup_request_id, ""} when cleanup_request_id > 0 -> {:ok, cleanup_request_id}
      _invalid -> {:error, :invalid_cleanup_reference}
    end
  end

  defp cleanup_request_id(_cleanup_reference), do: {:error, :invalid_cleanup_reference}

  defp same_cleanup_inventory?(left, right) when is_list(left) and is_list(right) do
    length(left) == length(right) and MapSet.equal?(MapSet.new(left), MapSet.new(right))
  end

  defp same_cleanup_inventory?(_left, _right), do: false

  defp settle_released_build_job(_snapshot, nil, _now, _stale_before), do: :ok

  defp settle_released_build_job(
         snapshot,
         %Oban.Job{worker: @build_worker, queue: "snapshots", state: state},
         _now,
         _stale_before
       )
       when state in @terminal_job_states do
    if snapshot.build_job_id, do: :ok, else: {:error, :snapshot_build_recovery_candidate_changed}
  end

  defp settle_released_build_job(
         %ProjectSnapshot{build_job_id: job_id},
         %Oban.Job{id: job_id, worker: @build_worker, queue: "snapshots", state: state} = job,
         now,
         _stale_before
       )
       when state in @releasable_waiting_job_states do
    job
    |> discard_orphaned_build_job(now)
    |> normalize_released_build_job_discard()
  end

  defp settle_released_build_job(snapshot, %Oban.Job{} = job, now, stale_before) do
    with :ok <- validate_stale_executing_job(snapshot, job, stale_before),
         {:ok, _job} <- discard_orphaned_build_job(job, now) do
      :ok
    end
  end

  defp normalize_released_build_job_discard({:ok, %Oban.Job{}}), do: :ok
  defp normalize_released_build_job_discard({:error, reason}), do: {:error, reason}

  defp terminalize_released_build(%ProjectSnapshot{cancel_requested_at: %DateTime{}} = snapshot, _reservation, now) do
    snapshot
    |> ProjectSnapshot.build_state_changeset(%{
      lifecycle_state: "cancelled",
      integrity_state: "unknown",
      progress_phase: "cancelled",
      failure_code: nil,
      failure_message: nil,
      failed_at: nil,
      cancelled_at: now,
      state_updated_at: now
    })
    |> persist_terminal_snapshot()
  end

  defp terminalize_released_build(%ProjectSnapshot{lifecycle_state: state} = snapshot, reservation, now)
       when state in ["building", "verifying"] do
    code = released_failure_code(reservation.release_reason)

    snapshot
    |> ProjectSnapshot.build_state_changeset(%{
      lifecycle_state: "failed",
      integrity_state: released_failure_integrity(code),
      progress_phase: "failed",
      failure_code: code,
      failure_message: Map.fetch!(@safe_failure_messages, code),
      failed_at: now,
      state_updated_at: now
    })
    |> persist_terminal_snapshot()
  end

  defp terminalize_released_build(_snapshot, _reservation, _now), do: {:error, :snapshot_build_recovery_candidate_changed}

  defp released_failure_code(code) when is_binary(code) do
    if Map.has_key?(@safe_failure_messages, code), do: code, else: "build_failed"
  end

  defp released_failure_code(_code), do: "build_failed"

  defp released_failure_integrity("source_missing"), do: "missing"
  defp released_failure_integrity("source_corrupt"), do: "corrupt"
  defp released_failure_integrity(_code), do: "incomplete"

  defp discard_orphaned_build_job(job, now) do
    job
    |> Ecto.Changeset.change(state: "discarded", discarded_at: %{now | microsecond: {0, 6}})
    |> Repo.update()
  end

  defp old_enough?(%DateTime{} = value, %DateTime{} = cutoff), do: DateTime.compare(value, cutoff) in [:lt, :eq]

  defp old_enough?(_value, _cutoff), do: false

  defp database_clock_now do
    %Postgrex.Result{rows: [[now]]} = Repo.query!("SELECT clock_timestamp()")
    DateTime.truncate(now, :second)
  end

  defp stale_build_heartbeat_seconds do
    :storyarn
    |> Application.fetch_env!(:snapshot_lifecycle)
    |> Keyword.fetch!(:stale_build_heartbeat_seconds)
    |> case do
      seconds when is_integer(seconds) and seconds >= 0 -> seconds
      invalid -> raise ArgumentError, "invalid stale build heartbeat seconds: #{inspect(invalid)}"
    end
  end

  defp lock_build_job(nil), do: nil

  defp lock_build_job(job_id) when is_integer(job_id) do
    Repo.one(from(job in Oban.Job, where: job.id == ^job_id, lock: "FOR UPDATE"))
  end

  defp lock_build_job(_job_id), do: nil

  defp lock_publication_claim_for_reservation(reservation_id) do
    Repo.one(
      from(claim in SnapshotObjectPublicationClaim,
        where: claim.storage_reservation_id_snapshot == ^reservation_id,
        lock: "FOR UPDATE"
      )
    )
  end

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
    case load_build_inputs(snapshot.id, snapshot.lifecycle_generation) do
      {:ok, build} ->
        if build.snapshot.cancel_requested_at do
          settle_cancelled(build.snapshot, :snapshot_build_cancelled, attempt, max_attempts)
        else
          execute_build(build, attempt, max_attempts)
        end

      {:error, reason} ->
        finish_failure(snapshot.id, snapshot.lifecycle_generation, reason, attempt, max_attempts)
    end
  end

  defp execute_build(build, attempt, max_attempts) do
    token = object_token(build.snapshot)
    generation = build.snapshot.lifecycle_generation

    opts = [
      token: token,
      storage_reservation: build.reservation,
      before_stage: &authorize_stage(build.snapshot.id, generation, &1),
      before_publish: &authorize_publication(build.snapshot.id, generation, &1),
      on_progress: copy_progress_callback(build.snapshot.id, generation, build.snapshot.total_size_bytes)
    ]

    with token when is_binary(token) <- token,
         {:ok, staged} <- SnapshotObjectStorage.stage_prepared(build.snapshot.project_id, build.prepared, opts),
         {:ok, _snapshot} <- mark_verifying(build.snapshot.id, generation, staged.total_size_bytes),
         {:ok, stored} <-
           SnapshotObjectStorage.publish(
             staged,
             &authorize_publication(build.snapshot.id, generation, &1),
             on_progress: build_fence_callback(build.snapshot.id, generation)
           ),
         {:ok, snapshot} <- commit_ready(build.snapshot.id, generation, stored) do
      broadcast(snapshot)
      {:ok, snapshot}
    else
      nil ->
        finish_failure(
          build.snapshot.id,
          generation,
          :invalid_snapshot_object_prefix,
          attempt,
          max_attempts
        )

      {:error, reason} ->
        finish_failure(build.snapshot.id, generation, reason, attempt, max_attempts)
    end
  end

  defp authorize_stage(snapshot_id, expected_generation, staged) do
    with workspace_id when is_integer(workspace_id) <- snapshot_workspace_id(snapshot_id),
         {:ok, reservation} <-
           Billing.transact_with_workspace_lock(workspace_id, fn _workspace ->
             authorize_stage_locked(snapshot_id, expected_generation, staged)
           end) do
      {:ok, reservation}
    else
      nil -> {:error, :project_snapshot_not_found}
      {:error, reason} -> {:error, reason}
    end
  end

  defp authorize_stage_locked(snapshot_id, expected_generation, staged) do
    snapshot = lock_snapshot(snapshot_id)
    reservation = lock_reservation(staged.storage_reservation_id)

    with %ProjectSnapshot{
           lifecycle_generation: ^expected_generation,
           cancel_requested_at: nil,
           storage_reservation_id: reservation_id
         } <- snapshot,
         %StorageReservation{id: ^reservation_id, status: "active"} <- reservation,
         :ok <- validate_executing_build_job(snapshot),
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

  defp mark_verifying(snapshot_id, expected_generation, progress_bytes) do
    update_build_state(snapshot_id, expected_generation, fn snapshot ->
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

  defp copy_progress_callback(snapshot_id, expected_generation, total_bytes) do
    checkpoint = :atomics.new(2, signed: true)
    :atomics.put(checkpoint, 1, 0)
    :atomics.put(checkpoint, 2, System.monotonic_time(:millisecond))

    fn completed_bytes ->
      with :ok <- validate_build_fence(snapshot_id, expected_generation),
           do:
             maybe_persist_progress_checkpoint(
               snapshot_id,
               expected_generation,
               completed_bytes,
               total_bytes,
               checkpoint
             )
    end
  end

  defp build_fence_callback(snapshot_id, expected_generation) do
    fn _completed_bytes -> validate_build_fence(snapshot_id, expected_generation) end
  end

  defp progress_checkpoint_due?(completed_bytes, total_bytes, last_bytes, last_at, now) do
    completed_bytes >= total_bytes or completed_bytes - last_bytes >= @progress_checkpoint_bytes or
      now - last_at >= @progress_checkpoint_ms
  end

  defp maybe_persist_progress_checkpoint(snapshot_id, expected_generation, completed_bytes, total_bytes, checkpoint) do
    last_bytes = :atomics.get(checkpoint, 1)
    last_at = :atomics.get(checkpoint, 2)
    now = System.monotonic_time(:millisecond)

    if progress_checkpoint_due?(completed_bytes, total_bytes, last_bytes, last_at, now) do
      persist_progress_checkpoint(snapshot_id, expected_generation, completed_bytes, checkpoint, now)
    else
      :ok
    end
  end

  defp persist_progress_checkpoint(snapshot_id, expected_generation, completed_bytes, checkpoint, now) do
    with :ok <- persist_copy_progress(snapshot_id, expected_generation, completed_bytes) do
      :atomics.put(checkpoint, 1, completed_bytes)
      :atomics.put(checkpoint, 2, now)
      :ok
    end
  end

  defp persist_copy_progress(snapshot_id, expected_generation, completed_bytes) do
    result =
      Repo.transact(fn ->
        snapshot_id
        |> lock_snapshot()
        |> persist_copy_progress_locked(expected_generation, completed_bytes)
      end)

    case result do
      {:ok, %ProjectSnapshot{} = snapshot} ->
        broadcast(snapshot)
        :ok

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp persist_copy_progress_locked(
         %ProjectSnapshot{lifecycle_generation: generation},
         expected_generation,
         _completed_bytes
       )
       when generation != expected_generation, do: {:error, :stale_snapshot_build_generation}

  defp persist_copy_progress_locked(
         %ProjectSnapshot{cancel_requested_at: %DateTime{}},
         _expected_generation,
         _completed_bytes
       ), do: {:error, :snapshot_build_cancelled}

  defp persist_copy_progress_locked(
         %ProjectSnapshot{lifecycle_state: "building"} = snapshot,
         _expected_generation,
         completed_bytes
       ) do
    with :ok <- validate_executing_build_job(snapshot) do
      snapshot
      |> ProjectSnapshot.build_state_changeset(%{
        progress_phase: "copying",
        progress_bytes: max(snapshot.progress_bytes, completed_bytes),
        state_updated_at: TimeHelpers.now()
      })
      |> Repo.update()
    end
  end

  defp persist_copy_progress_locked(%ProjectSnapshot{}, _expected_generation, _completed_bytes),
    do: {:error, :snapshot_build_state_conflict}

  defp persist_copy_progress_locked(nil, _expected_generation, _completed_bytes),
    do: {:error, :project_snapshot_not_found}

  @doc false
  def validate_build_fence(snapshot_id, expected_generation) do
    result =
      Repo.transact(fn ->
        snapshot_id
        |> lock_snapshot()
        |> validate_build_fence_locked(expected_generation)
      end)

    case result do
      {:ok, :authorized} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp validate_build_fence_locked(
         %ProjectSnapshot{lifecycle_generation: expected_generation, lifecycle_state: state, cancel_requested_at: nil} =
           snapshot,
         expected_generation
       )
       when state in ["building", "verifying"] do
    with :ok <- validate_executing_build_job(snapshot), do: {:ok, :authorized}
  end

  defp validate_build_fence_locked(%ProjectSnapshot{lifecycle_generation: generation}, expected_generation)
       when generation != expected_generation, do: {:error, :stale_snapshot_build_generation}

  defp validate_build_fence_locked(%ProjectSnapshot{cancel_requested_at: %DateTime{}}, _expected_generation),
    do: {:error, :snapshot_build_cancelled}

  defp validate_build_fence_locked(%ProjectSnapshot{}, _expected_generation), do: {:error, :snapshot_build_state_conflict}

  defp validate_build_fence_locked(nil, _expected_generation), do: {:error, :project_snapshot_not_found}

  defp authorize_publication(snapshot_id, expected_generation, staged) do
    with workspace_id when is_integer(workspace_id) <- snapshot_workspace_id(snapshot_id),
         {:ok, reservation} <-
           Billing.transact_with_workspace_lock(workspace_id, fn _workspace ->
             authorize_publication_locked(snapshot_id, expected_generation, staged)
           end) do
      {:ok, reservation}
    else
      nil -> {:error, :project_snapshot_not_found}
      {:error, reason} -> {:error, reason}
    end
  end

  defp authorize_publication_locked(snapshot_id, expected_generation, staged) do
    snapshot = lock_snapshot(snapshot_id)
    reservation = snapshot && lock_reservation(snapshot.storage_reservation_id)

    with %ProjectSnapshot{lifecycle_generation: ^expected_generation, cancel_requested_at: nil} <- snapshot,
         %StorageReservation{status: "active"} <- reservation,
         :ok <- validate_executing_build_job(snapshot),
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

  defp commit_ready(snapshot_id, expected_generation, stored) do
    snapshot = Repo.get_by(ProjectSnapshot, id: snapshot_id, lifecycle_generation: expected_generation)
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
             fn _reservation -> finalize_ready_snapshot(snapshot, expected_generation, stored, now) end
           ) do
      {:ok, ready_snapshot}
    else
      nil -> {:error, :snapshot_build_state_missing}
      {:error, reason} -> {:error, reason}
    end
  end

  defp finalize_ready_snapshot(snapshot, expected_generation, stored, now) do
    with :ok <- validate_executing_build_job(snapshot) do
      ProjectSnapshotCrud.finalize_object_set(
        snapshot.id,
        0,
        Map.merge(stored, %{
          expected_lifecycle_generation: expected_generation,
          progress_phase: "complete",
          progress_bytes: stored.total_size_bytes,
          progress_total_bytes: stored.total_size_bytes,
          verifying_started_at: snapshot.verifying_started_at || now,
          ready_at: now,
          state_updated_at: now
        })
      )
    end
  end

  defp finish_failure(snapshot_id, expected_generation, reason, attempt, max_attempts) do
    snapshot = Repo.get(ProjectSnapshot, snapshot_id)

    cond do
      is_nil(snapshot) ->
        settle_orphaned_build(snapshot_id, reason)

      snapshot.lifecycle_generation != expected_generation and not is_nil(snapshot.cancel_requested_at) ->
        settle_cancelled(snapshot, reason, attempt, max_attempts)

      snapshot.lifecycle_generation != expected_generation ->
        {:discard, :stale_snapshot_build_generation}

      snapshot.lifecycle_state == "ready" ->
        {:ok, snapshot}

      cancelled_reason?(reason) or not is_nil(snapshot.cancel_requested_at) ->
        settle_cancelled(snapshot, reason, attempt, max_attempts)

      true ->
        settle_or_snooze_failed_build(snapshot, reason, attempt, max_attempts)
    end
  end

  defp settle_or_snooze_failed_build(snapshot, reason, attempt, max_attempts) do
    if build_already_in_progress?(reason),
      do: {:snooze, 30},
      else: settle_failed_build(snapshot, reason, attempt, max_attempts)
  end

  defp settle_failed_build(snapshot, reason, attempt, max_attempts) do
    cleanup_scope = cleanup_scope(reason)

    snapshot
    |> settle_active_reservation(reason, cleanup_scope)
    |> handle_failed_settlement(snapshot, reason, attempt, max_attempts)
  end

  defp handle_failed_settlement({:ok, :released}, snapshot, reason, attempt, max_attempts) do
    cond do
      build_fence_lost?(reason) ->
        {:discard, :snapshot_build_job_not_executing}

      attempt < max_attempts and retryable?(reason) ->
        retry_failed_snapshot(snapshot, reason, attempt + 1, attempt, max_attempts)

      true ->
        fail_snapshot(snapshot, reason, attempt, max_attempts)
    end
  end

  defp handle_failed_settlement({:ok, :committed}, _snapshot, reason, attempt, max_attempts) when attempt < max_attempts,
    do: {:retry, safe_error_code(reason)}

  defp handle_failed_settlement({:ok, :active_unowned}, snapshot, _reason, attempt, max_attempts),
    do: retry_unsettled(snapshot, attempt, max_attempts)

  defp handle_failed_settlement({:ok, :committed}, _snapshot, _reason, attempt, max_attempts),
    do: retry_or_discard(:snapshot_build_settlement_committed, attempt, max_attempts)

  defp handle_failed_settlement({:error, _settlement_reason}, snapshot, _reason, attempt, max_attempts),
    do: retry_unsettled(snapshot, attempt, max_attempts)

  defp build_fence_lost?(:snapshot_build_job_not_executing), do: true

  defp build_fence_lost?(reason) when is_tuple(reason) do
    reason
    |> Tuple.to_list()
    |> Enum.any?(&build_fence_lost?/1)
  end

  defp build_fence_lost?(reason) when is_list(reason), do: Enum.any?(reason, &build_fence_lost?/1)
  defp build_fence_lost?(_reason), do: false

  defp retry_unsettled(snapshot, attempt, max_attempts) do
    if attempt < max_attempts,
      do: {:retry, :cleanup_unowned},
      else: fail_snapshot(snapshot, :cleanup_unowned, attempt, max_attempts)
  end

  defp retry_or_discard(code, attempt, max_attempts) when is_atom(code) do
    if attempt < max_attempts do
      {:retry, code}
    else
      Logger.error(
        "Project snapshot build exhausted its settlement retry budget: " <>
          "reason=#{code} attempt=#{attempt} max_attempts=#{max_attempts}"
      )

      {:discard, code}
    end
  end

  defp retry_failed_snapshot(snapshot, reason, operation_attempt, attempt, max_attempts) do
    case allocate_retry(snapshot, operation_attempt) do
      {:ok, retried} ->
        broadcast(retried)
        {:retry, safe_error_code(reason)}

      {:error, retry_reason} ->
        fail_snapshot(snapshot, retry_reason, attempt, max_attempts)
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
    |> ProjectSnapshot.retry_state_changeset(%{
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

  defp fail_snapshot(%ProjectSnapshot{} = snapshot, reason, attempt, max_attempts) do
    code = safe_error_code(reason)
    now = TimeHelpers.now()

    case update_terminal_build_state(snapshot.id, snapshot.lifecycle_generation, fn snapshot ->
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
        retry_or_discard(code, attempt, max_attempts)
    end
  end

  defp settle_cancelled(snapshot, reason, attempt, max_attempts) do
    case settle_cancelled_reservation(snapshot, reason) do
      {:ok, :released} -> mark_cancelled(snapshot.id, snapshot.lifecycle_generation, attempt, max_attempts)
      {:ok, :committed} -> retry_or_discard(:snapshot_build_cancelled_after_publish, attempt, max_attempts)
      {:ok, :active_unowned} -> retry_unsettled(snapshot, attempt, max_attempts)
      {:error, _settlement_reason} -> retry_unsettled(snapshot, attempt, max_attempts)
    end
  end

  defp settle_cancelled_reservation(snapshot, reason) do
    case Repo.get(StorageReservation, snapshot.storage_reservation_id) do
      %StorageReservation{status: "released"} ->
        {:ok, :released}

      %StorageReservation{status: "committed"} ->
        {:ok, :committed}

      %StorageReservation{status: "active", storage_started_at: nil} = reservation ->
        release_reservation(reservation, :snapshot_build_cancelled, :storage_not_started)

      %StorageReservation{status: "active"} = reservation ->
        with {:ok, canonical_scope} <- cancelled_cleanup_scope(snapshot, reservation),
             :ok <- poison_cancelled_publication_claim(reservation),
             {:ok, owned_scope} <- ensure_cancelled_cleanup_handoff(canonical_scope, reason) do
          release_reservation(
            reservation,
            :snapshot_build_cancelled,
            {:owned, owned_scope}
          )
        end

      nil ->
        {:error, :storage_reservation_not_found}
    end
  end

  defp cancelled_cleanup_scope(
         %ProjectSnapshot{
           id: snapshot_id,
           project_id: project_id,
           object_prefix: object_prefix,
           storage_reservation_id: reservation_id,
           capture_boundary: capture_boundary,
           capture_digest: capture_digest
         },
         %StorageReservation{
           id: reservation_id,
           kind: "snapshot_build",
           cleanup_object_prefix: object_prefix,
           cleanup_inventory_digest: inventory_digest,
           cleanup_inventory_count: inventory_count
         }
       ) do
    with %ProjectSnapshotCapture{
           capture_boundary: ^capture_boundary,
           capture_digest: ^capture_digest,
           manifest_json: manifest_json
         } <- Repo.get(ProjectSnapshotCapture, snapshot_id),
         {:ok, scope} <-
           SnapshotObjectStorage.cleanup_scope_from_capture(
             project_id,
             object_prefix,
             manifest_json
           ),
         true <- inventory_count == length(scope.storage_keys),
         true <- inventory_digest == scope.inventory_digest do
      {:ok, scope}
    else
      _invalid -> {:error, :snapshot_cancel_cleanup_inventory_mismatch}
    end
  end

  defp cancelled_cleanup_scope(_snapshot, _reservation), do: {:error, :snapshot_cancel_cleanup_reservation_mismatch}

  defp poison_cancelled_publication_claim(%StorageReservation{} = reservation) do
    result =
      Repo.transact(fn ->
        reservation
        |> lock_cancelled_publication_claim()
        |> poison_cancelled_publication_claim_locked(reservation)
      end)

    case result do
      {:ok, :poisoned} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp lock_cancelled_publication_claim(%StorageReservation{id: reservation_id}) do
    Repo.one(
      from(claim in SnapshotObjectPublicationClaim,
        where: claim.storage_reservation_id_snapshot == ^reservation_id,
        lock: "FOR UPDATE"
      )
    )
  end

  defp poison_cancelled_publication_claim_locked(%SnapshotObjectPublicationClaim{status: status}, _reservation)
       when status in ["staging", "publishing"], do: {:error, :snapshot_build_writer_may_still_be_active}

  defp poison_cancelled_publication_claim_locked(
         %SnapshotObjectPublicationClaim{
           object_prefix: object_prefix,
           storage_reservation_lease_token: lease_token,
           status: status
         } = claim,
         %StorageReservation{cleanup_object_prefix: object_prefix, lease_token: lease_token}
       )
       when status in ["staging", "staged", "publishing", "poisoned"] do
    claim
    |> SnapshotObjectPublicationClaim.status_changeset("poisoned")
    |> Repo.update()
    |> normalize_cancelled_claim_update()
  end

  defp poison_cancelled_publication_claim_locked(%SnapshotObjectPublicationClaim{status: "published"}, _reservation),
    do: {:error, :snapshot_build_cancelled_after_publish}

  defp poison_cancelled_publication_claim_locked(_claim, _reservation),
    do: {:error, :snapshot_object_publication_claim_not_poisoned}

  defp normalize_cancelled_claim_update({:ok, _claim}), do: {:ok, :poisoned}
  defp normalize_cancelled_claim_update({:error, changeset}), do: {:error, changeset}

  defp ensure_cancelled_cleanup_handoff(canonical_scope, reason) do
    reason_scope = cleanup_scope(reason)

    if matching_cleanup_handoff?(canonical_scope, reason_scope) do
      {:ok,
       Map.put(
         canonical_scope,
         :cleanup_request_id,
         value(reason_scope, :cleanup_request_id)
       )}
    else
      case persist_cancelled_cleanup_request(canonical_scope.storage_keys) do
        {:ok, cleanup_request} ->
          {:ok, Map.put(canonical_scope, :cleanup_request_id, cleanup_request.id)}

        {:error, handoff_reason} ->
          {:error, {:snapshot_cancel_cleanup_handoff_failed, handoff_reason}}
      end
    end
  end

  defp persist_cancelled_cleanup_request(storage_keys) do
    storage_keys = Enum.sort(storage_keys)

    persist_fun =
      case Application.get_env(:storyarn, __MODULE__, []) do
        opts when is_list(opts) ->
          case Keyword.get(opts, :cancel_cleanup_persist_fun) do
            callback when is_function(callback, 1) -> callback
            _invalid -> &StorageCompensation.persist_planned_cleanup_request/1
          end

        _invalid ->
          &StorageCompensation.persist_planned_cleanup_request/1
      end

    case existing_cancelled_cleanup_receipt(storage_keys) do
      {:ok, cleanup_request_id} ->
        {:ok, %{id: cleanup_request_id}}

      :missing ->
        persist_cancelled_cleanup_request(persist_fun, storage_keys)
    end
  end

  defp persist_cancelled_cleanup_request(persist_fun, storage_keys) do
    case persist_fun.(storage_keys) do
      {:ok, %{id: id} = cleanup_request} when is_integer(id) and id > 0 ->
        {:ok, cleanup_request}

      {:error, reason} ->
        case existing_cancelled_cleanup_receipt(storage_keys) do
          {:ok, cleanup_request_id} -> {:ok, %{id: cleanup_request_id}}
          :missing -> {:error, reason}
        end

      invalid ->
        {:error, {:invalid_snapshot_cancel_cleanup_handoff_result, invalid}}
    end
  rescue
    exception ->
      {:error, {:snapshot_cancel_cleanup_handoff_raised, exception.__struct__, Exception.message(exception)}}
  catch
    kind, reason ->
      {:error, {:snapshot_cancel_cleanup_handoff_caught, kind, reason}}
  end

  defp existing_cancelled_cleanup_receipt(storage_keys) do
    case Repo.one(
           from(receipt in StorageCleanupOwnershipReceipt,
             where: receipt.storage_keys == ^storage_keys,
             order_by: [desc: receipt.cleanup_request_id],
             limit: 1,
             select: receipt.cleanup_request_id
           )
         ) do
      cleanup_request_id when is_integer(cleanup_request_id) and cleanup_request_id > 0 ->
        {:ok, cleanup_request_id}

      _missing ->
        :missing
    end
  end

  defp matching_cleanup_handoff?(canonical_scope, reason_scope) when is_map(reason_scope) do
    cleanup_request_id = value(reason_scope, :cleanup_request_id)
    storage_keys = value(reason_scope, :storage_keys)

    is_integer(cleanup_request_id) and cleanup_request_id > 0 and is_list(storage_keys) and
      length(storage_keys) == length(canonical_scope.storage_keys) and
      MapSet.equal?(MapSet.new(storage_keys), MapSet.new(canonical_scope.storage_keys))
  end

  defp matching_cleanup_handoff?(_canonical_scope, _reason_scope), do: false

  defp mark_cancelled(snapshot_id, expected_generation, attempt, max_attempts) do
    now = TimeHelpers.now()

    case update_terminal_build_state(snapshot_id, expected_generation, fn snapshot ->
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

      {:error, _reason} ->
        retry_or_discard(:build_failed, attempt, max_attempts)
    end
  end

  defp cancel_locked(project_id, snapshot_id) do
    case lock_snapshot(project_id, snapshot_id) do
      nil ->
        {:error, :project_snapshot_not_found}

      %ProjectSnapshot{lifecycle_state: state} = snapshot
      when state in ["ready", "failed", "cancelled", "deleting"] ->
        {:ok, snapshot}

      %ProjectSnapshot{cancel_requested_at: %DateTime{}} = snapshot ->
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
    |> ProjectSnapshot.cancel_request_changeset(now)
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

  defp load_build_inputs(snapshot_id, expected_generation) do
    snapshot =
      case Repo.get_by(ProjectSnapshot, id: snapshot_id, lifecycle_generation: expected_generation) do
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

  defp update_build_state(snapshot_id, expected_generation, changeset_fun) do
    Repo.transact(fn ->
      snapshot_id
      |> lock_snapshot()
      |> update_build_state_locked(expected_generation, changeset_fun)
    end)
  end

  defp update_build_state_locked(
         %ProjectSnapshot{lifecycle_generation: expected_generation} = snapshot,
         expected_generation,
         changeset_fun
       ) do
    with :ok <- validate_executing_build_job(snapshot) do
      snapshot |> changeset_fun.() |> Repo.update()
    end
  end

  defp update_build_state_locked(%ProjectSnapshot{}, _expected_generation, _changeset_fun),
    do: {:error, :stale_snapshot_build_generation}

  defp update_build_state_locked(nil, _expected_generation, _changeset_fun), do: {:error, :project_snapshot_not_found}

  defp validate_executing_build_job(%ProjectSnapshot{build_job_id: job_id}) when is_integer(job_id) and job_id > 0 do
    case lock_build_job(job_id) do
      %Oban.Job{
        id: ^job_id,
        worker: @build_worker,
        queue: "snapshots",
        state: "executing"
      } ->
        :ok

      _job ->
        {:error, :snapshot_build_job_not_executing}
    end
  end

  defp validate_executing_build_job(_snapshot), do: {:error, :snapshot_build_job_not_executing}

  defp update_terminal_build_state(snapshot_id, expected_generation, changeset_fun) do
    Repo.transact(fn ->
      case lock_snapshot(snapshot_id) do
        %ProjectSnapshot{lifecycle_generation: ^expected_generation} = snapshot ->
          snapshot |> changeset_fun.() |> persist_terminal_snapshot()

        %ProjectSnapshot{} ->
          {:error, :stale_snapshot_build_generation}

        nil ->
          {:error, :project_snapshot_not_found}
      end
    end)
  end

  defp persist_terminal_snapshot(changeset) do
    persist_fun =
      case Application.get_env(:storyarn, __MODULE__, []) do
        opts when is_list(opts) ->
          case Keyword.get(opts, :terminal_state_persist_fun) do
            callback when is_function(callback, 1) -> callback
            _invalid -> &Repo.update/1
          end

        _invalid ->
          &Repo.update/1
      end

    case persist_fun.(changeset) do
      {:ok, %ProjectSnapshot{}} = success -> success
      {:error, reason} -> {:error, reason}
      invalid -> {:error, {:invalid_snapshot_terminal_state_result, invalid}}
    end
  rescue
    exception ->
      {:error, {:snapshot_terminal_state_raised, exception.__struct__, Exception.message(exception)}}
  catch
    kind, reason -> {:error, {:snapshot_terminal_state_caught, kind, reason}}
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

  defp build_already_in_progress?(reason) do
    contains_reason?(reason, :snapshot_object_namespace_in_progress) or
      contains_reason?(reason, :snapshot_object_publication_in_progress)
  end

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

  defp contains_reason?(%_{} = struct, target) do
    struct
    |> Map.from_struct()
    |> contains_reason?(target)
  end

  defp contains_reason?(map, target) when is_map(map) do
    map
    |> Map.to_list()
    |> Enum.any?(fn {key, value} -> contains_reason?(key, target) or contains_reason?(value, target) end)
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
