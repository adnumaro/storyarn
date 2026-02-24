defmodule Storyarn.Flows.Evaluator.NodeEvaluators.ExitEvaluator do
  @moduledoc """
  Handles evaluation of `exit` nodes in the flow debugger.

  Supports three exit modes:
  - `terminal` (default): ends execution
  - `flow_reference`: jumps to another flow
  - `caller_return`: returns to the calling flow (if on the call stack)
  """

  alias Storyarn.Flows.Evaluator.EngineHelpers

  @doc """
  Evaluate an exit node and return the appropriate result tuple.
  """
  def evaluate(node, state) do
    data = node.data || %{}
    exit_mode = data["exit_mode"] || "terminal"

    case exit_mode do
      "flow_reference" -> evaluate_flow_reference(node, state, data)
      "caller_return" -> evaluate_caller_return(node, state)
      _terminal -> evaluate_terminal(node, state, data)
    end
  end

  defp evaluate_flow_reference(node, state, data) do
    label = EngineHelpers.node_label(node)

    case data["referenced_flow_id"] do
      nil ->
        state =
          EngineHelpers.add_console(
            state,
            :error,
            node.id,
            label,
            "Exit has flow_reference mode but no referenced_flow_id"
          )

        {:finished, %{state | status: :finished}}

      flow_id ->
        state =
          EngineHelpers.add_console(
            state,
            :info,
            node.id,
            label,
            "Exit → flow reference (flow #{flow_id})"
          )

        {:flow_jump, state, flow_id}
    end
  end

  defp evaluate_caller_return(node, state) do
    label = EngineHelpers.node_label(node)

    if state.call_stack != [] do
      state =
        EngineHelpers.add_console(state, :info, node.id, label, "Exit → return to caller")

      {:flow_return, state}
    else
      state =
        EngineHelpers.add_console(
          state,
          :info,
          node.id,
          label,
          "Exit → caller return (no caller, finishing)"
        )

      {:finished, %{state | status: :finished}}
    end
  end

  defp evaluate_terminal(node, state, data) do
    label = EngineHelpers.node_label(node)
    target_type = data["target_type"]
    target_id = data["target_id"]

    exit_transition =
      if target_type in ["scene", "flow"] and target_id do
        %{type: target_type, id: target_id}
      else
        nil
      end

    state = EngineHelpers.add_console(state, :info, node.id, label, "Execution finished")
    {:finished, %{state | status: :finished, exit_transition: exit_transition}}
  end
end
