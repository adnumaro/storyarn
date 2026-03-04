defmodule Storyarn.Shared.MembershipOperations do
  @moduledoc """
  Generic membership operations shared by Projects and Workspaces.

  Parameterized by a config map containing:
  - `membership_schema` — e.g., ProjectMembership or WorkspaceMembership
  - `parent_schema` — e.g., Project or Workspace
  - `parent_key` — e.g., :project_id or :workspace_id
  """

  import Ecto.Query, warn: false

  alias Storyarn.Accounts.Scope
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
  def create_membership(config, parent_id, user_id, role) do
    struct(config.membership_schema)
    |> config.membership_schema.changeset(%{
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

  def update_member_role(config, membership, role) do
    membership
    |> config.membership_schema.changeset(%{role: role})
    |> Repo.update()
  end

  @doc """
  Removes a member. Cannot remove the owner.
  """
  def remove_member(%{role: "owner"}) do
    {:error, :cannot_remove_owner}
  end

  def remove_member(membership) do
    Repo.delete(membership)
  end

  @doc """
  Authorizes a user action on a parent entity.
  """
  def authorize(config, %Scope{user: user}, parent_id, action) do
    with %{} = parent <- Repo.get(config.parent_schema, parent_id),
         %{role: role} = membership <- get_membership(config, parent_id, user.id),
         true <- config.membership_schema.can?(role, action) do
      {:ok, parent, membership}
    else
      nil -> {:error, :not_found}
      false -> {:error, :unauthorized}
    end
  end
end
