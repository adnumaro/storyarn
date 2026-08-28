defmodule Storyarn.Flows.PlayerSession do
  @moduledoc """
  Owns the Flow player runtime session and its cross-flow transitions.

  The session keeps the evaluator state together with the graph it belongs to.
  Commands return an updated session; adapters decide whether that update is
  rendered in place, persisted, or followed by navigation.
  """

  alias Storyarn.Flows.Editor
  alias Storyarn.Flows.Evaluator.Engine
  alias Storyarn.Flows.Evaluator.EngineHelpers
  alias Storyarn.Flows.Evaluator.State
  alias Storyarn.Flows.Flow
  alias Storyarn.Flows.PlayerEngine
  alias Storyarn.Flows.Runtime.Events
  alias Storyarn.Flows.RuntimeGraph
  alias Storyarn.Flows.SceneResolver

  @max_flow_transitions 100
  @renderable_node_types ~w(dialogue exit)

  @enforce_keys [:state, :nodes, :connections, :flow]
  defstruct [:state, :nodes, :connections, :flow, :scene_id]

  @type t :: %__MODULE__{
          state: State.t(),
          nodes: %{optional(integer()) => map()},
          connections: [map()],
          flow: Flow.t(),
          scene_id: integer() | nil
        }

  @type error_reason ::
          :advance_failed
          | :entry_not_found
          | :invalid_response
          | :no_history
          | :transition_limit
          | {:flow_not_found, integer()}
          | {:target_entry_not_found, integer()}

  @type result :: {:ok, t()} | {:error, error_reason(), t()}

  @doc "Creates and advances a player session to its first interaction."
  @spec start(Flow.t(), map()) :: {:ok, t()} | {:error, error_reason()}
  def start(%Flow{} = flow, variables) when is_map(variables) do
    session = load_session(flow, variables)

    case RuntimeGraph.entry_node_id(session.nodes) do
      nil ->
        {:error, :entry_not_found}

      entry_id ->
        state = variables |> Engine.init(entry_id) |> Map.put(:current_flow_id, flow.id)

        case advance(session, state, [], 0) do
          {:ok, session} -> {:ok, session}
          {:error, reason, _session} -> {:error, reason}
        end
    end
  end

  @doc "Reconstitutes an ephemeral session previously stored by an adapter."
  @spec restore(Flow.t(), State.t(), map(), list(), integer() | nil) :: t()
  def restore(%Flow{} = flow, %State{} = state, nodes, connections, scene_id)
      when is_map(nodes) and is_list(connections) do
    %__MODULE__{
      state: state,
      nodes: nodes,
      connections: connections,
      flow: flow,
      scene_id: scene_id
    }
  end

  @doc "Emits the Flow-owned fact that a player session started."
  @spec record_started(term(), Flow.t()) :: :ok
  def record_started(scope_or_user, %Flow{} = flow) do
    Events.player_started(scope_or_user, flow)
  end

  @doc "Advances after an explicit continue action."
  @spec continue(t()) :: result()
  def continue(%__MODULE__{} = session) do
    state = session.state

    if state.status in [:finished, :waiting_input] and not is_nil(state.pending_choices) do
      {:ok, session}
    else
      advance(session, state, [advance_current_dialogue: true], 0)
    end
  end

  @doc "Chooses a dialogue response and advances to the next interaction."
  @spec choose_response(t(), term()) :: result()
  def choose_response(%__MODULE__{} = session, response_id) do
    case Engine.choose_response(session.state, response_id, session.connections) do
      {:ok, state} -> advance(session, state, [], 0)
      {:error, _state, _reason} -> {:error, :invalid_response, session}
    end
  end

  @doc "Resolves the authored response selected by a numbered player shortcut."
  @spec response_id_by_number([map()], :player | :analysis, integer()) ::
          {:ok, term()} | {:error, :response_not_found}
  def response_id_by_number(responses, mode, number)
      when is_list(responses) and mode in [:player, :analysis] and is_integer(number) and number > 0 do
    visible = if mode == :player, do: Enum.filter(responses, & &1.valid), else: responses

    case Enum.at(visible, number - 1) do
      %{id: response_id} -> {:ok, response_id}
      _missing -> {:error, :response_not_found}
    end
  end

  def response_id_by_number(_responses, _mode, _number), do: {:error, :response_not_found}

  @doc "Restores the previous renderable player state from evaluator snapshots."
  @spec go_back(t()) :: result()
  def go_back(%__MODULE__{} = session) do
    if can_go_back?(session) do
      case Engine.step_back(session.state) do
        {:ok, state} -> resolve_back_state(session, state)
        {:error, :no_history} -> {:error, :no_history, session}
      end
    else
      {:error, :no_history, session}
    end
  end

  @doc "Restarts the complete player run at its root Flow."
  @spec restart(t()) :: result()
  def restart(%__MODULE__{} = session) do
    root_session = root_session(session)

    state =
      session.state
      |> Engine.reset()
      |> Map.merge(%{
        current_flow_id: root_session.flow.id,
        call_stack: []
      })

    advance(root_session, state, [], 0)
  end

  @doc "Returns whether a snapshot can restore a renderable player node."
  @spec can_go_back?(t()) :: boolean()
  def can_go_back?(%__MODULE__{} = session) do
    Enum.any?(session.state.snapshots, fn snapshot ->
      snapshot.node_id != session.state.current_node_id and
        renderable_node?(Map.get(session.nodes, snapshot.node_id))
    end)
  end

  defp load_session(%Flow{} = flow, variables) do
    graph = RuntimeGraph.load(flow.id)

    %__MODULE__{
      state: Engine.init(variables, nil),
      nodes: graph.nodes,
      connections: graph.connections,
      flow: flow,
      scene_id: SceneResolver.resolve_scene_id(flow)
    }
  end

  defp advance(session, state, opts, transition_count) do
    state
    |> PlayerEngine.step_until_interactive(session.nodes, session.connections, opts)
    |> resolve_step(session, transition_count)
  end

  defp resolve_step({:flow_jump, _state, _target_flow_id, _skipped}, session, count)
       when count >= @max_flow_transitions do
    {:error, :transition_limit, session}
  end

  defp resolve_step({:flow_return, _state, _skipped}, session, count) when count >= @max_flow_transitions do
    {:error, :transition_limit, session}
  end

  defp resolve_step({:flow_jump, state, target_flow_id, _skipped}, session, count) do
    enter_flow(session, state, target_flow_id, count + 1)
  end

  defp resolve_step({:flow_return, state, _skipped}, session, count) do
    return_from_flow(session, state, count + 1)
  end

  defp resolve_step({:error, state, _skipped}, session, _count) do
    {:error, :advance_failed, %{session | state: state}}
  end

  defp resolve_step({_status, state, _skipped}, session, _count) do
    {:ok, %{session | state: state}}
  end

  defp enter_flow(session, state, target_flow_id, transition_count) do
    case Editor.get_flow_brief(session.flow.project_id, target_flow_id) do
      nil ->
        {:error, {:flow_not_found, target_flow_id}, session}

      target_flow ->
        enter_loaded_flow(session, state, target_flow, transition_count)
    end
  end

  defp enter_loaded_flow(session, state, target_flow, transition_count) do
    target_graph = RuntimeGraph.load(target_flow.id)

    case RuntimeGraph.entry_node_id(target_graph.nodes) do
      nil ->
        {:error, {:target_entry_not_found, target_flow.id}, session}

      entry_id ->
        state =
          state
          |> Engine.push_flow_context(
            state.current_node_id,
            session.nodes,
            session.connections,
            session.flow.name
          )
          |> Map.merge(%{
            current_node_id: entry_id,
            current_flow_id: target_flow.id,
            status: :paused
          })

        target_session = %__MODULE__{
          state: state,
          nodes: target_graph.nodes,
          connections: target_graph.connections,
          flow: target_flow,
          scene_id:
            SceneResolver.resolve_scene_id(target_flow,
              caller_scene_id: session.scene_id
            )
        }

        advance(target_session, state, [], transition_count)
    end
  end

  defp return_from_flow(session, state, transition_count) do
    case Engine.pop_flow_context(state) do
      {:error, :empty_stack} ->
        {:ok, %{session | state: %{state | status: :finished}}}

      {:ok, frame, state} ->
        resume_parent_flow(session, state, frame, transition_count)
    end
  end

  defp resume_parent_flow(session, state, frame, transition_count) do
    case Editor.get_flow_brief(session.flow.project_id, frame.flow_id) do
      nil ->
        {:error, {:flow_not_found, frame.flow_id}, session}

      parent_flow ->
        state = state_after_return(state, frame)

        parent_session = %__MODULE__{
          state: state,
          nodes: frame.nodes,
          connections: frame.connections,
          flow: parent_flow,
          scene_id: SceneResolver.resolve_scene_id(parent_flow)
        }

        advance(parent_session, state, [], transition_count)
    end
  end

  defp state_after_return(state, frame) do
    connection =
      EngineHelpers.find_return_connection(
        frame.connections,
        frame.return_node_id,
        state.current_node_id
      )

    if connection do
      %{
        state
        | current_node_id: connection.target_node_id,
          current_flow_id: frame.flow_id,
          status: :paused
      }
    else
      %{state | status: :finished, current_flow_id: frame.flow_id}
    end
  end

  defp resolve_back_state(session, state) do
    session = runtime_for_state(session, state)

    if renderable_node?(Map.get(session.nodes, state.current_node_id)) do
      {:ok, %{session | state: state}}
    else
      advance(session, state, [], 0)
    end
  end

  defp runtime_for_state(session, %{current_flow_id: flow_id} = state) when flow_id == session.flow.id do
    %{session | state: state}
  end

  defp runtime_for_state(session, %{current_flow_id: flow_id} = state) do
    frame = Enum.find(session.state.call_stack, &(&1.flow_id == flow_id))

    with %{nodes: nodes, connections: connections} <- frame,
         %Flow{} = flow <- Editor.get_flow_brief(session.flow.project_id, flow_id) do
      %__MODULE__{
        state: state,
        nodes: nodes,
        connections: connections,
        flow: flow,
        scene_id: SceneResolver.resolve_scene_id(flow)
      }
    else
      _missing_runtime -> %{session | state: state}
    end
  end

  defp root_session(%__MODULE__{state: %{call_stack: []}} = session), do: session

  defp root_session(session) do
    frame = List.last(session.state.call_stack)

    case Editor.get_flow_brief(session.flow.project_id, frame.flow_id) do
      %Flow{} = flow ->
        %__MODULE__{
          state: session.state,
          nodes: frame.nodes,
          connections: frame.connections,
          flow: flow,
          scene_id: SceneResolver.resolve_scene_id(flow)
        }

      nil ->
        session
    end
  end

  defp renderable_node?(%{type: type}) when type in @renderable_node_types, do: true
  defp renderable_node?(_node), do: false
end
