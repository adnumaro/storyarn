defmodule StoryarnWeb.MapLive.Show do
  @moduledoc false

  use StoryarnWeb, :live_view
  use StoryarnWeb.Helpers.Authorize

  import StoryarnWeb.Layouts, only: [flash_group: 1]
  import StoryarnWeb.MapLive.Components.Dock
  import StoryarnWeb.MapLive.Components.LayerBar
  import StoryarnWeb.MapLive.Components.Legend
  import StoryarnWeb.MapLive.Components.MapHeader
  import StoryarnWeb.MapLive.Components.MapSearchPanel
  import StoryarnWeb.MapLive.Components.MapPanel
  import StoryarnWeb.MapLive.Components.FloatingToolbar

  alias Storyarn.Maps
  alias Storyarn.Projects
  alias Storyarn.Repo

  import StoryarnWeb.MapLive.Helpers.MapHelpers
  import StoryarnWeb.MapLive.Helpers.Serializer

  alias StoryarnWeb.MapLive.Handlers.CanvasEventHandlers
  alias StoryarnWeb.MapLive.Handlers.ElementHandlers
  alias StoryarnWeb.MapLive.Handlers.LayerHandlers
  alias StoryarnWeb.MapLive.Handlers.TreeHandlers
  alias StoryarnWeb.MapLive.Handlers.UndoRedoHandlers

  @impl true
  def render(assigns) do
    ~H"""
    <div class="h-screen flex flex-col">
      <.map_header
        map={@map}
        ancestors={@ancestors}
        workspace={@workspace}
        project={@project}
        can_edit={@can_edit}
        edit_mode={@edit_mode}
        referencing_flows={@referencing_flows}
      />

      <%!-- Canvas area (full width — no sidebar) --%>
      <div class="flex-1 relative overflow-hidden">
        <div
          id="map-canvas"
          phx-hook="MapCanvas"
          phx-update="ignore"
          data-map={Jason.encode!(@map_data)}
          data-i18n={Jason.encode!(@canvas_i18n)}
          class="w-full h-full"
        >
          <div id="map-canvas-container" class="w-full h-full"></div>
        </div>

        <%!-- Top-left panel: Search + Layers --%>
        <div class="absolute top-3 left-3 z-[1000] flex flex-col gap-2 w-64">
          <.map_search_panel
            search_query={@search_query}
            search_filter={@search_filter}
            search_results={@search_results}
          />

          <%!-- Layer bar --%>
          <.layer_bar
            layers={@layers}
            active_layer_id={@active_layer_id}
            renaming_layer_id={@renaming_layer_id}
            can_edit={@can_edit}
            edit_mode={@edit_mode}
          />
        </div>

        <%!-- Bottom dock (edit mode only) --%>
        <.dock :if={@edit_mode} active_tool={@active_tool} pending_sheet={@pending_sheet_for_pin} />

        <%!-- Sheet picker overlay --%>
        <div
          :if={@show_sheet_picker}
          id="sheet-picker"
          class="absolute bottom-32 left-1/2 -translate-x-1/2 z-[1001] w-72 bg-base-100 rounded-lg border border-base-300 shadow-lg overflow-hidden"
        >
          <div class="p-2 border-b border-base-300 flex items-center justify-between">
            <span class="text-xs font-medium">{dgettext("maps", "Select a sheet")}</span>
            <button
              type="button"
              phx-click="cancel_sheet_picker"
              class="btn btn-ghost btn-xs btn-square"
            >
              <.icon name="x" class="size-3" />
            </button>
          </div>
          <div class="max-h-60 overflow-y-auto p-1">
            <.sheet_picker_list sheets={flatten_sheets(@project_sheets)} />
          </div>
        </div>

        <%!-- Flash messages overlay --%>
        <div class="absolute top-2 left-1/2 -translate-x-1/2 z-[1100]">
          <.flash_group flash={@flash} />
        </div>

        <%!-- Legend --%>
        <.legend
          pins={@pins}
          zones={@zones}
          connections={@connections}
          legend_open={@legend_open}
        />

        <%!-- Floating element toolbar --%>
        <div
          :if={@selected_element && @can_edit && @edit_mode}
          id="floating-toolbar-content"
          phx-hook="FloatingToolbar"
          class="absolute z-[1050]"
        >
          <.floating_toolbar
            selected_type={@selected_type}
            selected_element={@selected_element}
            layers={@layers}
            can_edit={not Map.get(@selected_element || %{}, :locked, false)}
            can_toggle_lock={true}
            project_maps={@project_maps}
            project_sheets={@project_sheets}
            project_flows={@project_flows}
            project_variables={@project_variables}
          />
        </div>

        <%!-- Pin icon upload overlay --%>
        <div
          :if={@show_pin_icon_upload && @selected_type == "pin" && @project && @current_scope}
          class="absolute top-3 right-3 z-[1060] w-64 bg-base-100 rounded-xl border border-base-300 shadow-xl p-3"
        >
          <div class="flex items-center justify-between mb-2">
            <span class="text-xs font-medium">{dgettext("maps", "Upload Icon")}</span>
            <button
              type="button"
              phx-click="toggle_pin_icon_upload"
              class="btn btn-ghost btn-xs btn-square"
            >
              <.icon name="x" class="size-3" />
            </button>
          </div>
          <.live_component
            module={StoryarnWeb.Components.AssetUpload}
            id="pin-icon-upload"
            project={@project}
            current_user={@current_scope.user}
            on_upload={fn asset -> send(self(), {:pin_icon_uploaded, asset}) end}
            accept={~w(image/jpeg image/png image/gif image/webp image/svg+xml)}
            max_entries={1}
            max_file_size={524_288}
          />
        </div>

        <%!-- Map settings floating panel (gear button) --%>
        <div
          id="map-settings-floating"
          class="hidden absolute top-3 right-3 z-[1000] w-72 max-h-[calc(100vh-8rem)]
                   overflow-y-auto bg-base-100 rounded-xl border border-base-300 shadow-xl"
          phx-click-away={JS.add_class("hidden", to: "#map-settings-floating")}
        >
          <div class="p-3 border-b border-base-300 flex items-center justify-between">
            <h2 class="font-medium text-sm flex items-center gap-2">
              <.icon name="settings" class="size-4" />
              {dgettext("maps", "Map Settings")}
            </h2>
            <button
              type="button"
              class="btn btn-ghost btn-xs btn-square"
              phx-click={JS.add_class("hidden", to: "#map-settings-floating")}
            >
              <.icon name="x" class="size-4" />
            </button>
          </div>
          <div :if={@can_edit && @edit_mode} class="p-3">
            <.map_properties
              map={@map}
              show_background_upload={@show_background_upload}
              project={@project}
              current_user={@current_scope.user}
            />
          </div>
        </div>
      </div>

      <%!-- Confirm modals --%>
      <.confirm_modal
        :if={@can_edit}
        id="delete-map-show-confirm"
        title={dgettext("maps", "Delete map?")}
        message={dgettext("maps", "Are you sure you want to delete this map?")}
        confirm_text={dgettext("maps", "Delete")}
        confirm_variant="error"
        icon="alert-triangle"
        on_confirm={JS.push("confirm_delete_map")}
      />

      <.confirm_modal
        :if={@can_edit}
        id="delete-layer-confirm"
        title={dgettext("maps", "Delete layer?")}
        message={
          dgettext(
            "maps",
            "This layer will be deleted. All elements on this layer will be moved to no layer."
          )
        }
        confirm_text={dgettext("maps", "Delete")}
        confirm_variant="error"
        icon="alert-triangle"
        on_confirm={JS.push("confirm_delete_layer")}
      />
    </div>
    """
  end

  @impl true
  def mount(
        %{
          "workspace_slug" => workspace_slug,
          "project_slug" => project_slug,
          "id" => map_id
        },
        _session,
        socket
      ) do
    case Projects.get_project_by_slugs(
           socket.assigns.current_scope,
           workspace_slug,
           project_slug
         ) do
      {:ok, project, membership} ->
        project = Repo.preload(project, :workspace)
        can_edit = Projects.ProjectMembership.can?(membership.role, :edit_content)

        case Maps.get_map(project.id, map_id) do
          nil ->
            {:ok,
             socket
             |> put_flash(:error, dgettext("maps", "Map not found."))
             |> redirect(
               to: ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/maps"
             )}

          map ->
            {:ok, mount_map(socket, project, membership, can_edit, map)}
        end

      {:error, _reason} ->
        {:ok,
         socket
         |> put_flash(:error, dgettext("maps", "You don't have access to this project."))
         |> redirect(to: ~p"/workspaces")}
    end
  end

  defp mount_map(socket, project, membership, can_edit, map) do
    maps_tree = Maps.list_maps_tree_with_elements(project.id)

    socket
    |> assign(:project, project)
    |> assign(:workspace, project.workspace)
    |> assign(:membership, membership)
    |> assign(:can_edit, can_edit)
    |> assign(:map, map)
    |> assign(:ancestors, Maps.list_ancestors(map))
    |> assign(:maps_tree, maps_tree)
    |> assign(:layers, map.layers || [])
    |> assign(:zones, map.zones || [])
    |> assign(:pins, map.pins || [])
    |> assign(:connections, map.connections || [])
    |> assign(:annotations, map.annotations || [])
    |> assign(:map_data, build_map_data(map, can_edit))
    |> assign(:edit_mode, can_edit)
    |> assign(:active_tool, :select)
    |> assign(:selected_element, nil)
    |> assign(:selected_type, nil)
    |> assign(:active_layer_id, default_layer_id(map.layers))
    |> assign(:renaming_layer_id, nil)
    |> assign(:show_background_upload, false)
    |> assign(:show_pin_icon_upload, false)
    |> assign(:show_sheet_picker, false)
    |> assign(:pending_sheet_for_pin, nil)
    |> assign(:search_query, "")
    |> assign(:search_filter, "all")
    |> assign(:search_results, [])
    |> assign(:legend_open, false)
    |> assign(:undo_stack, [])
    |> assign(:redo_stack, [])
    |> assign(:project_maps, Maps.list_maps(project.id))
    |> assign(:project_sheets, Storyarn.Sheets.list_sheets_tree(project.id))
    |> assign(:project_flows, Storyarn.Flows.list_flows(project.id))
    |> assign(:project_variables, Storyarn.Sheets.list_project_variables(project.id))
    |> assign(:referencing_flows, Storyarn.Flows.list_interaction_nodes_for_map(map.id))
    |> assign(:canvas_i18n, %{
      edit_properties: dgettext("maps", "Edit Properties"),
      connect_to: dgettext("maps", "Connect To\u2026"),
      edit_vertices: dgettext("maps", "Edit Vertices"),
      duplicate: dgettext("maps", "Duplicate"),
      bring_to_front: dgettext("maps", "Bring to Front"),
      send_to_back: dgettext("maps", "Send to Back"),
      lock: dgettext("maps", "Lock"),
      unlock: dgettext("maps", "Unlock"),
      delete: dgettext("maps", "Delete"),
      add_pin: dgettext("maps", "Add Pin Here"),
      add_annotation: dgettext("maps", "Add Annotation Here"),
      create_child_map: dgettext("maps", "Create child map"),
      name_zone_first: dgettext("maps", "Name the zone first")
    })
  end

  @impl true
  def handle_params(params, _url, socket) do
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

  defp parse_highlight_id(id) do
    case Integer.parse(id) do
      {int, ""} -> int
      _ -> nil
    end
  end

  @valid_tools ~w(select pan rectangle triangle circle freeform pin annotation connector ruler)

  @impl true
  def handle_event("save_name", params, socket) do
    with_auth(socket, :edit_content, fn ->
      CanvasEventHandlers.handle_save_name(params, socket)
    end)
  end

  def handle_event("set_tool", %{"tool" => tool} = params, socket) when tool in @valid_tools do
    CanvasEventHandlers.handle_set_tool(params["tool"], socket)
  end

  def handle_event("set_tool", _params, socket), do: {:noreply, socket}

  def handle_event("export_map", %{"format" => format}, socket) when format in ~w(png svg) do
    CanvasEventHandlers.handle_export_map(format, socket)
  end

  def handle_event("export_map", _params, socket), do: {:noreply, socket}

  def handle_event("toggle_edit_mode", params, socket) do
    with_auth(socket, :edit_content, fn ->
      CanvasEventHandlers.handle_toggle_edit_mode(socket, params)
    end)
  end

  def handle_event("search_elements", params, socket) do
    CanvasEventHandlers.handle_search_elements(params, socket)
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

  def handle_event("select_element", %{"type" => type} = params, socket)
      when type in ~w(pin zone connection annotation) do
    CanvasEventHandlers.handle_select_element(params, socket)
  end

  def handle_event("noop", _params, socket), do: {:noreply, socket}

  def handle_event("deselect", _params, socket) do
    CanvasEventHandlers.handle_deselect(socket)
  end

  # ---------------------------------------------------------------------------
  # Property panel update handlers — delegate to ElementHandlers
  # ---------------------------------------------------------------------------

  def handle_event("update_pin", params, socket) do
    with_auth(socket, :edit_content, fn ->
      ElementHandlers.handle_update_pin(params, socket)
    end)
  end

  def handle_event("update_zone", params, socket) do
    with_auth(socket, :edit_content, fn ->
      ElementHandlers.handle_update_zone(params, socket)
    end)
  end

  def handle_event("update_connection", params, socket) do
    with_auth(socket, :edit_content, fn ->
      ElementHandlers.handle_update_connection(params, socket)
    end)
  end

  def handle_event("update_connection_waypoints", params, socket) do
    with_auth(socket, :edit_content, fn ->
      ElementHandlers.handle_update_connection_waypoints(params, socket)
    end)
  end

  def handle_event("clear_connection_waypoints", params, socket) do
    with_auth(socket, :edit_content, fn ->
      ElementHandlers.handle_clear_connection_waypoints(params, socket)
    end)
  end

  def handle_event("set_pending_delete_pin", params, socket) do
    with_auth(socket, :edit_content, fn ->
      ElementHandlers.handle_set_pending_delete_pin(params, socket)
    end)
  end

  def handle_event("set_pending_delete_zone", params, socket) do
    with_auth(socket, :edit_content, fn ->
      ElementHandlers.handle_set_pending_delete_zone(params, socket)
    end)
  end

  def handle_event("set_pending_delete_connection", params, socket) do
    with_auth(socket, :edit_content, fn ->
      ElementHandlers.handle_set_pending_delete_connection(params, socket)
    end)
  end

  def handle_event("confirm_delete_element", params, socket) do
    with_auth(socket, :edit_content, fn ->
      ElementHandlers.handle_confirm_delete_element(params, socket)
    end)
  end

  # ---------------------------------------------------------------------------
  # Pin canvas handlers — delegate to ElementHandlers
  # ---------------------------------------------------------------------------

  def handle_event("create_pin", params, socket) do
    with_auth(socket, :edit_content, fn ->
      ElementHandlers.handle_create_pin(params, socket)
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
    with_auth(socket, :edit_content, fn ->
      ElementHandlers.handle_create_pin_from_sheet(params, socket)
    end)
  end

  def handle_event("move_pin", params, socket) do
    with_auth(socket, :edit_content, fn ->
      ElementHandlers.handle_move_pin(params, socket)
    end)
  end

  # ---------------------------------------------------------------------------
  # Zone canvas handlers — delegate to ElementHandlers
  # ---------------------------------------------------------------------------

  def handle_event("create_zone", params, socket) do
    with_auth(socket, :edit_content, fn ->
      ElementHandlers.handle_create_zone(params, socket)
    end)
  end

  # ---------------------------------------------------------------------------
  # Layer handlers — delegate to LayerHandlers
  # ---------------------------------------------------------------------------

  def handle_event("create_layer", params, socket) do
    with_auth(socket, :edit_content, fn ->
      LayerHandlers.handle_create_layer(params, socket)
    end)
  end

  def handle_event("set_active_layer", params, socket) do
    LayerHandlers.handle_set_active_layer(params, socket)
  end

  def handle_event("toggle_layer_visibility", params, socket) do
    with_auth(socket, :edit_content, fn ->
      LayerHandlers.handle_toggle_layer_visibility(params, socket)
    end)
  end

  def handle_event("update_layer_fog", params, socket) do
    with_auth(socket, :edit_content, fn ->
      LayerHandlers.handle_update_layer_fog(params, socket)
    end)
  end

  def handle_event("start_rename_layer", params, socket) do
    LayerHandlers.handle_start_rename_layer(params, socket)
  end

  def handle_event("rename_layer", params, socket) do
    with_auth(socket, :edit_content, fn ->
      LayerHandlers.handle_rename_layer(params, socket)
    end)
  end

  def handle_event("set_pending_delete_layer", params, socket) do
    with_auth(socket, :edit_content, fn ->
      LayerHandlers.handle_set_pending_delete_layer(params, socket)
    end)
  end

  def handle_event("confirm_delete_layer", params, socket) do
    with_auth(socket, :edit_content, fn ->
      LayerHandlers.handle_confirm_delete_layer(params, socket)
    end)
  end

  def handle_event("delete_layer", params, socket) do
    with_auth(socket, :edit_content, fn ->
      LayerHandlers.handle_delete_layer(params, socket)
    end)
  end

  # ---------------------------------------------------------------------------
  # Background upload handlers — delegate to LayerHandlers
  # ---------------------------------------------------------------------------

  def handle_event("toggle_legend", params, socket) do
    LayerHandlers.handle_toggle_legend(params, socket)
  end

  def handle_event("toggle_background_upload", params, socket) do
    LayerHandlers.handle_toggle_background_upload(params, socket)
  end

  def handle_event("remove_background", params, socket) do
    with_auth(socket, :edit_content, fn ->
      LayerHandlers.handle_remove_background(params, socket)
    end)
  end

  def handle_event("update_map_scale", params, socket) do
    with_auth(socket, :edit_content, fn ->
      LayerHandlers.handle_update_map_scale(params, socket)
    end)
  end

  def handle_event("toggle_pin_icon_upload", params, socket) do
    LayerHandlers.handle_toggle_pin_icon_upload(params, socket)
  end

  def handle_event("remove_pin_icon", params, socket) do
    with_auth(socket, :edit_content, fn ->
      LayerHandlers.handle_remove_pin_icon(params, socket)
    end)
  end

  # ---------------------------------------------------------------------------
  # Zone handlers — delegate to ElementHandlers
  # ---------------------------------------------------------------------------

  def handle_event("update_zone_vertices", params, socket) do
    with_auth(socket, :edit_content, fn ->
      ElementHandlers.handle_update_zone_vertices(params, socket)
    end)
  end

  def handle_event("duplicate_zone", params, socket) do
    with_auth(socket, :edit_content, fn ->
      ElementHandlers.handle_duplicate_zone(params, socket)
    end)
  end

  def handle_event("delete_zone", params, socket) do
    with_auth(socket, :edit_content, fn ->
      ElementHandlers.handle_delete_zone(params, socket)
    end)
  end

  def handle_event("update_zone_action_type", params, socket) do
    with_auth(socket, :edit_content, fn ->
      ElementHandlers.handle_update_zone_action_type(params, socket)
    end)
  end

  def handle_event("update_zone_assignments", params, socket) do
    with_auth(socket, :edit_content, fn ->
      ElementHandlers.handle_update_zone_assignments(params, socket)
    end)
  end

  def handle_event("update_zone_action_data", params, socket) do
    with_auth(socket, :edit_content, fn ->
      ElementHandlers.handle_update_zone_action_data(params, socket)
    end)
  end

  # ---------------------------------------------------------------------------
  # Pin handlers — delegate to ElementHandlers
  # ---------------------------------------------------------------------------

  def handle_event("delete_pin", params, socket) do
    with_auth(socket, :edit_content, fn ->
      ElementHandlers.handle_delete_pin(params, socket)
    end)
  end

  # ---------------------------------------------------------------------------
  # Connection handlers — delegate to ElementHandlers
  # ---------------------------------------------------------------------------

  def handle_event("create_connection", params, socket) do
    with_auth(socket, :edit_content, fn ->
      ElementHandlers.handle_create_connection(params, socket)
    end)
  end

  def handle_event("delete_connection", params, socket) do
    with_auth(socket, :edit_content, fn ->
      ElementHandlers.handle_delete_connection(params, socket)
    end)
  end

  # ---------------------------------------------------------------------------
  # Annotation canvas handlers — delegate to ElementHandlers
  # ---------------------------------------------------------------------------

  def handle_event("create_annotation", params, socket) do
    with_auth(socket, :edit_content, fn ->
      ElementHandlers.handle_create_annotation(params, socket)
    end)
  end

  def handle_event("update_annotation", params, socket) do
    with_auth(socket, :edit_content, fn ->
      ElementHandlers.handle_update_annotation(params, socket)
    end)
  end

  def handle_event("move_annotation", params, socket) do
    with_auth(socket, :edit_content, fn ->
      ElementHandlers.handle_move_annotation(params, socket)
    end)
  end

  def handle_event("delete_annotation", params, socket) do
    with_auth(socket, :edit_content, fn ->
      ElementHandlers.handle_delete_annotation(params, socket)
    end)
  end

  def handle_event("set_pending_delete_annotation", params, socket) do
    with_auth(socket, :edit_content, fn ->
      ElementHandlers.handle_set_pending_delete_annotation(params, socket)
    end)
  end

  # ---------------------------------------------------------------------------
  # Keyboard shortcut actions — delegate to ElementHandlers
  # ---------------------------------------------------------------------------

  def handle_event("delete_selected", _params, socket) do
    with_auth(socket, :edit_content, fn ->
      ElementHandlers.handle_delete_selected(socket)
    end)
  end

  def handle_event("duplicate_selected", _params, socket) do
    with_auth(socket, :edit_content, fn ->
      ElementHandlers.handle_duplicate_selected(socket)
    end)
  end

  def handle_event("copy_selected", _params, socket) do
    ElementHandlers.handle_copy_selected(socket)
  end

  def handle_event("paste_element", params, socket) do
    with_auth(socket, :edit_content, fn ->
      ElementHandlers.handle_paste_element(params, socket)
    end)
  end

  # ---------------------------------------------------------------------------
  # Undo / Redo — delegate to UndoRedoHandlers
  # ---------------------------------------------------------------------------

  def handle_event("undo", params, socket) do
    UndoRedoHandlers.handle_undo(params, socket)
  end

  def handle_event("redo", params, socket) do
    UndoRedoHandlers.handle_redo(params, socket)
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
        {:noreply,
         put_flash(socket, :error, dgettext("maps", "Flow not found."))}

      _flow ->
        {:noreply,
         push_navigate(socket,
           to:
             ~p"/workspaces/#{socket.assigns.workspace.slug}/projects/#{socket.assigns.project.slug}/flows/#{flow_id}"
         )}
    end
  end

  # ---------------------------------------------------------------------------
  # Sidebar tree event handlers — delegate to TreeHandlers
  # ---------------------------------------------------------------------------

  def handle_event("create_map", params, socket) do
    with_auth(socket, :edit_content, fn ->
      TreeHandlers.handle_create_map(params, socket)
    end)
  end

  def handle_event("create_child_map", params, socket) do
    with_auth(socket, :edit_content, fn ->
      TreeHandlers.handle_create_child_map(params, socket)
    end)
  end

  def handle_event("create_child_map_from_zone", params, socket) do
    with_auth(socket, :edit_content, fn ->
      TreeHandlers.handle_create_child_map_from_zone(params, socket)
    end)
  end

  def handle_event("set_pending_delete_map", params, socket) do
    TreeHandlers.handle_set_pending_delete_map(params, socket)
  end

  def handle_event("confirm_delete_map", params, socket) do
    TreeHandlers.handle_confirm_delete_map(params, socket)
  end

  def handle_event("delete_map", params, socket) do
    with_auth(socket, :edit_content, fn ->
      TreeHandlers.handle_delete_map(params, socket)
    end)
  end

  def handle_event("move_to_parent", params, socket) do
    with_auth(socket, :edit_content, fn ->
      TreeHandlers.handle_move_to_parent(params, socket)
    end)
  end

  # ---------------------------------------------------------------------------
  # handle_info callbacks
  # ---------------------------------------------------------------------------

  @impl true
  def handle_info({:background_uploaded, asset}, socket) do
    case Maps.update_map(socket.assigns.map, %{background_asset_id: asset.id}) do
      {:ok, updated} ->
        updated = Repo.preload(updated, :background_asset, force: true)

        {:noreply,
         socket
         |> assign(:map, updated)
         |> assign(:show_background_upload, false)
         |> push_event("background_changed", %{url: asset.url})
         |> put_flash(:info, dgettext("maps", "Background image updated."))}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, dgettext("maps", "Could not update background."))}
    end
  end

  def handle_info({:pin_icon_uploaded, asset}, socket) do
    case socket.assigns[:selected_element] do
      %{__struct__: Storyarn.Maps.MapPin} = pin ->
        case Maps.update_pin(pin, %{"icon_asset_id" => asset.id}) do
          {:ok, updated} ->
            updated = Repo.preload(updated, [:icon_asset, sheet: :avatar_asset], force: true)

            {:noreply,
             socket
             |> assign(:selected_element, updated)
             |> update_pin_in_list(updated)
             |> assign(:show_pin_icon_upload, false)
             |> push_event("pin_updated", serialize_pin(updated))
             |> put_flash(:info, dgettext("maps", "Pin icon updated."))}

          {:error, _} ->
            {:noreply, put_flash(socket, :error, dgettext("maps", "Could not update pin icon."))}
        end

      _ ->
        {:noreply, socket}
    end
  end

  # ---------------------------------------------------------------------------
  # Private helpers
  # ---------------------------------------------------------------------------

  defp with_auth(socket, action, fun) do
    case authorize(socket, action) do
      :ok -> fun.()
      {:error, :unauthorized} -> {:noreply, unauthorized_flash(socket)}
    end
  end

  defp unauthorized_flash(socket) do
    put_flash(
      socket,
      :error,
      dgettext("maps", "You don't have permission to perform this action.")
    )
  end

  attr :sheets, :list, required: true

  defp sheet_picker_list(assigns) do
    ~H"""
    <button
      :for={sheet <- @sheets}
      type="button"
      phx-click="start_pin_from_sheet"
      phx-value-sheet-id={sheet.id}
      class="w-full flex items-center gap-2 px-2 py-1.5 rounded hover:bg-base-200 text-left"
    >
      <div class="size-7 rounded-full bg-base-300 flex items-center justify-center shrink-0 overflow-hidden">
        <img
          :if={sheet_avatar_url(sheet)}
          src={sheet_avatar_url(sheet)}
          class="size-7 rounded-full object-cover"
        />
        <span :if={!sheet_avatar_url(sheet)} class="text-xs font-medium text-base-content/60">
          {String.slice(sheet.name, 0, 2)}
        </span>
      </div>
      <div class="min-w-0 flex-1">
        <div class="text-sm truncate">{sheet.name}</div>
        <div :if={sheet.shortcut} class="text-xs text-base-content/50 truncate">
          #{sheet.shortcut}
        </div>
      </div>
    </button>
    """
  end
end
