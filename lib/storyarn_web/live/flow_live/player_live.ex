defmodule StoryarnWeb.FlowLive.PlayerLive do
  @moduledoc """
  Full-screen cinematic story player for flows.

  Reuses the player runtime exposed by the `Storyarn.Flows` facade, which
  auto-advances through non-interactive nodes (conditions, instructions,
  hubs, etc.).
  """

  use StoryarnWeb, :live_view

  import StoryarnWeb.Layouts, only: [flash_group: 1]

  alias Storyarn.Flows
  alias StoryarnWeb.FlowLive.Helpers.FormHelpers
  alias StoryarnWeb.FlowLive.Helpers.SequencePresentation
  alias StoryarnWeb.FlowLive.Helpers.VariableHelpers
  alias StoryarnWeb.FlowLive.Player.Slide
  alias StoryarnWeb.PrivateMedia

  # ===========================================================================
  # Render
  # ===========================================================================

  @impl true
  def render(assigns) do
    ~H"""
    <div id="story-player" class="player-layout">
      <.vue
        v-component="live/flow/player/FlowPlayer"
        v-socket={@socket}
        id="flow-player"
        slide={serialize_slide(@slide)}
        player-mode={to_string(@player_mode)}
        can-go-back={@can_go_back}
        show-continue={show_continue?(@slide)}
        is-finished={@engine_state.status == :finished}
        visual-layers={player_visual_layers(assigns)}
        audio-tracks={player_audio_tracks(assigns)}
        editor-url={editor_url(assigns)}
        responses={serialize_responses(@slide)}
      />

      <.flash_group flash={@flash} socket={@socket} />
    </div>
    """
  end

  # ===========================================================================
  # Mount
  # ===========================================================================

  @impl true
  def mount(%{"id" => flow_id} = params, _session, %{assigns: %{project: project}} = socket) do
    session_id = params["player_session"] || Ecto.UUID.generate()

    socket =
      socket
      |> assign(:player_session_id, session_id)
      |> assign(:player_tab_id, player_tab_id(socket, session_id))

    mount_player(socket, project, flow_id)
  end

  defp mount_player(socket, project, flow_id) do
    case Flows.get_flow(project.id, flow_id) do
      nil ->
        {:ok,
         socket
         |> put_flash(:error, dgettext("flows", "Flow not found."))
         |> redirect(to: ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/flows")}

      flow ->
        mount_flow_player(socket, project, flow)
    end
  end

  defp mount_flow_player(socket, project, flow) do
    speakers = Flows.load_player_speakers(project.id)
    speakers_map = FormHelpers.player_speakers_map(speakers)
    variables = VariableHelpers.build_variables(project.id)

    case Flows.start_player_session(flow, variables) do
      {:error, reason} ->
        {:ok,
         socket
         |> put_flash(:error, player_start_error(reason))
         |> redirect(to: ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/flows/#{flow.id}")}

      {:ok, player_session} ->
        socket =
          maybe_restore_player_session(socket, project) ||
            socket
            |> assign(:speakers_map, speakers_map)
            |> assign(:project, project)
            |> assign(:workspace, project.workspace)
            |> assign(:player_mode, :player)
            |> assign_player_session(player_session)

        if connected?(socket) do
          Flows.record_player_started(socket.assigns.current_scope, flow)
        end

        {:ok, socket, layout: false}
    end
  end

  defp maybe_restore_player_session(socket, project) do
    # Only restore on connected mount — disconnected mount would consume the
    # session from the Agent, leaving nothing for the connected mount.
    if connected?(socket), do: do_restore_player_session(socket, project)
  end

  defp do_restore_player_session(socket, project) do
    user_id = socket.assigns.current_scope.user.id
    session_id = socket.assigns.player_session_id

    tab_id = socket.assigns.player_tab_id

    case Flows.debug_session_take({:player, user_id, project.id, session_id, tab_id}) do
      nil ->
        nil

      restored ->
        if Map.has_key?(restored, :player_mode) do
          speakers_map = restored[:speakers_map] || restored[:sheets_map] || %{}
          player_session = restore_player_session(restored)

          socket
          |> assign(:speakers_map, speakers_map)
          |> assign(:project, project)
          |> assign(:workspace, project.workspace)
          |> assign(:player_mode, restored.player_mode)
          |> assign_player_session(player_session)
        end
    end
  end

  defp restore_player_session(%{player_session: player_session}), do: player_session

  defp restore_player_session(restored) do
    Flows.restore_player_session(
      restored.flow,
      restored.engine_state,
      restored.nodes,
      restored.connections,
      restored[:current_scene_id]
    )
  end

  # ===========================================================================
  # Events
  # ===========================================================================

  @impl true
  def handle_event("continue", _params, socket) do
    socket.assigns.player_session
    |> Flows.continue_player_session()
    |> handle_player_result(socket)
  end

  def handle_event("choose_response", %{"id" => response_id}, socket) do
    socket.assigns.player_session
    |> Flows.choose_player_response(response_id)
    |> handle_player_result(socket)
  end

  def handle_event("choose_response_by_number", %{"number" => number}, socket) do
    responses = socket.assigns.slide[:responses] || []

    case Flows.player_response_id_by_number(responses, socket.assigns.player_mode, number) do
      {:ok, response_id} -> handle_event("choose_response", %{"id" => response_id}, socket)
      {:error, :response_not_found} -> {:noreply, socket}
    end
  end

  def handle_event("go_back", _params, socket) do
    socket.assigns.player_session
    |> Flows.go_back_player_session()
    |> handle_player_result(socket)
  end

  def handle_event("toggle_mode", _params, socket) do
    new_mode = if socket.assigns.player_mode == :player, do: :analysis, else: :player
    {:noreply, assign(socket, :player_mode, new_mode)}
  end

  def handle_event("restart", _params, socket) do
    socket.assigns.player_session
    |> Flows.restart_player_session()
    |> handle_player_result(socket)
  end

  def handle_event("exit_player", _params, socket) do
    %{workspace: ws, project: proj, flow: flow} = socket.assigns

    {:noreply, push_navigate(socket, to: ~p"/workspaces/#{ws.slug}/projects/#{proj.slug}/flows/#{flow.id}")}
  end

  defp store_and_navigate_player(socket, player_session) do
    %{workspace: ws, project: proj, speakers_map: speakers_map, player_mode: mode} = socket.assigns
    user_id = socket.assigns.current_scope.user.id
    session_id = socket.assigns.player_session_id
    tab_id = socket.assigns.player_tab_id

    Flows.debug_session_store({:player, user_id, proj.id, session_id, tab_id}, %{
      player_session: player_session,
      speakers_map: speakers_map,
      player_mode: mode
    })

    {:noreply,
     push_navigate(socket,
       to:
         ~p"/workspaces/#{ws.slug}/projects/#{proj.slug}/flows/#{player_session.flow.id}/play?player_session=#{session_id}"
     )}
  end

  # ===========================================================================
  # Private helpers
  # ===========================================================================

  defp player_tab_id(socket, fallback) do
    if connected?(socket) do
      socket
      |> get_connect_params()
      |> then(&Map.get(&1 || %{}, "player_tab_id", fallback))
    end
  end

  defp handle_player_result({:ok, player_session}, socket) do
    if player_session.flow.id == socket.assigns.flow.id do
      {:noreply, assign_player_session(socket, player_session)}
    else
      store_and_navigate_player(socket, player_session)
    end
  end

  defp handle_player_result({:error, :no_history, _player_session}, socket) do
    {:noreply, socket}
  end

  defp handle_player_result({:error, :invalid_response, _player_session}, socket) do
    {:noreply, put_flash(socket, :error, dgettext("flows", "Could not select that response."))}
  end

  defp handle_player_result({:error, {:target_entry_not_found, _flow_id}, _player_session}, socket) do
    {:noreply, put_flash(socket, :error, dgettext("flows", "Target flow has no entry node."))}
  end

  defp handle_player_result({:error, _reason, _player_session}, socket) do
    {:noreply, put_flash(socket, :error, dgettext("flows", "Error advancing through flow."))}
  end

  defp assign_player_session(socket, player_session) do
    state = player_session.state
    node = Map.get(player_session.nodes, state.current_node_id)
    slide = Slide.build(node, state, socket.assigns.speakers_map, socket.assigns.project.id)

    socket
    |> assign(:player_session, player_session)
    |> assign(:engine_state, state)
    |> assign(:nodes, player_session.nodes)
    |> assign(:connections, player_session.connections)
    |> assign(:flow, player_session.flow)
    |> assign(:slide, slide)
    |> assign(:can_go_back, Flows.player_session_can_go_back?(player_session))
    |> assign(:current_scene_id, player_session.scene_id)
  end

  defp player_start_error(:entry_not_found), do: dgettext("flows", "No entry node found in this flow.")

  defp player_start_error({:target_entry_not_found, _flow_id}), do: dgettext("flows", "Target flow has no entry node.")

  defp player_start_error(_reason), do: dgettext("flows", "Error advancing through flow.")

  defp show_continue?(%{type: :dialogue, responses: []}), do: true
  defp show_continue?(%{type: :dialogue}), do: false
  defp show_continue?(_), do: false

  # ===========================================================================
  # Vue serialization
  # ===========================================================================

  defp serialize_slide(%{type: :dialogue} = slide) do
    Map.merge(slide_base(slide), dialogue_slide_props(slide))
  end

  defp serialize_slide(%{type: :outcome} = slide) do
    Map.merge(slide_base(slide), outcome_slide_props(slide))
  end

  defp serialize_slide(slide), do: slide_base(slide)

  defp slide_base(slide), do: %{type: to_string(slide.type)}

  defp dialogue_slide_props(slide) do
    %{
      speaker_name: slide[:speaker_name],
      speaker_initials: slide[:speaker_initials] || "?",
      speaker_avatar_url: slide[:speaker_avatar_url],
      speaker_color: slide[:speaker_color],
      text: slide[:text] || "",
      stage_directions: slide[:stage_directions] || ""
    }
  end

  defp outcome_slide_props(slide) do
    %{
      label: slide[:label] || dgettext("flows", "The End"),
      outcome_color: slide[:outcome_color],
      outcome_tags: slide[:outcome_tags] || [],
      step_count: slide[:step_count] || 0,
      choices_made: slide[:choices_made] || 0,
      variables_changed: slide[:variables_changed] || 0
    }
  end

  defp serialize_responses(slide) do
    Enum.map(slide[:responses] || [], fn resp ->
      %{
        id: resp.id,
        text: resp.text,
        valid: resp.valid,
        number: resp.number,
        has_condition: resp.has_condition
      }
    end)
  end

  defp player_visual_layers(%{engine_state: state, nodes: nodes}) do
    composition = Flows.compose_player_sequences(state, nodes)
    SequencePresentation.visual_layers(composition, state.current_node_id)
  end

  defp player_visual_layers(_assigns), do: []

  defp player_audio_tracks(%{engine_state: state, nodes: nodes}) do
    state
    |> Flows.compose_player_sequences(nodes)
    |> Map.fetch!(:audio_tracks)
    |> Enum.flat_map(&serialize_audio_track/1)
  end

  defp player_audio_tracks(_assigns), do: []

  defp serialize_audio_track(%{item: track, sequence_id: sequence_id, depth: depth}) do
    url = media_url(track)
    asset = Map.get(track, :asset)

    if is_binary(url) and url != "" do
      [
        %{
          id: track.id,
          sequence_id: sequence_id,
          kind: track.kind,
          position: track.position || 0,
          url: url,
          volume: serialize_volume(Map.get(track, :volume)),
          content_type: Map.get(track, :content_type) || (asset && Map.get(asset, :content_type)),
          filename: Map.get(track, :filename) || (asset && Map.get(asset, :filename)),
          depth: depth
        }
      ]
    else
      []
    end
  end

  defp media_url(item) do
    Map.get(item, :url) || PrivateMedia.asset_url(Map.get(item, :asset))
  end

  defp serialize_volume(nil), do: 1.0
  defp serialize_volume(%Decimal{} = volume), do: Decimal.to_float(volume)
  defp serialize_volume(volume) when is_number(volume), do: volume

  defp editor_url(assigns) do
    ~p"/workspaces/#{assigns.workspace.slug}/projects/#{assigns.project.slug}/flows/#{assigns.flow.id}"
  end
end
