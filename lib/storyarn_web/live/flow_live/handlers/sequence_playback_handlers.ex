defmodule StoryarnWeb.FlowLive.Handlers.SequencePlaybackHandlers do
  @moduledoc """
  Runs an ephemeral Player session inside the Sequence workspace.

  Only playback assigns change. The editor graph, selected composition and
  debugger state remain owned by their existing handlers.
  """

  import Phoenix.Component, only: [assign: 2]

  alias Storyarn.Flows
  alias StoryarnWeb.FlowLive.Helpers.FormHelpers
  alias StoryarnWeb.FlowLive.Helpers.SequencePresentation
  alias StoryarnWeb.FlowLive.Player.Slide
  alias StoryarnWeb.PrivateMedia

  def handle_event(%{"action" => "stop"}, socket) do
    {:noreply, assign(socket, sequence_playback_session: nil, sequence_playback: nil)}
  end

  def handle_event(%{"action" => "start", "id" => id}, socket) do
    with node_id when is_integer(node_id) <- parse_id(id),
         %{type: "dialogue"} <- Flows.get_node(socket.assigns.flow.id, node_id) do
      variables = Flows.build_runtime_variables(socket.assigns.project.id)

      case Flows.start_player_session(socket.assigns.flow, variables, start_node_id: node_id) do
        {:ok, session} -> present(socket, session)
        {:error, reason} -> fail_start(socket, reason)
      end
    else
      _ -> {:noreply, socket}
    end
  end

  def handle_event(%{"action" => action} = params, socket) when action in ~w(continue choose back restart) do
    case socket.assigns[:sequence_playback_session] do
      nil -> {:noreply, socket}
      session -> execute(action, params, session, socket)
    end
  end

  def handle_event(_params, socket), do: {:noreply, socket}

  defp execute(action, params, session, socket) do
    result =
      case action do
        "continue" -> Flows.continue_player_session(session)
        "choose" -> Flows.choose_player_response(session, params["response_id"])
        "back" -> previous_intervention(session, position(session))
        "restart" -> Flows.restart_player_session(session)
      end

    case result do
      {:ok, ^session} when action != "restart" -> {:noreply, socket}
      {:ok, updated} -> present(socket, updated)
      {:error, reason, updated} -> present_error(socket, updated, reason)
    end
  end

  defp previous_intervention(session, current_position) do
    case Flows.go_back_player_session(session) do
      {:ok, previous} ->
        if position(previous) == current_position,
          do: previous_intervention(previous, current_position),
          else: {:ok, previous}

      error ->
        error
    end
  end

  defp position(session), do: {session.flow.id, session.state.current_node_id}

  defp present(socket, session) do
    {:noreply,
     assign(socket,
       sequence_playback_session: session,
       sequence_playback: projection(session, socket.assigns)
     )}
  end

  defp present_error(socket, session, reason) do
    projection =
      if session == socket.assigns[:sequence_playback_session],
        do: socket.assigns.sequence_playback,
        else: projection(session, socket.assigns)

    {:noreply,
     assign(socket,
       sequence_playback_session: session,
       sequence_playback: %{projection | error: error_code(reason)}
     )}
  end

  defp fail_start(socket, reason) do
    {:noreply,
     assign(socket,
       sequence_playback_session: nil,
       sequence_playback: %{
         slide: %{type: :empty, responses: []},
         visualLayers: [],
         audioTracks: [],
         voice: nil,
         canGoBack: false,
         showContinue: false,
         isFinished: false,
         error: error_code(reason)
       }
     )}
  end

  defp projection(session, assigns) do
    node = session.nodes[session.state.current_node_id]
    speakers = FormHelpers.player_speakers_map(assigns[:all_sheets] || [])
    slide = Slide.build(node, session.state, speakers, assigns.project.id)
    composition = Flows.compose_player_sequences(session.state, session.nodes)
    finished? = session.state.status == :finished

    %{
      slide: Map.put_new(slide, :responses, []),
      visualLayers: SequencePresentation.visual_layers(composition),
      audioTracks: audio_tracks(composition),
      voice: voice(node, assigns.project.id),
      canGoBack: Flows.player_session_can_go_back?(session),
      showContinue: not finished? and session.state.status != :waiting_input,
      isFinished: finished?,
      error: nil
    }
  end

  defp audio_tracks(composition) do
    Enum.flat_map(composition.audio_tracks, fn composed ->
      track = composed.item

      case PrivateMedia.asset_url(track.asset) do
        nil ->
          []

        url ->
          [
            %{
              id: composed.continuity_key,
              sequenceId: composed.sequence_id,
              kind: track.kind,
              position: track.position,
              url: url,
              volume: numeric(track.volume),
              depth: composed.depth
            }
          ]
      end
    end)
  end

  defp voice(%{type: "dialogue", data: data}, project_id) do
    with asset_id when is_integer(asset_id) <- parse_id(data["audio_asset_id"]),
         %{} = asset <- Flows.get_player_audio_asset(project_id, asset_id),
         url when is_binary(url) <- PrivateMedia.asset_url(asset) do
      %{url: url, key: Ecto.UUID.generate()}
    else
      _ -> nil
    end
  end

  defp voice(_node, _project_id), do: nil

  defp numeric(%Decimal{} = value), do: Decimal.to_float(value)
  defp numeric(value) when is_number(value), do: value
  defp numeric(_value), do: 1.0

  defp parse_id(value) when is_integer(value) and value > 0, do: value

  defp parse_id(value) when is_binary(value) do
    case Integer.parse(value) do
      {id, ""} when id > 0 -> id
      _ -> nil
    end
  end

  defp parse_id(_value), do: nil

  defp error_code({reason, _id}), do: Atom.to_string(reason)
  defp error_code(reason), do: Atom.to_string(reason)
end
