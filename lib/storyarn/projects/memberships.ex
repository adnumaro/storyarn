defmodule Storyarn.Projects.Memberships do
  @moduledoc false

  alias Storyarn.Projects.{Project, ProjectMembership}
  alias Storyarn.Repo
  alias Storyarn.Shared.MembershipOperations
  alias Storyarn.Workspaces.WorkspaceMembership

  @config %{
    membership_schema: ProjectMembership,
    parent_schema: Project,
    parent_key: :project_id
  }

  # Workspace role → synthetic project role mapping
  @workspace_to_project_role %{
    "owner" => "editor",
    "admin" => "editor",
    "member" => "editor",
    "viewer" => "viewer"
  }

  def list_project_members(project_id),
    do: MembershipOperations.list_members(@config, project_id)

  def get_membership(project_id, user_id),
    do: MembershipOperations.get_membership(@config, project_id, user_id)

  @doc """
  Gets the effective membership for a user on a project.

  First checks for a direct ProjectMembership. If none exists, falls back to
  the user's WorkspaceMembership and maps the workspace role to a synthetic
  project role (owner/admin/member → editor, viewer → viewer).

  Returns `%ProjectMembership{}` or `nil`.
  """
  def get_effective_membership(project_id, user_id, workspace_id) do
    case get_membership(project_id, user_id) do
      %ProjectMembership{} = pm ->
        pm

      nil ->
        case Repo.get_by(WorkspaceMembership, workspace_id: workspace_id, user_id: user_id) do
          %WorkspaceMembership{role: ws_role} ->
            project_role = Map.get(@workspace_to_project_role, ws_role, "viewer")

            %ProjectMembership{
              project_id: project_id,
              user_id: user_id,
              role: project_role
            }

          nil ->
            nil
        end
    end
  end

  def create_membership(project_id, user_id, role),
    do: MembershipOperations.create_membership(@config, project_id, user_id, role)

  def update_member_role(membership, role),
    do: MembershipOperations.update_member_role(@config, membership, role)

  def remove_member(membership),
    do: MembershipOperations.remove_member(membership)

  def authorize(scope, project_id, action),
    do: MembershipOperations.authorize(@config, scope, project_id, action)
end
