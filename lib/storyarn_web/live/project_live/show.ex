defmodule StoryarnWeb.ProjectLive.Show do
  @moduledoc """
  Project dashboard — overview with stats, issues, speakers, and activity.
  """

  use StoryarnWeb, :live_view
  use StoryarnWeb.Live.Shared.DashboardHandlers

  import StoryarnWeb.Live.Shared.DashboardHelpers,
    only: [fail_overview_load: 1, fail_issues_load: 1]

  alias Storyarn.Collaboration
  alias Storyarn.Dashboards.Cache, as: DashboardCache
  alias Storyarn.Projects
  alias Storyarn.Scenes
  alias Storyarn.Sheets
  alias StoryarnWeb.Live.Shared.DashboardHandlers
  alias StoryarnWeb.Live.Shared.ProjectChromeHelpers

  require Logger

  @impl true
  def render(assigns) do
    ~H"""
    <StoryarnWeb.Components.ProjectLayout.project
      socket={@socket}
      flash={@flash}
      project={@project}
      workspace={@workspace}
      current_scope={@current_scope}
      current_user={@current_user}
      membership={@membership}
      urls={@urls}
      active_tool={:dashboard}
      online_users={@online_users}
      sidebar_module={StoryarnWeb.ProjectSidebarLive}
      sidebar_session={
        %{
          "workspace_slug" => @workspace.slug,
          "project_slug" => @project.slug,
          "active_item" => "dashboard",
          "locale" => @locale
        }
      }
    >
      <.vue
        v-component="live/project/dashboard/ProjectDashboard"
        v-socket={@socket}
        v-inject="project-layout"
        id="project-dashboard"
        class="contents"
        stats={@stats}
        activity={@activity}
        tool-health={@tool_health}
        overview-status={to_string(@overview_status)}
        issues-status={to_string(@issues_status)}
        can-edit={@can_manage}
        workspace-slug={@workspace.slug}
        project-slug={@project.slug}
      />
    </StoryarnWeb.Components.ProjectLayout.project>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    %{project: project, membership: membership} = socket.assigns
    can_manage = Projects.can?(membership.role, :manage_project)

    socket =
      socket
      |> assign(:page_title, project.name)
      |> assign(:can_manage, can_manage)
      |> assign(:stats, nil)
      |> assign(:activity, [])
      |> assign(:tool_health, nil)
      |> assign(:overview_status, :loading)
      |> assign(:dashboard_overview_running?, false)
      |> assign(:dashboard_overview_reload_pending?, false)
      |> assign(:issues_status, :loading)
      |> assign(:dashboard_issues_running?, false)
      |> assign(:dashboard_issues_reload_pending?, false)
      |> assign(:online_users, ProjectChromeHelpers.initial_online_users(project.id))

    if connected?(socket) do
      Phoenix.PubSub.subscribe(Storyarn.PubSub, ProjectChromeHelpers.shell_topic(project.id))
      Collaboration.subscribe_dashboard(project.id)
      DashboardCache.subscribe_resets()
      send(self(), :load_dashboard_data)
    end

    {:ok, socket}
  end

  @impl true
  def handle_params(_params, _url, socket), do: {:noreply, socket}

  @impl true
  def handle_info({:EXIT, _pid, :normal}, socket), do: {:noreply, socket}

  def handle_info({:online_users, users}, socket), do: {:noreply, assign(socket, :online_users, users)}

  def handle_info({:toolbar_event, _name, _params}, socket), do: {:noreply, socket}

  # Shell-topic sibling actives — LVs from other tools broadcast on the shared
  # project shell topic. Project dashboard ignores them all.
  def handle_info({:active_sheet, _sheet_id}, socket), do: {:noreply, socket}
  def handle_info({:active_flow, _flow_id}, socket), do: {:noreply, socket}
  def handle_info({:active_scene, _scene_id}, socket), do: {:noreply, socket}
  def handle_info({:active_locale, _locale}, socket), do: {:noreply, socket}

  def handle_info(:load_dashboard_data, socket) do
    {:noreply, socket |> start_dashboard_overview() |> start_dashboard_issues()}
  end

  def handle_info(:load_dashboard_overview, socket), do: {:noreply, start_dashboard_overview(socket)}
  def handle_info(:load_dashboard_issues, socket), do: {:noreply, start_dashboard_issues(socket)}

  # ===========================================================================
  # Dashboard loading (async)
  # ===========================================================================

  @impl true
  def handle_async(:load_dashboard_overview, {:ok, data}, socket) do
    {:noreply,
     socket
     |> assign(:stats, data.stats)
     |> assign(:activity, data.activity)
     |> assign(:overview_status, :ready)
     |> DashboardHandlers.finish_load(:overview, &start_dashboard_overview/1)}
  end

  def handle_async(:load_dashboard_issues, {:ok, tool_health}, socket) do
    {:noreply,
     socket
     |> assign(:tool_health, tool_health)
     |> assign(:issues_status, :ready)
     |> DashboardHandlers.finish_load(:issues, &start_dashboard_issues/1)}
  end

  def handle_async(:load_dashboard_overview, {:exit, reason}, socket) do
    Logger.error("Project dashboard overview load failed for project #{socket.assigns.project.id}: #{inspect(reason)}")

    {:noreply,
     socket
     |> assign(:overview_status, fail_overview_load(socket.assigns.overview_status))
     |> DashboardHandlers.finish_failed_load(:overview)}
  end

  def handle_async(:load_dashboard_issues, {:exit, reason}, socket) do
    Logger.error("Project dashboard health load failed for project #{socket.assigns.project.id}: #{inspect(reason)}")

    {:noreply,
     socket
     |> assign(:issues_status, fail_issues_load(socket.assigns.issues_status))
     |> DashboardHandlers.finish_failed_load(:issues)}
  end

  # ===========================================================================
  # Events
  # ===========================================================================

  @impl true
  def handle_event("retry_dashboard_overview", _params, %{assigns: %{overview_status: status}} = socket)
      when status in [:error, :stale] do
    {:noreply, DashboardHandlers.retry_load(socket, :overview, &start_dashboard_overview/1)}
  end

  def handle_event("retry_dashboard_overview", _params, socket), do: {:noreply, socket}

  def handle_event("retry_dashboard_issues", _params, %{assigns: %{issues_status: status}} = socket)
      when status in [:error, :stale] do
    {:noreply, DashboardHandlers.retry_load(socket, :issues, &start_dashboard_issues/1)}
  end

  def handle_event("retry_dashboard_issues", _params, socket), do: {:noreply, socket}

  def handle_event(event, _params, socket) do
    Logger.warning("[project dashboard] ignored unknown event #{inspect(event)}")
    {:noreply, socket}
  end

  # ===========================================================================
  # Async loaders
  # ===========================================================================

  # The two loads are independent on purpose. The health sweeps are by far the
  # most expensive thing this page does; keeping them off the overview means the
  # stats and activity render immediately instead of waiting on all three
  # checkers, and a health failure degrades one card row instead of the page.
  defp start_dashboard_overview(socket) do
    project_id = socket.assigns.project.id

    DashboardHandlers.start_load(socket, :overview, fn ->
      %{
        stats:
          DashboardCache.fetch(project_id, :project_stats, fn ->
            Projects.project_stats(project_id)
          end),
        activity:
          project_id
          |> DashboardCache.fetch(:recent_activity, fn -> Projects.recent_activity(project_id) end)
          |> format_activity()
      }
    end)
  end

  # Deliberately the SAME cache keys the three tool dashboards use, so the
  # overview warms the entries they read and vice versa instead of paying for
  # the most expensive sweeps in the product a second time under private keys.
  # `:sheet_refs` has to be resolved first: the sheets checker needs the
  # project-wide reference set to judge which variables are unused, and getting
  # that wrong under-reports silently rather than crashing.
  #
  # No `Gettext.put_locale` here, unlike the tool dashboards: the result is
  # counts, so there is nothing to translate and nothing that could leak one
  # reader's locale to the next through the shared cache.
  defp start_dashboard_issues(socket) do
    project_id = socket.assigns.project.id

    DashboardHandlers.start_load(socket, :issues, fn ->
      referenced_ids =
        DashboardCache.fetch(project_id, :sheet_refs, fn ->
          Sheets.referenced_block_ids_for_project(project_id)
        end)

      Projects.tool_health_summary(%{
        flows:
          DashboardCache.fetch(project_id, :flow_issues, fn ->
            Projects.list_flow_dashboard_health_findings(project_id)
          end),
        sheets:
          DashboardCache.fetch(project_id, :sheet_issues, fn ->
            Sheets.list_dashboard_health_findings(project_id, referenced_ids)
          end),
        scenes:
          DashboardCache.fetch(project_id, :scene_health, fn ->
            Scenes.list_dashboard_health_findings(project_id)
          end)
      })
    end)
  end

  # ===========================================================================
  # Formatters (serialize for Vue)
  # ===========================================================================

  defp format_activity(activity) when is_list(activity) do
    Enum.map(activity, fn item ->
      %{
        name: item.name,
        type: item.type,
        updated_at: item.updated_at && DateTime.to_iso8601(item.updated_at)
      }
    end)
  end

  defp format_activity(_), do: []
end
