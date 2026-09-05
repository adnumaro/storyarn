defmodule StoryarnWeb.FlowLive.Handlers.DebugExecutionHandlers do
  @moduledoc """
  Execution handlers for the flow debugger: step, play, auto-step, and cross-flow navigation.

  Also exports canvas push utilities and timer helpers used by DebugSessionHandlers.
  """

  use StoryarnWeb, :verified_routes

  import Phoenix.Component, only: [assign: 3]
  import Phoenix.LiveView, only: [push_event: 3, push_patch: 2]

  alias Storyarn.Flows
  alias StoryarnWeb.FlowLive.Helpers.SequencePresentation
  alias StoryarnWeb.PrivateMedia

  @doc "Advances the debugger by one step. May trigger cross-flow navigation."
  def handle_debug_step(socket) do
    state = socket.assigns.debug_state
    nodes = socket.assigns.debug_nodes
    connections = socket.assigns.debug_connections

    result = Flows.debug_step(state, nodes, connections, socket.assigns.flow.name)

    case apply_debug_result(result, socket) do
      {:navigating, socket} ->
        {:noreply, socket}

      {:continue, socket} ->
        {:noreply, push_debug_canvas(socket, socket.assigns.debug_state)}
    end
  end

  @doc "Steps back to the previous state in the execution history."
  def handle_debug_step_back(socket) do
    state = socket.assigns.debug_state

    case Flows.debug_step_back(state) do
      {:ok, new_state} ->
        restore_debug_state(socket, state, new_state)

      {:error, :no_history} ->
        {:noreply, socket}
    end
  end

  @doc "Selects a dialogue response and advances past the choice point."
  def handle_debug_choose_response(%{"id" => response_id}, socket) do
    state = socket.assigns.debug_state
    connections = socket.assigns.debug_connections

    case Flows.debug_choose_response(state, response_id, connections) do
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

  @doc "Starts auto-play mode, stepping at the configured speed."
  def handle_debug_play(socket) do
    socket =
      socket
      |> assign(:debug_auto_playing, true)
      |> schedule_auto_step()

    {:noreply, socket}
  end

  @doc "Pauses auto-play mode."
  def handle_debug_pause(socket) do
    {:noreply,
     socket
     |> cancel_auto_timer()
     |> assign(:debug_auto_playing, false)}
  end

  @doc "Sets the auto-play step interval (200-3000ms)."
  def handle_debug_set_speed(%{"speed" => speed_str}, socket) do
    speed = parse_speed(speed_str)
    {:noreply, assign(socket, :debug_speed, speed)}
  end

  @doc "Timer callback for auto-play. Stops at breakpoints or waiting_input states."
  def handle_debug_auto_step(socket) do
    state = socket.assigns.debug_state

    if !socket.assigns.debug_auto_playing || is_nil(state) do
      {:noreply, assign(socket, :debug_auto_playing, false)}
    else
      do_auto_step(socket, state)
    end
  end

  # ===========================================================================
  # Public helpers (used by DebugSessionHandlers)
  # ===========================================================================

  @doc "Pushes node highlight and connection highlight events to the canvas."
  def push_debug_canvas(socket, state) do
    path = Enum.reverse(state.execution_path)
    active_connection = Flows.debug_active_connection(path, socket.assigns.debug_connections)

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

  @doc "Stores debug session to ETS and navigates to a different flow (cross-flow debugging)."
  def store_and_navigate(socket, target_flow_id) do
    user_id = socket.assigns.current_scope.user.id
    project_id = socket.assigns.project.id
    workspace_slug = socket.assigns.workspace.slug
    project_slug = socket.assigns.project.slug
    session_id = socket.assigns.debug_session_id

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
      debug_var_changed_only: socket.assigns.debug_var_changed_only,
      debug_step_limit_reached: socket.assigns[:debug_step_limit_reached] || false
    }

    Flows.debug_session_store({:debug, user_id, project_id, session_id}, debug_assigns)

    path =
      ~p"/workspaces/#{workspace_slug}/projects/#{project_slug}/flows/#{target_flow_id}?debug_session=#{session_id}"

    {:navigating, push_patch(socket, to: path)}
  end

  @doc "Schedules the next auto-step timer at the configured speed."
  def schedule_auto_step(socket) do
    socket = cancel_auto_timer(socket)
    speed = socket.assigns.debug_speed
    ref = Process.send_after(self(), :debug_auto_step, speed)
    assign(socket, :debug_auto_timer, ref)
  end

  @doc "Cancels the running auto-step timer if one exists."
  def cancel_auto_timer(socket) do
    case socket.assigns[:debug_auto_timer] do
      nil ->
        socket

      ref ->
        Process.cancel_timer(ref)
        assign(socket, :debug_auto_timer, nil)
    end
  end

  # ===========================================================================
  # Private
  # ===========================================================================

  defp restore_debug_state(socket, previous_state, new_state) do
    if changed_flow?(previous_state, new_state) do
      graph = new_state.current_flow_id |> Flows.load_runtime_graph() |> present_runtime_graph()

      socket =
        socket
        |> assign(:debug_state, new_state)
        |> assign(:debug_nodes, graph.nodes)
        |> assign(:debug_connections, graph.connections)

      {:navigating, socket} = store_and_navigate(socket, new_state.current_flow_id)
      {:noreply, socket}
    else
      {:noreply,
       socket
       |> assign(:debug_state, new_state)
       |> push_debug_canvas(new_state)}
    end
  end

  defp changed_flow?(previous_state, new_state) do
    is_integer(new_state.current_flow_id) and
      new_state.current_flow_id != previous_state.current_flow_id
  end

  defp do_auto_step(socket, state) do
    nodes = socket.assigns.debug_nodes
    connections = socket.assigns.debug_connections
    result = Flows.debug_auto_step(state, nodes, connections, socket.assigns.flow.name)

    case apply_auto_step_result(result, socket) do
      {:navigating, socket} -> {:noreply, socket}
      {:continue, socket, :stop} -> {:noreply, assign(socket, :debug_auto_playing, false)}
      {:continue, socket, :wait} -> {:noreply, socket}
      {:continue, socket, :continue} -> {:noreply, schedule_auto_step(socket)}
    end
  end

  defp apply_debug_result({:navigate, state, graph, target_flow_id}, socket) do
    graph = present_runtime_graph(graph)

    socket =
      socket
      |> assign(:debug_state, state)
      |> assign(:debug_nodes, graph.nodes)
      |> assign(:debug_connections, graph.connections)

    store_and_navigate(socket, target_flow_id)
  end

  defp apply_debug_result({:continue, state, graph, step_limit_reached?}, socket) do
    graph = present_runtime_graph(graph)

    socket =
      socket
      |> assign(:debug_state, state)
      |> assign(:debug_nodes, graph.nodes)
      |> assign(:debug_connections, graph.connections)
      |> assign(:debug_step_limit_reached, step_limit_reached?)

    socket =
      if step_limit_reached? do
        socket
        |> cancel_auto_timer()
        |> assign(:debug_auto_playing, false)
      else
        socket
      end

    {:continue, socket}
  end

  defp apply_auto_step_result({:navigate, state, graph, target_flow_id}, socket) do
    apply_debug_result({:navigate, state, graph, target_flow_id}, socket)
  end

  defp apply_auto_step_result({:continue, state, graph, step_limit_reached?, action}, socket) do
    {:continue, socket} =
      apply_debug_result({:continue, state, graph, step_limit_reached?}, socket)

    {:continue, push_debug_canvas(socket, state), action}
  end

  @doc "Converts runtime media records into the client-facing debug graph."
  def present_runtime_graph(%{nodes: nodes, connections: connections}) do
    %{
      nodes: Map.new(nodes, fn {id, node} -> {id, present_runtime_node(node)} end),
      connections: connections
    }
  end

  defp present_runtime_node(node) do
    if Map.has_key?(node, :sequence_config) or
         Map.has_key?(node, :sequence_visual_layers) or
         Map.has_key?(node, :sequence_tracks) do
      %{
        id: node.id,
        type: node.type,
        data: Map.get(node, :data) || %{},
        parent_id: Map.get(node, :parent_id),
        composition_source_id: Map.get(node, :composition_source_id),
        sequence_config: serialize_sequence_config(Map.get(node, :sequence_config)),
        sequence_visual_layers:
          Enum.map(Map.get(node, :sequence_visual_layers) || [], &serialize_sequence_visual_layer/1),
        sequence_tracks: Enum.map(Map.get(node, :sequence_tracks) || [], &serialize_sequence_track/1)
      }
    else
      node
    end
  end

  @doc "Resolves the dialogue whose presentation remains visible at the current debug position."
  @spec presentation_node_id(map() | integer() | String.t() | nil, map()) :: integer() | nil
  def presentation_node_id(state, nodes) when is_map(state) and is_map(nodes) do
    current_node_id = map_value(state, :current_node_id)
    execution_path = List.wrap(map_value(state, :execution_path))

    [current_node_id | execution_path]
    |> Enum.uniq()
    |> Enum.find_value(&dialogue_node_id(&1, nodes))
  end

  def presentation_node_id(node_id, nodes) when is_map(nodes), do: dialogue_node_id(node_id, nodes)
  def presentation_node_id(_state_or_node_id, _nodes), do: nil

  @doc "Builds the effective static composition shown for the debugger's presentation node."
  @spec present_debug_composition(map() | integer() | String.t() | nil, map()) :: map() | nil
  def present_debug_composition(state, nodes) when is_map(state) and is_map(nodes) do
    state
    |> presentation_node_id(nodes)
    |> present_debug_composition(nodes)
  end

  def present_debug_composition(node_id, nodes) when is_binary(node_id) and is_map(nodes) do
    case Integer.parse(node_id) do
      {parsed_id, ""} -> present_debug_composition(parsed_id, nodes)
      _invalid -> nil
    end
  end

  def present_debug_composition(node_id, nodes) when is_integer(node_id) and is_map(nodes) do
    node = Map.get(nodes, node_id) || Map.get(nodes, to_string(node_id))

    if map_value(node, :type) in ["sequence", "dialogue"] do
      do_present_debug_composition(node_id, nodes)
    end
  end

  def present_debug_composition(_state_or_node_id, _nodes), do: nil

  defp do_present_debug_composition(node_id, nodes) do
    composition = Flows.inspect_node_sequences(node_id, nodes)

    %{
      presentationNodeId: node_id,
      visualLayers:
        composition
        |> SequencePresentation.inspectable_visual_layers(node_id)
        |> decorate_debug_items(composition.visual_layers, :key, false, node_id),
      removedVisualLayers:
        composition
        |> SequencePresentation.inspectable_removed_visual_layers(node_id)
        |> decorate_debug_items(composition.removed_visual_layers, :key, true, node_id),
      audioTracks:
        composition
        |> SequencePresentation.inspectable_audio_tracks()
        |> decorate_debug_items(composition.audio_tracks, :trackKey, false, node_id),
      removedAudioTracks:
        composition
        |> SequencePresentation.inspectable_removed_audio_tracks()
        |> decorate_debug_items(composition.removed_audio_tracks, :trackKey, true, node_id),
      diagnostics: SequencePresentation.diagnostics(composition)
    }
  end

  defp decorate_debug_items(serialized_items, composed_items, serialized_key, removed?, selected_node_id) do
    composed_by_key =
      Map.new(composed_items, fn composed ->
        key = Map.get(composed, :layer_key) || Map.get(composed, :track_key)
        {to_string(key), composed}
      end)

    Enum.map(serialized_items, fn serialized ->
      composed = Map.fetch!(composed_by_key, to_string(Map.fetch!(serialized, serialized_key)))
      definition_owner_id = Map.fetch!(composed, :sequence_id)
      latest_owner_id = Map.fetch!(composed, :owner_node_id)

      serialized
      |> Map.put(:origin, %{
        nodeId: definition_owner_id,
        sequenceId: definition_owner_id,
        inherited: definition_owner_id != selected_node_id
      })
      |> Map.put(:lastChangedByNodeId, latest_owner_id)
      |> Map.put(:overriddenProperties, debug_property_overrides(composed))
      |> maybe_put_removed_by(removed?, latest_owner_id)
    end)
  end

  defp debug_property_overrides(composed) do
    composed
    |> Map.get(:property_sources, %{})
    |> Enum.reject(fn {_field, owner_id} -> owner_id == composed.sequence_id end)
    |> Enum.map(fn {field, owner_id} -> %{field: to_string(field), nodeId: owner_id} end)
    |> Enum.sort_by(& &1.field)
  end

  defp maybe_put_removed_by(item, true, owner_id), do: Map.put(item, :removedByNodeId, owner_id)
  defp maybe_put_removed_by(item, false, _owner_id), do: item

  defp dialogue_node_id(node_id, nodes) do
    with {:ok, normalized_id} <- normalize_node_id(node_id),
         node when not is_nil(node) <- Map.get(nodes, normalized_id) || Map.get(nodes, to_string(normalized_id)),
         "dialogue" <- map_value(node, :type) do
      normalized_id
    else
      _not_dialogue -> nil
    end
  end

  defp normalize_node_id(node_id) when is_integer(node_id), do: {:ok, node_id}

  defp normalize_node_id(node_id) when is_binary(node_id) do
    case Integer.parse(node_id) do
      {parsed_id, ""} -> {:ok, parsed_id}
      _invalid -> :error
    end
  end

  defp normalize_node_id(_node_id), do: :error

  defp map_value(nil, _key), do: nil

  defp map_value(map, key) when is_map(map), do: Map.get(map, key, Map.get(map, Atom.to_string(key)))

  defp serialize_sequence_config(%{} = config) do
    %{
      name: config.name,
      width: config.width,
      height: config.height
    }
  end

  defp serialize_sequence_config(_), do: nil

  defp serialize_sequence_visual_layer(%{url: _url} = layer), do: layer

  defp serialize_sequence_visual_layer(layer) do
    %{
      id: layer.id,
      layer_key: Map.get(layer, :layer_key),
      overridden_fields: Map.get(layer, :overridden_fields),
      removed: Map.get(layer, :removed, false),
      asset_id: Map.get(layer, :asset_id),
      kind: layer.kind,
      label: layer.label,
      url: PrivateMedia.asset_url(layer.asset),
      z_index: layer.z_index,
      slot: layer.slot,
      x: layer.x,
      y: layer.y,
      width: layer.width,
      height: layer.height,
      anchor_x: layer.anchor_x,
      anchor_y: layer.anchor_y,
      fit: layer.fit,
      opacity: layer.opacity,
      visible: layer.visible
    }
  end

  defp serialize_sequence_track(%{url: _url} = track), do: track

  defp serialize_sequence_track(track) do
    %{
      id: track.id,
      track_key: Map.get(track, :track_key),
      is_override: Map.get(track, :is_override, false),
      overridden_fields: Map.get(track, :overridden_fields),
      removed: Map.get(track, :removed, false),
      asset_id: Map.get(track, :asset_id),
      kind: track.kind,
      position: track.position || 0,
      url: PrivateMedia.asset_url(track.asset),
      volume: serialize_volume(track.volume),
      content_type: track.asset && track.asset.content_type,
      filename: track.asset && track.asset.filename
    }
  end

  defp serialize_volume(nil), do: 1.0
  defp serialize_volume(%Decimal{} = volume), do: Decimal.to_float(volume)
  defp serialize_volume(volume) when is_number(volume), do: volume

  defp parse_speed(val) when is_binary(val) do
    case Integer.parse(val) do
      {n, _} -> max(200, min(n, 3000))
      :error -> 800
    end
  end

  defp parse_speed(val) when is_integer(val), do: max(200, min(val, 3000))
  defp parse_speed(_), do: 800
end
