defmodule Storyarn.AI.Governance.Queries.WorkspaceAccess do
  @moduledoc """
  AI-owned workspace access reads over Governance-local SQL projections.

  Project-only access remains visible as a virtual membership with a nil role,
  preserving the distinction between visibility and permission to configure AI.
  """

  import Ecto.Query, warn: false

  alias Storyarn.AI.Governance
  alias Storyarn.AI.Governance.Data.ProjectMembershipRecord, as: ProjectMembership
  alias Storyarn.AI.Governance.Data.ProjectRecord, as: Project
  alias Storyarn.AI.Governance.Data.WorkspaceMembershipRecord, as: WorkspaceMembership
  alias Storyarn.AI.Governance.Data.WorkspaceRecord, as: Workspace
  alias Storyarn.AI.Governance.Rules.WorkspacePermissions
  alias Storyarn.Repo

  @spec list(Governance.scope()) :: [%{workspace: Workspace.t(), role: String.t() | nil}]
  def list(%{user: %{id: user_id}}) do
    via_workspace_membership =
      Workspace
      |> join(:inner, [workspace], membership in WorkspaceMembership,
        on: membership.workspace_id == workspace.id and membership.user_id == ^user_id
      )
      |> select([workspace, membership], %{workspace_id: workspace.id, role: membership.role})

    via_project_membership =
      Workspace
      |> join(:inner, [workspace], project in Project, on: project.workspace_id == workspace.id)
      |> join(:inner, [workspace, project], membership in ProjectMembership,
        on: membership.project_id == project.id and membership.user_id == ^user_id
      )
      |> join(:left, [workspace, project, membership], workspace_membership in WorkspaceMembership,
        on: workspace_membership.workspace_id == workspace.id and workspace_membership.user_id == ^user_id
      )
      |> where(
        [workspace, project, membership, workspace_membership],
        is_nil(project.deleted_at) and is_nil(workspace_membership.id)
      )
      |> select([workspace, project, membership, workspace_membership], %{
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

  def list(%{user: _user}), do: []

  @spec get(Governance.scope(), pos_integer()) ::
          {:ok, Workspace.t(), WorkspaceMembership.t()} | {:error, :not_found}
  def get(%{user: %{id: user_id}}, id) do
    Workspace
    |> Repo.get(id)
    |> authorize(user_id)
  end

  def get(%{user: _user}, _id), do: {:error, :not_found}

  @spec can?(String.t() | nil, atom()) :: boolean()
  defdelegate can?(role, action), to: WorkspacePermissions, as: :allowed?

  defp authorize(nil, _user_id), do: {:error, :not_found}

  defp authorize(%Workspace{} = workspace, user_id) do
    case Repo.get_by(WorkspaceMembership, workspace_id: workspace.id, user_id: user_id) do
      %WorkspaceMembership{} = membership ->
        {:ok, workspace, membership}

      nil ->
        authorize_project_only(workspace, user_id)
    end
  end

  defp authorize_project_only(workspace, user_id) do
    if project_membership?(workspace.id, user_id),
      do: {:ok, workspace, virtual_membership(workspace.id, user_id)},
      else: {:error, :not_found}
  end

  defp project_membership?(workspace_id, user_id) do
    Project
    |> join(:inner, [project], membership in ProjectMembership, on: membership.project_id == project.id)
    |> where(
      [project, membership],
      project.workspace_id == ^workspace_id and membership.user_id == ^user_id and
        is_nil(project.deleted_at)
    )
    |> limit(1)
    |> Repo.exists?()
  end

  defp virtual_membership(workspace_id, user_id) do
    %WorkspaceMembership{workspace_id: workspace_id, user_id: user_id, role: nil}
  end
end
