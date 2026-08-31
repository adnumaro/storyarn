defmodule Storyarn.Projects.MembershipOperations do
  @moduledoc """
  Membership operations serving the Projects context. The workspace arm moved
  into `Storyarn.Workspaces.Memberships` during the ENG-92 bounded-context
  migration.

  The config map retains the established query interface, but every writer is
  explicitly bound to the Project-owned membership schema so persistence
  ownership remains statically reviewable.
  """

  import Ecto.Query, warn: false

  alias Storyarn.Projects.ProjectMembership
  alias Storyarn.Repo

  @doc """
  Lists all members of a parent entity.
  """
  def list_members(config, parent_id) do
    config.membership_schema
    |> where([m], field(m, ^config.parent_key) == ^parent_id)
    |> preload(:user)
    |> order_by([m], asc: m.inserted_at)
    |> Repo.all()
  end

  @doc """
  Gets a membership by parent and user IDs.
  """
  def get_membership(config, parent_id, user_id) do
    Repo.get_by(config.membership_schema, [{config.parent_key, parent_id}, {:user_id, user_id}])
  end

  @doc """
  Creates a membership.
  """
  def create_membership(_config, _parent_id, _user_id, "owner") do
    {:error, :cannot_assign_owner_role}
  end

  def create_membership(%{membership_schema: ProjectMembership} = config, parent_id, user_id, role) do
    %ProjectMembership{}
    |> ProjectMembership.changeset(%{
      config.parent_key => parent_id,
      :user_id => user_id,
      :role => role
    })
    |> Repo.insert()
  end

  @doc """
  Updates a member's role. Cannot change the owner's role.
  """
  def update_member_role(_config, %{role: "owner"}, _role) do
    {:error, :cannot_change_owner_role}
  end

  def update_member_role(_config, _membership, "owner") do
    {:error, :cannot_assign_owner_role}
  end

  def update_member_role(%{membership_schema: ProjectMembership}, %ProjectMembership{} = membership, role) do
    membership
    |> ProjectMembership.changeset(%{role: role})
    |> Repo.update()
  end

  @doc """
  Removes a member. Cannot remove the owner.
  """
  def remove_member(%ProjectMembership{role: "owner"}) do
    {:error, :cannot_remove_owner}
  end

  def remove_member(%ProjectMembership{} = membership) do
    Repo.delete(membership)
  end
end
