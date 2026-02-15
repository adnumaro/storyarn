defmodule StoryarnWeb.FlowLive.Show do
  @moduledoc false

  use StoryarnWeb, :live_view
  use StoryarnWeb.Helpers.Authorize

  import StoryarnWeb.Components.CollaborationComponents
  import StoryarnWeb.Components.SaveIndicator
  import StoryarnWeb.FlowLive.Components.NodeTypeHelpers
  import StoryarnWeb.FlowLive.Components.DebugPanel
  import StoryarnWeb.FlowLive.Components.PropertiesPanels
  import StoryarnWeb.Layouts, only: [flash_group: 1]

  alias StoryarnWeb.FlowLive.Components.ScreenplayEditor

  alias Storyarn.Assets
  alias Storyarn.Collaboration
  alias Storyarn.Flows
  alias Storyarn.Flows.DebugSessionStore
  alias Storyarn.Flows.FlowNode
  alias Storyarn.Projects
  alias Storyarn.Repo
  alias Storyarn.Sheets
  alias StoryarnWeb.FlowLive.Handlers.CollaborationEventHandlers
  alias StoryarnWeb.FlowLive.Handlers.DebugHandlers
  alias StoryarnWeb.FlowLive.Handlers.EditorInfoHandlers
  alias StoryarnWeb.FlowLive.Handlers.GenericNodeHandlers
  alias StoryarnWeb.FlowLive.Helpers.CollaborationHelpers
  alias StoryarnWeb.FlowLive.Helpers.ConnectionHelpers
  alias StoryarnWeb.FlowLive.Helpers.FormHelpers
  alias StoryarnWeb.FlowLive.Helpers.NodeHelpers
  alias StoryarnWeb.FlowLive.Nodes.Condition
  alias StoryarnWeb.FlowLive.Nodes.Dialogue
  alias StoryarnWeb.FlowLive.Nodes.Exit, as: ExitNode
  alias StoryarnWeb.FlowLive.Nodes.Instruction
  alias StoryarnWeb.FlowLive.Nodes.Scene
  alias StoryarnWeb.FlowLive.Nodes.Subflow

  # Filter out entry from user-addable node types (entry is auto-created with flow)
  @node_types FlowNode.node_types() |> Enum.reject(&(&1 == "entry"))

  @impl true
  def render(%{loading: true} = assigns) do
    ~H"""
    <%!-- Minimal shell: the root-layout overlay (#page-loader) provides the
         animated spinner. This hidden div just hosts the FlowLoader hook
         that triggers the deferred data fetch. --%>
    <div id="flow-loader" phx-hook="FlowLoader" class="hidden"></div>
    """
  end

  def render(assigns) do
    ~H"""
    <div class="h-screen flex flex-col">
      <%!-- Header --%>
      <header class="navbar bg-base-100 border-b border-base-300 px-4 shrink-0">
        <div class="flex-none flex items-center gap-1">
          <.link
            navigate={~p"/workspaces/#{@workspace.slug}/projects/#{@project.slug}/flows"}
            class="btn btn-ghost btn-sm gap-2"
          >
            <.icon name="chevron-left" class="size-4" />
            {gettext("Flows")}
          </.link>
          <.link
            :if={@from_flow}
            navigate={
              ~p"/workspaces/#{@workspace.slug}/projects/#{@project.slug}/flows/#{@from_flow.id}"
            }
            class="btn btn-ghost btn-sm gap-1 text-base-content/60"
          >
            <.icon name="corner-up-left" class="size-3" />
            {@from_flow.name}
          </.link>
        </div>
        <div class="flex-1 flex items-center gap-3 ml-4">
          <div>
            <h1
              :if={@can_edit}
              id="flow-title"
              class="text-lg font-medium outline-none rounded px-1 -mx-1 empty:before:content-[attr(data-placeholder)] empty:before:text-base-content/30"
              contenteditable="true"
              phx-hook="EditableTitle"
              phx-update="ignore"
              data-placeholder={gettext("Untitled")}
              data-name={@flow.name}
            >
              {@flow.name}
            </h1>
            <h1 :if={!@can_edit} class="text-lg font-medium">{@flow.name}</h1>
            <div :if={@can_edit} class="flex items-center gap-1 text-xs">
              <span class="text-base-content/50">#</span>
              <span
                id="flow-shortcut"
                class="text-base-content/50 outline-none hover:text-base-content empty:before:content-[attr(data-placeholder)] empty:before:text-base-content/30"
                contenteditable="true"
                phx-hook="EditableShortcut"
                phx-update="ignore"
                data-placeholder={gettext("add-shortcut")}
                data-shortcut={@flow.shortcut || ""}
              >
                {@flow.shortcut}
              </span>
            </div>
            <div :if={!@can_edit && @flow.shortcut} class="text-xs text-base-content/50">
              #{@flow.shortcut}
            </div>
          </div>
          <span :if={@flow.is_main} class="badge badge-primary badge-sm" title={gettext("Main flow")}>
            {gettext("Main")}
          </span>
        </div>
        <div class="flex-none flex items-center gap-4">
          <.online_users users={@online_users} current_user_id={@current_scope.user.id} />
          <.save_indicator :if={@can_edit} status={@save_status} />
          <button
            type="button"
            class={[
              "btn btn-sm gap-2",
              if(@debug_panel_open, do: "btn-accent", else: "btn-ghost")
            ]}
            phx-click={if(@debug_panel_open, do: "debug_stop", else: "debug_start")}
          >
            <.icon name="bug" class="size-4" />
            {if @debug_panel_open, do: gettext("Stop Debug"), else: gettext("Debug")}
          </button>
          <div :if={@can_edit} class="dropdown dropdown-end">
            <button type="button" tabindex="0" class="btn btn-primary btn-sm gap-2">
              <.icon name="plus" class="size-4" />
              {gettext("Add Node")}
            </button>
            <ul
              tabindex="0"
              class="dropdown-content menu menu-sm bg-base-100 rounded-box shadow-lg border border-base-300 w-48 z-50 mt-2"
            >
              <li :for={type <- @node_types}>
                <button type="button" phx-click="add_node" phx-value-type={type}>
                  <.node_type_icon type={type} />
                  {node_type_label(type)}
                </button>
              </li>
            </ul>
          </div>
        </div>
      </header>

      <%!-- Collaboration Toast --%>
      <.collab_toast
        :if={@collab_toast}
        action={@collab_toast.action}
        user_email={@collab_toast.user_email}
        user_color={@collab_toast.user_color}
      />

      <%!-- Main content: Canvas + Debug Panel + Properties Panel --%>
      <div class="flex-1 flex overflow-hidden">
        <%!-- Canvas + Debug Panel (vertical stack) --%>
        <div class="flex-1 flex flex-col">
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
          />
        </div>

        <%!-- Node Properties Panel (Sidebar mode) --%>
        <.node_properties_panel
          :if={@selected_node && @editing_mode == :sidebar}
          node={@selected_node}
          form={@node_form}
          can_edit={@can_edit}
          all_sheets={@all_sheets}
          flow_hubs={@flow_hubs}
          audio_assets={@audio_assets}
          panel_sections={@panel_sections}
          project_variables={@project_variables}
          referencing_jumps={@referencing_jumps}
          available_flows={@available_flows}
          subflow_exits={@subflow_exits}
          outcome_tags_suggestions={@outcome_tags_suggestions}
          referencing_flows={@referencing_flows}
        />
      </div>

      <.flash_group flash={@flash} />

      <%!-- Screenplay Editor (fullscreen overlay) --%>
      <.live_component
        :if={@selected_node && @editing_mode == :screenplay}
        module={ScreenplayEditor}
        id={"screenplay-editor-#{@selected_node.id}"}
        node={@selected_node}
        can_edit={@can_edit}
        all_sheets={@all_sheets}
        on_close={JS.push("close_editor")}
        on_open_sidebar={JS.push("open_sidebar")}
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
    </div>
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
         |> put_flash(:error, gettext("You don't have access to this project."))
         |> redirect(to: ~p"/workspaces")}
    end
  end

  defp mount_with_project(socket, workspace_slug, project_slug, flow_id, project, membership) do
    # Use brief (no preloads) for the loading screen — fast query
    case Flows.get_flow_brief(project.id, flow_id) do
      nil ->
        {:ok,
         socket
         |> put_flash(:error, gettext("Flow not found."))
         |> redirect(to: ~p"/workspaces/#{workspace_slug}/projects/#{project_slug}/flows")}

      flow ->
        project = Repo.preload(project, :workspace)
        can_edit = Projects.ProjectMembership.can?(membership.role, :edit_content)

        socket =
          socket
          |> assign(:loading, true)
          |> assign(:project, project)
          |> assign(:workspace, project.workspace)
          |> assign(:membership, membership)
          |> assign(:flow, flow)
          |> assign(:can_edit, can_edit)
          |> assign(:from_flow, nil)

        {:ok, socket}
    end
  end

  defp maybe_restore_debug_session(socket) do
    user_id = socket.assigns.current_scope.user.id
    project_id = socket.assigns.project.id

    case DebugSessionStore.take({user_id, project_id}) do
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
    socket =
      socket
      |> maybe_navigate_to_node(params["node"])
      |> maybe_set_from_flow(params["from"])

    {:noreply, socket}
  end

  defp maybe_navigate_to_node(socket, nil), do: socket

  defp maybe_navigate_to_node(socket, node_id) do
    case Integer.parse(node_id) do
      {id, ""} -> push_event(socket, "navigate_to_node", %{node_db_id: id})
      _ -> socket
    end
  end

  defp maybe_set_from_flow(socket, nil), do: assign(socket, :from_flow, nil)

  defp maybe_set_from_flow(socket, from_id) do
    case Integer.parse(from_id) do
      {id, ""} -> resolve_from_flow(socket, id)
      _ -> assign(socket, :from_flow, nil)
    end
  end

  defp resolve_from_flow(socket, id) do
    case Flows.get_flow_brief(socket.assigns.project.id, id) do
      nil -> assign(socket, :from_flow, nil)
      flow -> assign(socket, :from_flow, flow)
    end
  end

  # ===========================================================================
  # Event Handlers (thin delegation)
  # ===========================================================================

  @impl true
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
          audio_assets: Assets.list_assets(project.id, content_type: "audio/"),
          project_variables: Sheets.list_project_variables(project.id)
        }
      end)

    {:noreply, socket}
  end

  def handle_event("add_node", params, socket) do
    with_auth(:edit_content, socket, fn -> GenericNodeHandlers.handle_add_node(params, socket) end)
  end

  def handle_event("save_name", params, socket) do
    with_auth(:edit_content, socket, fn ->
      GenericNodeHandlers.handle_save_name(params, socket)
    end)
  end

  def handle_event("save_shortcut", params, socket) do
    with_auth(:edit_content, socket, fn ->
      GenericNodeHandlers.handle_save_shortcut(params, socket)
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

  def handle_event("close_editor", _params, socket) do
    GenericNodeHandlers.handle_close_editor(socket)
  end

  def handle_event("deselect_node", _params, socket) do
    GenericNodeHandlers.handle_deselect_node(socket)
  end

  def handle_event("create_sheet", _params, socket) do
    with_auth(:edit_content, socket, fn -> GenericNodeHandlers.handle_create_sheet(socket) end)
  end

  def handle_event("node_moved", params, socket) do
    with_auth(:edit_content, socket, fn ->
      GenericNodeHandlers.handle_node_moved(params, socket)
    end)
  end

  def handle_event("update_node_data", %{"node" => _} = params, socket) do
    with_auth(:edit_content, socket, fn ->
      GenericNodeHandlers.handle_update_node_data(params, socket)
    end)
  end

  # Catch-all for update_node_data events without the "node" key (no-op)
  def handle_event("update_node_data", _params, socket) do
    {:noreply, socket}
  end

  def handle_event("update_node_text", params, socket) do
    with_auth(:edit_content, socket, fn ->
      GenericNodeHandlers.handle_update_node_text(params, socket)
    end)
  end

  def handle_event("mention_suggestions", params, socket) do
    GenericNodeHandlers.handle_mention_suggestions(params, socket)
  end

  def handle_event("delete_node", params, socket) do
    with_auth(:edit_content, socket, fn ->
      GenericNodeHandlers.handle_delete_node(params, socket)
    end)
  end

  def handle_event("duplicate_node", params, socket) do
    with_auth(:edit_content, socket, fn ->
      GenericNodeHandlers.handle_duplicate_node(params, socket)
    end)
  end

  def handle_event("generate_technical_id", _params, socket) do
    with_auth(:edit_content, socket, fn ->
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
    with_auth(:edit_content, socket, fn ->
      GenericNodeHandlers.handle_update_node_field(params, socket)
    end)
  end

  # Responses (dialogue-specific)
  def handle_event("add_response", params, socket) do
    with_auth(:edit_content, socket, fn ->
      Dialogue.Node.handle_add_response(params, socket)
    end)
  end

  def handle_event("remove_response", params, socket) do
    with_auth(:edit_content, socket, fn ->
      Dialogue.Node.handle_remove_response(params, socket)
    end)
  end

  def handle_event("update_response_text", params, socket) do
    with_auth(:edit_content, socket, fn ->
      Dialogue.Node.handle_update_response_text(params, socket)
    end)
  end

  def handle_event("update_response_condition", params, socket) do
    with_auth(:edit_content, socket, fn ->
      Dialogue.Node.handle_update_response_condition(params, socket)
    end)
  end

  def handle_event("update_response_instruction", params, socket) do
    with_auth(:edit_content, socket, fn ->
      Dialogue.Node.handle_update_response_instruction(params, socket)
    end)
  end

  # Panel UI
  def handle_event("toggle_panel_section", %{"section" => section}, socket) do
    panel_sections = socket.assigns.panel_sections
    current_state = Map.get(panel_sections, section, false)
    updated_sections = Map.put(panel_sections, section, !current_state)
    {:noreply, assign(socket, :panel_sections, updated_sections)}
  end

  # Connections
  def handle_event("connection_created", params, socket) do
    ConnectionHelpers.create_connection(socket, params)
  end

  def handle_event(
        "connection_deleted",
        %{"source_node_id" => source_id, "target_node_id" => target_id},
        socket
      ) do
    ConnectionHelpers.delete_connection_by_nodes(socket, source_id, target_id)
  end

  # Condition builders
  def handle_event("update_response_condition_builder", params, socket) do
    with_auth(:edit_content, socket, fn ->
      Condition.Node.handle_update_response_condition_builder(params, socket)
    end)
  end

  def handle_event("update_condition_builder", params, socket) do
    with_auth(:edit_content, socket, fn ->
      Condition.Node.handle_update_condition_builder(params, socket)
    end)
  end

  def handle_event("toggle_switch_mode", _params, socket) do
    with_auth(:edit_content, socket, fn ->
      Condition.Node.handle_toggle_switch_mode(socket)
    end)
  end

  # Instruction builder
  def handle_event("update_instruction_builder", params, socket) do
    with_auth(:edit_content, socket, fn ->
      Instruction.Node.handle_update_instruction_builder(params, socket)
    end)
  end

  # Subflow
  def handle_event("navigate_to_subflow", %{"flow-id" => flow_id_str}, socket) do
    case Integer.parse(flow_id_str) do
      {flow_id, ""} ->
        # Validate that the target flow belongs to the current project
        case Flows.get_flow_brief(socket.assigns.project.id, flow_id) do
          nil ->
            {:noreply, put_flash(socket, :error, gettext("Flow not found."))}

          _flow ->
            {:noreply,
             push_navigate(socket,
               to:
                 ~p"/workspaces/#{socket.assigns.workspace.slug}/projects/#{socket.assigns.project.slug}/flows/#{flow_id}?from=#{socket.assigns.flow.id}"
             )}
        end

      _ ->
        {:noreply, put_flash(socket, :error, gettext("Invalid flow ID."))}
    end
  end

  def handle_event("update_subflow_reference", %{"referenced_flow_id" => ref_id}, socket) do
    with_auth(:edit_content, socket, fn ->
      Subflow.Node.handle_update_reference(ref_id, socket)
    end)
  end

  # Exit node events
  def handle_event("update_exit_mode", %{"mode" => mode}, socket) do
    with_auth(:edit_content, socket, fn ->
      ExitNode.Node.handle_update_exit_mode(mode, socket)
    end)
  end

  def handle_event("update_exit_reference", %{"flow-id" => flow_id}, socket) do
    with_auth(:edit_content, socket, fn ->
      ExitNode.Node.handle_update_exit_reference(flow_id, socket)
    end)
  end

  def handle_event("add_outcome_tag", %{"tag" => tag}, socket) do
    with_auth(:edit_content, socket, fn ->
      ExitNode.Node.handle_add_outcome_tag(tag, socket)
    end)
  end

  def handle_event("remove_outcome_tag", %{"tag" => tag}, socket) do
    with_auth(:edit_content, socket, fn ->
      ExitNode.Node.handle_remove_outcome_tag(tag, socket)
    end)
  end

  def handle_event("update_outcome_color", %{"color" => color}, socket) do
    with_auth(:edit_content, socket, fn ->
      ExitNode.Node.handle_update_outcome_color(color, socket)
    end)
  end

  # Hub color picker
  def handle_event("update_hub_color", %{"color" => color}, socket) do
    with_auth(:edit_content, socket, fn ->
      node = socket.assigns.selected_node
      validated = validate_hex_color(color, Flows.HubColors.default_hex())

      NodeHelpers.persist_node_update(socket, node.id, fn data ->
        Map.put(data, "color", validated)
      end)
    end)
  end

  def handle_event("navigate_to_exit_flow", %{"flow-id" => flow_id_str}, socket) do
    case Integer.parse(flow_id_str) do
      {flow_id, ""} ->
        case Flows.get_flow_brief(socket.assigns.project.id, flow_id) do
          nil ->
            {:noreply, put_flash(socket, :error, gettext("Flow not found."))}

          _flow ->
            {:noreply,
             push_navigate(socket,
               to:
                 ~p"/workspaces/#{socket.assigns.workspace.slug}/projects/#{socket.assigns.project.slug}/flows/#{flow_id}?from=#{socket.assigns.flow.id}"
             )}
        end

      _ ->
        {:noreply, put_flash(socket, :error, gettext("Invalid flow ID."))}
    end
  end

  def handle_event("navigate_to_referencing_flow", %{"flow-id" => flow_id_str}, socket) do
    case Integer.parse(flow_id_str) do
      {flow_id, ""} ->
        case Flows.get_flow_brief(socket.assigns.project.id, flow_id) do
          nil ->
            {:noreply, put_flash(socket, :error, gettext("Flow not found."))}

          _flow ->
            {:noreply,
             push_navigate(socket,
               to:
                 ~p"/workspaces/#{socket.assigns.workspace.slug}/projects/#{socket.assigns.project.slug}/flows/#{flow_id}?from=#{socket.assigns.flow.id}"
             )}
        end

      _ ->
        {:noreply, put_flash(socket, :error, gettext("Invalid flow ID."))}
    end
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
      |> assign(:node_types, @node_types)
      |> assign(:all_sheets, data.all_sheets)
      |> assign(:flow_hubs, data.flow_hubs)
      |> assign(:audio_assets, data.audio_assets)
      |> assign(:project_variables, data.project_variables)
      |> assign(:selected_node, nil)
      |> assign(:node_form, nil)
      |> assign(:referencing_jumps, [])
      |> assign(:available_flows, [])
      |> assign(:subflow_exits, [])
      |> assign(:outcome_tags_suggestions, [])
      |> assign(:referencing_flows, [])
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
      |> assign(:loading, false)

    socket = maybe_restore_debug_session(socket)

    {:noreply, socket}
  end

  def handle_async(:load_flow_data, {:exit, _reason}, socket) do
    %{workspace: workspace, project: project} = socket.assigns

    {:noreply,
     socket
     |> put_flash(:error, gettext("Could not load flow data."))
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

  # ===========================================================================
  # Private Helpers
  # ===========================================================================

  defp with_auth(action, socket, fun) do
    case authorize(socket, action) do
      :ok -> fun.()
      {:error, :unauthorized} -> {:noreply, unauthorized_flash(socket)}
    end
  end

  defp unauthorized_flash(socket) do
    put_flash(socket, :error, gettext("You don't have permission to perform this action."))
  end

  defp validate_hex_color(color, default) when is_binary(color) do
    if String.match?(color, ~r/^#([0-9a-fA-F]{3}|[0-9a-fA-F]{6}|[0-9a-fA-F]{8})$/) do
      color
    else
      default
    end
  end

  defp validate_hex_color(_, default), do: default
end
