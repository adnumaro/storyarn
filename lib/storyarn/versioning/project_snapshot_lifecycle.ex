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
  alias Storyarn.Assets.StorageCompensation
  alias Storyarn.Billing
  alias Storyarn.Billing.StorageReservation
  alias Storyarn.Projects
  alias Storyarn.Projects.Project
  alias Storyarn.Repo
  alias Storyarn.Shared.TimeHelpers
  alias Storyarn.Versioning.ProjectSnapshot
  alias Storyarn.Versioning.ProjectSnapshotCapture
  alias Storyarn.Versioning.ProjectSnapshotPolicy
  alias Storyarn.Versioning.SnapshotCleanupIntent
  alias Storyarn.Versioning.SnapshotObjectPublicationClaim
  alias Storyarn.Versioning.SnapshotObjectStorage
  alias Storyarn.Workers.CleanupProjectSnapshotWorker
  alias Storyarn.Workspaces.Workspace

  @batch_size 100
  @retention_batch_size 50
  @deletable_user_states ~w(ready failed cancelled)
  @retention_states ~w(ready failed cancelled)
  @expirable_build_states ~w(pending building verifying)
  @terminal_job_states ~w(completed discarded cancelled)
  @hard_delete_reasons ~w(project_hard_delete workspace_hard_delete)a

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
          reservation_id: pos_integer(),
          reservation_generation: pos_integer(),
          reservation_expires_at: DateTime.t()
        }

  @doc "Authorizes and durably deletes one user-visible snapshot."
  @spec delete(Scope.t(), Project.t(), pos_integer()) ::
          {:ok, SnapshotCleanupIntent.t()} | {:error, term()}
  def delete(%Scope{user: %{id: user_id}} = scope, %Project{} = project, snapshot_id)
      when is_integer(user_id) and is_integer(snapshot_id) and snapshot_id > 0 do
    case Projects.authorize(scope, project.id, :manage_project) do
      {:ok, %Project{} = authorized_project, _membership} ->
        result =
          Billing.transact_with_workspace_lock(authorized_project.workspace_id, fn _workspace ->
            delete_user_snapshot_locked(authorized_project, snapshot_id, user_id)
          end)

        broadcast_deleted(result, authorized_project.id, snapshot_id)

      {:error, reason} when reason in [:not_found, :unauthorized] ->
        {:error, :unauthorized}

      {:error, reason} ->
        {:error, reason}
    end
  end

  def delete(_scope, _project, _snapshot_id), do: {:error, :invalid_snapshot_delete_request}

  @doc false
  @spec prepare_project_hard_delete(Project.t()) :: :ok | {:error, term()}
  def prepare_project_hard_delete(%Project{} = project) do
    prepare_project_hard_delete(project, :project_hard_delete)
  end

  @doc false
  @spec prepare_workspace_hard_delete(Workspace.t()) :: :ok | {:error, term()}
  def prepare_workspace_hard_delete(%Workspace{id: workspace_id}) when is_integer(workspace_id) do
    if Billing.workspace_lock_held?(workspace_id) do
      prepare_workspace_hard_delete_locked(workspace_id)
    else
      {:error, :snapshot_cleanup_workspace_lock_required}
    end
  end

  def prepare_workspace_hard_delete(_workspace), do: {:error, :invalid_workspace_cleanup_scope}

  defp prepare_workspace_hard_delete_locked(workspace_id) do
    with {:ok, project_ids} <- bounded_workspace_snapshot_project_ids(workspace_id) do
      Enum.reduce_while(project_ids, :ok, &prepare_workspace_project(workspace_id, &1, &2))
    end
  end

  defp prepare_workspace_project(workspace_id, project_id, :ok) do
    project = lock_workspace_project(workspace_id, project_id)

    case prepare_project_hard_delete(project, :workspace_hard_delete) do
      :ok -> {:cont, :ok}
      {:error, reason} -> {:halt, {:error, reason}}
    end
  end

  @doc "Lists one bounded, stable page of expired snapshot candidates."
  @spec list_retention_candidates(DateTime.t(), keyword()) :: [retention_candidate()]
  def list_retention_candidates(%DateTime{} = now, opts \\ []) do
    limit = opts |> Keyword.get(:limit, @retention_batch_size) |> min(@retention_batch_size) |> max(1)
    after_id = Keyword.get(opts, :after_id, 0)

    Repo.all(
      from(snapshot in ProjectSnapshot,
        join: project in Project,
        on: project.id == snapshot.project_id,
        join: workspace in Workspace,
        on: workspace.id == project.workspace_id,
        where:
          snapshot.id > ^after_id and snapshot.lifecycle_state in ^@retention_states and
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
  @spec delete_retention_candidate(retention_candidate(), DateTime.t()) ::
          {:ok, SnapshotCleanupIntent.t()} | {:error, term()}
  def delete_retention_candidate(%{} = candidate, %DateTime{} = now) do
    case Map.get(candidate, :workspace_id) do
      workspace_id when is_integer(workspace_id) ->
        Billing.transact_with_workspace_lock(workspace_id, fn _workspace ->
          delete_retention_candidate_locked(candidate, now)
        end)

      _invalid ->
        {:error, :retention_candidate_changed}
    end
  end

  def delete_retention_candidate(_candidate, _now), do: {:error, :retention_candidate_changed}

  @doc "Lists abandoned builds whose reservation expired and whose owning job cannot still write."
  @spec list_expired_build_candidates(DateTime.t(), keyword()) :: [expired_build_candidate()]
  def list_expired_build_candidates(%DateTime{} = now, opts \\ []) do
    limit = opts |> Keyword.get(:limit, @retention_batch_size) |> min(@retention_batch_size) |> max(1)
    after_id = Keyword.get(opts, :after_id, 0)

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
          snapshot.id > ^after_id and snapshot.lifecycle_state in ^@expirable_build_states and
            reservation.expires_at <= ^now and is_nil(project.deleted_at) and
            (is_nil(job.id) or job.state in ^@terminal_job_states),
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
          reservation_id: reservation.id,
          reservation_generation: reservation.generation,
          reservation_expires_at: reservation.expires_at
        }
      )
    )
  end

  @doc false
  @spec delete_expired_build_candidate(expired_build_candidate(), DateTime.t()) ::
          {:ok, SnapshotCleanupIntent.t()} | {:error, term()}
  def delete_expired_build_candidate(%{} = candidate, %DateTime{} = now) do
    case Map.get(candidate, :workspace_id) do
      workspace_id when is_integer(workspace_id) ->
        Billing.transact_with_workspace_lock(workspace_id, fn _workspace ->
          delete_expired_build_candidate_locked(candidate, now)
        end)

      _invalid ->
        {:error, :expired_build_candidate_changed}
    end
  end

  def delete_expired_build_candidate(_candidate, _now), do: {:error, :expired_build_candidate_changed}

  @doc false
  @spec process_cleanup_intent(pos_integer(), keyword()) ::
          {:ok, :completed | :more | :already_completed | :terminal}
          | {:error, :storage_provider_failure | term()}
  def process_cleanup_intent(intent_id, opts \\ [])

  def process_cleanup_intent(intent_id, opts) when is_integer(intent_id) and intent_id > 0 and is_list(opts) do
    final_attempt? = Keyword.get(opts, :final_attempt?, false) == true
    delete_fun = Keyword.get(opts, :delete_fun, &StorageCompensation.delete_storage_keys/1)

    with {:ok, claimed} <- claim_cleanup_intent(intent_id) do
      process_claimed_cleanup(claimed, delete_fun, final_attempt?)
    end
  end

  def process_cleanup_intent(_intent_id, _opts), do: {:error, :invalid_snapshot_cleanup_intent}

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
            retry_count: type(coalesce(sum(intent.retry_count), 0), :integer),
            terminal_failures: filter(count(intent.id), intent.status == "terminal"),
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
         :ok <- ensure_no_active_snapshot_operations(snapshot.id) do
      create_cleanup_and_delete(snapshot, project.workspace_id, :user_delete, {:user, user_id})
    else
      nil -> existing_intent_or_error(project.id, snapshot_id)
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
      Enum.reduce_while(snapshots, :ok, &prepare_hard_delete_snapshot(&1, &2, workspace_id, reason))
    end
  end

  defp prepare_hard_delete_snapshot(snapshot, :ok, workspace_id, reason) do
    with :ok <- ensure_hard_delete_operations_supported(snapshot),
         {:ok, _intent} <- create_cleanup_and_delete(snapshot, workspace_id, reason, :system) do
      {:cont, :ok}
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
         :ok <- ensure_no_active_snapshot_operations(snapshot.id) do
      create_cleanup_and_delete(snapshot, project.workspace_id, :retention, :system)
    else
      nil -> {:error, :retention_candidate_changed}
      {:error, reason} -> {:error, reason}
    end
  end

  defp delete_expired_build_candidate_locked(candidate, now) do
    project_id = Map.get(candidate, :project_id)
    snapshot_id = Map.get(candidate, :snapshot_id)

    with %Project{} = project <- lock_active_project(project_id, Map.get(candidate, :workspace_id)),
         %ProjectSnapshot{} = snapshot <- lock_snapshot(project_id, snapshot_id),
         %StorageReservation{} = reservation <- lock_build_reservation(snapshot_id, candidate),
         :ok <- revalidate_expired_build_candidate(snapshot, project, reservation, candidate, now),
         :ok <- ensure_hard_delete_operations_supported(snapshot) do
      create_cleanup_and_delete(snapshot, project.workspace_id, :expired_build, :system)
    else
      nil -> {:error, :expired_build_candidate_changed}
      {:error, reason} -> {:error, reason}
    end
  end

  defp revalidate_expired_build_candidate(snapshot, project, reservation, candidate, now) do
    job = lock_build_job(snapshot.build_job_id)

    facts = {
      snapshot.id,
      snapshot.project_id,
      project.workspace_id,
      snapshot.lifecycle_generation,
      snapshot.lifecycle_state,
      snapshot.build_job_id,
      job && job.state,
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
      Map.get(candidate, :reservation_id),
      Map.get(candidate, :reservation_generation),
      Map.get(candidate, :reservation_expires_at)
    }

    with true <- facts == expected,
         true <- snapshot.lifecycle_state in @expirable_build_states,
         true <- reservation.status == "active" and reservation.kind == "snapshot_build",
         true <- DateTime.compare(reservation.expires_at, now) in [:lt, :eq],
         true <- is_nil(job) or job.state in @terminal_job_states do
      :ok
    else
      _invalid -> {:error, :expired_build_candidate_changed}
    end
  end

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

  defp create_cleanup_and_delete(snapshot, workspace_id, reason, authority) do
    with :ok <- ensure_supported_mode(snapshot.mode),
         %ProjectSnapshotCapture{} = capture <- lock_capture(snapshot.id),
         {:ok, scope} <-
           SnapshotObjectStorage.cleanup_scope_from_capture(
             snapshot.project_id,
             snapshot.object_prefix,
             capture.manifest_json
           ),
         now = TimeHelpers.now(),
         {:ok, deleting} <- snapshot |> ProjectSnapshot.deletion_changeset(now) |> Repo.update(),
         :ok <- release_no_write_build_reservations(deleting),
         owner_token = Ecto.UUID.generate(),
         {:ok, cleanup_request} <-
           StorageCompensation.persist_snapshot_lifecycle_cleanup(scope.storage_keys, owner_token),
         {:ok, intent} <-
           insert_cleanup_intent(
             deleting,
             workspace_id,
             reason,
             authority,
             scope,
             cleanup_request.id,
             now
           ),
         :ok <- settle_active_build_reservations(deleting, cleanup_request.id, scope),
         :ok <- delete_publication_claim(deleting),
         {:ok, _deleted_snapshot} <- Repo.delete(deleting),
         {:ok, _job} <- enqueue_cleanup(intent.id) do
      {:ok, intent}
    else
      nil -> {:error, :snapshot_capture_missing}
      {:error, reason} -> {:error, reason}
    end
  end

  defp insert_cleanup_intent(snapshot, workspace_id, reason, authority, scope, cleanup_request_id, now) do
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
    if Repo.exists?(
         from(reservation in StorageReservation,
           where: reservation.project_snapshot_id_snapshot == ^snapshot_id and reservation.status == "active"
         )
       ),
       do: {:error, :snapshot_active_operation_blocks_deletion},
       else: :ok
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

    job = lock_build_job(snapshot.build_job_id)

    cond do
      active_reservations == [] ->
        :ok

      Enum.any?(active_reservations, &(&1.kind != "snapshot_build")) ->
        {:error, :snapshot_active_operation_blocks_deletion}

      is_nil(job) or job.state in @terminal_job_states ->
        :ok

      true ->
        {:error, :snapshot_active_operation_blocks_deletion}
    end
  end

  defp ensure_supported_mode("full"), do: :ok
  defp ensure_supported_mode("linked"), do: {:error, :linked_snapshot_lifecycle_not_enabled}
  defp ensure_supported_mode(_mode), do: {:error, :unsupported_snapshot_mode}

  defp claim_cleanup_intent(intent_id) do
    Repo.transact(fn ->
      case lock_cleanup_intent(intent_id) do
        nil -> {:error, :snapshot_cleanup_intent_not_found}
        %SnapshotCleanupIntent{status: "completed"} -> {:ok, :already_completed}
        %SnapshotCleanupIntent{status: "terminal"} -> {:ok, :terminal}
        %SnapshotCleanupIntent{} = intent -> intent |> SnapshotCleanupIntent.processing_changeset() |> Repo.update()
      end
    end)
  end

  defp process_claimed_cleanup(:already_completed, _delete_fun, _final_attempt?), do: {:ok, :already_completed}
  defp process_claimed_cleanup(:terminal, _delete_fun, _final_attempt?), do: {:ok, :terminal}

  defp process_claimed_cleanup(%SnapshotCleanupIntent{} = intent, delete_fun, final_attempt?) do
    batch = Enum.take(intent.remaining_storage_keys, @batch_size)

    case safe_delete(delete_fun, batch) do
      :ok -> finish_successful_batch(intent, batch)
      {:error, failed_keys} -> finish_failed_batch(intent, batch, failed_keys, final_attempt?)
    end
  end

  defp finish_successful_batch(intent, batch) do
    result = Repo.transact(fn -> update_successful_batch(intent.id, batch) end)
    handle_successful_batch_result(result, length(batch))
  end

  defp update_successful_batch(intent_id, batch) do
    current = lock_cleanup_intent(intent_id)

    cond do
      is_nil(current) ->
        {:error, :snapshot_cleanup_intent_not_found}

      current.status == "completed" ->
        {:ok, :already_completed}

      current.status == "terminal" ->
        {:ok, :terminal}

      current.remaining_storage_keys -- batch == [] ->
        current |> SnapshotCleanupIntent.completed_changeset() |> Repo.update()

      true ->
        remaining = current.remaining_storage_keys -- batch
        current |> SnapshotCleanupIntent.progress_changeset(remaining) |> Repo.update()
    end
  end

  defp handle_successful_batch_result({:ok, %SnapshotCleanupIntent{status: "completed"} = intent}, deleted_count) do
    emit_cleanup_stop(intent, :completed, deleted_count)
    {:ok, :completed}
  end

  defp handle_successful_batch_result({:ok, %SnapshotCleanupIntent{} = intent}, deleted_count) do
    emit_cleanup_stop(intent, :more, deleted_count)
    {:ok, :more}
  end

  defp handle_successful_batch_result({:ok, result}, _deleted_count) when result in [:already_completed, :terminal],
    do: {:ok, result}

  defp handle_successful_batch_result({:error, reason}, _deleted_count), do: {:error, reason}

  defp finish_failed_batch(intent, batch, failed_keys, final_attempt?) do
    failed_set = MapSet.new(failed_keys)
    successful = Enum.reject(batch, &MapSet.member?(failed_set, &1))

    result = Repo.transact(fn -> update_failed_batch(intent.id, successful, final_attempt?) end)
    handle_failed_batch_result(result, final_attempt?, length(successful))
  end

  defp update_failed_batch(intent_id, successful, final_attempt?) do
    current = lock_cleanup_intent(intent_id)

    cond do
      is_nil(current) -> {:error, :snapshot_cleanup_intent_not_found}
      current.status == "completed" -> {:ok, :already_completed}
      current.status == "terminal" -> {:ok, :terminal}
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
       when result in [:already_completed, :terminal], do: {:ok, result}

  defp handle_failed_batch_result({:ok, intent}, final_attempt?, deleted_count) do
    emit_cleanup_stop(intent, if(final_attempt?, do: :terminal, else: :retrying), deleted_count)

    if final_attempt?,
      do: {:ok, :terminal},
      else: {:error, :storage_provider_failure}
  end

  defp handle_failed_batch_result({:error, reason}, _final_attempt?, _deleted_count), do: {:error, reason}

  defp safe_delete(delete_fun, storage_keys) do
    case delete_fun.(storage_keys) do
      :ok -> :ok
      {:error, failed_keys} when is_list(failed_keys) -> {:error, normalize_failed_keys(failed_keys, storage_keys)}
      _invalid -> {:error, storage_keys}
    end
  rescue
    _exception -> {:error, storage_keys}
  catch
    _kind, _reason -> {:error, storage_keys}
  end

  defp normalize_failed_keys(failed_keys, storage_keys) do
    failed_keys = Enum.uniq(failed_keys)
    allowed = MapSet.new(storage_keys)

    if failed_keys != [] and Enum.all?(failed_keys, &MapSet.member?(allowed, &1)),
      do: failed_keys,
      else: storage_keys
  end

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

  defp lock_capture(snapshot_id) do
    Repo.one(
      from(capture in ProjectSnapshotCapture,
        where: capture.project_snapshot_id == ^snapshot_id,
        lock: "FOR SHARE"
      )
    )
  end

  defp lock_cleanup_intent(intent_id) do
    Repo.one(
      from(intent in SnapshotCleanupIntent,
        where: intent.id == ^intent_id,
        lock: "FOR UPDATE"
      )
    )
  end

  defp broadcast_deleted({:ok, %SnapshotCleanupIntent{} = intent} = result, project_id, snapshot_id) do
    Phoenix.PubSub.broadcast(Storyarn.PubSub, "project_snapshots:#{project_id}", {:project_snapshot_updated, snapshot_id})
    emit_cleanup_intent(intent)
    result
  end

  defp broadcast_deleted(result, _project_id, _snapshot_id), do: result

  defp emit_cleanup_intent(intent) do
    :telemetry.execute(
      [:storyarn, :snapshot, :cleanup, :intent],
      %{count: 1, object_count: intent.object_count, estimated_cleanup_bytes: intent.estimated_cleanup_bytes},
      %{reason: intent.reason, mode: intent.mode, authority_kind: intent.authority_kind}
    )
  end

  defp emit_cleanup_stop(intent, status, deleted_count) do
    backlog = cleanup_backlog()

    :telemetry.execute(
      [:storyarn, :snapshot, :cleanup, :stop],
      %{
        deleted_count: deleted_count,
        retry_count: intent.retry_count,
        backlog_count: backlog.backlog_count,
        backlog_bytes: backlog.backlog_bytes,
        oldest_age_seconds: backlog.oldest_age_seconds,
        terminal_failures: backlog.terminal_failures
      },
      %{status: status, reason: intent.reason, error_code: intent.last_error_code || "none"}
    )
  end
end
