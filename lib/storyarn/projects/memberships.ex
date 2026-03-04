defmodule Storyarn.Projects.Memberships do
  @moduledoc false

  alias Storyarn.Projects.{Project, ProjectMembership}
  alias Storyarn.Shared.MembershipOperations

  @config %{
    membership_schema: ProjectMembership,
    parent_schema: Project,
    parent_key: :project_id
  }

  def list_project_members(project_id),
    do: MembershipOperations.list_members(@config, project_id)

  def get_membership(project_id, user_id),
    do: MembershipOperations.get_membership(@config, project_id, user_id)

  def create_membership(project_id, user_id, role),
    do: MembershipOperations.create_membership(@config, project_id, user_id, role)

  def update_member_role(membership, role),
    do: MembershipOperations.update_member_role(@config, membership, role)

  def remove_member(membership),
    do: MembershipOperations.remove_member(membership)

  def authorize(scope, project_id, action),
    do: MembershipOperations.authorize(@config, scope, project_id, action)
end
