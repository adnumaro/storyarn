defmodule StoryarnWeb.FlowLive.Handlers.DebugSessionHandlers do
  @moduledoc """
  Session lifecycle handlers for the flow debugger: start, stop, reset, variable management,
  breakpoints, and tab/speed controls.
  """

  import Phoenix.Component, only: [assign: 3]
  import Phoenix.LiveView, only: [push_event: 3, put_flash: 3]

  use Gettext, backend: StoryarnWeb.Gettext

  alias Storyarn.Flows.Evaluator.Engine
  alias StoryarnWeb.FlowLive.Handlers.DebugExecutionHandlers
  alias StoryarnWeb.FlowLive.Helpers.VariableHelpers

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
           |> DebugExecutionHandlers.push_debug_canvas(new_state)}
        else
          {:noreply, socket}
        end

      _ ->
        {:noreply, socket}
    end
  end

  def handle_debug_reset(socket) do
    state = socket.assigns.debug_state

    if state.call_stack != [] do
      root_frame = List.last(state.call_stack)
      root_flow_id = root_frame.flow_id

      new_state = Engine.reset(state)
      new_state = %{new_state | current_flow_id: root_flow_id}

      socket =
        socket
        |> DebugExecutionHandlers.cancel_auto_timer()
        |> assign(:debug_state, new_state)
        |> assign(:debug_nodes, root_frame.nodes)
        |> assign(:debug_connections, root_frame.connections)
        |> assign(:debug_auto_playing, false)
        |> assign(:debug_step_limit_reached, false)

      {:navigating, navigated_socket} =
        DebugExecutionHandlers.store_and_navigate(socket, root_flow_id)

      {:noreply, navigated_socket}
    else
      new_state = Engine.reset(state)

      {:noreply,
       socket
       |> DebugExecutionHandlers.cancel_auto_timer()
       |> assign(:debug_state, new_state)
       |> assign(:debug_auto_playing, false)
       |> assign(:debug_step_limit_reached, false)
       |> push_event("debug_clear_highlights", %{})
       |> DebugExecutionHandlers.push_debug_canvas(new_state)}
    end
  end

  def handle_debug_stop(socket) do
    {:noreply,
     socket
     |> DebugExecutionHandlers.cancel_auto_timer()
     |> assign(:debug_state, nil)
     |> assign(:debug_panel_open, false)
     |> assign(:debug_auto_playing, false)
     |> assign(:debug_step_limit_reached, false)
     |> assign(:debug_nodes, %{})
     |> assign(:debug_connections, [])
     |> push_event("debug_clear_highlights", %{})}
  end

  def handle_debug_tab_change(%{"tab" => tab}, socket) do
    {:noreply, assign(socket, :debug_active_tab, tab)}
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

  def handle_debug_continue_past_limit(socket) do
    state = socket.assigns.debug_state
    new_state = Engine.extend_step_limit(state)

    {:noreply,
     socket
     |> assign(:debug_state, new_state)
     |> assign(:debug_step_limit_reached, false)}
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

  # ===========================================================================
  # Private — session init
  # ===========================================================================

  defp start_debug_session(socket) do
    project = socket.assigns.project
    flow = socket.assigns.flow

    nodes_map = DebugExecutionHandlers.build_nodes_map(flow.id)
    connections = DebugExecutionHandlers.build_connections(flow.id)

    case DebugExecutionHandlers.find_entry_node(nodes_map) do
      nil ->
        {:noreply,
         put_flash(socket, :error, dgettext("flows", "No entry node found in this flow."))}

      entry_node_id ->
        variables = VariableHelpers.build_variables(project.id)
        state = Engine.init(variables, entry_node_id)
        state = %{state | current_flow_id: flow.id}

        {:noreply,
         socket
         |> assign(:debug_state, state)
         |> assign(:debug_panel_open, true)
         |> assign(:debug_active_tab, "console")
         |> assign(:debug_nodes, nodes_map)
         |> assign(:debug_connections, connections)
         |> DebugExecutionHandlers.push_debug_canvas(state)}
    end
  end

  # ===========================================================================
  # Private — data conversion
  # ===========================================================================

  defp parse_variable_value(raw, "number") do
    case Float.parse(raw) do
      {n, _} ->
        {n, nil}

      :error ->
        warning =
          if raw != "",
            do:
              dgettext("flows", "Invalid number \"%{value}\", using 0",
                value: String.slice(raw, 0, 20)
              ),
            else: nil

        {0, warning}
    end
  end

  defp parse_variable_value("true", "boolean"), do: {true, nil}
  defp parse_variable_value(_, "boolean"), do: {false, nil}
  defp parse_variable_value(raw, _), do: {raw, nil}
end
