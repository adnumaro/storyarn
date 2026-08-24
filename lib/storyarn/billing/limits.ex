defmodule Storyarn.Billing.Limits do
  @moduledoc """
  Limit checks for billing plans. Each function queries current usage
  and compares against the plan limit.
  """

  import Ecto.Query, warn: false

  alias Storyarn.Billing.Persistence.EntityVersionRecord
  alias Storyarn.Billing.Persistence.FlowNodeRecord
  alias Storyarn.Billing.Persistence.FlowRecord
  alias Storyarn.Billing.Persistence.SceneRecord
  alias Storyarn.Billing.Persistence.SheetRecord
  alias Storyarn.Billing.Persistence.WorkspaceInvitationRecord, as: WorkspaceInvitation
  alias Storyarn.Billing.Persistence.WorkspaceMembershipRecord, as: WorkspaceMembership
  alias Storyarn.Billing.Persistence.WorkspaceRecord, as: Workspace
  alias Storyarn.Billing.Plan
  alias Storyarn.Billing.StorageAccounting
  alias Storyarn.Billing.SubscriptionCrud
  alias Storyarn.Projects.Project
  alias Storyarn.Projects.ProjectInvitation
  alias Storyarn.Projects.ProjectMembership
  alias Storyarn.ProjectTemplates.ProjectTemplate
  alias Storyarn.ProjectTemplates.ProjectTemplateVersion
  alias Storyarn.Repo
  alias Storyarn.Shared.TimeHelpers
  alias Storyarn.Versioning.WorkspaceSnapshotImport

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
    used = count_workspace_projects(workspace.id) + count_active_workspace_imports(workspace.id)
    check_limit(:projects_per_workspace, used, limit)
  end

  @doc false
  def can_publish_reserved_project?(workspace) do
    plan = SubscriptionCrud.plan_for(workspace)

    check_limit(
      :projects_per_workspace,
      count_workspace_projects(workspace.id),
      Plan.limit(plan, :projects_per_workspace)
    )
  end

  @doc """
  Checks if a source project's workspace can publish another project template.
  """
  def can_create_project_template?(%Project{} = source_project) do
    plan = SubscriptionCrud.plan_for_workspace_id(source_project.workspace_id)
    limit = Plan.limit(plan, :project_templates_per_workspace)
    used = count_workspace_project_templates(source_project.workspace_id)
    check_limit(:project_templates_per_workspace, used, limit)
  end

  @doc """
  Checks if a template can publish another immutable version.
  """
  def can_create_project_template_version?(%ProjectTemplate{} = template) do
    plan = plan_for_template(template)
    limit = Plan.limit(plan, :project_template_versions_per_template)
    used = count_project_template_versions(template.id)
    check_limit(:project_template_versions_per_template, used, limit)
  end

  @doc """
  Checks if a workspace can have another member (via workspace or project invitation).

  Accepts either a workspace or a project struct — for projects, resolves
  the workspace_id to check workspace-level member limits.
  """
  def can_invite_member?(%{id: _} = workspace) when not is_struct(workspace, Project) do
    check_member_limit(workspace.id)
  end

  def can_invite_member?(%Project{} = project) do
    check_member_limit(project.workspace_id)
  end

  @doc """
  Checks whether inviting an email would consume another workspace member slot.

  Emails that already occupy a slot through a membership or active invitation
  may be invited to another project without consuming additional capacity.
  """
  def can_invite_member?(%{id: _} = workspace, email) when not is_struct(workspace, Project) and is_binary(email) do
    check_member_limit(workspace.id, email)
  end

  def can_invite_member?(%Project{} = project, email) when is_binary(email) do
    check_member_limit(project.workspace_id, email)
  end

  @doc """
  Checks whether an invitation can be converted into a membership.

  Unlike `can_invite_member?/2`, this only counts existing memberships. The
  invitation being accepted already reserves its candidate's slot, while this
  check protects legacy or externally-created invitations from exceeding the
  plan when they are accepted.
  """
  def can_accept_member?(%{id: _} = workspace, email) when not is_struct(workspace, Project) and is_binary(email) do
    check_membership_limit(workspace.id, email)
  end

  def can_accept_member?(%Project{} = project, email) when is_binary(email) do
    check_membership_limit(project.workspace_id, email)
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
    plan = SubscriptionCrud.plan_for_workspace_id(workspace_id)
    limit = Plan.limit(plan, :items_per_project)
    used = count_project_items(project.id)
    check_capacity(:items_per_project, used, limit, count)
  end

  @doc """
  Checks if a project can have another named version.
  """
  def can_create_named_version?(project_id, workspace_id) do
    plan = SubscriptionCrud.plan_for_workspace_id(workspace_id)
    limit = Plan.limit(plan, :named_versions_per_project)
    used = count_named_versions(project_id)
    check_limit(:named_versions_per_project, used, limit)
  end

  @doc """
  Returns version control usage data for a project.
  """
  def project_usage(project_id, workspace_id) do
    plan = SubscriptionCrud.plan_for_workspace_id(workspace_id)

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
  def project_limits_usage(%Project{} = project) do
    consistent_usage_read(fn -> build_project_limits_usage(project) end)
  end

  defp build_project_limits_usage(project) do
    workspace = Repo.get!(Workspace, project.workspace_id)
    plan = SubscriptionCrud.plan_for(workspace)
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
        members:
          usage_bucket(
            count_occupied_workspace_member_slots(workspace.id),
            Plan.limit(plan, :members_per_workspace)
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
        {:ok, usage} -> usage
        {:error, reason} -> raise "project limits usage read failed: #{inspect(reason)}"
      end
    end
  end

  @doc """
  Returns usage data for a workspace.
  """
  def usage(workspace) do
    plan = SubscriptionCrud.plan_for(workspace)
    storage = StorageAccounting.workspace_usage(workspace.id)

    %{
      plan: plan,
      projects: %{
        used: count_workspace_projects(workspace.id),
        limit: Plan.limit(plan, :projects_per_workspace)
      },
      members: %{
        used: count_occupied_workspace_member_slots(workspace.id),
        limit: Plan.limit(plan, :members_per_workspace)
      },
      storage_bytes: %{
        used: storage.accounted_bytes,
        limit: Plan.limit(plan, :storage_bytes_per_workspace)
      },
      storage: storage
    }
  end

  # ============================================================================
  # Private count helpers
  # ============================================================================

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

  defp check_limit(resource, used, nil) do
    # Unknown plan/resource — default to blocking
    {:error, :limit_reached, %{resource: resource, used: used, limit: 0}}
  end

  defp check_limit(_resource, used, limit) when used < limit, do: :ok

  defp check_limit(resource, used, limit) do
    {:error, :limit_reached, %{resource: resource, used: used, limit: limit}}
  end

  defp check_capacity(resource, used, nil, _requested) do
    {:error, :limit_reached, %{resource: resource, used: used, limit: 0}}
  end

  defp check_capacity(_resource, used, limit, requested) when used + requested <= limit, do: :ok

  defp check_capacity(resource, used, limit, _requested) do
    {:error, :limit_reached, %{resource: resource, used: used, limit: limit}}
  end

  defp check_member_limit(workspace_id) do
    plan = SubscriptionCrud.plan_for_workspace_id(workspace_id)
    limit = Plan.limit(plan, :members_per_workspace)
    used = count_occupied_workspace_member_slots(workspace_id)
    check_limit(:members_per_workspace, used, limit)
  end

  defp check_member_limit(workspace_id, email) do
    normalized_email = email |> String.trim() |> String.downcase()

    if workspace_member_slot_occupied?(workspace_id, normalized_email) do
      :ok
    else
      check_member_limit(workspace_id)
    end
  end

  defp check_membership_limit(workspace_id, email) do
    normalized_email = email |> String.trim() |> String.downcase()

    if workspace_membership_slot_occupied?(workspace_id, normalized_email) do
      :ok
    else
      plan = SubscriptionCrud.plan_for_workspace_id(workspace_id)
      limit = Plan.limit(plan, :members_per_workspace)
      used = count_workspace_membership_slots(workspace_id)
      check_limit(:members_per_workspace, used, limit)
    end
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

  defp plan_for_template(%ProjectTemplate{source_project_id: source_project_id}) when is_integer(source_project_id) do
    Project
    |> where([project], project.id == ^source_project_id)
    |> select([project], project.workspace_id)
    |> Repo.one()
    |> case do
      workspace_id when is_integer(workspace_id) -> SubscriptionCrud.plan_for_workspace_id(workspace_id)
      nil -> nil
    end
  end

  defp plan_for_template(_template), do: nil

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
        where: p.workspace_id == ^workspace_id and is_nil(p.deleted_at),
        select: pm.user_id
      )

    union_query = union(wm_query, ^pm_query)

    Repo.one(from(u in subquery(union_query), select: count(u.user_id)))
  end

  defp count_occupied_workspace_member_slots(workspace_id) do
    occupied_slots = occupied_workspace_member_slots_query(workspace_id)

    Repo.one(from(slot in subquery(occupied_slots), select: count(slot.email)))
  end

  defp count_workspace_membership_slots(workspace_id) do
    membership_slots = workspace_membership_slots_query(workspace_id)

    Repo.one(from(slot in subquery(membership_slots), select: count(slot.email)))
  end

  defp workspace_member_slot_occupied?(workspace_id, email) do
    occupied_slots = occupied_workspace_member_slots_query(workspace_id)

    Repo.exists?(from(slot in subquery(occupied_slots), where: slot.email == ^email))
  end

  defp workspace_membership_slot_occupied?(workspace_id, email) do
    membership_slots = workspace_membership_slots_query(workspace_id)

    Repo.exists?(from(slot in subquery(membership_slots), where: slot.email == ^email))
  end

  defp workspace_membership_slots_query(workspace_id) do
    workspace_members =
      from(m in WorkspaceMembership,
        join: user in assoc(m, :user),
        where: m.workspace_id == ^workspace_id,
        select: %{email: fragment("lower(?)", user.email)}
      )

    project_members =
      from(m in ProjectMembership,
        join: project in Project,
        on: m.project_id == project.id,
        join: user in assoc(m, :user),
        where: project.workspace_id == ^workspace_id and is_nil(project.deleted_at),
        select: %{email: fragment("lower(?)", user.email)}
      )

    union(workspace_members, ^project_members)
  end

  defp occupied_workspace_member_slots_query(workspace_id) do
    now = TimeHelpers.now()

    workspace_invitations =
      from(invitation in WorkspaceInvitation,
        where: invitation.workspace_id == ^workspace_id,
        where: is_nil(invitation.accepted_at),
        where: invitation.expires_at > ^now,
        select: %{email: fragment("lower(?)", invitation.email)}
      )

    project_invitations =
      from(invitation in ProjectInvitation,
        join: project in Project,
        on: invitation.project_id == project.id,
        where: project.workspace_id == ^workspace_id and is_nil(project.deleted_at),
        where: is_nil(invitation.accepted_at),
        where: invitation.expires_at > ^now,
        select: %{email: fragment("lower(?)", invitation.email)}
      )

    workspace_id
    |> workspace_membership_slots_query()
    |> union(^workspace_invitations)
    |> union(^project_invitations)
  end

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
