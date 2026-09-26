defmodule StoryarnWeb.ProjectSettingsLive.UsageLimits do
  @moduledoc false

  use StoryarnWeb, :live_view

  import StoryarnWeb.ProjectLive.Components.SettingsComponents, only: [serialize_count_limit: 1]

  alias Storyarn.Commercial
  alias Storyarn.Projects
  alias StoryarnWeb.Live.Shared.UsageAccess

  # ===========================================================================
  # Render
  # ===========================================================================

  @impl true
  def render(assigns) do
    ~H"""
    <StoryarnWeb.Components.SettingsLayout.settings
      flash={@flash}
      socket={@socket}
      current_scope={@current_scope}
      current_path={@current_path}
      settings_nav={@settings_nav}
    >
      <.vue
        v-component="live/project/settings/ProjectSettingsUsageLimits"
        v-socket={@socket}
        v-inject="settings-layout"
        id="project-settings-usage-limits"
        usage-limits={serialize_usage_limits(@usage_limits)}
        workspace-usage-path={@workspace_usage_path}
        plan-path={@plan_path}
      />
    </StoryarnWeb.Components.SettingsLayout.settings>
    """
  end

  # ===========================================================================
  # Serialization helpers
  # ===========================================================================

  # A project owner may only be a member of this project, so the page gets the
  # project's own counters and nothing about the workspace: its totals are for
  # the workspace's owner, admins and members, on Workspace › Usage.
  defp serialize_usage_limits(usage) do
    %{
      project: %{
        items: serialize_bucket(usage.project.items),
        projectSnapshots: serialize_bucket(usage.project.project_snapshots),
        namedVersions: serialize_bucket(usage.project.named_versions)
      },
      itemBreakdown: %{
        sheets: usage.item_breakdown.sheets,
        flows: usage.item_breakdown.flows,
        scenes: usage.item_breakdown.scenes,
        flowNodes: usage.item_breakdown.flow_nodes
      }
    }
  end

  defp serialize_bucket(bucket) do
    %{
      used: bucket.used,
      limit: serialize_count_limit(bucket.limit)
    }
  end

  # ===========================================================================
  # Mount & handle_params
  # ===========================================================================

  @impl true
  def mount(_params, _session, socket) do
    stale_project = socket.assigns.project

    if connected?(socket) do
      :ok = Projects.subscribe_project_ownership_changes(stale_project.id)
    end

    case reload_project_owner(socket, stale_project.id) do
      {:ok, project, membership} ->
        socket =
          socket
          |> assign(:project, project)
          |> assign(:membership, membership)
          |> assign(:current_workspace, project.workspace)
          |> assign(:usage_limits, Commercial.project_limits_usage(project))
          |> assign_usage_links(project)

        {:ok, socket}

      _lost_access ->
        mount_access_denied(socket, stale_project)
    end
  end

  @impl true
  def handle_params(_params, url, socket) do
    current_path = URI.parse(url).path

    socket =
      socket
      |> assign(:page_title, dgettext("projects", "Project Settings"))
      |> assign(:current_path, current_path)

    {:noreply, socket}
  end

  @impl true
  def handle_info(
        {:project_ownership_transferred, %{project_id: project_id}},
        %{assigns: %{project: %{id: project_id}}} = socket
      ) do
    with {:ok, project, membership} <-
           Projects.reload_project(socket.assigns.current_scope, project_id),
         true <- project.owner_id == socket.assigns.current_scope.user.id,
         true <- Projects.can?(membership.role, :manage_project) do
      {:noreply,
       socket
       |> assign(:project, project)
       |> assign(:membership, membership)
       |> assign(:current_workspace, project.workspace)
       |> assign(:usage_limits, Commercial.project_limits_usage(project))
       |> assign_usage_links(project)}
    else
      _lost_access ->
        project = socket.assigns.project

        {:noreply,
         socket
         |> put_flash(
           :error,
           dgettext("projects", "You don't have permission to manage this project.")
         )
         |> push_navigate(to: ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}")}
    end
  end

  defp assign_usage_links(socket, project) do
    scope = socket.assigns.current_scope

    socket
    |> assign(:workspace_usage_path, UsageAccess.workspace_usage_path(scope, project.workspace))
    |> assign(:plan_path, UsageAccess.plan_path(scope, project.workspace))
  end

  defp reload_project_owner(socket, project_id) do
    with {:ok, project, membership} <-
           Projects.reload_project(socket.assigns.current_scope, project_id),
         true <- project.owner_id == socket.assigns.current_scope.user.id,
         true <- Projects.can?(membership.role, :manage_project) do
      {:ok, project, membership}
    else
      _lost_access -> {:error, :unauthorized}
    end
  end

  defp mount_access_denied(socket, project) do
    {:ok,
     socket
     |> put_flash(
       :error,
       dgettext("projects", "You don't have permission to manage this project.")
     )
     |> redirect(to: ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}")}
  end
end
