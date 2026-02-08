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

  alias Storyarn.Flows.Evaluator.{State, ConditionEval, InstructionExec}

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
      execution_path: [start_node_id]
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
      add_console(state, :error, nil, "", "Max steps (#{max}) reached — possible infinite loop")

    {:error, %{state | status: :finished}, :max_steps}
  end

  def step(%State{current_node_id: node_id} = state, nodes, connections) do
    case Map.get(nodes, node_id) do
      nil ->
        state = add_console(state, :error, node_id, "", "Node #{node_id} not found")
        {:error, %{state | status: :finished}, :node_not_found}

      node ->
        state = push_snapshot(state)
        state = %{state | step_count: state.step_count + 1, previous_variables: state.variables}
        evaluate_node(node, state, connections)
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
        execution_path: snapshot.execution_path,
        pending_choices: snapshot.pending_choices,
        status: snapshot.status,
        history: snapshot.history,
        snapshots: rest,
        step_count: max(state.step_count - 1, 0)
    }

    restored = add_console(restored, :info, nil, "", "Stepped back")
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
        execute_response_instruction(selected.instruction, state, node_id)
      else
        state
      end

    state = add_console(state, :info, node_id, "", "Selected: \"#{response_text}\"")

    # Find connection — try response_id as pin, then with "resp_" prefix
    conn =
      find_connection(connections, node_id, response_id) ||
        find_connection(connections, node_id, "resp_#{response_id}")

    case conn do
      nil ->
        state =
          add_console(state, :error, node_id, "", "No connection from response #{response_id}")

        {:error, %{state | status: :finished}, :no_connection}

      conn ->
        advance_to(state, conn.target_node_id)
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
          add_console(
            state,
            :info,
            nil,
            "",
            "User override: #{variable_ref}: #{format_value(old_value)} → #{format_value(new_value)}"
          )

        change = %{variable_ref: variable_ref, old_value: old_value, new_value: new_value}
        state = add_history_entries(state, nil, "", [change], :user_override)

        {:ok, state}
    end
  end

  @doc """
  Reset the debug session to its initial state.
  """
  @spec reset(State.t()) :: State.t()
  def reset(%State{} = state) do
    init(state.initial_variables, state.start_node_id)
  end

  # =============================================================================
  # Node evaluation — dispatches by node type
  # =============================================================================

  defp evaluate_node(%{type: "entry"} = node, state, connections) do
    label = node_label(node)
    state = add_console(state, :info, node.id, label, "Execution started")
    follow_output(state, node.id, label, connections)
  end

  defp evaluate_node(%{type: "exit"} = node, state, _connections) do
    label = node_label(node)
    state = add_console(state, :info, node.id, label, "Execution finished")
    {:finished, %{state | status: :finished}}
  end

  defp evaluate_node(%{type: "hub"} = node, state, connections) do
    label = node_label(node)
    state = add_console(state, :info, node.id, label, "Hub — pass through")
    follow_output(state, node.id, label, connections)
  end

  defp evaluate_node(%{type: "scene"} = node, state, connections) do
    label = node_label(node)
    state = add_console(state, :info, node.id, label, "Scene — pass through")
    follow_output(state, node.id, label, connections)
  end

  defp evaluate_node(%{type: "jump"} = node, state, _connections) do
    label = node_label(node)
    data = node.data || %{}
    hub_id = data["hub_id"] || "unknown"

    state =
      add_console(
        state,
        :info,
        node.id,
        label,
        "Jump to hub #{hub_id} — ending (cross-flow not yet supported)"
      )

    {:finished, %{state | status: :finished}}
  end

  defp evaluate_node(%{type: "subflow"} = node, state, _connections) do
    label = node_label(node)

    state =
      add_console(
        state,
        :info,
        node.id,
        label,
        "Subflow — ending (cross-flow not yet supported)"
      )

    {:finished, %{state | status: :finished}}
  end

  defp evaluate_node(%{type: "dialogue"} = node, state, connections) do
    data = node.data || %{}
    label = node_label(node)

    # 1. Evaluate input_condition if present
    {state, _input_ok} = evaluate_input_condition(data, state, node.id, label)

    # 2. Execute output_instruction if present
    state = execute_output_instruction(data, state, node.id, label)

    # 3. Handle responses
    responses = data["responses"] || []

    if responses == [] do
      state =
        add_console(state, :info, node.id, label, "Dialogue — no responses, following output")

      follow_output(state, node.id, label, connections)
    else
      evaluated = evaluate_response_conditions(responses, state.variables)
      valid_responses = Enum.filter(evaluated, & &1.valid)
      valid_count = length(valid_responses)
      total_count = length(evaluated)

      if valid_count == 1 do
        # Single valid response — auto-select it
        [only] = valid_responses

        state =
          add_console(
            state,
            :info,
            node.id,
            label,
            "Dialogue — auto-selected \"#{only.text}\" (1 of #{total_count} valid)"
          )

        # Execute response instruction if present
        state =
          if is_binary(only[:instruction]) and only[:instruction] != "" do
            execute_response_instruction(only.instruction, state, node.id)
          else
            state
          end

        # Follow connection from the response pin
        conn =
          find_connection(connections, node.id, only.id) ||
            find_connection(connections, node.id, "resp_#{only.id}")

        case conn do
          nil ->
            state =
              add_console(state, :error, node.id, label, "No connection from response #{only.id}")

            {:finished, %{state | status: :finished}}

          conn ->
            advance_to(state, conn.target_node_id)
        end
      else
        state =
          add_console(
            state,
            :info,
            node.id,
            label,
            "Dialogue — waiting for response (#{valid_count} of #{total_count} valid)"
          )

        pending = %{node_id: node.id, responses: evaluated}
        {:waiting_input, %{state | status: :waiting_input, pending_choices: pending}}
      end
    end
  end

  defp evaluate_node(%{type: "condition"} = node, state, connections) do
    data = node.data || %{}
    label = node_label(node)
    condition = data["condition"] || %{"logic" => "all", "rules" => []}
    switch_mode = data["switch_mode"] || false

    if switch_mode do
      evaluate_switch_condition(node.id, label, condition, state, connections)
    else
      evaluate_boolean_condition(node.id, label, condition, state, connections)
    end
  end

  defp evaluate_node(%{type: "instruction"} = node, state, connections) do
    data = node.data || %{}
    label = node_label(node)
    assignments = data["assignments"] || []

    {:ok, new_variables, changes, errors} = InstructionExec.execute(assignments, state.variables)
    state = %{state | variables: new_variables}

    # Log each change to console + history
    state =
      Enum.reduce(changes, state, fn change, acc ->
        add_console(
          acc,
          :info,
          node.id,
          label,
          "#{change.variable_ref}: #{format_value(change.old_value)} → #{format_value(change.new_value)} (#{change.operator})"
        )
      end)

    state = add_history_entries(state, node.id, label, changes, :instruction)

    # Log errors
    state =
      Enum.reduce(errors, state, fn error, acc ->
        add_console(acc, :error, node.id, label, "#{error.variable_ref}: #{error.reason}")
      end)

    state =
      if changes == [] and errors == [] do
        add_console(state, :info, node.id, label, "Instruction — no assignments")
      else
        state
      end

    follow_output(state, node.id, label, connections)
  end

  # Unknown node type — pass through
  defp evaluate_node(node, state, connections) do
    label = node_label(node)

    state =
      add_console(
        state,
        :warning,
        node.id,
        label,
        "Unknown node type: #{node.type} — pass through"
      )

    follow_output(state, node.id, label, connections)
  end

  # =============================================================================
  # Condition evaluation
  # =============================================================================

  defp evaluate_boolean_condition(node_id, label, condition, state, connections) do
    {result, rule_results} = ConditionEval.evaluate(condition, state.variables)
    branch = if result, do: "true", else: "false"
    detail = format_rule_summary(rule_results)
    level = if result, do: :info, else: :warning

    state =
      add_console_with_rules(
        state,
        level,
        node_id,
        label,
        "Condition → #{branch}#{detail}",
        rule_results
      )

    case find_connection(connections, node_id, branch) do
      nil ->
        state =
          add_console(state, :error, node_id, label, "No connection from pin \"#{branch}\"")

        {:finished, %{state | status: :finished}}

      conn ->
        advance_to(state, conn.target_node_id)
    end
  end

  defp evaluate_switch_condition(node_id, label, condition, state, connections) do
    rules = condition["rules"] || []

    {matched_pin, state} =
      Enum.reduce_while(rules, {nil, state}, fn rule, {_pin, acc_state} ->
        rule_result = ConditionEval.evaluate_rule(rule, acc_state.variables)
        rule_label = rule["label"] || rule["id"] || "unnamed"

        if rule_result.passed do
          acc_state =
            add_console(acc_state, :info, node_id, label, "Switch → case \"#{rule_label}\" matched")

          {:halt, {rule["id"], acc_state}}
        else
          acc_state =
            add_console(
              acc_state,
              :info,
              node_id,
              label,
              "Switch → case \"#{rule_label}\" did not match"
            )

          {:cont, {nil, acc_state}}
        end
      end)

    state =
      if is_nil(matched_pin) do
        add_console(state, :warning, node_id, label, "Switch — no case matched, following default")
      else
        state
      end

    pin = matched_pin || "default"

    conn =
      find_connection(connections, node_id, pin) ||
        if(pin != "default", do: find_connection(connections, node_id, "default"))

    case conn do
      nil ->
        state = add_console(state, :error, node_id, label, "No connection from pin \"#{pin}\"")
        {:finished, %{state | status: :finished}}

      conn ->
        advance_to(state, conn.target_node_id)
    end
  end

  # =============================================================================
  # Dialogue helpers
  # =============================================================================

  defp evaluate_input_condition(data, state, node_id, label) do
    input_condition = data["input_condition"]

    if is_binary(input_condition) and input_condition != "" do
      {result, rule_results} = ConditionEval.evaluate_string(input_condition, state.variables)

      if result do
        {state, true}
      else
        detail = format_rule_summary(rule_results)

        state =
          add_console_with_rules(
            state,
            :warning,
            node_id,
            label,
            "Input condition failed#{detail}",
            rule_results
          )

        {state, false}
      end
    else
      {state, true}
    end
  end

  defp execute_output_instruction(data, state, node_id, label) do
    output_instruction = data["output_instruction"]

    if is_binary(output_instruction) and output_instruction != "" do
      {:ok, new_variables, changes, errors} =
        InstructionExec.execute_string(output_instruction, state.variables)

      state = %{state | variables: new_variables}

      state =
        Enum.reduce(changes, state, fn change, acc ->
          add_console(
            acc,
            :info,
            node_id,
            label,
            "Output instruction: #{change.variable_ref}: #{format_value(change.old_value)} → #{format_value(change.new_value)}"
          )
        end)

      state = add_history_entries(state, node_id, label, changes, :instruction)

      Enum.reduce(errors, state, fn error, acc ->
        add_console(
          acc,
          :error,
          node_id,
          label,
          "Output instruction error: #{error.variable_ref}: #{error.reason}"
        )
      end)
    else
      state
    end
  end

  defp execute_response_instruction(instruction_json, state, node_id) do
    {:ok, new_variables, changes, errors} =
      InstructionExec.execute_string(instruction_json, state.variables)

    state = %{state | variables: new_variables}

    state =
      Enum.reduce(changes, state, fn change, acc ->
        add_console(
          acc,
          :info,
          node_id,
          "",
          "Response instruction: #{change.variable_ref}: #{format_value(change.old_value)} → #{format_value(change.new_value)}"
        )
      end)

    state = add_history_entries(state, node_id, "", changes, :instruction)

    Enum.reduce(errors, state, fn error, acc ->
      add_console(acc, :error, node_id, "", "Response instruction error: #{error.reason}")
    end)
  end

  defp evaluate_response_conditions(responses, variables) do
    Enum.map(responses, fn resp ->
      condition_string = resp["condition"]

      {valid, rule_results} =
        if is_binary(condition_string) and condition_string != "" do
          ConditionEval.evaluate_string(condition_string, variables)
        else
          {true, []}
        end

      %{
        id: resp["id"],
        text: resp["text"] || "",
        valid: valid,
        rule_details: rule_results,
        instruction: resp["instruction"]
      }
    end)
  end

  # =============================================================================
  # Helpers
  # =============================================================================

  defp advance_to(state, target_node_id) do
    {:ok,
     %{
       state
       | current_node_id: target_node_id,
         status: :paused,
         pending_choices: nil,
         execution_path: state.execution_path ++ [target_node_id]
     }}
  end

  defp follow_output(state, node_id, label, connections) do
    conn =
      find_connection(connections, node_id, "default") ||
        find_connection(connections, node_id, "output")

    case conn do
      nil ->
        state = add_console(state, :error, node_id, label, "No outgoing connection")
        {:finished, %{state | status: :finished}}

      conn ->
        advance_to(state, conn.target_node_id)
    end
  end

  defp push_snapshot(state) do
    snapshot = %{
      node_id: state.current_node_id,
      variables: state.variables,
      execution_path: state.execution_path,
      pending_choices: state.pending_choices,
      status: state.status,
      history: state.history
    }

    %{state | snapshots: [snapshot | state.snapshots]}
  end

  defp find_connection(connections, source_node_id, source_pin) do
    Enum.find(connections, fn conn ->
      conn.source_node_id == source_node_id and conn.source_pin == source_pin
    end)
  end

  defp node_label(%{data: %{"text" => text}}) when is_binary(text) and text != "" do
    text
    |> String.replace(~r/<[^>]*>/, "")
    |> String.trim()
    |> String.slice(0, 40)
    |> case do
      "" -> nil
      clean -> clean
    end
  end

  defp node_label(_node), do: nil

  defp add_console(state, level, node_id, node_label, message) do
    entry = %{
      ts: elapsed_ms(state),
      level: level,
      node_id: node_id,
      node_label: node_label || "",
      message: message,
      rule_details: nil
    }

    %{state | console: state.console ++ [entry]}
  end

  defp add_console_with_rules(state, level, node_id, node_label, message, rule_details) do
    entry = %{
      ts: elapsed_ms(state),
      level: level,
      node_id: node_id,
      node_label: node_label || "",
      message: message,
      rule_details: rule_details
    }

    %{state | console: state.console ++ [entry]}
  end

  defp elapsed_ms(%{started_at: nil}), do: 0

  defp elapsed_ms(%{started_at: started_at}) do
    System.monotonic_time(:millisecond) - started_at
  end

  defp format_rule_summary([]), do: ""

  defp format_rule_summary(results) do
    failed_count = Enum.count(results, &(!&1.passed))
    total = length(results)

    if failed_count > 0 do
      " (#{total - failed_count} of #{total} rules passed)"
    else
      " (all #{total} rules passed)"
    end
  end

  defp add_history_entries(state, _node_id, _node_label, [], _source), do: state

  defp add_history_entries(state, node_id, node_label, changes, source) do
    entries =
      Enum.map(changes, fn change ->
        %{
          ts: elapsed_ms(state),
          node_id: node_id,
          node_label: node_label || "",
          variable_ref: change.variable_ref,
          old_value: change.old_value,
          new_value: change.new_value,
          source: source
        }
      end)

    %{state | history: state.history ++ entries}
  end

  defp format_value(nil), do: "nil"
  defp format_value(v) when is_binary(v), do: v
  defp format_value(v), do: inspect(v)
end
