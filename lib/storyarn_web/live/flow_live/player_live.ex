defmodule StoryarnWeb.FlowLive.PlayerLive do
  @moduledoc """
  Full-screen cinematic story player for flows.

  Reuses the Flows evaluator state machine with a
  `PlayerEngine.step_until_interactive/3` wrapper that auto-advances
  through non-interactive nodes (conditions, instructions, hubs, etc.).
  """

  use StoryarnWeb, :live_view

  import StoryarnWeb.Layouts, only: [flash_group: 1]
  import StoryarnWeb.FlowLive.Player.Components.PlayerSlide
  import StoryarnWeb.FlowLive.Player.Components.PlayerChoices
  import StoryarnWeb.FlowLive.Player.Components.PlayerToolbar
  import StoryarnWeb.FlowLive.Player.Components.PlayerOutcome

  alias Storyarn.Flows
  alias Storyarn.Flows.DebugSessionStore
  alias Storyarn.Projects
  alias Storyarn.Scenes
  alias Storyarn.Sheets
  alias StoryarnWeb.FlowLive.Handlers.DebugExecutionHandlers
  alias StoryarnWeb.FlowLive.Helpers.FormHelpers
  alias StoryarnWeb.FlowLive.Helpers.VariableHelpers
  alias StoryarnWeb.FlowLive.Player.{PlayerEngine, Slide}
  alias StoryarnWeb.SceneLive.Helpers.Serializer, as: MapSerializer

  # ===========================================================================
  # Render
  # ===========================================================================

  @impl true
  def render(assigns) do
    ~H"""
    <div id="story-player" class="player-layout" phx-hook="StoryPlayer">
      <div class="player-main relative">
        <%!-- Scene backdrop (dimmed map background) --%>
        <div :if={@scene_backdrop} class="scene-backdrop scene-backdrop-transition">
          <img
            src={MapSerializer.background_url(@scene_backdrop)}
            alt=""
            class="scene-backdrop-img"
            draggable="false"
          />
        </div>

        <%!-- Flow content (on top) --%>
        <div class="relative z-10 flex flex-col items-center justify-center flex-1 w-full">
          <%= if @slide.type == :outcome do %>
            <.player_outcome
              slide={@slide}
              workspace={@workspace}
              project={@project}
              flow={@flow}
            />
          <% else %>
            <.player_slide slide={@slide} />
            <.player_choices responses={@slide[:responses] || []} player_mode={@player_mode} />
          <% end %>
        </div>
      </div>

      <.player_toolbar
        can_go_back={@can_go_back}
        show_continue={show_continue?(@slide)}
        player_mode={@player_mode}
        is_finished={@engine_state.status == :finished}
        workspace={@workspace}
        project={@project}
        flow={@flow}
      />

      <.flash_group flash={@flash} />
    </div>
    """
  end

  # ===========================================================================
  # Mount
  # ===========================================================================

  @impl true
  def mount(
        %{"workspace_slug" => workspace_slug, "project_slug" => project_slug, "id" => flow_id},
        _session,
        socket
      ) do
    case Projects.get_project_by_slugs(socket.assigns.current_scope, workspace_slug, project_slug) do
      {:ok, project, _membership} ->
        mount_player(socket, project, flow_id)

      {:error, _reason} ->
        {:ok,
         socket
         |> put_flash(:error, dgettext("flows", "You don't have access to this project."))
         |> redirect(to: ~p"/workspaces")}
    end
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
    nodes_map = DebugExecutionHandlers.build_nodes_map(flow.id)
    connections = DebugExecutionHandlers.build_connections(flow.id)
    all_sheets = Sheets.list_all_sheets(project.id)
    sheets_map = FormHelpers.sheets_map(all_sheets)
    variables = VariableHelpers.build_variables(project.id)

    case init_and_step(nodes_map, connections, variables, flow.id) do
      {:error, reason} ->
        {:ok,
         socket
         |> put_flash(:error, reason)
         |> redirect(
           to: ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/flows/#{flow.id}"
         )}

      {:ok, engine_state} ->
        node = Map.get(nodes_map, engine_state.current_node_id)
        slide = Slide.build(node, engine_state, sheets_map, project.id)

        scene_id = Flows.resolve_scene_id(flow)
        scene_backdrop = if scene_id, do: Scenes.get_scene_backdrop(scene_id)

        socket =
          maybe_restore_player_session(socket, project) ||
            socket
            |> assign(:engine_state, engine_state)
            |> assign(:nodes, nodes_map)
            |> assign(:connections, connections)
            |> assign(:sheets_map, sheets_map)
            |> assign(:flow, flow)
            |> assign(:project, project)
            |> assign(:workspace, project.workspace)
            |> assign(:slide, slide)
            |> assign(:player_mode, :player)
            |> assign(:can_go_back, engine_state.snapshots != [])
            |> assign(:scene_backdrop, scene_backdrop)
            |> assign(:current_scene_id, scene_id)

        {:ok, socket, layout: false}
    end
  end

  defp init_and_step(nodes_map, connections, variables, flow_id) do
    case DebugExecutionHandlers.find_entry_node(nodes_map) do
      nil ->
        {:error, dgettext("flows", "No entry node found in this flow.")}

      entry_node_id ->
        state = Flows.evaluator_init(variables, entry_node_id)
        state = %{state | current_flow_id: flow_id}

        case PlayerEngine.step_until_interactive(state, nodes_map, connections) do
          {:error, _state, _skipped} ->
            {:error, dgettext("flows", "Error advancing through flow.")}

          {_status, new_state, _skipped} ->
            {:ok, new_state}
        end
    end
  end

  defp maybe_restore_player_session(socket, project) do
    user_id = socket.assigns.current_scope.user.id

    case DebugSessionStore.take({user_id, project.id}) do
      nil ->
        nil

      restored ->
        if Map.has_key?(restored, :player_mode) do
          node = Map.get(restored.nodes, restored.engine_state.current_node_id)
          slide = Slide.build(node, restored.engine_state, restored.sheets_map, project.id)

          socket
          |> assign(:engine_state, restored.engine_state)
          |> assign(:nodes, restored.nodes)
          |> assign(:connections, restored.connections)
          |> assign(:sheets_map, restored.sheets_map)
          |> assign(:flow, restored.flow)
          |> assign(:project, project)
          |> assign(:workspace, project.workspace)
          |> assign(:slide, slide)
          |> assign(:player_mode, restored.player_mode)
          |> assign(:can_go_back, restored.engine_state.snapshots != [])
          |> assign(:scene_backdrop, restored[:scene_backdrop])
          |> assign(:current_scene_id, restored[:current_scene_id])
        else
          nil
        end
    end
  end

  # ===========================================================================
  # Events
  # ===========================================================================

  @impl true
  def handle_event("continue", _params, socket) do
    %{engine_state: state, nodes: nodes, connections: connections} = socket.assigns

    if state.status in [:finished, :waiting_input] and state.pending_choices != nil do
      {:noreply, socket}
    else
      case PlayerEngine.step_until_interactive(state, nodes, connections) do
        {:flow_jump, new_state, target_flow_id, _skipped} ->
          handle_flow_jump(socket, new_state, target_flow_id)

        {:flow_return, new_state, _skipped} ->
          handle_flow_return(socket, new_state)

        {_status, new_state, _skipped} ->
          {:noreply, update_slide(socket, new_state)}
      end
    end
  end

  def handle_event("choose_response", %{"id" => response_id}, socket) do
    %{engine_state: state, connections: connections, nodes: nodes} = socket.assigns

    case Flows.evaluator_choose_response(state, response_id, connections) do
      {:ok, new_state} ->
        case PlayerEngine.step_until_interactive(new_state, nodes, connections) do
          {:flow_jump, stepped_state, target_flow_id, _skipped} ->
            handle_flow_jump(socket, stepped_state, target_flow_id)

          {:flow_return, stepped_state, _skipped} ->
            handle_flow_return(socket, stepped_state)

          {_status, stepped_state, _skipped} ->
            {:noreply, update_slide(socket, stepped_state)}
        end

      {:error, _state, _reason} ->
        {:noreply,
         put_flash(socket, :error, dgettext("flows", "Could not select that response."))}
    end
  end

  def handle_event("choose_response_by_number", %{"number" => number}, socket) do
    responses = socket.assigns.slide[:responses] || []

    visible =
      if socket.assigns.player_mode == :player do
        Enum.filter(responses, & &1.valid)
      else
        responses
      end

    case Enum.at(visible, number - 1) do
      nil -> {:noreply, socket}
      resp -> handle_event("choose_response", %{"id" => resp.id}, socket)
    end
  end

  def handle_event("go_back", _params, socket) do
    case Flows.evaluator_step_back(socket.assigns.engine_state) do
      {:ok, new_state} ->
        {:noreply, update_slide(socket, new_state)}

      {:error, :no_history} ->
        {:noreply, socket}
    end
  end

  def handle_event("toggle_mode", _params, socket) do
    new_mode = if socket.assigns.player_mode == :player, do: :analysis, else: :player
    {:noreply, assign(socket, :player_mode, new_mode)}
  end

  def handle_event("restart", _params, socket) do
    %{engine_state: state, nodes: nodes, connections: connections} = socket.assigns

    new_state = Flows.evaluator_reset(state)

    case PlayerEngine.step_until_interactive(new_state, nodes, connections) do
      {:flow_jump, stepped_state, target_flow_id, _skipped} ->
        handle_flow_jump(socket, stepped_state, target_flow_id)

      {:flow_return, stepped_state, _skipped} ->
        handle_flow_return(socket, stepped_state)

      {_status, stepped_state, _skipped} ->
        {:noreply, update_slide(socket, stepped_state)}
    end
  end

  def handle_event("exit_player", _params, socket) do
    %{workspace: ws, project: proj, flow: flow} = socket.assigns

    {:noreply,
     push_navigate(socket, to: ~p"/workspaces/#{ws.slug}/projects/#{proj.slug}/flows/#{flow.id}")}
  end

  # ===========================================================================
  # Cross-flow navigation
  # ===========================================================================

  defp handle_flow_jump(socket, state, target_flow_id) do
    %{nodes: nodes, connections: connections, flow: flow} = socket.assigns

    state =
      Flows.evaluator_push_flow_context(
        state,
        state.current_node_id,
        nodes,
        connections,
        flow.name
      )

    target_nodes = DebugExecutionHandlers.build_nodes_map(target_flow_id)
    target_connections = DebugExecutionHandlers.build_connections(target_flow_id)

    # Resolve scene for target flow (pass current as caller context)
    target_flow = Flows.get_flow_brief(socket.assigns.project.id, target_flow_id)

    new_scene_id =
      if target_flow do
        Flows.resolve_scene_id(target_flow,
          caller_scene_id: socket.assigns.current_scene_id
        )
      end

    socket = maybe_update_scene_backdrop(socket, new_scene_id)

    case DebugExecutionHandlers.find_entry_node(target_nodes) do
      nil ->
        {:noreply, put_flash(socket, :error, dgettext("flows", "Target flow has no entry node."))}

      entry_id ->
        new_state = %{
          state
          | current_node_id: entry_id,
            current_flow_id: target_flow_id,
            status: :paused
        }

        case PlayerEngine.step_until_interactive(new_state, target_nodes, target_connections) do
          {:flow_jump, stepped_state, next_flow_id, _skipped} ->
            handle_flow_jump(
              assign(socket, :nodes, target_nodes) |> assign(:connections, target_connections),
              stepped_state,
              next_flow_id
            )

          {:flow_return, stepped_state, _skipped} ->
            handle_flow_return(
              assign(socket, :nodes, target_nodes) |> assign(:connections, target_connections),
              stepped_state
            )

          {_status, stepped_state, _skipped} ->
            store_and_navigate_player(
              socket,
              stepped_state,
              target_nodes,
              target_connections,
              target_flow_id
            )
        end
    end
  end

  defp handle_flow_return(socket, state) do
    case Flows.evaluator_pop_flow_context(state) do
      {:ok, frame, new_state} ->
        parent_nodes = frame.nodes
        parent_connections = frame.connections
        parent_flow_id = frame.flow_id

        # Restore parent flow's scene
        parent_flow = Flows.get_flow_brief(socket.assigns.project.id, parent_flow_id)
        parent_scene_id = if parent_flow, do: Flows.resolve_scene_id(parent_flow)
        socket = maybe_update_scene_backdrop(socket, parent_scene_id)

        # Find the connection after the return node to advance
        return_node_id = frame.return_node_id

        conn =
          Enum.find(parent_connections, fn c ->
            c.source_node_id == return_node_id and c.source_pin in ["default", "output"]
          end)

        new_state =
          if conn do
            %{
              new_state
              | current_node_id: conn.target_node_id,
                current_flow_id: parent_flow_id,
                status: :paused
            }
          else
            %{new_state | status: :finished, current_flow_id: parent_flow_id}
          end

        case PlayerEngine.step_until_interactive(new_state, parent_nodes, parent_connections) do
          {:flow_jump, stepped_state, next_flow_id, _skipped} ->
            handle_flow_jump(
              assign(socket, :nodes, parent_nodes) |> assign(:connections, parent_connections),
              stepped_state,
              next_flow_id
            )

          {:flow_return, stepped_state, _skipped} ->
            handle_flow_return(
              assign(socket, :nodes, parent_nodes) |> assign(:connections, parent_connections),
              stepped_state
            )

          {_status, stepped_state, _skipped} ->
            store_and_navigate_player(
              socket,
              stepped_state,
              parent_nodes,
              parent_connections,
              parent_flow_id
            )
        end

      {:error, :empty_stack} ->
        {:noreply, update_slide(socket, %{state | status: :finished})}
    end
  end

  defp store_and_navigate_player(socket, state, nodes, connections, flow_id) do
    %{workspace: ws, project: proj, sheets_map: sheets_map, player_mode: mode} = socket.assigns
    user_id = socket.assigns.current_scope.user.id

    target_flow = Flows.get_flow_brief(proj.id, flow_id)

    DebugSessionStore.store({user_id, proj.id}, %{
      engine_state: state,
      nodes: nodes,
      connections: connections,
      sheets_map: sheets_map,
      flow: target_flow,
      player_mode: mode,
      scene_backdrop: socket.assigns.scene_backdrop,
      current_scene_id: socket.assigns.current_scene_id
    })

    {:noreply,
     push_navigate(socket,
       to: ~p"/workspaces/#{ws.slug}/projects/#{proj.slug}/flows/#{flow_id}/play"
     )}
  end

  # ===========================================================================
  # Private helpers
  # ===========================================================================

  defp update_slide(socket, new_state) do
    %{nodes: nodes, sheets_map: sheets_map, project: project} = socket.assigns
    node = Map.get(nodes, new_state.current_node_id)
    slide = Slide.build(node, new_state, sheets_map, project.id)

    socket
    |> assign(:engine_state, new_state)
    |> assign(:slide, slide)
    |> assign(:can_go_back, new_state.snapshots != [])
  end

  defp maybe_update_scene_backdrop(socket, new_scene_id) do
    if new_scene_id == socket.assigns.current_scene_id do
      socket
    else
      new_backdrop = if new_scene_id, do: Scenes.get_scene_backdrop(new_scene_id)

      socket
      |> assign(:scene_backdrop, new_backdrop)
      |> assign(:current_scene_id, new_scene_id)
    end
  end

  defp show_continue?(%{type: :dialogue, responses: []}), do: true
  defp show_continue?(%{type: :dialogue}), do: false
  defp show_continue?(%{type: :scene}), do: true
  defp show_continue?(_), do: false
end
