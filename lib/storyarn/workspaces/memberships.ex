defmodule Storyarn.Workspaces.Memberships do
  @moduledoc false

  alias Storyarn.Accounts.User
  alias Storyarn.Shared.MembershipOperations
  alias Storyarn.Workspaces.{Workspace, WorkspaceMembership}

  @config %{
    membership_schema: WorkspaceMembership,
    parent_schema: Workspace,
    parent_key: :workspace_id
  }

  def list_workspace_members(workspace_id),
    do: MembershipOperations.list_members(@config, workspace_id)

  def get_membership(%Workspace{id: workspace_id}, %User{id: user_id}),
    do: MembershipOperations.get_membership(@config, workspace_id, user_id)

  def get_membership(workspace_id, user_id)
      when is_integer(workspace_id) and is_integer(user_id),
      do: MembershipOperations.get_membership(@config, workspace_id, user_id)

  def create_membership(workspace_id, user_id, role),
    do: MembershipOperations.create_membership(@config, workspace_id, user_id, role)

  def update_member_role(membership, role),
    do: MembershipOperations.update_member_role(@config, membership, role)

  def remove_member(membership),
    do: MembershipOperations.remove_member(membership)

  def authorize(scope, workspace_id, action),
    do: MembershipOperations.authorize(@config, scope, workspace_id, action)
end
