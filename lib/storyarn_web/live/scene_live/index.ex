defmodule StoryarnWeb.SceneLive.Index do
  @moduledoc """
  V2 Scenes dashboard — same logic as SceneLive.V1.Index, Vue + shadcn UI.
  """

  use StoryarnWeb, :live_view
  use StoryarnWeb.Live.Shared.DashboardHandlers

  import StoryarnWeb.Components.DashboardComponents,
    only: [
      sort_table: 4,
      paginate: 2,
      handle_sort: 5,
      handle_page: 4,
      reload_dashboard: 6
    ]

  alias Storyarn.Collaboration
  alias Storyarn.Dashboards.Cache, as: DashboardCache
  alias Storyarn.Scenes
  alias StoryarnWeb.Live.Shared.ProjectChromeHelpers

  @impl true
  def render(assigns) do
    ~H"""
    <StoryarnWeb.Components.ProjectShell.project_shell
      socket={@socket}
      project={@project}
      workspace={@workspace}
      current_scope={@current_scope}
      current_user={@current_user}
      urls={@urls}
      active_tool={:scenes}
      is_super_admin={@is_super_admin}
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
        v-component="modules/scenes/SceneDashboard"
        v-socket={@socket}
        id="scene-dashboard"
        stats={@dashboard_stats}
        table-data={@scene_table_data}
        pagination={
          %{
            sortBy: @sort_by,
            sortDir: to_string(@sort_dir),
            page: @page,
            totalPages: @total_pages,
            total: length(@all_scene_table_data)
          }
        }
        issues={@scene_issues}
        can-edit={@can_edit}
        workspace-slug={@workspace.slug}
        project-slug={@project.slug}
      />
    </StoryarnWeb.Components.ProjectShell.project_shell>
    """
  end

  # ===========================================================================
  # Mount & Lifecycle
  # ===========================================================================

  @impl true
  def mount(_params, _session, socket) do
    %{project: project} = socket.assigns
    scenes = Scenes.list_scenes(project.id)

    if connected?(socket) do
      Collaboration.subscribe_dashboard(project.id)

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

      if scenes != [], do: send(self(), :load_dashboard_data)
    end

    {:ok,
     socket
     |> assign(:online_users, ProjectChromeHelpers.initial_online_users(project.id))
     |> assign(:scenes, scenes)
     |> assign(:dashboard_stats, nil)
     |> assign(:all_scene_table_data, [])
     |> assign(:scene_table_data, [])
     |> assign(:scene_issues, [])
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

  def handle_info({:open_scene, scene_id}, socket) do
    path =
      ~p"/workspaces/#{socket.assigns.workspace.slug}/projects/#{socket.assigns.project.slug}/scenes/#{scene_id}"

    {:noreply, push_navigate(socket, to: path)}
  end

  def handle_info({:active_scene, _scene_id}, socket), do: {:noreply, socket}
  def handle_info({:tree_changed, :scenes}, socket), do: {:noreply, reload_scenes(socket)}
  def handle_info({:toolbar_event, _event, _params}, socket), do: {:noreply, socket}
  def handle_info({:online_users, users}, socket), do: {:noreply, assign(socket, :online_users, users)}

  # ===========================================================================
  # Dashboard loading (async)
  # ===========================================================================

  def handle_info(:load_dashboard_data, socket) do
    %{project: project, workspace: workspace, sort_by: sort_by, sort_dir: sort_dir} =
      socket.assigns

    {:noreply,
     start_async(socket, :load_dashboard_data, fn ->
       load_dashboard_data_async(project.id, workspace, project, sort_by, sort_dir)
     end)}
  end

  @impl true
  def handle_async(:load_dashboard_data, {:ok, data}, socket) do
    {:noreply,
     socket
     |> assign(:dashboard_stats, data.dashboard_stats)
     |> assign(:all_scene_table_data, data.sorted_table)
     |> assign(:scene_table_data, data.page_rows)
     |> assign(:page, 1)
     |> assign(:total_pages, data.total_pages)
     |> assign(:scene_issues, data.formatted_issues)}
  end

  def handle_async(:load_dashboard_data, {:exit, _reason}, socket), do: {:noreply, socket}

  defp load_dashboard_data_async(project_id, workspace, project, sort_by, sort_dir) do
    scenes = Scenes.list_scenes(project_id)

    stats =
      DashboardCache.fetch(project_id, :scene_stats, fn ->
        Scenes.scene_stats_for_project(project_id)
      end)

    bg_count =
      DashboardCache.fetch(project_id, :scene_bg, fn ->
        Scenes.scenes_with_background_count(project_id)
      end)

    issues =
      DashboardCache.fetch(project_id, :scene_issues, fn ->
        Scenes.detect_scene_issues(project_id)
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
          updated_at: scene.updated_at
        }
      end)

    sorted_table = sort_table(table_data, sort_by, sort_dir, scene_sort_columns())
    {page_rows, total_pages} = paginate(sorted_table, 1)

    %{
      dashboard_stats: %{
        scene_count: length(scenes),
        zone_count: table_data |> Enum.map(& &1.zone_count) |> Enum.sum(),
        pin_count: table_data |> Enum.map(& &1.pin_count) |> Enum.sum(),
        background_count: bg_count
      },
      sorted_table: sorted_table,
      page_rows: page_rows,
      total_pages: total_pages,
      formatted_issues: format_scene_issues(issues, workspace, project)
    }
  end

  # ===========================================================================
  # Events
  # ===========================================================================

  @impl true
  def handle_event("tree_panel_" <> _ = event, params, socket),
    do: ProjectChromeHelpers.forward_tree_panel(socket, event, params)

  def handle_event("sort_scenes", %{"column" => column}, socket) do
    {:noreply, handle_sort(socket, column, :all_scene_table_data, :scene_table_data, scene_sort_columns())}
  end

  def handle_event("page_scenes", %{"page" => page}, socket) do
    {:noreply, handle_page(socket, page, :all_scene_table_data, :scene_table_data)}
  end

  # Tree mutation events (create_scene, create_child_scene, move_to_parent,
  # set_pending_delete, confirm_delete, delete) now live in SceneSidebarLive —
  # they never reach this LV because the tree is rendered by SceneSidebarLive
  # which is a separate nested LV.

  # ===========================================================================
  # Private helpers
  # ===========================================================================

  defp reload_scenes(socket) do
    project_id = socket.assigns.project.id

    reload_dashboard(
      socket,
      :scenes,
      :all_scene_table_data,
      :scene_table_data,
      :scene_issues,
      fn s -> assign(s, :scenes, Scenes.list_scenes(project_id)) end
    )
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
    Enum.map(issues, fn issue ->
      {severity, message} =
        case issue.issue_type do
          :empty_scene ->
            {:info, dgettext("scenes", "Scene \"%{name}\" has no zones or pins", name: issue.scene_name)}

          :no_background ->
            {:warning, dgettext("scenes", "Scene \"%{name}\" has no background image", name: issue.scene_name)}

          :missing_shortcut ->
            {:warning, dgettext("scenes", "Scene \"%{name}\" has no shortcut", name: issue.scene_name)}

          _ ->
            {:info, dgettext("scenes", "Issue detected")}
        end

      %{
        severity: to_string(severity),
        message: message,
        href: ~p"/workspaces/#{workspace.slug}/projects/#{project.slug}/scenes/#{issue.scene_id}"
      }
    end)
  end
end
