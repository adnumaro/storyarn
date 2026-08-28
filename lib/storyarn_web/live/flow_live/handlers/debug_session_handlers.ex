defmodule StoryarnWeb.FlowLive.Handlers.DebugSessionHandlers do
  @moduledoc """
  Session lifecycle handlers for the flow debugger: start, stop, reset, variable management,
  breakpoints, and tab/speed controls.
  """

  use Gettext, backend: Storyarn.Gettext

  import Phoenix.Component, only: [assign: 3]
  import Phoenix.LiveView, only: [push_event: 3, put_flash: 3]

  alias Storyarn.Flows
  alias StoryarnWeb.FlowLive.Handlers.DebugExecutionHandlers

  def handle_debug_start(socket) do
    if socket.assigns[:debug_state] do
      {:noreply, socket}
    else
      start_debug_session(socket)
    end
  end

  def handle_debug_change_start_node(%{"node_id" => node_id_str}, socket) do
    case Flows.debug_select_start_node(
           socket.assigns.debug_state,
           socket.assigns.debug_nodes,
           node_id_str
         ) do
      {:ok, new_state} ->
        {:noreply,
         socket
         |> assign(:debug_state, new_state)
         |> assign(:debug_auto_playing, false)
         |> push_event("debug_clear_highlights", %{})
         |> DebugExecutionHandlers.push_debug_canvas(new_state)}

      {:error, :invalid_node} ->
        {:noreply, socket}
    end
  end

  def handle_debug_reset(socket) do
    state = socket.assigns.debug_state

    result =
      Flows.reset_debug_session(
        state,
        socket.assigns.debug_nodes,
        socket.assigns.debug_connections
      )

    case result do
      {:continue, new_state, graph} ->
        graph = DebugExecutionHandlers.present_runtime_graph(graph)

        {:noreply,
         socket
         |> DebugExecutionHandlers.cancel_auto_timer()
         |> assign(:debug_state, new_state)
         |> assign(:debug_nodes, graph.nodes)
         |> assign(:debug_connections, graph.connections)
         |> assign(:debug_auto_playing, false)
         |> assign(:debug_step_limit_reached, false)
         |> push_event("debug_clear_highlights", %{})
         |> DebugExecutionHandlers.push_debug_canvas(new_state)}

      {:navigate, new_state, graph, root_flow_id} ->
        graph = DebugExecutionHandlers.present_runtime_graph(graph)

        socket =
          socket
          |> DebugExecutionHandlers.cancel_auto_timer()
          |> assign(:debug_state, new_state)
          |> assign(:debug_nodes, graph.nodes)
          |> assign(:debug_connections, graph.connections)
          |> assign(:debug_auto_playing, false)
          |> assign(:debug_step_limit_reached, false)

        {:navigating, navigated_socket} =
          DebugExecutionHandlers.store_and_navigate(socket, root_flow_id)

        {:noreply, navigated_socket}
    end
  end

  def handle_debug_stop(socket) do
    stopped_session = Flows.stop_debug_session()

    {:noreply,
     socket
     |> DebugExecutionHandlers.cancel_auto_timer()
     |> assign(:debug_state, stopped_session.state)
     |> assign(:debug_panel_open, false)
     |> assign(:debug_auto_playing, false)
     |> assign(:debug_step_limit_reached, false)
     |> assign(:debug_nodes, stopped_session.graph.nodes)
     |> assign(:debug_connections, stopped_session.graph.connections)
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
    case Flows.set_debug_variable(socket.assigns.debug_state, key, raw_value) do
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
    new_state = Flows.extend_debug_step_limit(state)

    {:noreply,
     socket
     |> assign(:debug_state, new_state)
     |> assign(:debug_step_limit_reached, false)}
  end

  def handle_debug_toggle_breakpoint(%{"node_id" => node_id_str}, socket) do
    case Flows.toggle_debug_breakpoint(socket.assigns.debug_state, node_id_str) do
      {:ok, state} ->
        {:noreply,
         socket
         |> assign(:debug_state, state)
         |> push_event("debug_update_breakpoints", %{
           breakpoint_ids: MapSet.to_list(state.breakpoints)
         })}

      {:error, :invalid_node} ->
        {:noreply, socket}
    end
  end

  # ===========================================================================
  # Private — session init
  # ===========================================================================

  defp start_debug_session(socket) do
    flow = socket.assigns.flow

    case Flows.start_debug_session(socket.assigns.current_scope, flow) do
      {:error, :no_entry_node} ->
        {:noreply, put_flash(socket, :error, dgettext("flows", "No entry node found in this flow."))}

      {:ok, %{state: state, graph: runtime_graph}} ->
        graph = DebugExecutionHandlers.present_runtime_graph(runtime_graph)

        {:noreply,
         socket
         |> assign(:debug_state, state)
         |> assign(:debug_panel_open, true)
         |> assign(:debug_active_tab, "console")
         |> assign(:debug_nodes, graph.nodes)
         |> assign(:debug_connections, graph.connections)
         |> DebugExecutionHandlers.push_debug_canvas(state)}
    end
  end
end
