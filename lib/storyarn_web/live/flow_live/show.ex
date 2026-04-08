defmodule StoryarnWeb.FlowLive.Show do
  @moduledoc false

  use StoryarnWeb, :live_view
  alias StoryarnWeb.Helpers.Authorize
  alias StoryarnWeb.Live.Shared.RestorationHandlers

  import StoryarnWeb.Components.CollaborationComponents
  import StoryarnWeb.Live.Shared.TreePanelHandlers

  alias Storyarn.Collaboration
  alias Storyarn.Flows
  alias Storyarn.Projects
  alias Storyarn.Scenes
  alias Storyarn.Sheets
  alias StoryarnWeb.FlowLive.Handlers.CollaborationEventHandlers
  alias StoryarnWeb.FlowLive.Handlers.DebugHandlers
  alias StoryarnWeb.FlowLive.Handlers.EditorInfoHandlers
  alias StoryarnWeb.FlowLive.Handlers.GenericNodeHandlers
  alias StoryarnWeb.FlowLive.Handlers.NavigationHandlers
  alias StoryarnWeb.FlowLive.Handlers.PreviewHandlers
  alias StoryarnWeb.FlowLive.Helpers.CollaborationHelpers
  alias StoryarnWeb.FlowLive.Helpers.ConnectionHelpers
  alias StoryarnWeb.FlowLive.Helpers.FormHelpers
  alias StoryarnWeb.FlowLive.Helpers.NavigationHistory
  alias StoryarnWeb.FlowLive.Helpers.NodeHelpers
  alias StoryarnWeb.FlowLive.Helpers.SocketHelpers
  alias StoryarnWeb.FlowLive.Helpers.VariableHelpers
  alias StoryarnWeb.FlowLive.Nodes.Condition
  alias StoryarnWeb.FlowLive.Nodes.Dialogue
  alias StoryarnWeb.FlowLive.Nodes.Exit, as: ExitNode
  alias StoryarnWeb.FlowLive.Nodes.Instruction
  alias StoryarnWeb.FlowLive.Nodes.SlugLine
  alias StoryarnWeb.FlowLive.Nodes.Subflow
  alias StoryarnWeb.FlowLive.NodeTypeRegistry
  alias StoryarnWeb.Helpers.VersionHistoryHelpers
  alias StoryarnWeb.Live.Shared.CollaborationHelpers, as: Collab
  alias Storyarn.Versioning

  # Node types are now rendered by flow_dock.ex
  @lock_heartbeat_interval 10_000

  @impl true
  def render(%{compact: true, loading: true} = assigns) do
    ~H"""
    <Layouts.compare flash={@flash}>
      <div class="h-full"></div>
    </Layouts.compare>
    """
  end

  def render(%{compact: true} = assigns) do
    render_compact(assigns)
  end

  def render(assigns) do
    ~H"""
    <Layouts.app
      flash={@flash}
      socket={@socket}
      current_scope={@current_scope}
      project={@project}
      workspace={@workspace}
      active_tool={:flows}
      has_tree={true}
      canvas_mode={true}
      tree_panel_open={@tree_panel_open}
      tree_panel_pinned={@tree_panel_pinned}
      can_edit={@can_edit}
      restoration_banner={@restoration_banner}
      online_users={assigns[:online_users] || []}
      tree_props={
        %{
          flowsTree: @flows_tree,
          canEdit: @can_edit,
          workspaceSlug: @workspace.slug,
          projectSlug: @project.slug,
          selectedFlowId: @flow && @flow.id
        }
      }
    >
      <:top_bar_extra>
        <.vue
          :if={@flow}
          v-component="modules/flows/components/FlowHeader"
          v-socket={@socket}
          id="flow-header"
          flow-name={@flow.name}
          flow-shortcut={@flow.shortcut}
          is-main={@flow.is_main}
          can-edit={@can_edit}
          save-status={to_string(@save_status)}
          nav-history={
            %{
              back: @nav_history && NavigationHistory.peek_back(@nav_history),
              forward: @nav_history && NavigationHistory.peek_forward(@nav_history)
            }
          }
          flow-health={
            %{
              wordCount: @flow_word_count,
              errorNodes: @flow_error_nodes,
              infoNodes: @flow_info_nodes
            }
          }
          scene-selected={%{name: @scene_name, inherited: @scene_inherited}}
          project-scenes={Enum.map(@available_scenes, &Map.take(&1, [:id, :name]))}
        />
      </:top_bar_extra>
      <div class="h-full relative">
        <div class="absolute inset-0 flex flex-col">
          <div class="flex-1 relative">
            <%!-- Vue canvas --%>
            <.vue
              v-component="modules/flows/components/FlowEditor"
              v-socket={@socket}
              id={"flow-editor-#{@flow && @flow.id || "new"}"}
              class="w-full h-full"
              flow-data={if @loading, do: nil, else: Jason.encode!(@flow_data)}
              variable-map={
                if @loading,
                  do: nil,
                  else: Jason.encode!(FormHelpers.sheets_map(@all_sheets, @gallery_by_sheet))
              }
              labels={Jason.encode!(flow_canvas_labels())}
              loading={@loading}
              readonly={!@can_edit}
              user-id={@current_scope.user.id}
              user-color={Collaboration.user_color(@current_scope.user.id)}
              canvas-id={"flow-canvas-#{@flow && @flow.id || "new"}"}
              toolbar-data={Jason.encode!(toolbar_data(assigns))}
            />

            <%!-- Bottom dock (Vue) --%>
            <.vue
              :if={@flow}
              v-component="modules/flows/components/FlowDock"
              v-socket={@socket}
              id="flow-dock"
              can-edit={@can_edit}
              compact={false}
              debug-panel-open={@debug_panel_open}
              workspace-slug={@workspace.slug}
              project-slug={@project.slug}
              flow-id={@flow.id}
            />

            <%!-- Version History Panel (Vue) --%>
            <.vue
              v-component="modules/flows/components/FlowVersionHistoryPanel"
              v-socket={@socket}
              id="flow-versions-panel"
              open={@versions_panel_open}
              versions={(@history_data && @history_data[:versions]) || []}
              named-versions={(@history_data && @history_data[:named_versions]) || []}
              auto-versions={(@history_data && @history_data[:auto_versions]) || []}
              has-more={(@history_data && @history_data[:has_more]) || false}
              can-name-version={(@history_data && @history_data[:can_name_version]) || false}
              current-version-id={@history_data && @history_data[:current_version_id]}
              can-edit={@can_edit}
              loading={@versions_panel_open && is_nil(@history_data)}
            />
          </div>

          <%!-- Debug Panel (Vue) --%>
          <.vue
            v-component="modules/flows/components/FlowDebugPanel"
            v-socket={@socket}
            id="flow-debug-panel"
            open={@debug_panel_open && @debug_state != nil}
            state={@debug_state}
            nodes={@debug_nodes}
            controls={
              %{
                activeTab: @debug_active_tab,
                autoPlaying: @debug_auto_playing,
                speed: @debug_speed,
                varFilter: @debug_var_filter,
                varChangedOnly: @debug_var_changed_only,
                flowName: @flow && @flow.name,
                stepLimitReached: @debug_step_limit_reached
              }
            }
          />
        </div>

        <%!-- Collaboration Toast --%>
        <.collab_toast
          :if={@collab_toast}
          action={@collab_toast.action}
          user_email={@collab_toast.user_email}
          user_color={@collab_toast.user_color}
        />
      </div>

      <%!-- Builder Sidebar (Vue) --%>
      <.vue
        v-component="modules/flows/components/FlowBuilderPanel"
        v-socket={@socket}
        id="flow-builder-panel"
        open={@editing_mode == :builder && @selected_node != nil}
        node-type={@selected_node && @selected_node.type}
        node-id={@selected_node && @selected_node.id}
        condition={@selected_node && @selected_node.data["condition"]}
        assignments={@selected_node && (@selected_node.data["assignments"] || [])}
        switch-mode={@selected_node && @selected_node.data["switch_mode"] == true}
        project-variables={Jason.encode!(@project_variables)}
        can-edit={@can_edit}
      />

      <%!-- Screenplay Editor sidebar (Vue) --%>
      <.vue
        v-component="modules/flows/components/FlowScreenplayEditor"
        v-socket={@socket}
        id="flow-screenplay-editor"
        open={@editing_mode in [:screenplay, :editor] && @selected_node != nil}
        node={@selected_node && %{id: @selected_node.id, data: @selected_node.data}}
        can-edit={@can_edit}
        all-sheets={Enum.map(@all_sheets, &%{id: &1.id, name: &1.name})}
        project-variables={Jason.encode!(@project_variables)}
      />

      <%!-- Dialogue Preview (Vue) --%>
      <.vue
        v-component="modules/flows/components/FlowPreview"
        v-socket={@socket}
        id="flow-preview"
        {PreviewHandlers.serialize_preview_state(@socket)}
      />
    </Layouts.app>
    """
  end

  defp render_compact(assigns) do
    ~H"""
    <Layouts.compare flash={@flash}>
      <div class="h-full relative">
        <.vue
          v-component="modules/flows/components/FlowEditor"
          v-socket={@socket}
          id={"flow-editor-compact-#{@flow.id}"}
          class="w-full h-full"
          flow-data={Jason.encode!(@flow_data)}
          variable-map={Jason.encode!(FormHelpers.sheets_map(@all_sheets, @gallery_by_sheet))}
          labels={Jason.encode!(flow_canvas_labels())}
          loading={false}
          readonly={!@can_edit}
          user-id={@current_scope.user.id}
          user-color={Collaboration.user_color(@current_scope.user.id)}
          canvas-id={"flow-canvas-#{@flow.id}"}
          toolbar-data={Jason.encode!(toolbar_data(assigns))}
        />
      </div>
    </Layouts.compare>
    """
  end

  # ===========================================================================
  # Mount & Setup
  # ===========================================================================

  @impl true
  def mount(
        %{"workspace_slug" => workspace_slug, "project_slug" => project_slug},
        _session,
        socket
      ) do
    case Projects.get_project_by_slugs(socket.assigns.current_scope, workspace_slug, project_slug) do
      {:ok, project, membership} ->
        can_edit = Projects.can?(membership.role, :edit_content)

        if connected?(socket), do: Collaboration.subscribe_restoration(project.id)

        {can_edit, restoration_banner} =
          RestorationHandlers.check_restoration_lock(project.id, can_edit)

        socket =
          socket
          |> assign(focus_layout_defaults())
          |> assign(:compact, false)
          |> assign(:loading, true)
          |> assign(:project, project)
          |> assign(:workspace, project.workspace)
          |> assign(:membership, membership)
          |> assign(:can_edit, can_edit)
          |> assign(:restoration_banner, restoration_banner)
          # Defaults — flow loaded in handle_params
          |> assign(:flow, nil)
          |> assign(:nav_history, nil)
          |> assign(:flows_tree, Flows.list_flows_tree(project.id))
          |> assign(:pending_delete_id, nil)
          |> assign(:scene_name, nil)
          |> assign(:scene_inherited, false)
          |> assign(:available_scenes, [])
          |> assign(:flow_word_count, 0)
          |> assign(:flow_error_nodes, [])
          |> assign(:flow_info_nodes, [])
          |> assign(:save_status, :idle)
          |> assign(:selected_node, nil)
          |> assign(:node_form, nil)
          |> assign(:editing_mode, nil)
          |> assign(:debug_panel_open, false)
          |> assign(:debug_state, nil)
          |> assign(:debug_active_tab, "console")
          |> assign(:debug_nodes, %{})
          |> assign(:debug_auto_playing, false)
          |> assign(:debug_speed, 800)
          |> assign(:debug_editing_var, nil)
          |> assign(:debug_var_filter, "")
          |> assign(:debug_var_changed_only, false)
          |> assign(:debug_step_limit_reached, false)
          |> assign(:collab_toast, nil)
          |> assign(:versions_panel_open, false)
          |> assign(:history_data, nil)
          |> assign(:all_sheets, [])
          |> assign(:gallery_by_sheet, %{})
          |> assign(:flow_hubs, [])
          |> assign(:available_flows, [])
          |> assign(:flow_search_has_more, false)
          |> assign(:flow_search_deep, false)
          |> assign(:subflow_exits, [])
          |> assign(:referencing_jumps, [])
          |> assign(:referencing_flows, [])
          |> assign(:project_scenes, [])
          |> assign(:node_select_loading, false)
          |> assign(:panel_sections, %{})
          |> assign(:project_variables, [])

        {:ok, socket}

      {:error, _reason} ->
        {:ok,
         socket
         |> put_flash(:error, dgettext("flows", "You don't have access to this project."))
         |> redirect(to: ~p"/workspaces")}
    end
  end

  defp maybe_restore_debug_session(socket) do
    user_id = socket.assigns.current_scope.user.id
    project_id = socket.assigns.project.id

    case Flows.debug_session_take({user_id, project_id}) do
      nil ->
        socket

      debug_assigns ->
        socket =
          if debug_assigns.debug_auto_playing do
            ref = Process.send_after(self(), :debug_auto_step, debug_assigns.debug_speed)
            assign(socket, :debug_auto_timer, ref)
          else
            socket
          end

        socket
        |> assign(:debug_state, debug_assigns.debug_state)
        |> assign(:debug_panel_open, debug_assigns.debug_panel_open)
        |> assign(:debug_active_tab, debug_assigns.debug_active_tab)
        |> assign(:debug_nodes, debug_assigns.debug_nodes)
        |> assign(:debug_connections, debug_assigns.debug_connections)
        |> assign(:debug_speed, debug_assigns.debug_speed)
        |> assign(:debug_auto_playing, debug_assigns.debug_auto_playing)
        |> assign(:debug_editing_var, debug_assigns.debug_editing_var)
        |> assign(:debug_var_filter, debug_assigns.debug_var_filter)
        |> assign(:debug_var_changed_only, debug_assigns.debug_var_changed_only)
        |> assign(:debug_step_limit_reached, debug_assigns[:debug_step_limit_reached] || false)
        |> push_debug_canvas_events(debug_assigns.debug_state)
    end
  end

  defp push_debug_canvas_events(socket, state) do
    # execution_path is stored newest-first; reverse for display
    path = Enum.reverse(state.execution_path)

    socket
    |> push_event("debug_highlight_node", %{
      node_id: state.current_node_id,
      status: to_string(state.status),
      execution_path: path
    })
    |> push_event("debug_highlight_connections", %{
      active_connection: nil,
      execution_path: path
    })
    |> push_event("debug_update_breakpoints", %{
      breakpoint_ids: MapSet.to_list(state.breakpoints)
    })
  end

  @impl true
  def handle_params(%{"id" => flow_id} = params, _url, socket) do
    compact = params["layout"] == "compact"
    socket = assign(socket, :compact, compact)

    current_id =
      case socket.assigns.flow do
        %{id: id} -> to_string(id)
        _ -> nil
      end

    if flow_id == current_id do
      # Same flow — just handle ?node= param
      if socket.assigns.loading do
        {:noreply, socket}
      else
        {:noreply, maybe_navigate_to_node(socket, params["node"])}
      end
    else
      {:noreply, load_flow(socket, flow_id)}
    end
  end

  defp load_flow(socket, flow_id) do
    %{project: project} = socket.assigns

    case Flows.get_flow_brief(project.id, flow_id) do
      nil ->
        socket
        |> put_flash(:error, dgettext("flows", "Flow not found."))
        |> push_navigate(
          to: ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/flows"
        )

      flow ->
        # Teardown collaboration for previous flow (if switching)
        case socket.assigns.flow do
          %{id: prev_id} when prev_id != flow.id ->
            CollaborationHelpers.teardown_collaboration(
              prev_id,
              socket.assigns.current_scope.user.id
            )

          _ ->
            :ok
        end

        socket =
          socket
          |> assign(:loading, true)
          |> assign(:flow, flow)

        # V2: start async load directly (V1 defers via FlowLoader hook)
        if connected?(socket) do
          project = socket.assigns.project

          start_async(socket, :load_flow_data, fn ->
            full_flow = Flows.get_flow!(project.id, flow.id)
            project_variables = VariableHelpers.list_all_variables(project.id)

            %{
              flow: full_flow,
              flow_data:
                Flows.serialize_for_canvas(full_flow, project_variables: project_variables),
              all_sheets: Sheets.list_all_sheets(project.id),
              gallery_by_sheet: Sheets.batch_load_gallery_data_by_sheet(project.id),
              flow_hubs: Flows.list_hubs(flow.id),
              project_variables: project_variables,
              flows_tree: Flows.list_flows_tree(project.id),
              available_scenes: Scenes.list_scenes(project.id)
            }
          end)
        else
          socket
        end
    end
  end

  defp maybe_navigate_to_node(socket, nil), do: socket

  defp maybe_navigate_to_node(socket, node_id) do
    case Integer.parse(node_id) do
      {id, ""} -> push_event(socket, "navigate_to_node", %{node_db_id: id})
      _ -> socket
    end
  end

  # ===========================================================================
  # Event Handlers (thin delegation)
  # ===========================================================================

  @impl true
  # Tree panel events (from AppLayout)
  def handle_event("tree_panel_" <> _ = event, params, socket),
    do: handle_tree_panel_event(event, params, socket)

  def handle_event("open_versions_panel", _params, %{assigns: %{compact: true}} = socket) do
    {:noreply, socket}
  end

  def handle_event("open_versions_panel", _params, socket) do
    socket =
      if is_nil(socket.assigns.history_data) do
        VersionHistoryHelpers.load_history_data(
          socket,
          "flow",
          socket.assigns.flow,
          socket.assigns.project.id,
          socket.assigns.workspace.id
        )
      else
        socket
      end

    {:noreply, assign(socket, :versions_panel_open, true)}
  end

  def handle_event("close_versions_panel", _params, socket) do
    {:noreply, assign(socket, :versions_panel_open, false)}
  end

  # ---------------------------------------------------------------------------
  # Version History handlers (Vue FlowVersionHistoryPanel)
  # ---------------------------------------------------------------------------

  def handle_event("create_version", %{"title" => title, "description" => description}, socket) do
    Authorize.with_authorization(socket, :edit_content, fn _socket ->
      title = if title == "", do: nil, else: title
      description = if description == "", do: nil, else: description

      if title == nil do
        {:noreply, put_flash(socket, :error, dgettext("versioning", "Title is required."))}
      else
        flow = socket.assigns.flow
        user_id = socket.assigns.current_scope.user.id
        project_id = socket.assigns.project.id

        case Versioning.create_version("flow", flow, project_id, user_id,
               title: title,
               description: description
             ) do
          {:ok, _version} ->
            {:noreply,
             socket
             |> reload_history_data()
             |> put_flash(:info, dgettext("versioning", "Version created."))}

          {:error, _} ->
            {:noreply,
             put_flash(socket, :error, dgettext("versioning", "Could not create version."))}
        end
      end
    end)
  end

  def handle_event("promote_version", params, socket) do
    Authorize.with_authorization(socket, :edit_content, fn _socket ->
      %{"version_number" => vn, "title" => title, "description" => description} = params
      title = if title == "", do: nil, else: title
      description = if description == "", do: nil, else: description

      with {:ok, number} <- VersionHistoryHelpers.parse_version_number(vn),
           version when not is_nil(version) <-
             Versioning.get_version("flow", socket.assigns.flow.id, number) do
        case Versioning.update_version(version, %{title: title, description: description}) do
          {:ok, _} ->
            {:noreply,
             socket
             |> reload_history_data()
             |> put_flash(:info, dgettext("versioning", "Version named successfully."))}

          {:error, _} ->
            {:noreply,
             put_flash(socket, :error, dgettext("versioning", "Could not name version."))}
        end
      else
        _ -> {:noreply, put_flash(socket, :error, dgettext("versioning", "Version not found."))}
      end
    end)
  end

  def handle_event("delete_version", %{"version_number" => vn}, socket) do
    Authorize.with_authorization(socket, :edit_content, fn _socket ->
      with {:ok, number} <- VersionHistoryHelpers.parse_version_number(vn),
           version when not is_nil(version) <-
             Versioning.get_version("flow", socket.assigns.flow.id, number) do
        case Versioning.delete_version(version) do
          {:ok, _} ->
            {:noreply,
             socket
             |> reload_history_data()
             |> put_flash(:info, dgettext("versioning", "Version deleted."))}

          {:error, _} ->
            {:noreply,
             put_flash(socket, :error, dgettext("versioning", "Could not delete version."))}
        end
      else
        _ -> {:noreply, put_flash(socket, :error, dgettext("versioning", "Version not found."))}
      end
    end)
  end

  def handle_event("load_more_versions", _params, socket) do
    history = socket.assigns.history_data

    if history do
      next_page = (history[:page] || 1) + 1

      {:noreply,
       VersionHistoryHelpers.load_more_history(socket, "flow", socket.assigns.flow.id, next_page)}
    else
      {:noreply, socket}
    end
  end

  def handle_event("preview_restore", %{"version_number" => vn}, socket) do
    with {:ok, number} <- VersionHistoryHelpers.parse_version_number(vn),
         version when not is_nil(version) <-
           Versioning.get_version("flow", socket.assigns.flow.id, number) do
      VersionHistoryHelpers.detect_and_show_restore_preview(
        socket,
        "flow",
        socket.assigns.flow,
        version
      )
    else
      _ -> {:noreply, put_flash(socket, :error, dgettext("versioning", "Version not found."))}
    end
  end

  def handle_event("save_and_restore", %{"version_number" => vn}, socket) do
    Authorize.with_authorization(socket, :edit_content, fn _socket ->
      with {:ok, number} <- VersionHistoryHelpers.parse_version_number(vn),
           version when not is_nil(version) <-
             Versioning.get_version("flow", socket.assigns.flow.id, number) do
        flow = socket.assigns.flow
        project_id = socket.assigns.project.id
        user_id = socket.assigns.current_scope.user.id

        Versioning.create_version("flow", flow, project_id, user_id,
          title: dgettext("versioning", "Before restore to v%{n}", n: number)
        )

        VersionHistoryHelpers.show_conflict_preview(socket, "flow", flow, version, true)
      else
        _ -> {:noreply, socket}
      end
    end)
  end

  def handle_event("discard_and_restore", %{"version_number" => vn}, socket) do
    Authorize.with_authorization(socket, :edit_content, fn _socket ->
      with {:ok, number} <- VersionHistoryHelpers.parse_version_number(vn),
           version when not is_nil(version) <-
             Versioning.get_version("flow", socket.assigns.flow.id, number) do
        VersionHistoryHelpers.show_conflict_preview(
          socket,
          "flow",
          socket.assigns.flow,
          version,
          true
        )
      else
        _ -> {:noreply, socket}
      end
    end)
  end

  def handle_event("confirm_restore", %{"version_number" => vn} = params, socket) do
    Authorize.with_authorization(socket, :edit_content, fn _socket ->
      with {:ok, number} <- VersionHistoryHelpers.parse_version_number(vn),
           version when not is_nil(version) <-
             Versioning.get_version("flow", socket.assigns.flow.id, number) do
        skip = params["skip_pre_snapshot"] == true

        case Versioning.restore_version(version, "flow", socket.assigns.flow,
               skip_pre_snapshot: skip
             ) do
          {:ok, _} ->
            {:noreply,
             socket
             |> push_event("version_restored", %{})
             |> put_flash(:info, dgettext("versioning", "Version restored."))
             |> push_navigate(
               to:
                 ~p"/workspaces/#{socket.assigns.workspace.slug}/projects/#{socket.assigns.project.slug}/flows/#{socket.assigns.flow.id}"
             )}

          {:error, _} ->
            {:noreply,
             put_flash(socket, :error, dgettext("versioning", "Could not restore version."))}
        end
      else
        _ -> {:noreply, socket}
      end
    end)
  end

  def handle_event("compare_version", %{"version_number" => vn}, socket) do
    with {:ok, number} <- VersionHistoryHelpers.parse_version_number(vn) do
      %{workspace: workspace, project: project, flow: flow} = socket.assigns

      compare_url =
        ~p"/workspaces/#{workspace.slug}/projects/#{project.slug}/flows/#{flow.id}/compare/#{number}"

      {:noreply, push_navigate(socket, to: compare_url)}
    else
      _ -> {:noreply, socket}
    end
  end

  # Triggered by the FlowLoader hook after the browser has painted the spinner.
  def handle_event("load_flow_data", _params, socket) do
    %{flow: flow, project: project} = socket.assigns

    socket =
      start_async(socket, :load_flow_data, fn ->
        full_flow = Flows.get_flow!(project.id, flow.id)
        project_variables = VariableHelpers.list_all_variables(project.id)

        %{
          flow: full_flow,
          flow_data: Flows.serialize_for_canvas(full_flow, project_variables: project_variables),
          all_sheets: Sheets.list_all_sheets(project.id),
          gallery_by_sheet: Sheets.batch_load_gallery_data_by_sheet(project.id),
          flow_hubs: Flows.list_hubs(flow.id),
          project_variables: project_variables,
          flows_tree: Flows.list_flows_tree(project.id),
          available_scenes: Scenes.list_scenes(project.id)
        }
      end)

    {:noreply, socket}
  end

  def handle_event("add_node", params, socket) do
    Authorize.with_authorization(socket, :edit_content, fn _socket ->
      GenericNodeHandlers.handle_add_node(params, socket)
    end)
  end

  def handle_event("add_annotation", params, socket) do
    Authorize.with_authorization(socket, :edit_content, fn _socket ->
      GenericNodeHandlers.handle_add_node(
        %{
          "type" => "annotation",
          "position_x" => params["position_x"] || 100,
          "position_y" => params["position_y"] || 100
        },
        socket
      )
    end)
  end

  def handle_event("save_name", params, socket) do
    Authorize.with_authorization(socket, :edit_content, fn _socket ->
      GenericNodeHandlers.handle_save_name(params, socket)
    end)
  end

  def handle_event("save_shortcut", params, socket) do
    Authorize.with_authorization(socket, :edit_content, fn _socket ->
      GenericNodeHandlers.handle_save_shortcut(params, socket)
    end)
  end

  def handle_event("restore_flow_meta", params, socket) do
    Authorize.with_authorization(socket, :edit_content, fn _socket ->
      GenericNodeHandlers.handle_restore_flow_meta(params, socket)
    end)
  end

  def handle_event("node_selected", params, socket) do
    GenericNodeHandlers.handle_node_selected(params, socket)
  end

  def handle_event("node_double_clicked", params, socket) do
    GenericNodeHandlers.handle_node_double_clicked(params, socket)
  end

  def handle_event("open_screenplay", params, socket) do
    Dialogue.Node.handle_open_screenplay(params, socket)
  end

  def handle_event("open_sidebar", _params, socket) do
    GenericNodeHandlers.handle_open_sidebar(socket)
  end

  def handle_event("open_builder", _params, socket) do
    case socket.assigns.selected_node do
      nil ->
        {:noreply, socket}

      node ->
        socket =
          socket
          |> assign(:editing_mode, :builder)
          |> push_event("center_on_node", %{id: node.id, sidebar_width: 480})

        {:noreply, socket}
    end
  end

  def handle_event("close_builder", _params, socket) do
    {:noreply, assign(socket, :editing_mode, :toolbar)}
  end

  def handle_event("close_editor", _params, socket) do
    GenericNodeHandlers.handle_close_editor(socket)
  end

  def handle_event("deselect_node", _params, socket) do
    GenericNodeHandlers.handle_deselect_node(socket)
  end

  def handle_event("create_sheet", _params, socket) do
    Authorize.with_authorization(socket, :edit_content, fn _socket ->
      GenericNodeHandlers.handle_create_sheet(socket)
    end)
  end

  def handle_event("node_dragging", params, socket) do
    Authorize.with_authorization(socket, :edit_content, fn _socket ->
      GenericNodeHandlers.handle_node_dragging(params, socket)
    end)
  end

  def handle_event("node_moved", params, socket) do
    Authorize.with_authorization(socket, :edit_content, fn _socket ->
      GenericNodeHandlers.handle_node_moved(params, socket)
    end)
  end

  def handle_event("batch_update_positions", params, socket) do
    Authorize.with_authorization(socket, :edit_content, fn _socket ->
      GenericNodeHandlers.handle_batch_update_positions(params, socket)
    end)
  end

  def handle_event("search_available_flows", params, socket) do
    GenericNodeHandlers.handle_search_available_flows(params, socket)
  end

  def handle_event("search_flows_more", _params, socket) do
    GenericNodeHandlers.handle_search_flows_more(socket)
  end

  def handle_event("toggle_deep_search", _params, socket) do
    GenericNodeHandlers.handle_toggle_deep_search(socket)
  end

  def handle_event("update_node_data", %{"node" => _} = params, socket) do
    Authorize.with_authorization(socket, :edit_content, fn _socket ->
      GenericNodeHandlers.handle_update_node_data(params, socket)
    end)
  end

  # Catch-all for update_node_data events without the "node" key (no-op)
  def handle_event("update_node_data", _params, socket) do
    {:noreply, socket}
  end

  def handle_event("update_node_text", params, socket) do
    Authorize.with_authorization(socket, :edit_content, fn _socket ->
      GenericNodeHandlers.handle_update_node_text(params, socket)
    end)
  end

  def handle_event("mention_suggestions", params, socket) do
    GenericNodeHandlers.handle_mention_suggestions(params, socket)
  end

  def handle_event("delete_node", params, socket) do
    Authorize.with_authorization(socket, :edit_content, fn _socket ->
      GenericNodeHandlers.handle_delete_node(params, socket)
    end)
  end

  def handle_event("restore_node", %{"id" => node_id}, socket) do
    Authorize.with_authorization(socket, :edit_content, fn _socket ->
      NodeHelpers.restore_node(socket, node_id)
    end)
  end

  def handle_event("restore_node_data", %{"id" => node_id, "data" => data}, socket) do
    Authorize.with_authorization(socket, :edit_content, fn _socket ->
      NodeHelpers.restore_node_data(socket, node_id, data)
    end)
  end

  def handle_event("duplicate_node", params, socket) do
    Authorize.with_authorization(socket, :edit_content, fn _socket ->
      GenericNodeHandlers.handle_duplicate_node(params, socket)
    end)
  end

  def handle_event("generate_technical_id", _params, socket) do
    Authorize.with_authorization(socket, :edit_content, fn _socket ->
      node = socket.assigns.selected_node

      cond do
        node && node.type == "dialogue" ->
          Dialogue.Node.handle_generate_technical_id(socket)

        node && node.type == "exit" ->
          ExitNode.Node.handle_generate_technical_id(socket)

        node && node.type == "slug_line" ->
          SlugLine.Node.handle_generate_technical_id(socket)

        true ->
          {:noreply, socket}
      end
    end)
  end

  def handle_event("update_node_field", params, socket) do
    Authorize.with_authorization(socket, :edit_content, fn _socket ->
      GenericNodeHandlers.handle_update_node_field(params, socket)
    end)
  end

  def handle_event("update_annotation_color", %{"value" => color}, socket) do
    Authorize.with_authorization(socket, :edit_content, fn _socket ->
      update_selected_node_data(socket, "color", color)
    end)
  end

  def handle_event("update_annotation_font_size", %{"value" => size}, socket)
      when size in ["sm", "md", "lg"] do
    Authorize.with_authorization(socket, :edit_content, fn _socket ->
      update_selected_node_data(socket, "font_size", size)
    end)
  end

  # Responses (dialogue-specific)
  def handle_event("add_response", params, socket) do
    Authorize.with_authorization(socket, :edit_content, fn _socket ->
      Dialogue.Node.handle_add_response(params, socket)
    end)
  end

  def handle_event("remove_response", params, socket) do
    Authorize.with_authorization(socket, :edit_content, fn _socket ->
      Dialogue.Node.handle_remove_response(params, socket)
    end)
  end

  def handle_event("update_response_text", params, socket) do
    Authorize.with_authorization(socket, :edit_content, fn _socket ->
      Dialogue.Node.handle_update_response_text(params, socket)
    end)
  end

  def handle_event("update_response_condition", params, socket) do
    Authorize.with_authorization(socket, :edit_content, fn _socket ->
      Dialogue.Node.handle_update_response_condition(params, socket)
    end)
  end

  def handle_event("update_response_instruction", params, socket) do
    Authorize.with_authorization(socket, :edit_content, fn _socket ->
      Dialogue.Node.handle_update_response_instruction(params, socket)
    end)
  end

  def handle_event("update_response_instruction_builder", params, socket) do
    Authorize.with_authorization(socket, :edit_content, fn _socket ->
      Dialogue.Node.handle_update_response_instruction_builder(params, socket)
    end)
  end

  # Connections
  def handle_event("connection_created", params, socket) do
    Authorize.with_authorization(socket, :edit_content, fn _socket ->
      ConnectionHelpers.create_connection(socket, params)
    end)
  end

  def handle_event(
        "connection_deleted",
        %{"source_node_id" => source_id, "target_node_id" => target_id},
        socket
      ) do
    Authorize.with_authorization(socket, :edit_content, fn _socket ->
      ConnectionHelpers.delete_connection_by_nodes(socket, source_id, target_id)
    end)
  end

  # Condition builders
  def handle_event("update_response_condition_builder", params, socket) do
    Authorize.with_authorization(socket, :edit_content, fn _socket ->
      Condition.Node.handle_update_response_condition_builder(params, socket)
    end)
  end

  def handle_event("update_condition_builder", params, socket) do
    Authorize.with_authorization(socket, :edit_content, fn _socket ->
      Condition.Node.handle_update_condition_builder(params, socket)
    end)
  end

  def handle_event("toggle_switch_mode", _params, socket) do
    Authorize.with_authorization(socket, :edit_content, fn _socket ->
      Condition.Node.handle_toggle_switch_mode(socket)
    end)
  end

  # Instruction builder
  def handle_event("update_instruction_builder", params, socket) do
    Authorize.with_authorization(socket, :edit_content, fn _socket ->
      Instruction.Node.handle_update_instruction_builder(params, socket)
    end)
  end

  # Expression editor tab toggle (Builder ↔ Code)
  def handle_event("toggle_expression_tab", %{"id" => id, "tab" => tab}, socket) do
    panel_sections = Map.put(socket.assigns.panel_sections, "tab_#{id}", tab)
    {:noreply, assign(socket, :panel_sections, panel_sections)}
  end

  # Subflow
  def handle_event("navigate_to_subflow", %{"flow-id" => flow_id_str}, socket) do
    NavigationHandlers.handle_navigate_to_flow(flow_id_str, socket)
  end

  def handle_event("nav_back", _params, %{assigns: %{nav_history: nil}} = socket) do
    {:noreply, socket}
  end

  def handle_event("nav_back", _params, socket) do
    case NavigationHistory.back(socket.assigns.nav_history) do
      {:ok, entry, updated_history} ->
        store_nav_history(socket, updated_history)

        {:noreply,
         push_patch(socket,
           to:
             ~p"/workspaces/#{socket.assigns.workspace.slug}/projects/#{socket.assigns.project.slug}/flows/#{entry.flow_id}"
         )}

      :at_start ->
        {:noreply, socket}
    end
  end

  def handle_event("nav_forward", _params, %{assigns: %{nav_history: nil}} = socket) do
    {:noreply, socket}
  end

  def handle_event("nav_forward", _params, socket) do
    case NavigationHistory.forward(socket.assigns.nav_history) do
      {:ok, entry, updated_history} ->
        store_nav_history(socket, updated_history)

        {:noreply,
         push_patch(socket,
           to:
             ~p"/workspaces/#{socket.assigns.workspace.slug}/projects/#{socket.assigns.project.slug}/flows/#{entry.flow_id}"
         )}

      :at_end ->
        {:noreply, socket}
    end
  end

  def handle_event("update_subflow_reference", %{"referenced_flow_id" => ref_id}, socket) do
    Authorize.with_authorization(socket, :edit_content, fn _socket ->
      Subflow.Node.handle_update_reference(ref_id, socket)
    end)
  end

  # Create linked flow (exit flow_reference / subflow)
  def handle_event("create_linked_flow", %{"node-id" => node_id_str}, socket) do
    Authorize.with_authorization(socket, :edit_content, fn _socket ->
      case Flows.get_node(socket.assigns.flow.id, node_id_str) do
        nil ->
          {:noreply, put_flash(socket, :error, dgettext("flows", "Node not found."))}

        node ->
          do_create_linked_flow(socket, node)
      end
    end)
  end

  # Exit node events
  def handle_event("update_exit_mode", %{"mode" => mode}, socket) do
    Authorize.with_authorization(socket, :edit_content, fn _socket ->
      ExitNode.Node.handle_update_exit_mode(mode, socket)
    end)
  end

  def handle_event("update_exit_reference", %{"flow-id" => flow_id}, socket) do
    Authorize.with_authorization(socket, :edit_content, fn _socket ->
      ExitNode.Node.handle_update_exit_reference(flow_id, socket)
    end)
  end

  def handle_event("add_outcome_tag", %{"tag" => tag}, socket) do
    Authorize.with_authorization(socket, :edit_content, fn _socket ->
      ExitNode.Node.handle_add_outcome_tag(tag, socket)
    end)
  end

  def handle_event("remove_outcome_tag", %{"tag" => tag}, socket) do
    Authorize.with_authorization(socket, :edit_content, fn _socket ->
      ExitNode.Node.handle_remove_outcome_tag(tag, socket)
    end)
  end

  def handle_event("update_outcome_color", %{"value" => color}, socket) do
    Authorize.with_authorization(socket, :edit_content, fn _socket ->
      ExitNode.Node.handle_update_outcome_color(color, socket)
    end)
  end

  def handle_event("update_exit_target", params, socket) do
    Authorize.with_authorization(socket, :edit_content, fn _socket ->
      ExitNode.Node.handle_update_exit_target(params, socket)
    end)
  end

  # Scene map
  def handle_event("update_scene", %{"scene_id" => scene_id}, socket) do
    Authorize.with_authorization(socket, :edit_content, fn _socket ->
      scene_id =
        if scene_id in [nil, "", "null"],
          do: nil,
          else: Storyarn.Shared.MapUtils.parse_int(scene_id)

      case Flows.update_flow_scene(socket.assigns.flow, %{scene_id: scene_id}) do
        {:ok, updated_flow} ->
          {:noreply,
           socket
           |> assign(:flow, updated_flow)
           |> assign_scene_info(updated_flow)}

        {:error, _changeset} ->
          {:noreply, put_flash(socket, :error, dgettext("flows", "Could not update scene map."))}
      end
    end)
  end

  # Hub color picker
  def handle_event("update_hub_color", %{"color" => color}, socket) do
    Authorize.with_authorization(socket, :edit_content, fn _socket ->
      validated =
        StoryarnWeb.FlowLive.Components.NodeTypeHelpers.validate_hex_color(
          color,
          Flows.hub_colors_default_hex()
        )

      update_selected_node_data(socket, "color", validated)
    end)
  end

  def handle_event("navigate_to_exit_flow", %{"flow-id" => flow_id_str}, socket) do
    NavigationHandlers.handle_navigate_to_flow(flow_id_str, socket)
  end

  def handle_event("navigate_to_referencing_flow", %{"flow-id" => flow_id_str}, socket) do
    NavigationHandlers.handle_navigate_to_flow(flow_id_str, socket)
  end

  # Debug
  def handle_event("debug_start", _params, socket) do
    DebugHandlers.handle_debug_start(socket)
  end

  def handle_event("debug_step", _params, socket) do
    DebugHandlers.handle_debug_step(socket)
  end

  def handle_event("debug_step_back", _params, socket) do
    DebugHandlers.handle_debug_step_back(socket)
  end

  def handle_event("debug_choose_response", params, socket) do
    DebugHandlers.handle_debug_choose_response(params, socket)
  end

  def handle_event("debug_reset", _params, socket) do
    DebugHandlers.handle_debug_reset(socket)
  end

  def handle_event("debug_stop", _params, socket) do
    DebugHandlers.handle_debug_stop(socket)
  end

  def handle_event("debug_tab_change", params, socket) do
    DebugHandlers.handle_debug_tab_change(params, socket)
  end

  def handle_event("debug_play", _params, socket) do
    DebugHandlers.handle_debug_play(socket)
  end

  def handle_event("debug_pause", _params, socket) do
    DebugHandlers.handle_debug_pause(socket)
  end

  def handle_event("debug_set_speed", params, socket) do
    DebugHandlers.handle_debug_set_speed(params, socket)
  end

  def handle_event("debug_edit_variable", params, socket) do
    DebugHandlers.handle_debug_edit_variable(params, socket)
  end

  def handle_event("debug_cancel_edit", _params, socket) do
    DebugHandlers.handle_debug_cancel_edit(socket)
  end

  def handle_event("debug_set_variable", params, socket) do
    DebugHandlers.handle_debug_set_variable(params, socket)
  end

  def handle_event("debug_var_filter", params, socket) do
    DebugHandlers.handle_debug_var_filter(params, socket)
  end

  def handle_event("debug_var_toggle_changed", _params, socket) do
    DebugHandlers.handle_debug_var_toggle_changed(socket)
  end

  def handle_event("debug_change_start_node", params, socket) do
    DebugHandlers.handle_debug_change_start_node(params, socket)
  end

  def handle_event("debug_toggle_breakpoint", params, socket) do
    DebugHandlers.handle_debug_toggle_breakpoint(params, socket)
  end

  def handle_event("debug_continue_past_limit", _params, socket) do
    DebugHandlers.handle_debug_continue_past_limit(socket)
  end

  # Collaboration & Preview
  def handle_event("cursor_moved", params, socket) do
    CollaborationEventHandlers.handle_cursor_moved(params, socket)
  end

  def handle_event("start_preview", params, socket) do
    PreviewHandlers.handle_start_preview(params, socket)
  end

  def handle_event("preview_select_response", params, socket) do
    PreviewHandlers.handle_select_response(params, socket)
  end

  def handle_event("preview_continue", params, socket) do
    PreviewHandlers.handle_continue(params, socket)
  end

  def handle_event("preview_go_back", params, socket) do
    PreviewHandlers.handle_go_back(params, socket)
  end

  def handle_event("preview_close", _params, socket) do
    PreviewHandlers.handle_close(socket)
  end

  def handle_event("request_flow_refresh", _params, socket) do
    EditorInfoHandlers.handle_flow_refresh(socket)
  end

  def handle_event("navigate_to_hub", %{"id" => node_id}, socket) do
    case Integer.parse(node_id) do
      {id, ""} -> {:noreply, push_event(socket, "navigate_to_hub", %{jump_db_id: id})}
      _ -> {:noreply, socket}
    end
  end

  def handle_event("navigate_to_node", %{"id" => node_id}, socket) do
    case Integer.parse(node_id) do
      {id, ""} -> {:noreply, push_event(socket, "navigate_to_node", %{node_db_id: id})}
      _ -> {:noreply, socket}
    end
  end

  def handle_event("navigate_to_jumps", %{"id" => node_id}, socket) do
    case Integer.parse(node_id) do
      {id, ""} -> {:noreply, push_event(socket, "navigate_to_jumps", %{hub_db_id: id})}
      _ -> {:noreply, socket}
    end
  end

  # ===========================================================================
  # Sidebar Tree Event Handlers
  # ===========================================================================

  def handle_event("create_flow", _params, socket) do
    Authorize.with_authorization(socket, :edit_content, fn _socket ->
      handle_create_entity(
        socket,
        %{name: dgettext("flows", "Untitled")},
        &Flows.create_flow/2,
        &flow_path/2,
        dgettext("flows", "Could not create flow."),
        patch: true,
        reload_tree_fn: &reload_flows_tree/1
      )
    end)
  end

  def handle_event("create_child_flow", %{"parent-id" => parent_id}, socket) do
    Authorize.with_authorization(socket, :edit_content, fn _socket ->
      handle_create_child(
        socket,
        parent_id,
        %{name: dgettext("flows", "Untitled")},
        &Flows.create_flow/2,
        &flow_path/2,
        dgettext("flows", "Could not create flow."),
        patch: true,
        reload_tree_fn: &reload_flows_tree/1
      )
    end)
  end

  def handle_event("set_main_flow", %{"id" => flow_id}, socket) do
    Authorize.with_authorization(socket, :edit_content, fn _socket ->
      case Flows.get_flow(socket.assigns.project.id, flow_id) do
        nil ->
          {:noreply, put_flash(socket, :error, dgettext("flows", "Flow not found."))}

        flow ->
          do_set_main_flow(socket, flow)
      end
    end)
  end

  def handle_event("set_pending_delete_flow", %{"id" => id}, socket) do
    handle_set_pending_delete(socket, id)
  end

  def handle_event("confirm_delete_flow", _params, socket) do
    handle_confirm_delete(socket, fn socket, id ->
      Authorize.with_authorization(socket, :edit_content, fn _socket ->
        handle_delete_entity(socket, id,
          current_entity_id: socket.assigns.flow.id,
          get_fn: &Flows.get_flow!/2,
          delete_fn: &Flows.delete_flow/1,
          index_path:
            ~p"/workspaces/#{socket.assigns.workspace.slug}/projects/#{socket.assigns.project.slug}/flows",
          reload_tree_fn: &reload_flows_tree/1,
          success_msg: dgettext("flows", "Flow moved to trash."),
          error_msg: dgettext("flows", "Could not delete flow.")
        )
      end)
    end)
  end

  def handle_event("delete_flow", %{"id" => flow_id}, socket) do
    Authorize.with_authorization(socket, :edit_content, fn _socket ->
      handle_delete_entity(socket, flow_id,
        current_entity_id: socket.assigns.flow.id,
        get_fn: &Flows.get_flow!/2,
        delete_fn: &Flows.delete_flow/1,
        index_path:
          ~p"/workspaces/#{socket.assigns.workspace.slug}/projects/#{socket.assigns.project.slug}/flows",
        reload_tree_fn: &reload_flows_tree/1,
        success_msg: dgettext("flows", "Flow moved to trash."),
        error_msg: dgettext("flows", "Could not delete flow.")
      )
    end)
  end

  def handle_event(
        "move_to_parent",
        %{"item_id" => item_id, "new_parent_id" => new_parent_id, "position" => position},
        socket
      ) do
    Authorize.with_authorization(socket, :edit_content, fn _socket ->
      handle_move_entity(socket, item_id, new_parent_id, position,
        get_fn: &Flows.get_flow!/2,
        move_fn: &Flows.move_flow_to_position/3,
        reload_tree_fn: &reload_flows_tree/1,
        error_msg: dgettext("flows", "Could not move flow.")
      )
    end)
  end

  defp flow_path(socket, flow) do
    ~p"/workspaces/#{socket.assigns.workspace.slug}/projects/#{socket.assigns.project.slug}/flows/#{flow.id}"
  end

  defp reload_flows_tree(socket) do
    assign(socket, :flows_tree, Flows.list_flows_tree(socket.assigns.project.id))
  end

  defp reload_history_data(socket) do
    VersionHistoryHelpers.load_history_data(
      socket,
      "flow",
      socket.assigns.flow,
      socket.assigns.project.id,
      socket.assigns.workspace.id
    )
  end

  # ===========================================================================
  # Handle Info (thin delegation)
  # ===========================================================================

  @impl true
  def handle_async(:load_flow_data, {:ok, data}, socket) do
    # Replace the brief flow with the fully-preloaded one
    flow = data.flow
    user = socket.assigns.current_scope.user

    unless socket.assigns.compact do
      CollaborationHelpers.setup_collaboration(socket, flow, user)
    end

    {online_users, node_locks} =
      if socket.assigns.compact do
        {[], %{}}
      else
        CollaborationHelpers.get_initial_collab_state(socket, flow)
      end

    # Reuse tree if already loaded (patch navigation)
    flows_tree =
      if socket.assigns.flows_tree != [] do
        socket.assigns.flows_tree
      else
        data.flows_tree
      end

    socket =
      socket
      |> assign(:flow, flow)
      |> assign(:flow_data, data.flow_data)
      |> assign(:flows_tree, flows_tree)
      |> assign(:all_sheets, data.all_sheets)
      |> assign(:gallery_by_sheet, data.gallery_by_sheet)
      |> assign(:flow_hubs, data.flow_hubs)
      |> assign(:project_variables, data.project_variables)
      |> assign(:selected_node, nil)
      |> assign(:node_form, nil)
      |> assign(:node_select_loading, false)
      |> assign(:referencing_jumps, [])
      |> assign(:available_flows, [])
      |> assign(:flow_search_query, "")
      |> assign(:flow_search_offset, 0)
      |> assign(:flow_search_has_more, false)
      |> assign(:flow_search_deep, false)
      |> assign(:subflow_exits, [])
      |> assign(:outcome_tags_suggestions, [])
      |> assign(:referencing_flows, [])
      |> assign(:project_scenes, [])
      |> assign(:editing_mode, nil)
      |> assign(:save_status, :idle)
      |> assign(:preview_show, false)
      |> assign(:preview_current_node, nil)
      |> assign(:preview_speaker, nil)
      |> assign(:preview_responses, [])
      |> assign(:preview_has_next, false)
      |> assign(:preview_history, [])
      |> assign(:versions_panel_open, false)
      |> assign(:history_data, nil)
      |> assign(:collab_scope, {:flow, flow.id})
      |> assign(:online_users, online_users)
      |> assign(:node_locks, node_locks)
      |> assign(:collab_toast, nil)
      |> assign(:remote_cursors, %{})
      |> assign(:panel_sections, %{})
      |> assign(:debug_state, nil)
      |> assign(:debug_panel_open, false)
      |> assign(:debug_active_tab, "console")
      |> assign(:debug_nodes, %{})
      |> assign(:debug_connections, [])
      |> assign(:debug_speed, 800)
      |> assign(:debug_auto_playing, false)
      |> assign(:debug_editing_var, nil)
      |> assign(:debug_var_filter, "")
      |> assign(:debug_var_changed_only, false)
      |> assign(:debug_auto_timer, nil)
      |> assign(:debug_step_limit_reached, false)
      |> assign(:auto_snapshot_ref, nil)
      |> assign(:auto_snapshot_timer, nil)
      |> assign(:available_scenes, data.available_scenes)
      |> assign(:loading, false)
      |> assign_scene_info(flow)
      |> SocketHelpers.assign_flow_stats(flow, data.flow_data)

    socket =
      socket
      |> maybe_restore_nav_history()
      |> maybe_restore_debug_session()

    {:noreply, socket}
  end

  def handle_async(:load_flow_data, {:exit, _reason}, socket) do
    %{workspace: workspace, project: project} = socket.assigns

    {:noreply,
     socket
     |> put_flash(:error, dgettext("flows", "Could not load flow data."))
     |> redirect(to: ~p"/workspaces/#{workspace.slug}/projects/#{project.slug}/flows")}
  end

  # Linked helper processes can terminate normally during flow transitions.
  # Ignore those exits so the editor does not remount while switching flows.
  @impl true
  def handle_info({:EXIT, _pid, :normal}, socket), do: {:noreply, socket}

  @impl true
  def handle_info({:project_restoration_started, payload}, socket),
    do:
      RestorationHandlers.handle_restoration_event(
        {:project_restoration_started, payload},
        socket
      )

  @impl true
  def handle_info({:project_restoration_completed, payload}, socket),
    do:
      RestorationHandlers.handle_restoration_event(
        {:project_restoration_completed, payload},
        socket
      )

  @impl true
  def handle_info({:project_restoration_failed, payload}, socket),
    do:
      RestorationHandlers.handle_restoration_event(
        {:project_restoration_failed, payload},
        socket
      )

  @impl true
  def handle_info({:try_auto_snapshot, token}, socket) do
    if token == socket.assigns[:auto_snapshot_ref] do
      %{flow: flow, current_scope: scope} = socket.assigns
      Flows.maybe_create_version(flow, scope.user.id)
      {:noreply, socket |> assign(:auto_snapshot_ref, nil) |> assign(:auto_snapshot_timer, nil)}
    else
      {:noreply, socket}
    end
  end

  def handle_info(:reset_save_status, socket) do
    EditorInfoHandlers.handle_reset_save_status(socket)
  end

  def handle_info({:load_node_select_data, node}, socket) do
    socket = NodeTypeRegistry.on_select(node.type, node, socket)
    {:noreply, assign(socket, :node_select_loading, false)}
  end

  def handle_info({:node_updated, updated_node}, socket),
    do: EditorInfoHandlers.handle_node_updated(updated_node, socket)

  def handle_info({:mention_suggestions, query, component_cid}, socket),
    do: EditorInfoHandlers.handle_mention_suggestions(query, component_cid, socket)

  def handle_info({:variable_suggestions, query, component_cid}, socket),
    do: EditorInfoHandlers.handle_variable_suggestions(query, component_cid, socket)

  def handle_info({:resolve_variable_defaults, refs, component_cid}, socket),
    do: EditorInfoHandlers.handle_resolve_variable_defaults(refs, component_cid, socket)

  def handle_info(:debug_auto_step, socket),
    do: DebugHandlers.handle_debug_auto_step(socket)

  def handle_info(:clear_collab_toast, socket),
    do: CollaborationEventHandlers.handle_clear_collab_toast(socket)

  def handle_info({Storyarn.Collaboration.Presence, {:join, _} = event}, socket),
    do: CollaborationEventHandlers.handle_presence_event(event, socket)

  def handle_info({Storyarn.Collaboration.Presence, {:leave, _} = event}, socket),
    do: CollaborationEventHandlers.handle_presence_event(event, socket)

  def handle_info({:cursor_update, cursor_data}, socket),
    do: CollaborationEventHandlers.handle_cursor_update(cursor_data, socket)

  def handle_info({:cursor_leave, user_id}, socket),
    do: CollaborationEventHandlers.handle_cursor_leave(user_id, socket)

  def handle_info({:lock_change, action, payload}, socket),
    do: CollaborationEventHandlers.handle_lock_change(action, payload, socket)

  def handle_info({:remote_change, action, payload}, socket),
    do: CollaborationEventHandlers.handle_remote_change(action, payload, socket)

  def handle_info({:audio_picker, :selected, asset_id}, socket) do
    case socket.assigns.selected_node do
      nil ->
        {:noreply, socket}

      node ->
        NodeHelpers.persist_node_update(socket, node.id, fn data ->
          Map.put(data, "audio_asset_id", asset_id)
        end)
    end
  end

  def handle_info({:audio_picker, :error, message}, socket) do
    {:noreply, put_flash(socket, :error, message)}
  end

  # Lock heartbeat — refresh lock every 10s to prevent expiry during editing
  def handle_info(:refresh_node_lock, socket) do
    if node_id = socket.assigns[:locked_node_id] do
      Collaboration.refresh_lock(
        {:flow, socket.assigns.flow.id},
        node_id,
        socket.assigns.current_scope.user.id
      )

      ref = Process.send_after(self(), :refresh_node_lock, @lock_heartbeat_interval)
      {:noreply, assign(socket, :lock_heartbeat_ref, ref)}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def terminate(_reason, socket) do
    if socket.assigns[:flow] do
      # Cancel heartbeat timer
      if ref = socket.assigns[:lock_heartbeat_ref] do
        Process.cancel_timer(ref)
      end

      # Teardown collaboration (unsubscribe, untrack, release locks)
      if scope = socket.assigns[:collab_scope] do
        user_id = socket.assigns.current_scope.user.id
        Collab.teardown(scope, user_id)
      end
    end
  end

  # ===========================================================================
  # Private Helpers
  # ===========================================================================

  defp toolbar_data(assigns) do
    %{
      hubs: assigns.flow_hubs,
      projectFlows: Enum.map(assigns.available_flows, &Map.take(&1, [:id, :name])),
      sheetAvatars:
        Enum.map(assigns.all_sheets, fn s ->
          avatars =
            if is_list(s.avatars),
              do:
                Enum.map(s.avatars, fn a ->
                  %{
                    id: a.id,
                    name: a.name,
                    position: a.position,
                    asset: %{url: a.asset && a.asset.url}
                  }
                end),
              else: []

          %{id: s.id, name: s.name, color: s.color, avatars: avatars}
        end),
      subflowExits: assigns.subflow_exits,
      referencingJumps: assigns.referencing_jumps,
      referencingFlows: assigns.referencing_flows
    }
  end

  defp flow_canvas_labels do
    %{
      # Root menu
      add_node: dgettext("flows", "Add node"),
      add_note: dgettext("flows", "Add Note"),
      play_preview: dgettext("flows", "Play preview"),
      start_debugging: dgettext("flows", "Start debugging"),
      auto_layout: dgettext("flows", "Auto-layout"),
      # Node types
      dialogue: dgettext("flows", "Dialogue"),
      condition: dgettext("flows", "Condition"),
      instruction: dgettext("flows", "Instruction"),
      hub: dgettext("flows", "Hub"),
      jump: dgettext("flows", "Jump"),
      exit: dgettext("flows", "Exit"),
      subflow: dgettext("flows", "Subflow"),
      slug_line: dgettext("flows", "Slug Line"),
      # Node actions
      open_editor_panel: dgettext("flows", "Open editor panel"),
      preview_from_here: dgettext("flows", "Preview from here"),
      generate_technical_id: dgettext("flows", "Generate technical ID"),
      toggle_switch_mode: dgettext("flows", "Toggle switch mode"),
      locate_referencing_jumps: dgettext("flows", "Locate referencing jumps"),
      locate_target_hub: dgettext("flows", "Locate target hub"),
      open_referenced_flow: dgettext("flows", "Open referenced flow"),
      create_linked_flow: dgettext("flows", "Create linked flow"),
      view_referencing_flows: dgettext("flows", "View referencing flows"),
      duplicate: dgettext("flows", "Duplicate"),
      delete: dgettext("flows", "Delete"),
      # Inline edit
      search: dgettext("flows", "Search…"),
      no_speaker: dgettext("flows", "Dialogue"),
      stage_directions: dgettext("flows", "Stage directions…"),
      menu_text: dgettext("flows", "Menu text…"),
      dialogue_text: dgettext("flows", "Dialogue text…")
    }
  end

  defp maybe_restore_nav_history(socket) do
    user_id = socket.assigns.current_scope.user.id
    project_id = socket.assigns.project.id
    flow = socket.assigns.flow
    key = {user_id, project_id}

    history = Flows.nav_history_get(key) || NavigationHistory.new(flow.id, flow.name)
    history = NavigationHistory.push(history, flow.id, flow.name)
    Flows.nav_history_put(key, history)

    assign(socket, :nav_history, history)
  end

  defp store_nav_history(socket, history) do
    user_id = socket.assigns.current_scope.user.id
    project_id = socket.assigns.project.id
    Flows.nav_history_put({user_id, project_id}, history)
  end

  defp update_selected_node_data(socket, field, value) do
    case socket.assigns.selected_node do
      nil -> {:noreply, socket}
      node -> NodeHelpers.persist_node_update(socket, node.id, &Map.put(&1, field, value))
    end
  end

  defp do_create_linked_flow(socket, node) do
    case Flows.create_linked_flow(socket.assigns.project, socket.assigns.flow, node) do
      {:ok, %{flow: new_flow}} ->
        {:noreply,
         push_patch(socket,
           to:
             ~p"/workspaces/#{socket.assigns.workspace.slug}/projects/#{socket.assigns.project.slug}/flows/#{new_flow.id}"
         )}

      {:error, :limit_reached, _details} ->
        {:noreply, put_flash(socket, :error, gettext("Item limit reached for your plan"))}

      {:error, _, _reason, _changes} ->
        {:noreply, put_flash(socket, :error, dgettext("flows", "Could not create linked flow."))}
    end
  end

  defp do_set_main_flow(socket, flow) do
    case Flows.set_main_flow(flow) do
      {:ok, _} ->
        {:noreply, assign(socket, :flows_tree, Flows.list_flows_tree(socket.assigns.project.id))}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, dgettext("flows", "Could not set main flow."))}
    end
  end

  defp assign_scene_info(socket, flow) do
    resolved_id = Flows.resolve_scene_id(flow)
    is_inherited = resolved_id != nil and resolved_id != flow.scene_id

    scene_name =
      if resolved_id do
        case Scenes.get_scene_brief(socket.assigns.project.id, resolved_id) do
          nil -> nil
          map -> map.name
        end
      end

    socket
    |> assign(:scene_name, scene_name)
    |> assign(:scene_inherited, is_inherited)
  end
end
