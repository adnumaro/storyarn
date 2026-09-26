defmodule Storyarn.Commercial.Billing.Limits do
  @moduledoc """
  Limit checks for billing plans. Each function queries current usage
  and compares against the plan limit.
  """

  import Ecto.Query, warn: false

  alias Storyarn.Commercial.Billing.EditorSeats
  alias Storyarn.Commercial.Billing.Persistence.EntityVersionRecord
  alias Storyarn.Commercial.Billing.Persistence.FlowNodeRecord
  alias Storyarn.Commercial.Billing.Persistence.FlowRecord
  alias Storyarn.Commercial.Billing.Persistence.ProjectRecord, as: Project
  alias Storyarn.Commercial.Billing.Persistence.ProjectTemplateRecord, as: ProjectTemplate
  alias Storyarn.Commercial.Billing.Persistence.ProjectTemplateVersionRecord, as: ProjectTemplateVersion
  alias Storyarn.Commercial.Billing.Persistence.SceneRecord
  alias Storyarn.Commercial.Billing.Persistence.SheetRecord
  alias Storyarn.Commercial.Billing.Persistence.WorkspaceRecord, as: Workspace
  alias Storyarn.Commercial.Billing.Persistence.WorkspaceSnapshotImportRecord, as: WorkspaceSnapshotImport
  alias Storyarn.Commercial.Billing.Plan
  alias Storyarn.Commercial.Billing.StorageAccounting
  alias Storyarn.Commercial.Queries.Subscriptions
  alias Storyarn.Repo

  @doc """
  Checks if a user can create another workspace.

  This is an admission check, not a concurrency boundary. Workspace creation
  must hold a row lock for the user while it calls this function and until the
  new Workspace commits.
  """
  def can_create_workspace?(user) do
    # Only the workspaces the user owns count; being a member of someone
    # else's workspace does not.
    limit = user.id |> Subscriptions.plan_for_user() |> Plan.limit(:workspaces_per_user)
    used = count_user_workspaces(user.id)
    check_limit(:workspaces_per_user, used, limit)
  end

  @doc """
  Checks if a workspace can have another project.
  """
  def can_create_project?(workspace) do
    plan = Subscriptions.plan_for(workspace)
    limit = Plan.limit(plan, :projects_per_workspace)
    used = count_workspace_projects(workspace.id) + count_active_workspace_imports(workspace.id)
    check_limit(:projects_per_workspace, used, limit)
  end

  @doc false
  def can_publish_reserved_project?(workspace) do
    plan = Subscriptions.plan_for(workspace)

    check_limit(
      :projects_per_workspace,
      count_workspace_projects(workspace.id),
      Plan.limit(plan, :projects_per_workspace)
    )
  end

  @doc """
  Checks if a source project's workspace can publish another project template.
  """
  def can_create_project_template?(%{id: _, workspace_id: _} = source_project) do
    plan = Subscriptions.plan_for_workspace_id(source_project.workspace_id)
    limit = Plan.limit(plan, :project_templates_per_workspace)
    used = count_workspace_project_templates(source_project.workspace_id)
    check_limit(:project_templates_per_workspace, used, limit)
  end

  @doc """
  Checks if a template can publish another immutable version.
  """
  def can_create_project_template_version?(%{id: _, source_project_id: _} = template) do
    plan = plan_for_template(template)
    limit = Plan.limit(plan, :project_template_versions_per_template)
    used = count_project_template_versions(template.id)
    check_limit(:project_template_versions_per_template, used, limit)
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
    StorageAccounting.check_capacity(workspace, file_size)
  end

  @doc """
  Checks if a project can have another item (flow node, sheet, flow, or scene).
  """
  def can_create_item?(project) do
    can_create_items?(project, 1)
  end

  @doc """
  Checks whether a project has room for a compound operation that creates
  multiple billable items atomically.
  """
  def can_create_items?(project, count) when is_integer(count) and count > 0 do
    workspace_id = project.workspace_id
    plan = Subscriptions.plan_for_workspace_id(workspace_id)
    limit = Plan.limit(plan, :items_per_project)
    used = count_project_items(project.id)
    check_capacity(:items_per_project, used, limit, count)
  end

  @doc """
  Checks if a project can have another named version.
  """
  def can_create_named_version?(project_id, workspace_id) do
    plan = Subscriptions.plan_for_workspace_id(workspace_id)
    limit = Plan.limit(plan, :named_versions_per_project)
    used = count_named_versions(project_id)
    check_limit(:named_versions_per_project, used, limit)
  end

  @doc """
  Returns version control usage data for a project.
  """
  def project_usage(project_id, workspace_id) do
    plan = Subscriptions.plan_for_workspace_id(workspace_id)

    %{
      project_snapshots: %{
        used: StorageAccounting.project_snapshot_slot_usage(project_id),
        limit: Plan.limit(plan, :project_snapshots_per_project)
      },
      named_versions: %{
        used: count_named_versions(project_id),
        limit: Plan.limit(plan, :named_versions_per_project)
      }
    }
  end

  @doc """
  Returns all usage data relevant to a project settings limits page.

  Some limits are scoped to the project itself, while others are scoped to the
  containing workspace but directly affect project actions.
  """
  def project_limits_usage(%{id: _, workspace_id: _} = project) do
    consistent_usage_read(fn -> build_project_limits_usage(project) end)
  end

  defp build_project_limits_usage(project) do
    workspace = Repo.get!(Workspace, project.workspace_id)
    plan = Subscriptions.plan_for(workspace)
    storage_context = StorageAccounting.project_storage_context(project.id, workspace.id)
    workspace_storage = storage_context.workspace
    project_storage = storage_context.project

    %{
      plan: plan_summary(plan),
      project: %{
        items: usage_bucket(count_project_items(project.id), Plan.limit(plan, :items_per_project)),
        project_snapshots:
          usage_bucket(
            storage_context.snapshot_slots,
            Plan.limit(plan, :project_snapshots_per_project)
          ),
        named_versions:
          usage_bucket(
            count_named_versions(project.id),
            Plan.limit(plan, :named_versions_per_project)
          )
      },
      workspace: %{
        projects:
          usage_bucket(
            count_workspace_projects(workspace.id),
            Plan.limit(plan, :projects_per_workspace)
          ),
        project_templates:
          usage_bucket(
            count_workspace_project_templates(workspace.id),
            Plan.limit(plan, :project_templates_per_workspace)
          ),
        storage_bytes:
          usage_bucket(
            workspace_storage.accounted_bytes,
            Plan.limit(plan, :storage_bytes_per_workspace)
          )
      },
      item_breakdown: %{
        sheets: count_active(SheetRecord, project.id),
        flows: count_active(FlowRecord, project.id),
        scenes: count_active(SceneRecord, project.id),
        flow_nodes: count_nodes(project.id)
      },
      storage: %{
        project_bytes: project_storage.accounted_bytes,
        project_asset_bytes: project_storage.current_assets.bytes + project_storage.asset_trash.bytes,
        project_snapshot_bytes: project_storage.full_snapshots.bytes,
        project_reservation_bytes: project_storage.active_reservations.bytes,
        asset_count: project_storage.current_assets.count + project_storage.asset_trash.count,
        workspace: workspace_storage
      }
    }
  end

  defp consistent_usage_read(fun) do
    if Repo.in_transaction?() do
      fun.()
    else
      case Repo.repeatable_read(fun, timeout: :infinity) do
        # ============================================================================
        # Private count helpers
        # ============================================================================
        {:ok, usage} -> usage
        {:error, reason} -> raise "project limits usage read failed: #{inspect(reason)}"
      end
    end
  end

  @doc """
  Returns an account's plan with the seats and workspaces it uses, for its
  owner's Plan & billing page. These are totals across every workspace the
  account owns.
  """
  def account_usage(user_id) do
    plan = Subscriptions.plan_for_user(user_id)

    %{
      plan: plan_summary(plan),
      seats: EditorSeats.usage(user_id),
      workspaces: %{used: count_user_workspaces(user_id), limit: Plan.limit(plan, :workspaces_per_user)}
    }
  end

  @doc """
  Returns usage data for a workspace.
  """
  def usage(workspace) do
    plan = Subscriptions.plan_for(workspace)
    storage = StorageAccounting.workspace_usage(workspace.id)

    %{
      plan: plan,
      projects: %{
        used: count_workspace_projects(workspace.id),
        limit: Plan.limit(plan, :projects_per_workspace)
      },
      storage_bytes: %{
        used: storage.accounted_bytes,
        limit: Plan.limit(plan, :storage_bytes_per_workspace)
      },
      storage: storage
    }
  end

  defp plan_summary(plan) do
    %{
      key: plan,
      name: (Plan.get(plan) || %{})[:name] || plan
    }
  end

  defp usage_bucket(used, limit) do
    %{
      used: used || 0,
      limit: limit
    }
  end

  # The commercial named-version quota counts across every entity type in the
  # project; the three tool-owned copies count only their own entity type.
  defp count_named_versions(project_id) do
    Repo.aggregate(
      from(version in EntityVersionRecord,
        where: version.project_id == ^project_id and not is_nil(version.title) and version.is_auto == false
      ),
      :count
    )
  end

  defp check_limit(_resource, _used, :unlimited), do: :ok

  defp check_limit(resource, used, nil) do
    # Unknown plan/resource — default to blocking
    {:error, :limit_reached, %{resource: resource, used: used, limit: 0}}
  end

  defp check_limit(_resource, used, limit) when is_integer(limit) and used < limit, do: :ok

  defp check_limit(resource, used, limit) do
    {:error, :limit_reached, %{resource: resource, used: used, limit: limit}}
  end

  defp check_capacity(_resource, _used, :unlimited, _requested), do: :ok

  defp check_capacity(resource, used, nil, _requested) do
    {:error, :limit_reached, %{resource: resource, used: used, limit: 0}}
  end

  defp check_capacity(_resource, used, limit, requested) when is_integer(limit) and used + requested <= limit, do: :ok

  defp check_capacity(resource, used, limit, _requested) do
    {:error, :limit_reached, %{resource: resource, used: used, limit: limit}}
  end

  defp count_user_workspaces(user_id) do
    Repo.aggregate(from(w in Workspace, where: w.owner_id == ^user_id), :count)
  end

  defp count_workspace_projects(workspace_id) do
    Repo.aggregate(from(p in Project, where: p.workspace_id == ^workspace_id and is_nil(p.deleted_at)), :count)
  end

  defp count_active_workspace_imports(workspace_id) do
    Repo.aggregate(
      from(import in WorkspaceSnapshotImport,
        where: import.workspace_id == ^workspace_id and import.status in ^WorkspaceSnapshotImport.active_statuses()
      ),
      :count
    )
  end

  defp count_workspace_project_templates(workspace_id) do
    Repo.aggregate(
      from(template in ProjectTemplate,
        join: project in Project,
        on: project.id == template.source_project_id,
        where: project.workspace_id == ^workspace_id
      ),
      :count
    )
  end

  defp count_project_template_versions(template_id) do
    Repo.aggregate(
      from(version in ProjectTemplateVersion, where: version.project_template_id == ^template_id),
      :count
    )
  end

  defp plan_for_template(%{source_project_id: source_project_id}) when is_integer(source_project_id) do
    Project
    |> where([project], project.id == ^source_project_id)
    |> select([project], project.workspace_id)
    |> Repo.one()
    |> case do
      workspace_id when is_integer(workspace_id) -> Subscriptions.plan_for_workspace_id(workspace_id)
      nil -> nil
    end
  end

  defp plan_for_template(_template), do: nil

  @doc false
  def count_project_items(project_id) do
    count_nodes(project_id) +
      count_active(SheetRecord, project_id) +
      count_active(FlowRecord, project_id) +
      count_active(SceneRecord, project_id)
  end

  defp count_nodes(project_id) do
    Repo.aggregate(
      from(n in FlowNodeRecord,
        join: f in FlowRecord,
        on: n.flow_id == f.id,
        where: f.project_id == ^project_id and is_nil(n.deleted_at) and is_nil(f.deleted_at)
      ),
      :count
    )
  end

  defp count_active(schema, project_id) do
    Repo.aggregate(from(s in schema, where: s.project_id == ^project_id and is_nil(s.deleted_at)), :count)
  end
end
