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
        socket =
          socket
          |> assign(:debug_state, new_state)
          |> push_debug_canvas(new_state)

        if socket.assigns.debug_auto_playing do
          speed = socket.assigns.debug_speed
          Process.send_after(self(), :debug_auto_step, speed)
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
    new_state = Engine.reset(state)

    {:noreply,
     socket
     |> assign(:debug_state, new_state)
     |> assign(:debug_auto_playing, false)
     |> push_event("debug_clear_highlights", %{})
     |> push_debug_canvas(new_state)}
  end

  def handle_debug_stop(socket) do
    {:noreply,
     socket
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
    speed = socket.assigns.debug_speed
    Process.send_after(self(), :debug_auto_step, speed)

    {:noreply, assign(socket, :debug_auto_playing, true)}
  end

  def handle_debug_pause(socket) do
    {:noreply, assign(socket, :debug_auto_playing, false)}
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
    parsed = parse_variable_value(raw_value, block_type)

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

  def handle_debug_auto_step(socket) do
    state = socket.assigns.debug_state

    cond do
      !socket.assigns.debug_auto_playing || is_nil(state) || state.status == :finished ->
        {:noreply, assign(socket, :debug_auto_playing, false)}

      state.status == :waiting_input ->
        # Keep auto-play active but don't schedule next step — wait for user choice
        {:noreply, socket}

      true ->
        nodes = socket.assigns.debug_nodes
        connections = socket.assigns.debug_connections

        case Engine.step(state, nodes, connections) do
          {status, new_state} ->
            socket =
              socket
              |> assign(:debug_state, new_state)
              |> push_debug_canvas(new_state)

            cond do
              status == :finished ->
                {:noreply, assign(socket, :debug_auto_playing, false)}

              status == :waiting_input ->
                # Keep auto-play active, wait for user to choose a response
                {:noreply, socket}

              true ->
                speed = socket.assigns.debug_speed
                Process.send_after(self(), :debug_auto_step, speed)
                {:noreply, socket}
            end

          {:error, new_state, _reason} ->
            {:noreply,
             socket
             |> assign(:debug_state, new_state)
             |> assign(:debug_auto_playing, false)
             |> push_debug_canvas(new_state)}
        end
    end
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
    active_connection = find_active_connection(state, socket.assigns.debug_connections)

    socket
    |> push_event("debug_highlight_node", %{
      node_id: state.current_node_id,
      status: to_string(state.status),
      execution_path: state.execution_path
    })
    |> push_event("debug_highlight_connections", %{
      active_connection: active_connection,
      execution_path: state.execution_path
    })
  end

  defp find_active_connection(state, connections) do
    path = state.execution_path

    case path do
      [] ->
        nil

      [_single] ->
        nil

      _ ->
        source_id = Enum.at(path, -2)
        target_id = Enum.at(path, -1)

        Enum.find_value(connections, fn conn ->
          if conn.source_node_id == source_id and conn.target_node_id == target_id do
            %{source_node_id: source_id, target_node_id: target_id, source_pin: conn.source_pin}
          end
        end)
    end
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
      {n, _} -> n
      :error -> 0
    end
  end

  defp parse_variable_value("true", "boolean"), do: true
  defp parse_variable_value(_, "boolean"), do: false
  defp parse_variable_value(raw, _), do: raw
end
