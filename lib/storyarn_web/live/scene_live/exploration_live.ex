defmodule StoryarnWeb.SceneLive.ExplorationLive do
  @moduledoc """
  Full-screen exploration mode player for maps.

  Renders a map with interactive zones and pins. Clicking instruction elements
  executes variable assignments; clicking target elements navigates to other maps
  or launches flow dialogues overlaid on the dimmed map.

  Flow execution runs in-place (no URL change) — cross-flow jumps and returns
  are handled internally via the engine call stack.
  """

  use StoryarnWeb, :live_view

  import StoryarnWeb.Layouts, only: [flash_group: 1]

  import StoryarnWeb.FlowLive.Player.Components.PlayerSlide, only: [player_slide: 1]
  import StoryarnWeb.FlowLive.Player.Components.PlayerChoices, only: [player_choices: 1]

  alias Storyarn.Flows
  alias Storyarn.Projects
  alias Storyarn.Scenes
  alias Storyarn.Shared.{FormulaRuntime, MapUtils}
  alias Storyarn.Sheets

  alias StoryarnWeb.FlowLive.Handlers.DebugExecutionHandlers
  alias StoryarnWeb.FlowLive.Helpers.FormHelpers
  alias StoryarnWeb.FlowLive.Helpers.VariableHelpers
  alias StoryarnWeb.FlowLive.Player.PlayerEngine
  alias StoryarnWeb.FlowLive.Player.Slide
  alias StoryarnWeb.SceneLive.Helpers.Serializer

  # ===========================================================================
  # Render
  # ===========================================================================

  @impl true
  def render(assigns) do
    ~H"""
    <div class="player-layout" phx-window-keydown="handle_keydown">
      <div class="player-toolbar">
        <div class="player-toolbar-left">
          <button type="button" class="player-toolbar-btn" phx-click="exit_exploration">
            <.icon name="arrow-left" class="size-4" />
            {dgettext("scenes", "Exit")}
          </button>
        </div>
        <div class="player-toolbar-center">
          <span class="text-sm font-medium">{@scene.name}</span>
          <span :if={@flow_mode && @active_flow} class="text-xs opacity-50 ml-2">
            — {@active_flow.flow.name}
          </span>
        </div>
        <div class="player-toolbar-right">
          <button
            type="button"
            class="player-toolbar-btn"
            phx-click="save_session"
            title={dgettext("scenes", "Save progress")}
          >
            <.icon name="save" class="size-4" />
          </button>
          <button
            type="button"
            class={"player-toolbar-btn #{if @show_zones, do: "player-toolbar-btn-active"}"}
            phx-click="toggle_show_zones"
            title={dgettext("scenes", "Show zones")}
          >
            <.icon name="scan" class="size-4" />
          </button>
        </div>
      </div>

      <div class={[
        "player-main relative",
        @scene.exploration_display_mode == "scaled" && "exploration-viewport"
      ]}>
        <%!-- Session prompt overlay --%>
        <div :if={@session_prompt} class="exploration-session-overlay">
          <div class="session-prompt-modal">
            <div class="session-prompt-header">
              <h3 class="text-lg font-semibold">
                <.icon name="bookmark" class="size-5 inline-block mr-1 opacity-60" />
                {dgettext("scenes", "Saved Progress Found")}
              </h3>
            </div>
            <div class="session-prompt-body">
              <p class="text-sm opacity-70">
                {dgettext("scenes", "You have a saved exploration session.")}
              </p>
              <div :if={@pending_session} class="session-prompt-details">
                <div :if={@pending_session.scene} class="text-sm">
                  <span class="opacity-50">{dgettext("scenes", "Scene:")}</span>
                  <span class="font-medium ml-1">{@pending_session.scene.name}</span>
                </div>
                <div class="text-xs opacity-40">
                  {dgettext("scenes", "Last played: %{time}",
                    time: Calendar.strftime(@pending_session.updated_at, "%b %d, %Y at %H:%M")
                  )}
                </div>
              </div>
            </div>
            <div class="session-prompt-actions">
              <button
                type="button"
                phx-click="continue_session"
                class="player-toolbar-btn player-toolbar-btn-primary"
              >
                <.icon name="play" class="size-4" />
                {dgettext("scenes", "Continue")}
              </button>
              <button type="button" phx-click="new_session" class="player-toolbar-btn">
                <.icon name="rotate-ccw" class="size-4" />
                {dgettext("scenes", "New Game")}
              </button>
            </div>
          </div>
        </div>
        <%!-- Map layer (dimmed when flow active) --%>
        <div class={[
          "w-full",
          @scene.exploration_display_mode != "scaled" && "max-w-4xl",
          @flow_mode && "opacity-30 pointer-events-none"
        ]}>
          <div
            id="exploration-player"
            phx-hook="ExplorationPlayer"
            phx-update="ignore"
            data-exploration={Jason.encode!(@exploration_data)}
          >
          </div>
        </div>

        <%!-- Flow overlay --%>
        <div :if={@flow_mode && @active_flow} class="exploration-flow-overlay">
          <.player_slide slide={@active_flow.slide} />
          <.player_choices
            responses={@active_flow.slide[:responses] || []}
            player_mode={:player}
          />

          <div :if={show_flow_continue?(@active_flow)} class="mt-4">
            <button type="button" phx-click="flow_continue" class="player-toolbar-btn">
              {dgettext("scenes", "Continue")} →
            </button>
          </div>

          <div :if={@active_flow.slide.type == :outcome} class="mt-4">
            <button type="button" phx-click="flow_finish" class="player-toolbar-btn">
              {dgettext("scenes", "Return to map")}
            </button>
          </div>
        </div>

        <%!-- Collection overlay --%>
        <div :if={@collection_mode && @collection_zone} class="exploration-collection-overlay">
          <div class="collection-modal">
            <div class="collection-modal-header">
              <h3 class="text-lg font-semibold">
                <.icon name="package-open" class="size-5 inline-block mr-1 opacity-60" />
                {dgettext("scenes", "Collection")}
              </h3>
              <button
                type="button"
                phx-click="collection_close"
                class="player-toolbar-btn"
              >
                <.icon name="x" class="size-4" />
              </button>
            </div>

            <div :if={@collection_items == []} class="collection-modal-empty">
              <.icon name="package-open" class="size-8 opacity-30" />
              <p class="text-sm opacity-50 mt-2">
                {if @collection_zone.empty_message != "",
                  do: @collection_zone.empty_message,
                  else: dgettext("scenes", "Nothing here...")}
              </p>
            </div>

            <div :if={@collection_items != []} class="collection-modal-items">
              <div
                :for={item <- @collection_items}
                class="collection-item-card"
              >
                <div class="collection-item-info">
                  <span class="collection-item-label">
                    {item["label"] || item["_sheet_name"] || dgettext("scenes", "Item")}
                  </span>
                </div>
                <button
                  type="button"
                  phx-click="collection_take"
                  phx-value-item-id={item["id"]}
                  class="player-toolbar-btn player-toolbar-btn-primary"
                >
                  {dgettext("scenes", "Take")}
                </button>
              </div>
            </div>

            <div
              :if={@collection_items != [] && @collection_zone.collect_all_enabled}
              class="collection-modal-footer"
            >
              <button
                type="button"
                phx-click="collection_take_all"
                class="player-toolbar-btn player-toolbar-btn-primary"
              >
                <.icon name="package-check" class="size-4" />
                {dgettext("scenes", "Take All")}
              </button>
            </div>
          </div>
        </div>
      </div>

      <.flash_group flash={@flash} />
    </div>
    """
  end

  # ===========================================================================
  # Mount
  # ===========================================================================

  @impl true
  def mount(
        %{
          "workspace_slug" => workspace_slug,
          "project_slug" => project_slug,
          "id" => scene_id
        },
        _session,
        socket
      ) do
    case Projects.get_project_by_slugs(
           socket.assigns.current_scope,
           workspace_slug,
           project_slug
         ) do
      {:ok, project, _membership} ->
        mount_exploration(socket, project, scene_id)

      {:error, _reason} ->
        {:ok,
         socket
         |> put_flash(:error, dgettext("scenes", "You don't have access to this project."))
         |> redirect(to: ~p"/workspaces")}
    end
  end

  defp mount_exploration(socket, project, scene_id) do
    case Scenes.get_scene(project.id, scene_id) do
      nil ->
        {:ok,
         socket
         |> put_flash(:error, dgettext("scenes", "Scene not found."))
         |> redirect(
           to: ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/scenes"
         )}

      scene ->
        user_id = socket.assigns.current_scope.user.id
        existing_session = Scenes.get_exploration_session(user_id, project.id)

        variables = VariableHelpers.build_variables(project.id)
        zones = evaluate_elements(scene.zones || [], variables)
        pins = evaluate_elements(scene.pins || [], variables)

        socket =
          socket
          |> assign(:scene, scene)
          |> assign(:project, project)
          |> assign(:workspace, project.workspace)
          |> assign(:variables, variables)
          |> assign(:zones, zones)
          |> assign(:pins, pins)
          |> assign(:exploration_data, serialize_for_exploration(scene, zones, pins))
          |> assign(:show_zones, false)
          |> assign(:flow_mode, false)
          |> assign(:active_flow, nil)
          |> assign(:flow_nodes, %{})
          |> assign(:flow_connections, [])
          |> assign(:flow_sheets_map, %{})
          |> assign(:collection_mode, false)
          |> assign(:collection_zone, nil)
          |> assign(:collection_items, [])
          |> assign(:collected_ids, MapSet.new())
          |> assign(:session_prompt, existing_session != nil)
          |> assign(:pending_session, existing_session)

        {:ok, socket, layout: false}
    end
  end

  # ===========================================================================
  # Events — Exploration
  # ===========================================================================

  @impl true
  def handle_event("exploration_element_click", params, socket) do
    socket = handle_element_action(params, socket)
    socket = handle_element_target(params, socket)
    {:noreply, socket}
  end

  def handle_event("toggle_show_zones", _params, socket) do
    new_val = !socket.assigns.show_zones

    {:noreply,
     socket
     |> assign(:show_zones, new_val)
     |> push_event("toggle_show_zones", %{show: new_val})}
  end

  def handle_event("exit_exploration", _params, socket) do
    cond do
      socket.assigns.collection_mode ->
        {:noreply, close_collection_modal(socket)}

      socket.assigns.flow_mode ->
        {:noreply,
         socket
         |> assign(:flow_mode, false)
         |> assign(:active_flow, nil)}

      true ->
        path =
          ~p"/workspaces/#{socket.assigns.workspace.slug}/projects/#{socket.assigns.project.slug}/scenes/#{socket.assigns.scene.id}"

        {:noreply, push_navigate(socket, to: path)}
    end
  end

  # ===========================================================================
  # Events — Collection
  # ===========================================================================

  def handle_event("collection_take", %{"item-id" => item_id}, socket) do
    item = Enum.find(socket.assigns.collection_items, &(&1["id"] == item_id))

    if item do
      socket = execute_collection_item(socket, item)
      {:noreply, refresh_collection_items(socket)}
    else
      {:noreply, socket}
    end
  end

  def handle_event("collection_take_all", _params, socket) do
    visible_items = socket.assigns.collection_items

    socket =
      Enum.reduce(visible_items, socket, fn item, acc ->
        execute_collection_item(acc, item)
      end)

    {:noreply, refresh_collection_items(socket)}
  end

  def handle_event("collection_close", _params, socket) do
    {:noreply, close_collection_modal(socket)}
  end

  # ===========================================================================
  # Events — Session Persistence
  # ===========================================================================

  def handle_event("continue_session", _params, socket) do
    session = socket.assigns.pending_session

    # Rebuild variables with saved overrides
    variables = VariableHelpers.build_variables(socket.assigns.project.id)

    variables =
      Enum.reduce(session.variable_values || %{}, variables, fn {ref, value}, acc ->
        case Map.get(acc, ref) do
          nil -> acc
          entry -> Map.put(acc, ref, %{entry | value: value})
        end
      end)

    variables = FormulaRuntime.recompute_formulas(variables)

    # Restore collected IDs
    collected_ids = MapSet.new(session.collected_ids || [])

    socket =
      socket
      |> assign(:collected_ids, collected_ids)
      |> assign(:session_prompt, false)
      |> assign(:pending_session, nil)

    # Navigate to saved scene if different from current
    if session.scene_id && session.scene_id != socket.assigns.scene.id do
      case Scenes.get_scene(socket.assigns.project.id, session.scene_id) do
        nil ->
          # Saved scene was deleted, stay on current scene with restored variables
          socket = apply_variable_update(socket, variables)

          {:noreply,
           put_flash(
             socket,
             :warning,
             dgettext("scenes", "Saved scene no longer exists. Starting on current scene.")
           )}

        _saved_scene ->
          # Navigate to saved scene — positions will be restored via JS event
          socket = assign(socket, :variables, variables)

          path =
            ~p"/workspaces/#{socket.assigns.workspace.slug}/projects/#{socket.assigns.project.slug}/scenes/#{session.scene_id}/explore"

          {:noreply, push_navigate(socket, to: path)}
      end
    else
      # Same scene — apply variables and restore positions
      socket =
        socket
        |> apply_variable_update(variables)
        |> push_event("restore_positions", %{
          leader: get_in(session.player_positions, ["leader"]),
          party: get_in(session.player_positions, ["party"]),
          camera: session.camera_state
        })

      {:noreply, socket}
    end
  end

  def handle_event("new_session", _params, socket) do
    user_id = socket.assigns.current_scope.user.id
    Scenes.delete_exploration_session(user_id, socket.assigns.project.id)

    {:noreply,
     socket
     |> assign(:session_prompt, false)
     |> assign(:pending_session, nil)}
  end

  def handle_event("save_session", _params, socket) do
    {:noreply, push_event(socket, "request_positions", %{})}
  end

  def handle_event("report_positions", params, socket) do
    case do_save_session(socket, params) do
      {:ok, socket} ->
        {:noreply, put_flash(socket, :info, dgettext("scenes", "Progress saved."))}

      {:error, socket} ->
        {:noreply, put_flash(socket, :error, dgettext("scenes", "Failed to save progress."))}
    end
  end

  # ===========================================================================
  # Events — Flow Execution
  # ===========================================================================

  def handle_event("flow_continue", _params, socket) do
    %{engine_state: state} = socket.assigns.active_flow
    nodes = socket.assigns.flow_nodes
    connections = socket.assigns.flow_connections

    case PlayerEngine.step_until_interactive(state, nodes, connections) do
      {:flow_jump, new_state, target_flow_id, _skipped} ->
        handle_exploration_flow_jump(socket, new_state, target_flow_id)

      {:flow_return, new_state, _skipped} ->
        handle_exploration_flow_return(socket, new_state)

      {:finished, new_state, _skipped} ->
        handle_flow_finished(socket, new_state)

      {_status, new_state, _skipped} ->
        {:noreply, update_flow_slide(socket, new_state)}
    end
  end

  def handle_event("choose_response", %{"id" => response_id}, socket) do
    %{engine_state: state} = socket.assigns.active_flow
    nodes = socket.assigns.flow_nodes
    connections = socket.assigns.flow_connections

    case Flows.evaluator_choose_response(state, response_id, connections) do
      {:ok, new_state} ->
        case PlayerEngine.step_until_interactive(new_state, nodes, connections) do
          {:flow_jump, stepped, target_flow_id, _} ->
            handle_exploration_flow_jump(socket, stepped, target_flow_id)

          {:flow_return, stepped, _} ->
            handle_exploration_flow_return(socket, stepped)

          {:finished, stepped, _} ->
            handle_flow_finished(socket, stepped)

          {_status, stepped, _} ->
            {:noreply, update_flow_slide(socket, stepped)}
        end

      {:error, _state, _reason} ->
        {:noreply,
         put_flash(socket, :error, dgettext("scenes", "Could not select that response."))}
    end
  end

  def handle_event("go_back", _params, socket) do
    %{engine_state: state} = socket.assigns.active_flow

    case Flows.evaluator_step_back(state) do
      {:ok, new_state} -> {:noreply, update_flow_slide(socket, new_state)}
      {:error, :no_history} -> {:noreply, socket}
    end
  end

  def handle_event("flow_finish", _params, socket) do
    state = socket.assigns.active_flow.engine_state
    handle_flow_finished(socket, state)
  end

  # ===========================================================================
  # Events — Keyboard
  # ===========================================================================

  def handle_event("handle_keydown", %{"key" => key}, socket) do
    cond do
      # Escape — close collection modal, exit flow overlay, or exit exploration
      key == "Escape" ->
        cond do
          socket.assigns.collection_mode ->
            {:noreply, close_collection_modal(socket)}

          socket.assigns.flow_mode ->
            {:noreply, socket |> assign(:flow_mode, false) |> assign(:active_flow, nil)}

          true ->
            path =
              ~p"/workspaces/#{socket.assigns.workspace.slug}/projects/#{socket.assigns.project.slug}/scenes/#{socket.assigns.scene.id}"

            {:noreply, push_navigate(socket, to: path)}
        end

      # Flow mode keyboard controls
      socket.assigns.flow_mode && socket.assigns.active_flow != nil ->
        handle_flow_keydown(key, socket)

      true ->
        {:noreply, socket}
    end
  end

  # ===========================================================================
  # Private — Element Click Handling
  # ===========================================================================

  defp handle_element_action(
         %{"action_type" => "instruction", "action_data" => action_data},
         socket
       ) do
    assignments = action_data["assignments"] || []

    case Flows.execute_instructions(assignments, socket.assigns.variables) do
      {:ok, new_variables, _changes, _errors, warnings} ->
        new_variables = FormulaRuntime.recompute_formulas(new_variables)
        socket = refresh_exploration_state(socket, new_variables)

        if warnings != [] do
          msg = Enum.map_join(warnings, "\n", & &1.message)
          put_flash(socket, :warning, msg)
        else
          socket
        end

      _ ->
        socket
    end
  end

  defp handle_element_action(
         %{"action_type" => "collection", "element_id" => zone_id, "action_data" => action_data},
         socket
       ) do
    open_collection_modal(socket, zone_id, action_data)
  end

  defp handle_element_action(_params, socket), do: socket

  defp handle_element_target(%{"target_type" => "scene", "target_id" => target_scene_id}, socket)
       when not is_nil(target_scene_id) and target_scene_id != "" do
    path =
      ~p"/workspaces/#{socket.assigns.workspace.slug}/projects/#{socket.assigns.project.slug}/scenes/#{target_scene_id}/explore"

    push_navigate(socket, to: path)
  end

  defp handle_element_target(%{"target_type" => "flow", "target_id" => flow_id}, socket)
       when not is_nil(flow_id) and flow_id != "" do
    case MapUtils.parse_int(flow_id) do
      nil ->
        socket

      parsed_id ->
        case init_flow(socket, parsed_id) do
          {:ok, socket} -> socket
          {:error, socket} -> socket
        end
    end
  end

  defp handle_element_target(_params, socket), do: socket

  # ===========================================================================
  # Private — Flow Init
  # ===========================================================================

  defp init_flow(socket, flow_id) do
    project = socket.assigns.project

    case Flows.get_flow(project.id, flow_id) do
      nil ->
        {:error, put_flash(socket, :error, dgettext("scenes", "Flow not found."))}

      flow ->
        nodes_map = DebugExecutionHandlers.build_nodes_map(flow.id)
        connections = DebugExecutionHandlers.build_connections(flow.id)
        all_sheets = Sheets.list_all_sheets(project.id)
        sheets_map = FormHelpers.sheets_map(all_sheets)

        case find_entry_and_step(nodes_map, connections, socket.assigns.variables, flow.id) do
          {:error, reason} ->
            {:error, put_flash(socket, :error, reason)}

          {:ok, engine_state} ->
            node = Map.get(nodes_map, engine_state.current_node_id)
            slide = Slide.build(node, engine_state, sheets_map, project.id)

            {:ok,
             socket
             |> assign(:flow_mode, true)
             |> assign(:flow_nodes, nodes_map)
             |> assign(:flow_connections, connections)
             |> assign(:flow_sheets_map, sheets_map)
             |> push_event("patrol_pause", %{})
             |> assign(:active_flow, %{
               flow_id: flow.id,
               flow: flow,
               engine_state: engine_state,
               slide: slide
             })}
        end
    end
  end

  defp find_entry_and_step(nodes_map, connections, variables, flow_id) do
    case DebugExecutionHandlers.find_entry_node(nodes_map) do
      nil ->
        {:error, dgettext("scenes", "Flow has no entry node.")}

      entry_id ->
        state =
          Flows.evaluator_init(variables, entry_id)
          |> Map.put(:current_flow_id, flow_id)

        case PlayerEngine.step_until_interactive(state, nodes_map, connections) do
          {:finished, final_state, _} -> {:ok, final_state}
          {:flow_jump, jumped_state, _target_id, _} -> {:ok, jumped_state}
          {:flow_return, returned_state, _} -> {:ok, returned_state}
          {_status, stepped_state, _} -> {:ok, stepped_state}
        end
    end
  end

  # ===========================================================================
  # Private — Cross-flow Handling
  # ===========================================================================

  defp handle_exploration_flow_jump(socket, state, target_flow_id) do
    state =
      Flows.evaluator_push_flow_context(
        state,
        state.current_node_id,
        socket.assigns.flow_nodes,
        socket.assigns.flow_connections,
        ""
      )

    target_nodes = DebugExecutionHandlers.build_nodes_map(target_flow_id)
    target_connections = DebugExecutionHandlers.build_connections(target_flow_id)

    case DebugExecutionHandlers.find_entry_node(target_nodes) do
      nil ->
        {:noreply,
         put_flash(socket, :error, dgettext("scenes", "Target flow has no entry node."))}

      entry_id ->
        log_entry = %{node_id: entry_id, depth: length(state.call_stack)}

        new_state = %{
          state
          | current_node_id: entry_id,
            current_flow_id: target_flow_id,
            status: :paused,
            execution_path: [entry_id | state.execution_path],
            execution_log: [log_entry | state.execution_log]
        }

        case PlayerEngine.step_until_interactive(new_state, target_nodes, target_connections) do
          {:flow_jump, stepped, next_flow_id, _} ->
            socket = update_active_flow(socket, stepped, target_nodes, target_connections)
            handle_exploration_flow_jump(socket, stepped, next_flow_id)

          {:flow_return, stepped, _} ->
            socket = update_active_flow(socket, stepped, target_nodes, target_connections)
            handle_exploration_flow_return(socket, stepped)

          {:finished, stepped, _} ->
            socket = update_active_flow(socket, stepped, target_nodes, target_connections)
            handle_flow_finished(socket, stepped)

          {_status, stepped, _} ->
            {:noreply, update_active_flow(socket, stepped, target_nodes, target_connections)}
        end
    end
  end

  defp handle_exploration_flow_return(socket, state) do
    case Flows.evaluator_pop_flow_context(state) do
      {:ok, frame, new_state} ->
        parent_nodes = frame.nodes
        parent_connections = frame.connections

        conn =
          Enum.find(parent_connections, fn c ->
            c.source_node_id == frame.return_node_id and c.source_pin in ["default", "output"]
          end)

        new_state =
          if conn do
            log_entry = %{
              node_id: conn.target_node_id,
              depth: length(new_state.call_stack)
            }

            %{
              new_state
              | current_node_id: conn.target_node_id,
                current_flow_id: frame.flow_id,
                status: :paused,
                execution_path: [conn.target_node_id | frame.execution_path],
                execution_log: [log_entry | new_state.execution_log]
            }
          else
            %{new_state | status: :finished, current_flow_id: frame.flow_id}
          end

        case PlayerEngine.step_until_interactive(new_state, parent_nodes, parent_connections) do
          {:flow_jump, stepped, next_flow_id, _} ->
            socket = update_active_flow(socket, stepped, parent_nodes, parent_connections)
            handle_exploration_flow_jump(socket, stepped, next_flow_id)

          {:flow_return, stepped, _} ->
            socket = update_active_flow(socket, stepped, parent_nodes, parent_connections)
            handle_exploration_flow_return(socket, stepped)

          {:finished, stepped, _} ->
            socket = update_active_flow(socket, stepped, parent_nodes, parent_connections)
            handle_flow_finished(socket, stepped)

          {_status, stepped, _} ->
            {:noreply, update_active_flow(socket, stepped, parent_nodes, parent_connections)}
        end

      {:error, :empty_stack} ->
        handle_flow_finished(socket, %{state | status: :finished})
    end
  end

  # ===========================================================================
  # Private — Flow Finish & Return to Exploration
  # ===========================================================================

  defp handle_flow_finished(socket, final_state) do
    new_variables = final_state.variables

    case final_state.exit_transition do
      nil ->
        {:noreply, return_to_exploration(socket, new_variables)}

      %{type: "scene", id: scene_id} ->
        socket = assign(socket, :variables, new_variables)

        path =
          ~p"/workspaces/#{socket.assigns.workspace.slug}/projects/#{socket.assigns.project.slug}/scenes/#{scene_id}/explore"

        {:noreply, push_navigate(socket, to: path)}

      %{type: "flow", id: flow_id} ->
        socket =
          socket
          |> assign(:variables, new_variables)
          |> assign(:flow_mode, false)
          |> assign(:active_flow, nil)

        case init_flow(socket, flow_id) do
          {:ok, socket} -> {:noreply, socket}
          {:error, socket} -> {:noreply, return_to_exploration(socket, new_variables)}
        end

      _ ->
        {:noreply, return_to_exploration(socket, new_variables)}
    end
  end

  defp return_to_exploration(socket, new_variables) do
    socket
    |> apply_variable_update(new_variables)
    |> assign(:flow_mode, false)
    |> assign(:active_flow, nil)
    |> push_event("patrol_resume", %{})
  end

  # ===========================================================================
  # Private — Flow Helpers
  # ===========================================================================

  defp update_flow_slide(socket, new_state) do
    af = socket.assigns.active_flow
    node = Map.get(socket.assigns.flow_nodes, new_state.current_node_id)

    slide =
      Slide.build(node, new_state, socket.assigns.flow_sheets_map, socket.assigns.project.id)

    assign(socket, :active_flow, %{af | engine_state: new_state, slide: slide})
  end

  defp update_active_flow(socket, new_state, nodes, connections) do
    af = socket.assigns.active_flow
    node = Map.get(nodes, new_state.current_node_id)

    slide =
      Slide.build(node, new_state, socket.assigns.flow_sheets_map, socket.assigns.project.id)

    socket
    |> assign(:flow_nodes, nodes)
    |> assign(:flow_connections, connections)
    |> assign(:active_flow, %{af | engine_state: new_state, slide: slide})
  end

  defp show_flow_continue?(active_flow) do
    slide = active_flow.slide
    state = active_flow.engine_state

    # Show continue when: dialogue without responses, or paused (not waiting_input/finished/outcome)
    cond do
      slide.type == :outcome -> false
      slide.type == :dialogue && (slide[:responses] || []) != [] -> false
      state.status == :finished -> false
      true -> true
    end
  end

  defp refresh_exploration_state(socket, new_variables) do
    apply_variable_update(socket, new_variables)
  end

  defp apply_variable_update(socket, new_variables) do
    zones = evaluate_elements(socket.assigns.scene.zones || [], new_variables)
    pins = evaluate_elements(socket.assigns.scene.pins || [], new_variables)

    display_vars =
      Map.new(new_variables, fn {ref, v} -> {ref, Flows.evaluator_format_value(v.value)} end)

    socket
    |> assign(:variables, new_variables)
    |> assign(:zones, zones)
    |> assign(:pins, pins)
    |> push_event("exploration_state_updated", %{
      zones: Enum.map(zones, &%{id: &1.id, visibility: &1.visibility}),
      pins: Enum.map(pins, &%{id: &1.id, visibility: &1.visibility}),
      variables: display_vars
    })
  end

  # ===========================================================================
  # Private — Keyboard Handling for Flow Mode
  # ===========================================================================

  defp handle_flow_keydown(key, socket) do
    slide = socket.assigns.active_flow.slide
    responses = slide[:responses] || []
    has_responses = responses != []

    cond do
      has_responses && key =~ ~r/^[1-9]$/ ->
        handle_flow_response_key(key, responses, socket)

      key in ["Enter", " ", "ArrowRight"] && !has_responses ->
        handle_flow_continue_key(slide, socket)

      key in ["ArrowLeft", "Backspace"] ->
        handle_event("go_back", %{}, socket)

      true ->
        {:noreply, socket}
    end
  end

  defp handle_flow_response_key(key, responses, socket) do
    case Integer.parse(key) do
      {idx, ""} ->
        valid_responses = Enum.filter(responses, & &1.valid)

        case Enum.at(valid_responses, idx - 1) do
          nil -> {:noreply, socket}
          resp -> handle_event("choose_response", %{"id" => resp.id}, socket)
        end

      _ ->
        {:noreply, socket}
    end
  end

  defp handle_flow_continue_key(slide, socket) do
    if slide.type == :outcome do
      handle_event("flow_finish", %{}, socket)
    else
      handle_event("flow_continue", %{}, socket)
    end
  end

  # ===========================================================================
  # Private — Collection Helpers
  # ===========================================================================

  defp open_collection_modal(socket, zone_id, action_data) do
    items = action_data["items"] || []
    variables = socket.assigns.variables
    collected = socket.assigns.collected_ids

    visible_items =
      items
      |> Enum.reject(&MapSet.member?(collected, &1["id"]))
      |> Enum.filter(&item_visible?(&1, variables))

    # Load sheet data for visible items
    visible_items = Enum.map(visible_items, &load_item_sheet_data(&1, socket.assigns.project.id))

    socket
    |> push_event("patrol_pause", %{})
    |> assign(:collection_mode, true)
    |> assign(:collection_zone, %{
      id: zone_id,
      action_data: action_data,
      empty_message: action_data["empty_message"] || "",
      collect_all_enabled: action_data["collect_all_enabled"] != false
    })
    |> assign(:collection_items, visible_items)
  end

  defp close_collection_modal(socket) do
    socket
    |> assign(:collection_mode, false)
    |> assign(:collection_zone, nil)
    |> assign(:collection_items, [])
    |> push_event("patrol_resume", %{})
  end

  defp execute_collection_item(socket, item) do
    assignments = get_in(item, ["instruction", "assignments"]) || []
    collected = MapSet.put(socket.assigns.collected_ids, item["id"])
    socket = assign(socket, :collected_ids, collected)

    if assignments == [] do
      socket
    else
      case Flows.execute_instructions(assignments, socket.assigns.variables) do
        {:ok, new_variables, _changes, _errors, _warnings} ->
          new_variables = FormulaRuntime.recompute_formulas(new_variables)
          refresh_exploration_state(socket, new_variables)

        _ ->
          socket
      end
    end
  end

  defp refresh_collection_items(socket) do
    case socket.assigns.collection_zone do
      nil ->
        socket

      zone_info ->
        items = zone_info.action_data["items"] || []
        variables = socket.assigns.variables
        collected = socket.assigns.collected_ids

        visible_items =
          items
          |> Enum.reject(&MapSet.member?(collected, &1["id"]))
          |> Enum.filter(&item_visible?(&1, variables))
          |> Enum.map(&load_item_sheet_data(&1, socket.assigns.project.id))

        assign(socket, :collection_items, visible_items)
    end
  end

  defp item_visible?(item, variables) do
    case item["condition"] do
      nil -> true
      condition when condition == %{} -> true
      condition -> elem(Flows.evaluate_condition(condition, variables), 0)
    end
  end

  defp load_item_sheet_data(item, project_id) do
    case MapUtils.parse_int(item["sheet_id"]) do
      nil ->
        item

      sheet_id ->
        case Sheets.get_sheet(project_id, sheet_id) do
          nil -> item
          sheet -> Map.put(item, "_sheet_name", sheet.name)
        end
    end
  end

  # ===========================================================================
  # Private — Evaluation Helpers
  # ===========================================================================

  defp evaluate_elements(elements, variables) do
    Enum.map(elements, fn el ->
      visibility = evaluate_visibility(el.condition, el.condition_effect, variables)
      Map.put(el, :visibility, visibility)
    end)
  end

  defp evaluate_visibility(nil, _effect, _vars), do: :visible
  defp evaluate_visibility(condition, _effect, _vars) when condition == %{}, do: :visible

  defp evaluate_visibility(condition, effect, variables) do
    {passed, _} = Flows.evaluate_condition(condition, variables)

    if passed do
      :visible
    else
      case effect do
        "disable" -> :disable
        _ -> :hide
      end
    end
  end

  # ===========================================================================
  # Private — Session Persistence Helpers
  # ===========================================================================

  defp build_session_attrs(socket) do
    variable_values =
      socket.assigns.variables
      |> Enum.reject(fn {_ref, v} -> v.value == v.initial_value end)
      |> Map.new(fn {ref, v} -> {ref, v.value} end)

    %{
      scene_id: socket.assigns.scene.id,
      variable_values: variable_values,
      collected_ids: MapSet.to_list(socket.assigns.collected_ids)
    }
  end

  defp do_save_session(socket, position_params) do
    user_id = socket.assigns.current_scope.user.id
    project_id = socket.assigns.project.id

    attrs =
      build_session_attrs(socket)
      |> Map.merge(%{
        player_positions: %{
          "leader" => position_params["leader"],
          "party" => position_params["party"]
        },
        camera_state: position_params["camera"]
      })

    case Scenes.save_exploration_session(user_id, project_id, attrs) do
      {:ok, _session} -> {:ok, socket}
      {:error, _changeset} -> {:error, socket}
    end
  end

  defp serialize_for_exploration(scene, zones, pins) do
    connections = scene.connections || []

    %{
      background_url: Serializer.background_url(scene),
      scene_width: scene.width,
      scene_height: scene.height,
      display_mode: scene.exploration_display_mode || "fit",
      default_zoom: scene.default_zoom || 1.0,
      default_center_x: scene.default_center_x,
      default_center_y: scene.default_center_y,
      zones:
        Enum.map(zones, fn z ->
          z |> Serializer.serialize_zone() |> Map.put(:visibility, z.visibility)
        end),
      pins:
        Enum.map(pins, fn p ->
          serialized = p |> Serializer.serialize_pin() |> Map.put(:visibility, p.visibility)

          if p.patrol_mode in [nil, "none"] do
            serialized
          else
            route = build_patrol_route(p, pins, connections)
            Map.put(serialized, :patrol_route, route)
          end
        end)
    }
  end

  # ---------------------------------------------------------------------------
  # Patrol Route Builder
  # ---------------------------------------------------------------------------

  # Builds an ordered patrol route by traversing connections from the given pin.
  # Returns a flat list of %{x, y, is_pin_stop} points.
  defp build_patrol_route(pin, pins, connections) do
    pins_by_id = Map.new(pins, &{&1.id, &1})
    start_point = %{x: pin.position_x, y: pin.position_y, is_pin_stop: true}
    traverse_route([pin.id], pin.id, pins_by_id, connections, [start_point])
  end

  defp traverse_route(visited, current_pin_id, pins_by_id, connections, acc) do
    next_connections = find_unvisited_connections(connections, current_pin_id, visited)

    case next_connections do
      [] ->
        Enum.reverse(acc)

      [conn | _] ->
        {waypoints, target_pin_id} = connection_traversal_data(conn, current_pin_id)
        follow_connection(visited, target_pin_id, waypoints, pins_by_id, connections, acc)
    end
  end

  defp find_unvisited_connections(connections, pin_id, visited) do
    connections
    |> Enum.filter(fn conn ->
      (conn.from_pin_id == pin_id && conn.to_pin_id not in visited) ||
        (conn.bidirectional && conn.to_pin_id == pin_id && conn.from_pin_id not in visited)
    end)
    |> Enum.sort_by(& &1.id)
  end

  defp connection_traversal_data(conn, current_pin_id) do
    if conn.from_pin_id == current_pin_id do
      {conn.waypoints || [], conn.to_pin_id}
    else
      {Enum.reverse(conn.waypoints || []), conn.from_pin_id}
    end
  end

  defp follow_connection(visited, target_pin_id, waypoints, pins_by_id, connections, acc) do
    waypoint_points =
      Enum.map(waypoints, fn wp ->
        %{x: wp["x"], y: wp["y"], is_pin_stop: false}
      end)

    case Map.get(pins_by_id, target_pin_id) do
      nil ->
        Enum.reverse(acc)

      target_pin ->
        pin_point = %{x: target_pin.position_x, y: target_pin.position_y, is_pin_stop: true}
        new_acc = [pin_point | Enum.reverse(waypoint_points)] ++ acc

        traverse_route(
          [target_pin_id | visited],
          target_pin_id,
          pins_by_id,
          connections,
          new_acc
        )
    end
  end
end
