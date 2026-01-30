defmodule Storyarn.Projects.Memberships do
  @moduledoc false

  import Ecto.Query, warn: false

  alias Storyarn.Accounts.Scope
  alias Storyarn.Projects.{Project, ProjectMembership}
  alias Storyarn.Repo

  @doc """
  Lists all members of a project.
  """
  def list_project_members(project_id) do
    ProjectMembership
    |> where(project_id: ^project_id)
    |> preload(:user)
    |> order_by([m], asc: m.inserted_at)
    |> Repo.all()
  end

  @doc """
  Gets a membership by project and user.
  """
  def get_membership(project_id, user_id) do
    Repo.get_by(ProjectMembership, project_id: project_id, user_id: user_id)
  end

  @doc """
  Creates a membership.
  """
  def create_membership(project_id, user_id, role) do
    %ProjectMembership{}
    |> ProjectMembership.changeset(%{project_id: project_id, user_id: user_id, role: role})
    |> Repo.insert()
  end

  @doc """
  Updates a member's role.

  Cannot change the owner's role.
  """
  def update_member_role(%ProjectMembership{role: "owner"}, _role) do
    {:error, :cannot_change_owner_role}
  end

  def update_member_role(%ProjectMembership{} = membership, role) do
    membership
    |> ProjectMembership.changeset(%{role: role})
    |> Repo.update()
  end

  @doc """
  Removes a member from a project.

  Cannot remove the owner.
  """
  def remove_member(%ProjectMembership{role: "owner"}) do
    {:error, :cannot_remove_owner}
  end

  def remove_member(%ProjectMembership{} = membership) do
    Repo.delete(membership)
  end

  @doc """
  Authorizes a user action on a project.
  """
  def authorize(%Scope{user: user}, project_id, action) do
    with %Project{} = project <- Repo.get(Project, project_id),
         %ProjectMembership{role: role} = membership <- get_membership(project_id, user.id),
         true <- ProjectMembership.can?(role, action) do
      {:ok, project, membership}
    else
      nil -> {:error, :not_found}
      false -> {:error, :unauthorized}
    end
  end
end
