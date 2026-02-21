defmodule Storyarn.Flows.Evaluator.NodeEvaluators.InstructionEvaluator do
  @moduledoc """
  Handles evaluation of `instruction` nodes in the flow debugger.

  Executes variable assignments defined in the node's data and logs
  each change to the console and history.
  """

  alias Storyarn.Flows.Evaluator.{EngineHelpers, InstructionExec}

  @doc """
  Evaluate an instruction node: execute all assignments and follow the output.
  """
  def evaluate(node, state, connections) do
    data = node.data || %{}
    label = EngineHelpers.node_label(node)
    assignments = data["assignments"] || []

    {:ok, new_variables, changes, errors} = InstructionExec.execute(assignments, state.variables)
    state = %{state | variables: new_variables}

    # Log each change to console + history
    state =
      Enum.reduce(changes, state, fn change, acc ->
        EngineHelpers.add_console(
          acc,
          :info,
          node.id,
          label,
          "#{change.variable_ref}: #{EngineHelpers.format_value(change.old_value)} → #{EngineHelpers.format_value(change.new_value)} (#{change.operator})"
        )
      end)

    state = EngineHelpers.add_history_entries(state, node.id, label, changes, :instruction)

    # Log errors
    state =
      Enum.reduce(errors, state, fn error, acc ->
        EngineHelpers.add_console(
          acc,
          :error,
          node.id,
          label,
          "#{error.variable_ref}: #{error.reason}"
        )
      end)

    state =
      if changes == [] and errors == [] do
        EngineHelpers.add_console(state, :info, node.id, label, "Instruction — no assignments")
      else
        state
      end

    EngineHelpers.follow_output(state, node.id, label, connections)
  end
end
