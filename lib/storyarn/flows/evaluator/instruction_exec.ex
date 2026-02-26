defmodule Storyarn.Flows.Evaluator.InstructionExec do
  @moduledoc """
  Executes instruction assignments against the current variable state.

  The "write" side of the evaluator — mirrors `Storyarn.Flows.Instruction`
  operator definitions but actually performs the mutations on the in-memory
  variable state during a debug session.

  Returns the updated variables map plus a list of changes for logging.

  ## Usage

      assignments = [
        %{"sheet" => "mc.jaime", "variable" => "health", "operator" => "subtract", "value" => "20",
          "value_type" => "literal"}
      ]
      variables = %{"mc.jaime.health" => %{value: 100, block_type: "number", ...}}

      {:ok, new_variables, changes} = InstructionExec.execute(assignments, variables)
      # new_variables["mc.jaime.health"].value == 80
      # changes == [%{variable_ref: "mc.jaime.health", old_value: 100, new_value: 80, operator: "subtract"}]
  """

  alias Storyarn.Flows.Instruction
  alias Storyarn.Sheets

  @type change :: %{
          variable_ref: String.t(),
          old_value: any(),
          new_value: any(),
          operator: String.t()
        }

  @type error :: %{
          variable_ref: String.t(),
          reason: String.t()
        }

  @doc """
  Executes a list of assignments against the variable state.

  Returns `{:ok, new_variables, changes, errors}` where:
  - `new_variables` is the updated variables map (with source set to `:instruction`)
  - `changes` is a list of successful mutations
  - `errors` is a list of skipped assignments with reasons

  Incomplete assignments are silently skipped.
  Missing variables are reported as errors and skipped.
  """
  @spec execute(list(), map()) :: {:ok, map(), [change()], [error()]}
  def execute(assignments, variables) when is_list(assignments) do
    assignments
    |> Enum.filter(&Instruction.complete_assignment?/1)
    |> Enum.reduce({variables, [], []}, fn assignment, acc ->
      execute_single_assignment(assignment, acc)
    end)
    |> then(fn {vars, changes, errors} -> {:ok, vars, changes, errors} end)
  end

  def execute(_, variables), do: {:ok, variables, [], []}

  defp execute_single_assignment(assignment, {vars, changes, errors}) do
    variable_ref = "#{assignment["sheet"]}.#{assignment["variable"]}"

    case Map.get(vars, variable_ref) do
      nil ->
        error = %{variable_ref: variable_ref, reason: "Variable not found in state"}
        {vars, changes, errors ++ [error]}

      var_entry ->
        apply_assignment(assignment, variable_ref, var_entry, vars, changes, errors)
    end
  end

  defp apply_assignment(assignment, variable_ref, var_entry, vars, changes, errors) do
    operator = assignment["operator"]

    case resolve_value(assignment, vars) do
      {:ok, resolved_value} ->
        raw_value =
          apply_operator(operator, var_entry.value, resolved_value, var_entry.block_type)

        new_value = clamp_to_constraints(raw_value, var_entry)

        updated_entry = %{
          var_entry
          | value: new_value,
            previous_value: var_entry.value,
            source: :instruction
        }

        change = %{
          variable_ref: variable_ref,
          old_value: var_entry.value,
          new_value: new_value,
          operator: operator
        }

        {Map.put(vars, variable_ref, updated_entry), changes ++ [change], errors}

      {:error, reason} ->
        error = %{variable_ref: variable_ref, reason: reason}
        {vars, changes, errors ++ [error]}
    end
  end

  @doc """
  Executes assignments from a JSON string.

  Parses the string first, then executes.
  """
  @spec execute_string(String.t() | nil, map()) :: {:ok, map(), [change()], [error()]}
  def execute_string(nil, variables), do: {:ok, variables, [], []}
  def execute_string("", variables), do: {:ok, variables, [], []}

  def execute_string(json_string, variables) when is_binary(json_string) do
    case Jason.decode(json_string) do
      {:ok, assignments} when is_list(assignments) ->
        execute(Instruction.sanitize(assignments), variables)

      _ ->
        {:ok, variables, [], []}
    end
  end

  # -- Operator application --

  # Number operators
  defp apply_operator("set", _old, value, "number"), do: parse_number(value)
  defp apply_operator("add", old, value, "number"), do: safe_add(old, value)
  defp apply_operator("subtract", old, value, "number"), do: safe_subtract(old, value)

  # Boolean operators
  defp apply_operator("set_true", _old, _value, _type), do: true
  defp apply_operator("set_false", _old, _value, _type), do: false
  defp apply_operator("toggle", old, _value, _type), do: !old

  # Text operators
  defp apply_operator("set", _old, value, type) when type in ["text", "rich_text"], do: value
  defp apply_operator("clear", _old, _value, type) when type in ["text", "rich_text"], do: nil

  # Select / multi_select / date — all use set
  defp apply_operator("set", _old, value, _type), do: value

  # Set if unset — only set when current value is nil
  defp apply_operator("set_if_unset", nil, value, "number"), do: parse_number(value)
  defp apply_operator("set_if_unset", nil, value, _type), do: value
  defp apply_operator("set_if_unset", old, _value, _type), do: old

  # Fallback
  defp apply_operator(_operator, _old, value, _type), do: value

  # -- Value resolution --

  defp resolve_value(%{"value_type" => "variable_ref"} = assignment, variables) do
    ref_sheet = assignment["value_sheet"]
    ref_variable = assignment["value"]

    if is_binary(ref_sheet) and ref_sheet != "" and is_binary(ref_variable) and ref_variable != "" do
      ref_key = "#{ref_sheet}.#{ref_variable}"

      case Map.get(variables, ref_key) do
        nil -> {:error, "Referenced variable #{ref_key} not found"}
        %{value: value} -> {:ok, value}
      end
    else
      {:error, "Incomplete variable reference"}
    end
  end

  defp resolve_value(assignment, _variables) do
    {:ok, assignment["value"]}
  end

  # -- Number helpers --

  defp parse_number(nil), do: nil
  defp parse_number(n) when is_number(n), do: n

  defp parse_number(s) when is_binary(s) do
    case Float.parse(s) do
      {n, _} -> n
      :error -> nil
    end
  end

  defp parse_number(_), do: nil

  defp safe_add(old, value) do
    old_n = parse_number(old) || 0
    val_n = parse_number(value) || 0
    old_n + val_n
  end

  defp safe_subtract(old, value) do
    old_n = parse_number(old) || 0
    val_n = parse_number(value) || 0
    old_n - val_n
  end

  # -- Constraint clamping (delegates to Sheets facade) --

  defp clamp_to_constraints(value, %{block_type: block_type, constraints: constraints}),
    do: Sheets.clamp_to_constraints(value, constraints, block_type)

  defp clamp_to_constraints(value, _), do: value
end
