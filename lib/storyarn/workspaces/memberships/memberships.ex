defmodule Storyarn.Workspaces.Memberships do
  @moduledoc false

  alias Storyarn.Workspaces.Memberships.Commands.ChangeMemberRole
  alias Storyarn.Workspaces.Memberships.Commands.CreateMembership
  alias Storyarn.Workspaces.Memberships.Commands.RemoveMember
  alias Storyarn.Workspaces.Memberships.Queries.Authorize
  alias Storyarn.Workspaces.Memberships.Queries.Members
  alias Storyarn.Workspaces.Memberships.Queries.WorkspaceAccess
  alias Storyarn.Workspaces.Memberships.Rules.Permissions

  defdelegate list_workspaces(scope), to: WorkspaceAccess, as: :list
  defdelegate list_workspaces_for_user(user), to: WorkspaceAccess, as: :list_for_user
  defdelegate get_default_workspace(user), to: WorkspaceAccess, as: :default_for
  defdelegate get_workspace(scope, id), to: WorkspaceAccess, as: :get
  defdelegate get_workspace_by_slug(scope, slug), to: WorkspaceAccess, as: :get_by_slug

  defdelegate list_workspace_members(workspace_id), to: Members, as: :list
  defdelegate get_membership(workspace_or_id, user_or_id), to: Members, as: :get
  defdelegate create_membership(workspace_id, user_id, role), to: CreateMembership, as: :create
  defdelegate update_member_role(membership, role), to: ChangeMemberRole, as: :change
  defdelegate remove_member(membership), to: RemoveMember, as: :remove
  defdelegate authorize(scope, workspace_id, action), to: Authorize, as: :call
  defdelegate can?(role, action), to: Permissions, as: :allowed?
end
