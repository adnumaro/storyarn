defmodule StoryarnWeb.FlowLive.Handlers.PreviewHandlers do
  @moduledoc """
  Handles dialogue preview navigation.

  Ports the logic from the old PreviewComponent LiveComponent into
  socket-based state that drives the FlowPreview Vue component.
  """

  import Phoenix.Component, only: [assign: 2]

  alias Phoenix.LiveView.Socket
  alias Storyarn.Flows
  alias Storyarn.Platform.Shared.HtmlSanitizer

  # ============================================================================
  # Public handlers
  # ============================================================================

  @spec handle_start_preview(map(), Socket.t()) ::
          {:noreply, Socket.t()}
  def handle_start_preview(%{"id" => node_id}, socket) do
    case Flows.start_dialogue_preview(socket.assigns.flow.id, node_id) do
      :not_found ->
        {:noreply, socket}

      {:ok, preview} ->
        socket =
          socket
          |> assign(preview_show: true, preview_history: [])
          |> assign_preview(preview)

        {:noreply, socket}

      :empty ->
        {:noreply,
         socket
         |> assign(preview_show: true, preview_history: [])
         |> assign_empty_node()}
    end
  end

  @spec handle_select_response(map(), Socket.t()) ::
          {:noreply, Socket.t()}
  def handle_select_response(%{"response_id" => response_id}, socket) do
    current_node = socket.assigns.preview_current_node
    follow_preview(socket, current_node, response_id)
  end

  @spec handle_continue(map(), Socket.t()) ::
          {:noreply, Socket.t()}
  def handle_continue(_params, socket) do
    current_node = socket.assigns.preview_current_node
    follow_preview(socket, current_node, "output")
  end

  @spec handle_go_back(map(), Socket.t()) ::
          {:noreply, Socket.t()}
  def handle_go_back(_params, socket) do
    case socket.assigns.preview_history do
      [prev_node_id | rest] ->
        flow_id = socket.assigns.flow.id

        case Flows.start_dialogue_preview(flow_id, prev_node_id) do
          {:ok, preview} ->
            {:noreply,
             socket
             |> assign(preview_history: rest)
             |> assign_preview(preview)}

          :empty ->
            {:noreply,
             socket
             |> assign(preview_history: rest)
             |> assign_empty_node()}

          :not_found ->
            {:noreply, socket}
        end

      [] ->
        {:noreply, socket}
    end
  end

  @spec handle_close(Socket.t()) :: {:noreply, Socket.t()}
  def handle_close(socket) do
    {:noreply, assign(socket, preview_show: false, preview_current_node: nil)}
  end

  # ============================================================================
  # Serialization (socket assigns → Vue props)
  # ============================================================================

  @spec serialize_preview_state(Socket.t() | map()) :: map()
  def serialize_preview_state(%Socket{assigns: assigns}), do: serialize_preview_state(assigns)

  def serialize_preview_state(assigns) when is_map(assigns) do
    # Guard: during disconnected static render, assigns may not be populated yet
    if is_map_key(assigns, :preview_current_node) do
      node = assigns.preview_current_node

      %{
        open: assigns[:preview_show] || false,
        currentNode: serialize_node(node, assigns),
        responses: serialize_responses(node),
        hasNext: assigns[:preview_has_next] || false,
        hasHistory: (assigns[:preview_history] || []) != []
      }
    else
      return_default_state()
    end
  end

  defp return_default_state do
    %{open: false, currentNode: nil, responses: [], hasNext: false, hasHistory: false}
  end

  # ============================================================================
  # Private — adapter state
  # ============================================================================

  defp assign_preview(socket, %{node: node, has_next?: has_next?}) do
    speaker_name = resolve_speaker(socket.assigns, node.data["speaker_sheet_id"])
    responses = node.data["responses"] || []

    assign(socket,
      preview_current_node: node,
      preview_speaker: speaker_name,
      preview_responses: responses,
      preview_has_next: has_next?
    )
  end

  defp follow_preview(socket, nil, _source_pin), do: {:noreply, socket}

  defp follow_preview(socket, current_node, source_pin) do
    case Flows.follow_dialogue_preview(socket.assigns.flow.id, current_node.id, source_pin) do
      result when result in [:no_transition, :not_found] ->
        {:noreply, socket}

      {:ok, preview} ->
        {:noreply,
         socket
         |> remember_preview_node(current_node.id)
         |> assign_preview(preview)}

      :empty ->
        {:noreply,
         socket
         |> remember_preview_node(current_node.id)
         |> assign_empty_node()}
    end
  end

  defp remember_preview_node(socket, node_id) do
    assign(socket, preview_history: [node_id | socket.assigns.preview_history])
  end

  defp assign_empty_node(socket) do
    assign(socket,
      preview_current_node: nil,
      preview_speaker: nil,
      preview_responses: [],
      preview_has_next: false
    )
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
    Enum.map(node.data["responses"] || [], fn response ->
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

  defp resolve_speaker(assigns, speaker_sheet_id) when is_integer(speaker_sheet_id) or is_binary(speaker_sheet_id) do
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
    Flows.get_preview_speaker_name(assigns.project.id, sheet_id)
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
    |> Flows.map_player_rich_text_references(&render_preview_reference/1)
  end

  defp render_preview_reference(reference) do
    "<span class=\"text-xs px-1.5 py-0.5 rounded bg-muted text-muted-foreground font-mono\">[#{reference}]</span>"
  end
end
