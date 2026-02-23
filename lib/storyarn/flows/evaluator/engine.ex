defmodule Storyarn.Flows.Evaluator.Engine do
  @moduledoc """
  Pure functional state machine for the flow debugger.

  Receives the current debug state, a map of nodes, and a list of connections.
  Returns the new state. No DB access — all data is passed in by the caller.

  ## Usage

      state = Engine.init(variables, start_node_id)
      {:ok, state} = Engine.step(state, nodes, connections)
      {:waiting_input, state} = Engine.step(state, nodes, connections)
      {:ok, state} = Engine.choose_response(state, response_id, connections)
      {:finished, state} = Engine.step(state, nodes, connections)

  ## Node map format

  Nodes must be a map keyed by integer id:

      %{1 => %{id: 1, type: "entry", data: %{}}, ...}

  ## Connection list format

      [%{source_node_id: 1, source_pin: "default", target_node_id: 2, target_pin: "input"}, ...]
  """

  alias Storyarn.Flows.Evaluator.{EngineHelpers, State}

  alias Storyarn.Flows.Evaluator.NodeEvaluators.{
    ConditionNodeEvaluator,
    DialogueEvaluator,
    ExitEvaluator,
    InstructionEvaluator
  }

  # =============================================================================
  # Public API
  # =============================================================================

  @doc """
  Initialize a debug session.

  `variables` is a pre-built map of `%{"sheet.var" => %{value: ..., block_type: ..., ...}}`.
  The caller (LiveView handler) is responsible for loading variables from the DB.
  """
  @spec init(map(), integer()) :: State.t()
  def init(variables, start_node_id) do
    now = System.monotonic_time(:millisecond)

    %State{
      start_node_id: start_node_id,
      current_node_id: start_node_id,
      status: :paused,
      variables: variables,
      initial_variables: variables,
      previous_variables: variables,
      started_at: now,
      console: [
        %{
          ts: 0,
          level: :info,
          node_id: nil,
          node_label: "",
          message: "Debug session started",
          rule_details: nil
        }
      ],
      execution_path: [start_node_id],
      execution_log: [%{node_id: start_node_id, depth: 0}]
    }
  end

  @doc """
  Advance one node in the flow.

  Returns:
  - `{:ok, state}` — moved to next node, ready for another step
  - `{:waiting_input, state}` — dialogue with choices, call `choose_response/3`
  - `{:finished, state}` — execution ended (exit node, jump, or error)
  - `{:error, state, reason}` — unrecoverable error
  """
  @spec step(State.t(), map(), list()) ::
          {:ok, State.t()}
          | {:waiting_input, State.t()}
          | {:finished, State.t()}
          | {:flow_jump, State.t(), integer()}
          | {:flow_return, State.t()}
          | {:step_limit, State.t()}
          | {:error, State.t(), atom()}
  def step(%State{status: :finished} = state, _nodes, _connections) do
    {:finished, state}
  end

  def step(%State{status: :waiting_input} = state, _nodes, _connections) do
    {:waiting_input, state}
  end

  def step(%State{step_count: count, max_steps: max} = state, _nodes, _connections)
      when count >= max do
    state =
      EngineHelpers.add_console(
        state,
        :warning,
        nil,
        "",
        "Step limit (#{max}) reached — possible infinite loop. Continue or reset."
      )

    {:step_limit, %{state | status: :paused}}
  end

  def step(%State{current_node_id: node_id} = state, nodes, connections) do
    case Map.get(nodes, node_id) do
      nil ->
        state = EngineHelpers.add_console(state, :error, node_id, "", "Node #{node_id} not found")
        {:error, %{state | status: :finished}, :node_not_found}

      node ->
        state = push_snapshot(state)
        state = %{state | step_count: state.step_count + 1, previous_variables: state.variables}
        evaluate_node(node, state, connections, nodes)
    end
  end

  @doc """
  Undo the last step by restoring from the snapshots stack.
  """
  @spec step_back(State.t()) :: {:ok, State.t()} | {:error, :no_history}
  def step_back(%State{snapshots: []}) do
    {:error, :no_history}
  end

  def step_back(%State{snapshots: [snapshot | rest]} = state) do
    restored = %{
      state
      | current_node_id: snapshot.node_id,
        variables: snapshot.variables,
        previous_variables: snapshot.previous_variables,
        execution_path: snapshot.execution_path,
        execution_log: snapshot.execution_log,
        pending_choices: snapshot.pending_choices,
        status: snapshot.status,
        history: snapshot.history,
        call_stack: snapshot.call_stack,
        current_flow_id: snapshot.current_flow_id,
        snapshots: rest,
        step_count: max(state.step_count - 1, 0)
    }

    restored = EngineHelpers.add_console(restored, :info, nil, "", "Stepped back")
    {:ok, restored}
  end

  @doc """
  User selects a dialogue response. Executes the response's instruction (if any)
  and advances to the next node via the response's output pin.
  """
  @spec choose_response(State.t(), String.t(), list()) ::
          {:ok, State.t()} | {:error, State.t(), atom()}
  def choose_response(
        %State{status: :waiting_input, pending_choices: %{node_id: node_id} = choices} = state,
        response_id,
        connections
      ) do
    # Find the selected response to get its instruction and label
    selected = Enum.find(choices.responses, fn r -> r.id == response_id end)
    response_text = if selected, do: selected.text, else: response_id

    # Execute response instruction if present
    state =
      if selected && is_binary(selected[:instruction]) && selected[:instruction] != "" do
        DialogueEvaluator.execute_response_instruction(selected.instruction, state, node_id)
      else
        state
      end

    state = EngineHelpers.add_console(state, :info, node_id, "", "Selected: \"#{response_text}\"")

    # Find connection — try response_id as pin, then with "resp_" prefix
    conn =
      EngineHelpers.find_connection(connections, node_id, response_id) ||
        EngineHelpers.find_connection(connections, node_id, "resp_#{response_id}")

    case conn do
      nil ->
        state =
          EngineHelpers.add_console(
            state,
            :error,
            node_id,
            "",
            "No connection from response #{response_id}"
          )

        {:error, %{state | status: :finished}, :no_connection}

      conn ->
        EngineHelpers.advance_to(state, conn.target_node_id)
    end
  end

  def choose_response(state, _response_id, _connections) do
    {:error, state, :not_waiting_input}
  end

  @doc """
  Manually set a variable value (user override in the debug panel).

  Updates the variable value, sets source to `:user_override`, and adds
  console + history entries to track the change.
  """
  @spec set_variable(State.t(), String.t(), any()) :: {:ok, State.t()} | {:error, :not_found}
  def set_variable(%State{} = state, variable_ref, new_value) do
    case Map.get(state.variables, variable_ref) do
      nil ->
        {:error, :not_found}

      var ->
        old_value = var.value
        updated_var = %{var | value: new_value, previous_value: old_value, source: :user_override}
        variables = Map.put(state.variables, variable_ref, updated_var)

        state = %{state | variables: variables}

        state =
          EngineHelpers.add_console(
            state,
            :info,
            nil,
            "",
            "User override: #{variable_ref}: #{EngineHelpers.format_value(old_value)} → #{EngineHelpers.format_value(new_value)}"
          )

        change = %{variable_ref: variable_ref, old_value: old_value, new_value: new_value}
        state = EngineHelpers.add_history_entries(state, nil, "", [change], :user_override)

        {:ok, state}
    end
  end

  @doc """
  Reset the debug session to its initial state.
  Preserves breakpoints and current_flow_id across resets.
  Clears call stack.
  """
  @spec reset(State.t()) :: State.t()
  def reset(%State{} = state) do
    new_state = init(state.initial_variables, state.start_node_id)
    %{new_state | breakpoints: state.breakpoints, current_flow_id: state.current_flow_id}
  end

  @doc """
  Extend the step limit by 1000 steps.
  Called when the user chooses to continue past the step limit.
  """
  @spec extend_step_limit(State.t()) :: State.t()
  def extend_step_limit(%State{} = state) do
    new_max = state.max_steps + 1000

    state
    |> EngineHelpers.add_console(:info, nil, "", "Step limit extended to #{new_max}")
    |> Map.put(:max_steps, new_max)
  end

  # =============================================================================
  # Cross-flow call stack
  # =============================================================================

  @doc """
  Push the current flow context onto the call stack before entering a sub-flow.

  Saves: current flow_id, the return node (subflow/exit node that triggered the jump),
  the current nodes map, connections, and execution path — everything needed to
  resume after returning.
  """
  @spec push_flow_context(State.t(), integer(), map(), list(), String.t() | nil) :: State.t()
  def push_flow_context(%State{} = state, return_node_id, nodes, connections, flow_name \\ nil) do
    frame = %{
      flow_id: state.current_flow_id,
      flow_name: flow_name,
      return_node_id: return_node_id,
      nodes: nodes,
      connections: connections,
      execution_path: state.execution_path
    }

    %{state | call_stack: [frame | state.call_stack]}
  end

  @doc """
  Pop the most recent flow context from the call stack (returning from a sub-flow).

  Returns `{:ok, frame, updated_state}` or `{:error, :empty_stack}`.
  """
  @spec pop_flow_context(State.t()) :: {:ok, map(), State.t()} | {:error, :empty_stack}
  def pop_flow_context(%State{call_stack: []}), do: {:error, :empty_stack}

  def pop_flow_context(%State{call_stack: [frame | rest]} = state) do
    {:ok, frame, %{state | call_stack: rest}}
  end

  # =============================================================================
  # Breakpoints
  # =============================================================================

  @doc """
  Toggle a breakpoint on/off for a node.
  """
  @spec toggle_breakpoint(State.t(), integer()) :: State.t()
  def toggle_breakpoint(%State{} = state, node_id) do
    breakpoints =
      if MapSet.member?(state.breakpoints, node_id) do
        MapSet.delete(state.breakpoints, node_id)
      else
        MapSet.put(state.breakpoints, node_id)
      end

    %{state | breakpoints: breakpoints}
  end

  @doc """
  Check if a node has a breakpoint set.
  """
  @spec has_breakpoint?(State.t(), integer()) :: boolean()
  def has_breakpoint?(%State{} = state, node_id) do
    MapSet.member?(state.breakpoints, node_id)
  end

  @doc """
  Check if execution is currently paused at a breakpoint.
  """
  @spec at_breakpoint?(State.t()) :: boolean()
  def at_breakpoint?(%State{current_node_id: nil}), do: false

  def at_breakpoint?(%State{} = state) do
    MapSet.member?(state.breakpoints, state.current_node_id)
  end

  @doc """
  Add a console entry indicating execution paused at a breakpoint.
  """
  @spec add_breakpoint_hit(State.t(), integer()) :: State.t()
  def add_breakpoint_hit(%State{} = state, node_id) do
    EngineHelpers.add_console(state, :warning, node_id, "", "Paused at breakpoint")
  end

  @doc """
  Add a console entry from outside the engine (e.g., handler-level warnings).
  """
  @spec add_console_entry(State.t(), atom(), integer() | nil, String.t(), String.t()) :: State.t()
  def add_console_entry(%State{} = state, level, node_id, node_label, message) do
    EngineHelpers.add_console(state, level, node_id, node_label, message)
  end

  # =============================================================================
  # Node evaluation — dispatches by node type
  # =============================================================================

  defp evaluate_node(%{type: "entry"} = node, state, connections, _nodes) do
    label = EngineHelpers.node_label(node)
    state = EngineHelpers.add_console(state, :info, node.id, label, "Execution started")
    EngineHelpers.follow_output(state, node.id, label, connections)
  end

  defp evaluate_node(%{type: "exit"} = node, state, _connections, _nodes) do
    ExitEvaluator.evaluate(node, state)
  end

  defp evaluate_node(%{type: "hub"} = node, state, connections, _nodes) do
    label = EngineHelpers.node_label(node)
    state = EngineHelpers.add_console(state, :info, node.id, label, "Hub — pass through")
    EngineHelpers.follow_output(state, node.id, label, connections)
  end

  defp evaluate_node(%{type: "scene"} = node, state, connections, _nodes) do
    label = EngineHelpers.node_label(node)
    state = EngineHelpers.add_console(state, :info, node.id, label, "Scene — pass through")
    EngineHelpers.follow_output(state, node.id, label, connections)
  end

  defp evaluate_node(%{type: "jump"} = node, state, _connections, nodes) do
    label = EngineHelpers.node_label(node)
    data = node.data || %{}
    target_hub_id = data["target_hub_id"]

    if is_nil(target_hub_id) or target_hub_id == "" do
      state =
        EngineHelpers.add_console(
          state,
          :error,
          node.id,
          label,
          "Jump node has no target_hub_id configured"
        )

      {:finished, %{state | status: :finished}}
    else
      case find_hub_by_hub_id(nodes, target_hub_id) do
        nil ->
          state =
            EngineHelpers.add_console(
              state,
              :error,
              node.id,
              label,
              "Jump target hub \"#{target_hub_id}\" not found in this flow"
            )

          {:finished, %{state | status: :finished}}

        hub_node_id ->
          state =
            EngineHelpers.add_console(
              state,
              :info,
              node.id,
              label,
              "Jump → hub \"#{target_hub_id}\" (node #{hub_node_id})"
            )

          EngineHelpers.advance_to(state, hub_node_id)
      end
    end
  end

  defp evaluate_node(%{type: "subflow"} = node, state, _connections, _nodes) do
    label = EngineHelpers.node_label(node)
    data = node.data || %{}

    case data["referenced_flow_id"] do
      nil ->
        state =
          EngineHelpers.add_console(
            state,
            :error,
            node.id,
            label,
            "Subflow node has no referenced_flow_id"
          )

        {:finished, %{state | status: :finished}}

      flow_id ->
        state =
          EngineHelpers.add_console(
            state,
            :info,
            node.id,
            label,
            "Subflow → entering flow #{flow_id}"
          )

        {:flow_jump, state, flow_id}
    end
  end

  defp evaluate_node(%{type: "dialogue"} = node, state, connections, _nodes) do
    DialogueEvaluator.evaluate(node, state, connections)
  end

  defp evaluate_node(%{type: "condition"} = node, state, connections, _nodes) do
    ConditionNodeEvaluator.evaluate(node, state, connections)
  end

  defp evaluate_node(%{type: "instruction"} = node, state, connections, _nodes) do
    InstructionEvaluator.evaluate(node, state, connections)
  end

  # Unknown/deprecated node type — log warning and skip via default output
  defp evaluate_node(node, state, connections, _nodes) do
    label = EngineHelpers.node_label(node)

    state =
      EngineHelpers.add_console(
        state,
        :warning,
        node.id,
        label,
        "Unknown node type '#{node.type}' — skipping"
      )

    case EngineHelpers.find_connection(connections, node.id, "output") do
      nil ->
        EngineHelpers.follow_output(state, node.id, label, connections)

      conn ->
        EngineHelpers.advance_to(state, conn.target_node_id)
    end
  end

  # =============================================================================
  # Private helpers
  # =============================================================================

  defp push_snapshot(state) do
    snapshot = %{
      node_id: state.current_node_id,
      variables: state.variables,
      previous_variables: state.previous_variables,
      execution_path: state.execution_path,
      execution_log: state.execution_log,
      pending_choices: state.pending_choices,
      status: state.status,
      history: state.history,
      call_stack: state.call_stack,
      current_flow_id: state.current_flow_id
    }

    %{state | snapshots: [snapshot | state.snapshots]}
  end

  defp find_hub_by_hub_id(nodes, target_hub_id) do
    Enum.find_value(nodes, fn {node_id, node} ->
      if node.type == "hub" and is_map(node.data) and node.data["hub_id"] == target_hub_id do
        node_id
      end
    end)
  end
end
