defmodule Storyarn.Workspaces.WorkspaceCrud do
  @moduledoc false

  import Ecto.Query, warn: false

  alias Storyarn.Accounts.{Scope, User}
  alias Storyarn.Billing
  alias Storyarn.Projects.{Project, ProjectMembership}
  alias Storyarn.Repo
  alias Storyarn.Workspaces.{Workspace, WorkspaceMembership}

  @doc """
  Lists all workspaces the user has access to.

  Includes workspaces via WorkspaceMembership (with role) and workspaces
  the user can see through ProjectMembership only (with role: nil).
  """
  def list_workspaces(%Scope{user: user}) do
    # Workspaces via workspace membership
    via_wm =
      Workspace
      |> join(:inner, [w], m in WorkspaceMembership,
        on: m.workspace_id == w.id and m.user_id == ^user.id
      )
      |> select([w, m], %{workspace_id: w.id, role: m.role})

    # Workspaces via project membership only (no workspace membership)
    via_pm =
      Workspace
      |> join(:inner, [w], p in Project, on: p.workspace_id == w.id)
      |> join(:inner, [w, p], pm in ProjectMembership,
        on: pm.project_id == p.id and pm.user_id == ^user.id
      )
      |> join(:left, [w, p, pm], wm in WorkspaceMembership,
        on: wm.workspace_id == w.id and wm.user_id == ^user.id
      )
      |> where([w, p, pm, wm], is_nil(wm.id))
      |> select([w, p, pm, wm], %{workspace_id: w.id, role: type(^nil, :string)})
      |> distinct(true)

    union_query = union(via_wm, ^via_pm)

    from(u in subquery(union_query),
      join: w in Workspace,
      on: w.id == u.workspace_id,
      select: %{workspace: w, role: u.role},
      order_by: [asc: w.inserted_at]
    )
    |> Repo.all()
  end

  @doc """
  Lists all workspaces for a user (simpler version for sidebar).

  Includes workspaces visible through ProjectMembership.
  """
  def list_workspaces_for_user(%User{} = user) do
    Workspace
    |> join(:left, [w], wm in WorkspaceMembership,
      on: wm.workspace_id == w.id and wm.user_id == ^user.id
    )
    |> join(:left, [w, wm], p in Project, on: p.workspace_id == w.id)
    |> join(:left, [w, wm, p], pm in ProjectMembership,
      on: pm.project_id == p.id and pm.user_id == ^user.id
    )
    |> where([w, wm, p, pm], not is_nil(wm.id) or not is_nil(pm.id))
    |> distinct([w], w.id)
    |> order_by([w], asc: w.inserted_at)
    |> Repo.all()
  end

  @doc """
  Gets the user's default workspace.

  Priority: First owned workspace via WorkspaceMembership, then first workspace
  with any membership. Falls back to workspace via ProjectMembership.
  """
  def get_default_workspace(%User{} = user) do
    workspace =
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

    workspace || get_default_workspace_via_project(user)
  end

  @doc """
  Gets a workspace by ID with authorization check.

  Returns a virtual WorkspaceMembership with `role: nil` for users who have
  access only through ProjectMembership (no workspace-level permissions).
  """
  def get_workspace(%Scope{user: user}, id) do
    Repo.get(Workspace, id)
    |> authorize_workspace_access(user)
  end

  @doc """
  Gets a workspace by slug with authorization check.

  Returns a virtual WorkspaceMembership with `role: nil` for users who have
  access only through ProjectMembership (no workspace-level permissions).
  """
  def get_workspace_by_slug(%Scope{user: user}, slug) do
    Repo.get_by(Workspace, slug: slug)
    |> authorize_workspace_access(user)
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
    with :ok <- Billing.can_create_workspace?(user) do
      do_create_workspace_with_owner(user, attrs)
    end
  end

  defp do_create_workspace_with_owner(user, attrs) do
    Repo.transact(fn ->
      with {:ok, workspace} <- insert_workspace(user, attrs),
           {:ok, _membership} <- create_owner_membership(workspace, user),
           {:ok, _subscription} <- Billing.create_subscription(workspace) do
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

  defp authorize_workspace_access(nil, _user), do: {:error, :not_found}

  defp authorize_workspace_access(%Workspace{} = workspace, user) do
    case get_membership(workspace.id, user.id) do
      %WorkspaceMembership{} = membership ->
        {:ok, workspace, membership}

      nil ->
        if has_project_membership?(workspace.id, user.id) do
          {:ok, workspace, virtual_membership(workspace.id, user.id)}
        else
          {:error, :not_found}
        end
    end
  end

  defp get_membership(workspace_id, user_id) do
    Repo.get_by(WorkspaceMembership, workspace_id: workspace_id, user_id: user_id)
  end

  defp has_project_membership?(workspace_id, user_id) do
    Project
    |> join(:inner, [p], pm in ProjectMembership, on: pm.project_id == p.id)
    |> where([p, pm], p.workspace_id == ^workspace_id and pm.user_id == ^user_id)
    |> limit(1)
    |> Repo.exists?()
  end

  defp virtual_membership(workspace_id, user_id) do
    %WorkspaceMembership{workspace_id: workspace_id, user_id: user_id, role: nil}
  end

  defp get_default_workspace_via_project(%User{} = user) do
    Workspace
    |> join(:inner, [w], p in Project, on: p.workspace_id == w.id)
    |> join(:inner, [w, p], pm in ProjectMembership,
      on: pm.project_id == p.id and pm.user_id == ^user.id
    )
    |> order_by([w], asc: w.inserted_at)
    |> limit(1)
    |> Repo.one()
  end
end
