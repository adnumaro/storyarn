defmodule Storyarn.Workspaces.Memberships do
  @moduledoc false

  import Ecto.Query, warn: false

  alias Storyarn.Accounts.{Scope, User}
  alias Storyarn.Repo
  alias Storyarn.Workspaces.{Workspace, WorkspaceMembership}

  @doc """
  Lists all members of a workspace.
  """
  def list_workspace_members(workspace_id) do
    WorkspaceMembership
    |> where(workspace_id: ^workspace_id)
    |> preload(:user)
    |> order_by([m], asc: m.inserted_at)
    |> Repo.all()
  end

  @doc """
  Gets a membership by workspace and user.
  """
  def get_membership(%Workspace{id: workspace_id}, %User{id: user_id}) do
    get_membership(workspace_id, user_id)
  end

  def get_membership(workspace_id, user_id)
      when is_integer(workspace_id) and is_integer(user_id) do
    Repo.get_by(WorkspaceMembership, workspace_id: workspace_id, user_id: user_id)
  end

  @doc """
  Creates a membership.
  """
  def create_membership(workspace_id, user_id, role) do
    %WorkspaceMembership{}
    |> WorkspaceMembership.changeset(%{
      workspace_id: workspace_id,
      user_id: user_id,
      role: role
    })
    |> Repo.insert()
  end

  @doc """
  Updates a member's role.

  Cannot change the owner's role.
  """
  def update_member_role(%WorkspaceMembership{role: "owner"}, _role) do
    {:error, :cannot_change_owner_role}
  end

  def update_member_role(%WorkspaceMembership{} = membership, role) do
    membership
    |> WorkspaceMembership.changeset(%{role: role})
    |> Repo.update()
  end

  @doc """
  Removes a member from a workspace.

  Cannot remove the owner.
  """
  def remove_member(%WorkspaceMembership{role: "owner"}) do
    {:error, :cannot_remove_owner}
  end

  def remove_member(%WorkspaceMembership{} = membership) do
    Repo.delete(membership)
  end

  @doc """
  Authorizes a user action on a workspace.
  """
  def authorize(%Scope{user: user}, workspace_id, action) do
    with %Workspace{} = workspace <- Repo.get(Workspace, workspace_id),
         %WorkspaceMembership{role: role} = membership <- get_membership(workspace_id, user.id),
         true <- WorkspaceMembership.can?(role, action) do
      {:ok, workspace, membership}
    else
      nil -> {:error, :not_found}
      false -> {:error, :unauthorized}
    end
  end
end
