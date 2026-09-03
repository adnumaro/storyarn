defmodule Storyarn.Projects.Lifecycle.Commands.ProjectCommands do
  @moduledoc false

  import Ecto.Query, warn: false

  alias Storyarn.Commercial
  alias Storyarn.Platform.Shared.TimeHelpers
  alias Storyarn.Projects.Assets
  alias Storyarn.Projects.Events
  alias Storyarn.Projects.Lifecycle.Commands.UniqueSlug
  alias Storyarn.Projects.Memberships
  alias Storyarn.Projects.Persistence.WorkspaceMembershipRecord, as: WorkspaceMembership
  alias Storyarn.Projects.Persistence.WorkspaceRecord, as: Workspace
  alias Storyarn.Projects.Project
  alias Storyarn.Projects.ProjectInvitation
  alias Storyarn.Projects.ProjectMembership
  alias Storyarn.Projects.Versioning
  alias Storyarn.Projects.WorkspaceAccess
  alias Storyarn.Repo

  def create_project(%{user: user}, attrs) do
    case attrs[:workspace_id] || attrs["workspace_id"] do
      nil -> {:error, :not_found}
      workspace_id -> do_create_project(user, workspace_id, attrs)
    end
  end

  @spec lock_and_check_workspace_capacity(integer()) ::
          :ok | {:error, :not_found} | {:error, :limit_reached, map()}
  def lock_and_check_workspace_capacity(workspace_id) do
    workspace =
      Workspace
      |> where([candidate], candidate.id == ^workspace_id)
      |> lock("FOR UPDATE")
      |> Repo.one()

    case workspace do
      %Workspace{} -> Commercial.can_create_project?(workspace)
      nil -> {:error, :not_found}
    end
  end

  def change_project(%Project{} = project, attrs \\ %{}), do: Project.update_changeset(project, attrs)
  def change_new_project, do: change_new_project(%Project{}, %{})

  def change_new_project(%Project{} = project, attrs \\ %{}) do
    Project.create_form_changeset(project, attrs)
  end

  def update_project(%{user: %{id: user_id}} = scope, project_id, attrs)
      when is_integer(user_id) and user_id > 0 and is_integer(project_id) and project_id > 0 and is_map(attrs) do
    Repo.transact(fn ->
      with {:ok, %Project{} = project, _membership} <-
             Memberships.authorize_locked(scope, project_id, :manage_project, :update) do
        persist_project_update(project, attrs)
      end
    end)
  end

  def update_project(_scope, _project_id, _attrs), do: {:error, :unauthorized}

  defp persist_project_update(project, attrs) do
    project
    |> Project.update_changeset(attrs)
    |> Ecto.Changeset.put_change(:last_activity_at, TimeHelpers.now())
    |> Repo.update()
  end

  def touch_project(project_id, at \\ TimeHelpers.now())
  def touch_project(project_id, nil), do: touch_project(project_id, TimeHelpers.now())

  def touch_project(project_id, at) when is_integer(project_id) do
    Repo.update_all(from(project in Project, where: project.id == ^project_id),
      set: [last_activity_at: at]
    )

    :ok
  end

  def delete_project(%{user: %{id: user_id}} = scope, project_id)
      when is_integer(user_id) and user_id > 0 and is_integer(project_id) and project_id > 0 do
    with_authorized_project_deletion_lock(scope, project_id, fn locked_project ->
      soft_delete_locked_project(locked_project, user_id)
    end)
  end

  def delete_project(_scope, _project_id), do: {:error, :unauthorized}

  def permanently_delete_project(%Project{} = project) do
    result =
      with {:ok, provider_namespace_fingerprint} <- Assets.storage_provider_namespace_fingerprint() do
        with_project_deletion_lock(project.id, fn locked_project ->
          # credo:disable-for-next-line Credo.Check.Refactor.Nesting
          with {:ok, cleanup_intents} <-
                 Versioning.prepare_project_snapshot_hard_delete(
                   locked_project,
                   provider_namespace_fingerprint
                 ),
               :ok <-
                 Assets.prepare_parent_hard_delete_locked(locked_project.workspace_id, [locked_project.id]),
               {:ok, deleted_project} <- delete_locked_project(locked_project) do
            {:ok, {deleted_project, cleanup_intents}}
          end
        end)
      end

    case result do
      {:ok, {deleted_project, cleanup_intents}} ->
        :ok = Versioning.publish_committed_snapshot_cleanup_intents(cleanup_intents)
        {:ok, deleted_project}

      error ->
        error
    end
  end

  defp delete_locked_project(%Project{} = project), do: Repo.delete(project)

  defp do_create_project(user, workspace_id, attrs) do
    result =
      Repo.transact(fn ->
        with %Workspace{} = workspace <- lock_workspace_for_project_creation(workspace_id),
             {:ok, _membership} <- authorize_project_creation_locked(workspace, user),
             :ok <- normalize_capacity_result(Commercial.can_create_project?(workspace)),
             {:ok, project} <- insert_project(user, attrs),
             {:ok, _membership} <- create_owner_membership(project, user) do
          {:ok, project}
        else
          nil -> {:error, :not_found}
          {:error, reason} -> {:error, reason}
        end
      end)

    case result do
      {:ok, project} ->
        Events.project_created(user, project)
        {:ok, project}

      {:error, {:limit_reached, details}} ->
        {:error, :limit_reached, details}

      error ->
        error
    end
  end

  # The membership mutation workflows that can revoke project-creation rights
  # serialize through this Workspace row before changing their membership.
  # Holding it through authorization, capacity admission and insert makes this
  # command linearizable with membership removal and role changes.
  defp lock_workspace_for_project_creation(workspace_id) do
    Repo.one(
      from(workspace in Workspace,
        where: workspace.id == ^workspace_id,
        lock: "FOR UPDATE"
      )
    )
  end

  defp authorize_project_creation_locked(%Workspace{} = workspace, user) do
    case lock_workspace_membership(workspace.id, user.id) do
      %WorkspaceMembership{role: role} = membership ->
        if WorkspaceAccess.can?(role, :create_project),
          do: {:ok, membership},
          else: {:error, :unauthorized}

      nil ->
        missing_direct_membership_error(workspace, user)
    end
  end

  defp lock_workspace_membership(workspace_id, user_id) do
    Repo.one(
      from(membership in WorkspaceMembership,
        where: membership.workspace_id == ^workspace_id and membership.user_id == ^user_id,
        lock: "FOR UPDATE"
      )
    )
  end

  # Preserve the established distinction for project-only users: they can see
  # the Workspace, but their virtual membership never grants project creation.
  defp missing_direct_membership_error(workspace, user) do
    case WorkspaceAccess.get_workspace(%{user: user}, workspace.id) do
      {:ok, _workspace, _virtual_membership} -> {:error, :unauthorized}
      {:error, reason} -> {:error, reason}
    end
  end

  defp normalize_capacity_result(:ok), do: :ok

  defp normalize_capacity_result({:error, :limit_reached, details}), do: {:error, {:limit_reached, details}}

  defp normalize_capacity_result({:error, reason}), do: {:error, reason}

  defp with_project_deletion_lock(project_id, fun) do
    case persisted_project_workspace_id(project_id) do
      nil ->
        {:error, :not_found}

      workspace_id ->
        workspace_id
        |> Commercial.transact_with_workspace_lock(fn _workspace ->
          delete_locked_project(project_id, workspace_id, fun)
        end)
        |> normalize_project_deletion_result()
    end
  end

  defp with_authorized_project_deletion_lock(scope, project_id, fun) do
    case persisted_project_workspace_id(project_id) do
      nil ->
        {:error, :not_found}

      workspace_id ->
        workspace_id
        |> Commercial.transact_with_workspace_lock(fn _workspace ->
          delete_authorized_project_locked(scope, project_id, workspace_id, fun)
        end)
        |> normalize_project_deletion_result()
    end
  end

  defp delete_authorized_project_locked(scope, project_id, workspace_id, fun) do
    with %Project{} = locked_project <- lock_active_project(project_id, workspace_id),
         {:ok, %Project{id: ^project_id}, _membership} <-
           Memberships.authorize_locked(scope, project_id, :manage_project, :update) do
      fun.(locked_project)
    else
      nil -> {:error, :not_found}
      {:error, reason} -> {:error, reason}
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

  defp lock_active_project(project_id, workspace_id) do
    Repo.one(
      from(candidate in Project,
        where:
          candidate.id == ^project_id and candidate.workspace_id == ^workspace_id and
            is_nil(candidate.deleted_at),
        lock: "FOR UPDATE"
      )
    )
  end

  defp soft_delete_locked_project(locked_project, user_id) do
    locked_project
    |> Project.soft_delete_changeset(%{
      deleted_at: TimeHelpers.now(),
      deleted_by_id: user_id
    })
    |> Repo.update()
    |> case do
      {:ok, deleted_project} ->
        ProjectInvitation
        |> where([invitation], invitation.project_id == ^locked_project.id)
        |> where([invitation], is_nil(invitation.accepted_at))
        |> Repo.delete_all()

        {:ok, deleted_project}

      error ->
        error
    end
  end

  defp normalize_project_deletion_result({:error, :workspace_not_found}), do: {:error, :not_found}
  defp normalize_project_deletion_result(result), do: result

  defp insert_project(user, attrs) do
    workspace_id = attrs[:workspace_id] || attrs["workspace_id"]
    name = attrs[:name] || attrs["name"] || "untitled"
    slug = UniqueSlug.generate(Project, [workspace_id: workspace_id], name)

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
