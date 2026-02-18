defmodule StoryarnWeb.MapLive.Show do
  @moduledoc false

  use StoryarnWeb, :live_view
  use StoryarnWeb.Helpers.Authorize

  import StoryarnWeb.Layouts, only: [flash_group: 1]
  import StoryarnWeb.MapLive.Components.Dock
  import StoryarnWeb.MapLive.Components.Legend
  import StoryarnWeb.MapLive.Components.PropertiesPanel

  alias Storyarn.Maps
  alias Storyarn.Projects
  alias Storyarn.Repo

  @impl true
  def render(assigns) do
    ~H"""
    <div class="h-screen flex flex-col">
      <%!-- Header --%>
      <header class="navbar bg-base-100 border-b border-base-300 px-4 shrink-0">
        <div class="flex-none flex items-center gap-1">
          <.link
            navigate={
              ~p"/workspaces/#{@workspace.slug}/projects/#{@project.slug}/maps"
            }
            class="btn btn-ghost btn-sm gap-2"
          >
            <.icon name="chevron-left" class="size-4" />
            {dgettext("maps", "Maps")}
          </.link>
        </div>
        <div class="flex-1 flex items-center gap-3 ml-4">
          <div>
            <h1
              :if={@can_edit}
              id="map-title"
              class="text-lg font-medium outline-none rounded px-1 -mx-1 empty:before:content-[attr(data-placeholder)] empty:before:text-base-content/30"
              contenteditable="true"
              phx-hook="EditableTitle"
              phx-update="ignore"
              data-placeholder={dgettext("maps", "Untitled")}
              data-name={@map.name}
            >
              {@map.name}
            </h1>
            <h1 :if={!@can_edit} class="text-lg font-medium">
              {@map.name}
            </h1>
          </div>
          <span :if={@map.shortcut} class="badge badge-ghost font-mono text-xs">
            #{@map.shortcut}
          </span>
        </div>
        <div class="flex-none flex items-center gap-1">
          <%!-- Export dropdown --%>
          <div class="dropdown dropdown-end">
            <div
              tabindex="0"
              role="button"
              class="btn btn-ghost btn-sm gap-2"
              title={dgettext("maps", "Export map")}
            >
              <.icon name="download" class="size-4" />
              {dgettext("maps", "Export")}
            </div>
            <ul
              tabindex="0"
              class="dropdown-content menu bg-base-100 rounded-lg border border-base-300 shadow-md w-44 p-1 mt-1 z-[1001]"
            >
              <li>
                <button type="button" phx-click="export_map" phx-value-format="png" class="text-sm">
                  <.icon name="image" class="size-4" />
                  {dgettext("maps", "Export as PNG")}
                </button>
              </li>
              <li>
                <button type="button" phx-click="export_map" phx-value-format="svg" class="text-sm">
                  <.icon name="file-code" class="size-4" />
                  {dgettext("maps", "Export as SVG")}
                </button>
              </li>
            </ul>
          </div>

          <%!-- Edit/View mode toggle --%>
          <button
            :if={@can_edit}
            type="button"
            phx-click="toggle_edit_mode"
            class={"btn btn-sm gap-2 #{if @edit_mode, do: "btn-primary", else: "btn-ghost"}"}
            title={if @edit_mode, do: dgettext("maps", "Switch to View mode"), else: dgettext("maps", "Switch to Edit mode")}
          >
            <.icon name={if @edit_mode, do: "pencil", else: "eye"} class="size-4" />
            {if @edit_mode, do: dgettext("maps", "Edit"), else: dgettext("maps", "View")}
          </button>
        </div>
      </header>

      <%!-- Canvas + Properties panel --%>
      <div class="flex-1 flex overflow-hidden">
        <%!-- Canvas area --%>
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
            <%!-- Search bar --%>
            <div class="bg-base-100 rounded-lg border border-base-300 shadow-md">
              <form id="search-form" phx-change="search_elements" phx-submit="search_elements">
                <div class="flex items-center gap-1.5 px-2.5 py-1.5">
                  <.icon name="search" class="size-4 text-base-content/40 shrink-0" />
                  <input
                    type="text"
                    name="query"
                    value={@search_query}
                    placeholder={dgettext("maps", "Search elements...")}
                    phx-debounce="300"
                    autocomplete="off"
                    class="flex-1 bg-transparent text-sm border-none outline-none placeholder:text-base-content/30 p-0"
                  />
                  <button
                    :if={@search_query != ""}
                    type="button"
                    phx-click="clear_search"
                    class="btn btn-ghost btn-xs btn-square"
                  >
                    <.icon name="x" class="size-3" />
                  </button>
                </div>
              </form>

              <%!-- Type filter tabs --%>
              <div :if={@search_query != ""} class="flex gap-1 px-2 pb-1.5 flex-wrap">
                <button
                  :for={
                    {label, value} <- [
                      {dgettext("maps", "All"), "all"},
                      {dgettext("maps", "Pins"), "pin"},
                      {dgettext("maps", "Zones"), "zone"},
                      {dgettext("maps", "Notes"), "annotation"},
                      {dgettext("maps", "Lines"), "connection"}
                    ]
                  }
                  type="button"
                  phx-click="set_search_filter"
                  phx-value-filter={value}
                  class={"btn btn-xs #{if @search_filter == value, do: "btn-primary", else: "btn-ghost"}"}
                >
                  {label}
                </button>
              </div>

              <%!-- Search results --%>
              <div
                :if={@search_query != "" && @search_results != []}
                class="max-h-48 overflow-y-auto border-t border-base-300"
              >
                <button
                  :for={result <- @search_results}
                  type="button"
                  phx-click="focus_search_result"
                  phx-value-type={result.type}
                  phx-value-id={result.id}
                  class="w-full flex items-center gap-2 px-3 py-1.5 hover:bg-base-200 text-left"
                >
                  <.icon name={search_result_icon(result.type)} class="size-3.5 text-base-content/50" />
                  <span class="text-xs truncate">{result.label}</span>
                </button>
              </div>

              <%!-- No results --%>
              <div
                :if={@search_query != "" && @search_results == []}
                class="px-3 py-2 text-xs text-base-content/50 border-t border-base-300"
              >
                {dgettext("maps", "No results found")}
              </div>
            </div>

            <%!-- Layer bar --%>
            <div class="bg-base-100 rounded-lg border border-base-300 shadow-md px-3 py-1.5">
              <div class="flex items-center justify-between mb-1">
                <span class="text-xs font-medium text-base-content/60">
                  <.icon name="layers" class="size-3.5 inline-block mr-1" />{dgettext("maps", "Layers")}
                </span>
                <div :if={@can_edit and @edit_mode} class="flex items-center gap-1 shrink-0">
                  <button
                    type="button"
                    phx-click="create_layer"
                    class="btn btn-ghost btn-xs btn-square"
                    title={dgettext("maps", "Add layer")}
                  >
                    <.icon name="plus" class="size-3.5" />
                  </button>
                </div>
              </div>
              <div class="flex flex-col gap-0.5" id="layer-bar-items">
                <div :for={layer <- @layers} class="flex items-center group">
                  <button
                    :if={@can_edit and @edit_mode}
                    type="button"
                    phx-click="toggle_layer_visibility"
                    phx-value-id={layer.id}
                    class="btn btn-ghost btn-xs btn-square shrink-0"
                    title={dgettext("maps", "Toggle visibility")}
                  >
                    <.icon
                      name={if(layer.visible, do: "eye", else: "eye-off")}
                      class={"size-3 #{unless layer.visible, do: "opacity-40"}"}
                    />
                  </button>
                  <%!-- Inline rename input (replaces the button text) --%>
                  <input
                    :if={@renaming_layer_id == layer.id}
                    type="text"
                    id={"layer-rename-#{layer.id}"}
                    value={layer.name}
                    phx-blur="rename_layer"
                    phx-keydown="rename_layer"
                    phx-key="Enter"
                    phx-value-id={layer.id}
                    phx-mounted={JS.focus(to: "#layer-rename-#{layer.id}")}
                    class="input input-xs input-bordered flex-1 min-w-0"
                  />
                  <%!-- Normal layer name button --%>
                  <button
                    :if={@renaming_layer_id != layer.id}
                    type="button"
                    phx-click="set_active_layer"
                    phx-value-id={layer.id}
                    class={[
                      "btn btn-xs flex-1 justify-start min-w-0",
                      if(layer.id == @active_layer_id,
                        do: "btn-primary btn-outline",
                        else: "btn-ghost"
                      )
                    ]}
                    title={dgettext("maps", "Set as active layer")}
                  >
                    <span class={"text-xs truncate #{unless layer.visible, do: "opacity-40 line-through"}"}>
                      {layer.name}
                    </span>
                    <.icon
                      :if={layer.fog_enabled}
                      name="cloud-fog"
                      class="size-3 opacity-50 shrink-0"
                      title={dgettext("maps", "Fog of War enabled")}
                    />
                  </button>
                  <%!-- Kebab menu for rename/delete --%>
                  <div :if={@can_edit and @edit_mode and @renaming_layer_id != layer.id} class="dropdown dropdown-end">
                    <div
                      tabindex="0"
                      role="button"
                      class="btn btn-ghost btn-xs btn-square opacity-0 group-hover:opacity-100 transition-opacity shrink-0"
                      title={dgettext("maps", "Layer options")}
                    >
                      <.icon name="ellipsis-vertical" class="size-3" />
                    </div>
                    <ul
                      tabindex="0"
                      class="dropdown-content menu bg-base-100 rounded-lg border border-base-300 shadow-md w-36 p-1 z-[1100]"
                    >
                      <li>
                        <button
                          type="button"
                          phx-click={JS.push("start_rename_layer", value: %{id: layer.id})}
                          class="text-sm"
                        >
                          <.icon name="pencil" class="size-3.5" />
                          {dgettext("maps", "Rename")}
                        </button>
                      </li>
                      <li>
                        <button
                          type="button"
                          phx-click={
                            JS.push("update_layer_fog",
                              value: %{
                                id: layer.id,
                                field: "fog_enabled",
                                value: to_string(!layer.fog_enabled)
                              }
                            )
                          }
                          class="text-sm"
                        >
                          <.icon
                            name={if(layer.fog_enabled, do: "eye", else: "cloud-fog")}
                            class="size-3.5"
                          />
                          {if(layer.fog_enabled,
                            do: dgettext("maps", "Disable Fog"),
                            else: dgettext("maps", "Enable Fog")
                          )}
                        </button>
                      </li>
                      <li>
                        <button
                          type="button"
                          phx-click={
                            JS.push("set_pending_delete_layer", value: %{id: layer.id})
                            |> show_modal("delete-layer-confirm")
                          }
                          class="text-sm text-error"
                          disabled={length(@layers) <= 1}
                        >
                          <.icon name="trash-2" class="size-3.5" />
                          {dgettext("maps", "Delete")}
                        </button>
                      </li>
                    </ul>
                  </div>
                </div>
              </div>
            </div>
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
          <div class="absolute top-2 right-2 z-[1000]">
            <.flash_group flash={@flash} />
          </div>

          <%!-- Legend --%>
          <.legend
            pins={@pins}
            zones={@zones}
            connections={@connections}
            legend_open={@legend_open}
          />

          <%!-- (Layer bar moved to top-left panel next to search) --%>
        </div>

        <%!-- Properties panel --%>
        <aside
          :if={@selected_element}
          id="properties-panel"
          class="w-72 bg-base-100 border-l border-base-300 flex flex-col overflow-hidden shrink-0"
        >
          <div class="p-3 border-b border-base-300 flex items-center justify-between">
            <h2 class="font-medium text-sm flex items-center gap-2">
              <.icon name={panel_icon(@selected_type)} class="size-4" />
              {panel_title(@selected_type)}
            </h2>
            <button
              type="button"
              class="btn btn-ghost btn-xs btn-square"
              phx-click="deselect"
            >
              <.icon name="x" class="size-4" />
            </button>
          </div>

          <div class="flex-1 overflow-y-auto p-3">
            <.pin_properties
              :if={@selected_type == "pin"}
              pin={@selected_element}
              layers={@layers}
              can_edit={@can_edit and @edit_mode and not Map.get(@selected_element || %{}, :locked, false)}
              can_toggle_lock={@can_edit and @edit_mode}
              project_maps={@project_maps}
              project_sheets={@project_sheets}
              project_flows={@project_flows}
              show_pin_icon_upload={@show_pin_icon_upload}
              project={@project}
              current_user={@current_scope.user}
            />
            <.zone_properties
              :if={@selected_type == "zone"}
              zone={@selected_element}
              layers={@layers}
              can_edit={@can_edit and @edit_mode and not Map.get(@selected_element || %{}, :locked, false)}
              can_toggle_lock={@can_edit and @edit_mode}
              project_maps={@project_maps}
              project_sheets={@project_sheets}
              project_flows={@project_flows}
            />
            <.connection_properties
              :if={@selected_type == "connection"}
              connection={@selected_element}
              can_edit={@can_edit and @edit_mode}
            />
            <.annotation_properties
              :if={@selected_type == "annotation"}
              annotation={@selected_element}
              layers={@layers}
              can_edit={@can_edit and @edit_mode and not Map.get(@selected_element || %{}, :locked, false)}
              can_toggle_lock={@can_edit and @edit_mode}
            />
          </div>
        </aside>

        <%!-- Map properties panel (when nothing selected) --%>
        <aside
          :if={!@selected_element && @can_edit && @edit_mode}
          id="map-settings-panel"
          class="w-72 bg-base-100 border-l border-base-300 flex flex-col overflow-hidden shrink-0"
        >
          <div class="p-3 border-b border-base-300">
            <h2 class="font-medium text-sm flex items-center gap-2">
              <.icon name="settings" class="size-4" />
              {dgettext("maps", "Map Properties")}
            </h2>
          </div>

          <div class="flex-1 overflow-y-auto p-3">
            <.map_properties
              map={@map}
              show_background_upload={@show_background_upload}
              project={@project}
              current_user={@current_scope.user}
            />
          </div>
        </aside>
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
          dgettext("maps", 
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
    maps_tree = Maps.list_maps_tree(project.id)

    socket
    |> assign(:project, project)
    |> assign(:workspace, project.workspace)
    |> assign(:membership, membership)
    |> assign(:can_edit, can_edit)
    |> assign(:map, map)
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
      add_annotation: dgettext("maps", "Add Annotation Here")
    })
  end

  @impl true
  def handle_params(_params, _url, socket) do
    {:noreply, socket}
  end

  # ---------------------------------------------------------------------------
  # Map name editing
  # ---------------------------------------------------------------------------

  @impl true
  def handle_event("save_name", %{"name" => name}, socket) do
    case authorize(socket, :edit_content) do
      :ok ->
        case Maps.update_map(socket.assigns.map, %{name: name}) do
          {:ok, updated} ->
            {:noreply,
             socket
             |> assign(:map, updated)
             |> reload_maps_tree()}

          {:error, _} ->
            {:noreply, put_flash(socket, :error, dgettext("maps", "Could not save map name."))}
        end

      {:error, :unauthorized} ->
        {:noreply,
         put_flash(socket, :error, dgettext("maps", "You don't have permission to perform this action."))}
    end
  end

  # ---------------------------------------------------------------------------
  # Canvas mode + element selection
  # ---------------------------------------------------------------------------

  @valid_tools ~w(select pan rectangle triangle circle freeform pin annotation connector ruler)

  def handle_event("set_tool", %{"tool" => tool}, socket) when tool in @valid_tools do
    tool_atom = String.to_existing_atom(tool)

    {:noreply,
     socket
     |> assign(:active_tool, tool_atom)
     |> push_event("tool_changed", %{tool: tool})}
  end

  def handle_event("export_map", %{"format" => format}, socket) when format in ~w(png svg) do
    {:noreply, push_event(socket, "export_map", %{format: format})}
  end

  def handle_event("toggle_edit_mode", _params, socket) do
    case authorize(socket, :edit_content) do
      :ok ->
        new_mode = !socket.assigns.edit_mode

        {:noreply,
         socket
         |> assign(:edit_mode, new_mode)
         |> assign(:active_tool, if(new_mode, do: :select, else: :pan))
         |> push_event("edit_mode_changed", %{edit_mode: new_mode})
         |> push_event("tool_changed", %{tool: if(new_mode, do: "select", else: "pan")})}

      {:error, :unauthorized} ->
        {:noreply,
         put_flash(socket, :error, dgettext("maps", "You don't have permission to perform this action."))}
    end
  end

  # ---------------------------------------------------------------------------
  # Search & Filter
  # ---------------------------------------------------------------------------

  def handle_event("search_elements", %{"query" => query}, socket) do
    query = String.trim(query)

    if query == "" do
      {:noreply,
       socket
       |> assign(:search_query, "")
       |> assign(:search_results, [])
       |> push_event("clear_highlights", %{})}
    else
      results = search_map_elements(socket, query, socket.assigns.search_filter)

      {:noreply,
       socket
       |> assign(:search_query, query)
       |> assign(:search_results, results)
       |> push_event("highlight_elements", %{
         elements: Enum.map(results, &%{type: &1.type, id: &1.id})
       })}
    end
  end

  def handle_event("set_search_filter", %{"filter" => filter}, socket)
      when filter in ~w(all pin zone annotation connection) do
    socket = assign(socket, :search_filter, filter)

    if socket.assigns.search_query != "" do
      results = search_map_elements(socket, socket.assigns.search_query, filter)

      {:noreply,
       socket
       |> assign(:search_results, results)
       |> push_event("highlight_elements", %{
         elements: Enum.map(results, &%{type: &1.type, id: &1.id})
       })}
    else
      {:noreply, socket}
    end
  end

  def handle_event("clear_search", _params, socket) do
    {:noreply,
     socket
     |> assign(:search_query, "")
     |> assign(:search_filter, "all")
     |> assign(:search_results, [])
     |> push_event("clear_highlights", %{})}
  end

  def handle_event("focus_search_result", %{"type" => type, "id" => id}, socket)
      when type in ~w(pin zone connection annotation) do
    id = parse_id(id)
    map_id = socket.assigns.map.id

    case load_element(type, id, map_id) do
      nil ->
        {:noreply, socket}

      element ->
        {:noreply,
         socket
         |> assign(:selected_type, type)
         |> assign(:selected_element, element)
         |> push_event("element_selected", %{type: type, id: id})
         |> push_event("focus_element", %{type: type, id: id})}
    end
  end

  # ---------------------------------------------------------------------------
  # Element selection
  # ---------------------------------------------------------------------------

  def handle_event("select_element", %{"type" => type, "id" => id}, socket)
      when type in ~w(pin zone connection annotation) do
    id = parse_id(id)
    map_id = socket.assigns.map.id

    case load_element(type, id, map_id) do
      nil ->
        {:noreply, socket}

      element ->
        {:noreply,
         socket
         |> assign(:selected_type, type)
         |> assign(:selected_element, element)
         |> push_event("element_selected", %{type: type, id: id})}
    end
  end

  def handle_event("noop", _params, socket), do: {:noreply, socket}

  def handle_event("deselect", _params, socket) do
    {:noreply,
     socket
     |> assign(:selected_type, nil)
     |> assign(:selected_element, nil)
     |> push_event("element_deselected", %{})}
  end

  # ---------------------------------------------------------------------------
  # Property panel update handlers
  # ---------------------------------------------------------------------------

  def handle_event("update_pin", %{"field" => field} = params, socket) do
    id = params["id"] || params["element_id"]

    case authorize(socket, :edit_content) do
      :ok ->
        case Maps.get_pin(socket.assigns.map.id, id) do
          nil -> {:noreply, socket}
          pin -> do_update_pin(socket, pin, field, extract_field_value(params, field))
        end

      {:error, :unauthorized} ->
        {:noreply,
         put_flash(socket, :error, dgettext("maps", "You don't have permission to perform this action."))}
    end
  end

  def handle_event("update_zone", %{"field" => field} = params, socket) do
    id = params["id"] || params["element_id"]

    case authorize(socket, :edit_content) do
      :ok ->
        case Maps.get_zone(socket.assigns.map.id, id) do
          nil -> {:noreply, socket}
          zone -> do_update_zone(socket, zone, field, extract_field_value(params, field))
        end

      {:error, :unauthorized} ->
        {:noreply,
         put_flash(socket, :error, dgettext("maps", "You don't have permission to perform this action."))}
    end
  end

  def handle_event("update_connection", %{"field" => field} = params, socket) do
    id = params["id"] || params["element_id"]

    case authorize(socket, :edit_content) do
      :ok ->
        case Maps.get_connection(socket.assigns.map.id, id) do
          nil -> {:noreply, socket}
          conn -> do_update_connection(socket, conn, field, extract_field_value(params, field))
        end

      {:error, :unauthorized} ->
        {:noreply,
         put_flash(socket, :error, dgettext("maps", "You don't have permission to perform this action."))}
    end
  end

  def handle_event("update_connection_waypoints", %{"id" => id, "waypoints" => waypoints}, socket) do
    case authorize(socket, :edit_content) do
      :ok ->
        case Maps.get_connection(socket.assigns.map.id, id) do
          nil -> {:noreply, socket}
          conn -> do_update_connection_waypoints(socket, conn, waypoints)
        end

      {:error, :unauthorized} ->
        {:noreply,
         put_flash(socket, :error, dgettext("maps", "You don't have permission to perform this action."))}
    end
  end

  def handle_event("clear_connection_waypoints", %{"id" => id}, socket) do
    case authorize(socket, :edit_content) do
      :ok ->
        case Maps.get_connection(socket.assigns.map.id, id) do
          nil -> {:noreply, socket}
          conn -> do_clear_connection_waypoints(socket, conn)
        end

      {:error, :unauthorized} ->
        {:noreply,
         put_flash(socket, :error, dgettext("maps", "You don't have permission to perform this action."))}
    end
  end

  def handle_event("set_pending_delete_pin", %{"id" => id}, socket) do
    {:noreply, assign(socket, :pending_delete_element, {:pin, parse_id(id)})}
  end

  def handle_event("set_pending_delete_zone", %{"id" => id}, socket) do
    {:noreply, assign(socket, :pending_delete_element, {:zone, parse_id(id)})}
  end

  def handle_event("set_pending_delete_connection", %{"id" => id}, socket) do
    {:noreply, assign(socket, :pending_delete_element, {:connection, parse_id(id)})}
  end

  def handle_event("confirm_delete_element", _params, socket) do
    case socket.assigns[:pending_delete_element] do
      {:pin, id} ->
        handle_event("delete_pin", %{"id" => to_string(id)}, socket)

      {:zone, id} ->
        handle_event("delete_zone", %{"id" => to_string(id)}, socket)

      {:connection, id} ->
        handle_event("delete_connection", %{"id" => to_string(id)}, socket)

      {:annotation, id} ->
        handle_event("delete_annotation", %{"id" => to_string(id)}, socket)

      _ ->
        {:noreply, socket}
    end
  end

  # ---------------------------------------------------------------------------
  # Pin canvas handlers
  # ---------------------------------------------------------------------------

  def handle_event("create_pin", %{"position_x" => x, "position_y" => y}, socket) do
    case authorize(socket, :edit_content) do
      :ok ->
        attrs = %{
          "position_x" => x,
          "position_y" => y,
          "label" => dgettext("maps", "New Pin"),
          "pin_type" => "location",
          "layer_id" => socket.assigns.active_layer_id
        }

        case Maps.create_pin(socket.assigns.map.id, attrs) do
          {:ok, pin} ->
            {:noreply,
             socket
             |> assign(:pins, socket.assigns.pins ++ [pin])
             |> push_event("pin_created", serialize_pin(pin))}

          {:error, _} ->
            {:noreply, put_flash(socket, :error, dgettext("maps", "Could not create pin."))}
        end

      {:error, :unauthorized} ->
        {:noreply,
         put_flash(socket, :error, dgettext("maps", "You don't have permission to perform this action."))}
    end
  end

  def handle_event("show_sheet_picker", _params, socket) do
    {:noreply, assign(socket, :show_sheet_picker, true)}
  end

  def handle_event("cancel_sheet_picker", _params, socket) do
    {:noreply,
     socket
     |> assign(show_sheet_picker: false, pending_sheet_for_pin: nil)
     |> push_event("pending_sheet_changed", %{active: false})}
  end

  def handle_event("start_pin_from_sheet", %{"sheet-id" => sheet_id}, socket) do
    sheet =
      Storyarn.Sheets.get_sheet(socket.assigns.project.id, sheet_id)
      |> Storyarn.Repo.preload(avatar_asset: [])

    if sheet do
      {:noreply,
       socket
       |> assign(:pending_sheet_for_pin, sheet)
       |> assign(:show_sheet_picker, false)
       |> assign(:active_tool, :pin)
       |> push_event("tool_changed", %{tool: "pin"})
       |> push_event("pending_sheet_changed", %{active: true})}
    else
      {:noreply, put_flash(socket, :error, dgettext("maps", "Sheet not found."))}
    end
  end

  def handle_event("create_pin_from_sheet", %{"position_x" => x, "position_y" => y}, socket) do
    case authorize(socket, :edit_content) do
      :ok -> do_create_pin_from_sheet(socket, x, y)
      {:error, :unauthorized} ->
        {:noreply,
         put_flash(socket, :error, dgettext("maps", "You don't have permission to perform this action."))}
    end
  end

  def handle_event(
        "move_pin",
        %{"id" => pin_id, "position_x" => x, "position_y" => y},
        socket
      ) do
    case authorize(socket, :edit_content) do
      :ok ->
        case Maps.get_pin(socket.assigns.map.id, pin_id) do
          nil -> {:noreply, socket}
          pin -> do_move_pin(socket, pin, x, y)
        end

      {:error, :unauthorized} ->
        {:noreply,
         put_flash(socket, :error, dgettext("maps", "You don't have permission to perform this action."))}
    end
  end

  # ---------------------------------------------------------------------------
  # Zone canvas handlers
  # ---------------------------------------------------------------------------

  def handle_event("create_zone", %{"vertices" => vertices} = params, socket) do
    case authorize(socket, :edit_content) do
      :ok ->
        name = params["name"]
        name = if name == "" or is_nil(name), do: dgettext("maps", "New Zone"), else: name

        attrs = %{
          "name" => name,
          "vertices" => vertices,
          "layer_id" => socket.assigns.active_layer_id
        }

        case Maps.create_zone(socket.assigns.map.id, attrs) do
          {:ok, zone} ->
            {:noreply,
             socket
             |> assign(:zones, socket.assigns.zones ++ [zone])
             |> push_event("zone_created", serialize_zone(zone))}

          {:error, changeset} ->
            msg = zone_error_message(changeset)
            {:noreply, put_flash(socket, :error, msg)}
        end

      {:error, :unauthorized} ->
        {:noreply,
         put_flash(socket, :error, dgettext("maps", "You don't have permission to perform this action."))}
    end
  end

  # ---------------------------------------------------------------------------
  # Layer handlers
  # ---------------------------------------------------------------------------

  def handle_event("create_layer", _params, socket) do
    case authorize(socket, :edit_content) do
      :ok ->
        case Maps.create_layer(socket.assigns.map.id, %{name: dgettext("maps", "New Layer")}) do
          {:ok, layer} ->
            {:noreply,
             socket
             |> push_event("layer_created", %{id: layer.id, name: layer.name})
             |> put_flash(:info, dgettext("maps", "Layer created."))
             |> reload_map()}

          {:error, _} ->
            {:noreply, put_flash(socket, :error, dgettext("maps", "Could not create layer."))}
        end

      {:error, :unauthorized} ->
        {:noreply,
         put_flash(socket, :error, dgettext("maps", "You don't have permission to perform this action."))}
    end
  end

  def handle_event("set_active_layer", %{"id" => layer_id}, socket) do
    {:noreply, assign(socket, :active_layer_id, parse_id(layer_id))}
  end

  def handle_event("toggle_layer_visibility", %{"id" => layer_id}, socket) do
    case authorize(socket, :edit_content) do
      :ok ->
        case Maps.get_layer(socket.assigns.map.id, layer_id) do
          nil -> {:noreply, socket}
          layer -> do_toggle_layer_visibility(socket, layer)
        end

      {:error, :unauthorized} ->
        {:noreply,
         put_flash(socket, :error, dgettext("maps", "You don't have permission to perform this action."))}
    end
  end

  def handle_event("update_layer_fog", %{"id" => layer_id, "field" => field} = params, socket)
      when field in ~w(fog_enabled fog_color fog_opacity) do
    case authorize(socket, :edit_content) do
      :ok ->
        case Maps.get_layer(socket.assigns.map.id, layer_id) do
          nil -> {:noreply, socket}
          layer ->
            value = normalize_fog_value(field, extract_field_value(params, field))
            do_update_layer_fog(socket, layer, field, value)
        end

      {:error, :unauthorized} ->
        {:noreply,
         put_flash(socket, :error, dgettext("maps", "You don't have permission to perform this action."))}
    end
  end

  def handle_event("start_rename_layer", %{"id" => id}, socket) do
    {:noreply, assign(socket, :renaming_layer_id, id)}
  end

  def handle_event("rename_layer", %{"id" => id, "value" => name}, socket) do
    case authorize(socket, :edit_content) do
      :ok ->
        {:noreply,
         socket
         |> do_rename_layer(id, String.trim(name))
         |> assign(:renaming_layer_id, nil)}

      {:error, :unauthorized} ->
        {:noreply,
         socket
         |> put_flash(:error, dgettext("maps", "You don't have permission to perform this action."))
         |> assign(:renaming_layer_id, nil)}
    end
  end

  def handle_event("set_pending_delete_layer", %{"id" => id}, socket) do
    {:noreply, assign(socket, :pending_delete_layer_id, id)}
  end

  def handle_event("confirm_delete_layer", _params, socket) do
    if id = socket.assigns[:pending_delete_layer_id] do
      handle_event("delete_layer", %{"id" => id}, socket)
    else
      {:noreply, socket}
    end
  end

  def handle_event("delete_layer", %{"id" => layer_id}, socket) do
    case authorize(socket, :edit_content) do
      :ok ->
        case Maps.get_layer(socket.assigns.map.id, layer_id) do
          nil -> {:noreply, socket}
          layer -> do_delete_layer(socket, layer)
        end

      {:error, :unauthorized} ->
        {:noreply,
         put_flash(socket, :error, dgettext("maps", "You don't have permission to perform this action."))}
    end
  end

  # ---------------------------------------------------------------------------
  # Background upload handlers
  # ---------------------------------------------------------------------------

  def handle_event("toggle_legend", _params, socket) do
    {:noreply, assign(socket, :legend_open, !socket.assigns.legend_open)}
  end

  def handle_event("toggle_background_upload", _params, socket) do
    {:noreply, assign(socket, :show_background_upload, !socket.assigns.show_background_upload)}
  end

  def handle_event("remove_background", _params, socket) do
    case authorize(socket, :edit_content) do
      :ok ->
        case Maps.update_map(socket.assigns.map, %{background_asset_id: nil}) do
          {:ok, updated} ->
            {:noreply,
             socket
             |> assign(:map, updated)
             |> push_event("background_changed", %{url: nil})}

          {:error, _} ->
            {:noreply, put_flash(socket, :error, dgettext("maps", "Could not remove background."))}
        end

      {:error, :unauthorized} ->
        {:noreply,
         put_flash(socket, :error, dgettext("maps", "You don't have permission to perform this action."))}
    end
  end

  def handle_event("update_map_scale", %{"field" => field} = params, socket)
      when field in ~w(scale_unit scale_value) do
    case authorize(socket, :edit_content) do
      :ok ->
        value = parse_scale_field(field, extract_field_value(params, field))

        case Maps.update_map(socket.assigns.map, %{field => value}) do
          {:ok, updated} ->
            {:noreply,
             socket
             |> assign(:map, updated)
             |> assign(:map_data, build_map_data(updated, socket.assigns.can_edit))}

          {:error, _} ->
            {:noreply, put_flash(socket, :error, dgettext("maps", "Could not update map scale."))}
        end

      {:error, :unauthorized} ->
        {:noreply,
         put_flash(socket, :error, dgettext("maps", "You don't have permission to perform this action."))}
    end
  end

  def handle_event("toggle_pin_icon_upload", _params, socket) do
    {:noreply, assign(socket, :show_pin_icon_upload, !socket.assigns.show_pin_icon_upload)}
  end

  def handle_event("remove_pin_icon", _params, socket) do
    case authorize(socket, :edit_content) do
      :ok ->
        pin = socket.assigns.selected_element

        case Maps.update_pin(pin, %{"icon_asset_id" => nil}) do
          {:ok, updated} ->
            updated = Repo.preload(updated, [:icon_asset, sheet: :avatar_asset], force: true)

            {:noreply,
             socket
             |> assign(:selected_element, updated)
             |> update_pin_in_list(updated)
             |> assign(:show_pin_icon_upload, false)
             |> push_event("pin_updated", serialize_pin(updated))}

          {:error, _} ->
            {:noreply, put_flash(socket, :error, dgettext("maps", "Could not remove pin icon."))}
        end

      {:error, :unauthorized} ->
        {:noreply,
         put_flash(socket, :error, dgettext("maps", "You don't have permission to perform this action."))}
    end
  end

  # ---------------------------------------------------------------------------
  # Zone handlers
  # ---------------------------------------------------------------------------

  def handle_event("update_zone_vertices", %{"id" => id, "vertices" => vertices}, socket) do
    case authorize(socket, :edit_content) do
      :ok ->
        case Maps.get_zone(socket.assigns.map.id, id) do
          nil -> {:noreply, socket}
          zone -> do_update_zone_vertices(socket, zone, vertices)
        end

      {:error, :unauthorized} ->
        {:noreply,
         put_flash(socket, :error, dgettext("maps", "You don't have permission to perform this action."))}
    end
  end

  def handle_event("duplicate_zone", %{"id" => zone_id}, socket) do
    case authorize(socket, :edit_content) do
      :ok ->
        case Maps.get_zone(socket.assigns.map.id, zone_id) do
          nil -> {:noreply, socket}
          zone -> do_duplicate_zone(socket, zone)
        end

      {:error, :unauthorized} ->
        {:noreply,
         put_flash(socket, :error, dgettext("maps", "You don't have permission to perform this action."))}
    end
  end

  def handle_event("delete_zone", %{"id" => zone_id}, socket) do
    case authorize(socket, :edit_content) do
      :ok ->
        case Maps.get_zone(socket.assigns.map.id, zone_id) do
          nil -> {:noreply, socket}
          zone -> do_delete_zone(socket, zone)
        end

      {:error, :unauthorized} ->
        {:noreply,
         put_flash(socket, :error, dgettext("maps", "You don't have permission to perform this action."))}
    end
  end

  # ---------------------------------------------------------------------------
  # Pin handlers
  # ---------------------------------------------------------------------------

  def handle_event("delete_pin", %{"id" => pin_id}, socket) do
    case authorize(socket, :edit_content) do
      :ok ->
        case Maps.get_pin(socket.assigns.map.id, pin_id) do
          nil -> {:noreply, socket}
          pin -> do_delete_pin(socket, pin)
        end

      {:error, :unauthorized} ->
        {:noreply,
         put_flash(socket, :error, dgettext("maps", "You don't have permission to perform this action."))}
    end
  end

  # ---------------------------------------------------------------------------
  # Connection handlers
  # ---------------------------------------------------------------------------

  def handle_event(
        "create_connection",
        %{"from_pin_id" => from_pin_id, "to_pin_id" => to_pin_id},
        socket
      ) do
    case authorize(socket, :edit_content) do
      :ok ->
        attrs = %{
          "from_pin_id" => from_pin_id,
          "to_pin_id" => to_pin_id
        }

        case Maps.create_connection(socket.assigns.map.id, attrs) do
          {:ok, conn} ->
            {:noreply,
             socket
             |> assign(:connections, socket.assigns.connections ++ [conn])
             |> push_event("connection_created", serialize_connection(conn))}

          {:error, _} ->
            {:noreply, put_flash(socket, :error, dgettext("maps", "Could not create connection."))}
        end

      {:error, :unauthorized} ->
        {:noreply,
         put_flash(socket, :error, dgettext("maps", "You don't have permission to perform this action."))}
    end
  end

  def handle_event("delete_connection", %{"id" => connection_id}, socket) do
    case authorize(socket, :edit_content) do
      :ok ->
        case Maps.get_connection(socket.assigns.map.id, connection_id) do
          nil -> {:noreply, socket}
          connection -> do_delete_connection(socket, connection)
        end

      {:error, :unauthorized} ->
        {:noreply,
         put_flash(socket, :error, dgettext("maps", "You don't have permission to perform this action."))}
    end
  end

  # ---------------------------------------------------------------------------
  # Annotation canvas handlers
  # ---------------------------------------------------------------------------

  def handle_event("create_annotation", %{"position_x" => x, "position_y" => y} = params, socket) do
    case authorize(socket, :edit_content) do
      :ok ->
        attrs = %{
          "text" => params["text"] || dgettext("maps", "Note"),
          "position_x" => x,
          "position_y" => y,
          "font_size" => params["font_size"] || "md",
          "color" => params["color"],
          "layer_id" => socket.assigns.active_layer_id
        }

        case Maps.create_annotation(socket.assigns.map.id, attrs) do
          {:ok, annotation} ->
            {:noreply,
             socket
             |> assign(:annotations, socket.assigns.annotations ++ [annotation])
             |> push_event("annotation_created", serialize_annotation(annotation))}

          {:error, _} ->
            {:noreply, put_flash(socket, :error, dgettext("maps", "Could not create annotation."))}
        end

      {:error, :unauthorized} ->
        {:noreply,
         put_flash(socket, :error, dgettext("maps", "You don't have permission to perform this action."))}
    end
  end

  def handle_event("update_annotation", %{"field" => field} = params, socket) do
    id = params["id"] || params["element_id"]
    value = params["value"] || params[field]

    case authorize(socket, :edit_content) do
      :ok ->
        case Maps.get_annotation(socket.assigns.map.id, id) do
          nil -> {:noreply, socket}
          annotation -> do_update_annotation(socket, annotation, field, value)
        end

      {:error, :unauthorized} ->
        {:noreply,
         put_flash(socket, :error, dgettext("maps", "You don't have permission to perform this action."))}
    end
  end

  def handle_event("move_annotation", %{"id" => id, "position_x" => x, "position_y" => y}, socket) do
    case authorize(socket, :edit_content) do
      :ok ->
        case Maps.get_annotation(socket.assigns.map.id, id) do
          nil -> {:noreply, socket}
          annotation -> do_move_annotation(socket, annotation, x, y)
        end

      {:error, :unauthorized} ->
        {:noreply,
         put_flash(socket, :error, dgettext("maps", "You don't have permission to perform this action."))}
    end
  end

  def handle_event("delete_annotation", %{"id" => annotation_id}, socket) do
    case authorize(socket, :edit_content) do
      :ok ->
        case Maps.get_annotation(socket.assigns.map.id, annotation_id) do
          nil -> {:noreply, socket}
          annotation -> do_delete_annotation(socket, annotation)
        end

      {:error, :unauthorized} ->
        {:noreply,
         put_flash(socket, :error, dgettext("maps", "You don't have permission to perform this action."))}
    end
  end

  def handle_event("set_pending_delete_annotation", %{"id" => id}, socket) do
    {:noreply, assign(socket, :pending_delete_element, {:annotation, parse_id(id)})}
  end

  # ---------------------------------------------------------------------------
  # Undo / Redo
  # ---------------------------------------------------------------------------

  def handle_event("undo", _params, socket) do
    case socket.assigns.undo_stack do
      [] ->
        {:noreply, socket}

      [action | rest] ->
        case undo_action(action, socket) do
          {:ok, socket, recreated} ->
            {type, _} = action
            redo_action = {type, recreated}

            {:noreply,
             socket
             |> assign(:undo_stack, rest)
             |> push_redo(redo_action)
             |> reload_map()}

          {:error, socket} ->
            {:noreply, assign(socket, :undo_stack, rest)}
        end
    end
  end

  def handle_event("redo", _params, socket) do
    case socket.assigns.redo_stack do
      [] ->
        {:noreply, socket}

      [action | rest] ->
        case redo_action(action, socket) do
          {:ok, socket} ->
            {:noreply,
             socket
             |> assign(:redo_stack, rest)
             |> push_undo_no_clear(action)
             |> reload_map()}

          {:error, socket} ->
            {:noreply, assign(socket, :redo_stack, rest)}
        end
    end
  end

  # ---------------------------------------------------------------------------
  # Target navigation
  # ---------------------------------------------------------------------------

  def handle_event("navigate_to_target", %{"type" => "map", "id" => id}, socket) do
    {:noreply,
     push_navigate(socket,
       to:
         ~p"/workspaces/#{socket.assigns.workspace.slug}/projects/#{socket.assigns.project.slug}/maps/#{id}"
     )}
  end

  def handle_event("navigate_to_target", _params, socket) do
    {:noreply, socket}
  end

  # ---------------------------------------------------------------------------
  # Sidebar tree event handlers
  # ---------------------------------------------------------------------------

  def handle_event("create_map", _params, socket) do
    case authorize(socket, :edit_content) do
      :ok ->
        case Maps.create_map(socket.assigns.project, %{name: dgettext("maps", "Untitled")}) do
          {:ok, new_map} ->
            {:noreply,
             push_navigate(socket,
               to:
                 ~p"/workspaces/#{socket.assigns.workspace.slug}/projects/#{socket.assigns.project.slug}/maps/#{new_map.id}"
             )}

          {:error, _changeset} ->
            {:noreply, put_flash(socket, :error, dgettext("maps", "Could not create map."))}
        end

      {:error, :unauthorized} ->
        {:noreply,
         put_flash(socket, :error, dgettext("maps", "You don't have permission to perform this action."))}
    end
  end

  def handle_event("create_child_map", %{"parent-id" => parent_id}, socket) do
    case authorize(socket, :edit_content) do
      :ok ->
        attrs = %{name: dgettext("maps", "Untitled"), parent_id: parent_id}

        case Maps.create_map(socket.assigns.project, attrs) do
          {:ok, new_map} ->
            {:noreply,
             push_navigate(socket,
               to:
                 ~p"/workspaces/#{socket.assigns.workspace.slug}/projects/#{socket.assigns.project.slug}/maps/#{new_map.id}"
             )}

          {:error, _changeset} ->
            {:noreply, put_flash(socket, :error, dgettext("maps", "Could not create map."))}
        end

      {:error, :unauthorized} ->
        {:noreply,
         put_flash(socket, :error, dgettext("maps", "You don't have permission to perform this action."))}
    end
  end

  def handle_event("set_pending_delete_map", %{"id" => id}, socket) do
    {:noreply, assign(socket, :pending_delete_id, id)}
  end

  def handle_event("confirm_delete_map", _params, socket) do
    if id = socket.assigns[:pending_delete_id] do
      handle_event("delete_map", %{"id" => id}, socket)
    else
      {:noreply, socket}
    end
  end

  def handle_event("delete_map", %{"id" => map_id}, socket) do
    case authorize(socket, :edit_content) do
      :ok ->
        case Maps.get_map(socket.assigns.project.id, map_id) do
          nil -> {:noreply, socket}
          map -> do_delete_current_map(socket, map, map_id)
        end

      {:error, :unauthorized} ->
        {:noreply,
         put_flash(socket, :error, dgettext("maps", "You don't have permission to perform this action."))}
    end
  end

  def handle_event(
        "move_to_parent",
        %{"item_id" => item_id, "new_parent_id" => new_parent_id, "position" => position},
        socket
      ) do
    case authorize(socket, :edit_content) do
      :ok ->
        case Maps.get_map(socket.assigns.project.id, item_id) do
          nil -> {:noreply, socket}
          map -> do_move_map_in_show(socket, map, new_parent_id, position)
        end

      {:error, :unauthorized} ->
        {:noreply,
         put_flash(socket, :error, dgettext("maps", "You don't have permission to perform this action."))}
    end
  end

  defp do_create_pin_from_sheet(socket, _x, _y) when is_nil(socket.assigns.pending_sheet_for_pin) do
    {:noreply, put_flash(socket, :error, dgettext("maps", "No sheet selected."))}
  end

  defp do_create_pin_from_sheet(socket, x, y) do
    sheet = socket.assigns.pending_sheet_for_pin

    attrs = %{
      "position_x" => x,
      "position_y" => y,
      "label" => sheet.name,
      "pin_type" => "character",
      "sheet_id" => sheet.id,
      "target_type" => "sheet",
      "target_id" => sheet.id,
      "layer_id" => socket.assigns.active_layer_id
    }

    case Maps.create_pin(socket.assigns.map.id, attrs) do
      {:ok, pin} ->
        pin = %{pin | sheet: sheet}

        {:noreply,
         socket
         |> assign(:pins, socket.assigns.pins ++ [pin])
         |> assign(:pending_sheet_for_pin, nil)
         |> assign(:active_tool, :select)
         |> push_event("pin_created", serialize_pin(pin))
         |> push_event("tool_changed", %{tool: "select"})
         |> push_event("pending_sheet_changed", %{active: false})}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, dgettext("maps", "Could not create pin."))}
    end
  end

  defp do_rename_layer(socket, _id, name) when name == "", do: socket

  defp do_rename_layer(socket, id, name) do
    case Maps.get_layer(socket.assigns.map.id, id) do
      nil -> socket
      layer -> do_update_layer_name(socket, layer, name)
    end
  end

  defp do_update_layer_name(socket, layer, name) when name == layer.name, do: socket

  defp do_update_layer_name(socket, layer, name) do
    case Maps.update_layer(layer, %{"name" => name}) do
      {:ok, _updated} ->
        socket
        |> put_flash(:info, dgettext("maps", "Layer renamed."))
        |> reload_map()

      {:error, _} ->
        put_flash(socket, :error, dgettext("maps", "Could not rename layer."))
    end
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

  # ---------------------------------------------------------------------------
  # Search helpers
  # ---------------------------------------------------------------------------

  defp search_map_elements(socket, query, filter) do
    q = String.downcase(query)

    []
    |> maybe_search(filter, "pin", fn -> search_pins(socket.assigns.pins, q) end)
    |> maybe_search(filter, "zone", fn -> search_zones(socket.assigns.zones, q) end)
    |> maybe_search(filter, "annotation", fn -> search_annotations(socket.assigns.annotations, q) end)
    |> maybe_search(filter, "connection", fn -> search_connections(socket.assigns.connections, q) end)
  end

  defp maybe_search(acc, "all", _type, fun), do: acc ++ fun.()
  defp maybe_search(acc, filter, filter, fun), do: acc ++ fun.()
  defp maybe_search(acc, _filter, _type, _fun), do: acc

  defp search_pins(pins, q) do
    pins
    |> Enum.filter(&matches_text?(&1.label, q))
    |> Enum.map(&%{type: "pin", id: &1.id, label: &1.label || dgettext("maps", "Pin")})
  end

  defp search_zones(zones, q) do
    zones
    |> Enum.filter(&matches_text?(&1.name, q))
    |> Enum.map(&%{type: "zone", id: &1.id, label: &1.name || dgettext("maps", "Zone")})
  end

  defp search_annotations(annotations, q) do
    annotations
    |> Enum.filter(&matches_text?(&1.text, q))
    |> Enum.map(&%{type: "annotation", id: &1.id, label: &1.text || dgettext("maps", "Note")})
  end

  defp search_connections(connections, q) do
    connections
    |> Enum.filter(&matches_text?(&1.label, q))
    |> Enum.map(&%{type: "connection", id: &1.id, label: &1.label || dgettext("maps", "Connection")})
  end

  defp matches_text?(nil, _q), do: false
  defp matches_text?(text, q), do: String.contains?(String.downcase(text), q)

  defp search_result_icon("pin"), do: "map-pin"
  defp search_result_icon("zone"), do: "pentagon"
  defp search_result_icon("connection"), do: "cable"
  defp search_result_icon("annotation"), do: "sticky-note"
  defp search_result_icon(_), do: "search"

  defp after_map_deleted(socket, deleted_map_id) do
    socket = put_flash(socket, :info, dgettext("maps", "Map moved to trash."))

    if to_string(deleted_map_id) == to_string(socket.assigns.map.id) do
      push_navigate(socket,
        to:
          ~p"/workspaces/#{socket.assigns.workspace.slug}/projects/#{socket.assigns.project.slug}/maps"
      )
    else
      reload_maps_tree(socket)
    end
  end

  defp build_map_data(map, can_edit) do
    %{
      id: map.id,
      name: map.name,
      width: map.width,
      height: map.height,
      default_zoom: map.default_zoom,
      default_center_x: map.default_center_x,
      default_center_y: map.default_center_y,
      background_url: background_url(map),
      scale_unit: map.scale_unit,
      scale_value: map.scale_value,
      can_edit: can_edit,
      layers: Enum.map(map.layers || [], &serialize_layer/1),
      pins: Enum.map(map.pins || [], &serialize_pin/1),
      zones: Enum.map(map.zones || [], &serialize_zone/1),
      connections: Enum.map(map.connections || [], &serialize_connection/1),
      annotations: Enum.map(map.annotations || [], &serialize_annotation/1)
    }
  end

  defp background_url(%{background_asset: %{url: url}}) when is_binary(url), do: url
  defp background_url(_), do: nil

  defp serialize_layer(layer) do
    %{
      id: layer.id,
      name: layer.name,
      visible: layer.visible,
      is_default: layer.is_default,
      position: layer.position,
      fog_enabled: layer.fog_enabled,
      fog_color: layer.fog_color,
      fog_opacity: layer.fog_opacity
    }
  end

  defp serialize_pin(pin) do
    %{
      id: pin.id,
      position_x: pin.position_x,
      position_y: pin.position_y,
      pin_type: pin.pin_type,
      icon: pin.icon,
      color: pin.color,
      label: pin.label,
      tooltip: pin.tooltip,
      size: pin.size,
      layer_id: pin.layer_id,
      target_type: pin.target_type,
      target_id: pin.target_id,
      sheet_id: pin.sheet_id,
      avatar_url: pin_avatar_url(pin),
      icon_asset_url: pin_icon_asset_url(pin),
      position: pin.position,
      locked: pin.locked || false
    }
  end

  defp pin_avatar_url(%{sheet: %{avatar_asset: %{url: url}}}) when is_binary(url), do: url
  defp pin_avatar_url(_), do: nil

  defp pin_icon_asset_url(%{icon_asset: %{url: url}}) when is_binary(url), do: url
  defp pin_icon_asset_url(_), do: nil

  defp serialize_zone(zone) do
    %{
      id: zone.id,
      name: zone.name,
      vertices: zone.vertices,
      fill_color: zone.fill_color,
      border_color: zone.border_color,
      border_width: zone.border_width,
      border_style: zone.border_style,
      opacity: zone.opacity,
      tooltip: zone.tooltip,
      layer_id: zone.layer_id,
      target_type: zone.target_type,
      target_id: zone.target_id,
      position: zone.position,
      locked: zone.locked || false
    }
  end

  defp serialize_connection(conn) do
    %{
      id: conn.id,
      from_pin_id: conn.from_pin_id,
      to_pin_id: conn.to_pin_id,
      line_style: conn.line_style,
      color: conn.color,
      label: conn.label,
      bidirectional: conn.bidirectional,
      waypoints: conn.waypoints || []
    }
  end

  defp serialize_annotation(annotation) do
    %{
      id: annotation.id,
      text: annotation.text,
      position_x: annotation.position_x,
      position_y: annotation.position_y,
      font_size: annotation.font_size,
      color: annotation.color,
      layer_id: annotation.layer_id,
      position: annotation.position,
      locked: annotation.locked || false
    }
  end

  defp update_pin_in_list(socket, updated_pin) do
    pins =
      Enum.map(socket.assigns.pins, fn pin ->
        if pin.id == updated_pin.id, do: updated_pin, else: pin
      end)

    assign(socket, :pins, pins)
  end

  defp reload_map(socket) do
    map = Maps.get_map(socket.assigns.project.id, socket.assigns.map.id)

    socket
    |> assign(:map, map)
    |> assign(:layers, map.layers || [])
    |> assign(:zones, map.zones || [])
    |> assign(:pins, map.pins || [])
    |> assign(:connections, map.connections || [])
    |> reload_maps_tree()
  end

  defp reload_maps_tree(socket) do
    assign(socket, :maps_tree, Maps.list_maps_tree(socket.assigns.project.id))
  end

  defp zone_error_message(%Ecto.Changeset{} = changeset) do
    if Keyword.has_key?(changeset.errors, :vertices) do
      {msg, _} = Keyword.fetch!(changeset.errors, :vertices)
      dgettext("maps", "Invalid zone: %{reason}", reason: msg)
    else
      dgettext("maps", "Could not create zone.")
    end
  end

  defp zone_error_message(_), do: dgettext("maps", "Could not create zone.")

  defp default_layer_id(nil), do: nil
  defp default_layer_id([]), do: nil

  defp default_layer_id(layers) do
    default = Enum.find(layers, fn l -> l.is_default end)
    if default, do: default.id, else: List.first(layers).id
  end

  defp parse_id(id) when is_integer(id), do: id

  defp parse_id(id) when is_binary(id) do
    case Integer.parse(id) do
      {int, ""} -> int
      _ -> id
    end
  end

  defp parse_float(val, default \\ 0.85)
  defp parse_float("", default), do: default
  defp parse_float(nil, default), do: default
  defp parse_float(val, _default) when is_float(val), do: val
  defp parse_float(val, _default) when is_integer(val), do: val / 1

  defp parse_float(val, default) when is_binary(val) do
    case Float.parse(val) do
      {f, _} -> f
      :error -> default
    end
  end

  defp parse_float(_, default), do: default

  defp parse_float_or_nil(val), do: parse_float(val, nil)

  defp parse_scale_field("scale_value", raw) do
    case parse_float_or_nil(raw) do
      v when is_number(v) and v > 0 -> v
      _ -> nil
    end
  end

  defp parse_scale_field(_field, value), do: value

  defp load_element("pin", id, map_id), do: Maps.get_pin(map_id, id)
  defp load_element("zone", id, map_id), do: Maps.get_zone(map_id, id)
  defp load_element("connection", id, map_id), do: Maps.get_connection(map_id, id)
  defp load_element("annotation", id, map_id), do: Maps.get_annotation(map_id, id)

  # ---------------------------------------------------------------------------
  # Lock-aware element operation helpers
  # ---------------------------------------------------------------------------

  defp do_move_pin(socket, %{locked: true}, _x, _y), do: {:noreply, socket}

  defp do_move_pin(socket, pin, x, y) do
    case Maps.move_pin(pin, x, y) do
      {:ok, _updated} -> {:noreply, socket}
      {:error, _} -> {:noreply, put_flash(socket, :error, dgettext("maps", "Could not move pin."))}
    end
  end

  defp do_delete_pin(socket, %{locked: true}) do
    {:noreply, put_flash(socket, :error, dgettext("maps", "Cannot delete a locked element."))}
  end

  defp do_delete_pin(socket, pin) do
    case Maps.delete_pin(pin) do
      {:ok, _} ->
        {:noreply,
         socket
         |> push_undo({:delete_pin, pin})
         |> assign(:selected_element, nil)
         |> assign(:selected_type, nil)
         |> push_event("pin_deleted", %{id: pin.id})
         |> put_flash(:info, dgettext("maps", "Pin deleted. Press Ctrl+Z to undo."))
         |> reload_map()}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, dgettext("maps", "Could not delete pin."))}
    end
  end

  defp do_update_zone_vertices(socket, %{locked: true}, _vertices), do: {:noreply, socket}

  defp do_update_zone_vertices(socket, zone, vertices) do
    case Maps.update_zone_vertices(zone, %{"vertices" => vertices}) do
      {:ok, updated} ->
        {:noreply,
         socket
         |> assign(:zones, replace_in_list(socket.assigns.zones, updated))
         |> maybe_update_selected_element("zone", updated)
         |> push_event("zone_vertices_updated", serialize_zone(updated))}

      {:error, changeset} ->
        msg = zone_error_message(changeset)
        {:noreply, put_flash(socket, :error, msg)}
    end
  end

  defp replace_in_list(list, updated) do
    Enum.map(list, &replace_element(&1, updated))
  end

  defp replace_element(element, updated) when element.id == updated.id, do: updated
  defp replace_element(element, _updated), do: element

  defp do_update_pin(socket, pin, field, value) do
    case Maps.update_pin(pin, %{field => value}) do
      {:ok, updated} ->
        {:noreply,
         socket
         |> assign(:selected_element, updated)
         |> assign(:pins, replace_in_list(socket.assigns.pins, updated))
         |> push_event("pin_updated", serialize_pin(updated))}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, dgettext("maps", "Could not update pin."))}
    end
  end

  defp do_update_zone(socket, zone, field, value) do
    case Maps.update_zone(zone, %{field => value}) do
      {:ok, updated} ->
        {:noreply,
         socket
         |> assign(:selected_element, updated)
         |> assign(:zones, replace_in_list(socket.assigns.zones, updated))
         |> push_event("zone_updated", serialize_zone(updated))}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, dgettext("maps", "Could not update zone."))}
    end
  end

  defp do_update_connection(socket, conn, field, value) do
    case Maps.update_connection(conn, %{field => value}) do
      {:ok, updated} ->
        {:noreply,
         socket
         |> assign(:selected_element, updated)
         |> assign(:connections, replace_in_list(socket.assigns.connections, updated))
         |> push_event("connection_updated", serialize_connection(updated))}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, dgettext("maps", "Could not update connection."))}
    end
  end

  defp do_update_annotation(socket, annotation, field, value) do
    case Maps.update_annotation(annotation, %{field => value}) do
      {:ok, updated} ->
        {:noreply,
         socket
         |> assign(:annotations, replace_in_list(socket.assigns.annotations, updated))
         |> maybe_update_selected_element("annotation", updated)
         |> push_event("annotation_updated", serialize_annotation(updated))}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, dgettext("maps", "Could not update annotation."))}
    end
  end

  defp do_update_connection_waypoints(socket, conn, waypoints) do
    case Maps.update_connection_waypoints(conn, %{"waypoints" => waypoints}) do
      {:ok, updated} ->
        {:noreply,
         socket
         |> assign(:selected_element, updated)
         |> push_event("connection_updated", serialize_connection(updated))}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, dgettext("maps", "Could not update waypoints."))}
    end
  end

  defp do_clear_connection_waypoints(socket, conn) do
    case Maps.update_connection_waypoints(conn, %{"waypoints" => []}) do
      {:ok, updated} ->
        {:noreply,
         socket
         |> assign(:selected_element, updated)
         |> push_event("connection_updated", serialize_connection(updated))}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, dgettext("maps", "Could not clear waypoints."))}
    end
  end

  defp do_toggle_layer_visibility(socket, layer) do
    case Maps.toggle_layer_visibility(layer) do
      {:ok, updated} ->
        {:noreply,
         socket
         |> push_event("layer_visibility_changed", %{id: updated.id, visible: updated.visible})
         |> reload_map()}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, dgettext("maps", "Could not toggle layer visibility."))}
    end
  end

  defp normalize_fog_value("fog_enabled", value), do: value in ["true", true]
  defp normalize_fog_value("fog_opacity", value), do: parse_float(value)
  defp normalize_fog_value(_field, value), do: value

  defp do_update_layer_fog(socket, layer, field, value) do
    case Maps.update_layer(layer, %{field => value}) do
      {:ok, updated} ->
        {:noreply,
         socket
         |> push_event("layer_fog_changed", %{
           id: updated.id,
           fog_enabled: updated.fog_enabled,
           fog_color: updated.fog_color,
           fog_opacity: updated.fog_opacity
         })
         |> reload_map()}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, dgettext("maps", "Could not update fog settings."))}
    end
  end

  defp do_delete_layer(socket, layer) do
    case Maps.delete_layer(layer) do
      {:ok, _} ->
        {:noreply,
         socket
         |> push_event("layer_deleted", %{id: layer.id})
         |> put_flash(:info, dgettext("maps", "Layer deleted."))
         |> reload_map()}

      {:error, :cannot_delete_last_layer} ->
        {:noreply, put_flash(socket, :error, dgettext("maps", "Cannot delete the last layer of a map."))}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, dgettext("maps", "Could not delete layer."))}
    end
  end

  defp do_duplicate_zone(socket, zone) do
    shifted_vertices =
      Enum.map(zone.vertices, fn v ->
        %{"x" => min(v["x"] + 5, 100.0), "y" => min(v["y"] + 5, 100.0)}
      end)

    attrs = %{
      "name" => zone.name <> " (copy)",
      "vertices" => shifted_vertices,
      "fill_color" => zone.fill_color,
      "border_color" => zone.border_color,
      "border_width" => zone.border_width,
      "border_style" => zone.border_style,
      "opacity" => zone.opacity,
      "layer_id" => zone.layer_id
    }

    case Maps.create_zone(socket.assigns.map.id, attrs) do
      {:ok, new_zone} ->
        {:noreply,
         socket
         |> assign(:zones, socket.assigns.zones ++ [new_zone])
         |> push_event("zone_created", serialize_zone(new_zone))
         |> put_flash(:info, dgettext("maps", "Zone duplicated."))}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, dgettext("maps", "Could not duplicate zone."))}
    end
  end

  defp do_delete_connection(socket, connection) do
    case Maps.delete_connection(connection) do
      {:ok, _} ->
        {:noreply,
         socket
         |> push_undo({:delete_connection, connection})
         |> assign(:selected_element, nil)
         |> assign(:selected_type, nil)
         |> push_event("connection_deleted", %{id: connection.id})
         |> put_flash(:info, dgettext("maps", "Connection deleted. Press Ctrl+Z to undo."))
         |> reload_map()}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, dgettext("maps", "Could not delete connection."))}
    end
  end

  defp do_delete_current_map(socket, map, map_id) do
    case Maps.delete_map(map) do
      {:ok, _} -> {:noreply, after_map_deleted(socket, map_id)}
      {:error, _} -> {:noreply, put_flash(socket, :error, dgettext("maps", "Could not delete map."))}
    end
  end

  defp do_move_map_in_show(socket, map, new_parent_id, position) do
    new_parent_id = parse_int(new_parent_id)
    position = parse_int(position) || 0

    case Maps.move_map_to_position(map, new_parent_id, position) do
      {:ok, _} -> {:noreply, reload_maps_tree(socket)}
      {:error, _} -> {:noreply, put_flash(socket, :error, dgettext("maps", "Could not move map."))}
    end
  end

  defp do_delete_zone(socket, %{locked: true}) do
    {:noreply, put_flash(socket, :error, dgettext("maps", "Cannot delete a locked element."))}
  end

  defp do_delete_zone(socket, zone) do
    case Maps.delete_zone(zone) do
      {:ok, _} ->
        {:noreply,
         socket
         |> push_undo({:delete_zone, zone})
         |> assign(:selected_element, nil)
         |> assign(:selected_type, nil)
         |> push_event("zone_deleted", %{id: zone.id})
         |> put_flash(:info, dgettext("maps", "Zone deleted. Press Ctrl+Z to undo."))
         |> reload_map()}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, dgettext("maps", "Could not delete zone."))}
    end
  end

  defp do_move_annotation(socket, %{locked: true}, _x, _y), do: {:noreply, socket}

  defp do_move_annotation(socket, annotation, x, y) do
    case Maps.move_annotation(annotation, x, y) do
      {:ok, _updated} -> {:noreply, socket}
      {:error, _} -> {:noreply, put_flash(socket, :error, dgettext("maps", "Could not move annotation."))}
    end
  end

  defp do_delete_annotation(socket, %{locked: true}) do
    {:noreply, put_flash(socket, :error, dgettext("maps", "Cannot delete a locked element."))}
  end

  defp do_delete_annotation(socket, annotation) do
    case Maps.delete_annotation(annotation) do
      {:ok, _} ->
        {:noreply,
         socket
         |> push_undo({:delete_annotation, annotation})
         |> assign(:annotations, Enum.reject(socket.assigns.annotations, &(&1.id == annotation.id)))
         |> assign(:selected_element, nil)
         |> assign(:selected_type, nil)
         |> push_event("annotation_deleted", %{id: annotation.id})
         |> put_flash(:info, dgettext("maps", "Annotation deleted. Press Ctrl+Z to undo."))}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, dgettext("maps", "Could not delete annotation."))}
    end
  end

  # Checkbox phx-click sends DOM value "on" as "value", so boolean toggles
  # use phx-value-toggle to avoid the collision.
  defp extract_field_value(%{"toggle" => value}, _field), do: value
  defp extract_field_value(%{"value" => value}, _field), do: value

  defp extract_field_value(params, field) do
    # For phx-blur inputs, value comes from the input's value attribute
    Map.get(params, field, Map.get(params, "value", ""))
  end

  defp panel_icon("pin"), do: "map-pin"
  defp panel_icon("zone"), do: "pentagon"
  defp panel_icon("connection"), do: "cable"
  defp panel_icon("annotation"), do: "sticky-note"
  defp panel_icon(_), do: "settings"

  defp panel_title("pin"), do: dgettext("maps", "Pin Properties")
  defp panel_title("zone"), do: dgettext("maps", "Zone Properties")
  defp panel_title("connection"), do: dgettext("maps", "Connection Properties")
  defp panel_title("annotation"), do: dgettext("maps", "Annotation Properties")
  defp panel_title(_), do: dgettext("maps", "Properties")

  defp maybe_update_selected_element(socket, type, updated) do
    if socket.assigns.selected_type == type &&
         socket.assigns.selected_element &&
         socket.assigns.selected_element.id == updated.id do
      assign(socket, :selected_element, updated)
    else
      socket
    end
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

  defp sheet_avatar_url(%{avatar_asset: %{url: url}}) when is_binary(url), do: url
  defp sheet_avatar_url(_), do: nil

  defp flatten_sheets(sheets) do
    Enum.flat_map(sheets, fn sheet ->
      children = if Map.has_key?(sheet, :children) && is_list(sheet.children), do: sheet.children, else: []
      [sheet | flatten_sheets(children)]
    end)
  end

  defp parse_int(""), do: nil
  defp parse_int(nil), do: nil
  defp parse_int(val) when is_integer(val), do: val

  defp parse_int(str) when is_binary(str) do
    case Integer.parse(str) do
      {int, ""} -> int
      _ -> nil
    end
  end

  # ---------------------------------------------------------------------------
  # Undo / Redo helpers
  # ---------------------------------------------------------------------------

  @max_undo 50

  defp push_undo(socket, action) do
    stack = Enum.take([action | socket.assigns.undo_stack], @max_undo)
    assign(socket, undo_stack: stack, redo_stack: [])
  end

  defp push_undo_no_clear(socket, action) do
    stack = Enum.take([action | socket.assigns.undo_stack], @max_undo)
    assign(socket, :undo_stack, stack)
  end

  defp push_redo(socket, action) do
    stack = Enum.take([action | socket.assigns.redo_stack], @max_undo)
    assign(socket, :redo_stack, stack)
  end

  # Undo: re-create the deleted element
  # Returns {:ok, socket, recreated_element} so the redo stack stores the actual new element
  defp undo_action({:delete_pin, pin}, socket) do
    attrs = %{
      "position_x" => pin.position_x,
      "position_y" => pin.position_y,
      "label" => pin.label,
      "pin_type" => pin.pin_type,
      "color" => pin.color,
      "icon" => pin.icon,
      "size" => pin.size,
      "tooltip" => pin.tooltip,
      "layer_id" => pin.layer_id,
      "sheet_id" => pin.sheet_id,
      "target_type" => pin.target_type,
      "target_id" => pin.target_id
    }

    case Maps.create_pin(socket.assigns.map.id, attrs) do
      {:ok, new_pin} ->
        {:ok,
         socket
         |> assign(:pins, socket.assigns.pins ++ [new_pin])
         |> push_event("pin_created", serialize_pin(new_pin))
         |> put_flash(:info, dgettext("maps", "Undo: pin restored.")),
         new_pin}

      {:error, _} ->
        {:error, put_flash(socket, :error, dgettext("maps", "Could not undo."))}
    end
  end

  defp undo_action({:delete_zone, zone}, socket) do
    attrs = %{
      "name" => zone.name,
      "vertices" => zone.vertices,
      "fill_color" => zone.fill_color,
      "border_color" => zone.border_color,
      "border_width" => zone.border_width,
      "border_style" => zone.border_style,
      "opacity" => zone.opacity,
      "tooltip" => zone.tooltip,
      "layer_id" => zone.layer_id,
      "target_type" => zone.target_type,
      "target_id" => zone.target_id
    }

    case Maps.create_zone(socket.assigns.map.id, attrs) do
      {:ok, new_zone} ->
        {:ok,
         socket
         |> assign(:zones, socket.assigns.zones ++ [new_zone])
         |> push_event("zone_created", serialize_zone(new_zone))
         |> put_flash(:info, dgettext("maps", "Undo: zone restored.")),
         new_zone}

      {:error, _} ->
        {:error, put_flash(socket, :error, dgettext("maps", "Could not undo."))}
    end
  end

  defp undo_action({:delete_connection, conn}, socket) do
    attrs = %{
      "from_pin_id" => conn.from_pin_id,
      "to_pin_id" => conn.to_pin_id,
      "line_style" => conn.line_style,
      "color" => conn.color,
      "label" => conn.label,
      "bidirectional" => conn.bidirectional,
      "waypoints" => conn.waypoints || []
    }

    case Maps.create_connection(socket.assigns.map.id, attrs) do
      {:ok, new_conn} ->
        {:ok,
         socket
         |> assign(:connections, socket.assigns.connections ++ [new_conn])
         |> push_event("connection_created", serialize_connection(new_conn))
         |> put_flash(:info, dgettext("maps", "Undo: connection restored.")),
         new_conn}

      {:error, _} ->
        {:error, put_flash(socket, :error, dgettext("maps", "Could not undo."))}
    end
  end

  defp undo_action({:delete_annotation, annotation}, socket) do
    attrs = %{
      "text" => annotation.text,
      "position_x" => annotation.position_x,
      "position_y" => annotation.position_y,
      "font_size" => annotation.font_size,
      "color" => annotation.color,
      "layer_id" => annotation.layer_id
    }

    case Maps.create_annotation(socket.assigns.map.id, attrs) do
      {:ok, new_ann} ->
        {:ok,
         socket
         |> assign(:annotations, socket.assigns.annotations ++ [new_ann])
         |> push_event("annotation_created", serialize_annotation(new_ann))
         |> put_flash(:info, dgettext("maps", "Undo: annotation restored.")),
         new_ann}

      {:error, _} ->
        {:error, put_flash(socket, :error, dgettext("maps", "Could not undo."))}
    end
  end

  # Redo: re-delete the element using the recreated element stored by undo
  defp redo_action({:delete_pin, pin}, socket) do
    case Enum.find(socket.assigns.pins, &(&1.id == pin.id)) do
      nil ->
        {:error, socket}

      found ->
        case Maps.delete_pin(found) do
          {:ok, _} ->
            {:ok,
             socket
             |> assign(:pins, Enum.reject(socket.assigns.pins, &(&1.id == found.id)))
             |> assign(:selected_element, nil)
             |> assign(:selected_type, nil)
             |> push_event("pin_deleted", %{id: found.id})}

          {:error, _} ->
            {:error, socket}
        end
    end
  end

  defp redo_action({:delete_zone, zone}, socket) do
    case Enum.find(socket.assigns.zones, &(&1.id == zone.id)) do
      nil ->
        {:error, socket}

      found ->
        case Maps.delete_zone(found) do
          {:ok, _} ->
            {:ok,
             socket
             |> assign(:zones, Enum.reject(socket.assigns.zones, &(&1.id == found.id)))
             |> assign(:selected_element, nil)
             |> assign(:selected_type, nil)
             |> push_event("zone_deleted", %{id: found.id})}

          {:error, _} ->
            {:error, socket}
        end
    end
  end

  defp redo_action({:delete_connection, conn}, socket) do
    case Enum.find(socket.assigns.connections, &(&1.id == conn.id)) do
      nil ->
        {:error, socket}

      found ->
        case Maps.delete_connection(found) do
          {:ok, _} ->
            {:ok,
             socket
             |> assign(:connections, Enum.reject(socket.assigns.connections, &(&1.id == found.id)))
             |> assign(:selected_element, nil)
             |> assign(:selected_type, nil)
             |> push_event("connection_deleted", %{id: found.id})}

          {:error, _} ->
            {:error, socket}
        end
    end
  end

  defp redo_action({:delete_annotation, ann}, socket) do
    case Enum.find(socket.assigns.annotations, &(&1.id == ann.id)) do
      nil ->
        {:error, socket}

      found ->
        case Maps.delete_annotation(found) do
          {:ok, _} ->
            {:ok,
             socket
             |> assign(:annotations, Enum.reject(socket.assigns.annotations, &(&1.id == found.id)))
             |> assign(:selected_element, nil)
             |> assign(:selected_type, nil)
             |> push_event("annotation_deleted", %{id: found.id})}

          {:error, _} ->
            {:error, socket}
        end
    end
  end
end
