defmodule Storyarn.Flows.Evaluator.ConditionEval do
  @moduledoc """
  Evaluates condition maps against the current variable state.

  Returns per-rule evaluation detail for debugging — inspired by articy:draft's
  sub-expression highlighting. Each rule result includes whether it passed,
  the actual value found, and the comparison attempted.

  ## Usage

      variables = %{"mc.jaime.health" => %{value: 80, block_type: "number", ...}}
      condition = %{"logic" => "all", "rules" => [
        %{"sheet" => "mc.jaime", "variable" => "health", "operator" => "greater_than", "value" => "50"}
      ]}

      {true, [%{passed: true, variable_ref: "mc.jaime.health", ...}]} =
        ConditionEval.evaluate(condition, variables)
  """

  alias Storyarn.Flows.Condition

  @type rule_result :: %{
          rule_id: String.t() | nil,
          passed: boolean(),
          variable_ref: String.t(),
          operator: String.t(),
          expected_value: any(),
          actual_value: any()
        }

  @doc """
  Evaluates a full condition map against the variable state.

  Returns `{result, rule_results}` where:
  - `result` is `true` or `false`
  - `rule_results` is a list of per-rule evaluation details

  Special cases:
  - `nil` or empty condition → `{true, []}` (no condition = always passes)
  - `:legacy` condition → `{true, []}` (legacy plain text, can't evaluate)
  - Condition with no complete rules → `{true, []}` (nothing to evaluate)
  """
  @spec evaluate(map() | nil, map()) :: {boolean(), [rule_result()]}
  def evaluate(nil, _variables), do: {true, []}
  def evaluate(%{"rules" => []}, _variables), do: {true, []}
  def evaluate(%{"rules" => nil}, _variables), do: {true, []}

  def evaluate(%{"logic" => logic, "rules" => rules}, variables)
      when is_list(rules) do
    rule_results =
      rules
      |> Enum.filter(&complete_rule?/1)
      |> Enum.map(&evaluate_rule(&1, variables))

    # No complete rules → pass
    if rule_results == [] do
      {true, []}
    else
      result =
        case logic do
          "all" -> Enum.all?(rule_results, & &1.passed)
          "any" -> Enum.any?(rule_results, & &1.passed)
          _ -> Enum.all?(rule_results, & &1.passed)
        end

      {result, rule_results}
    end
  end

  def evaluate(_invalid, _variables), do: {true, []}

  @doc """
  Evaluates a condition stored as a JSON string (as found in dialogue node fields).

  Parses the string first using `Condition.parse/1`, then evaluates.
  Legacy plain-text conditions pass automatically.
  """
  @spec evaluate_string(String.t() | nil, map()) :: {boolean(), [rule_result()]}
  def evaluate_string(nil, _variables), do: {true, []}
  def evaluate_string("", _variables), do: {true, []}

  def evaluate_string(condition_string, variables) when is_binary(condition_string) do
    case Condition.parse(condition_string) do
      :legacy -> {true, []}
      nil -> {true, []}
      condition_map -> evaluate(condition_map, variables)
    end
  end

  @doc """
  Evaluates a single rule against the variable state.

  Returns a `rule_result` map with pass/fail and comparison details.
  """
  @spec evaluate_rule(map(), map()) :: rule_result()
  def evaluate_rule(
        %{"sheet" => sheet, "variable" => variable, "operator" => operator} = rule,
        variables
      ) do
    variable_ref = "#{sheet}.#{variable}"
    expected_value = rule["value"]

    case Map.get(variables, variable_ref) do
      nil ->
        # Variable not found in state — treat value as nil
        passed = evaluate_operator(operator, nil, expected_value, nil)

        %{
          rule_id: rule["id"],
          passed: passed,
          variable_ref: variable_ref,
          operator: operator,
          expected_value: expected_value,
          actual_value: nil
        }

      %{value: actual_value, block_type: block_type} ->
        passed = evaluate_operator(operator, actual_value, expected_value, block_type)

        %{
          rule_id: rule["id"],
          passed: passed,
          variable_ref: variable_ref,
          operator: operator,
          expected_value: expected_value,
          actual_value: actual_value
        }
    end
  end

  # -- Operator evaluation --

  # Number operators
  defp evaluate_operator("equals", actual, expected, "number") do
    parse_number(actual) == parse_number(expected)
  end

  defp evaluate_operator("not_equals", actual, expected, "number") do
    parse_number(actual) != parse_number(expected)
  end

  defp evaluate_operator("greater_than", actual, expected, "number") do
    with {a, _} when is_number(a) <- safe_parse_number(actual),
         {e, _} when is_number(e) <- safe_parse_number(expected) do
      a > e
    else
      _ -> false
    end
  end

  defp evaluate_operator("greater_than_or_equal", actual, expected, "number") do
    with {a, _} when is_number(a) <- safe_parse_number(actual),
         {e, _} when is_number(e) <- safe_parse_number(expected) do
      a >= e
    else
      _ -> false
    end
  end

  defp evaluate_operator("less_than", actual, expected, "number") do
    with {a, _} when is_number(a) <- safe_parse_number(actual),
         {e, _} when is_number(e) <- safe_parse_number(expected) do
      a < e
    else
      _ -> false
    end
  end

  defp evaluate_operator("less_than_or_equal", actual, expected, "number") do
    with {a, _} when is_number(a) <- safe_parse_number(actual),
         {e, _} when is_number(e) <- safe_parse_number(expected) do
      a <= e
    else
      _ -> false
    end
  end

  # Boolean operators
  defp evaluate_operator("is_true", actual, _expected, _block_type), do: actual == true
  defp evaluate_operator("is_false", actual, _expected, _block_type), do: actual == false
  defp evaluate_operator("is_nil", actual, _expected, _block_type), do: is_nil(actual)

  # Text operators
  defp evaluate_operator("equals", actual, expected, block_type)
       when block_type in ["text", "rich_text"] do
    to_string_safe(actual) == to_string_safe(expected)
  end

  defp evaluate_operator("not_equals", actual, expected, block_type)
       when block_type in ["text", "rich_text"] do
    to_string_safe(actual) != to_string_safe(expected)
  end

  defp evaluate_operator("contains", actual, expected, block_type)
       when block_type in ["text", "rich_text"] do
    str = to_string_safe(actual)
    substr = to_string_safe(expected)
    substr != "" and String.contains?(str, substr)
  end

  defp evaluate_operator("starts_with", actual, expected, block_type)
       when block_type in ["text", "rich_text"] do
    String.starts_with?(to_string_safe(actual), to_string_safe(expected))
  end

  defp evaluate_operator("ends_with", actual, expected, block_type)
       when block_type in ["text", "rich_text"] do
    String.ends_with?(to_string_safe(actual), to_string_safe(expected))
  end

  defp evaluate_operator("is_empty", actual, _expected, block_type)
       when block_type in ["text", "rich_text"] do
    actual in [nil, ""]
  end

  # Select operators
  defp evaluate_operator("equals", actual, expected, "select") do
    to_string_safe(actual) == to_string_safe(expected)
  end

  defp evaluate_operator("not_equals", actual, expected, "select") do
    to_string_safe(actual) != to_string_safe(expected)
  end

  # Multi-select operators
  defp evaluate_operator("contains", actual, expected, "multi_select") when is_list(actual) do
    to_string_safe(expected) in Enum.map(actual, &to_string_safe/1)
  end

  defp evaluate_operator("contains", _actual, _expected, "multi_select"), do: false

  defp evaluate_operator("not_contains", actual, expected, "multi_select")
       when is_list(actual) do
    to_string_safe(expected) not in Enum.map(actual, &to_string_safe/1)
  end

  defp evaluate_operator("not_contains", _actual, _expected, "multi_select"), do: true

  defp evaluate_operator("is_empty", actual, _expected, "multi_select") do
    actual in [nil, []]
  end

  # Date operators
  defp evaluate_operator("equals", actual, expected, "date") do
    compare_dates(actual, expected) == :eq
  end

  defp evaluate_operator("not_equals", actual, expected, "date") do
    compare_dates(actual, expected) != :eq
  end

  defp evaluate_operator("before", actual, expected, "date") do
    compare_dates(actual, expected) == :lt
  end

  defp evaluate_operator("after", actual, expected, "date") do
    compare_dates(actual, expected) == :gt
  end

  # Fallback: unknown block_type — try generic string comparison
  defp evaluate_operator("equals", actual, expected, _block_type) do
    to_string_safe(actual) == to_string_safe(expected)
  end

  defp evaluate_operator("not_equals", actual, expected, _block_type) do
    to_string_safe(actual) != to_string_safe(expected)
  end

  defp evaluate_operator(_operator, _actual, _expected, _block_type), do: false

  # -- Helpers --

  defp complete_rule?(%{"sheet" => sheet, "variable" => variable, "operator" => operator}) do
    is_binary(sheet) and sheet != "" and
      is_binary(variable) and variable != "" and
      is_binary(operator) and operator != ""
  end

  defp complete_rule?(_), do: false

  defp parse_number(nil), do: nil
  defp parse_number(n) when is_number(n), do: n * 1.0

  defp parse_number(s) when is_binary(s) do
    case Float.parse(s) do
      {n, _} -> n
      :error -> nil
    end
  end

  defp parse_number(_), do: nil

  defp safe_parse_number(nil), do: :error
  defp safe_parse_number(n) when is_number(n), do: {n * 1.0, ""}

  defp safe_parse_number(s) when is_binary(s) do
    case Float.parse(s) do
      {n, rest} -> {n, rest}
      :error -> :error
    end
  end

  defp safe_parse_number(_), do: :error

  defp to_string_safe(nil), do: ""
  defp to_string_safe(s) when is_binary(s), do: s
  defp to_string_safe(n) when is_number(n), do: to_string(n)
  defp to_string_safe(b) when is_boolean(b), do: to_string(b)
  defp to_string_safe(other), do: inspect(other)

  defp compare_dates(actual, expected) do
    with {:ok, date_a} <- parse_date(actual),
         {:ok, date_e} <- parse_date(expected) do
      Date.compare(date_a, date_e)
    else
      _ -> :error
    end
  end

  defp parse_date(%Date{} = d), do: {:ok, d}

  defp parse_date(s) when is_binary(s) do
    case Date.from_iso8601(s) do
      {:ok, d} -> {:ok, d}
      _ -> :error
    end
  end

  defp parse_date(_), do: :error
end
