defmodule Storyarn.Projects.ProjectCrud do
  @moduledoc false

  import Ecto.Query, warn: false

  alias Storyarn.Accounts.Scope
  alias Storyarn.Analytics
  alias Storyarn.Assets
  alias Storyarn.Billing
  alias Storyarn.Projects.Memberships
  alias Storyarn.Projects.Project
  alias Storyarn.Projects.ProjectInvitation
  alias Storyarn.Projects.ProjectMembership
  alias Storyarn.Repo
  alias Storyarn.Shared.NameNormalizer
  alias Storyarn.Shared.TimeHelpers
  alias Storyarn.Versioning
  alias Storyarn.Workspaces
  alias Storyarn.Workspaces.Workspace

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
          project_subtype: project.project_subtype
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
  def change_new_project, do: change_new_project(%Project{}, %{})

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
    with_project_deletion_lock(project.id, fn locked_project ->
      locked_project
      |> Project.soft_delete_changeset(%{
        deleted_at: TimeHelpers.now(),
        deleted_by_id: user_id
      })
      |> Repo.update()
      |> case do
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
    result =
      with_project_deletion_lock(project.id, fn locked_project ->
        with {:ok, cleanup_intents} <- Versioning.prepare_project_snapshot_hard_delete(locked_project),
             :ok <-
               Assets.prepare_parent_hard_delete_locked(locked_project.workspace_id, [locked_project.id]),
             {:ok, deleted_project} <- Repo.delete(locked_project) do
          {:ok, {deleted_project, cleanup_intents}}
        end
      end)

    case result do
      {:ok, {deleted_project, cleanup_intents}} ->
        :ok = Versioning.publish_committed_snapshot_cleanup_intents(cleanup_intents)
        {:ok, deleted_project}

      error ->
        error
    end
  end

  defp with_project_deletion_lock(project_id, fun) do
    case persisted_project_workspace_id(project_id) do
      nil ->
        {:error, :not_found}

      workspace_id ->
        workspace_id
        |> Billing.transact_with_workspace_lock(fn _workspace ->
          delete_locked_project(project_id, workspace_id, fun)
        end)
        |> normalize_project_deletion_result()
    end
  end

  defp delete_locked_project(project_id, workspace_id, fun) do
    case lock_project(project_id, workspace_id) do
      %Project{} = locked_project -> fun.(locked_project)
      nil -> {:error, :not_found}
    end
  end

  defp persisted_project_workspace_id(project_id) do
    Repo.one(
      from(candidate in Project,
        where: candidate.id == ^project_id,
        select: candidate.workspace_id
      )
    )
  end

  defp lock_project(project_id, workspace_id) do
    Repo.one(
      from(candidate in Project,
        where: candidate.id == ^project_id and candidate.workspace_id == ^workspace_id,
        lock: "FOR UPDATE"
      )
    )
  end

  defp normalize_project_deletion_result({:error, :workspace_not_found}), do: {:error, :not_found}

  defp normalize_project_deletion_result(result), do: result

  @doc """
  Lists soft-deleted projects in a workspace.
  Preloads the user who moved each project to trash.
  """
  def list_deleted_projects(workspace_id) do
    Repo.all(
      from(p in Project,
        where: p.workspace_id == ^workspace_id and not is_nil(p.deleted_at),
        order_by: [desc: p.deleted_at],
        preload: [:deleted_by]
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
