defmodule Storyarn.Workspaces.Memberships.Queries.WorkspaceAccess do
  @moduledoc false

  import Ecto.Query, warn: false

  alias Storyarn.Repo
  alias Storyarn.Workspaces.Memberships.Projections.ProjectMembershipRecord, as: ProjectMembership
  alias Storyarn.Workspaces.Memberships.Projections.ProjectRecord, as: Project
  alias Storyarn.Workspaces.Memberships.Queries.Members
  alias Storyarn.Workspaces.Workspace
  alias Storyarn.Workspaces.WorkspaceMembership

  @spec list(%{user: %{id: integer()}}) ::
          [%{workspace: Workspace.t(), role: String.t() | nil}]
  def list(%{user: user}) do
    via_workspace_membership =
      Workspace
      |> join(:inner, [workspace], membership in WorkspaceMembership,
        on: membership.workspace_id == workspace.id and membership.user_id == ^user.id
      )
      |> select([workspace, membership], %{
        workspace_id: workspace.id,
        role: membership.role
      })

    via_project_membership =
      Workspace
      |> join(:inner, [workspace], project in Project, on: project.workspace_id == workspace.id)
      |> join(:inner, [workspace, project], project_membership in ProjectMembership,
        on:
          project_membership.project_id == project.id and
            project_membership.user_id == ^user.id
      )
      |> join(:left, [workspace, project, project_membership], membership in WorkspaceMembership,
        on: membership.workspace_id == workspace.id and membership.user_id == ^user.id
      )
      |> where(
        [workspace, project, project_membership, membership],
        is_nil(project.deleted_at) and is_nil(membership.id)
      )
      |> select([workspace, project, project_membership, membership], %{
        workspace_id: workspace.id,
        role: type(^nil, :string)
      })
      |> distinct(true)

    union_query = union(via_workspace_membership, ^via_project_membership)

    Repo.all(
      from(entry in subquery(union_query),
        join: workspace in Workspace,
        on: workspace.id == entry.workspace_id,
        select: %{workspace: workspace, role: entry.role},
        order_by: [asc: workspace.inserted_at]
      )
    )
  end

  @spec list_for_user(%{id: integer()}) :: [Workspace.t()]
  def list_for_user(%{id: _} = user) do
    Workspace
    |> join(:left, [workspace], membership in WorkspaceMembership,
      on: membership.workspace_id == workspace.id and membership.user_id == ^user.id
    )
    |> join(:left, [workspace, membership], project in Project, on: project.workspace_id == workspace.id)
    |> join(
      :left,
      [workspace, membership, project],
      project_membership in ProjectMembership,
      on:
        project_membership.project_id == project.id and
          project_membership.user_id == ^user.id
    )
    |> where(
      [workspace, membership, project, project_membership],
      not is_nil(membership.id) or
        (is_nil(project.deleted_at) and not is_nil(project_membership.id))
    )
    |> distinct([workspace], workspace.id)
    |> order_by([workspace], asc: workspace.inserted_at)
    |> Repo.all()
  end

  @spec default_for(%{id: integer()}) :: Workspace.t() | nil
  def default_for(%{id: _} = user) do
    workspace =
      Workspace
      |> join(:inner, [workspace], membership in WorkspaceMembership,
        on: membership.workspace_id == workspace.id and membership.user_id == ^user.id
      )
      |> order_by([workspace, membership],
        desc: fragment("CASE WHEN ? = 'owner' THEN 1 ELSE 0 END", membership.role),
        asc: workspace.inserted_at
      )
      |> limit(1)
      |> Repo.one()

    workspace || default_via_project(user)
  end

  @spec get(%{user: %{id: integer()}}, integer()) ::
          {:ok, Workspace.t(), WorkspaceMembership.t()} | {:error, :not_found}
  def get(%{user: user}, id) do
    Workspace
    |> Repo.get(id)
    |> authorize_workspace_access(user)
  end

  @spec get_by_slug(%{user: %{id: integer()}}, String.t()) ::
          {:ok, Workspace.t(), WorkspaceMembership.t()} | {:error, :not_found}
  def get_by_slug(%{user: user}, slug) do
    Workspace
    |> Repo.get_by(slug: slug)
    |> authorize_workspace_access(user)
  end

  defp authorize_workspace_access(nil, _user), do: {:error, :not_found}

  defp authorize_workspace_access(%Workspace{} = workspace, user) do
    case Members.get(workspace.id, user.id) do
      %WorkspaceMembership{} = membership ->
        {:ok, workspace, membership}

      nil ->
        if project_member?(workspace.id, user.id) do
          {:ok, workspace, virtual_membership(workspace.id, user.id)}
        else
          {:error, :not_found}
        end
    end
  end

  defp project_member?(workspace_id, user_id) do
    Project
    |> join(:inner, [project], project_membership in ProjectMembership, on: project_membership.project_id == project.id)
    |> where(
      [project, project_membership],
      project.workspace_id == ^workspace_id and
        project_membership.user_id == ^user_id and is_nil(project.deleted_at)
    )
    |> limit(1)
    |> Repo.exists?()
  end

  defp virtual_membership(workspace_id, user_id) do
    %WorkspaceMembership{workspace_id: workspace_id, user_id: user_id, role: nil}
  end

  defp default_via_project(user) do
    Workspace
    |> join(:inner, [workspace], project in Project, on: project.workspace_id == workspace.id)
    |> join(:inner, [workspace, project], project_membership in ProjectMembership,
      on:
        project_membership.project_id == project.id and
          project_membership.user_id == ^user.id
    )
    |> where([workspace, project, project_membership], is_nil(project.deleted_at))
    |> order_by([workspace], asc: workspace.inserted_at)
    |> limit(1)
    |> Repo.one()
  end
end
