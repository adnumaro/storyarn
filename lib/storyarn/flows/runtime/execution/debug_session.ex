defmodule Storyarn.Flows.DebugSession do
  @moduledoc """
  Application service and state transitions for the Flow debugger.

  This module owns runtime graph changes, entry selection, stepping,
  breakpoints, call-stack transitions, resets and variable overrides. Phoenix
  adapters only schedule timers, push visual events and perform navigation.
  """

  use Gettext, backend: Storyarn.Gettext

  alias Storyarn.Flows.Evaluator.Engine
  alias Storyarn.Flows.Evaluator.EngineHelpers
  alias Storyarn.Flows.Evaluator.State
  alias Storyarn.Flows.Flow
  alias Storyarn.Flows.Runtime.Events
  alias Storyarn.Flows.RuntimeGraph
  alias Storyarn.Flows.RuntimeVariables

  @type graph :: RuntimeGraph.t()
  @type step_result ::
          {:continue, State.t(), graph(), boolean()}
          | {:navigate, State.t(), graph(), pos_integer()}
  @type auto_action :: :continue | :stop | :wait
  @type auto_step_result ::
          {:continue, State.t(), graph(), boolean(), auto_action()}
          | {:navigate, State.t(), graph(), pos_integer()}

  @doc "Starts a complete debug session and emits the Flow-owned start fact."
  @spec start(term(), Flow.t()) ::
          {:ok, %{state: State.t(), graph: graph()}} | {:error, :no_entry_node}
  def start(scope_or_user, %Flow{} = flow) do
    graph = RuntimeGraph.load(flow.id)

    with {:ok, session} <- initialize(RuntimeVariables.build(flow.project_id), graph, flow.id) do
      Events.debug_started(scope_or_user, flow)
      {:ok, session}
    end
  end

  @doc "Initializes a debug session from already-loaded runtime inputs."
  @spec initialize(map(), graph(), pos_integer()) ::
          {:ok, %{state: State.t(), graph: graph()}} | {:error, :no_entry_node}
  def initialize(variables, graph, flow_id) do
    case RuntimeGraph.entry_node_id(graph.nodes) do
      nil ->
        {:error, :no_entry_node}

      entry_node_id ->
        state = variables |> Engine.init(entry_node_id) |> Map.put(:current_flow_id, flow_id)
        {:ok, %{state: state, graph: graph}}
    end
  end

  @doc "Selects and resets to another valid start node."
  @spec select_start_node(State.t(), map(), integer() | String.t()) ::
          {:ok, State.t()} | {:error, :invalid_node}
  def select_start_node(state, nodes, node_id) do
    with {:ok, normalized_node_id} <- normalize_node_id(node_id),
         true <- Map.has_key?(nodes, normalized_node_id) do
      new_state = Engine.reset(%{state | start_node_id: normalized_node_id})
      {:ok, new_state}
    else
      _invalid -> {:error, :invalid_node}
    end
  end

  @doc "Advances the debugger and resolves cross-Flow call-stack transitions."
  @spec step(State.t(), map(), list(), String.t() | nil) :: step_result()
  def step(state, nodes, connections, flow_name) do
    step(state, nodes, connections, flow_name, &RuntimeGraph.load/1)
  end

  @doc false
  @spec step(State.t(), map(), list(), String.t() | nil, (pos_integer() -> graph())) ::
          step_result()
  def step(state, nodes, connections, flow_name, graph_loader) when is_function(graph_loader, 1) do
    state
    |> Engine.step(nodes, connections)
    |> resolve_step_result(%{nodes: nodes, connections: connections}, flow_name, graph_loader)
  end

  @doc "Runs an automatic step and decides whether playback continues, waits or stops."
  @spec auto_step(State.t(), map(), list(), String.t() | nil) :: auto_step_result()
  def auto_step(%State{status: :finished} = state, nodes, connections, _flow_name) do
    {:continue, state, %{nodes: nodes, connections: connections}, false, :stop}
  end

  def auto_step(%State{status: :waiting_input} = state, nodes, connections, _flow_name) do
    {:continue, state, %{nodes: nodes, connections: connections}, false, :wait}
  end

  def auto_step(state, nodes, connections, flow_name) do
    case step(state, nodes, connections, flow_name) do
      {:navigate, _state, _graph, _flow_id} = navigation ->
        navigation

      {:continue, new_state, graph, step_limit_reached?} ->
        {new_state, action} = auto_action(new_state, step_limit_reached?)
        {:continue, new_state, graph, step_limit_reached?, action}
    end
  end

  @doc "Restores the previous evaluator snapshot."
  @spec step_back(State.t()) :: {:ok, State.t()} | {:error, :no_history}
  defdelegate step_back(state), to: Engine

  @doc "Applies a selected response to a waiting debugger session."
  @spec choose_response(State.t(), String.t(), list()) ::
          {:ok, State.t()} | {:error, State.t(), atom()}
  defdelegate choose_response(state, response_id, connections), to: Engine

  @doc "Resets the session, returning to the root Flow when currently nested."
  @spec reset(State.t(), map(), list()) ::
          {:continue, State.t(), graph()} | {:navigate, State.t(), graph(), pos_integer()}
  def reset(%State{call_stack: []} = state, nodes, connections) do
    {:continue, Engine.reset(state), %{nodes: nodes, connections: connections}}
  end

  def reset(%State{} = state, _nodes, _connections) do
    root_frame = List.last(state.call_stack)
    new_state = state |> Engine.reset() |> Map.put(:current_flow_id, root_frame.flow_id)
    graph = %{nodes: root_frame.nodes, connections: root_frame.connections}

    {:navigate, new_state, graph, root_frame.flow_id}
  end

  @doc "Returns the semantic empty state for a stopped debug session."
  @spec stop() :: %{state: nil, graph: graph()}
  def stop, do: %{state: nil, graph: RuntimeGraph.empty()}

  @doc "Coerces and applies a debugger variable override."
  @spec set_variable(State.t(), String.t(), term()) ::
          {:ok, State.t()} | {:error, :not_found}
  def set_variable(state, key, raw_value) do
    block_type = get_in(state.variables, [key, :block_type])

    state_and_value =
      case RuntimeVariables.coerce_override(raw_value, block_type) do
        {:ok, value} ->
          {state, value}

        {:warning, value, :invalid_number} ->
          warning =
            dgettext("flows", "Invalid number \"%{value}\", using 0",
              value: raw_value |> to_string() |> String.slice(0, 20)
            )

          {Engine.add_console_entry(state, :warning, nil, "", warning), value}
      end

    {state, value} = state_and_value
    Engine.set_variable(state, key, value)
  end

  @doc "Extends the debugger step limit."
  @spec extend_step_limit(State.t()) :: State.t()
  defdelegate extend_step_limit(state), to: Engine

  @doc "Toggles a breakpoint when the node id is valid."
  @spec toggle_breakpoint(State.t(), integer() | String.t()) ::
          {:ok, State.t()} | {:error, :invalid_node}
  def toggle_breakpoint(state, node_id) do
    case normalize_node_id(node_id) do
      {:ok, normalized_node_id} -> {:ok, Engine.toggle_breakpoint(state, normalized_node_id)}
      :error -> {:error, :invalid_node}
    end
  end

  defp resolve_step_result({:flow_jump, state, target_flow_id}, current_graph, flow_name, graph_loader) do
    return_node_id = state.current_node_id

    state =
      Engine.push_flow_context(
        state,
        return_node_id,
        current_graph.nodes,
        current_graph.connections,
        flow_name
      )

    target_graph = graph_loader.(target_flow_id)

    case RuntimeGraph.entry_node_id(target_graph.nodes) do
      nil ->
        {:continue, %{state | status: :finished}, current_graph, false}

      entry_node_id ->
        log_entry = %{node_id: entry_node_id, depth: length(state.call_stack)}

        state = %{
          state
          | current_node_id: entry_node_id,
            current_flow_id: target_flow_id,
            execution_path: [entry_node_id | state.execution_path],
            execution_log: [log_entry | state.execution_log]
        }

        {:navigate, state, target_graph, target_flow_id}
    end
  end

  defp resolve_step_result({:flow_return, state}, current_graph, _flow_name, _graph_loader) do
    case Engine.pop_flow_context(state) do
      {:error, :empty_stack} ->
        {:continue, %{state | status: :finished}, current_graph, false}

      {:ok, frame, state} ->
        state = %{state | current_flow_id: frame.flow_id}

        state =
          case EngineHelpers.find_return_connection(
                 frame.connections,
                 frame.return_node_id,
                 state.current_node_id
               ) do
            nil ->
              %{state | status: :finished}

            next_connection ->
              log_entry = %{
                node_id: next_connection.target_node_id,
                depth: length(state.call_stack)
              }

              %{
                state
                | current_node_id: next_connection.target_node_id,
                  execution_path: [next_connection.target_node_id | frame.execution_path],
                  execution_log: [log_entry | state.execution_log]
              }
          end

        graph = %{nodes: frame.nodes, connections: frame.connections}
        {:navigate, state, graph, frame.flow_id}
    end
  end

  defp resolve_step_result({:step_limit, state}, graph, _flow_name, _graph_loader), do: {:continue, state, graph, true}

  defp resolve_step_result({_status, state}, graph, _flow_name, _graph_loader), do: {:continue, state, graph, false}

  defp resolve_step_result({:error, state, _reason}, graph, _flow_name, _graph_loader),
    do: {:continue, state, graph, false}

  defp auto_action(state, true), do: {state, :stop}

  defp auto_action(%State{status: status} = state, false) when status in [:finished, :waiting_input] do
    action = if status == :finished, do: :stop, else: :wait
    {state, action}
  end

  defp auto_action(state, false) do
    if Engine.at_breakpoint?(state) do
      {Engine.add_breakpoint_hit(state, state.current_node_id), :stop}
    else
      {state, :continue}
    end
  end

  defp normalize_node_id(node_id) when is_integer(node_id), do: {:ok, node_id}

  defp normalize_node_id(node_id) when is_binary(node_id) do
    case Integer.parse(node_id) do
      {parsed, ""} -> {:ok, parsed}
      _invalid -> :error
    end
  end

  defp normalize_node_id(_node_id), do: :error
end
