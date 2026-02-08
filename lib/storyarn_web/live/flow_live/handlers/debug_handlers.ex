defmodule StoryarnWeb.FlowLive.Handlers.DebugHandlers do
  @moduledoc """
  Event handlers for the flow debugger.

  Manages the debug session lifecycle: start, step, step_back, choose_response,
  reset, and stop. Bridges between LiveView events and the pure functional
  Evaluator.Engine.
  """

  import Phoenix.Component, only: [assign: 3]
  import Phoenix.LiveView, only: [push_event: 3, put_flash: 3]

  use Gettext, backend: StoryarnWeb.Gettext

  alias Storyarn.Flows
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

  def handle_debug_step(socket) do
    state = socket.assigns.debug_state
    nodes = socket.assigns.debug_nodes
    connections = socket.assigns.debug_connections

    case Engine.step(state, nodes, connections) do
      {_status, new_state} ->
        {:noreply,
         socket
         |> assign(:debug_state, new_state)
         |> push_debug_canvas(new_state)}

      {:error, new_state, _reason} ->
        {:noreply,
         socket
         |> assign(:debug_state, new_state)
         |> push_debug_canvas(new_state)}
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
        {:noreply,
         socket
         |> assign(:debug_state, new_state)
         |> push_debug_canvas(new_state)}

      {:error, new_state, _reason} ->
        {:noreply,
         socket
         |> assign(:debug_state, new_state)
         |> push_debug_canvas(new_state)}
    end
  end

  def handle_debug_reset(socket) do
    state = socket.assigns.debug_state
    new_state = Engine.reset(state)

    {:noreply,
     socket
     |> assign(:debug_state, new_state)
     |> push_event("debug_clear_highlights", %{})
     |> push_debug_canvas(new_state)}
  end

  def handle_debug_stop(socket) do
    {:noreply,
     socket
     |> assign(:debug_state, nil)
     |> assign(:debug_panel_open, false)
     |> assign(:debug_nodes, %{})
     |> assign(:debug_connections, [])
     |> push_event("debug_clear_highlights", %{})}
  end

  def handle_debug_tab_change(%{"tab" => tab}, socket) do
    {:noreply, assign(socket, :debug_active_tab, tab)}
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
    push_event(socket, "debug_highlight_node", %{
      node_id: state.current_node_id,
      status: to_string(state.status),
      execution_path: state.execution_path
    })
  end
end
