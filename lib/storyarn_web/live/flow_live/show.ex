defmodule StoryarnWeb.FlowLive.Show do
  @moduledoc false

  use StoryarnWeb, :live_view
  use StoryarnWeb.Helpers.Authorize

  import StoryarnWeb.Components.CollaborationComponents
  import StoryarnWeb.FlowLive.Components.BuilderPanel
  import StoryarnWeb.FlowLive.Components.DebugPanel
  import StoryarnWeb.FlowLive.Components.FlowHeader
  import StoryarnWeb.FlowLive.Components.FlowToolbar
  import StoryarnWeb.Live.Shared.TreePanelHandlers

  alias StoryarnWeb.Components.Sidebar.FlowTree
  alias StoryarnWeb.FlowLive.Components.ScreenplayEditor

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
  alias StoryarnWeb.FlowLive.Helpers.CollaborationHelpers
  alias StoryarnWeb.FlowLive.Helpers.ConnectionHelpers
  alias StoryarnWeb.FlowLive.Helpers.FormHelpers
  alias StoryarnWeb.FlowLive.Helpers.NavigationHistory
  alias StoryarnWeb.FlowLive.Helpers.NodeHelpers
  alias StoryarnWeb.FlowLive.Nodes.Condition
  alias StoryarnWeb.FlowLive.Nodes.Dialogue
  alias StoryarnWeb.FlowLive.Nodes.Exit, as: ExitNode
  alias StoryarnWeb.FlowLive.Nodes.Instruction
  alias StoryarnWeb.FlowLive.Nodes.Scene
  alias StoryarnWeb.FlowLive.Nodes.Subflow

  # Filter out entry from user-addable node types (entry is auto-created with flow)
  @node_types Flows.node_types() |> Enum.reject(&(&1 == "entry"))

  @impl true
  def render(%{loading: true} = assigns) do
    ~H"""
    <Layouts.focus
      flash={@flash}
      current_scope={@current_scope}
      project={@project}
      workspace={@workspace}
      active_tool={:flows}
      has_tree={false}
      canvas_mode={true}
    >
      <%!-- Minimal shell: the root-layout overlay (#page-loader) provides the
           animated spinner. This hidden div just hosts the FlowLoader hook
           that triggers the deferred data fetch. --%>
      <div id="flow-loader" phx-hook="FlowLoader" class="hidden"></div>
    </Layouts.focus>
    """
  end

  def render(assigns) do
    ~H"""
    <Layouts.focus
      flash={@flash}
      current_scope={@current_scope}
      project={@project}
      workspace={@workspace}
      active_tool={:flows}
      has_tree={true}
      tree_panel_open={@tree_panel_open}
      tree_panel_pinned={@tree_panel_pinned}
      can_edit={@can_edit}
      online_users={@online_users}
      canvas_mode={true}
    >
      <:top_bar_extra>
        <.flow_info_bar
          flow={@flow}
          can_edit={@can_edit}
          save_status={@save_status}
          nav_history={@nav_history}
          scene_name={@scene_name}
          scene_inherited={@scene_inherited}
          available_scenes={@available_scenes}
        />
      </:top_bar_extra>
      <:top_bar_extra_right>
        <.flow_actions
          flow={@flow}
          workspace={@workspace}
          project={@project}
          can_edit={@can_edit}
          debug_panel_open={@debug_panel_open}
          node_types={@node_types}
        />
      </:top_bar_extra_right>
      <:tree_content>
        <FlowTree.flows_section
          flows_tree={@flows_tree}
          workspace={@workspace}
          project={@project}
          selected_flow_id={to_string(@flow.id)}
          can_edit={@can_edit}
        />
      </:tree_content>
      <div class="h-full relative">
        <%!-- Canvas fills the entire area --%>
        <div class="absolute inset-0 flex flex-col">
          <div class="flex-1 relative bg-base-200">
            <div
              id="flow-canvas"
              phx-hook="FlowCanvas"
              phx-update="ignore"
              class="absolute inset-0"
              data-flow={Jason.encode!(@flow_data)}
              data-sheets={Jason.encode!(FormHelpers.sheets_map(@all_sheets))}
              data-locks={Jason.encode!(@node_locks)}
              data-user-id={@current_scope.user.id}
              data-user-color={Collaboration.user_color(@current_scope.user.id)}
            >
            </div>

            <%!-- Floating Toolbar --%>
            <div
              id="flow-floating-toolbar"
              phx-hook="FlowFloatingToolbar"
              class="absolute z-30"
            >
              <div
                :if={@selected_node && @editing_mode in [:toolbar, :builder]}
                class="floating-toolbar"
              >
                <.node_toolbar
                  node={@selected_node}
                  form={@node_form}
                  can_edit={@can_edit}
                  all_sheets={@all_sheets}
                  flow_hubs={@flow_hubs}
                  available_flows={@available_flows}
                  available_scenes={assigns[:available_scenes] || []}
                  flow_search_has_more={@flow_search_has_more}
                  flow_search_deep={@flow_search_deep}
                  subflow_exits={@subflow_exits}
                  referencing_jumps={@referencing_jumps}
                  referencing_flows={@referencing_flows}
                  project_scenes={@project_scenes}
                />
              </div>

              <%!-- Builder Panel (below toolbar) --%>
              <div
                :if={@selected_node && @editing_mode == :builder}
                id="builder-panel-content"
                class="mt-2 bg-base-100 border border-base-300 rounded-lg shadow-lg p-4 max-h-[60vh] overflow-y-auto w-[400px]"
              >
                <.builder_content
                  node={@selected_node}
                  form={@node_form}
                  can_edit={@can_edit}
                  project_variables={@project_variables}
                  panel_sections={@panel_sections}
                />
              </div>
            </div>
          </div>

          <.debug_panel
            :if={@debug_panel_open && @debug_state}
            debug_state={@debug_state}
            debug_active_tab={@debug_active_tab}
            debug_nodes={@debug_nodes}
            debug_auto_playing={@debug_auto_playing}
            debug_speed={@debug_speed}
            debug_editing_var={@debug_editing_var}
            debug_var_filter={@debug_var_filter}
            debug_var_changed_only={@debug_var_changed_only}
            debug_current_flow_name={@flow.name}
            debug_step_limit_reached={@debug_step_limit_reached}
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

      <%!-- Screenplay Editor (fullscreen overlay) --%>
      <.live_component
        :if={@selected_node && @editing_mode in [:screenplay, :editor]}
        module={ScreenplayEditor}
        id={"screenplay-editor-#{@selected_node.id}"}
        node={@selected_node}
        can_edit={@can_edit}
        all_sheets={@all_sheets}
        project_variables={@project_variables}
        project={@project}
        current_user={@current_scope.user}
        panel_sections={@panel_sections}
        on_close={JS.push("close_editor")}
      />

      <%!-- Preview Modal --%>
      <.live_component
        module={StoryarnWeb.FlowLive.PreviewComponent}
        id="flow-preview"
        show={@preview_show}
        start_node={@preview_node}
        project={@project}
        sheets_map={FormHelpers.sheets_map(@all_sheets)}
      />
    </Layouts.focus>
    """
  end

  # ===========================================================================
  # Mount & Setup
  # ===========================================================================

  @impl true
  def mount(
        %{"workspace_slug" => workspace_slug, "project_slug" => project_slug, "id" => flow_id},
        _session,
        socket
      ) do
    case Projects.get_project_by_slugs(socket.assigns.current_scope, workspace_slug, project_slug) do
      {:ok, project, membership} ->
        mount_with_project(socket, workspace_slug, project_slug, flow_id, project, membership)

      {:error, _reason} ->
        {:ok,
         socket
         |> put_flash(:error, dgettext("flows", "You don't have access to this project."))
         |> redirect(to: ~p"/workspaces")}
    end
  end

  defp mount_with_project(socket, workspace_slug, project_slug, flow_id, project, membership) do
    # Use brief (no preloads) for the loading screen — fast query
    case Flows.get_flow_brief(project.id, flow_id) do
      nil ->
        {:ok,
         socket
         |> put_flash(:error, dgettext("flows", "Flow not found."))
         |> redirect(to: ~p"/workspaces/#{workspace_slug}/projects/#{project_slug}/flows")}

      flow ->
        can_edit = Projects.can?(membership.role, :edit_content)

        socket =
          socket
          |> assign(focus_layout_defaults())
          |> assign(:loading, true)
          |> assign(:project, project)
          |> assign(:workspace, project.workspace)
          |> assign(:membership, membership)
          |> assign(:flow, flow)
          |> assign(:can_edit, can_edit)
          |> assign(:nav_history, nil)
          |> assign(:flows_tree, [])
          |> assign(:pending_delete_id, nil)
          |> assign(:scene_name, nil)
          |> assign(:scene_inherited, false)
          |> assign(:available_scenes, [])

        {:ok, socket}
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
  def handle_params(_params, _url, %{assigns: %{loading: true}} = socket) do
    {:noreply, socket}
  end

  def handle_params(params, _url, socket) do
    {:noreply, maybe_navigate_to_node(socket, params["node"])}
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
  # Tree panel events (from FocusLayout)
  def handle_event("tree_panel_" <> _ = event, params, socket),
    do: handle_tree_panel_event(event, params, socket)

  # Triggered by the FlowLoader hook after the browser has painted the spinner.
  def handle_event("load_flow_data", _params, socket) do
    %{flow: flow, project: project} = socket.assigns

    socket =
      start_async(socket, :load_flow_data, fn ->
        full_flow = Flows.get_flow!(project.id, flow.id)

        %{
          flow: full_flow,
          flow_data: Flows.serialize_for_canvas(full_flow),
          all_sheets: Sheets.list_all_sheets(project.id),
          flow_hubs: Flows.list_hubs(flow.id),
          project_variables: Sheets.list_project_variables(project.id),
          flows_tree: Flows.list_flows_tree(project.id),
          available_scenes: Scenes.list_scenes(project.id)
        }
      end)

    {:noreply, socket}
  end

  def handle_event("add_node", params, socket) do
    with_authorization(socket, :edit_content, fn _socket ->
      GenericNodeHandlers.handle_add_node(params, socket)
    end)
  end

  def handle_event("save_name", params, socket) do
    with_authorization(socket, :edit_content, fn _socket ->
      GenericNodeHandlers.handle_save_name(params, socket)
    end)
  end

  def handle_event("save_shortcut", params, socket) do
    with_authorization(socket, :edit_content, fn _socket ->
      GenericNodeHandlers.handle_save_shortcut(params, socket)
    end)
  end

  def handle_event("restore_flow_meta", params, socket) do
    with_authorization(socket, :edit_content, fn _socket ->
      GenericNodeHandlers.handle_restore_flow_meta(params, socket)
    end)
  end

  def handle_event("node_selected", params, socket) do
    GenericNodeHandlers.handle_node_selected(params, socket)
  end

  def handle_event("node_double_clicked", params, socket) do
    GenericNodeHandlers.handle_node_double_clicked(params, socket)
  end

  def handle_event("open_screenplay", _params, socket) do
    Dialogue.Node.handle_open_screenplay(socket)
  end

  def handle_event("open_sidebar", _params, socket) do
    GenericNodeHandlers.handle_open_sidebar(socket)
  end

  def handle_event("open_builder", _params, socket) do
    {:noreply, assign(socket, :editing_mode, :builder)}
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
    with_authorization(socket, :edit_content, fn _socket ->
      GenericNodeHandlers.handle_create_sheet(socket)
    end)
  end

  def handle_event("node_moved", params, socket) do
    with_authorization(socket, :edit_content, fn _socket ->
      GenericNodeHandlers.handle_node_moved(params, socket)
    end)
  end

  def handle_event("batch_update_positions", params, socket) do
    with_authorization(socket, :edit_content, fn _socket ->
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
    with_authorization(socket, :edit_content, fn _socket ->
      GenericNodeHandlers.handle_update_node_data(params, socket)
    end)
  end

  # Catch-all for update_node_data events without the "node" key (no-op)
  def handle_event("update_node_data", _params, socket) do
    {:noreply, socket}
  end

  def handle_event("update_node_text", params, socket) do
    with_authorization(socket, :edit_content, fn _socket ->
      GenericNodeHandlers.handle_update_node_text(params, socket)
    end)
  end

  def handle_event("mention_suggestions", params, socket) do
    GenericNodeHandlers.handle_mention_suggestions(params, socket)
  end

  def handle_event("delete_node", params, socket) do
    with_authorization(socket, :edit_content, fn _socket ->
      GenericNodeHandlers.handle_delete_node(params, socket)
    end)
  end

  def handle_event("restore_node", %{"id" => node_id}, socket) do
    with_authorization(socket, :edit_content, fn _socket ->
      NodeHelpers.restore_node(socket, node_id)
    end)
  end

  def handle_event("restore_node_data", %{"id" => node_id, "data" => data}, socket) do
    with_authorization(socket, :edit_content, fn _socket ->
      NodeHelpers.restore_node_data(socket, node_id, data)
    end)
  end

  def handle_event("duplicate_node", params, socket) do
    with_authorization(socket, :edit_content, fn _socket ->
      GenericNodeHandlers.handle_duplicate_node(params, socket)
    end)
  end

  def handle_event("generate_technical_id", _params, socket) do
    with_authorization(socket, :edit_content, fn _socket ->
      node = socket.assigns.selected_node

      cond do
        node && node.type == "dialogue" ->
          Dialogue.Node.handle_generate_technical_id(socket)

        node && node.type == "exit" ->
          ExitNode.Node.handle_generate_technical_id(socket)

        node && node.type == "scene" ->
          Scene.Node.handle_generate_technical_id(socket)

        true ->
          {:noreply, socket}
      end
    end)
  end

  def handle_event("update_node_field", params, socket) do
    with_authorization(socket, :edit_content, fn _socket ->
      GenericNodeHandlers.handle_update_node_field(params, socket)
    end)
  end

  # Responses (dialogue-specific)
  def handle_event("add_response", params, socket) do
    with_authorization(socket, :edit_content, fn _socket ->
      Dialogue.Node.handle_add_response(params, socket)
    end)
  end

  def handle_event("remove_response", params, socket) do
    with_authorization(socket, :edit_content, fn _socket ->
      Dialogue.Node.handle_remove_response(params, socket)
    end)
  end

  def handle_event("update_response_text", params, socket) do
    with_authorization(socket, :edit_content, fn _socket ->
      Dialogue.Node.handle_update_response_text(params, socket)
    end)
  end

  def handle_event("update_response_condition", params, socket) do
    with_authorization(socket, :edit_content, fn _socket ->
      Dialogue.Node.handle_update_response_condition(params, socket)
    end)
  end

  def handle_event("update_response_instruction", params, socket) do
    with_authorization(socket, :edit_content, fn _socket ->
      Dialogue.Node.handle_update_response_instruction(params, socket)
    end)
  end

  def handle_event("update_response_instruction_builder", params, socket) do
    with_authorization(socket, :edit_content, fn _socket ->
      Dialogue.Node.handle_update_response_instruction_builder(params, socket)
    end)
  end

  # Connections
  def handle_event("connection_created", params, socket) do
    with_authorization(socket, :edit_content, fn _socket ->
      ConnectionHelpers.create_connection(socket, params)
    end)
  end

  def handle_event(
        "connection_deleted",
        %{"source_node_id" => source_id, "target_node_id" => target_id},
        socket
      ) do
    with_authorization(socket, :edit_content, fn _socket ->
      ConnectionHelpers.delete_connection_by_nodes(socket, source_id, target_id)
    end)
  end

  # Condition builders
  def handle_event("update_response_condition_builder", params, socket) do
    with_authorization(socket, :edit_content, fn _socket ->
      Condition.Node.handle_update_response_condition_builder(params, socket)
    end)
  end

  def handle_event("update_condition_builder", params, socket) do
    with_authorization(socket, :edit_content, fn _socket ->
      Condition.Node.handle_update_condition_builder(params, socket)
    end)
  end

  def handle_event("toggle_switch_mode", _params, socket) do
    with_authorization(socket, :edit_content, fn _socket ->
      Condition.Node.handle_toggle_switch_mode(socket)
    end)
  end

  # Instruction builder
  def handle_event("update_instruction_builder", params, socket) do
    with_authorization(socket, :edit_content, fn _socket ->
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
         push_navigate(socket,
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
         push_navigate(socket,
           to:
             ~p"/workspaces/#{socket.assigns.workspace.slug}/projects/#{socket.assigns.project.slug}/flows/#{entry.flow_id}"
         )}

      :at_end ->
        {:noreply, socket}
    end
  end

  def handle_event("update_subflow_reference", %{"referenced_flow_id" => ref_id}, socket) do
    with_authorization(socket, :edit_content, fn _socket ->
      Subflow.Node.handle_update_reference(ref_id, socket)
    end)
  end

  # Create linked flow (exit flow_reference / subflow)
  def handle_event("create_linked_flow", %{"node-id" => node_id_str}, socket) do
    with_authorization(socket, :edit_content, fn _socket ->
      node = Flows.get_node!(socket.assigns.flow.id, node_id_str)

      case Flows.create_linked_flow(socket.assigns.project, socket.assigns.flow, node) do
        {:ok, %{flow: new_flow}} ->
          {:noreply,
           push_navigate(socket,
             to:
               ~p"/workspaces/#{socket.assigns.workspace.slug}/projects/#{socket.assigns.project.slug}/flows/#{new_flow.id}"
           )}

        {:error, _, _reason, _changes} ->
          {:noreply,
           put_flash(socket, :error, dgettext("flows", "Could not create linked flow."))}
      end
    end)
  end

  # Exit node events
  def handle_event("update_exit_mode", %{"mode" => mode}, socket) do
    with_authorization(socket, :edit_content, fn _socket ->
      ExitNode.Node.handle_update_exit_mode(mode, socket)
    end)
  end

  def handle_event("update_exit_reference", %{"flow-id" => flow_id}, socket) do
    with_authorization(socket, :edit_content, fn _socket ->
      ExitNode.Node.handle_update_exit_reference(flow_id, socket)
    end)
  end

  def handle_event("add_outcome_tag", %{"tag" => tag}, socket) do
    with_authorization(socket, :edit_content, fn _socket ->
      ExitNode.Node.handle_add_outcome_tag(tag, socket)
    end)
  end

  def handle_event("remove_outcome_tag", %{"tag" => tag}, socket) do
    with_authorization(socket, :edit_content, fn _socket ->
      ExitNode.Node.handle_remove_outcome_tag(tag, socket)
    end)
  end

  def handle_event("update_outcome_color", %{"color" => color}, socket) do
    with_authorization(socket, :edit_content, fn _socket ->
      ExitNode.Node.handle_update_outcome_color(color, socket)
    end)
  end

  def handle_event("update_exit_target", params, socket) do
    with_authorization(socket, :edit_content, fn _socket ->
      ExitNode.Node.handle_update_exit_target(params, socket)
    end)
  end

  # Scene map
  def handle_event("update_scene", %{"scene_id" => scene_id}, socket) do
    with_authorization(socket, :edit_content, fn _socket ->
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
    with_authorization(socket, :edit_content, fn _socket ->
      node = socket.assigns.selected_node

      validated =
        StoryarnWeb.FlowLive.Components.NodeTypeHelpers.validate_hex_color(
          color,
          Flows.HubColors.default_hex()
        )

      NodeHelpers.persist_node_update(socket, node.id, fn data ->
        Map.put(data, "color", validated)
      end)
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
    GenericNodeHandlers.handle_start_preview(params, socket)
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
    with_authorization(socket, :edit_content, fn _socket ->
      case Flows.create_flow(socket.assigns.project, %{name: dgettext("flows", "Untitled")}) do
        {:ok, new_flow} ->
          {:noreply,
           push_navigate(socket,
             to:
               ~p"/workspaces/#{socket.assigns.workspace.slug}/projects/#{socket.assigns.project.slug}/flows/#{new_flow.id}"
           )}

        {:error, _changeset} ->
          {:noreply, put_flash(socket, :error, dgettext("flows", "Could not create flow."))}
      end
    end)
  end

  def handle_event("create_child_flow", %{"parent-id" => parent_id}, socket) do
    with_authorization(socket, :edit_content, fn _socket ->
      attrs = %{name: dgettext("flows", "Untitled"), parent_id: parent_id}

      case Flows.create_flow(socket.assigns.project, attrs) do
        {:ok, new_flow} ->
          {:noreply,
           push_navigate(socket,
             to:
               ~p"/workspaces/#{socket.assigns.workspace.slug}/projects/#{socket.assigns.project.slug}/flows/#{new_flow.id}"
           )}

        {:error, _changeset} ->
          {:noreply, put_flash(socket, :error, dgettext("flows", "Could not create flow."))}
      end
    end)
  end

  def handle_event("set_main_flow", %{"id" => flow_id}, socket) do
    with_authorization(socket, :edit_content, fn _socket ->
      flow = Flows.get_flow!(socket.assigns.project.id, flow_id)

      case Flows.set_main_flow(flow) do
        {:ok, _} ->
          {:noreply,
           assign(socket, :flows_tree, Flows.list_flows_tree(socket.assigns.project.id))}

        {:error, _} ->
          {:noreply, put_flash(socket, :error, dgettext("flows", "Could not set main flow."))}
      end
    end)
  end

  def handle_event("set_pending_delete_flow", %{"id" => id}, socket) do
    {:noreply, assign(socket, :pending_delete_id, id)}
  end

  def handle_event("confirm_delete_flow", _params, socket) do
    if id = socket.assigns[:pending_delete_id] do
      handle_event("delete_flow", %{"id" => id}, socket)
    else
      {:noreply, socket}
    end
  end

  def handle_event("delete_flow", %{"id" => flow_id}, socket) do
    with_authorization(socket, :edit_content, fn _socket ->
      flow = Flows.get_flow!(socket.assigns.project.id, flow_id)

      case Flows.delete_flow(flow) do
        {:ok, _} ->
          handle_flow_deleted(socket, flow)

        {:error, _} ->
          {:noreply, put_flash(socket, :error, dgettext("flows", "Could not delete flow."))}
      end
    end)
  end

  def handle_event(
        "move_to_parent",
        %{"item_id" => item_id, "new_parent_id" => new_parent_id, "position" => position},
        socket
      ) do
    with_authorization(socket, :edit_content, fn _socket ->
      flow = Flows.get_flow!(socket.assigns.project.id, item_id)
      new_parent_id = Storyarn.Shared.MapUtils.parse_int(new_parent_id)
      position = Storyarn.Shared.MapUtils.parse_int(position) || 0

      case Flows.move_flow_to_position(flow, new_parent_id, position) do
        {:ok, _} ->
          {:noreply,
           assign(socket, :flows_tree, Flows.list_flows_tree(socket.assigns.project.id))}

        {:error, _} ->
          {:noreply, put_flash(socket, :error, dgettext("flows", "Could not move flow."))}
      end
    end)
  end

  defp handle_flow_deleted(socket, flow) do
    if to_string(flow.id) == to_string(socket.assigns.flow.id) do
      {:noreply,
       push_navigate(socket,
         to:
           ~p"/workspaces/#{socket.assigns.workspace.slug}/projects/#{socket.assigns.project.slug}/flows"
       )}
    else
      {:noreply,
       socket
       |> assign(:flows_tree, Flows.list_flows_tree(socket.assigns.project.id))
       |> put_flash(:info, dgettext("flows", "Flow moved to trash."))}
    end
  end

  # ===========================================================================
  # Handle Info (thin delegation)
  # ===========================================================================

  @impl true
  def handle_async(:load_flow_data, {:ok, data}, socket) do
    # Replace the brief flow with the fully-preloaded one
    flow = data.flow
    user = socket.assigns.current_scope.user

    CollaborationHelpers.setup_collaboration(socket, flow, user)
    {online_users, node_locks} = CollaborationHelpers.get_initial_collab_state(socket, flow)

    socket =
      socket
      |> assign(:flow, flow)
      |> assign(:flow_data, data.flow_data)
      |> assign(:flows_tree, data.flows_tree)
      |> assign(:node_types, @node_types)
      |> assign(:all_sheets, data.all_sheets)
      |> assign(:flow_hubs, data.flow_hubs)
      |> assign(:project_variables, data.project_variables)
      |> assign(:selected_node, nil)
      |> assign(:node_form, nil)
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
      |> assign(:preview_node, nil)
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
      |> assign(:available_scenes, data.available_scenes)
      |> assign(:loading, false)
      |> assign_scene_info(flow)

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

  @impl true
  def handle_info(:reset_save_status, socket),
    do: EditorInfoHandlers.handle_reset_save_status(socket)

  def handle_info({:node_updated, updated_node}, socket),
    do: EditorInfoHandlers.handle_node_updated(updated_node, socket)

  def handle_info({:close_preview}, socket),
    do: EditorInfoHandlers.handle_close_preview(socket)

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

  def handle_info(%{event: "presence_diff", payload: _diff}, socket),
    do: CollaborationEventHandlers.handle_presence_diff(socket)

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

  # ===========================================================================
  # Private Helpers
  # ===========================================================================

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
