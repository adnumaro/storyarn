defmodule Storyarn.Projects.WorkspaceAccess do
  @moduledoc """
  Project-owned read of workspace access.

  Mirrors the Workspaces context's authorization reads exactly — including
  the workspace permission table and the virtual membership granted through
  project-only membership — over Project-owned persistence records.
  """

  import Ecto.Query, warn: false

  alias Storyarn.Projects.Persistence.WorkspaceMembershipRecord, as: WorkspaceMembership
  alias Storyarn.Projects.Persistence.WorkspaceRecord, as: Workspace
  alias Storyarn.Projects.Project
  alias Storyarn.Projects.ProjectMembership
  alias Storyarn.Repo

  @doc """
  Checks if a workspace role can perform an action — the exact permission
  table the Workspaces context owns.
  """
  def can?(role, action)

  def can?("owner", _action), do: true
  def can?("admin", :access_workspace_general_settings), do: true
  def can?("admin", :access_workspace_settings), do: true
  def can?("admin", :manage_members), do: true
  def can?("admin", :create_project), do: true
  def can?("admin", :use_ai), do: true
  def can?("admin", :view), do: true
  def can?("member", :access_workspace_general_settings), do: true
  def can?("member", :create_project), do: true
  def can?("member", :view), do: true
  def can?("viewer", :view), do: true
  def can?(_role, _action), do: false

  @doc """
  Authorizes a user action on a workspace — the exact check the Workspaces
  context applies for workspace-level actions.
  """
  def authorize(%{user: user}, workspace_id, action) do
    with %Workspace{} = workspace <- Repo.get(Workspace, workspace_id),
         %{role: role} = membership <- get_membership(workspace_id, user.id),
         true <- can?(role, action) do
      {:ok, workspace, membership}
    else
      nil -> {:error, :not_found}
      false -> {:error, :unauthorized}
    end
  end

  @doc """
  Gets a workspace by ID with the same authorization check the Workspaces
  context applies, including the virtual project-only membership.
  """
  def get_workspace(%{user: user}, id) do
    Workspace
    |> Repo.get(id)
    |> authorize_workspace_access(user)
  end

  defp authorize_workspace_access(nil, _user), do: {:error, :not_found}

  defp authorize_workspace_access(%Workspace{} = workspace, user) do
    case get_membership(workspace.id, user.id) do
      %WorkspaceMembership{} = membership ->
        {:ok, workspace, membership}

      nil ->
        if has_project_membership?(workspace.id, user.id) do
          {:ok, workspace, %WorkspaceMembership{workspace_id: workspace.id, user_id: user.id, role: nil}}
        else
          {:error, :not_found}
        end
    end
  end

  defp has_project_membership?(workspace_id, user_id) do
    Project
    |> join(:inner, [p], pm in ProjectMembership, on: pm.project_id == p.id)
    |> where([p, pm], p.workspace_id == ^workspace_id and pm.user_id == ^user_id and is_nil(p.deleted_at))
    |> limit(1)
    |> Repo.exists?()
  end

  @doc "Gets a membership by workspace and user ids."
  def get_membership(workspace_id, user_id) do
    Repo.get_by(WorkspaceMembership, workspace_id: workspace_id, user_id: user_id)
  end
end
