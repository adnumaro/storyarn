defmodule Storyarn.Workspaces.WorkspaceCrud do
  @moduledoc false

  import Ecto.Query, warn: false

  alias Storyarn.Accounts.{Scope, User}
  alias Storyarn.Repo
  alias Storyarn.Workspaces.{Workspace, WorkspaceMembership}

  @doc """
  Lists all workspaces the user has access to.
  """
  def list_workspaces(%Scope{user: user}) do
    Workspace
    |> join(:inner, [w], m in WorkspaceMembership,
      on: m.workspace_id == w.id and m.user_id == ^user.id
    )
    |> select([w, m], %{workspace: w, role: m.role})
    |> order_by([w], asc: w.inserted_at)
    |> Repo.all()
  end

  @doc """
  Lists all workspaces for a user (simpler version for sidebar).
  """
  def list_workspaces_for_user(%User{} = user) do
    Workspace
    |> join(:inner, [w], m in WorkspaceMembership,
      on: m.workspace_id == w.id and m.user_id == ^user.id
    )
    |> order_by([w], asc: w.inserted_at)
    |> Repo.all()
  end

  @doc """
  Gets the user's default workspace.

  Priority: First owned workspace, then first workspace with membership.
  """
  def get_default_workspace(%User{} = user) do
    Workspace
    |> join(:inner, [w], m in WorkspaceMembership,
      on: m.workspace_id == w.id and m.user_id == ^user.id
    )
    |> order_by([w, m],
      desc: fragment("CASE WHEN ? = 'owner' THEN 1 ELSE 0 END", m.role),
      asc: w.inserted_at
    )
    |> limit(1)
    |> Repo.one()
  end

  @doc """
  Gets a workspace by ID with authorization check.
  """
  def get_workspace(%Scope{user: user}, id) do
    with %Workspace{} = workspace <- Repo.get(Workspace, id),
         %WorkspaceMembership{} = membership <- get_membership(workspace.id, user.id) do
      {:ok, workspace, membership}
    else
      nil -> {:error, :not_found}
    end
  end

  @doc """
  Gets a workspace by slug with authorization check.
  """
  def get_workspace_by_slug(%Scope{user: user}, slug) do
    with %Workspace{} = workspace <- Repo.get_by(Workspace, slug: slug),
         %WorkspaceMembership{} = membership <- get_membership(workspace.id, user.id) do
      {:ok, workspace, membership}
    else
      nil -> {:error, :not_found}
    end
  end

  @doc """
  Gets a workspace by slug without authorization check.
  """
  def get_workspace_by_slug!(slug) do
    Repo.get_by!(Workspace, slug: slug)
  end

  @doc """
  Gets a workspace by ID without authorization check.
  """
  def get_workspace!(id), do: Repo.get!(Workspace, id)

  @doc """
  Creates a workspace and sets up the owner membership.
  """
  def create_workspace(%Scope{user: user}, attrs) do
    create_workspace_with_owner(user, attrs)
  end

  @doc """
  Creates a workspace with owner membership (for internal use).
  """
  def create_workspace_with_owner(%User{} = user, attrs) do
    Repo.transact(fn ->
      with {:ok, workspace} <- insert_workspace(user, attrs),
           {:ok, _membership} <- create_owner_membership(workspace, user) do
        {:ok, workspace}
      end
    end)
  end

  @doc """
  Returns a changeset for tracking workspace changes.
  """
  def change_workspace(%Workspace{} = workspace, attrs \\ %{}) do
    Workspace.update_changeset(workspace, attrs)
  end

  @doc """
  Updates a workspace.
  """
  def update_workspace(%Workspace{} = workspace, attrs) do
    workspace
    |> Workspace.update_changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes a workspace.
  """
  def delete_workspace(%Workspace{} = workspace) do
    Repo.delete(workspace)
  end

  # Private helpers

  defp insert_workspace(user, attrs) do
    %Workspace{owner_id: user.id}
    |> Workspace.create_changeset(attrs)
    |> Repo.insert()
  end

  defp create_owner_membership(workspace, user) do
    %WorkspaceMembership{}
    |> WorkspaceMembership.changeset(%{
      workspace_id: workspace.id,
      user_id: user.id,
      role: "owner"
    })
    |> Repo.insert()
  end

  defp get_membership(workspace_id, user_id) do
    Repo.get_by(WorkspaceMembership, workspace_id: workspace_id, user_id: user_id)
  end
end
