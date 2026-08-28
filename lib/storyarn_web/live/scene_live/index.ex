defmodule StoryarnWeb.SceneLive.Index do
  @moduledoc """
  V2 Scenes dashboard — same logic as SceneLive.V1.Index, Vue + shadcn UI.
  """

  use StoryarnWeb, :live_view
  use StoryarnWeb.Live.Shared.DashboardHandlers

  import StoryarnWeb.Live.Shared.DashboardHelpers,
    only: [
      sort_table: 4,
      pagination: 2,
      handle_sort: 5,
      handle_page: 4,
      default_issue_filters: 0,
      default_issue_filter_options: 0,
      handle_issue_filter: 4,
      handle_issue_page: 3,
      put_issues: 3,
      put_stable_issue_ids: 3,
      fail_overview_load: 1,
      fail_issues_load: 1,
      put_pending_delete_id: 2
    ]

  alias Storyarn.Platform.Collaboration
  alias Storyarn.Platform.Dashboards.Cache, as: DashboardCache
  alias Storyarn.Platform.Shared.StringUtils
  alias Storyarn.Scenes
  alias StoryarnWeb.Helpers.Authorize
  alias StoryarnWeb.Live.Shared.DashboardHandlers
  alias StoryarnWeb.Live.Shared.ProjectChromeHelpers
  alias StoryarnWeb.Live.TreeSidebarActions
  alias StoryarnWeb.SceneLive.Helpers.SceneHelpers

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
      active_tool={:scenes}
      online_users={@online_users}
      sidebar_module={StoryarnWeb.SceneSidebarLive}
      sidebar_session={
        %{
          "project_id" => @project.id,
          "workspace_slug" => @workspace.slug,
          "project_slug" => @project.slug,
          "scene_id" => nil,
          "can_edit" => @can_edit,
          "active_tool" => "scenes",
          "dashboard_url" => ~p"/workspaces/#{@workspace.slug}/projects/#{@project.slug}/scenes",
          "current_scope" => @current_scope,
          "locale" => @locale
        }
      }
    >
      <.vue
        v-component="live/scene/dashboard/SceneDashboard"
        v-socket={@socket}
        v-inject="project-layout"
        id="scene-dashboard"
        class="contents"
        stats={@dashboard_stats}
        table-data={@scene_table_data}
        pagination={
          %{
            sortBy: @sort_by,
            sortDir: to_string(@sort_dir),
            page: @page,
            totalPages: @total_pages,
            total: @total_scenes
          }
        }
        issues={@scene_issues}
        overview-status={to_string(@overview_status)}
        issues-status={to_string(@issues_status)}
        issue-pagination={
          %{
            page: @issue_page,
            totalPages: @issue_total_pages,
            total: @issue_total,
            unfilteredTotal: @unfiltered_issue_total
          }
        }
        issue-filters={@issue_filters}
        issue-filter-options={@issue_filter_options}
        can-edit={@can_edit}
      />
    </StoryarnWeb.Components.ProjectLayout.project>
    """
  end

  # ===========================================================================
  # Mount & Lifecycle
  # ===========================================================================

  @impl true
  def mount(_params, _session, socket) do
    %{project: project} = socket.assigns

    if connected?(socket) do
      Collaboration.subscribe_dashboard(project.id)
      DashboardCache.subscribe_resets()

      Phoenix.PubSub.subscribe(
        Storyarn.PubSub,
        StoryarnWeb.SceneSidebarLive.shell_topic(project.id)
      )

      # Index is the scenes "dashboard" — clear any scene highlight the
      # sticky sidebar may have carried over from a previous Show visit so
      # the dashboard link looks active instead.
      Phoenix.PubSub.broadcast(
        Storyarn.PubSub,
        StoryarnWeb.SceneSidebarLive.shell_topic(project.id),
        {:active_scene, nil}
      )

      send(self(), :load_dashboard_data)
    end

    {:ok,
     socket
     |> assign(:online_users, ProjectChromeHelpers.initial_online_users(project.id))
     |> assign(:dashboard_stats, nil)
     |> assign(:overview_status, :loading)
     |> assign(:dashboard_overview_running?, false)
     |> assign(:dashboard_overview_reload_pending?, false)
     |> assign(:all_scene_table_data, [])
     |> assign(:scene_table_data, [])
     |> assign(:total_scenes, 0)
     |> assign(:all_scene_issues, [])
     |> assign(:scene_issues, [])
     |> assign(:issues_status, :loading)
     |> assign(:dashboard_issues_running?, false)
     |> assign(:dashboard_issues_reload_pending?, false)
     |> assign(:issue_filters, default_issue_filters())
     |> assign(:issue_filter_options, default_issue_filter_options())
     |> assign(:issue_page, 1)
     |> assign(:issue_total_pages, 1)
     |> assign(:issue_total, 0)
     |> assign(:unfiltered_issue_total, 0)
     |> assign(:sort_by, "name")
     |> assign(:sort_dir, :asc)
     |> assign(:page, 1)
     |> assign(:total_pages, 1)
     |> assign(:pending_delete_id, nil)}
  end

  @impl true
  def handle_params(_params, _url, socket), do: {:noreply, socket}

  # ===========================================================================
  # Shell topic messages
  # ===========================================================================

  def handle_info({:EXIT, _pid, :normal}, socket), do: {:noreply, socket}

  def handle_info({:open_scene, scene_id}, socket) do
    path =
      ~p"/workspaces/#{socket.assigns.workspace.slug}/projects/#{socket.assigns.project.slug}/scenes/#{scene_id}"

    {:noreply, push_navigate(socket, to: path)}
  end

  def handle_info({:active_scene, _scene_id}, socket), do: {:noreply, socket}
  def handle_info({:active_sheet, _sheet_id}, socket), do: {:noreply, socket}
  def handle_info({:active_flow, _flow_id}, socket), do: {:noreply, socket}
  def handle_info({:active_locale, _locale}, socket), do: {:noreply, socket}

  def handle_info({:tree_changed, :scenes}, socket) do
    {:noreply, DashboardHandlers.schedule_reload(socket)}
  end

  def handle_info({:entities_deleted, _type, _ids}, socket), do: {:noreply, socket}
  def handle_info({:toolbar_event, _event, _params}, socket), do: {:noreply, socket}
  def handle_info({:online_users, users}, socket), do: {:noreply, assign(socket, :online_users, users)}

  # ===========================================================================
  # Dashboard loading (async)
  # ===========================================================================

  def handle_info(:load_dashboard_data, socket) do
    {:noreply, socket |> start_dashboard_overview() |> start_dashboard_issues()}
  end

  def handle_info(:load_dashboard_overview, socket), do: {:noreply, start_dashboard_overview(socket)}
  def handle_info(:load_dashboard_issues, socket), do: {:noreply, start_dashboard_issues(socket)}

  @impl true
  def handle_async(:load_dashboard_overview, {:ok, data}, socket) do
    sorted_table =
      sort_table(
        data.table_data,
        socket.assigns.sort_by,
        socket.assigns.sort_dir,
        scene_sort_columns()
      )

    page = pagination(sorted_table, socket.assigns.page)

    socket =
      socket
      |> assign(:dashboard_stats, data.dashboard_stats)
      |> assign(:overview_status, :ready)
      |> assign(:all_scene_table_data, sorted_table)
      |> assign(:scene_table_data, page.rows)
      |> assign(:total_scenes, page.total)
      |> assign(:page, page.page)
      |> assign(:total_pages, page.total_pages)
      |> DashboardHandlers.finish_load(:overview, &start_dashboard_overview/1)

    {:noreply, socket}
  end

  def handle_async(:load_dashboard_issues, {:ok, issues}, socket) do
    socket =
      socket
      |> put_issues(issues, issue_assign_opts())
      |> assign(:issues_status, :ready)
      |> DashboardHandlers.finish_load(:issues, &start_dashboard_issues/1)

    {:noreply, socket}
  end

  def handle_async(:load_dashboard_overview, {:exit, reason}, socket) do
    Logger.error("Scene dashboard overview load failed for project #{socket.assigns.project.id}: #{inspect(reason)}")

    socket =
      socket
      |> assign(:overview_status, fail_overview_load(socket.assigns.overview_status))
      |> DashboardHandlers.finish_failed_load(:overview)

    {:noreply, socket}
  end

  def handle_async(:load_dashboard_issues, {:exit, reason}, socket) do
    Logger.error("Scene dashboard issues load failed for project #{socket.assigns.project.id}: #{inspect(reason)}")

    socket =
      socket
      |> assign(:issues_status, fail_issues_load(socket.assigns.issues_status))
      |> DashboardHandlers.finish_failed_load(:issues)

    {:noreply, socket}
  end

  defp load_dashboard_overview_async(project_id, workspace, project) do
    scenes = Scenes.list_scenes(project_id)

    stats =
      DashboardCache.fetch(project_id, :scene_stats, fn ->
        Scenes.scene_stats_for_project(project_id)
      end)

    bg_count =
      DashboardCache.fetch(project_id, :scene_bg, fn ->
        Scenes.scenes_with_background_count(project_id)
      end)

    table_data =
      Enum.map(scenes, fn scene ->
        scene_stats =
          Map.get(stats, scene.id, %{
            zone_count: 0,
            pin_count: 0,
            connection_count: 0
          })

        %{
          id: scene.id,
          name: scene.name,
          zone_count: scene_stats.zone_count,
          pin_count: scene_stats.pin_count,
          connection_count: scene_stats.connection_count,
          updated_at: scene.updated_at,
          href: ~p"/workspaces/#{workspace.slug}/projects/#{project.slug}/scenes/#{scene.id}"
        }
      end)

    %{
      dashboard_stats: %{
        scene_count: length(scenes),
        zone_count: table_data |> Enum.map(& &1.zone_count) |> Enum.sum(),
        pin_count: table_data |> Enum.map(& &1.pin_count) |> Enum.sum(),
        background_count: bg_count
      },
      table_data: table_data
    }
  end

  defp load_dashboard_issues_async(project_id, workspace, project) do
    project_id
    |> DashboardCache.fetch(:scene_health, fn ->
      Scenes.list_dashboard_health_findings(project_id)
    end)
    |> format_scene_issues(workspace, project)
  end

  # ===========================================================================
  # Events
  # ===========================================================================

  @impl true
  def handle_event("sort_scenes", %{"column" => column}, socket) do
    {:noreply,
     handle_sort(
       socket,
       column,
       :all_scene_table_data,
       :scene_table_data,
       scene_sort_columns()
     )}
  end

  def handle_event("page_scenes", %{"page" => page}, socket) do
    {:noreply, handle_page(socket, page, :all_scene_table_data, :scene_table_data)}
  end

  def handle_event("filter_scene_issues", %{"filter" => filter, "value" => value}, socket) do
    {:noreply, handle_issue_filter(socket, filter, value, issue_assign_opts())}
  end

  def handle_event("page_scene_issues", %{"page" => page}, socket) do
    {:noreply, handle_issue_page(socket, page, issue_assign_opts())}
  end

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

  def handle_event("set_pending_delete_scene", %{"id" => id}, socket) do
    {:noreply, put_pending_delete_id(socket, id)}
  end

  def handle_event("confirm_delete_scene", _params, socket) do
    Authorize.with_authorization(socket, :edit_content, &confirm_delete_scene/1)
  end

  def handle_event(event, _params, socket) do
    Logger.warning("[scenes dashboard] ignored unknown event #{inspect(event)}")
    {:noreply, socket}
  end

  # Other tree mutation events (create_scene, create_child_scene and
  # move_to_parent) live in the separately rendered SceneSidebarLive.

  # ===========================================================================
  # Private helpers
  # ===========================================================================

  defp confirm_delete_scene(socket) do
    TreeSidebarActions.confirm_delete(socket, %{
      get_entity: &Scenes.get_scene/2,
      delete_entity: &Scenes.delete_scene_subtree(socket.assigns.current_scope, &1),
      broadcast_deleted: &broadcast_entities_deleted/2,
      refresh_tree: &refresh_dashboard_and_tree/1,
      deleted_message: dgettext("scenes", "Scene moved to trash."),
      delete_error_message: dgettext("scenes", "Could not delete scene.")
    })
  end

  defp broadcast_entities_deleted(socket, ids) do
    Phoenix.PubSub.broadcast_from(
      Storyarn.PubSub,
      self(),
      StoryarnWeb.SceneSidebarLive.shell_topic(socket.assigns.project.id),
      {:entities_deleted, :scene, ids}
    )
  end

  defp refresh_dashboard_and_tree(socket) do
    Phoenix.PubSub.broadcast_from(
      Storyarn.PubSub,
      self(),
      StoryarnWeb.SceneSidebarLive.shell_topic(socket.assigns.project.id),
      {:tree_changed, :scenes}
    )

    DashboardHandlers.schedule_reload(socket)
  end

  defp start_dashboard_overview(socket) do
    %{project: project, workspace: workspace, locale: locale} = socket.assigns

    DashboardHandlers.start_load(socket, :overview, fn ->
      Gettext.put_locale(Storyarn.Gettext, locale)
      load_dashboard_overview_async(project.id, workspace, project)
    end)
  end

  defp start_dashboard_issues(socket) do
    %{project: project, workspace: workspace, locale: locale} = socket.assigns

    DashboardHandlers.start_load(socket, :issues, fn ->
      Gettext.put_locale(Storyarn.Gettext, locale)
      load_dashboard_issues_async(project.id, workspace, project)
    end)
  end

  defp issue_assign_opts do
    [
      all_key: :all_scene_issues,
      page_key: :scene_issues,
      filters_key: :issue_filters,
      options_key: :issue_filter_options,
      page_assign: :issue_page,
      total_pages_assign: :issue_total_pages,
      total_assign: :issue_total,
      unfiltered_total_assign: :unfiltered_issue_total
    ]
  end

  defp scene_sort_columns do
    %{
      "name" => &String.downcase(&1.name),
      "zone_count" => & &1.zone_count,
      "pin_count" => & &1.pin_count,
      "connection_count" => & &1.connection_count,
      "updated_at" => &(&1.updated_at || ~U[1970-01-01 00:00:00Z])
    }
  end

  defp format_scene_issues(issues, workspace, project) do
    issues
    |> Enum.map(fn issue ->
      resource_label = scene_label(issue)

      %{
        severity: Atom.to_string(issue.severity),
        code: Atom.to_string(issue.code),
        label: scene_health_label(issue),
        details: issue.details,
        scene_id: issue.scene_id,
        entity_type: issue.entity_type,
        entity_id: issue.entity_id,
        resource_id: issue.scene_id,
        resource_label: resource_label,
        href: scene_health_href(issue, workspace, project)
      }
    end)
    |> Enum.sort_by(
      &{
        Scenes.health_severity_rank(&1.severity),
        &1.label,
        &1.code,
        &1.scene_id,
        &1.entity_type,
        &1.entity_id || 0,
        :erlang.term_to_binary(&1.details, [:deterministic])
      }
    )
    |> put_stable_issue_ids("scene", fn issue ->
      {issue.scene_id, issue.code, issue.entity_type, issue.entity_id, issue.details}
    end)
  end

  defp scene_label(issue) do
    StringUtils.present_label(
      Map.get(issue.details, :scene_name),
      SceneHelpers.element_type_label("scene")
    )
  end

  # Location only — never a rendered sentence. The code carries the meaning and
  # Vue resolves it from `scenes.health.findings.*`, the same catalog the editor
  # popover uses, exactly as the sheets and flows dashboards do.
  #
  # The blank-name fallback matches `SceneLive.Helpers.HealthHelpers` so a scene
  # nobody named reads the same on both surfaces.
  defp scene_health_label(issue) do
    scene_name = scene_label(issue)

    case Map.get(issue.details, :entity_label) do
      label when is_binary(label) and label != "" -> "#{scene_name} · #{label}"
      _ -> scene_name
    end
  end

  defp scene_health_href(issue, workspace, project) do
    base = ~p"/workspaces/#{workspace.slug}/projects/#{project.slug}/scenes/#{issue.scene_id}"

    if issue.entity_type in ~w(pin zone connection annotation) and not is_nil(issue.entity_id) do
      "#{base}?highlight=#{issue.entity_type}:#{issue.entity_id}"
    else
      base
    end
  end
end
