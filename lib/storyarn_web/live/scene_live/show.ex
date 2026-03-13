defmodule StoryarnWeb.SceneLive.Show do
  @moduledoc false

  use StoryarnWeb, :live_view
  use StoryarnWeb.Helpers.Authorize
  use StoryarnWeb.Live.Shared.RestorationHandlers

  import StoryarnWeb.Live.Shared.TreePanelHandlers
  import StoryarnWeb.SceneLive.Components.Dock
  import StoryarnWeb.SceneLive.Components.LayerBar
  import StoryarnWeb.SceneLive.Components.Legend
  import StoryarnWeb.SceneLive.Components.SceneHeader
  import StoryarnWeb.SceneLive.Components.SceneSearchPanel
  import StoryarnWeb.Components.CanvasToolbar
  import StoryarnWeb.SceneLive.Components.FloatingToolbar
  import StoryarnWeb.SceneLive.Components.SceneElementPanel
  import StoryarnWeb.SceneLive.Components.SceneSettingsPanel
  import StoryarnWeb.Components.RightSidebar

  alias StoryarnWeb.Components.DraftComponents
  alias StoryarnWeb.Live.Shared.DraftHandlers

  alias Storyarn.Assets
  alias Storyarn.Collaboration
  alias Storyarn.Drafts
  alias Storyarn.Projects
  alias Storyarn.Scenes
  alias StoryarnWeb.Live.Shared.CollaborationHelpers, as: Collab

  alias StoryarnWeb.Components.Sidebar.SceneTree

  import StoryarnWeb.SceneLive.Helpers.SceneHelpers
  import StoryarnWeb.SceneLive.Helpers.Serializer

  alias StoryarnWeb.SceneLive.Handlers.CanvasEventHandlers
  alias StoryarnWeb.SceneLive.Handlers.CollaborationHandlers
  alias StoryarnWeb.SceneLive.Handlers.ElementHandlers
  alias StoryarnWeb.SceneLive.Handlers.LayerHandlers
  alias StoryarnWeb.SceneLive.Handlers.TreeHandlers
  alias StoryarnWeb.SceneLive.Handlers.UndoRedoHandlers

  @lock_heartbeat_interval 10_000

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.focus
      flash={@flash}
      current_scope={@current_scope}
      project={@project}
      workspace={@workspace}
      active_tool={:scenes}
      has_tree={true}
      tree_panel_open={@tree_panel_open}
      tree_panel_pinned={@tree_panel_pinned}
      can_edit={@can_edit}
      canvas_mode={true}
      restoration_banner={@restoration_banner}
      online_users={@online_users}
    >
      <:tree_content>
        <div role="tablist" class="tabs tabs-border tabs-sm mb-6">
          <button
            role="tab"
            class={["tab", @tree_panel_tab == "scenes" && "tab-active"]}
            phx-click="switch_tree_tab"
            phx-value-tab="scenes"
          >
            <.icon name="map" class="size-3.5 mr-1" />{dgettext("scenes", "Scenes")}
          </button>
          <button
            role="tab"
            class={["tab", @tree_panel_tab == "layers" && "tab-active"]}
            phx-click="switch_tree_tab"
            phx-value-tab="layers"
          >
            <.icon name="layers" class="size-3.5 mr-1" />{dgettext("scenes", "Layers")}
          </button>
        </div>
        <div :if={@tree_panel_tab == "scenes"}>
          <SceneTree.scenes_section
            scenes_tree={@scenes_tree}
            workspace={@workspace}
            project={@project}
            selected_scene_id={@scene && to_string(@scene.id)}
            can_edit={@can_edit}
          />
        </div>
        <div :if={@tree_panel_tab == "layers" && @scene}>
          <.layer_panel
            layers={@layers}
            active_layer_id={@active_layer_id}
            renaming_layer_id={@renaming_layer_id}
            can_edit={@can_edit}
            edit_mode={@edit_mode}
          />
        </div>
      </:tree_content>
      <:top_bar_extra>
        <DraftComponents.draft_banner is_draft={@is_draft} />
        <%= if @scene do %>
          <.map_info_bar
            scene={@scene}
            ancestors={@ancestors}
            workspace={@workspace}
            project={@project}
            can_edit={@can_edit}
            referencing_flows={@referencing_flows}
          />
          <.map_search_panel
            search_query={@search_query}
            search_filter={@search_filter}
            search_results={@search_results}
          />
        <% end %>
      </:top_bar_extra>
      <:top_bar_extra_right>
        <%= if @scene do %>
          <.map_actions
            can_edit={@can_edit}
            edit_mode={@edit_mode}
            is_draft={@is_draft}
          />
        <% end %>
      </:top_bar_extra_right>
      <SceneTree.delete_modal :if={@can_edit} />
      <%= if @scene do %>
        <div class="h-full relative">
          <%!-- Canvas fills the entire area --%>
          <div
            id="scene-canvas-wrapper"
            class="absolute inset-0 overflow-hidden"
            phx-drop-target={
              @can_edit && @edit_mode && @uploads[:background] && @uploads.background.ref
            }
            phx-hook="CanvasDropZone"
          >
            <div
              id={"scene-canvas-#{@scene.id}"}
              phx-hook="SceneCanvas"
              phx-update="ignore"
              data-scene={Jason.encode!(@scene_data)}
              data-i18n={Jason.encode!(@canvas_i18n)}
              data-current-user-id={@current_scope.user.id}
              data-locks={Jason.encode!(@entity_locks)}
              class="w-full h-full"
            >
              <div id="scene-canvas-container" class="w-full h-full"></div>
            </div>

            <%!-- Hidden file input for background upload --%>
            <form
              :if={@can_edit && @uploads[:background]}
              id="bg-upload-form"
              phx-change="validate_bg_upload"
              class="hidden"
            >
              <.live_file_input upload={@uploads.background} />
            </form>

            <%!-- Empty canvas — upload prompt --%>
            <div
              :if={!background_set?(@scene) && @can_edit && @edit_mode && @uploads[:background]}
              class="absolute inset-0 flex items-center justify-center z-[500] pointer-events-none"
            >
              <label
                for={@uploads.background.ref}
                class="pointer-events-auto cursor-pointer group flex flex-col items-center gap-3
                     p-8 rounded-xl border-2 border-dashed border-base-content/15
                     hover:border-primary/40 hover:bg-base-100/50 transition-colors"
              >
                <.icon
                  name="image-plus"
                  class="size-10 opacity-20 group-hover:opacity-50 transition-opacity"
                />
                <span class="text-sm text-base-content/40 group-hover:text-base-content/60 transition-colors">
                  {dgettext("scenes", "Upload background image")}
                </span>
                <span class="text-xs text-base-content/25">
                  {dgettext("scenes", "or drag & drop")}
                </span>
              </label>
            </div>

            <%!-- Drag & drop overlay (shown by CanvasDropZone hook) --%>
            <div
              :if={@can_edit && @edit_mode}
              id="canvas-drop-indicator"
              class="hidden absolute inset-0 z-[999] bg-primary/5 border-2 border-dashed border-primary/30
                   flex items-center justify-center pointer-events-none"
            >
              <div class="text-center">
                <.icon name="image-plus" class="size-12 text-primary/50 mx-auto mb-2" />
                <p class="text-sm font-medium text-primary/60">
                  {dgettext("scenes", "Drop image to set background")}
                </p>
              </div>
            </div>
          </div>

          <%!-- UI overlays — outside overflow-hidden wrapper so backdrop-blur works --%>

          <%!-- Upload progress indicator --%>
          <div
            :for={
              entry <-
                if(@can_edit && @uploads[:background],
                  do: @uploads.background.entries,
                  else: []
                )
            }
            class="absolute bottom-20 left-1/2 -translate-x-1/2 z-[1000]
                 bg-base-100 rounded-lg border border-base-300 shadow-lg px-4 py-2 flex items-center gap-3"
          >
            <.icon name="upload" class="size-4 animate-pulse text-primary" />
            <div class="w-40">
              <div class="text-xs text-base-content/60 mb-1 flex min-w-0">
                <span class="truncate">{Path.rootname(entry.client_name)}</span>
                <span class="flex-shrink-0">{Path.extname(entry.client_name)}</span>
              </div>
              <div class="w-full bg-base-300 rounded-full h-1.5">
                <div
                  class="bg-primary h-1.5 rounded-full transition-all"
                  style={"width: #{entry.progress}%"}
                >
                </div>
              </div>
            </div>
          </div>

          <%!-- Bottom dock (edit mode only) --%>
          <.dock
            :if={@edit_mode}
            active_tool={@active_tool}
            pending_sheet={@pending_sheet_for_pin}
            workspace={@workspace}
            project={@project}
            scene={@scene}
          />

          <%!-- Version History Panel --%>
          <.right_sidebar
            id="scene-versions-panel"
            title={dgettext("scenes", "Version History")}
            open_event="open_versions_panel"
            close_event="close_versions_panel"
            width="320px"
            loading={!@versions_panel_open}
          >
            <:actions>
              <button
                :if={@can_edit && @versions_panel_open}
                type="button"
                class="btn btn-ghost btn-xs btn-square"
                phx-click="show_create_version_modal"
              >
                <.icon name="plus" class="size-4" />
              </button>
            </:actions>
            <.live_component
              :if={@versions_panel_open}
              module={StoryarnWeb.Components.VersionsSection}
              id="scene-versions-section"
              entity={@scene}
              entity_type="scene"
              project_id={@project.id}
              current_user_id={@current_scope.user.id}
              can_edit={@can_edit}
              current_version_id={@scene.current_version_id}
              workspace_id={@workspace.id}
            />
          </.right_sidebar>

          <%!-- Sheet picker overlay --%>
          <div
            :if={@show_sheet_picker}
            id="sheet-picker"
            class="absolute bottom-32 left-1/2 -translate-x-1/2 z-[1001] w-72 bg-base-100 rounded-lg border border-base-300 shadow-lg overflow-hidden"
          >
            <div class="p-2 border-b border-base-300 flex items-center justify-between">
              <span class="text-xs font-medium">{dgettext("scenes", "Select a sheet")}</span>
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

          <%!-- Bottom-right controls: reset zoom + legend --%>
          <div class="absolute bottom-3 right-3 z-[1000] flex items-end gap-2">
            <div id="scene-controls-slot" phx-update="ignore"></div>
            <.legend
              pins={@pins}
              zones={@zones}
              connections={@connections}
              legend_open={@legend_open}
            />
          </div>

          <%!-- Floating element toolbar --%>
          <.canvas_toolbar
            id="scene-floating-toolbar"
            canvas_id={"scene-canvas-#{@scene.id}"}
            visible={@selected_element != nil && @can_edit && @edit_mode}
            z_class="z-[1050]"
          >
            <.floating_toolbar
              selected_type={@selected_type}
              selected_element={@selected_element}
              layers={@layers}
              can_edit={not Map.get(@selected_element || %{}, :locked, false)}
              can_toggle_lock={true}
            />
          </.canvas_toolbar>

          <%!-- Element Properties Sidebar --%>
          <div
            id="scene-element-panel"
            phx-hook="RightSidebar"
            data-right-panel
            data-open-event="open_element_panel"
            data-close-event="close_element_panel"
            class={[
              "fixed flex flex-col overflow-hidden",
              "inset-0 z-50 bg-base-100",
              "xl:inset-auto xl:right-3 xl:top-[76px] xl:bottom-3 xl:z-[1010] xl:w-[480px]",
              "xl:bg-base-200/95 xl:backdrop-blur xl:border xl:border-base-300 xl:rounded-xl xl:shadow-sm"
            ]}
          >
            <div :if={@element_panel_open && @selected_element != nil}>
              <.scene_element_panel
                selected_type={@selected_type}
                selected_element={@selected_element}
                can_edit={not Map.get(@selected_element || %{}, :locked, false)}
                project_scenes={@project_scenes}
                project_sheets={@project_sheets}
                project_flows={@project_flows}
                project_variables={@project_variables}
                panel_sections={@panel_sections}
              />
            </div>
            <div
              :if={!(@element_panel_open && @selected_element != nil)}
              class="flex items-center justify-center h-full"
            >
              <span class="loading loading-spinner loading-md text-base-content/40"></span>
            </div>
          </div>

          <%!-- Scene Settings Sidebar --%>
          <div
            id="scene-settings-panel"
            phx-hook="RightSidebar"
            data-right-panel
            data-open-event="open_scene_settings"
            data-close-event="close_scene_settings"
            class={[
              "fixed flex flex-col overflow-hidden",
              "inset-0 z-50 bg-base-100",
              "xl:inset-auto xl:right-3 xl:top-[76px] xl:bottom-3 xl:z-[1010] xl:w-[320px]",
              "xl:bg-base-200/95 xl:backdrop-blur xl:border xl:border-base-300 xl:rounded-xl xl:shadow-sm"
            ]}
          >
            <div :if={@scene_settings_open && @can_edit && @edit_mode}>
              <.scene_settings_panel
                scene={@scene}
                can_edit={@can_edit}
                bg_upload_input_id={@uploads[:background] && @uploads.background.ref}
              />
            </div>
            <div
              :if={!(@scene_settings_open && @can_edit && @edit_mode)}
              class="flex items-center justify-center h-full"
            >
              <span class="loading loading-spinner loading-md text-base-content/40"></span>
            </div>
          </div>
        </div>

        <%!-- Pin icon upload overlay (fixed, outside canvas overflow) --%>
        <div
          :if={@show_pin_icon_upload && @selected_type == "pin" && @project && @current_scope}
          id="pin-icon-upload-panel"
          class="fixed top-16 right-4 z-[1030] w-64 bg-base-200 border border-base-300 rounded-lg
               shadow-lg p-3"
        >
          <div class="flex items-center justify-between mb-2">
            <span class="text-xs font-medium">{dgettext("scenes", "Upload Icon")}</span>
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
      <% else %>
        <div class="h-full flex items-center justify-center">
          <span class="loading loading-spinner loading-lg text-base-content/30"></span>
        </div>
      <% end %>

      <%!-- Confirm modals --%>
      <DraftComponents.discard_draft_modal is_draft={@is_draft} />

      <.confirm_modal
        :if={@can_edit}
        id="delete-scene-show-confirm"
        title={dgettext("scenes", "Delete scene?")}
        message={dgettext("scenes", "Are you sure you want to delete this scene?")}
        confirm_text={dgettext("scenes", "Delete")}
        confirm_variant="error"
        icon="alert-triangle"
        on_confirm={JS.push("confirm_delete_scene")}
      />

      <.confirm_modal
        :if={@can_edit}
        id="delete-layer-confirm"
        title={dgettext("scenes", "Delete layer?")}
        message={
          dgettext(
            "maps",
            "This layer will be deleted. All elements on this layer will be moved to no layer."
          )
        }
        confirm_text={dgettext("scenes", "Delete")}
        confirm_variant="error"
        icon="alert-triangle"
        on_confirm={JS.push("confirm_delete_layer")}
      />
    </Layouts.focus>
    """
  end

  @impl true
  def mount(
        %{
          "workspace_slug" => workspace_slug,
          "project_slug" => project_slug
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
        can_edit = Projects.can?(membership.role, :edit_content)

        if connected?(socket), do: Collaboration.subscribe_restoration(project.id)

        {can_edit, restoration_banner} = check_restoration_lock(project.id, can_edit)

        socket =
          socket
          |> assign(focus_layout_defaults())
          |> assign(:tree_panel_tab, "scenes")
          |> assign(:project, project)
          |> assign(:workspace, project.workspace)
          |> assign(:membership, membership)
          |> assign(:can_edit, can_edit)
          |> assign(:restoration_banner, restoration_banner)
          |> assign(:canvas_i18n, canvas_i18n())
          |> assign(:online_users, [])
          |> assign(:collab_scope, nil)
          |> assign(:entity_locks, %{})
          |> assign(:lock_heartbeat_ref, nil)
          |> assign(:_broadcast, nil)
          # Defaults — scene loaded in handle_params
          |> assign(:scene, nil)
          |> assign(:ancestors, [])
          |> assign(:scenes_tree, Scenes.list_scenes_tree(project.id))
          |> assign(:layers, [])
          |> assign(:zones, [])
          |> assign(:pins, [])
          |> assign(:connections, [])
          |> assign(:annotations, [])
          |> assign(:scene_data, %{})
          |> assign(:edit_mode, can_edit)
          |> assign(:active_tool, :select)
          |> assign(:selected_element, nil)
          |> assign(:selected_type, nil)
          |> assign(:element_panel_open, false)
          |> assign(:scene_settings_open, false)
          |> assign(:active_layer_id, nil)
          |> assign(:renaming_layer_id, nil)
          |> assign(:show_pin_icon_upload, false)
          |> assign(:show_sheet_picker, false)
          |> assign(:pending_sheet_for_pin, nil)
          |> assign(:search_query, "")
          |> assign(:search_filter, "all")
          |> assign(:search_results, [])
          |> assign(:legend_open, false)
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
          |> assign(:is_draft, false)
          |> assign(:draft, nil)
          |> maybe_allow_background_upload(can_edit)

        {:ok, socket}

      {:error, _reason} ->
        {:ok,
         socket
         |> put_flash(:error, dgettext("scenes", "You don't have access to this project."))
         |> redirect(to: ~p"/workspaces")}
    end
  end

  @impl true
  def handle_params(%{"id" => _scene_id, "draft_id" => draft_id} = _params, _url, socket) do
    {:noreply, load_draft_scene(socket, draft_id)}
  end

  def handle_params(%{"id" => scene_id} = params, _url, socket) do
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
        |> push_navigate(
          to: ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/scenes"
        )

      scene ->
        has_tree = socket.assigns.sidebar_loaded

        # Setup collaboration for new scene
        scope = {:scene, scene.id}
        user = socket.assigns.current_scope.user
        Collab.setup(socket, scope, user, cursors: true, locks: true, changes: true)
        {online_users, entity_locks} = Collab.get_initial_state(socket, scope)

        socket
        |> assign(:scene, scene)
        |> assign(:collab_scope, scope)
        |> assign(:online_users, online_users)
        |> assign(:entity_locks, entity_locks)
        |> assign(:_broadcast, nil)
        |> schedule_lock_heartbeat()
        |> assign(:ancestors, Scenes.list_ancestors(scene))
        |> assign(:layers, scene.layers || [])
        |> assign(:zones, scene.zones || [])
        |> assign(:pins, scene.pins || [])
        |> assign(:connections, scene.connections || [])
        |> assign(:annotations, scene.annotations || [])
        |> assign(:scene_data, build_scene_data(scene, can_edit))
        |> assign(:edit_mode, can_edit)
        |> assign(:active_tool, :select)
        |> assign(:selected_element, nil)
        |> assign(:selected_type, nil)
        |> assign(:element_panel_open, false)
        |> assign(:scene_settings_open, false)
        |> assign(:versions_panel_open, false)
        |> assign(:active_layer_id, default_layer_id(scene.layers))
        |> assign(:renaming_layer_id, nil)
        |> assign(:show_pin_icon_upload, false)
        |> assign(:show_sheet_picker, false)
        |> assign(:pending_sheet_for_pin, nil)
        |> assign(:search_query, "")
        |> assign(:search_filter, "all")
        |> assign(:search_results, [])
        |> assign(:legend_open, false)
        |> assign(:undo_stack, [])
        |> assign(:redo_stack, [])
        |> assign(:auto_snapshot_ref, nil)
        |> assign(:auto_snapshot_timer, nil)
        |> assign(:panel_sections, %{})
        |> assign(:referencing_flows, [])
        |> maybe_load_sidebar(has_tree, project)
    end
  end

  defp load_draft_scene(socket, draft_id) do
    %{project: project, current_scope: scope, can_edit: can_edit} = socket.assigns

    with draft when not is_nil(draft) <- Drafts.get_my_draft(draft_id, scope.user.id),
         true <- draft.entity_type == "scene" and draft.status == "active",
         entity when not is_nil(entity) <- Drafts.get_draft_entity(draft) do
      # Skip collaboration for drafts
      has_tree = socket.assigns.sidebar_loaded

      socket
      |> assign(:scene, entity)
      |> assign(:is_draft, true)
      |> assign(:draft, draft)
      |> assign(:ancestors, [])
      |> assign(:layers, entity.layers || [])
      |> assign(:zones, entity.zones || [])
      |> assign(:pins, entity.pins || [])
      |> assign(:connections, entity.connections || [])
      |> assign(:annotations, entity.annotations || [])
      |> assign(:scene_data, build_scene_data(entity, can_edit))
      |> assign(:edit_mode, can_edit)
      |> assign(:active_tool, :select)
      |> assign(:selected_element, nil)
      |> assign(:selected_type, nil)
      |> assign(:element_panel_open, false)
      |> assign(:scene_settings_open, false)
      |> assign(:versions_panel_open, false)
      |> assign(:active_layer_id, default_layer_id(entity.layers))
      |> assign(:renaming_layer_id, nil)
      |> assign(:show_pin_icon_upload, false)
      |> assign(:show_sheet_picker, false)
      |> assign(:pending_sheet_for_pin, nil)
      |> assign(:search_query, "")
      |> assign(:search_filter, "all")
      |> assign(:search_results, [])
      |> assign(:legend_open, false)
      |> assign(:undo_stack, [])
      |> assign(:redo_stack, [])
      |> assign(:panel_sections, %{})
      |> assign(:referencing_flows, [])
      |> maybe_load_sidebar(has_tree, project)
    else
      _ ->
        socket
        |> put_flash(:error, dgettext("scenes", "Draft not found."))
        |> push_navigate(
          to: ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/scenes"
        )
    end
  end

  defp maybe_load_sidebar(socket, true, _project), do: socket

  defp maybe_load_sidebar(socket, false, project) do
    start_async(socket, :load_sidebar_data, fn ->
      %{
        scenes_tree: Scenes.list_scenes_tree_with_elements(project.id),
        project_scenes: Scenes.list_scenes(project.id),
        project_sheets: Storyarn.Sheets.list_sheets_tree(project.id),
        project_flows: Storyarn.Flows.list_flows(project.id),
        project_variables: Storyarn.Sheets.list_project_variables(project.id)
      }
    end)
  end

  defp canvas_i18n do
    %{
      edit_properties: dgettext("scenes", "Edit Properties"),
      connect_to: dgettext("scenes", "Connect To\u2026"),
      edit_vertices: dgettext("scenes", "Edit Vertices"),
      duplicate: dgettext("scenes", "Duplicate"),
      bring_to_front: dgettext("scenes", "Bring to Front"),
      send_to_back: dgettext("scenes", "Send to Back"),
      lock: dgettext("scenes", "Lock"),
      unlock: dgettext("scenes", "Unlock"),
      delete: dgettext("scenes", "Delete"),
      add_pin: dgettext("scenes", "Add Pin Here"),
      add_annotation: dgettext("scenes", "Add Annotation Here"),
      create_child_scene: dgettext("scenes", "Create child scene"),
      name_zone_first: dgettext("scenes", "Name the zone first")
    }
  end

  defp parse_highlight_id(id) do
    case Integer.parse(id) do
      {int, ""} -> int
      _ -> nil
    end
  end

  @valid_tools ~w(select pan rectangle triangle circle freeform pin annotation connector ruler)

  @impl true
  # Tree panel events (from FocusLayout)
  def handle_event("tree_panel_" <> _ = event, params, socket),
    do: handle_tree_panel_event(event, params, socket)

  def handle_event("switch_tree_tab", %{"tab" => tab}, socket)
      when tab in ~w(scenes layers) do
    {:noreply, assign(socket, :tree_panel_tab, tab)}
  end

  def handle_event("open_versions_panel", _params, socket) do
    {:noreply, assign(socket, :versions_panel_open, true)}
  end

  def handle_event("close_versions_panel", _params, socket) do
    {:noreply, assign(socket, :versions_panel_open, false)}
  end

  def handle_event("show_create_version_modal", _params, socket) do
    send_update(StoryarnWeb.Components.VersionsSection,
      id: "scene-versions-section",
      show_create_version_modal: true
    )

    {:noreply, socket}
  end

  def handle_event("save_name", params, socket) do
    with_authorization(socket, :edit_content, fn _socket ->
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
    with_authorization(socket, :edit_content, fn _socket ->
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

  def handle_event("select_element", %{"type" => type, "id" => id} = params, socket)
      when type in ~w(pin zone connection annotation) do
    release_element_lock(socket)

    CanvasEventHandlers.handle_select_element(params, socket)
    |> maybe_acquire_lock(id)
  end

  def handle_event("validate_bg_upload", _params, socket), do: {:noreply, socket}

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

  def handle_event(
        "drag_annotation",
        %{"id" => id, "position_x" => x, "position_y" => y},
        socket
      )
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
    {:noreply,
     socket
     |> assign(:element_panel_open, true)
     |> assign(:scene_settings_open, false)}
  end

  def handle_event("close_element_panel", _params, socket) do
    {:noreply, assign(socket, :element_panel_open, false)}
  end

  def handle_event("open_scene_settings", _params, socket) do
    {:noreply,
     socket
     |> assign(:scene_settings_open, true)
     |> assign(:element_panel_open, false)}
  end

  def handle_event("close_scene_settings", _params, socket) do
    {:noreply, assign(socket, :scene_settings_open, false)}
  end

  # ---------------------------------------------------------------------------
  # Property panel update handlers — delegate to ElementHandlers
  # ---------------------------------------------------------------------------

  def handle_event("update_pin", params, socket) do
    with_authorization(socket, :edit_content, fn _socket ->
      ElementHandlers.handle_update_pin(params, socket) |> broadcast_scene_change()
    end)
  end

  def handle_event("update_zone", params, socket) do
    with_authorization(socket, :edit_content, fn _socket ->
      ElementHandlers.handle_update_zone(params, socket) |> broadcast_scene_change()
    end)
  end

  def handle_event("update_connection", params, socket) do
    with_authorization(socket, :edit_content, fn _socket ->
      ElementHandlers.handle_update_connection(params, socket) |> broadcast_scene_change()
    end)
  end

  def handle_event("update_connection_waypoints", params, socket) do
    with_authorization(socket, :edit_content, fn _socket ->
      ElementHandlers.handle_update_connection_waypoints(params, socket)
      |> broadcast_scene_change()
    end)
  end

  def handle_event("clear_connection_waypoints", params, socket) do
    with_authorization(socket, :edit_content, fn _socket ->
      ElementHandlers.handle_clear_connection_waypoints(params, socket)
      |> broadcast_scene_change()
    end)
  end

  def handle_event("set_pending_delete_pin", params, socket) do
    with_authorization(socket, :edit_content, fn _socket ->
      ElementHandlers.handle_set_pending_delete_pin(params, socket)
    end)
  end

  def handle_event("set_pending_delete_zone", params, socket) do
    with_authorization(socket, :edit_content, fn _socket ->
      ElementHandlers.handle_set_pending_delete_zone(params, socket)
    end)
  end

  def handle_event("set_pending_delete_connection", params, socket) do
    with_authorization(socket, :edit_content, fn _socket ->
      ElementHandlers.handle_set_pending_delete_connection(params, socket)
    end)
  end

  def handle_event("confirm_delete_element", params, socket) do
    with_authorization(socket, :edit_content, fn _socket ->
      ElementHandlers.handle_confirm_delete_element(params, socket) |> broadcast_scene_change()
    end)
  end

  # ---------------------------------------------------------------------------
  # Pin canvas handlers — delegate to ElementHandlers
  # ---------------------------------------------------------------------------

  def handle_event("create_pin", params, socket) do
    with_authorization(socket, :edit_content, fn _socket ->
      ElementHandlers.handle_create_pin(params, socket) |> broadcast_scene_change()
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
    with_authorization(socket, :edit_content, fn _socket ->
      ElementHandlers.handle_create_pin_from_sheet(params, socket) |> broadcast_scene_change()
    end)
  end

  def handle_event("move_pin", params, socket) do
    with_authorization(socket, :edit_content, fn _socket ->
      ElementHandlers.handle_move_pin(params, socket) |> broadcast_scene_change()
    end)
  end

  # ---------------------------------------------------------------------------
  # Zone canvas handlers — delegate to ElementHandlers
  # ---------------------------------------------------------------------------

  def handle_event("create_zone", params, socket) do
    with_authorization(socket, :edit_content, fn _socket ->
      ElementHandlers.handle_create_zone(params, socket) |> broadcast_scene_change()
    end)
  end

  # ---------------------------------------------------------------------------
  # Layer handlers — delegate to LayerHandlers
  # ---------------------------------------------------------------------------

  def handle_event("create_layer", params, socket) do
    with_authorization(socket, :edit_content, fn _socket ->
      LayerHandlers.handle_create_layer(params, socket) |> broadcast_scene_change()
    end)
  end

  def handle_event("set_active_layer", params, socket) do
    LayerHandlers.handle_set_active_layer(params, socket)
  end

  def handle_event("toggle_layer_visibility", params, socket) do
    with_authorization(socket, :edit_content, fn _socket ->
      LayerHandlers.handle_toggle_layer_visibility(params, socket) |> broadcast_scene_change()
    end)
  end

  def handle_event("update_layer_fog", params, socket) do
    with_authorization(socket, :edit_content, fn _socket ->
      LayerHandlers.handle_update_layer_fog(params, socket) |> broadcast_scene_change()
    end)
  end

  def handle_event("start_rename_layer", params, socket) do
    LayerHandlers.handle_start_rename_layer(params, socket)
  end

  def handle_event("rename_layer", params, socket) do
    with_authorization(socket, :edit_content, fn _socket ->
      LayerHandlers.handle_rename_layer(params, socket) |> broadcast_scene_change()
    end)
  end

  def handle_event("set_pending_delete_layer", params, socket) do
    with_authorization(socket, :edit_content, fn _socket ->
      LayerHandlers.handle_set_pending_delete_layer(params, socket)
    end)
  end

  def handle_event("confirm_delete_layer", params, socket) do
    with_authorization(socket, :edit_content, fn _socket ->
      LayerHandlers.handle_confirm_delete_layer(params, socket) |> broadcast_scene_change()
    end)
  end

  def handle_event("delete_layer", params, socket) do
    with_authorization(socket, :edit_content, fn _socket ->
      LayerHandlers.handle_delete_layer(params, socket) |> broadcast_scene_change()
    end)
  end

  # ---------------------------------------------------------------------------
  # Background upload handlers — delegate to LayerHandlers
  # ---------------------------------------------------------------------------

  def handle_event("toggle_legend", params, socket) do
    LayerHandlers.handle_toggle_legend(params, socket)
  end

  def handle_event("remove_background", params, socket) do
    with_authorization(socket, :edit_content, fn _socket ->
      LayerHandlers.handle_remove_background(params, socket) |> broadcast_scene_change()
    end)
  end

  def handle_event("update_scene_scale", params, socket) do
    with_authorization(socket, :edit_content, fn _socket ->
      LayerHandlers.handle_update_scene_scale(params, socket) |> broadcast_scene_change()
    end)
  end

  def handle_event("toggle_pin_icon_upload", params, socket) do
    LayerHandlers.handle_toggle_pin_icon_upload(params, socket)
  end

  def handle_event("remove_pin_icon", params, socket) do
    with_authorization(socket, :edit_content, fn _socket ->
      LayerHandlers.handle_remove_pin_icon(params, socket) |> broadcast_scene_change()
    end)
  end

  # ---------------------------------------------------------------------------
  # Zone handlers — delegate to ElementHandlers
  # ---------------------------------------------------------------------------

  def handle_event("update_zone_vertices", params, socket) do
    with_authorization(socket, :edit_content, fn _socket ->
      ElementHandlers.handle_update_zone_vertices(params, socket) |> broadcast_scene_change()
    end)
  end

  def handle_event("duplicate_zone", params, socket) do
    with_authorization(socket, :edit_content, fn _socket ->
      ElementHandlers.handle_duplicate_zone(params, socket) |> broadcast_scene_change()
    end)
  end

  def handle_event("delete_zone", params, socket) do
    with_authorization(socket, :edit_content, fn _socket ->
      ElementHandlers.handle_delete_zone(params, socket) |> broadcast_scene_change()
    end)
  end

  def handle_event("update_zone_action_type", params, socket) do
    with_authorization(socket, :edit_content, fn _socket ->
      ElementHandlers.handle_update_zone_action_type(params, socket) |> broadcast_scene_change()
    end)
  end

  def handle_event("update_zone_assignments", params, socket) do
    with_authorization(socket, :edit_content, fn _socket ->
      ElementHandlers.handle_update_zone_assignments(params, socket) |> broadcast_scene_change()
    end)
  end

  def handle_event("update_zone_action_data", params, socket) do
    with_authorization(socket, :edit_content, fn _socket ->
      ElementHandlers.handle_update_zone_action_data(params, socket) |> broadcast_scene_change()
    end)
  end

  def handle_event("update_zone_condition", params, socket) do
    with_authorization(socket, :edit_content, fn _socket ->
      ElementHandlers.handle_update_zone_condition(params, socket) |> broadcast_scene_change()
    end)
  end

  def handle_event("update_zone_condition_effect", %{"value" => _} = params, socket) do
    with_authorization(socket, :edit_content, fn _socket ->
      ElementHandlers.handle_update_zone_condition_effect(params, socket)
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

  def handle_event("update_pin_action_type", params, socket) do
    with_authorization(socket, :edit_content, fn _socket ->
      ElementHandlers.handle_update_pin_action_type(params, socket) |> broadcast_scene_change()
    end)
  end

  def handle_event("update_pin_assignments", params, socket) do
    with_authorization(socket, :edit_content, fn _socket ->
      ElementHandlers.handle_update_pin_assignments(params, socket) |> broadcast_scene_change()
    end)
  end

  def handle_event("update_pin_action_data", params, socket) do
    with_authorization(socket, :edit_content, fn _socket ->
      ElementHandlers.handle_update_pin_action_data(params, socket) |> broadcast_scene_change()
    end)
  end

  def handle_event("update_pin_condition", params, socket) do
    with_authorization(socket, :edit_content, fn _socket ->
      ElementHandlers.handle_update_pin_condition(params, socket) |> broadcast_scene_change()
    end)
  end

  def handle_event("update_pin_condition_effect", %{"value" => _} = params, socket) do
    with_authorization(socket, :edit_content, fn _socket ->
      ElementHandlers.handle_update_pin_condition_effect(params, socket)
      |> broadcast_scene_change()
    end)
  end

  def handle_event("delete_pin", params, socket) do
    with_authorization(socket, :edit_content, fn _socket ->
      ElementHandlers.handle_delete_pin(params, socket) |> broadcast_scene_change()
    end)
  end

  # ---------------------------------------------------------------------------
  # Connection handlers — delegate to ElementHandlers
  # ---------------------------------------------------------------------------

  def handle_event("create_connection", params, socket) do
    with_authorization(socket, :edit_content, fn _socket ->
      ElementHandlers.handle_create_connection(params, socket) |> broadcast_scene_change()
    end)
  end

  def handle_event("delete_connection", params, socket) do
    with_authorization(socket, :edit_content, fn _socket ->
      ElementHandlers.handle_delete_connection(params, socket) |> broadcast_scene_change()
    end)
  end

  # ---------------------------------------------------------------------------
  # Annotation canvas handlers — delegate to ElementHandlers
  # ---------------------------------------------------------------------------

  def handle_event("create_annotation", params, socket) do
    with_authorization(socket, :edit_content, fn _socket ->
      ElementHandlers.handle_create_annotation(params, socket) |> broadcast_scene_change()
    end)
  end

  def handle_event("update_annotation", params, socket) do
    with_authorization(socket, :edit_content, fn _socket ->
      ElementHandlers.handle_update_annotation(params, socket) |> broadcast_scene_change()
    end)
  end

  def handle_event("move_annotation", params, socket) do
    with_authorization(socket, :edit_content, fn _socket ->
      ElementHandlers.handle_move_annotation(params, socket) |> broadcast_scene_change()
    end)
  end

  def handle_event("delete_annotation", params, socket) do
    with_authorization(socket, :edit_content, fn _socket ->
      ElementHandlers.handle_delete_annotation(params, socket) |> broadcast_scene_change()
    end)
  end

  def handle_event("set_pending_delete_annotation", params, socket) do
    with_authorization(socket, :edit_content, fn _socket ->
      ElementHandlers.handle_set_pending_delete_annotation(params, socket)
    end)
  end

  # ---------------------------------------------------------------------------
  # Keyboard shortcut actions — delegate to ElementHandlers
  # ---------------------------------------------------------------------------

  def handle_event("delete_selected", _params, socket) do
    with_authorization(socket, :edit_content, fn _socket ->
      ElementHandlers.handle_delete_selected(socket) |> broadcast_scene_change()
    end)
  end

  def handle_event("duplicate_selected", _params, socket) do
    with_authorization(socket, :edit_content, fn _socket ->
      ElementHandlers.handle_duplicate_selected(socket) |> broadcast_scene_change()
    end)
  end

  def handle_event("copy_selected", _params, socket) do
    ElementHandlers.handle_copy_selected(socket)
  end

  def handle_event("paste_element", params, socket) do
    with_authorization(socket, :edit_content, fn _socket ->
      ElementHandlers.handle_paste_element(params, socket) |> broadcast_scene_change()
    end)
  end

  # ---------------------------------------------------------------------------
  # Undo / Redo — delegate to UndoRedoHandlers
  # ---------------------------------------------------------------------------

  def handle_event("undo", params, socket) do
    with_authorization(socket, :edit_content, fn _socket ->
      UndoRedoHandlers.handle_undo(params, socket) |> broadcast_scene_change()
    end)
  end

  def handle_event("redo", params, socket) do
    with_authorization(socket, :edit_content, fn _socket ->
      UndoRedoHandlers.handle_redo(params, socket) |> broadcast_scene_change()
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
           to:
             ~p"/workspaces/#{socket.assigns.workspace.slug}/projects/#{socket.assigns.project.slug}/flows/#{flow_id}"
         )}
    end
  end

  # ---------------------------------------------------------------------------
  # Sidebar tree event handlers — delegate to TreeHandlers
  # ---------------------------------------------------------------------------

  def handle_event("create_scene", params, socket) do
    with_authorization(socket, :edit_content, fn _socket ->
      TreeHandlers.handle_create_scene(params, socket) |> broadcast_scene_change()
    end)
  end

  def handle_event("create_child_scene", params, socket) do
    with_authorization(socket, :edit_content, fn _socket ->
      TreeHandlers.handle_create_child_scene(params, socket) |> broadcast_scene_change()
    end)
  end

  def handle_event("create_child_scene_from_zone", params, socket) do
    with_authorization(socket, :edit_content, fn _socket ->
      TreeHandlers.handle_create_child_scene_from_zone(params, socket) |> broadcast_scene_change()
    end)
  end

  def handle_event("create_draft", _params, socket) do
    with_authorization(socket, :edit_content, fn _socket ->
      %{scene: scene} = socket.assigns

      DraftHandlers.handle_create_draft(socket, "scene", scene.id, fn s, draft ->
        %{project: project} = s.assigns

        ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/scenes/#{scene.id}/drafts/#{draft.id}"
      end)
    end)
  end

  def handle_event("discard_draft", _params, socket) do
    with_authorization(socket, :edit_content, fn _socket ->
      %{project: project} = socket.assigns

      DraftHandlers.handle_discard_draft(
        socket,
        ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/scenes"
      )
    end)
  end

  def handle_event("set_pending_delete_scene", %{"id" => id}, socket) do
    handle_set_pending_delete(socket, id)
  end

  def handle_event("confirm_delete_scene", _params, socket) do
    handle_confirm_delete(socket, fn socket, id ->
      with_authorization(socket, :edit_content, fn _socket ->
        TreeHandlers.handle_delete_scene(%{"id" => id}, socket) |> broadcast_scene_change()
      end)
    end)
  end

  def handle_event("delete_scene", params, socket) do
    with_authorization(socket, :edit_content, fn _socket ->
      TreeHandlers.handle_delete_scene(params, socket) |> broadcast_scene_change()
    end)
  end

  def handle_event("move_to_parent", params, socket) do
    with_authorization(socket, :edit_content, fn _socket ->
      TreeHandlers.handle_move_to_parent(params, socket) |> broadcast_scene_change()
    end)
  end

  # ---------------------------------------------------------------------------
  # handle_info callbacks
  # ---------------------------------------------------------------------------

  @impl true
  def handle_async(:load_sidebar_data, {:ok, data}, socket) do
    {:noreply,
     socket
     |> assign(:scenes_tree, data.scenes_tree)
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
  def handle_info({:pin_icon_uploaded, asset}, socket) do
    case socket.assigns[:selected_element] do
      %{__struct__: Storyarn.Scenes.ScenePin} = pin ->
        case Scenes.update_pin(pin, %{"icon_asset_id" => asset.id}) do
          {:ok, updated} ->
            updated = Scenes.preload_pin_associations(updated)

            {:noreply,
             socket
             |> assign(:selected_element, updated)
             |> update_pin_in_list(updated)
             |> assign(:show_pin_icon_upload, false)
             |> assign(:_broadcast, {:pin_updated, %{id: updated.id}})
             |> push_event("pin_updated", serialize_pin(updated))
             |> put_flash(:info, dgettext("scenes", "Pin icon updated."))}
            |> broadcast_scene_change()

          {:error, _} ->
            {:noreply,
             put_flash(socket, :error, dgettext("scenes", "Could not update pin icon."))}
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

  def handle_info({:versions_section, :version_created, %{version: _}}, socket) do
    {:noreply, socket}
  end

  def handle_info(
        {:versions_section, :version_restored, %{entity: updated_scene, version: _}},
        socket
      ) do
    # Cancel any pending auto-snapshot (stale after restore)
    socket = StoryarnWeb.Helpers.AutoSnapshot.cancel(socket)

    %{project: project, can_edit: can_edit} = socket.assigns

    # Reload scene with all associations
    scene = Scenes.get_scene(project.id, updated_scene.id)
    scene_data = build_scene_data(scene, can_edit)

    result =
      {:noreply,
       socket
       |> assign(:scene, scene)
       |> assign(:layers, scene.layers || [])
       |> assign(:zones, scene.zones || [])
       |> assign(:pins, scene.pins || [])
       |> assign(:connections, scene.connections || [])
       |> assign(:annotations, scene.annotations || [])
       |> assign(:scene_data, scene_data)
       |> assign(:selected_element, nil)
       |> assign(:selected_type, nil)
       |> assign(:element_panel_open, false)
       |> assign(:scene_settings_open, false)
       |> assign(:versions_panel_open, false)
       |> assign(:undo_stack, [])
       |> assign(:redo_stack, [])
       |> assign(:_broadcast, {:scene_refreshed, %{}})
       |> push_event("scene_data", scene_data)
       |> push_event("panel-close", %{to: "#scene-versions-panel"})}

    broadcast_scene_change(result)
  end

  def handle_info({:versions_section, :version_deleted, %{version: _}}, socket) do
    {:noreply, socket}
  end

  # ---------------------------------------------------------------------------
  # Handle Info: Collaboration
  # ---------------------------------------------------------------------------

  def handle_info({Storyarn.Collaboration.Presence, {:join, presence}}, socket) do
    Collab.handle_presence_join(socket, presence)
  end

  def handle_info({Storyarn.Collaboration.Presence, {:leave, _} = event}, socket) do
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
      max_file_size: 10_485_760,
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
           socket.assigns.current_scope.user
         ) do
      {:ok, asset} -> {:ok, {:ok, asset}}
      {:error, reason} -> {:ok, {:error, reason}}
    end
  end

  defp handle_background_result([{:ok, asset}], socket),
    do: process_background_upload(socket, asset)

  defp handle_background_result(_results, socket),
    do: {:noreply, put_flash(socket, :error, dgettext("scenes", "Could not upload background."))}

  defp process_background_upload(socket, asset) do
    case Scenes.update_scene(socket.assigns.scene, %{background_asset_id: asset.id}) do
      {:ok, updated} ->
        updated = Scenes.preload_scene_background(updated)
        Collaboration.broadcast_change({:assets, socket.assigns.project.id}, :asset_created, %{})

        {:noreply,
         socket
         |> assign(:scene, updated)
         |> assign(:_broadcast, {:layer_updated, %{}})
         |> push_event("background_changed", %{url: asset.url})
         |> put_flash(:info, dgettext("scenes", "Background image updated."))}
        |> broadcast_scene_change()

      {:error, _} ->
        {:noreply, put_flash(socket, :error, dgettext("scenes", "Could not update background."))}
    end
  end

  defp background_set?(%{background_asset_id: id}) when not is_nil(id), do: true
  defp background_set?(_), do: false

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
