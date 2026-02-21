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
    label = EngineHelpers.node_label(node)
    data = node.data || %{}
    exit_mode = data["exit_mode"] || "terminal"

    case exit_mode do
      "flow_reference" ->
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

      "caller_return" ->
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

      _terminal ->
        state = EngineHelpers.add_console(state, :info, node.id, label, "Execution finished")
        {:finished, %{state | status: :finished}}
    end
  end
end
