defmodule StoryarnWeb.FlowLive.Handlers.PreviewHandlers do
  @moduledoc """
  Handles dialogue preview navigation.

  Ports the logic from the old PreviewComponent LiveComponent into
  socket-based state that drives the FlowPreview Vue component.
  """

  import Phoenix.Component, only: [assign: 2]

  alias Storyarn.Flows
  alias Storyarn.Shared.HtmlSanitizer
  alias Storyarn.Sheets

  @max_traversal_depth 50

  # ============================================================================
  # Public handlers
  # ============================================================================

  @spec handle_start_preview(map(), Phoenix.LiveView.Socket.t()) ::
          {:noreply, Phoenix.LiveView.Socket.t()}
  def handle_start_preview(%{"id" => node_id}, socket) do
    case Flows.get_node(socket.assigns.flow.id, node_id) do
      nil ->
        {:noreply, socket}

      node ->
        socket =
          socket
          |> assign(preview_show: true, preview_history: [])
          |> load_node(node)

        {:noreply, socket}
    end
  end

  @spec handle_select_response(map(), Phoenix.LiveView.Socket.t()) ::
          {:noreply, Phoenix.LiveView.Socket.t()}
  def handle_select_response(%{"response_id" => response_id}, socket) do
    current_node = socket.assigns.preview_current_node
    connections = Flows.get_outgoing_connections(current_node.id)
    next_connection = Enum.find(connections, fn conn -> conn.source_pin == response_id end)

    if next_connection do
      history = [current_node.id | socket.assigns.preview_history]
      next_node = Flows.get_node_by_id!(current_node.flow_id, next_connection.target_node_id)

      socket =
        socket
        |> assign(preview_history: history)
        |> load_node(next_node)

      {:noreply, socket}
    else
      {:noreply, socket}
    end
  end

  @spec handle_continue(map(), Phoenix.LiveView.Socket.t()) ::
          {:noreply, Phoenix.LiveView.Socket.t()}
  def handle_continue(_params, socket) do
    current_node = socket.assigns.preview_current_node
    connections = Flows.get_outgoing_connections(current_node.id)
    next_connection = Enum.find(connections, fn conn -> conn.source_pin == "output" end)

    if next_connection do
      history = [current_node.id | socket.assigns.preview_history]
      next_node = Flows.get_node_by_id!(current_node.flow_id, next_connection.target_node_id)

      socket =
        socket
        |> assign(preview_history: history)
        |> load_node(next_node)

      {:noreply, socket}
    else
      {:noreply, socket}
    end
  end

  @spec handle_go_back(map(), Phoenix.LiveView.Socket.t()) ::
          {:noreply, Phoenix.LiveView.Socket.t()}
  def handle_go_back(_params, socket) do
    case socket.assigns.preview_history do
      [prev_node_id | rest] ->
        prev_node =
          Flows.get_node_by_id!(socket.assigns.preview_current_node.flow_id, prev_node_id)

        socket =
          socket
          |> assign(preview_history: rest)
          |> load_node(prev_node)

        {:noreply, socket}

      [] ->
        {:noreply, socket}
    end
  end

  @spec handle_close(Phoenix.LiveView.Socket.t()) :: {:noreply, Phoenix.LiveView.Socket.t()}
  def handle_close(socket) do
    {:noreply, assign(socket, preview_show: false, preview_current_node: nil)}
  end

  # ============================================================================
  # Serialization (socket assigns → Vue props)
  # ============================================================================

  @spec serialize_preview_state(Phoenix.LiveView.Socket.t()) :: map()
  def serialize_preview_state(socket) do
    node = socket.assigns[:preview_current_node]

    %{
      open: socket.assigns[:preview_show] || false,
      currentNode: serialize_node(node, socket.assigns),
      responses: serialize_responses(node),
      hasNext: socket.assigns[:preview_has_next] || false,
      hasHistory: (socket.assigns[:preview_history] || []) != []
    }
  end

  # ============================================================================
  # Private — node loading (ported from PreviewComponent)
  # ============================================================================

  defp load_node(socket, node) do
    if node.type == "dialogue" do
      load_dialogue_node(socket, node)
    else
      skip_to_next_dialogue(socket, node, MapSet.new(), 0)
    end
  end

  defp load_dialogue_node(socket, node) do
    speaker_name = resolve_speaker(socket.assigns, node.data["speaker_sheet_id"])
    responses = node.data["responses"] || []
    connections = Flows.get_outgoing_connections(node.id)
    has_next = responses == [] && has_output_connection?(connections)

    assign(socket,
      preview_current_node: node,
      preview_speaker: speaker_name,
      preview_responses: responses,
      preview_has_next: has_next
    )
  end

  defp skip_to_next_dialogue(socket, _node, _visited, depth)
       when depth >= @max_traversal_depth do
    assign_empty_node(socket)
  end

  defp skip_to_next_dialogue(socket, %{type: "jump"} = node, visited, depth) do
    if MapSet.member?(visited, node.id) do
      assign_empty_node(socket)
    else
      visited = MapSet.put(visited, node.id)
      follow_jump_target(socket, node, visited, depth)
    end
  end

  defp skip_to_next_dialogue(socket, node, visited, depth) do
    if MapSet.member?(visited, node.id) do
      assign_empty_node(socket)
    else
      visited = MapSet.put(visited, node.id)
      follow_first_connection(socket, node, visited, depth)
    end
  end

  defp follow_jump_target(socket, node, visited, depth) do
    target_hub_id = node.data["target_hub_id"]

    if target_hub_id && target_hub_id != "" do
      case Flows.get_hub_by_hub_id(node.flow_id, target_hub_id) do
        nil -> assign_empty_node(socket)
        hub -> skip_to_next_dialogue(socket, hub, visited, depth + 1)
      end
    else
      assign_empty_node(socket)
    end
  end

  defp follow_first_connection(socket, node, visited, depth) do
    connections = Flows.get_outgoing_connections(node.id)

    case List.first(connections) do
      nil ->
        assign_empty_node(socket)

      next_conn ->
        next_node = Flows.get_node_by_id!(node.flow_id, next_conn.target_node_id)
        load_or_skip(socket, next_node, visited, depth)
    end
  end

  defp load_or_skip(socket, %{type: "dialogue"} = node, _visited, _depth) do
    load_dialogue_node(socket, node)
  end

  defp load_or_skip(socket, node, visited, depth) do
    skip_to_next_dialogue(socket, node, visited, depth + 1)
  end

  defp assign_empty_node(socket) do
    assign(socket,
      preview_current_node: nil,
      preview_speaker: nil,
      preview_responses: [],
      preview_has_next: false
    )
  end

  defp has_output_connection?(connections) do
    Enum.any?(connections, fn conn -> conn.source_pin == "output" end)
  end

  # ============================================================================
  # Private — serialization helpers
  # ============================================================================

  defp serialize_node(nil, _assigns), do: nil

  defp serialize_node(node, assigns) do
    speaker = assigns[:preview_speaker]

    %{
      id: node.id,
      text: sanitize_and_interpolate(node.data["text"] || ""),
      speaker: speaker,
      speakerInitials: speaker_initials(speaker)
    }
  end

  defp serialize_responses(nil), do: []

  defp serialize_responses(node) do
    (node.data["responses"] || [])
    |> Enum.map(fn response ->
      %{
        id: response["id"],
        text: sanitize_and_interpolate(response["text"] || ""),
        hasCondition: response["condition"] != nil && response["condition"] != "",
        conditionLabel: response["condition"]
      }
    end)
  end

  # ============================================================================
  # Private — speaker resolution
  # ============================================================================

  defp resolve_speaker(assigns, speaker_sheet_id)
       when is_integer(speaker_sheet_id) or is_binary(speaker_sheet_id) do
    sheet_id = parse_sheet_id(speaker_sheet_id)
    if sheet_id, do: lookup_speaker_name(assigns, sheet_id)
  end

  defp resolve_speaker(_assigns, _), do: nil

  defp parse_sheet_id(id) when is_integer(id), do: id

  defp parse_sheet_id(id) when is_binary(id) do
    case Integer.parse(id) do
      {parsed, ""} -> parsed
      _ -> nil
    end
  end

  defp lookup_speaker_name(assigns, sheet_id) do
    sheets_map = Map.get(assigns, :sheets_map, %{})
    sheet_info = Map.get(sheets_map, to_string(sheet_id))

    if sheet_info do
      sheet_info.name
    else
      case Sheets.get_sheet(assigns.project.id, sheet_id) do
        nil -> nil
        sheet -> sheet.name
      end
    end
  end

  # ============================================================================
  # Private — text helpers
  # ============================================================================

  defp speaker_initials(nil), do: "?"

  defp speaker_initials(name) when is_binary(name) do
    name
    |> String.split()
    |> Enum.take(2)
    |> Enum.map_join("", &String.first/1)
    |> String.upcase()
  end

  defp sanitize_and_interpolate(""), do: ""

  defp sanitize_and_interpolate(text) when is_binary(text) do
    text
    |> HtmlSanitizer.sanitize_html()
    |> interpolate_variables()
  end

  defp interpolate_variables(text) when is_binary(text) do
    Regex.replace(~r/\{(\w+)\}/, text, fn _, var_name ->
      "<span class=\"text-xs px-1.5 py-0.5 rounded bg-muted text-muted-foreground font-mono\">[#{var_name}]</span>"
    end)
  end
end
