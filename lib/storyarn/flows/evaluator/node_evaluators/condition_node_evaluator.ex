defmodule Storyarn.Flows.Evaluator.NodeEvaluators.ConditionNodeEvaluator do
  @moduledoc """
  Handles evaluation of `condition` nodes in the flow debugger.

  Supports two modes:
  - Boolean mode: evaluates a condition expression to true/false and follows the matching branch.
  - Switch mode: evaluates cases in order and follows the first matching case (or default).
  """

  alias Storyarn.Flows.Evaluator.{ConditionEval, EngineHelpers}

  @doc """
  Evaluate a condition node and advance to the appropriate next node.
  """
  def evaluate(node, state, connections) do
    data = node.data || %{}
    label = EngineHelpers.node_label(node)
    condition = data["condition"] || %{"logic" => "all", "rules" => []}
    switch_mode = data["switch_mode"] || false

    if switch_mode do
      evaluate_switch(node.id, label, condition, state, connections)
    else
      evaluate_boolean(node.id, label, condition, state, connections)
    end
  end

  # ---------------------------------------------------------------------------
  # Boolean mode
  # ---------------------------------------------------------------------------

  defp evaluate_boolean(node_id, label, condition, state, connections) do
    {result, rule_results} = ConditionEval.evaluate(condition, state.variables)
    branch = if result, do: "true", else: "false"
    detail = EngineHelpers.format_rule_summary(rule_results)
    level = if result, do: :info, else: :warning

    state =
      EngineHelpers.add_console_with_rules(
        state,
        level,
        node_id,
        label,
        "Condition → #{branch}#{detail}",
        rule_results
      )

    case EngineHelpers.find_connection(connections, node_id, branch) do
      nil ->
        state =
          EngineHelpers.add_console(state, :error, node_id, label, "No connection from pin \"#{branch}\"")

        {:finished, %{state | status: :finished}}

      conn ->
        EngineHelpers.advance_to(state, conn.target_node_id)
    end
  end

  # ---------------------------------------------------------------------------
  # Switch mode
  # ---------------------------------------------------------------------------

  defp evaluate_switch(node_id, label, condition, state, connections) do
    if condition["blocks"] do
      evaluate_switch_blocks(node_id, label, condition, state, connections)
    else
      evaluate_switch_rules(node_id, label, condition, state, connections)
    end
  end

  defp evaluate_switch_rules(node_id, label, condition, state, connections) do
    rules = condition["rules"] || []

    {matched_pin, state} =
      Enum.reduce_while(rules, {nil, state}, fn rule, {_pin, acc_state} ->
        evaluate_switch_rule(rule, acc_state, node_id, label)
      end)

    state = log_switch_default_if_unmatched(state, matched_pin, node_id, label)
    pin = matched_pin || "default"
    follow_switch_pin(state, node_id, label, pin, connections)
  end

  defp evaluate_switch_blocks(node_id, label, condition, state, connections) do
    blocks = condition["blocks"] || []

    {matched_pin, state} =
      Enum.reduce_while(blocks, {nil, state}, fn block, {_pin, acc_state} ->
        evaluate_switch_block(block, acc_state, node_id, label)
      end)

    state = log_switch_default_if_unmatched(state, matched_pin, node_id, label)
    pin = matched_pin || "default"
    follow_switch_pin(state, node_id, label, pin, connections)
  end

  defp evaluate_switch_block(%{"type" => "block"} = block, acc_state, node_id, label) do
    block_condition = %{"logic" => block["logic"] || "all", "rules" => block["rules"] || []}
    {result, _rule_results} = ConditionEval.evaluate(block_condition, acc_state.variables)
    block_label = block["label"] || block["id"] || "unnamed"

    if result do
      acc_state =
        EngineHelpers.add_console(
          acc_state,
          :info,
          node_id,
          label,
          "Switch → case \"#{block_label}\" matched"
        )

      {:halt, {block["id"], acc_state}}
    else
      acc_state =
        EngineHelpers.add_console(
          acc_state,
          :info,
          node_id,
          label,
          "Switch → case \"#{block_label}\" did not match"
        )

      {:cont, {nil, acc_state}}
    end
  end

  defp evaluate_switch_block(_, acc_state, _node_id, _label) do
    {:cont, {nil, acc_state}}
  end

  defp evaluate_switch_rule(rule, acc_state, node_id, label) do
    rule_result = ConditionEval.evaluate_rule(rule, acc_state.variables)
    rule_label = rule["label"] || rule["id"] || "unnamed"

    if rule_result.passed do
      acc_state =
        EngineHelpers.add_console(acc_state, :info, node_id, label, "Switch → case \"#{rule_label}\" matched")

      {:halt, {rule["id"], acc_state}}
    else
      acc_state =
        EngineHelpers.add_console(
          acc_state,
          :info,
          node_id,
          label,
          "Switch → case \"#{rule_label}\" did not match"
        )

      {:cont, {nil, acc_state}}
    end
  end

  defp log_switch_default_if_unmatched(state, nil, node_id, label) do
    EngineHelpers.add_console(state, :warning, node_id, label, "Switch — no case matched, following default")
  end

  defp log_switch_default_if_unmatched(state, _matched_pin, _node_id, _label), do: state

  defp follow_switch_pin(state, node_id, label, pin, connections) do
    conn =
      EngineHelpers.find_connection(connections, node_id, pin) ||
        if(pin != "default", do: EngineHelpers.find_connection(connections, node_id, "default"))

    case conn do
      nil ->
        state = EngineHelpers.add_console(state, :error, node_id, label, "No connection from pin \"#{pin}\"")
        {:finished, %{state | status: :finished}}

      conn ->
        EngineHelpers.advance_to(state, conn.target_node_id)
    end
  end
end
