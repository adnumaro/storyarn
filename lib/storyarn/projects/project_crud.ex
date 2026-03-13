defmodule Storyarn.Projects.ProjectCrud do
  @moduledoc false

  import Ecto.Query, warn: false

  alias Storyarn.Accounts.Scope
  alias Storyarn.Billing
  alias Storyarn.Projects.{Memberships, Project, ProjectMembership}
  alias Storyarn.Repo
  alias Storyarn.Shared.{NameNormalizer, TimeHelpers}
  alias Storyarn.Workspaces.Workspace

  @doc """
  Lists all projects the user has access to (owned or as a member).
  """
  def list_projects(%Scope{user: user}) do
    Project
    |> where([p], is_nil(p.deleted_at))
    |> join(:inner, [p], m in ProjectMembership,
      on: m.project_id == p.id and m.user_id == ^user.id
    )
    |> select([p, m], %{project: p, role: m.role})
    |> order_by([p], desc: p.updated_at)
    |> Repo.all()
  end

  @doc """
  Lists all projects in a workspace that the user has access to.
  """
  def list_projects_for_workspace(workspace_id, %Scope{user: user}) do
    Project
    |> where([p], p.workspace_id == ^workspace_id and is_nil(p.deleted_at))
    |> join(:left, [p], pm in ProjectMembership,
      on: pm.project_id == p.id and pm.user_id == ^user.id
    )
    |> join(:left, [p, pm], wm in Storyarn.Workspaces.WorkspaceMembership,
      on: wm.workspace_id == p.workspace_id and wm.user_id == ^user.id
    )
    |> where([p, pm, wm], not is_nil(pm.id) or not is_nil(wm.id))
    |> select([p, pm, wm], %{
      project: p,
      project_role: pm.role,
      workspace_role: wm.role
    })
    |> order_by([p], desc: p.updated_at)
    |> Repo.all()
  end

  @doc """
  Gets a single project by ID with authorization check.
  """
  def get_project(%Scope{user: user}, id) do
    project =
      from(p in Project, where: p.id == ^id and is_nil(p.deleted_at))
      |> Repo.one()

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
    workspace_id = attrs[:workspace_id] || attrs["workspace_id"]
    workspace = Repo.get!(Workspace, workspace_id)

    with :ok <- Billing.can_create_project?(workspace) do
      do_create_project(user, attrs)
    end
  end

  defp do_create_project(user, attrs) do
    Repo.transact(fn ->
      with {:ok, project} <- insert_project(user, attrs),
           {:ok, _membership} <- create_owner_membership(project, user) do
        {:ok, project}
      end
    end)
  end

  @doc """
  Returns a changeset for tracking project changes.
  """
  def change_project(%Project{} = project, attrs \\ %{}) do
    Project.update_changeset(project, attrs)
  end

  @doc """
  Updates a project.
  """
  def update_project(%Project{} = project, attrs) do
    project
    |> Project.update_changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Soft-deletes a project by setting deleted_at and deleted_by_id.
  """
  def delete_project(%Project{} = project, user_id) do
    project
    |> Project.soft_delete_changeset(%{deleted_at: TimeHelpers.now(), deleted_by_id: user_id})
    |> Repo.update()
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
      from(s in Storyarn.Versioning.ProjectSnapshot,
        where: s.project_id == parent_as(:project).id,
        select: count(s.id)
      )

    from(p in Project,
      as: :project,
      where: p.workspace_id == ^workspace_id and not is_nil(p.deleted_at),
      order_by: [desc: p.deleted_at],
      preload: [:deleted_by],
      select_merge: %{snapshot_count: subquery(snapshot_count_query)}
    )
    |> Repo.all()
  end

  @doc """
  Gets a single deleted project with its snapshots preloaded.
  """
  def get_deleted_project(workspace_id, project_id) do
    from(p in Project,
      where: p.id == ^project_id and p.workspace_id == ^workspace_id and not is_nil(p.deleted_at),
      preload: [:deleted_by]
    )
    |> Repo.one()
  end

  @doc """
  Lists all projects with auto snapshots enabled (for daily cron job).
  """
  def list_projects_with_auto_snapshots do
    from(p in Project, where: p.auto_snapshots_enabled == true and is_nil(p.deleted_at))
    |> Repo.all()
  end

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

  Returns `{:ok, project}` if the lock was acquired,
  `{:error, :already_locked}` if another restoration is in progress.
  """
  def acquire_restoration_lock(project_id, user_id) do
    now = Storyarn.Shared.TimeHelpers.now()

    {count, _} =
      from(p in Project,
        where: p.id == ^project_id and p.restoration_in_progress == false
      )
      |> Repo.update_all(
        set: [
          restoration_in_progress: true,
          restoration_started_by_id: user_id,
          restoration_started_at: now
        ]
      )

    if count == 1 do
      {:ok, Repo.get!(Project, project_id)}
    else
      {:error, :already_locked}
    end
  end

  @doc """
  Releases the restoration lock on a project.
  """
  def release_restoration_lock(project_id) do
    {_count, _} =
      from(p in Project, where: p.id == ^project_id)
      |> Repo.update_all(
        set: [
          restoration_in_progress: false,
          restoration_started_by_id: nil,
          restoration_started_at: nil
        ]
      )

    {:ok, Repo.get!(Project, project_id)}
  end

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
  Clears a stale restoration lock if it's older than the given timeout.
  """
  def clear_stale_restoration_lock(project_id, timeout_minutes \\ 15) do
    cutoff = DateTime.add(Storyarn.Shared.TimeHelpers.now(), -timeout_minutes * 60, :second)

    {count, _} =
      from(p in Project,
        where:
          p.id == ^project_id and
            p.restoration_in_progress == true and
            p.restoration_started_at < ^cutoff
      )
      |> Repo.update_all(
        set: [
          restoration_in_progress: false,
          restoration_started_by_id: nil,
          restoration_started_at: nil
        ]
      )

    if count == 1, do: {:ok, :cleared}, else: {:error, :not_stale}
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
