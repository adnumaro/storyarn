defmodule StoryarnWeb.SceneLive.Index do
  @moduledoc """
  V2 Scenes dashboard — same logic as SceneLive.V1.Index, Vue + shadcn UI.
  """

  use StoryarnWeb, :live_view
  alias StoryarnWeb.Helpers.Authorize

  import StoryarnWeb.Live.Shared.TreePanelHandlers

  import StoryarnWeb.Components.DashboardComponents,
    only: [
      sort_table: 4,
      paginate: 2,
      handle_sort: 5,
      handle_page: 4,
      reload_dashboard: 6
    ]

  use StoryarnWeb.Live.Shared.DashboardHandlers

  alias Storyarn.Collaboration
  alias Storyarn.Dashboards.Cache, as: DashboardCache
  alias Storyarn.Projects
  alias Storyarn.Scenes
  alias Storyarn.Shared.MapUtils

  import StoryarnWeb.SceneLive.Helpers.PropsSerializer, only: [prepare_scenes_tree: 1]

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app
      flash={@flash}
      socket={@socket}
      current_scope={@current_scope}
      project={@project}
      workspace={@workspace}
      active_tool={:scenes}
      on_dashboard={true}
      has_tree={true}
      tree_panel_open={@tree_panel_open}
      tree_panel_pinned={@tree_panel_pinned}
      show_pin={false}
      can_edit={@can_edit}
      tree_props={
        %{
          scenesTree: @scenes_tree,
          canEdit: @can_edit,
          workspaceSlug: @workspace.slug,
          projectSlug: @project.slug,
          hasLayers: false
        }
      }
    >
      <.vue
        v-component="pages/workspaces/projects/scenes/index"
        v-socket={@socket}
        id="scene-dashboard"
        stats={@dashboard_stats}
        table-data={@scene_table_data}
        pagination={%{
          sortBy: @sort_by,
          sortDir: to_string(@sort_dir),
          page: @page,
          totalPages: @total_pages,
          total: length(@all_scene_table_data)
        }}
        issues={@scene_issues}
        can-edit={@can_edit}
        workspace-slug={@workspace.slug}
        project-slug={@project.slug}
      />
    </Layouts.app>
    """
  end

  # ===========================================================================
  # Mount & Lifecycle
  # ===========================================================================

  @impl true
  def mount(
        %{"workspace_slug" => workspace_slug, "project_slug" => project_slug},
        _session,
        socket
      ) do
    case Projects.get_project_by_slugs(
           socket.assigns.current_scope,
           workspace_slug,
           project_slug
         ) do
      {:ok, project, membership} ->
        scenes = Scenes.list_scenes(project.id)
        can_edit = Projects.can?(membership.role, :edit_content)

        socket =
          socket
          |> assign(focus_layout_defaults())
          |> assign(:tree_panel_open, true)
          |> assign(:project, project)
          |> assign(:workspace, project.workspace)
          |> assign(:membership, membership)
          |> assign(:can_edit, can_edit)
          |> assign(:scenes_tree, prepare_scenes_tree(Scenes.list_scenes_tree(project.id)))
          |> assign(:scenes, scenes)
          |> assign(:dashboard_stats, nil)
          |> assign(:all_scene_table_data, [])
          |> assign(:scene_table_data, [])
          |> assign(:scene_issues, [])
          |> assign(:sort_by, "name")
          |> assign(:sort_dir, :asc)
          |> assign(:page, 1)
          |> assign(:total_pages, 1)
          |> assign(:pending_delete_id, nil)

        if connected?(socket), do: Collaboration.subscribe_dashboard(project.id)
        if connected?(socket) and scenes != [], do: send(self(), :load_dashboard_data)

        {:ok, socket}

      {:error, _reason} ->
        {:ok,
         socket
         |> put_flash(:error, dgettext("scenes", "You don't have access to this project."))
         |> redirect(to: ~p"/workspaces")}
    end
  end

  @impl true
  def handle_params(_params, _url, socket), do: {:noreply, socket}

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
    do: handle_tree_panel_event(event, params, socket)

  def handle_event("sort_scenes", %{"column" => column}, socket) do
    {:noreply,
     handle_sort(socket, column, :all_scene_table_data, :scene_table_data, scene_sort_columns())}
  end

  def handle_event("page_scenes", %{"page" => page}, socket) do
    {:noreply, handle_page(socket, page, :all_scene_table_data, :scene_table_data)}
  end

  def handle_event(event, %{"id" => id}, socket)
      when event in ~w(set_pending_delete set_pending_delete_scene) do
    {:noreply, assign(socket, :pending_delete_id, id)}
  end

  def handle_event(event, _params, socket)
      when event in ~w(confirm_delete confirm_delete_scene) do
    if id = socket.assigns[:pending_delete_id] do
      handle_event("delete", %{"id" => id}, socket)
    else
      {:noreply, socket}
    end
  end

  def handle_event(event, %{"id" => scene_id}, socket)
      when event in ~w(delete delete_scene) do
    Authorize.with_authorization(socket, :edit_content, fn socket ->
      case Scenes.get_scene(socket.assigns.project.id, scene_id) do
        nil ->
          {:noreply, put_flash(socket, :error, dgettext("scenes", "Scene not found."))}

        scene ->
          case Scenes.delete_scene(scene) do
            {:ok, _} ->
              {:noreply,
               socket
               |> put_flash(:info, dgettext("scenes", "Scene moved to trash."))
               |> reload_scenes()}

            {:error, _} ->
              {:noreply,
               put_flash(socket, :error, dgettext("scenes", "Could not delete scene."))}
          end
      end
    end)
  end

  def handle_event("create_scene", _params, socket) do
    Authorize.with_authorization(socket, :edit_content, fn socket ->
      case Scenes.create_scene(socket.assigns.project, %{name: dgettext("scenes", "Untitled")}) do
        {:ok, new_scene} ->
          {:noreply,
           push_navigate(socket,
             to:
               ~p"/workspaces/#{socket.assigns.workspace.slug}/projects/#{socket.assigns.project.slug}/scenes/#{new_scene.id}"
           )}

        {:error, :limit_reached, _details} ->
          {:noreply, put_flash(socket, :error, gettext("Item limit reached for your plan"))}

        {:error, _changeset} ->
          {:noreply, put_flash(socket, :error, dgettext("scenes", "Could not create scene."))}
      end
    end)
  end

  def handle_event("create_child_scene", %{"parent_id" => parent_id}, socket) do
    Authorize.with_authorization(socket, :edit_content, fn socket ->
      attrs = %{name: dgettext("scenes", "Untitled"), parent_id: parent_id}

      case Scenes.create_scene(socket.assigns.project, attrs) do
        {:ok, new_scene} ->
          {:noreply,
           push_navigate(socket,
             to:
               ~p"/workspaces/#{socket.assigns.workspace.slug}/projects/#{socket.assigns.project.slug}/scenes/#{new_scene.id}"
           )}

        {:error, :limit_reached, _details} ->
          {:noreply, put_flash(socket, :error, gettext("Item limit reached for your plan"))}

        {:error, _changeset} ->
          {:noreply, put_flash(socket, :error, dgettext("scenes", "Could not create scene."))}
      end
    end)
  end

  def handle_event(
        "move_to_parent",
        %{"item_id" => item_id, "new_parent_id" => new_parent_id, "position" => position},
        socket
      ) do
    Authorize.with_authorization(socket, :edit_content, fn socket ->
      case Scenes.get_scene(socket.assigns.project.id, item_id) do
        nil ->
          {:noreply, put_flash(socket, :error, dgettext("scenes", "Scene not found."))}

        scene ->
          new_parent_id = MapUtils.parse_int(new_parent_id)
          position = MapUtils.parse_int(position) || 0

          case Scenes.move_scene_to_position(scene, new_parent_id, position) do
            {:ok, _} ->
              {:noreply, reload_scenes(socket)}

            {:error, _} ->
              {:noreply,
               put_flash(socket, :error, dgettext("scenes", "Could not move scene."))}
          end
      end
    end)
  end

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
      fn s ->
        s
        |> assign(:scenes, Scenes.list_scenes(project_id))
        |> assign(:scenes_tree, prepare_scenes_tree(Scenes.list_scenes_tree(project_id)))
      end
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
            {:info,
             dgettext("scenes", "Scene \"%{name}\" has no zones or pins", name: issue.scene_name)}

          :no_background ->
            {:warning,
             dgettext("scenes", "Scene \"%{name}\" has no background image",
               name: issue.scene_name
             )}

          :missing_shortcut ->
            {:warning,
             dgettext("scenes", "Scene \"%{name}\" has no shortcut", name: issue.scene_name)}

          _ ->
            {:info, gettext("Issue detected")}
        end

      %{
        severity: to_string(severity),
        message: message,
        href:
          ~p"/workspaces/#{workspace.slug}/projects/#{project.slug}/scenes/#{issue.scene_id}"
      }
    end)
  end
end
