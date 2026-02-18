defmodule StoryarnWeb.FlowLive.Handlers.DebugExecutionHandlers do
  @moduledoc """
  Execution handlers for the flow debugger: step, play, auto-step, and cross-flow navigation.

  Also exports canvas push utilities and timer helpers used by DebugSessionHandlers.
  """

  import Phoenix.Component, only: [assign: 3]
  import Phoenix.LiveView, only: [push_event: 3, push_navigate: 2]

  use StoryarnWeb, :verified_routes

  alias Storyarn.Flows
  alias Storyarn.Flows.DebugSessionStore
  alias Storyarn.Flows.Evaluator.Engine

  def handle_debug_step(socket) do
    state = socket.assigns.debug_state
    nodes = socket.assigns.debug_nodes
    connections = socket.assigns.debug_connections

    result = Engine.step(state, nodes, connections)

    case apply_step_result(result, socket) do
      {:navigating, socket} -> {:noreply, socket}
      {:continue, socket} -> {:noreply, push_debug_canvas(socket, socket.assigns.debug_state)}
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

  # ===========================================================================
  # Public helpers (used by DebugSessionHandlers)
  # ===========================================================================

  def push_debug_canvas(socket, state) do
    path = Enum.reverse(state.execution_path)
    active_connection = find_active_connection(path, socket.assigns.debug_connections)

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

  def store_and_navigate(socket, target_flow_id) do
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
      ~p"/workspaces/#{workspace_slug}/projects/#{project_slug}/flows/#{target_flow_id}"

    {:navigating, push_navigate(socket, to: path)}
  end

  def schedule_auto_step(socket) do
    socket = cancel_auto_timer(socket)
    speed = socket.assigns.debug_speed
    ref = Process.send_after(self(), :debug_auto_step, speed)
    assign(socket, :debug_auto_timer, ref)
  end

  def cancel_auto_timer(socket) do
    case socket.assigns[:debug_auto_timer] do
      nil -> socket
      ref ->
        Process.cancel_timer(ref)
        assign(socket, :debug_auto_timer, nil)
    end
  end

  # ===========================================================================
  # Private
  # ===========================================================================

  defp do_auto_step(socket, state) do
    nodes = socket.assigns.debug_nodes
    connections = socket.assigns.debug_connections
    result = Engine.step(state, nodes, connections)

    case apply_step_result(result, socket) do
      {:navigating, socket} -> {:noreply, socket}
      {:continue, socket} -> finalize_auto_step(socket)
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

  defp schedule_or_stop_auto_play(socket, _state, true),
    do: {:noreply, assign(socket, :debug_auto_playing, false)}

  defp schedule_or_stop_auto_play(socket, %{status: :finished}, _),
    do: {:noreply, assign(socket, :debug_auto_playing, false)}

  defp schedule_or_stop_auto_play(socket, %{status: :waiting_input}, _),
    do: {:noreply, socket}

  defp schedule_or_stop_auto_play(socket, _state, _),
    do: {:noreply, schedule_auto_step(socket)}

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

  defp apply_step_result({_status, state}, socket),
    do: {:continue, assign(socket, :debug_state, state)}

  defp apply_step_result({:error, state, _reason}, socket),
    do: {:continue, assign(socket, :debug_state, state)}

  defp find_active_connection([], _), do: nil
  defp find_active_connection([_single], _), do: nil

  defp find_active_connection(path, connections) do
    source_id = Enum.at(path, -2)
    target_id = Enum.at(path, -1)

    Enum.find_value(connections, fn conn ->
      if conn.source_node_id == source_id and conn.target_node_id == target_id do
        %{source_node_id: source_id, target_node_id: target_id, source_pin: conn.source_pin}
      end
    end)
  end

  def build_nodes_map(flow_id) do
    Flows.list_nodes(flow_id)
    |> Map.new(fn node -> {node.id, %{id: node.id, type: node.type, data: node.data || %{}}} end)
  end

  def build_connections(flow_id) do
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

  def find_entry_node(nodes_map) do
    Enum.find_value(nodes_map, fn {id, node} ->
      if node.type == "entry", do: id
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
end
