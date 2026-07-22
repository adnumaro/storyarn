defmodule Storyarn.Projects.ProjectCrud do
  @moduledoc false

  import Ecto.Query, warn: false

  alias Storyarn.Accounts.Scope
  alias Storyarn.Analytics
  alias Storyarn.Billing
  alias Storyarn.Projects.Memberships
  alias Storyarn.Projects.Project
  alias Storyarn.Projects.ProjectInvitation
  alias Storyarn.Projects.ProjectMembership
  alias Storyarn.Repo
  alias Storyarn.Shared.NameNormalizer
  alias Storyarn.Shared.TimeHelpers
  alias Storyarn.Versioning.ProjectSnapshot
  alias Storyarn.Workspaces
  alias Storyarn.Workspaces.Workspace

  @restore_project_worker "Storyarn.Workers.RestoreProjectWorker"
  @active_restore_job_states ~w(available scheduled executing retryable)

  @doc """
  Lists all projects the user has access to (owned or as a member).
  """
  def list_projects(%Scope{user: user}) do
    Project
    |> where([p], is_nil(p.deleted_at))
    |> join(:inner, [p], m in ProjectMembership, on: m.project_id == p.id and m.user_id == ^user.id)
    |> select([p, m], %{project: p, role: m.role})
    |> order_by([p], desc: fragment("COALESCE(?, ?)", p.last_activity_at, p.updated_at))
    |> Repo.all()
  end

  @doc """
  Lists all projects in a workspace that the user has access to.
  """
  def list_projects_for_workspace(workspace_id, %Scope{user: user}) do
    Project
    |> where([p], p.workspace_id == ^workspace_id and is_nil(p.deleted_at))
    |> join(:left, [p], pm in ProjectMembership, on: pm.project_id == p.id and pm.user_id == ^user.id)
    |> join(:left, [p, pm], wm in Storyarn.Workspaces.WorkspaceMembership,
      on: wm.workspace_id == p.workspace_id and wm.user_id == ^user.id
    )
    |> where([p, pm, wm], not is_nil(pm.id) or not is_nil(wm.id))
    |> select([p, pm, wm], %{
      project: p,
      project_role: pm.role,
      workspace_role: wm.role
    })
    |> order_by([p], desc: fragment("COALESCE(?, ?)", p.last_activity_at, p.updated_at))
    |> Repo.all()
  end

  @doc """
  Gets a single project by ID with authorization check.
  """
  def get_project(%Scope{user: user}, id) do
    project = Repo.one(from(p in Project, where: p.id == ^id and is_nil(p.deleted_at)))

    with %Project{} <- project,
         %ProjectMembership{} = membership <-
           Memberships.get_effective_membership(project.id, user.id, project.workspace_id) do
      {:ok, project, membership}
    else
      nil -> {:error, :not_found}
    end
  end

  @doc """
  Gets a project without authorization check.
  """
  def get_project!(id), do: Repo.get!(Project, id)

  @doc """
  Gets a project by workspace slug and project slug with authorization check.
  """
  def get_project_by_slugs(%Scope{user: user}, workspace_slug, project_slug) do
    query =
      from p in Project,
        join: w in Workspace,
        on: w.id == p.workspace_id,
        where: w.slug == ^workspace_slug and p.slug == ^project_slug and is_nil(p.deleted_at),
        preload: [:workspace]

    with %Project{} = project <- Repo.one(query),
         %ProjectMembership{} = membership <-
           Memberships.get_effective_membership(project.id, user.id, project.workspace_id) do
      {:ok, project, membership}
    else
      nil -> {:error, :not_found}
    end
  end

  @doc """
  Creates a project and sets up the owner membership.
  """
  def create_project(%Scope{user: user}, attrs) do
    with {:ok, workspace, membership} <- authorized_workspace_for_create(attrs, user),
         true <- Workspaces.can?(membership.role, :create_project) do
      do_create_project(user, workspace.id, attrs)
    else
      false -> {:error, :unauthorized}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc false
  @spec lock_and_check_workspace_capacity(integer()) ::
          :ok | {:error, :not_found} | {:error, :limit_reached, map()}
  def lock_and_check_workspace_capacity(workspace_id) do
    workspace =
      Workspace
      |> where([workspace], workspace.id == ^workspace_id)
      |> lock("FOR UPDATE")
      |> Repo.one()

    case workspace do
      %Workspace{} -> Billing.can_create_project?(workspace)
      nil -> {:error, :not_found}
    end
  end

  defp authorized_workspace_for_create(attrs, user) do
    case attrs[:workspace_id] || attrs["workspace_id"] do
      nil -> {:error, :not_found}
      workspace_id -> Workspaces.get_workspace(Scope.for_user(user), workspace_id)
    end
  end

  defp do_create_project(user, workspace_id, attrs) do
    result =
      Repo.transact(fn ->
        with :ok <- normalize_capacity_result(lock_and_check_workspace_capacity(workspace_id)),
             {:ok, project} <- insert_project(user, attrs),
             {:ok, _membership} <- create_owner_membership(project, user) do
          {:ok, project}
        end
      end)

    case result do
      {:ok, project} ->
        Analytics.track(user, "project created", %{
          project_id: project.id,
          workspace_id: project.workspace_id,
          project_type: project.project_type,
          project_subtype: project.project_subtype,
          project_type_other: project.project_type_other
        })

        {:ok, project}

      {:error, {:limit_reached, details}} ->
        {:error, :limit_reached, details}

      error ->
        error
    end
  end

  defp normalize_capacity_result(:ok), do: :ok

  defp normalize_capacity_result({:error, :limit_reached, details}) do
    {:error, {:limit_reached, details}}
  end

  defp normalize_capacity_result({:error, reason}), do: {:error, reason}

  @doc """
  Returns a changeset for tracking project changes.
  """
  def change_project(%Project{} = project, attrs \\ %{}) do
    Project.update_changeset(project, attrs)
  end

  @doc """
  Returns a changeset for validating new project form input.
  """
  def change_new_project(%Project{} = project, attrs \\ %{}) do
    Project.create_form_changeset(project, attrs)
  end

  @doc """
  Updates a project.
  """
  def update_project(%Project{} = project, attrs) do
    project
    |> Project.update_changeset(attrs)
    |> Ecto.Changeset.put_change(:last_activity_at, TimeHelpers.now())
    |> Repo.update()
  end

  @doc """
  Marks a project as having content activity without changing project metadata.
  """
  def touch_project(project_id, at \\ TimeHelpers.now())

  def touch_project(project_id, nil), do: touch_project(project_id, TimeHelpers.now())

  def touch_project(project_id, at) when is_integer(project_id) do
    Repo.update_all(from(p in Project, where: p.id == ^project_id), set: [last_activity_at: at])

    :ok
  end

  @doc """
  Soft-deletes a project by setting deleted_at and deleted_by_id.
  """
  def delete_project(%Project{} = project, user_id) do
    Repo.transact(fn ->
      result =
        project
        |> Project.soft_delete_changeset(%{
          deleted_at: TimeHelpers.now(),
          deleted_by_id: user_id
        })
        |> Repo.update()

      case result do
        {:ok, deleted_project} ->
          ProjectInvitation
          |> where([invitation], invitation.project_id == ^project.id)
          |> where([invitation], is_nil(invitation.accepted_at))
          |> Repo.delete_all()

          {:ok, deleted_project}

        error ->
          error
      end
    end)
  end

  @doc """
  Permanently deletes a project (for retention cleanup).
  """
  def permanently_delete_project(%Project{} = project) do
    Repo.delete(project)
  end

  @doc """
  Lists soft-deleted projects in a workspace.
  Preloads deleted_by user and includes snapshot count.
  """
  def list_deleted_projects(workspace_id) do
    snapshot_count_query =
      from(s in ProjectSnapshot,
        where: s.project_id == parent_as(:project).id,
        select: count(s.id)
      )

    Repo.all(
      from(p in Project,
        as: :project,
        where: p.workspace_id == ^workspace_id and not is_nil(p.deleted_at),
        order_by: [desc: p.deleted_at],
        preload: [:deleted_by],
        select_merge: %{snapshot_count: subquery(snapshot_count_query)}
      )
    )
  end

  @doc """
  Gets a single deleted project with its snapshots preloaded.
  """
  def get_deleted_project(workspace_id, project_id) do
    Repo.one(
      from(p in Project,
        where: p.id == ^project_id and p.workspace_id == ^workspace_id and not is_nil(p.deleted_at),
        preload: [:deleted_by]
      )
    )
  end

  @doc """
  Lists all projects with auto snapshots enabled (for daily cron job).
  """
  def list_projects_with_auto_snapshots(opts \\ []) do
    after_id = Keyword.get(opts, :after_id)
    limit = Keyword.get(opts, :limit)

    Project
    |> where([p], p.auto_snapshots_enabled == true and is_nil(p.deleted_at))
    |> order_by([p], asc: p.id)
    |> maybe_after_project_id(after_id)
    |> maybe_limit(limit)
    |> Repo.all()
  end

  defp maybe_after_project_id(query, nil), do: query
  defp maybe_after_project_id(query, after_id), do: where(query, [p], p.id > ^after_id)

  defp maybe_limit(query, nil), do: query
  defp maybe_limit(query, limit), do: limit(query, ^limit)

  @doc """
  Checks if auto-versioning is enabled for a given entity type in a project.

  Returns `true` when the project has the corresponding toggle enabled.
  Uses a lightweight single-column query to avoid loading the full project.
  """
  @spec auto_versioning_enabled?(integer(), :flow | :scene | :sheet) :: boolean()
  def auto_versioning_enabled?(project_id, entity_type) do
    field = auto_version_field(entity_type)

    from(p in Project,
      where: p.id == ^project_id,
      select: field(p, ^field)
    )
    |> Repo.one()
    |> Kernel.||(false)
  end

  defp auto_version_field(:flow), do: :auto_version_flows
  defp auto_version_field(:scene), do: :auto_version_scenes
  defp auto_version_field(:sheet), do: :auto_version_sheets

  # =============================================================================
  # Restoration Lock
  # =============================================================================

  @doc """
  Atomically acquires a restoration lock on a project.

  The lock is bound to the actor, target snapshot, and a random token. The
  token must accompany the queued job and is required to release the lock.

  Returns `{:ok, project}` if the lock was acquired,
  `{:error, :already_locked}` if another restoration is in progress, or
  `{:error, :snapshot_not_found}` if the snapshot does not belong to the
  project.
  """
  def acquire_restoration_lock(project_id, user_id, snapshot_id) do
    now = TimeHelpers.now()
    token = Ecto.UUID.generate()

    fn ->
      owned_snapshot =
        ProjectSnapshot
        |> where([snapshot], snapshot.id == ^snapshot_id and snapshot.project_id == ^project_id)
        |> lock("FOR SHARE")
        |> Repo.one()

      if owned_snapshot,
        do:
          claim_restoration_lock!(
            project_id,
            user_id,
            snapshot_id,
            token,
            now
          ),
        else: Repo.rollback(:snapshot_not_found)
    end
    |> Repo.transaction()
    |> case do
      {:ok, project} -> {:ok, project}
      {:error, reason} -> {:error, reason}
    end
  end

  defp claim_restoration_lock!(project_id, user_id, snapshot_id, token, now) do
    {count, _} =
      Repo.update_all(
        from(p in Project,
          where: p.id == ^project_id and p.restoration_in_progress == false
        ),
        set: [
          restoration_in_progress: true,
          restoration_started_by_id: user_id,
          restoration_started_at: now,
          restoration_token: token,
          restoration_claimed_by_job_id: nil,
          restoration_snapshot_id: snapshot_id
        ]
      )

    case count do
      1 -> Repo.get!(Project, project_id)
      _count -> Repo.rollback(:already_locked)
    end
  end

  @doc """
  Releases an unclaimed restoration lock only when the token matches.

  This is the enqueue-compensation path. Once a worker claims the lock, it must
  use `release_restoration_lock/3` with its Oban job id.
  """
  def release_restoration_lock(project_id, token) do
    case Ecto.UUID.cast(token) do
      {:ok, cast_token} ->
        project_id
        |> unclaimed_restoration_lock_query(cast_token)
        |> release_restoration_lock_query(project_id)

      :error ->
        {:error, :lock_mismatch}
    end
  end

  @doc """
  Releases a claimed restoration lock only when both token and job id match.
  """
  def release_restoration_lock(project_id, token, job_id) when is_integer(job_id) and job_id > 0 do
    case Ecto.UUID.cast(token) do
      {:ok, cast_token} ->
        project_id
        |> claimed_restoration_lock_query(cast_token, job_id)
        |> release_restoration_lock_query(project_id)

      :error ->
        {:error, :lock_mismatch}
    end
  end

  def release_restoration_lock(_project_id, _token, _job_id), do: {:error, :invalid_job_id}

  defp unclaimed_restoration_lock_query(project_id, token) do
    from(project in Project,
      where:
        project.id == ^project_id and
          project.restoration_in_progress == true and
          project.restoration_token == ^token and
          is_nil(project.restoration_claimed_by_job_id),
      select: project
    )
  end

  defp claimed_restoration_lock_query(project_id, token, job_id) do
    from(project in Project,
      where:
        project.id == ^project_id and
          project.restoration_in_progress == true and
          project.restoration_token == ^token and
          project.restoration_claimed_by_job_id == ^job_id,
      select: project
    )
  end

  defp release_restoration_lock_query(query, project_id) do
    case Repo.update_all(
           query,
           set: [
             restoration_in_progress: false,
             restoration_started_by_id: nil,
             restoration_started_at: nil,
             restoration_token: nil,
             restoration_claimed_by_job_id: nil,
             restoration_snapshot_id: nil
           ]
         ) do
      {1, [%Project{} = project]} ->
        {:ok, project}

      {0, _rows} ->
        if Repo.exists?(from(project in Project, where: project.id == ^project_id)),
          do: {:error, :lock_mismatch},
          else: {:error, :not_found}
    end
  end

  @doc """
  Verifies that a queued restore still owns the project's active lock.
  """
  def verify_restoration_lock(project_id, user_id, snapshot_id, token) do
    case Repo.get(Project, project_id) do
      nil ->
        {:error, :not_found}

      %Project{
        restoration_in_progress: true,
        restoration_started_by_id: ^user_id,
        restoration_snapshot_id: ^snapshot_id,
        restoration_token: ^token
      } = project ->
        {:ok, project}

      %Project{restoration_in_progress: false} ->
        {:error, :not_locked}

      %Project{} ->
        {:error, :lock_mismatch}
    end
  end

  @doc """
  Atomically fences an active restoration lock to a single Oban job.

  A lock is unclaimed between enqueue and worker start. Only the first worker
  whose actor, snapshot, and token all match may set the claiming job id.
  Subsequent deliveries — including duplicates carrying the same token — fail
  closed before authorization, safety snapshots, or restore mutations.
  """
  def claim_restoration_lock(project_id, user_id, snapshot_id, token, job_id) when is_integer(job_id) and job_id > 0 do
    case Ecto.UUID.cast(token) do
      {:ok, cast_token} ->
        do_claim_restoration_lock(
          project_id,
          user_id,
          snapshot_id,
          cast_token,
          job_id
        )

      :error ->
        {:error, :lock_mismatch}
    end
  end

  def claim_restoration_lock(_project_id, _user_id, _snapshot_id, _token, _job_id), do: {:error, :invalid_job_id}

  defp do_claim_restoration_lock(project_id, user_id, snapshot_id, token, job_id) do
    {count, claimed_projects} =
      Repo.update_all(
        from(project in Project,
          where:
            project.id == ^project_id and
              project.restoration_in_progress == true and
              project.restoration_started_by_id == ^user_id and
              project.restoration_snapshot_id == ^snapshot_id and
              project.restoration_token == ^token and
              is_nil(project.restoration_claimed_by_job_id),
          select: project
        ),
        set: [restoration_claimed_by_job_id: job_id]
      )

    case {count, claimed_projects} do
      {1, [%Project{} = project]} ->
        {:ok, project}

      {0, _rows} ->
        classify_restoration_claim_failure(
          Repo.get(Project, project_id),
          user_id,
          snapshot_id,
          token
        )
    end
  end

  defp classify_restoration_claim_failure(nil, _user_id, _snapshot_id, _token), do: {:error, :not_found}

  defp classify_restoration_claim_failure(%Project{restoration_in_progress: false}, _user_id, _snapshot_id, _token),
    do: {:error, :not_locked}

  defp classify_restoration_claim_failure(
         %Project{
           restoration_in_progress: true,
           restoration_started_by_id: user_id,
           restoration_snapshot_id: snapshot_id,
           restoration_token: token,
           restoration_claimed_by_job_id: claimed_by_job_id
         },
         user_id,
         snapshot_id,
         token
       )
       when not is_nil(claimed_by_job_id), do: {:error, :already_claimed}

  defp classify_restoration_claim_failure(%Project{}, _user_id, _snapshot_id, _token), do: {:error, :lock_mismatch}

  @doc """
  Checks if a restoration is in progress for a project.

  Returns `{true, %{user_id: id, started_at: dt}}` or `false`.
  """
  def restoration_in_progress?(project_id) do
    from(p in Project,
      where: p.id == ^project_id,
      select: {p.restoration_in_progress, p.restoration_started_by_id, p.restoration_started_at}
    )
    |> Repo.one()
    |> case do
      {true, user_id, started_at} ->
        {true, %{user_id: user_id, started_at: started_at}}

      _ ->
        false
    end
  end

  @doc """
  Clears a stale restoration lock if it's older than the given timeout and no
  queued or executing Oban job still owns its token.

  The project row is locked while checking the job state. This also waits for
  an in-flight restore transaction, which holds the same row lock for the full
  mutation.
  """
  def clear_stale_restoration_lock(project_id, timeout_minutes \\ 15) do
    cutoff = DateTime.add(TimeHelpers.now(), -timeout_minutes * 60, :second)

    fn ->
      project =
        Project
        |> where([project], project.id == ^project_id)
        |> lock("FOR UPDATE")
        |> Repo.one()

      cond do
        not stale_restoration_lock?(project, cutoff) ->
          Repo.rollback(:not_stale)

        active_restore_job?(project.restoration_token) ->
          Repo.rollback(:restore_active)

        true ->
          {1, _} =
            Repo.update_all(
              from(candidate in Project,
                where:
                  candidate.id == ^project.id and
                    candidate.restoration_token ==
                      ^project.restoration_token
              ),
              set: [
                restoration_in_progress: false,
                restoration_started_by_id: nil,
                restoration_started_at: nil,
                restoration_token: nil,
                restoration_claimed_by_job_id: nil,
                restoration_snapshot_id: nil
              ]
            )

          :cleared
      end
    end
    |> Repo.transaction()
    |> case do
      {:ok, :cleared} -> {:ok, :cleared}
      {:error, reason} -> {:error, reason}
    end
  end

  defp stale_restoration_lock?(
         %Project{restoration_in_progress: true, restoration_started_at: %DateTime{} = started_at},
         cutoff
       ) do
    DateTime.before?(started_at, cutoff)
  end

  defp stale_restoration_lock?(_project, _cutoff), do: false

  defp active_restore_job?(token) do
    Repo.exists?(
      from(job in Oban.Job,
        where:
          job.worker == ^@restore_project_worker and
            job.state in ^@active_restore_job_states and
            fragment("?->>'lock_token' = ?", job.args, ^token)
      )
    )
  end

  # Private helpers

  defp insert_project(user, attrs) do
    workspace_id = attrs[:workspace_id] || attrs["workspace_id"]
    name = attrs[:name] || attrs["name"] || "untitled"
    slug = NameNormalizer.generate_unique_slug(Project, [workspace_id: workspace_id], name)

    # Use same key type as input attrs (atom if attrs has atom keys, string otherwise)
    slug_key =
      if Map.has_key?(attrs, :name) or Map.has_key?(attrs, :workspace_id), do: :slug, else: "slug"

    %Project{owner_id: user.id}
    |> Project.create_changeset(Map.put(attrs, slug_key, slug))
    |> Repo.insert()
  end

  defp create_owner_membership(project, user) do
    %ProjectMembership{}
    |> ProjectMembership.changeset(%{project_id: project.id, user_id: user.id, role: "owner"})
    |> Repo.insert()
  end
end
