defmodule StoryarnWeb.SceneLive.Show do
  @moduledoc false

  use StoryarnWeb, :live_view

  import StoryarnWeb.SceneLive.Helpers.PropsSerializer,
    only: [
      prepare_layers_for_vue: 1,
      prepare_legend_groups: 3,
      prepare_scene_for_vue: 1,
      prepare_pins_for_vue: 1,
      prepare_zones_for_vue: 1,
      prepare_connections_for_vue: 1,
      prepare_annotations_for_vue: 1,
      serialize_entity_locks: 1,
      serialize_selected_element: 2,
      prepare_ambient_flows_for_vue: 1,
      prepare_project_flows_for_vue: 1,
      prepare_project_scenes_for_vue: 1,
      prepare_project_sheets_for_vue: 1
    ]

  import StoryarnWeb.SceneLive.Helpers.SceneHelpers
  import StoryarnWeb.SceneLive.Helpers.SceneSerializer

  alias Storyarn.Analytics
  alias Storyarn.Assets
  alias Storyarn.Collaboration
  alias Storyarn.Collaboration.Presence
  alias Storyarn.Scenes
  alias Storyarn.Shared.HtmlSanitizer
  alias Storyarn.Shared.MapUtils
  alias Storyarn.Versioning
  alias StoryarnWeb.FlowLive.Helpers.VariableHelpers
  alias StoryarnWeb.Helpers.Authorize
  alias StoryarnWeb.Helpers.VersionEventHelpers
  alias StoryarnWeb.Helpers.VersionHistoryHelpers
  alias StoryarnWeb.Live.Shared.CollaborationHelpers, as: Collab
  alias StoryarnWeb.Live.Shared.PickerSearch
  alias StoryarnWeb.Live.Shared.ProjectChromeHelpers
  alias StoryarnWeb.Live.Shared.RestorationHandlers
  alias StoryarnWeb.PrivateMedia
  alias StoryarnWeb.SceneLive.Handlers.CanvasEventHandlers
  alias StoryarnWeb.SceneLive.Handlers.CollaborationHandlers
  alias StoryarnWeb.SceneLive.Handlers.ElementHandlers
  alias StoryarnWeb.SceneLive.Handlers.LayerHandlers
  alias StoryarnWeb.SceneLive.Handlers.TreeHandlers
  alias StoryarnWeb.SceneLive.Handlers.UndoRedoHandlers

  @lock_heartbeat_interval 10_000
  @zone_label_icon_max_size 256 * 1024
  @zone_label_icon_content_types ~w(image/svg+xml image/png image/gif)
  @zone_label_icon_extensions ~w(.svg .png .gif)

  @impl true
  def render(%{compact: true, scene: nil} = assigns) do
    ~H"""
    <StoryarnWeb.Components.CompareLayout.compare socket={@socket} flash={@flash}>
      <div class="h-full"></div>
    </StoryarnWeb.Components.CompareLayout.compare>
    """
  end

  def render(%{compact: true} = assigns) do
    render_compact(assigns)
  end

  def render(assigns) do
    assigns = assign(assigns, :background_upload, scene_background_upload(assigns))

    ~H"""
    <StoryarnWeb.Components.ProjectLayout.project
      socket={@socket}
      flash={@flash}
      project={@project}
      workspace={@workspace}
      current_scope={@current_scope}
      current_user={@current_user}
      urls={@urls}
      active_tool={:scenes}
      is_super_admin={@is_super_admin}
      online_users={@online_users}
      restoration_banner={@restoration_banner}
      onboarding={@onboarding}
      onboarding_autostart
      canvas_mode={true}
      sidebar_module={StoryarnWeb.SceneSidebarLive}
      sidebar_session={
        %{
          "project_id" => @project.id,
          "workspace_slug" => @workspace.slug,
          "project_slug" => @project.slug,
          "scene_id" => @scene && to_string(@scene.id),
          "can_edit" => @can_edit,
          "active_tool" => "scenes",
          "dashboard_url" => ~p"/workspaces/#{@workspace.slug}/projects/#{@project.slug}/scenes",
          "current_scope" => @current_scope,
          "locale" => @locale
        }
      }
    >
      <.vue
        :if={@scene}
        v-component="live/scene/show/SceneHeader"
        v-socket={@socket}
        v-inject:top-left="project-layout"
        id="scene-header"
        header={scene_header_props(assigns)}
      />

      <.vue
        :if={@scene}
        v-component="live/scene/show/SceneHeaderActions"
        v-socket={@socket}
        v-inject:top-right="project-layout"
        id="scene-actions"
        edit-mode={@edit_mode}
        can-edit={@can_edit}
      />

      <.vue
        :if={@scene}
        v-component="live/scene/show/SceneSurface"
        v-socket={@socket}
        v-inject="project-layout"
        id="scene-surface"
        class="w-full h-full"
        surface={scene_surface_props(assigns)}
      />

      <%!-- LiveView owns the upload input; Vue owns the visible upload surface. --%>
      <form
        :if={@can_edit && @background_upload}
        id="bg-upload-form"
        phx-change="validate_bg_upload"
        class="hidden"
      >
        <.live_file_input upload={@background_upload} />
      </form>

      <.vue
        :if={@scene}
        v-component="live/scene/show/ScenePanels"
        v-socket={@socket}
        v-inject:panels="project-layout"
        id="scene-panels"
        panels={scene_panels_props(assigns)}
      />
    </StoryarnWeb.Components.ProjectLayout.project>
    """
  end

  defp render_compact(assigns) do
    ~H"""
    <StoryarnWeb.Components.CompareLayout.compare socket={@socket} flash={@flash}>
      <.vue
        v-component="live/scene/show/SceneCompactSurface"
        v-socket={@socket}
        v-inject="compare-layout"
        id={"scene-compact-surface-#{@scene.id}"}
        class="h-full relative"
        surface={scene_compact_surface_props(assigns)}
      />
    </StoryarnWeb.Components.CompareLayout.compare>
    """
  end

  defp scene_header_props(assigns) do
    %{
      toolbar: %{
        canEdit: assigns.can_edit,
        sceneName: assigns.scene.name,
        sceneShortcut: assigns.scene.shortcut
      },
      search: %{
        searchQuery: assigns.search_query,
        searchFilter: assigns.search_filter,
        searchResults: assigns.search_results
      }
    }
  end

  defp scene_surface_props(assigns) do
    %{
      canvas: scene_surface_canvas(assigns),
      dock: scene_surface_dock(assigns),
      layers: scene_surface_layers(assigns),
      legend: scene_surface_legend(assigns),
      upload: scene_surface_upload(assigns)
    }
  end

  defp scene_compact_surface_props(assigns) do
    %{
      canvas:
        assigns
        |> scene_surface_canvas()
        |> Map.merge(%{
          id: "scene-canvas-compact-#{assigns.scene.id}",
          mountId: "scene-canvas-compact-mount-#{assigns.scene.id}"
        }),
      dock:
        assigns
        |> scene_surface_dock()
        |> Map.merge(%{compact: true, projectSheets: []})
    }
  end

  defp scene_panels_props(assigns) do
    %{
      versions: scene_panels_versions(assigns),
      element: scene_panels_element(assigns),
      settings: scene_panels_settings(assigns)
    }
  end

  defp scene_surface_canvas(assigns) do
    scene_id = assigns.scene.id

    %{
      key: "scene-canvas-mount-#{scene_id}",
      id: "scene-canvas-#{scene_id}",
      mountId: "scene-canvas-mount-#{scene_id}",
      sceneData: prepare_scene_for_vue(assigns.scene),
      pins: prepare_pins_for_vue(assigns.pins),
      zones: prepare_zones_for_vue(assigns.zones),
      connections: prepare_connections_for_vue(assigns.connections),
      annotations: prepare_annotations_for_vue(assigns.annotations),
      layers: prepare_layers_for_vue(assigns.layers),
      activeTool: to_string(assigns.active_tool),
      editMode: assigns.edit_mode,
      canEdit: assigns.can_edit,
      collaboration: %{
        userId: assigns.current_scope.user.id,
        locks: serialize_entity_locks(assigns.entity_locks)
      }
    }
  end

  defp scene_surface_dock(assigns) do
    %{
      activeTool: to_string(assigns.active_tool),
      editMode: assigns.edit_mode,
      compact: false,
      pendingSheet: assigns.pending_sheet_for_pin && %{name: assigns.pending_sheet_for_pin.name},
      projectSheets: prepare_project_sheets_for_vue(assigns.project_sheets),
      workspaceSlug: assigns.workspace.slug,
      projectSlug: assigns.project.slug,
      sceneId: assigns.scene.id
    }
  end

  defp scene_surface_layers(assigns) do
    %{
      layers: prepare_layers_for_vue(assigns.layers),
      activeLayerId: assigns.active_layer_id,
      canEdit: assigns.can_edit,
      editMode: assigns.edit_mode,
      popoverOpen: assigns.layers_popover_open
    }
  end

  defp scene_surface_legend(assigns) do
    %{
      legendData: prepare_legend_groups(assigns.pins, assigns.zones, assigns.connections),
      legendOpen: assigns.legend_open
    }
  end

  defp scene_surface_upload(assigns) do
    background_upload = scene_background_upload(assigns)
    can_upload = !!(assigns.can_edit && assigns.edit_mode && background_upload)

    %{
      canUpload: can_upload,
      backgroundSet: background_set?(assigns.scene),
      inputRef: if(can_upload, do: background_upload.ref),
      dropTarget: if(can_upload, do: background_upload.ref),
      entries:
        if can_upload do
          Enum.map(background_upload.entries, &scene_upload_entry/1)
        else
          []
        end
    }
  end

  defp scene_background_upload(assigns) do
    assigns
    |> Map.get(:uploads, %{})
    |> Map.get(:background)
  end

  defp scene_upload_entry(entry) do
    %{
      ref: entry.ref,
      name: entry.client_name,
      baseName: Path.rootname(entry.client_name),
      extension: Path.extname(entry.client_name),
      progress: entry.progress
    }
  end

  defp scene_panels_versions(assigns) do
    history_data = assigns.history_data

    %{
      open: assigns.right_panel == :versions,
      versions: history_value(history_data, :versions, []),
      namedVersions: history_value(history_data, :named_versions, []),
      autoVersions: history_value(history_data, :auto_versions, []),
      hasMore: history_value(history_data, :has_more, false),
      canNameVersion: history_value(history_data, :can_name_version, false),
      currentVersionId: history_value(history_data, :current_version_id, nil),
      canEdit: assigns.can_edit,
      restoreEnabled:
        assigns.can_edit &&
          Versioning.restore_enabled?({:entity_version_restore, "scene"}),
      loading: assigns.right_panel == :versions && is_nil(history_data)
    }
  end

  defp scene_panels_element(assigns) do
    %{
      selectedType: assigns.selected_type,
      selectedElement: serialize_selected_element(assigns.selected_type, assigns.selected_element),
      canEdit: assigns.can_edit && not Map.get(assigns.selected_element || %{}, :locked, false),
      elementPanelOpen: assigns.right_panel == :element,
      projectSheets: PickerSearch.initial_sheet_options(assigns.project.id, selected_sheet_ids(assigns)),
      projectFlows: element_panel_flow_options(assigns),
      projectScenes: prepare_project_scenes_for_vue(assigns.project_scenes),
      projectVariables: assigns.project_variables
    }
  end

  defp element_panel_flow_options(%{selected_type: "zone"} = assigns) do
    prepare_project_flows_for_vue(assigns.project_flows)
  end

  defp element_panel_flow_options(assigns) do
    PickerSearch.initial_flow_options(assigns.project.id, selected_flow_ids(assigns))
  end

  defp selected_sheet_ids(%{selected_type: "pin", selected_element: pin}) do
    [pin && Map.get(pin, :sheet_id)]
  end

  defp selected_sheet_ids(%{selected_type: "zone", selected_element: zone}) do
    zone
    |> zone_collection_sheet_ids()
    |> Enum.uniq()
  end

  defp selected_sheet_ids(_assigns), do: []

  defp selected_flow_ids(%{selected_type: "pin", selected_element: pin}) do
    [pin && Map.get(pin, :flow_id)]
  end

  defp selected_flow_ids(_assigns), do: []

  defp zone_collection_sheet_ids(nil), do: []

  defp zone_collection_sheet_ids(zone) do
    zone
    |> Map.get(:action_data, %{})
    |> collection_items()
    |> Enum.map(fn item -> item["sheet_id"] || item[:sheet_id] end)
    |> Enum.reject(&is_nil/1)
  end

  defp collection_items(%{"items" => items}) when is_list(items), do: items
  defp collection_items(%{items: items}) when is_list(items), do: items
  defp collection_items(_action_data), do: []

  defp scene_panels_settings(assigns) do
    %{
      scene: prepare_scene_for_vue(assigns.scene),
      canEdit: assigns.can_edit,
      ambientFlows: prepare_ambient_flows_for_vue(assigns.ambient_flows),
      projectFlows: prepare_project_flows_for_vue(assigns.project_flows),
      sceneSettingsOpen: assigns.right_panel == :settings && assigns.can_edit && assigns.edit_mode
    }
  end

  defp history_value(nil, _key, default), do: default
  defp history_value(history_data, key, default), do: history_data[key] || default

  @impl true
  def mount(_params, _session, socket) do
    %{project: project, can_edit: can_edit} = socket.assigns

    if connected?(socket) do
      Collaboration.subscribe_restoration(project.id)

      Phoenix.PubSub.subscribe(
        Storyarn.PubSub,
        ProjectChromeHelpers.shell_topic(project.id)
      )
    end

    {can_edit, restoration_banner} =
      RestorationHandlers.check_restoration_lock(project.id, can_edit)

    socket =
      socket
      |> assign(:can_edit, can_edit)
      |> assign(:compact, false)
      |> assign(:restoration_banner, restoration_banner)
      |> assign(:online_users, ProjectChromeHelpers.initial_online_users(project.id))
      |> assign(:collab_scope, nil)
      |> assign(:entity_locks, %{})
      |> assign(:lock_heartbeat_ref, nil)
      |> assign(:_broadcast, nil)
      # Defaults — scene loaded in handle_params
      |> assign(:scene, nil)
      |> assign(:ancestors, [])
      |> assign(:layers, [])
      |> assign(:zones, [])
      |> assign(:pins, [])
      |> assign(:connections, [])
      |> assign(:annotations, [])
      |> assign(:ambient_flows, [])
      |> assign(:scene_data, %{})
      |> assign(:edit_mode, can_edit)
      |> assign(:active_tool, :select)
      |> assign(:selected_element, nil)
      |> assign(:selected_type, nil)
      |> assign(:right_panel, nil)
      |> assign(:active_layer_id, nil)
      |> assign(:renaming_layer_id, nil)
      |> assign(:show_pin_icon_upload, false)
      |> assign(:show_sheet_picker, false)
      |> assign(:pending_sheet_for_pin, nil)
      |> assign(:search_query, "")
      |> assign(:search_filter, "all")
      |> assign(:search_results, [])
      |> assign(:legend_open, false)
      |> assign(:layers_popover_open, false)
      |> assign(:undo_stack, [])
      |> assign(:redo_stack, [])
      |> assign(:panel_sections, %{})
      |> assign(:project_scenes, [])
      |> assign(:project_sheets, [])
      |> assign(:project_flows, [])
      |> assign(:project_variables, [])
      |> assign(:referencing_flows, [])
      |> assign(:sidebar_loaded, false)
      |> assign(:pending_delete_id, nil)
      |> maybe_allow_background_upload(can_edit)

    {:ok, socket}
  end

  @impl true
  def handle_params(%{"id" => scene_id} = params, _url, socket) do
    compact = params["layout"] == "compact"

    socket = assign(socket, :compact, compact)

    current_id =
      case socket.assigns.scene do
        %{id: id} -> to_string(id)
        _ -> nil
      end

    socket =
      if scene_id == current_id do
        socket
      else
        load_scene(socket, scene_id)
      end

    Phoenix.PubSub.broadcast(
      Storyarn.PubSub,
      ProjectChromeHelpers.shell_topic(socket.assigns.project.id),
      {:active_scene, scene_id}
    )

    # Handle highlight params
    socket =
      case params["highlight"] do
        "pin:" <> id ->
          push_event(socket, "focus_element", %{type: "pin", id: parse_highlight_id(id)})

        "zone:" <> id ->
          push_event(socket, "focus_element", %{type: "zone", id: parse_highlight_id(id)})

        _ ->
          socket
      end

    {:noreply, socket}
  end

  defp load_scene(socket, scene_id) do
    %{project: project, can_edit: can_edit} = socket.assigns

    # Teardown previous scene collaboration
    socket = teardown_scene_collab(socket)

    case Scenes.get_scene(project.id, scene_id) do
      nil ->
        socket
        |> put_flash(:error, dgettext("scenes", "Scene not found."))
        |> push_navigate(to: ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/scenes")

      scene ->
        has_tree = socket.assigns.sidebar_loaded

        socket
        |> setup_scene_collab(scene)
        |> assign_scene_state(scene, can_edit)
        |> maybe_load_sidebar(has_tree, project)
    end
  end

  defp setup_scene_collab(socket, scene) do
    compact = socket.assigns.compact

    {online_users, entity_locks} =
      if compact do
        {[], %{}}
      else
        scope = {:scene, scene.id}
        user = socket.assigns.current_scope.user
        Collab.setup(socket, scope, user, cursors: true, locks: true, changes: true)
        Collab.get_initial_state(socket, scope)
      end

    socket
    |> assign(:collab_scope, if(compact, do: nil, else: {:scene, scene.id}))
    |> assign(:online_users, online_users)
    |> assign(:entity_locks, entity_locks)
    |> assign(:_broadcast, nil)
    |> then(fn s -> if compact, do: s, else: schedule_lock_heartbeat(s) end)
  end

  defp reload_ambient_flows(socket) do
    assign(socket, :ambient_flows, Scenes.list_ambient_flows(socket.assigns.scene.id))
  end

  defp update_ambient_flow_priority(socket, af_id, value) do
    id = MapUtils.parse_int(af_id)

    case Scenes.get_ambient_flow(socket.assigns.scene.id, id) do
      nil -> socket
      af -> save_ambient_flow_priority(socket, af, value)
    end
  end

  defp save_ambient_flow_priority(socket, ambient_flow, value) do
    priority = MapUtils.parse_int(value) || 0

    case Scenes.update_ambient_flow(ambient_flow, %{"priority" => priority}) do
      {:ok, _} -> reload_ambient_flows(socket)
      {:error, _} -> socket
    end
  end

  defp do_remove_ambient_flow(socket, id) do
    scene = socket.assigns.scene

    case Scenes.get_ambient_flow(scene.id, MapUtils.parse_int(id)) do
      nil ->
        socket

      af ->
        case Scenes.delete_ambient_flow(af) do
          {:ok, _} ->
            reload_ambient_flows(socket)

          {:error, _} ->
            put_flash(socket, :error, dgettext("scenes", "Could not remove ambient flow."))
        end
    end
  end

  defp do_toggle_ambient_flow(socket, id) do
    scene = socket.assigns.scene

    case Scenes.get_ambient_flow(scene.id, MapUtils.parse_int(id)) do
      nil ->
        socket

      af ->
        case Scenes.update_ambient_flow(af, %{enabled: !af.enabled}) do
          {:ok, _} ->
            reload_ambient_flows(socket)

          {:error, _} ->
            put_flash(socket, :error, dgettext("scenes", "Could not update ambient flow."))
        end
    end
  end

  defp do_reorder_ambient_flow(socket, id, direction) do
    flows = socket.assigns.ambient_flows

    with idx when idx != nil <- Enum.find_index(flows, &(to_string(&1.id) == id)),
         new_idx = compute_reorder_index(idx, direction, length(flows)),
         true <- idx != new_idx do
      ordered_ids =
        flows
        |> Enum.map(& &1.id)
        |> List.delete_at(idx)
        |> List.insert_at(new_idx, Enum.at(flows, idx).id)

      case Scenes.reorder_ambient_flows(socket.assigns.scene.id, ordered_ids) do
        {:ok, _} ->
          reload_ambient_flows(socket)

        {:error, _} ->
          put_flash(socket, :error, dgettext("scenes", "Could not reorder ambient flows."))
      end
    else
      _ -> socket
    end
  end

  defp compute_reorder_index(idx, "up", _len), do: max(0, idx - 1)
  defp compute_reorder_index(idx, "down", len), do: min(len - 1, idx + 1)
  defp compute_reorder_index(idx, _direction, _len), do: idx

  defp do_update_ambient_flow_trigger(socket, params) do
    id = MapUtils.parse_int(params["id"])

    case Scenes.get_ambient_flow(socket.assigns.scene.id, id) do
      nil ->
        socket

      af ->
        attrs = build_trigger_attrs(af, params)

        case Scenes.update_ambient_flow(af, attrs) do
          {:ok, _} ->
            reload_ambient_flows(socket)

          {:error, _} ->
            put_flash(socket, :error, dgettext("scenes", "Could not update trigger."))
        end
    end
  end

  defp build_trigger_attrs(af, params) do
    trigger_type = params["trigger_type"] || af.trigger_type

    %{
      "trigger_type" => trigger_type,
      "trigger_config" => build_trigger_config(trigger_type, params),
      "priority" => MapUtils.parse_int(params["priority"]) || 0
    }
  end

  defp build_trigger_config("timed", params), do: %{"interval_ms" => MapUtils.parse_int(params["interval_ms"]) || 30_000}

  defp build_trigger_config("on_event", params), do: %{"variable_ref" => params["variable_ref"] || ""}

  defp build_trigger_config(_type, _params), do: %{}

  defp assign_scene_state(socket, scene, can_edit) do
    socket
    |> assign(:scene, scene)
    |> assign(:ancestors, Scenes.list_ancestors(scene))
    |> assign(:layers, scene.layers || [])
    |> assign(:zones, scene.zones || [])
    |> assign(:pins, scene.pins || [])
    |> assign(:connections, scene.connections || [])
    |> assign(:annotations, scene.annotations || [])
    |> assign(:ambient_flows, Scenes.list_ambient_flows(scene.id))
    |> assign(:scene_data, build_scene_data(scene, can_edit))
    |> assign(:edit_mode, can_edit)
    |> assign(:active_tool, :select)
    |> assign(:selected_element, nil)
    |> assign(:selected_type, nil)
    |> assign(:right_panel, nil)
    |> assign(:history_data, nil)
    |> assign(:active_layer_id, default_layer_id(scene.layers))
    |> assign(:renaming_layer_id, nil)
    |> assign(:show_pin_icon_upload, false)
    |> assign(:show_sheet_picker, false)
    |> assign(:pending_sheet_for_pin, nil)
    |> assign(:search_query, "")
    |> assign(:search_filter, "all")
    |> assign(:search_results, [])
    |> assign(:legend_open, false)
    |> assign(:layers_popover_open, false)
    |> assign(:undo_stack, [])
    |> assign(:redo_stack, [])
    |> assign(:auto_snapshot_ref, nil)
    |> assign(:auto_snapshot_timer, nil)
    |> assign(:panel_sections, %{})
    |> assign(:referencing_flows, [])
  end

  defp maybe_load_sidebar(socket, true, _project), do: socket

  defp maybe_load_sidebar(socket, false, project) do
    start_async(socket, :load_sidebar_data, fn ->
      %{
        project_scenes: Scenes.list_scenes(project.id),
        project_sheets: Storyarn.Sheets.list_sheets_tree(project.id),
        project_flows: Storyarn.Flows.list_flows(project.id),
        project_variables: VariableHelpers.list_all_variables(project.id)
      }
    end)
  end

  defp parse_highlight_id(id) do
    case Integer.parse(id) do
      {int, ""} -> int
      _ -> nil
    end
  end

  @valid_tools ~w(select pan rectangle triangle circle freeform pin annotation connector ruler)

  @impl true
  def handle_event("open_versions_panel", _params, %{assigns: %{compact: true}} = socket) do
    {:noreply, socket}
  end

  def handle_event("open_versions_panel", _params, socket) do
    maybe_track_version_panel_opened(socket, "scene")

    socket =
      if is_nil(socket.assigns.history_data) do
        VersionHistoryHelpers.load_history_data(
          socket,
          "scene",
          socket.assigns.scene,
          socket.assigns.project.id,
          socket.assigns.workspace.id
        )
      else
        socket
      end

    {:noreply, assign(socket, :right_panel, :versions)}
  end

  def handle_event("close_versions_panel", _params, socket) do
    {:noreply, dismiss_right_panel(socket, :versions)}
  end

  # ---------------------------------------------------------------------------
  # Version History handlers (Vue VersionHistoryPanel)
  # ---------------------------------------------------------------------------

  def handle_event("create_version", %{"title" => title, "description" => description}, socket) do
    VersionEventHelpers.handle_create(%{"title" => title, "description" => description}, socket, scene_version_config())
  end

  def handle_event("promote_version", params, socket) do
    VersionEventHelpers.handle_promote(params, socket, scene_version_config())
  end

  def handle_event("delete_version", %{"version_number" => vn}, socket) do
    VersionEventHelpers.handle_delete(%{"version_number" => vn}, socket, scene_version_config())
  end

  def handle_event("load_more_versions", _params, socket) do
    VersionEventHelpers.handle_load_more(socket, scene_version_config())
  end

  def handle_event("preview_restore", %{"version_number" => vn}, socket) do
    VersionEventHelpers.handle_preview_restore(%{"version_number" => vn}, socket, scene_version_config())
  end

  def handle_event("save_and_restore", %{"version_number" => vn}, socket) do
    VersionEventHelpers.handle_save_and_restore(%{"version_number" => vn}, socket, scene_version_config())
  end

  def handle_event("discard_and_restore", %{"version_number" => vn}, socket) do
    VersionEventHelpers.handle_discard_and_restore(%{"version_number" => vn}, socket, scene_version_config())
  end

  def handle_event("confirm_restore", %{"version_number" => vn} = params, socket) do
    VersionEventHelpers.handle_confirm_restore(
      %{"version_number" => vn, "skip_pre_snapshot" => params["skip_pre_snapshot"]},
      socket,
      scene_version_config()
    )
  end

  def handle_event("compare_version", %{"version_number" => vn}, socket) do
    VersionEventHelpers.handle_compare(%{"version_number" => vn}, socket, scene_version_config())
  end

  def handle_event("save_name", params, socket) do
    Authorize.with_authorization(socket, :edit_content, fn _socket ->
      CanvasEventHandlers.handle_save_name(params, socket)
    end)
  end

  def handle_event("set_tool", %{"type" => tool}, socket) when tool in @valid_tools do
    CanvasEventHandlers.handle_set_tool(tool, socket)
  end

  def handle_event("set_tool", _params, socket), do: {:noreply, socket}

  def handle_event("export_scene", %{"format" => format}, socket) when format in ~w(png svg) do
    CanvasEventHandlers.handle_export_scene(format, socket)
  end

  def handle_event("export_scene", _params, socket), do: {:noreply, socket}

  def handle_event("toggle_edit_mode", params, socket) do
    Authorize.with_authorization(socket, :edit_content, fn _socket ->
      CanvasEventHandlers.handle_toggle_edit_mode(socket, params)
    end)
  end

  def handle_event("search_elements", params, socket) do
    CanvasEventHandlers.handle_search_elements(params, socket)
  end

  def handle_event("picker_search", params, socket) do
    {:noreply, PickerSearch.handle_search(socket, params)}
  end

  def handle_event("set_search_filter", %{"filter" => filter} = params, socket)
      when filter in ~w(all pin zone annotation connection) do
    CanvasEventHandlers.handle_set_search_filter(params, socket)
  end

  def handle_event("set_search_filter", _params, socket), do: {:noreply, socket}

  def handle_event("clear_search", _params, socket) do
    CanvasEventHandlers.handle_clear_search(socket)
  end

  def handle_event("focus_search_result", %{"type" => type} = params, socket)
      when type in ~w(pin zone connection annotation) do
    CanvasEventHandlers.handle_focus_search_result(params, socket)
  end

  def handle_event("focus_search_result", _params, socket), do: {:noreply, socket}

  def handle_event("select_element", %{"type" => type, "id" => id} = params, socket)
      when type in ~w(pin zone connection annotation) do
    release_element_lock(socket)

    params
    |> CanvasEventHandlers.handle_select_element(socket)
    |> maybe_acquire_lock(id)
  end

  def handle_event("validate_bg_upload", _params, socket) do
    case socket.assigns.uploads[:background] do
      %{entries: [entry | _]} ->
        if entry.valid? do
          {:noreply, socket}
        else
          errors = upload_errors(socket.assigns.uploads.background, entry)
          message = upload_error_to_message(errors)
          {:noreply, put_flash(socket, :error, message)}
        end

      _ ->
        {:noreply, socket}
    end
  end

  def handle_event("noop", _params, socket), do: {:noreply, socket}

  def handle_event("deselect", _params, socket) do
    release_element_lock(socket)
    CanvasEventHandlers.handle_deselect(socket)
  end

  # ---------------------------------------------------------------------------
  # Collaboration: cursor events
  # ---------------------------------------------------------------------------

  def handle_event("cursor_moved", params, socket) do
    CollaborationHandlers.handle_cursor_moved(params, socket)
  end

  def handle_event("cursor_left", _params, socket) do
    CollaborationHandlers.handle_cursor_left(socket)
  end

  # ---------------------------------------------------------------------------
  # Collaboration: ephemeral drag relay (no DB, no auth)
  # ---------------------------------------------------------------------------

  def handle_event("drag_pin", %{"id" => id, "position_x" => x, "position_y" => y}, socket)
      when (is_binary(id) or is_integer(id)) and is_number(x) and is_number(y) do
    CollaborationHandlers.handle_drag_relay(socket, :pin_dragging, %{
      id: id,
      position_x: x,
      position_y: y
    })
  end

  def handle_event("drag_pin", _params, socket), do: {:noreply, socket}

  def handle_event("drag_annotation", %{"id" => id, "position_x" => x, "position_y" => y}, socket)
      when (is_binary(id) or is_integer(id)) and is_number(x) and is_number(y) do
    CollaborationHandlers.handle_drag_relay(socket, :annotation_dragging, %{
      id: id,
      position_x: x,
      position_y: y
    })
  end

  def handle_event("drag_annotation", _params, socket), do: {:noreply, socket}

  def handle_event("drag_zone", %{"id" => id, "vertices" => vertices}, socket)
      when (is_binary(id) or is_integer(id)) and is_list(vertices) do
    CollaborationHandlers.handle_drag_relay(socket, :zone_dragging, %{
      id: id,
      vertices: vertices
    })
  end

  def handle_event("drag_zone", _params, socket), do: {:noreply, socket}

  # ---------------------------------------------------------------------------
  # Element properties panel
  # ---------------------------------------------------------------------------

  def handle_event("open_element_panel", _params, socket) do
    {:noreply, assign(socket, :right_panel, :element)}
  end

  def handle_event("toggle_element_panel", _params, socket) do
    target = if socket.assigns.right_panel == :element, do: nil, else: :element
    {:noreply, assign(socket, :right_panel, target)}
  end

  def handle_event("close_element_panel", _params, socket) do
    {:noreply, dismiss_right_panel(socket, :element)}
  end

  def handle_event("open_scene_settings", _params, socket) do
    {:noreply, assign(socket, :right_panel, :settings)}
  end

  def handle_event("close_scene_settings", _params, socket) do
    {:noreply, dismiss_right_panel(socket, :settings)}
  end

  # ---------------------------------------------------------------------------
  # Property panel update handlers — delegate to ElementHandlers
  # ---------------------------------------------------------------------------

  def handle_event("update_patrol_mode", %{"id" => mode}, socket) do
    Authorize.with_authorization(socket, :edit_content, fn _socket ->
      params = %{
        "id" => socket.assigns.selected_element.id,
        "field" => "patrol_mode",
        "value" => mode
      }

      params |> ElementHandlers.handle_update_pin(socket) |> broadcast_scene_change()
    end)
  end

  def handle_event("update_pin", params, socket) do
    Authorize.with_authorization(socket, :edit_content, fn _socket ->
      params |> ElementHandlers.handle_update_pin(socket) |> broadcast_scene_change()
    end)
  end

  def handle_event("pin_icon_upload_validation_error", %{"reason" => "invalid_type"}, socket) do
    {:noreply, put_flash(socket, :error, zone_label_icon_invalid_type_message())}
  end

  def handle_event("pin_icon_upload_validation_error", %{"reason" => "too_large"}, socket) do
    {:noreply, put_flash(socket, :error, zone_label_icon_too_large_message())}
  end

  def handle_event("upload_pin_icon", %{"id" => id, "filename" => filename, "content_type" => ct, "data" => data}, socket) do
    Authorize.with_authorization(socket, :edit_content, fn _socket ->
      with %{__struct__: Scenes.ScenePin} = pin <- Scenes.get_pin(socket.assigns.scene.id, id),
           :ok <- validate_zone_label_icon_type(filename, ct),
           [_header, base64] <- String.split(data, ",", parts: 2),
           {:ok, binary} <- Base.decode64(base64),
           :ok <- validate_zone_label_icon_size(binary),
           {:ok, icon_binary} <- validate_zone_label_icon_binary(ct, binary),
           {:ok, asset} <-
             upload_scene_icon_asset(icon_binary, filename, ct, socket),
           {:ok, updated} <- Scenes.update_pin(pin, %{"icon_asset_id" => asset.id}) do
        updated = Scenes.preload_pin_associations(updated)

        broadcast_scene_change(
          {:noreply,
           socket
           |> maybe_update_selected_pin(updated)
           |> update_pin_in_list(updated)
           |> push_event("pin_updated", serialize_pin(updated))
           |> put_flash(:info, dgettext("scenes", "Pin icon updated."))}
        )
      else
        {:error, message} ->
          {:noreply, put_flash(socket, :error, message)}

        _ ->
          {:noreply, put_flash(socket, :error, dgettext("scenes", "Could not upload pin icon."))}
      end
    end)
  end

  def handle_event("update_zone", params, socket) do
    Authorize.with_authorization(socket, :edit_content, fn _socket ->
      params |> ElementHandlers.handle_update_zone(socket) |> broadcast_scene_change()
    end)
  end

  def handle_event("zone_icon_upload_validation_error", %{"reason" => "invalid_type"}, socket) do
    {:noreply, put_flash(socket, :error, zone_label_icon_invalid_type_message())}
  end

  def handle_event("zone_icon_upload_validation_error", %{"reason" => "too_large"}, socket) do
    {:noreply, put_flash(socket, :error, zone_label_icon_too_large_message())}
  end

  def handle_event(
        "upload_zone_label_icon",
        %{"id" => id, "filename" => filename, "content_type" => ct, "data" => data},
        socket
      ) do
    Authorize.with_authorization(socket, :edit_content, fn _socket ->
      with %{__struct__: Scenes.SceneZone} = zone <- Scenes.get_zone(socket.assigns.scene.id, id),
           :ok <- validate_zone_label_icon_type(filename, ct),
           [_header, base64] <- String.split(data, ",", parts: 2),
           {:ok, binary} <- Base.decode64(base64),
           :ok <- validate_zone_label_icon_size(binary),
           {:ok, icon_binary} <- validate_zone_label_icon_binary(ct, binary),
           {:ok, asset} <-
             upload_scene_icon_asset(icon_binary, filename, ct, socket),
           {:ok, updated} <- Scenes.update_zone(zone, %{"label_icon_asset_id" => asset.id}) do
        updated = Scenes.get_zone!(updated.id)

        broadcast_scene_change(
          {:noreply,
           socket
           |> maybe_update_selected_zone(updated)
           |> update_zone_in_list(updated)
           |> push_event("zone_updated", serialize_zone(updated))
           |> put_flash(:info, dgettext("scenes", "Zone icon updated."))}
        )
      else
        {:error, message} ->
          {:noreply, put_flash(socket, :error, message)}

        _ ->
          {:noreply, put_flash(socket, :error, dgettext("scenes", "Could not upload zone icon."))}
      end
    end)
  end

  def handle_event("update_connection", params, socket) do
    Authorize.with_authorization(socket, :edit_content, fn _socket ->
      params |> ElementHandlers.handle_update_connection(socket) |> broadcast_scene_change()
    end)
  end

  def handle_event("update_connection_waypoints", params, socket) do
    Authorize.with_authorization(socket, :edit_content, fn _socket ->
      params
      |> ElementHandlers.handle_update_connection_waypoints(socket)
      |> broadcast_scene_change()
    end)
  end

  def handle_event("clear_connection_waypoints", params, socket) do
    Authorize.with_authorization(socket, :edit_content, fn _socket ->
      params
      |> ElementHandlers.handle_clear_connection_waypoints(socket)
      |> broadcast_scene_change()
    end)
  end

  def handle_event("set_pending_delete_pin", params, socket) do
    Authorize.with_authorization(socket, :edit_content, fn _socket ->
      ElementHandlers.handle_set_pending_delete_pin(params, socket)
    end)
  end

  def handle_event("set_pending_delete_zone", params, socket) do
    Authorize.with_authorization(socket, :edit_content, fn _socket ->
      ElementHandlers.handle_set_pending_delete_zone(params, socket)
    end)
  end

  def handle_event("set_pending_delete_connection", params, socket) do
    Authorize.with_authorization(socket, :edit_content, fn _socket ->
      ElementHandlers.handle_set_pending_delete_connection(params, socket)
    end)
  end

  def handle_event("confirm_delete_element", params, socket) do
    Authorize.with_authorization(socket, :edit_content, fn _socket ->
      params |> ElementHandlers.handle_confirm_delete_element(socket) |> broadcast_scene_change()
    end)
  end

  # ---------------------------------------------------------------------------
  # Pin canvas handlers — delegate to ElementHandlers
  # ---------------------------------------------------------------------------

  def handle_event("create_pin", params, socket) do
    Authorize.with_authorization(socket, :edit_content, fn _socket ->
      params |> ElementHandlers.handle_create_pin(socket) |> broadcast_scene_change()
    end)
  end

  def handle_event("show_sheet_picker", params, socket) do
    ElementHandlers.handle_show_sheet_picker(params, socket)
  end

  def handle_event("cancel_sheet_picker", params, socket) do
    ElementHandlers.handle_cancel_sheet_picker(params, socket)
  end

  def handle_event("start_pin_from_sheet", params, socket) do
    ElementHandlers.handle_start_pin_from_sheet(params, socket)
  end

  def handle_event("create_pin_from_sheet", params, socket) do
    Authorize.with_authorization(socket, :edit_content, fn _socket ->
      params |> ElementHandlers.handle_create_pin_from_sheet(socket) |> broadcast_scene_change()
    end)
  end

  def handle_event("move_pin", params, socket) do
    Authorize.with_authorization(socket, :edit_content, fn _socket ->
      params |> ElementHandlers.handle_move_pin(socket) |> broadcast_scene_change()
    end)
  end

  # ---------------------------------------------------------------------------
  # Zone canvas handlers — delegate to ElementHandlers
  # ---------------------------------------------------------------------------

  def handle_event("create_zone", params, socket) do
    Authorize.with_authorization(socket, :edit_content, fn _socket ->
      params |> ElementHandlers.handle_create_zone(socket) |> broadcast_scene_change()
    end)
  end

  # ---------------------------------------------------------------------------
  # Layer handlers — delegate to LayerHandlers
  # ---------------------------------------------------------------------------

  def handle_event("create_layer", params, socket) do
    Authorize.with_authorization(socket, :edit_content, fn _socket ->
      params |> LayerHandlers.handle_create_layer(socket) |> broadcast_scene_change()
    end)
  end

  def handle_event("set_active_layer", params, socket) do
    LayerHandlers.handle_set_active_layer(params, socket)
  end

  def handle_event("toggle_layer_visibility", params, socket) do
    Authorize.with_authorization(socket, :edit_content, fn _socket ->
      params |> LayerHandlers.handle_toggle_layer_visibility(socket) |> broadcast_scene_change()
    end)
  end

  def handle_event("update_layer_fog", params, socket) do
    Authorize.with_authorization(socket, :edit_content, fn _socket ->
      params |> LayerHandlers.handle_update_layer_fog(socket) |> broadcast_scene_change()
    end)
  end

  def handle_event("start_rename_layer", params, socket) do
    LayerHandlers.handle_start_rename_layer(params, socket)
  end

  def handle_event("rename_layer", params, socket) do
    Authorize.with_authorization(socket, :edit_content, fn _socket ->
      params |> LayerHandlers.handle_rename_layer(socket) |> broadcast_scene_change()
    end)
  end

  def handle_event("set_pending_delete_layer", params, socket) do
    Authorize.with_authorization(socket, :edit_content, fn _socket ->
      LayerHandlers.handle_set_pending_delete_layer(params, socket)
    end)
  end

  def handle_event("confirm_delete_layer", params, socket) do
    Authorize.with_authorization(socket, :edit_content, fn _socket ->
      params |> LayerHandlers.handle_confirm_delete_layer(socket) |> broadcast_scene_change()
    end)
  end

  def handle_event("delete_layer", params, socket) do
    Authorize.with_authorization(socket, :edit_content, fn _socket ->
      params |> LayerHandlers.handle_delete_layer(socket) |> broadcast_scene_change()
    end)
  end

  # ---------------------------------------------------------------------------
  # Background upload handlers — delegate to LayerHandlers
  # ---------------------------------------------------------------------------

  def handle_event("toggle_legend", params, socket) do
    LayerHandlers.handle_toggle_legend(params, socket)
  end

  def handle_event("toggle_layers_popover", _params, socket) do
    {:noreply, assign(socket, :layers_popover_open, !socket.assigns.layers_popover_open)}
  end

  def handle_event("attach_background_asset", %{"asset_id" => asset_id}, socket) do
    Authorize.with_authorization(socket, :edit_content, fn socket ->
      project_id = socket.assigns.project.id

      case Assets.get_asset(project_id, MapUtils.parse_int(asset_id)) do
        nil -> {:noreply, put_flash(socket, :error, dgettext("scenes", "Asset not found."))}
        asset -> process_background_upload(socket, asset)
      end
    end)
  end

  def handle_event("remove_background", params, socket) do
    Authorize.with_authorization(socket, :edit_content, fn _socket ->
      params |> LayerHandlers.handle_remove_background(socket) |> broadcast_scene_change()
    end)
  end

  def handle_event("update_scene_scale", params, socket) do
    Authorize.with_authorization(socket, :edit_content, fn _socket ->
      params |> LayerHandlers.handle_update_scene_scale(socket) |> broadcast_scene_change()
    end)
  end

  def handle_event("update_scene_fog", params, socket) do
    Authorize.with_authorization(socket, :edit_content, fn _socket ->
      params |> LayerHandlers.handle_update_scene_fog(socket) |> broadcast_scene_change()
    end)
  end

  def handle_event("update_exploration_display_mode", params, socket) do
    Authorize.with_authorization(socket, :edit_content, fn _socket ->
      params
      |> LayerHandlers.handle_update_exploration_display_mode(socket)
      |> broadcast_scene_change()
    end)
  end

  def handle_event("select_add_ambient_flow", %{"id" => ""}, socket), do: {:noreply, socket}

  def handle_event("select_add_ambient_flow", %{"id" => flow_id}, socket) do
    Authorize.with_authorization(socket, :edit_content, fn _socket ->
      case Scenes.create_ambient_flow(socket.assigns.scene.id, %{
             "flow_id" => MapUtils.parse_int(flow_id)
           }) do
        {:ok, _} ->
          {:noreply, reload_ambient_flows(socket)}

        {:error, _} ->
          {:noreply, put_flash(socket, :error, dgettext("scenes", "Could not add ambient flow."))}
      end
    end)
  end

  def handle_event("add_ambient_flow", %{"flow_id" => ""}, socket), do: {:noreply, socket}

  def handle_event("add_ambient_flow", %{"flow_id" => flow_id}, socket) do
    Authorize.with_authorization(socket, :edit_content, fn _socket ->
      case Scenes.create_ambient_flow(socket.assigns.scene.id, %{
             "flow_id" => MapUtils.parse_int(flow_id)
           }) do
        {:ok, _} ->
          {:noreply, reload_ambient_flows(socket)}

        {:error, _} ->
          {:noreply, put_flash(socket, :error, dgettext("scenes", "Could not add ambient flow."))}
      end
    end)
  end

  def handle_event("remove_ambient_flow", %{"id" => id}, socket) do
    Authorize.with_authorization(socket, :edit_content, fn _socket ->
      {:noreply, do_remove_ambient_flow(socket, id)}
    end)
  end

  def handle_event("toggle_ambient_flow", %{"id" => id}, socket) do
    Authorize.with_authorization(socket, :edit_content, fn _socket ->
      {:noreply, do_toggle_ambient_flow(socket, id)}
    end)
  end

  def handle_event("reorder_ambient_flow", %{"id" => id, "direction" => direction}, socket) do
    Authorize.with_authorization(socket, :edit_content, fn _socket ->
      {:noreply, do_reorder_ambient_flow(socket, id, direction)}
    end)
  end

  def handle_event("update_ambient_flow_priority", %{"id" => af_id, "value" => value}, socket) do
    Authorize.with_authorization(socket, :edit_content, fn _socket ->
      {:noreply, update_ambient_flow_priority(socket, af_id, value)}
    end)
  end

  def handle_event("select_ambient_variable_ref:" <> af_id, %{"id" => variable_ref}, socket) do
    Authorize.with_authorization(socket, :edit_content, fn _socket ->
      params = %{"id" => af_id, "trigger_type" => "on_event", "variable_ref" => variable_ref}
      {:noreply, do_update_ambient_flow_trigger(socket, params)}
    end)
  end

  def handle_event("select_ambient_trigger_type:" <> af_id, %{"id" => trigger_type}, socket) do
    Authorize.with_authorization(socket, :edit_content, fn _socket ->
      params = %{"id" => af_id, "trigger_type" => trigger_type}
      {:noreply, do_update_ambient_flow_trigger(socket, params)}
    end)
  end

  def handle_event("update_ambient_flow_trigger", params, socket) do
    Authorize.with_authorization(socket, :edit_content, fn _socket ->
      {:noreply, do_update_ambient_flow_trigger(socket, params)}
    end)
  end

  def handle_event("toggle_pin_icon_upload", params, socket) do
    LayerHandlers.handle_toggle_pin_icon_upload(params, socket)
  end

  def handle_event("remove_pin_icon", params, socket) do
    Authorize.with_authorization(socket, :edit_content, fn _socket ->
      params |> LayerHandlers.handle_remove_pin_icon(socket) |> broadcast_scene_change()
    end)
  end

  # ---------------------------------------------------------------------------
  # Zone handlers — delegate to ElementHandlers
  # ---------------------------------------------------------------------------

  def handle_event("update_zone_vertices", params, socket) do
    Authorize.with_authorization(socket, :edit_content, fn _socket ->
      params |> ElementHandlers.handle_update_zone_vertices(socket) |> broadcast_scene_change()
    end)
  end

  def handle_event("duplicate_zone", params, socket) do
    Authorize.with_authorization(socket, :edit_content, fn _socket ->
      params |> ElementHandlers.handle_duplicate_zone(socket) |> broadcast_scene_change()
    end)
  end

  def handle_event("delete_zone", params, socket) do
    Authorize.with_authorization(socket, :edit_content, fn _socket ->
      params |> ElementHandlers.handle_delete_zone(socket) |> broadcast_scene_change()
    end)
  end

  def handle_event("update_zone_action_type", params, socket) do
    Authorize.with_authorization(socket, :edit_content, fn _socket ->
      params |> ElementHandlers.handle_update_zone_action_type(socket) |> broadcast_scene_change()
    end)
  end

  def handle_event("update_zone_assignments", params, socket) do
    Authorize.with_authorization(socket, :edit_content, fn _socket ->
      params |> ElementHandlers.handle_update_zone_assignments(socket) |> broadcast_scene_change()
    end)
  end

  def handle_event("select_zone_display_var:" <> zone_id, %{"id" => variable_ref}, socket) do
    Authorize.with_authorization(socket, :edit_content, fn _socket ->
      params = %{"zone-id" => zone_id, "field" => "variable_ref", "value" => variable_ref}
      params |> ElementHandlers.handle_update_zone_action_data(socket) |> broadcast_scene_change()
    end)
  end

  def handle_event("update_zone_action_data", params, socket) do
    Authorize.with_authorization(socket, :edit_content, fn _socket ->
      params |> ElementHandlers.handle_update_zone_action_data(socket) |> broadcast_scene_change()
    end)
  end

  def handle_event("update_zone_condition", params, socket) do
    Authorize.with_authorization(socket, :edit_content, fn _socket ->
      params |> ElementHandlers.handle_update_zone_condition(socket) |> broadcast_scene_change()
    end)
  end

  def handle_event("update_zone_condition_effect", %{"effect" => _} = params, socket) do
    Authorize.with_authorization(socket, :edit_content, fn _socket ->
      params
      |> ElementHandlers.handle_update_zone_condition_effect(socket)
      |> broadcast_scene_change()
    end)
  end

  def handle_event("add_collection_item", params, socket) do
    Authorize.with_authorization(socket, :edit_content, fn _socket ->
      params |> ElementHandlers.handle_add_collection_item(socket) |> broadcast_scene_change()
    end)
  end

  def handle_event("remove_collection_item", params, socket) do
    Authorize.with_authorization(socket, :edit_content, fn _socket ->
      params |> ElementHandlers.handle_remove_collection_item(socket) |> broadcast_scene_change()
    end)
  end

  def handle_event("update_collection_item", params, socket) do
    Authorize.with_authorization(socket, :edit_content, fn _socket ->
      params |> ElementHandlers.handle_update_collection_item(socket) |> broadcast_scene_change()
    end)
  end

  def handle_event("update_collection_item_condition", params, socket) do
    Authorize.with_authorization(socket, :edit_content, fn _socket ->
      params
      |> ElementHandlers.handle_update_collection_item_condition(socket)
      |> broadcast_scene_change()
    end)
  end

  def handle_event("update_collection_item_instruction", params, socket) do
    Authorize.with_authorization(socket, :edit_content, fn _socket ->
      params
      |> ElementHandlers.handle_update_collection_item_instruction(socket)
      |> broadcast_scene_change()
    end)
  end

  def handle_event("update_collection_settings", params, socket) do
    Authorize.with_authorization(socket, :edit_content, fn _socket ->
      params
      |> ElementHandlers.handle_update_collection_settings(socket)
      |> broadcast_scene_change()
    end)
  end

  # Expression editor tab toggle (Builder ↔ Code)
  def handle_event("toggle_expression_tab", %{"id" => id, "tab" => tab}, socket) do
    panel_sections = Map.put(socket.assigns.panel_sections, "tab_#{id}", tab)
    {:noreply, assign(socket, :panel_sections, panel_sections)}
  end

  # ---------------------------------------------------------------------------
  # Pin handlers — delegate to ElementHandlers
  # ---------------------------------------------------------------------------

  def handle_event("update_pin_condition", params, socket) do
    Authorize.with_authorization(socket, :edit_content, fn _socket ->
      params |> ElementHandlers.handle_update_pin_condition(socket) |> broadcast_scene_change()
    end)
  end

  def handle_event("update_pin_condition_effect", %{"effect" => _} = params, socket) do
    Authorize.with_authorization(socket, :edit_content, fn _socket ->
      params
      |> ElementHandlers.handle_update_pin_condition_effect(socket)
      |> broadcast_scene_change()
    end)
  end

  def handle_event("delete_pin", params, socket) do
    Authorize.with_authorization(socket, :edit_content, fn _socket ->
      params |> ElementHandlers.handle_delete_pin(socket) |> broadcast_scene_change()
    end)
  end

  # ---------------------------------------------------------------------------
  # Connection handlers — delegate to ElementHandlers
  # ---------------------------------------------------------------------------

  def handle_event("create_connection", params, socket) do
    Authorize.with_authorization(socket, :edit_content, fn _socket ->
      params |> ElementHandlers.handle_create_connection(socket) |> broadcast_scene_change()
    end)
  end

  def handle_event("delete_connection", params, socket) do
    Authorize.with_authorization(socket, :edit_content, fn _socket ->
      params |> ElementHandlers.handle_delete_connection(socket) |> broadcast_scene_change()
    end)
  end

  # ---------------------------------------------------------------------------
  # Annotation canvas handlers — delegate to ElementHandlers
  # ---------------------------------------------------------------------------

  def handle_event("create_annotation", params, socket) do
    Authorize.with_authorization(socket, :edit_content, fn _socket ->
      params |> ElementHandlers.handle_create_annotation(socket) |> broadcast_scene_change()
    end)
  end

  def handle_event("update_annotation", params, socket) do
    Authorize.with_authorization(socket, :edit_content, fn _socket ->
      params |> ElementHandlers.handle_update_annotation(socket) |> broadcast_scene_change()
    end)
  end

  def handle_event("move_annotation", params, socket) do
    Authorize.with_authorization(socket, :edit_content, fn _socket ->
      params |> ElementHandlers.handle_move_annotation(socket) |> broadcast_scene_change()
    end)
  end

  def handle_event("delete_annotation", params, socket) do
    Authorize.with_authorization(socket, :edit_content, fn _socket ->
      params |> ElementHandlers.handle_delete_annotation(socket) |> broadcast_scene_change()
    end)
  end

  def handle_event("set_pending_delete_annotation", params, socket) do
    Authorize.with_authorization(socket, :edit_content, fn _socket ->
      ElementHandlers.handle_set_pending_delete_annotation(params, socket)
    end)
  end

  # ---------------------------------------------------------------------------
  # Keyboard shortcut actions — delegate to ElementHandlers
  # ---------------------------------------------------------------------------

  def handle_event("delete_selected", _params, socket) do
    Authorize.with_authorization(socket, :edit_content, fn _socket ->
      socket |> ElementHandlers.handle_delete_selected() |> broadcast_scene_change()
    end)
  end

  def handle_event("duplicate_selected", _params, socket) do
    Authorize.with_authorization(socket, :edit_content, fn _socket ->
      socket |> ElementHandlers.handle_duplicate_selected() |> broadcast_scene_change()
    end)
  end

  def handle_event("copy_selected", _params, socket) do
    ElementHandlers.handle_copy_selected(socket)
  end

  def handle_event("paste_element", params, socket) do
    Authorize.with_authorization(socket, :edit_content, fn _socket ->
      params |> ElementHandlers.handle_paste_element(socket) |> broadcast_scene_change()
    end)
  end

  # ---------------------------------------------------------------------------
  # Undo / Redo — delegate to UndoRedoHandlers
  # ---------------------------------------------------------------------------

  def handle_event("undo", params, socket) do
    Authorize.with_authorization(socket, :edit_content, fn _socket ->
      params |> UndoRedoHandlers.handle_undo(socket) |> broadcast_scene_change()
    end)
  end

  def handle_event("redo", params, socket) do
    Authorize.with_authorization(socket, :edit_content, fn _socket ->
      params |> UndoRedoHandlers.handle_redo(socket) |> broadcast_scene_change()
    end)
  end

  # ---------------------------------------------------------------------------
  # Target navigation — delegate to TreeHandlers
  # ---------------------------------------------------------------------------

  def handle_event("navigate_to_target", params, socket) do
    TreeHandlers.handle_navigate_to_target(params, socket)
  end

  def handle_event("navigate_to_referencing_flow", %{"flow-id" => flow_id}, socket) do
    case Storyarn.Flows.get_flow_brief(socket.assigns.project.id, flow_id) do
      nil ->
        {:noreply, put_flash(socket, :error, dgettext("scenes", "Flow not found."))}

      _flow ->
        {:noreply,
         push_navigate(socket,
           to: ~p"/workspaces/#{socket.assigns.workspace.slug}/projects/#{socket.assigns.project.slug}/flows/#{flow_id}"
         )}
    end
  end

  # ---------------------------------------------------------------------------
  # Sidebar tree event handlers
  #
  # `create_scene`, `create_child_scene`, `set_pending_delete_scene`,
  # `confirm_delete_scene`, `delete_scene`, `move_to_parent` now live in
  # `SceneSidebarLive` — they never reach this LV because the tree is
  # rendered by that separate sticky sidebar. Only `create_child_scene_from_zone`
  # stays because it's fired from the canvas zone context menu, not the tree.
  # ---------------------------------------------------------------------------

  def handle_event("create_child_scene_from_zone", params, socket) do
    Authorize.with_authorization(socket, :edit_content, fn _socket ->
      params |> TreeHandlers.handle_create_child_scene_from_zone(socket) |> broadcast_scene_change()
    end)
  end

  # ---------------------------------------------------------------------------
  # handle_info callbacks
  # ---------------------------------------------------------------------------

  @impl true
  def handle_async(:load_sidebar_data, {:ok, data}, socket) do
    {:noreply,
     socket
     |> assign(:project_scenes, data.project_scenes)
     |> assign(:project_sheets, data.project_sheets)
     |> assign(:project_flows, data.project_flows)
     |> assign(:project_variables, data.project_variables)
     |> assign(:sidebar_loaded, true)}
  end

  def handle_async(:load_sidebar_data, {:exit, _reason}, socket) do
    {:noreply, assign(socket, :sidebar_loaded, true)}
  end

  @impl true
  def handle_info({:EXIT, _pid, :normal}, socket), do: {:noreply, socket}

  def handle_info({:entity_selected, "pin-sheet-" <> _, sheet_id}, socket) do
    Authorize.with_authorization(socket, :edit_content, fn _socket ->
      pin = socket.assigns.selected_element

      case Scenes.update_pin(pin, %{"sheet_id" => sheet_id}) do
        {:ok, updated} ->
          updated = Scenes.preload_pin_associations(updated)

          {:noreply,
           socket
           |> assign(:selected_element, updated)
           |> assign(:pins, replace_in_list(socket.assigns.pins, updated))
           |> push_event("pin_updated", serialize_pin(updated))
           |> assign(:_broadcast, {:pin_updated, %{id: updated.id}})}

        {:error, _} ->
          {:noreply, put_flash(socket, :error, dgettext("scenes", "Could not update pin."))}
      end
    end)
  end

  def handle_info({:entity_selected, "pin-flow-" <> _, flow_id}, socket) do
    Authorize.with_authorization(socket, :edit_content, fn _socket ->
      pin = socket.assigns.selected_element

      case Scenes.update_pin(pin, %{"flow_id" => flow_id}) do
        {:ok, updated} ->
          updated = Scenes.preload_pin_associations(updated)

          {:noreply,
           socket
           |> assign(:selected_element, updated)
           |> assign(:pins, replace_in_list(socket.assigns.pins, updated))
           |> push_event("pin_updated", serialize_pin(updated))
           |> assign(:_broadcast, {:pin_updated, %{id: updated.id}})}

        {:error, _} ->
          {:noreply, put_flash(socket, :error, dgettext("scenes", "Could not update pin."))}
      end
    end)
  end

  def handle_info({:entity_selected, "collection-item-sheet-" <> rest, sheet_id}, socket) do
    Authorize.with_authorization(socket, :edit_content, fn _socket ->
      [zone_id, item_id] = String.split(rest, "-", parts: 2)

      %{
        "zone-id" => zone_id,
        "item-id" => item_id,
        "field" => "sheet_id",
        "value" => if(sheet_id, do: to_string(sheet_id), else: "")
      }
      |> ElementHandlers.handle_update_collection_item(socket)
      |> broadcast_scene_change()
    end)
  end

  def handle_info({:pin_icon_uploaded, asset}, socket) do
    case socket.assigns[:selected_element] do
      %{__struct__: Storyarn.Scenes.ScenePin} = pin ->
        case Scenes.update_pin(pin, %{"icon_asset_id" => asset.id}) do
          {:ok, updated} ->
            updated = Scenes.preload_pin_associations(updated)

            broadcast_scene_change(
              {:noreply,
               socket
               |> assign(:selected_element, updated)
               |> update_pin_in_list(updated)
               |> assign(:show_pin_icon_upload, false)
               |> assign(:_broadcast, {:pin_updated, %{id: updated.id}})
               |> push_event("pin_updated", serialize_pin(updated))
               |> put_flash(:info, dgettext("scenes", "Pin icon updated."))}
            )

          {:error, _} ->
            {:noreply, put_flash(socket, :error, dgettext("scenes", "Could not update pin icon."))}
        end

      _ ->
        {:noreply, socket}
    end
  end

  @impl true
  def handle_info({:try_auto_snapshot, token}, socket) do
    if token == socket.assigns[:auto_snapshot_ref] do
      %{scene: scene, current_scope: scope} = socket.assigns
      Scenes.maybe_create_version(scene, scope.user.id)
      {:noreply, socket |> assign(:auto_snapshot_ref, nil) |> assign(:auto_snapshot_timer, nil)}
    else
      {:noreply, socket}
    end
  end

  # ---------------------------------------------------------------------------
  # Handle Info: Version History
  # ---------------------------------------------------------------------------

  @impl true
  def handle_info({:project_restoration_started, payload}, socket),
    do: RestorationHandlers.handle_restoration_event({:project_restoration_started, payload}, socket)

  @impl true
  def handle_info({:project_restoration_completed, payload}, socket),
    do: RestorationHandlers.handle_restoration_event({:project_restoration_completed, payload}, socket)

  @impl true
  def handle_info({:project_restoration_failed, payload}, socket),
    do: RestorationHandlers.handle_restoration_event({:project_restoration_failed, payload}, socket)

  # ---------------------------------------------------------------------------
  # Handle Info: Collaboration
  # ---------------------------------------------------------------------------

  def handle_info({Presence, {:join, presence}}, socket) do
    Collab.handle_presence_join(socket, presence)
  end

  def handle_info({Presence, {:leave, _} = event}, socket) do
    Collab.handle_presence_leave(socket, elem(event, 1))
  end

  def handle_info({:cursor_update, cursor_data}, socket) do
    if cursor_data.user_id == socket.assigns.current_scope.user.id do
      {:noreply, socket}
    else
      {:noreply, push_event(socket, "cursor_update", cursor_data)}
    end
  end

  def handle_info({:cursor_leave, user_id}, socket) do
    {:noreply, push_event(socket, "cursor_leave", %{user_id: user_id})}
  end

  def handle_info({:lock_change, _action, _payload}, socket) do
    CollaborationHandlers.handle_lock_change(socket)
  end

  def handle_info({:remote_change, action, payload}, socket) do
    CollaborationHandlers.handle_remote_change(action, payload, socket)
  end

  # ---------------------------------------------------------------------------
  # Shell topic messages (ProjectLayout + SceneSidebarLive)
  # ---------------------------------------------------------------------------

  # Broadcast from handle_params of this LV; the sidebar listens too. Noop for
  # Show since it owns the scene state already. Sibling active_* messages
  # travel on the same shell topic when multiple tools share a project — swallow
  # them so they don't crash the LV with FunctionClauseError.
  def handle_info({:active_scene, _scene_id}, socket), do: {:noreply, socket}
  def handle_info({:active_sheet, _sheet_id}, socket), do: {:noreply, socket}
  def handle_info({:active_flow, _flow_id}, socket), do: {:noreply, socket}
  def handle_info({:active_locale, _locale}, socket), do: {:noreply, socket}

  # Sidebar → page; Index picks it up on tree-create navigation. Ignored in Show.
  def handle_info({:open_scene, _id}, socket), do: {:noreply, socket}

  # Tree mutations in the sidebar LV broadcast this; Show doesn't own the tree.
  def handle_info({:tree_changed, :scenes}, socket), do: {:noreply, socket}

  def handle_info({:entity_deleted, id}, socket) do
    if to_string(id) == to_string(socket.assigns.scene.id) do
      {:noreply,
       push_navigate(socket,
         to: ~p"/workspaces/#{socket.assigns.workspace.slug}/projects/#{socket.assigns.project.slug}/scenes"
       )}
    else
      {:noreply, socket}
    end
  end

  def handle_info({:toolbar_event, _event, _params}, socket), do: {:noreply, socket}

  def handle_info({:online_users, users}, socket), do: {:noreply, assign(socket, :online_users, users)}

  @impl true
  def handle_info(:refresh_locks, socket) do
    with scope when not is_nil(scope) <- socket.assigns[:collab_scope],
         %{id: element_id} <- socket.assigns[:selected_element] do
      user_id = socket.assigns.current_scope.user.id
      Collaboration.refresh_lock(scope, element_id, user_id)
    end

    {:noreply, schedule_lock_heartbeat(socket)}
  end

  @impl true
  def terminate(_reason, socket) do
    teardown_scene_collab(socket)
  end

  # ---------------------------------------------------------------------------
  # Private helpers: Collaboration
  # ---------------------------------------------------------------------------

  defp teardown_scene_collab(socket) do
    if ref = socket.assigns[:lock_heartbeat_ref], do: Process.cancel_timer(ref)

    if scope = socket.assigns[:collab_scope] do
      user_id = socket.assigns.current_scope.user.id
      Collab.teardown(scope, user_id)
    end

    socket
  end

  defp schedule_lock_heartbeat(socket) do
    if ref = socket.assigns[:lock_heartbeat_ref], do: Process.cancel_timer(ref)
    ref = Process.send_after(self(), :refresh_locks, @lock_heartbeat_interval)
    assign(socket, :lock_heartbeat_ref, ref)
  end

  defp maybe_acquire_lock({:noreply, socket}, id) do
    scope = socket.assigns[:collab_scope]
    parsed_id = parse_element_id(id)

    if socket.assigns.can_edit && scope && parsed_id do
      user = socket.assigns.current_scope.user

      case Collaboration.acquire_lock(scope, parsed_id, user) do
        {:ok, _} ->
          Collab.broadcast_lock_change(socket, scope, :locked, parsed_id)

        {:error, :already_locked, _lock_info} ->
          :ok
      end
    end

    {:noreply, socket}
  end

  defp release_element_lock(socket) do
    with %{id: element_id} <- socket.assigns[:selected_element],
         scope when not is_nil(scope) <- socket.assigns[:collab_scope] do
      user_id = socket.assigns.current_scope.user.id
      Collaboration.release_lock(scope, element_id, user_id)
      Collab.broadcast_lock_change(socket, scope, :unlocked, element_id)
    end

    :ok
  end

  defp parse_element_id(id) when is_integer(id), do: id

  defp parse_element_id(id) when is_binary(id) do
    case Integer.parse(id) do
      {int, ""} -> int
      _ -> nil
    end
  end

  defp parse_element_id(_), do: nil

  defp reload_history_data(socket) do
    VersionHistoryHelpers.load_history_data(
      socket,
      "scene",
      socket.assigns.scene,
      socket.assigns.project.id,
      socket.assigns.workspace.id
    )
  end

  defp maybe_track_version_panel_opened(socket, entity_type) do
    if socket.assigns[:right_panel] != :versions do
      Analytics.track(socket.assigns.current_scope, "version panel opened", %{
        entity_type: entity_type,
        project_id: socket.assigns.project.id
      })
    end
  end

  defp scene_version_config do
    %{
      entity_type: "scene",
      entity_key: :scene,
      reload_history: &reload_history_data/1,
      restore_path: &scene_restore_path/1,
      compare_path: &scene_compare_path/2
    }
  end

  defp scene_restore_path(socket) do
    %{workspace: workspace, project: project, scene: scene} = socket.assigns
    ~p"/workspaces/#{workspace.slug}/projects/#{project.slug}/scenes/#{scene.id}"
  end

  defp scene_compare_path(socket, version_number) do
    %{workspace: workspace, project: project, scene: scene} = socket.assigns
    ~p"/workspaces/#{workspace.slug}/projects/#{project.slug}/scenes/#{scene.id}/compare/#{version_number}"
  end

  defp broadcast_scene_change({:noreply, socket} = _result) do
    {action, payload} =
      socket.assigns[:_broadcast] || {:scene_refreshed, %{}}

    if scope = socket.assigns[:collab_scope] do
      Collab.broadcast_change(socket, scope, action, payload)
    end

    {:noreply, assign(socket, :_broadcast, nil)}
  end

  # ---------------------------------------------------------------------------
  # Private helpers
  # ---------------------------------------------------------------------------

  defp maybe_allow_background_upload(socket, false), do: socket

  defp maybe_allow_background_upload(socket, true) do
    allow_upload(socket, :background,
      accept: ~w(image/jpeg image/png image/gif image/webp),
      max_entries: 1,
      max_file_size: 52_428_800,
      auto_upload: true,
      progress: fn name, entry, socket -> handle_progress(name, entry, socket) end
    )
  end

  defp handle_progress(:background, entry, socket) do
    if entry.done? do
      socket
      |> consume_uploaded_entries(:background, &consume_background_entry(&1, &2, socket))
      |> handle_background_result(socket)
    else
      {:noreply, socket}
    end
  end

  defp consume_background_entry(%{path: path}, entry, socket) do
    case Assets.upload_and_create_asset(
           path,
           entry,
           socket.assigns.project,
           socket.assigns.current_scope.user,
           purpose: :scene_background
         ) do
      {:ok, asset} -> {:ok, {:ok, asset}}
      {:error, reason} -> {:ok, {:error, reason}}
    end
  end

  defp handle_background_result([{:ok, asset}], socket), do: process_background_upload(socket, asset)

  defp handle_background_result(_results, socket),
    do: {:noreply, put_flash(socket, :error, dgettext("scenes", "Could not upload background."))}

  defp process_background_upload(socket, asset) do
    case Scenes.update_scene(socket.assigns.scene, %{background_asset_id: asset.id}) do
      {:ok, updated} ->
        updated = Scenes.preload_scene_background(updated)
        Collaboration.broadcast_change({:assets, socket.assigns.project.id}, :asset_created, %{})

        broadcast_scene_change(
          {:noreply,
           socket
           |> assign(:scene, updated)
           |> assign(:_broadcast, {:layer_updated, %{}})
           |> push_event("background_changed", %{url: PrivateMedia.asset_url(asset)})
           |> put_flash(:info, dgettext("scenes", "Background image updated."))}
        )

      {:error, _} ->
        {:noreply, put_flash(socket, :error, dgettext("scenes", "Could not update background."))}
    end
  end

  defp background_set?(%{background_asset_id: id}) when not is_nil(id), do: true
  defp background_set?(_), do: false

  defp maybe_update_selected_zone(
         %{assigns: %{selected_type: "zone", selected_element: %{id: id}}} = socket,
         %{id: id} = zone
       ) do
    assign(socket, :selected_element, zone)
  end

  defp maybe_update_selected_zone(socket, _zone), do: socket

  defp maybe_update_selected_pin(
         %{assigns: %{selected_type: "pin", selected_element: %{id: id}}} = socket,
         %{id: id} = pin
       ) do
    assign(socket, :selected_element, pin)
  end

  defp maybe_update_selected_pin(socket, _pin), do: socket

  defp validate_zone_label_icon_type(filename, content_type) do
    extension = filename |> Path.extname() |> String.downcase()

    cond do
      content_type not in @zone_label_icon_content_types ->
        {:error, zone_label_icon_invalid_type_message()}

      extension not in @zone_label_icon_extensions ->
        {:error, zone_label_icon_invalid_type_message()}

      true ->
        :ok
    end
  end

  defp upload_scene_icon_asset(icon_binary, filename, "image/svg+xml", socket) do
    Assets.upload_sanitized_svg_and_create_asset(
      icon_binary,
      %{filename: filename, content_type: "image/svg+xml"},
      socket.assigns.project,
      socket.assigns.current_scope.user
    )
  end

  defp upload_scene_icon_asset(icon_binary, filename, content_type, socket) do
    Assets.upload_binary_and_create_asset(
      icon_binary,
      %{filename: filename, content_type: content_type},
      socket.assigns.project,
      socket.assigns.current_scope.user
    )
  end

  defp validate_zone_label_icon_size(binary) when byte_size(binary) <= @zone_label_icon_max_size, do: :ok

  defp validate_zone_label_icon_size(_binary) do
    {:error, zone_label_icon_too_large_message()}
  end

  defp validate_zone_label_icon_binary("image/png", <<137, 80, 78, 71, 13, 10, 26, 10, _::binary>> = binary),
    do: {:ok, binary}

  defp validate_zone_label_icon_binary("image/gif", <<"GIF87a", _::binary>> = binary), do: {:ok, binary}
  defp validate_zone_label_icon_binary("image/gif", <<"GIF89a", _::binary>> = binary), do: {:ok, binary}

  defp validate_zone_label_icon_binary("image/svg+xml", binary) do
    with true <- String.valid?(binary),
         svg = binary |> strip_utf8_bom() |> String.trim(),
         true <- svg_root?(svg),
         sanitized = HtmlSanitizer.sanitize_html(svg),
         true <- svg_root?(sanitized),
         true <- byte_size(sanitized) <= @zone_label_icon_max_size do
      {:ok, sanitized}
    else
      _ -> {:error, zone_label_icon_invalid_type_message()}
    end
  end

  defp validate_zone_label_icon_binary(_content_type, _binary) do
    {:error, zone_label_icon_invalid_type_message()}
  end

  defp strip_utf8_bom(<<0xEF, 0xBB, 0xBF, rest::binary>>), do: rest
  defp strip_utf8_bom(binary), do: binary

  defp svg_root?(svg) when is_binary(svg) do
    case Floki.parse_fragment(svg) do
      {:ok, nodes} -> nodes |> Floki.find("svg") |> Enum.any?()
      _ -> false
    end
  end

  defp zone_label_icon_invalid_type_message do
    dgettext("scenes", "Only SVG, PNG, or GIF icons are allowed.")
  end

  defp zone_label_icon_too_large_message do
    dgettext("scenes", "Icon is too large. Maximum size is 256 KB.")
  end

  defp upload_error_to_message(errors) do
    cond do
      :too_large in errors ->
        dgettext("scenes", "File is too large. Maximum size is 50 MB.")

      :not_accepted in errors ->
        dgettext(
          "scenes",
          "File type not supported. Please upload a JPEG, PNG, GIF, or WebP image."
        )

      true ->
        dgettext("scenes", "Could not upload file.")
    end
  end
end
