defmodule StoryarnWeb.MapLive.ExplorationLive do
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
  alias Storyarn.Flows.Evaluator.ConditionEval
  alias Storyarn.Flows.Evaluator.Engine
  alias Storyarn.Flows.Evaluator.Helpers, as: EvalHelpers
  alias Storyarn.Flows.Evaluator.InstructionExec
  alias Storyarn.Maps
  alias Storyarn.Projects
  alias Storyarn.Shared.MapUtils
  alias Storyarn.Sheets

  alias StoryarnWeb.FlowLive.Handlers.DebugExecutionHandlers
  alias StoryarnWeb.FlowLive.Helpers.FormHelpers
  alias StoryarnWeb.FlowLive.Helpers.VariableHelpers
  alias StoryarnWeb.FlowLive.Player.PlayerEngine
  alias StoryarnWeb.FlowLive.Player.Slide
  alias StoryarnWeb.MapLive.Helpers.Serializer

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
            {dgettext("maps", "Exit")}
          </button>
        </div>
        <div class="player-toolbar-center">
          <span class="text-sm font-medium">{@map.name}</span>
          <span :if={@flow_mode && @active_flow} class="text-xs opacity-50 ml-2">
            — {@active_flow.flow.name}
          </span>
        </div>
        <div class="player-toolbar-right"></div>
      </div>

      <div class="player-main relative">
        <%!-- Map layer (dimmed when flow active) --%>
        <div class={["w-full max-w-4xl", @flow_mode && "opacity-30 pointer-events-none"]}>
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
              {dgettext("maps", "Continue")} →
            </button>
          </div>

          <div :if={@active_flow.slide.type == :outcome} class="mt-4">
            <button type="button" phx-click="flow_finish" class="player-toolbar-btn">
              {dgettext("maps", "Return to map")}
            </button>
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
          "id" => map_id
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
        mount_exploration(socket, project, map_id)

      {:error, _reason} ->
        {:ok,
         socket
         |> put_flash(:error, dgettext("maps", "You don't have access to this project."))
         |> redirect(to: ~p"/workspaces")}
    end
  end

  defp mount_exploration(socket, project, map_id) do
    case Maps.get_map(project.id, map_id) do
      nil ->
        {:ok,
         socket
         |> put_flash(:error, dgettext("maps", "Map not found."))
         |> redirect(to: ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/maps")}

      map ->
        variables = VariableHelpers.build_variables(project.id)
        zones = evaluate_elements(map.zones || [], variables)
        pins = evaluate_elements(map.pins || [], variables)

        socket =
          socket
          |> assign(:map, map)
          |> assign(:project, project)
          |> assign(:workspace, project.workspace)
          |> assign(:variables, variables)
          |> assign(:zones, zones)
          |> assign(:pins, pins)
          |> assign(:exploration_data, serialize_for_exploration(map, zones, pins))
          |> assign(:flow_mode, false)
          |> assign(:active_flow, nil)
          |> assign(:flow_nodes, %{})
          |> assign(:flow_connections, [])
          |> assign(:flow_sheets_map, %{})

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

  def handle_event("exit_exploration", _params, socket) do
    if socket.assigns.flow_mode do
      # Exit flow overlay, return to map exploration
      {:noreply,
       socket
       |> assign(:flow_mode, false)
       |> assign(:active_flow, nil)}
    else
      path =
        ~p"/workspaces/#{socket.assigns.workspace.slug}/projects/#{socket.assigns.project.slug}/maps/#{socket.assigns.map.id}"

      {:noreply, push_navigate(socket, to: path)}
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

    case Engine.choose_response(state, response_id, connections) do
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
        {:noreply, put_flash(socket, :error, dgettext("maps", "Could not select that response."))}
    end
  end

  def handle_event("go_back", _params, socket) do
    %{engine_state: state} = socket.assigns.active_flow

    case Engine.step_back(state) do
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
      # Escape — exit flow overlay or exploration
      key == "Escape" ->
        if socket.assigns.flow_mode do
          {:noreply, socket |> assign(:flow_mode, false) |> assign(:active_flow, nil)}
        else
          path =
            ~p"/workspaces/#{socket.assigns.workspace.slug}/projects/#{socket.assigns.project.slug}/maps/#{socket.assigns.map.id}"

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

    case InstructionExec.execute(assignments, socket.assigns.variables) do
      {:ok, new_variables, _changes, _errors} ->
        refresh_exploration_state(socket, new_variables)

      _ ->
        socket
    end
  end

  defp handle_element_action(_params, socket), do: socket

  defp handle_element_target(%{"target_type" => "map", "target_id" => target_map_id}, socket)
       when not is_nil(target_map_id) and target_map_id != "" do
    path =
      ~p"/workspaces/#{socket.assigns.workspace.slug}/projects/#{socket.assigns.project.slug}/maps/#{target_map_id}/explore"

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
        {:error, put_flash(socket, :error, dgettext("maps", "Flow not found."))}

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
        {:error, dgettext("maps", "Flow has no entry node.")}

      entry_id ->
        state =
          Engine.init(variables, entry_id)
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
      Engine.push_flow_context(
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
        {:noreply, put_flash(socket, :error, dgettext("maps", "Target flow has no entry node."))}

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
    case Engine.pop_flow_context(state) do
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

      %{type: "map", id: map_id} ->
        socket = assign(socket, :variables, new_variables)

        path =
          ~p"/workspaces/#{socket.assigns.workspace.slug}/projects/#{socket.assigns.project.slug}/maps/#{map_id}/explore"

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
    zones = evaluate_elements(socket.assigns.map.zones || [], new_variables)
    pins = evaluate_elements(socket.assigns.map.pins || [], new_variables)

    display_vars =
      Map.new(new_variables, fn {ref, v} -> {ref, EvalHelpers.format_value(v.value)} end)

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
    {passed, _} = ConditionEval.evaluate(condition, variables)

    if passed do
      :visible
    else
      case effect do
        "disable" -> :disable
        _ -> :hide
      end
    end
  end

  defp serialize_for_exploration(map, zones, pins) do
    %{
      background_url: Serializer.background_url(map),
      map_width: map.width,
      map_height: map.height,
      zones:
        Enum.map(zones, fn z ->
          z |> Serializer.serialize_zone() |> Map.put(:visibility, z.visibility)
        end),
      pins:
        Enum.map(pins, fn p ->
          p |> Serializer.serialize_pin() |> Map.put(:visibility, p.visibility)
        end)
    }
  end
end
