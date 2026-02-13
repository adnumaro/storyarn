defmodule StoryarnWeb.FlowLive.Handlers.DebugHandlers do
  @moduledoc """
  Event handlers for the flow debugger.

  Manages the debug session lifecycle: start, step, step_back, choose_response,
  reset, and stop. Bridges between LiveView events and the pure functional
  Evaluator.Engine.
  """

  import Phoenix.Component, only: [assign: 3]
  import Phoenix.LiveView, only: [push_event: 3, push_navigate: 2, put_flash: 3]

  use Gettext, backend: StoryarnWeb.Gettext

  alias Storyarn.Flows
  alias Storyarn.Flows.DebugSessionStore
  alias Storyarn.Flows.Evaluator.Engine
  alias Storyarn.Sheets

  # ===========================================================================
  # Public handlers
  # ===========================================================================

  def handle_debug_start(socket) do
    if socket.assigns[:debug_state] do
      {:noreply, socket}
    else
      start_debug_session(socket)
    end
  end

  def handle_debug_change_start_node(%{"node_id" => node_id_str}, socket) do
    case Integer.parse(node_id_str) do
      {node_id, ""} ->
        state = socket.assigns.debug_state
        nodes = socket.assigns.debug_nodes

        if Map.has_key?(nodes, node_id) do
          new_state = Engine.reset(%{state | start_node_id: node_id})

          {:noreply,
           socket
           |> assign(:debug_state, new_state)
           |> assign(:debug_auto_playing, false)
           |> push_event("debug_clear_highlights", %{})
           |> push_debug_canvas(new_state)}
        else
          {:noreply, socket}
        end

      _ ->
        {:noreply, socket}
    end
  end

  def handle_debug_step(socket) do
    state = socket.assigns.debug_state
    nodes = socket.assigns.debug_nodes
    connections = socket.assigns.debug_connections

    result = Engine.step(state, nodes, connections)

    case apply_step_result(result, socket) do
      {:navigating, socket} ->
        {:noreply, socket}

      {:continue, socket} ->
        {:noreply, push_debug_canvas(socket, socket.assigns.debug_state)}
    end
  end

  def handle_debug_step_back(socket) do
    state = socket.assigns.debug_state

    case Engine.step_back(state) do
      {:ok, new_state} ->
        {:noreply,
         socket
         |> assign(:debug_state, new_state)
         |> push_debug_canvas(new_state)}

      {:error, :no_history} ->
        {:noreply, socket}
    end
  end

  def handle_debug_choose_response(%{"id" => response_id}, socket) do
    state = socket.assigns.debug_state
    connections = socket.assigns.debug_connections

    case Engine.choose_response(state, response_id, connections) do
      {:ok, new_state} ->
        socket =
          socket
          |> assign(:debug_state, new_state)
          |> push_debug_canvas(new_state)

        socket =
          if socket.assigns.debug_auto_playing do
            schedule_auto_step(socket)
          else
            socket
          end

        {:noreply, socket}

      {:error, new_state, _reason} ->
        {:noreply,
         socket
         |> assign(:debug_state, new_state)
         |> push_debug_canvas(new_state)}
    end
  end

  def handle_debug_reset(socket) do
    state = socket.assigns.debug_state

    if state.call_stack != [] do
      # Navigate back to root flow when resetting from a sub-flow
      root_frame = List.last(state.call_stack)
      root_flow_id = root_frame.flow_id

      new_state = Engine.reset(state)
      new_state = %{new_state | current_flow_id: root_flow_id}

      socket =
        socket
        |> cancel_auto_timer()
        |> assign(:debug_state, new_state)
        |> assign(:debug_nodes, root_frame.nodes)
        |> assign(:debug_connections, root_frame.connections)
        |> assign(:debug_auto_playing, false)

      {:navigating, socket} = store_and_navigate(socket, root_flow_id)
      {:noreply, socket}
    else
      new_state = Engine.reset(state)

      {:noreply,
       socket
       |> cancel_auto_timer()
       |> assign(:debug_state, new_state)
       |> assign(:debug_auto_playing, false)
       |> push_event("debug_clear_highlights", %{})
       |> push_debug_canvas(new_state)}
    end
  end

  def handle_debug_stop(socket) do
    {:noreply,
     socket
     |> cancel_auto_timer()
     |> assign(:debug_state, nil)
     |> assign(:debug_panel_open, false)
     |> assign(:debug_auto_playing, false)
     |> assign(:debug_nodes, %{})
     |> assign(:debug_connections, [])
     |> push_event("debug_clear_highlights", %{})}
  end

  def handle_debug_tab_change(%{"tab" => tab}, socket) do
    {:noreply, assign(socket, :debug_active_tab, tab)}
  end

  def handle_debug_play(socket) do
    socket =
      socket
      |> assign(:debug_auto_playing, true)
      |> schedule_auto_step()

    {:noreply, socket}
  end

  def handle_debug_pause(socket) do
    {:noreply,
     socket
     |> cancel_auto_timer()
     |> assign(:debug_auto_playing, false)}
  end

  def handle_debug_set_speed(%{"speed" => speed_str}, socket) do
    speed = parse_speed(speed_str)
    {:noreply, assign(socket, :debug_speed, speed)}
  end

  def handle_debug_edit_variable(%{"key" => key}, socket) do
    {:noreply, assign(socket, :debug_editing_var, key)}
  end

  def handle_debug_cancel_edit(socket) do
    {:noreply, assign(socket, :debug_editing_var, nil)}
  end

  def handle_debug_set_variable(%{"key" => key, "value" => raw_value}, socket) do
    state = socket.assigns.debug_state
    block_type = get_in(state.variables, [key, :block_type])
    {parsed, parse_warning} = parse_variable_value(raw_value, block_type)

    # Add console warning if value didn't parse cleanly
    state =
      if parse_warning do
        Engine.add_console_entry(state, :warning, nil, "", parse_warning)
      else
        state
      end

    case Engine.set_variable(state, key, parsed) do
      {:ok, new_state} ->
        {:noreply,
         socket
         |> assign(:debug_state, new_state)
         |> assign(:debug_editing_var, nil)}

      {:error, :not_found} ->
        {:noreply, assign(socket, :debug_editing_var, nil)}
    end
  end

  def handle_debug_var_filter(%{"filter" => filter}, socket) do
    {:noreply, assign(socket, :debug_var_filter, filter)}
  end

  def handle_debug_var_toggle_changed(socket) do
    {:noreply, assign(socket, :debug_var_changed_only, !socket.assigns.debug_var_changed_only)}
  end

  def handle_debug_toggle_breakpoint(%{"node_id" => node_id_str}, socket) do
    case Integer.parse(node_id_str) do
      {node_id, ""} ->
        state = Engine.toggle_breakpoint(socket.assigns.debug_state, node_id)

        {:noreply,
         socket
         |> assign(:debug_state, state)
         |> push_event("debug_update_breakpoints", %{
           breakpoint_ids: MapSet.to_list(state.breakpoints)
         })}

      _ ->
        {:noreply, socket}
    end
  end

  def handle_debug_auto_step(socket) do
    state = socket.assigns.debug_state

    cond do
      !socket.assigns.debug_auto_playing || is_nil(state) || state.status == :finished ->
        {:noreply, assign(socket, :debug_auto_playing, false)}

      state.status == :waiting_input ->
        {:noreply, socket}

      true ->
        do_auto_step(socket, state)
    end
  end

  defp do_auto_step(socket, state) do
    nodes = socket.assigns.debug_nodes
    connections = socket.assigns.debug_connections
    result = Engine.step(state, nodes, connections)

    case apply_step_result(result, socket) do
      {:navigating, socket} ->
        {:noreply, socket}

      {:continue, socket} ->
        finalize_auto_step(socket)
    end
  end

  defp finalize_auto_step(socket) do
    new_state = socket.assigns.debug_state

    {new_state, hit_breakpoint} = maybe_hit_breakpoint(new_state)

    socket =
      socket
      |> assign(:debug_state, new_state)
      |> push_debug_canvas(new_state)

    schedule_or_stop_auto_play(socket, new_state, hit_breakpoint)
  end

  defp maybe_hit_breakpoint(state) do
    if state.status not in [:finished, :waiting_input] and Engine.at_breakpoint?(state) do
      {Engine.add_breakpoint_hit(state, state.current_node_id), true}
    else
      {state, false}
    end
  end

  defp schedule_or_stop_auto_play(socket, _state, true) do
    {:noreply, assign(socket, :debug_auto_playing, false)}
  end

  defp schedule_or_stop_auto_play(socket, %{status: :finished}, _hit_breakpoint) do
    {:noreply, assign(socket, :debug_auto_playing, false)}
  end

  defp schedule_or_stop_auto_play(socket, %{status: :waiting_input}, _hit_breakpoint) do
    {:noreply, socket}
  end

  defp schedule_or_stop_auto_play(socket, _state, _hit_breakpoint) do
    {:noreply, schedule_auto_step(socket)}
  end

  # ===========================================================================
  # Private — session init
  # ===========================================================================

  defp start_debug_session(socket) do
    project = socket.assigns.project
    flow = socket.assigns.flow

    nodes_map = build_nodes_map(flow.id)
    connections = build_connections(flow.id)

    case find_entry_node(nodes_map) do
      nil ->
        {:noreply, put_flash(socket, :error, gettext("No entry node found in this flow."))}

      entry_node_id ->
        variables = build_variables(project.id)
        state = Engine.init(variables, entry_node_id)
        state = %{state | current_flow_id: flow.id}

        {:noreply,
         socket
         |> assign(:debug_state, state)
         |> assign(:debug_panel_open, true)
         |> assign(:debug_active_tab, "console")
         |> assign(:debug_nodes, nodes_map)
         |> assign(:debug_connections, connections)
         |> push_debug_canvas(state)}
    end
  end

  # ===========================================================================
  # Private — step result handling (cross-flow transitions)
  # ===========================================================================

  # Updates socket assigns based on Engine.step result.
  # Returns {:continue, socket} for normal steps, {:navigating, socket} for cross-flow.
  defp apply_step_result({:flow_jump, state, target_flow_id}, socket) do
    current_node_id = state.current_node_id
    nodes = socket.assigns.debug_nodes
    connections = socket.assigns.debug_connections
    flow_name = socket.assigns.flow.name

    state = Engine.push_flow_context(state, current_node_id, nodes, connections, flow_name)

    target_nodes = build_nodes_map(target_flow_id)
    target_connections = build_connections(target_flow_id)

    case find_entry_node(target_nodes) do
      nil ->
        {:continue, assign(socket, :debug_state, %{state | status: :finished})}

      entry_id ->
        log_entry = %{node_id: entry_id, depth: length(state.call_stack)}

        state = %{
          state
          | current_node_id: entry_id,
            current_flow_id: target_flow_id,
            execution_path: [entry_id | state.execution_path],
            execution_log: [log_entry | state.execution_log]
        }

        socket =
          socket
          |> assign(:debug_state, state)
          |> assign(:debug_nodes, target_nodes)
          |> assign(:debug_connections, target_connections)

        store_and_navigate(socket, target_flow_id)
    end
  end

  defp apply_step_result({:flow_return, state}, socket) do
    case Engine.pop_flow_context(state) do
      {:error, :empty_stack} ->
        {:continue, assign(socket, :debug_state, %{state | status: :finished})}

      {:ok, frame, state} ->
        state = %{state | current_flow_id: frame.flow_id}

        # Find next node after the return node in restored connections
        next_conn =
          Enum.find(frame.connections, fn c ->
            c.source_node_id == frame.return_node_id
          end)

        state =
          if next_conn do
            log_entry = %{node_id: next_conn.target_node_id, depth: length(state.call_stack)}

            %{
              state
              | current_node_id: next_conn.target_node_id,
                execution_path: [next_conn.target_node_id | frame.execution_path],
                execution_log: [log_entry | state.execution_log]
            }
          else
            %{state | status: :finished}
          end

        socket =
          socket
          |> assign(:debug_state, state)
          |> assign(:debug_nodes, frame.nodes)
          |> assign(:debug_connections, frame.connections)

        store_and_navigate(socket, frame.flow_id)
    end
  end

  defp apply_step_result({_status, state}, socket) do
    {:continue, assign(socket, :debug_state, state)}
  end

  defp apply_step_result({:error, state, _reason}, socket) do
    {:continue, assign(socket, :debug_state, state)}
  end

  defp store_and_navigate(socket, target_flow_id) do
    user_id = socket.assigns.current_scope.user.id
    project_id = socket.assigns.project.id
    workspace_slug = socket.assigns.workspace.slug
    project_slug = socket.assigns.project.slug

    debug_assigns = %{
      debug_state: socket.assigns.debug_state,
      debug_nodes: socket.assigns.debug_nodes,
      debug_connections: socket.assigns.debug_connections,
      debug_panel_open: true,
      debug_active_tab: socket.assigns.debug_active_tab,
      debug_speed: socket.assigns.debug_speed,
      debug_auto_playing: socket.assigns.debug_auto_playing,
      debug_editing_var: nil,
      debug_var_filter: socket.assigns.debug_var_filter,
      debug_var_changed_only: socket.assigns.debug_var_changed_only
    }

    DebugSessionStore.store({user_id, project_id}, debug_assigns)

    path =
      "/workspaces/#{workspace_slug}/projects/#{project_slug}/flows/#{target_flow_id}"

    {:navigating, push_navigate(socket, to: path)}
  end

  # ===========================================================================
  # Private — data conversion
  # ===========================================================================

  defp build_variables(project_id) do
    Sheets.list_project_variables(project_id)
    |> Enum.reduce(%{}, fn var, acc ->
      key = "#{var.sheet_shortcut}.#{var.variable_name}"

      Map.put(acc, key, %{
        value: default_value(var.block_type),
        initial_value: default_value(var.block_type),
        previous_value: default_value(var.block_type),
        source: :initial,
        block_type: var.block_type,
        block_id: var.block_id,
        sheet_shortcut: var.sheet_shortcut,
        variable_name: var.variable_name
      })
    end)
  end

  defp default_value("number"), do: 0
  defp default_value("boolean"), do: false
  defp default_value("text"), do: ""
  defp default_value("rich_text"), do: ""
  defp default_value(_), do: nil

  defp build_nodes_map(flow_id) do
    Flows.list_nodes(flow_id)
    |> Map.new(fn node -> {node.id, %{id: node.id, type: node.type, data: node.data || %{}}} end)
  end

  defp build_connections(flow_id) do
    Flows.list_connections(flow_id)
    |> Enum.map(fn conn ->
      %{
        source_node_id: conn.source_node_id,
        source_pin: conn.source_pin,
        target_node_id: conn.target_node_id,
        target_pin: conn.target_pin
      }
    end)
  end

  defp find_entry_node(nodes_map) do
    Enum.find_value(nodes_map, fn {id, node} ->
      if node.type == "entry", do: id
    end)
  end

  # ===========================================================================
  # Private — canvas push events
  # ===========================================================================

  defp push_debug_canvas(socket, state) do
    # execution_path is stored in newest-first order; reverse for display
    path = Enum.reverse(state.execution_path)
    active_connection = find_active_connection(path, socket.assigns.debug_connections)

    # Show "error" status when current node has an error console entry
    status_str =
      if state.status == :finished and
           Enum.any?(state.console, &(&1.level == :error and &1.node_id == state.current_node_id)) do
        "error"
      else
        to_string(state.status)
      end

    socket
    |> push_event("debug_highlight_node", %{
      node_id: state.current_node_id,
      status: status_str,
      execution_path: path
    })
    |> push_event("debug_highlight_connections", %{
      active_connection: active_connection,
      execution_path: path
    })
  end

  defp find_active_connection([], _connections), do: nil
  defp find_active_connection([_single], _connections), do: nil

  defp find_active_connection(path, connections) do
    source_id = Enum.at(path, -2)
    target_id = Enum.at(path, -1)

    Enum.find_value(connections, fn conn ->
      if conn.source_node_id == source_id and conn.target_node_id == target_id do
        %{source_node_id: source_id, target_node_id: target_id, source_pin: conn.source_pin}
      end
    end)
  end

  defp parse_speed(val) when is_binary(val) do
    case Integer.parse(val) do
      {n, _} -> max(200, min(n, 3000))
      :error -> 800
    end
  end

  defp parse_speed(val) when is_integer(val), do: max(200, min(val, 3000))
  defp parse_speed(_), do: 800

  defp parse_variable_value(raw, "number") do
    case Float.parse(raw) do
      {n, _} ->
        {n, nil}

      :error ->
        warning =
          if raw != "",
            do: "Invalid number \"#{String.slice(raw, 0, 20)}\", using 0",
            else: nil

        {0, warning}
    end
  end

  defp parse_variable_value("true", "boolean"), do: {true, nil}
  defp parse_variable_value(_, "boolean"), do: {false, nil}
  defp parse_variable_value(raw, _), do: {raw, nil}

  # ===========================================================================
  # Private — auto-play timer management
  # ===========================================================================

  defp schedule_auto_step(socket) do
    socket = cancel_auto_timer(socket)
    speed = socket.assigns.debug_speed
    ref = Process.send_after(self(), :debug_auto_step, speed)
    assign(socket, :debug_auto_timer, ref)
  end

  defp cancel_auto_timer(socket) do
    case socket.assigns[:debug_auto_timer] do
      nil ->
        socket

      ref ->
        Process.cancel_timer(ref)
        assign(socket, :debug_auto_timer, nil)
    end
  end
end
