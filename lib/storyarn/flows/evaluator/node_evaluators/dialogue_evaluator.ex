defmodule Storyarn.Flows.Evaluator.NodeEvaluators.DialogueEvaluator do
  @moduledoc """
  Handles evaluation of `dialogue` nodes in the flow debugger.

  Evaluates response conditions, auto-selects responses when only one is valid,
  or suspends execution waiting for user input when multiple valid responses exist.
  Also handles response instructions (variable assignments triggered on selection).
  """

  alias Storyarn.Flows.Evaluator.{ConditionEval, EngineHelpers, InstructionExec}

  @doc """
  Evaluate a dialogue node. Returns one of:
  - `{:ok, state}` — auto-advanced to next node (no choices or single valid response)
  - `{:waiting_input, state}` — user must choose a response
  - `{:finished, state}` — no valid next node found
  """
  def evaluate(node, state, connections) do
    data = node.data || %{}
    label = EngineHelpers.node_label(node)
    responses = data["responses"] || []
    handle_dialogue_responses(responses, state, node.id, label, connections)
  end

  @doc """
  Execute a response instruction (JSON string of assignments) and update state.
  """
  def execute_response_instruction(instruction_json, state, node_id) do
    {:ok, new_variables, changes, errors} =
      InstructionExec.execute_string(instruction_json, state.variables)

    state = %{state | variables: new_variables}

    state =
      Enum.reduce(changes, state, fn change, acc ->
        EngineHelpers.add_console(
          acc,
          :info,
          node_id,
          "",
          "Response instruction: #{change.variable_ref}: #{EngineHelpers.format_value(change.old_value)} → #{EngineHelpers.format_value(change.new_value)}"
        )
      end)

    state = EngineHelpers.add_history_entries(state, node_id, "", changes, :instruction)

    Enum.reduce(errors, state, fn error, acc ->
      EngineHelpers.add_console(
        acc,
        :error,
        node_id,
        "",
        "Response instruction error: #{error.reason}"
      )
    end)
  end

  @doc """
  Execute structured response assignments and update state.
  """
  def execute_response_assignments(assignments, state, node_id) do
    {:ok, new_variables, changes, errors} =
      InstructionExec.execute(assignments, state.variables)

    state = %{state | variables: new_variables}

    state =
      Enum.reduce(changes, state, fn change, acc ->
        EngineHelpers.add_console(
          acc,
          :info,
          node_id,
          "",
          "Response instruction: #{change.variable_ref}: #{EngineHelpers.format_value(change.old_value)} → #{EngineHelpers.format_value(change.new_value)}"
        )
      end)

    state = EngineHelpers.add_history_entries(state, node_id, "", changes, :instruction)

    Enum.reduce(errors, state, fn error, acc ->
      EngineHelpers.add_console(
        acc,
        :error,
        node_id,
        "",
        "Response instruction error: #{error.reason}"
      )
    end)
  end

  # ---------------------------------------------------------------------------
  # Private helpers
  # ---------------------------------------------------------------------------

  defp handle_dialogue_responses([], state, node_id, label, connections) do
    state =
      EngineHelpers.add_console(
        state,
        :info,
        node_id,
        label,
        "Dialogue — no responses, following output"
      )

    EngineHelpers.follow_output(state, node_id, label, connections)
  end

  defp handle_dialogue_responses(responses, state, node_id, label, connections) do
    evaluated = evaluate_response_conditions(responses, state.variables)
    valid_responses = Enum.filter(evaluated, & &1.valid)

    case valid_responses do
      [only] -> auto_select_response(only, evaluated, state, node_id, label, connections)
      _ -> wait_for_response(evaluated, valid_responses, state, node_id, label)
    end
  end

  defp auto_select_response(only, evaluated, state, node_id, label, connections) do
    total_count = length(evaluated)

    state =
      EngineHelpers.add_console(
        state,
        :info,
        node_id,
        label,
        "Dialogue — auto-selected \"#{only.text}\" (1 of #{total_count} valid)"
      )

    state =
      cond do
        is_list(only[:instruction_assignments]) and only[:instruction_assignments] != [] ->
          execute_response_assignments(only.instruction_assignments, state, node_id)

        is_binary(only[:instruction]) and only[:instruction] != "" ->
          execute_response_instruction(only.instruction, state, node_id)

        true ->
          state
      end

    conn =
      EngineHelpers.find_connection(connections, node_id, only.id) ||
        EngineHelpers.find_connection(connections, node_id, "resp_#{only.id}")

    case conn do
      nil ->
        state =
          EngineHelpers.add_console(
            state,
            :error,
            node_id,
            label,
            "No connection from response #{only.id}"
          )

        {:finished, %{state | status: :finished}}

      conn ->
        EngineHelpers.advance_to(state, conn.target_node_id)
    end
  end

  defp wait_for_response(evaluated, valid_responses, state, node_id, label) do
    valid_count = length(valid_responses)
    total_count = length(evaluated)

    state =
      EngineHelpers.add_console(
        state,
        :info,
        node_id,
        label,
        "Dialogue — waiting for response (#{valid_count} of #{total_count} valid)"
      )

    pending = %{node_id: node_id, responses: evaluated}
    {:waiting_input, %{state | status: :waiting_input, pending_choices: pending}}
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
        instruction: resp["instruction"],
        instruction_assignments: resp["instruction_assignments"] || []
      }
    end)
  end
end
