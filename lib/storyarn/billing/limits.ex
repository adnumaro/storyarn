defmodule Storyarn.Billing.Limits do
  @moduledoc """
  Limit checks for billing plans. Each function queries current usage
  and compares against the plan limit.
  """

  import Ecto.Query, warn: false

  alias Storyarn.Assets.Asset
  alias Storyarn.Billing.{Plan, SubscriptionCrud}
  alias Storyarn.Flows.{Flow, FlowNode}
  alias Storyarn.Projects.{Project, ProjectMembership}
  alias Storyarn.Repo
  alias Storyarn.Scenes.Scene
  alias Storyarn.Sheets.Sheet
  alias Storyarn.Workspaces.{Workspace, WorkspaceMembership}

  @doc """
  Checks if a user can create another workspace.
  """
  def can_create_workspace?(user) do
    # Uses default plan directly: user has no workspace yet, so no subscription to query.
    # Future: if user-level plans exist, resolve plan from user instead.
    limit = Plan.limit(Plan.default_plan(), :workspaces_per_user)
    used = count_user_workspaces(user.id)
    check_limit(:workspaces_per_user, used, limit)
  end

  @doc """
  Checks if a workspace can have another project.
  """
  def can_create_project?(workspace) do
    plan = SubscriptionCrud.plan_for(workspace)
    limit = Plan.limit(plan, :projects_per_workspace)
    used = count_workspace_projects(workspace.id)
    check_limit(:projects_per_workspace, used, limit)
  end

  @doc """
  Checks if a workspace can have another member (via workspace or project invitation).

  Accepts either a workspace or a project struct — for projects, resolves
  the workspace_id to check workspace-level member limits.
  """
  def can_invite_member?(%Workspace{} = workspace) do
    check_member_limit(workspace.id)
  end

  def can_invite_member?(%Project{} = project) do
    check_member_limit(project.workspace_id)
  end

  @doc """
  Checks if a project's workspace can accept an asset upload of the given size.
  Encapsulates the workspace lookup so callers don't need direct Repo access.
  """
  def can_upload_asset_for_project?(project, file_size) do
    workspace = Repo.get!(Workspace, project.workspace_id)
    can_upload_asset?(workspace, file_size)
  end

  @doc """
  Checks if a workspace can accept an asset upload of the given size.
  """
  def can_upload_asset?(workspace, file_size) do
    plan = SubscriptionCrud.plan_for(workspace)
    limit = Plan.limit(plan, :storage_bytes_per_workspace)
    used = total_workspace_storage(workspace.id)
    new_total = used + file_size

    cond do
      is_nil(limit) ->
        {:error, :limit_reached, %{resource: :storage_bytes_per_workspace, used: used, limit: 0}}

      new_total <= limit ->
        :ok

      true ->
        {:error, :limit_reached,
         %{resource: :storage_bytes_per_workspace, used: used, limit: limit}}
    end
  end

  @doc """
  Checks if a project can have another item (flow node, sheet, flow, or scene).
  """
  def can_create_item?(project) do
    workspace_id = project.workspace_id
    plan = SubscriptionCrud.plan_for_workspace_id(workspace_id)
    limit = Plan.limit(plan, :items_per_project)
    used = count_project_items(project.id)
    check_limit(:items_per_project, used, limit)
  end

  @doc """
  Checks if a project can have another project snapshot.
  """
  def can_create_project_snapshot?(project_id, workspace_id) do
    plan = SubscriptionCrud.plan_for_workspace_id(workspace_id)
    limit = Plan.limit(plan, :project_snapshots_per_project)
    used = Storyarn.Versioning.count_project_snapshots(project_id)
    check_limit(:project_snapshots_per_project, used, limit)
  end

  @doc """
  Checks if a project can have another named version.
  """
  def can_create_named_version?(project_id, workspace_id) do
    plan = SubscriptionCrud.plan_for_workspace_id(workspace_id)
    limit = Plan.limit(plan, :named_versions_per_project)
    used = Storyarn.Versioning.count_named_versions(project_id)
    check_limit(:named_versions_per_project, used, limit)
  end

  @doc """
  Returns version control usage data for a project.
  """
  def project_usage(project_id, workspace_id) do
    plan = SubscriptionCrud.plan_for_workspace_id(workspace_id)

    %{
      project_snapshots: %{
        used: Storyarn.Versioning.count_project_snapshots(project_id),
        limit: Plan.limit(plan, :project_snapshots_per_project)
      },
      named_versions: %{
        used: Storyarn.Versioning.count_named_versions(project_id),
        limit: Plan.limit(plan, :named_versions_per_project)
      }
    }
  end

  @doc """
  Returns usage data for a workspace.
  """
  def usage(workspace) do
    plan = SubscriptionCrud.plan_for(workspace)

    %{
      plan: plan,
      projects: %{
        used: count_workspace_projects(workspace.id),
        limit: Plan.limit(plan, :projects_per_workspace)
      },
      members: %{
        used: count_unique_workspace_users(workspace.id),
        limit: Plan.limit(plan, :members_per_workspace)
      },
      storage_bytes: %{
        used: total_workspace_storage(workspace.id),
        limit: Plan.limit(plan, :storage_bytes_per_workspace)
      }
    }
  end

  # ============================================================================
  # Private count helpers
  # ============================================================================

  defp check_limit(resource, used, nil) do
    # Unknown plan/resource — default to blocking
    {:error, :limit_reached, %{resource: resource, used: used, limit: 0}}
  end

  defp check_limit(_resource, used, limit) when used < limit, do: :ok

  defp check_limit(resource, used, limit) do
    {:error, :limit_reached, %{resource: resource, used: used, limit: limit}}
  end

  defp check_member_limit(workspace_id) do
    plan = SubscriptionCrud.plan_for_workspace_id(workspace_id)
    limit = Plan.limit(plan, :members_per_workspace)
    used = count_unique_workspace_users(workspace_id)
    check_limit(:members_per_workspace, used, limit)
  end

  defp count_user_workspaces(user_id) do
    from(w in Workspace, where: w.owner_id == ^user_id)
    |> Repo.aggregate(:count)
  end

  defp count_workspace_projects(workspace_id) do
    from(p in Project, where: p.workspace_id == ^workspace_id)
    |> Repo.aggregate(:count)
  end

  @doc false
  def count_unique_workspace_users(workspace_id) do
    # Workspace members
    wm_query =
      from(m in WorkspaceMembership,
        where: m.workspace_id == ^workspace_id,
        select: m.user_id
      )

    # Project-only members (users with project membership but no workspace membership)
    pm_query =
      from(pm in ProjectMembership,
        join: p in Project,
        on: pm.project_id == p.id,
        where: p.workspace_id == ^workspace_id,
        select: pm.user_id
      )

    union_query = union(wm_query, ^pm_query)

    from(u in subquery(union_query), select: count(u.user_id))
    |> Repo.one()
  end

  @doc false
  def count_project_items(project_id) do
    count_nodes(project_id) +
      count_active(Sheet, project_id) +
      count_active(Flow, project_id) +
      count_active(Scene, project_id)
  end

  defp count_nodes(project_id) do
    from(n in FlowNode,
      join: f in Flow,
      on: n.flow_id == f.id,
      where:
        f.project_id == ^project_id and is_nil(n.deleted_at) and is_nil(f.deleted_at) and
          is_nil(f.draft_id)
    )
    |> Repo.aggregate(:count)
  end

  defp count_active(schema, project_id) do
    from(s in schema,
      where: s.project_id == ^project_id and is_nil(s.deleted_at) and is_nil(s.draft_id)
    )
    |> Repo.aggregate(:count)
  end

  defp total_workspace_storage(workspace_id) do
    from(a in Asset,
      join: p in Project,
      on: a.project_id == p.id,
      where: p.workspace_id == ^workspace_id,
      select: coalesce(sum(a.size), 0)
    )
    |> Repo.one()
  end
end
