defmodule Storyarn.AI.WorkspaceAccess do
  @moduledoc """
  AI-owned read of workspace access.

  Mirrors the Workspaces context's authorization reads exactly — including
  the virtual membership granted through project-only membership — over
  AI-owned persistence records, so AI policy decisions stop depending on the
  Workspaces boundary.
  """

  import Ecto.Query, warn: false

  alias Storyarn.AI.Persistence.ProjectMembershipRecord, as: ProjectMembership
  alias Storyarn.AI.Persistence.ProjectRecord, as: Project
  alias Storyarn.AI.Persistence.WorkspaceMembershipRecord, as: WorkspaceMembership
  alias Storyarn.AI.Persistence.WorkspaceRecord, as: Workspace
  alias Storyarn.Repo

  @doc """
  Lists all workspaces the user has access to, with `:workspace` and `:role`
  keys. Role is `nil` for workspaces accessible only through project
  membership.
  """
  def list_workspaces(%{user: user}) do
    via_wm =
      Workspace
      |> join(:inner, [w], m in WorkspaceMembership, on: m.workspace_id == w.id and m.user_id == ^user.id)
      |> select([w, m], %{workspace_id: w.id, role: m.role})

    via_pm =
      Workspace
      |> join(:inner, [w], p in Project, on: p.workspace_id == w.id)
      |> join(:inner, [w, p], pm in ProjectMembership, on: pm.project_id == p.id and pm.user_id == ^user.id)
      |> join(:left, [w, p, pm], wm in WorkspaceMembership, on: wm.workspace_id == w.id and wm.user_id == ^user.id)
      |> where([w, p, pm, wm], is_nil(p.deleted_at) and is_nil(wm.id))
      |> select([w, p, pm, wm], %{workspace_id: w.id, role: type(^nil, :string)})
      |> distinct(true)

    union_query = union(via_wm, ^via_pm)

    Repo.all(
      from(u in subquery(union_query),
        join: w in Workspace,
        on: w.id == u.workspace_id,
        select: %{workspace: w, role: u.role},
        order_by: [asc: w.inserted_at]
      )
    )
  end

  @doc """
  Gets a workspace by ID with the same authorization check the Workspaces
  context applies.
  """
  def get_workspace(%{user: user}, id) do
    Workspace
    |> Repo.get(id)
    |> authorize_workspace_access(user)
  end

  @doc """
  Checks if a workspace role can perform an action — the exact permission
  table the Workspaces context owns.
  """
  def can?(role, action)

  def can?("owner", _action), do: true
  def can?("admin", :access_workspace_general_settings), do: true
  def can?("admin", :access_workspace_settings), do: true
  def can?("admin", :manage_members), do: true
  def can?("admin", :create_project), do: true
  def can?("admin", :use_ai), do: true
  def can?("admin", :view), do: true
  def can?("member", :access_workspace_general_settings), do: true
  def can?("member", :create_project), do: true
  def can?("member", :view), do: true
  def can?("viewer", :view), do: true
  def can?(_role, _action), do: false

  defp authorize_workspace_access(nil, _user), do: {:error, :not_found}

  defp authorize_workspace_access(%Workspace{} = workspace, user) do
    case Repo.get_by(WorkspaceMembership, workspace_id: workspace.id, user_id: user.id) do
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

  defp has_project_membership?(workspace_id, user_id) do
    Project
    |> join(:inner, [p], pm in ProjectMembership, on: pm.project_id == p.id)
    |> where([p, pm], p.workspace_id == ^workspace_id and pm.user_id == ^user_id and is_nil(p.deleted_at))
    |> limit(1)
    |> Repo.exists?()
  end

  defp virtual_membership(workspace_id, user_id) do
    %WorkspaceMembership{workspace_id: workspace_id, user_id: user_id, role: nil}
  end
end
