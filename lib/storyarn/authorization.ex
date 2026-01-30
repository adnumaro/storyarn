defmodule Storyarn.Authorization do
  @moduledoc """
  Central authorization module for Storyarn.

  Implements cascading permission system:
  - Project membership overrides workspace membership (more specific wins)
  - If user has no project membership, workspace membership is used
  - If user has neither, access is denied

  ## Permission Hierarchy

  Roles in order of privilege:
  1. owner - Full control
  2. admin - Can manage members (workspace) or all content (project)
  3. member/editor - Can create/edit content
  4. viewer - Read-only access

  ## Examples

      # User is member at workspace level, admin at project level
      # -> Effective role for project: admin (project overrides)

      # User is admin at workspace level, no project membership
      # -> Effective role for project: admin (inherited from workspace)

      # User is admin at workspace level, viewer at project level
      # -> Effective role for project: viewer (project overrides)
  """

  alias Storyarn.Accounts.User
  alias Storyarn.Projects
  alias Storyarn.Projects.{Project, ProjectMembership}
  alias Storyarn.Workspaces
  alias Storyarn.Workspaces.{Workspace, WorkspaceMembership}

  @type role :: String.t()
  @type permission_source :: :project | :workspace
  @type effective_role :: {:ok, role(), permission_source()} | {:error, :no_access}

  @doc """
  Gets the effective role for a user on a specific project.

  Project-level membership overrides workspace-level membership.

  Returns:
  - `{:ok, role, :project}` - Role from direct project membership
  - `{:ok, role, :workspace}` - Role inherited from workspace membership
  - `{:error, :no_access}` - User has no access to the project
  """
  @spec get_effective_role(User.t(), Project.t()) :: effective_role()
  def get_effective_role(%User{} = user, %Project{} = project) do
    case Projects.get_membership(project.id, user.id) do
      %ProjectMembership{role: role} ->
        {:ok, role, :project}

      nil ->
        get_inherited_workspace_role(user, project)
    end
  end

  defp get_inherited_workspace_role(%User{} = _user, %Project{workspace_id: nil}) do
    {:error, :no_access}
  end

  defp get_inherited_workspace_role(%User{} = user, %Project{workspace_id: workspace_id}) do
    case Workspaces.get_membership(workspace_id, user.id) do
      %WorkspaceMembership{role: role} ->
        {:ok, role, :workspace}

      nil ->
        {:error, :no_access}
    end
  end

  @doc """
  Gets the role for a user on a workspace.

  Returns:
  - `{:ok, role}` - User's role in the workspace
  - `{:error, :no_access}` - User has no access to the workspace
  """
  @spec get_role_in_workspace(User.t(), Workspace.t()) :: {:ok, role()} | {:error, :no_access}
  def get_role_in_workspace(%User{} = user, %Workspace{} = workspace) do
    case Workspaces.get_membership(workspace.id, user.id) do
      %WorkspaceMembership{role: role} ->
        {:ok, role}

      nil ->
        {:error, :no_access}
    end
  end

  @doc """
  Checks if a user can perform an action on a project or workspace.

  ## Project Actions

  - `:manage_project` - Update settings, delete project (owner only)
  - `:manage_members` - Invite/remove members, change roles (owner only)
  - `:edit_content` - Edit flows, entities (owner, editor)
  - `:view` - View project content (all roles)

  ## Workspace Actions

  - `:manage_workspace` - Update settings, delete workspace (owner only)
  - `:manage_members` - Invite/remove members, change roles (owner, admin)
  - `:create_project` - Create new projects (owner, admin, member)
  - `:view` - View workspace content (all roles)
  """
  @spec can?(User.t(), atom(), Project.t() | Workspace.t()) :: boolean()
  def can?(%User{} = user, action, %Project{} = project) do
    case get_effective_role(user, project) do
      {:ok, role, _source} ->
        project_action_allowed?(role, action)

      {:error, :no_access} ->
        false
    end
  end

  def can?(%User{} = user, action, %Workspace{} = workspace) do
    case get_role_in_workspace(user, workspace) do
      {:ok, role} ->
        WorkspaceMembership.can?(role, action)

      {:error, :no_access} ->
        false
    end
  end

  # Project action permissions based on role
  defp project_action_allowed?(role, action)

  # Owner can do everything
  defp project_action_allowed?("owner", _action), do: true

  # Admin inherits from workspace - treat as editor for project content
  defp project_action_allowed?("admin", :edit_content), do: true
  defp project_action_allowed?("admin", :view), do: true

  # Editor/Member can edit and view
  defp project_action_allowed?("editor", :edit_content), do: true
  defp project_action_allowed?("editor", :view), do: true
  defp project_action_allowed?("member", :edit_content), do: true
  defp project_action_allowed?("member", :view), do: true

  # Viewer can only view
  defp project_action_allowed?("viewer", :view), do: true

  # Default deny
  defp project_action_allowed?(_role, _action), do: false

  @doc """
  Authorizes and returns the project with effective role information.

  Returns:
  - `{:ok, project, role, source}` - Authorized with role info
  - `{:error, :not_found}` - Project doesn't exist
  - `{:error, :unauthorized}` - User doesn't have required permission
  """
  def authorize_project(%User{} = user, project_id, action) do
    with %Project{} = project <- Storyarn.Repo.get(Project, project_id),
         {:ok, role, source} <- get_effective_role(user, project),
         true <- project_action_allowed?(role, action) do
      {:ok, project, role, source}
    else
      nil -> {:error, :not_found}
      {:error, :no_access} -> {:error, :unauthorized}
      false -> {:error, :unauthorized}
    end
  end

  @doc """
  Returns a human-readable description of where the permission comes from.
  """
  def permission_source_label(:project), do: "project"
  def permission_source_label(:workspace), do: "workspace (inherited)"
end
