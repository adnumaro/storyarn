defmodule Storyarn.Imports.Parsers.Yarn.Expression do
  @moduledoc false

  alias Storyarn.Shared.NameNormalizer

  @comparison_operators [
    {~r/^(.+?)\s+is\s+not\s+(.+)$/i, "not_equals"},
    {~r/^(.+?)\s+is\s+(.+)$/i, "equals"},
    {~r/^(.+?)\s*>=\s*(.+)$/, "greater_than_or_equal"},
    {~r/^(.+?)\s*<=\s*(.+)$/, "less_than_or_equal"},
    {~r/^(.+?)\s*!=\s*(.+)$/, "not_equals"},
    {~r/^(.+?)\s*==\s*(.+)$/, "equals"},
    {~r/^(.+?)\s*>\s*(.+)$/, "greater_than"},
    {~r/^(.+?)\s*<\s*(.+)$/, "less_than"}
  ]

  @spec declaration(String.t()) :: {:ok, map()} | {:error, atom()}
  def declaration(args) when is_binary(args) do
    case Regex.run(~r/^\s*(\$[A-Za-z_][A-Za-z0-9_.]*)\s*=\s*(.+?)\s*$/, args, capture: :all_but_first) do
      [reference, raw_value] ->
        with {:ok, variable} <- variable(reference),
             {:ok, value, type} <- literal(raw_value) do
          {:ok, %{variable: variable, value: value, type: type}}
        end

      _other ->
        {:error, :unsupported_yarn_declaration}
    end
  end

  @spec assignment(String.t()) :: {:ok, map()} | {:error, atom()}
  def assignment(args) when is_binary(args) do
    case Regex.run(~r/^\s*(\$[A-Za-z_][A-Za-z0-9_.]*)\s+(?:to|=)\s+(.+?)\s*$/, args, capture: :all_but_first) do
      [reference, expression] -> build_assignment(reference, expression)
      _other -> {:error, :unsupported_yarn_assignment}
    end
  end

  @spec condition(String.t()) :: {:ok, map()} | {:error, atom()}
  def condition(expression) when is_binary(expression) do
    expression = String.trim(expression)
    and_parts = split_logic(expression, :and)
    or_parts = split_logic(expression, :or)

    cond do
      length(and_parts) > 1 and length(or_parts) > 1 ->
        {:error, :unsupported_yarn_mixed_logic}

      length(and_parts) > 1 ->
        build_condition("all", and_parts)

      length(or_parts) > 1 ->
        build_condition("any", or_parts)

      true ->
        build_condition("all", [expression])
    end
  end

  @spec referenced_variables(String.t()) :: [String.t()]
  def referenced_variables(text) when is_binary(text) do
    ~r/\$([A-Za-z_][A-Za-z0-9_.]*)/
    |> Regex.scan(text, capture: :all_but_first)
    |> Enum.map(fn [name] -> normalize_variable(name) end)
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
  end

  @spec interpolate(String.t(), :dialogue | :response) :: String.t()
  def interpolate(text, mode) when is_binary(text) do
    Regex.replace(~r/\{\$([A-Za-z_][A-Za-z0-9_.]*)\}/, text, fn _match, name ->
      variable = normalize_variable(name) || "variable"
      if mode == :dialogue, do: "{yarn.#{variable}}", else: "$yarn.#{variable}"
    end)
  end

  defp build_assignment(reference, expression) do
    with {:ok, variable} <- variable(reference) do
      expression = String.trim(expression)
      escaped_ref = Regex.escape(reference)

      cond do
        Regex.match?(~r/^!\s*#{escaped_ref}$/i, expression) ->
          {:ok, assignment_map(variable, "toggle", nil)}

        captures = Regex.run(~r/^#{escaped_ref}\s*\+\s*(.+)$/i, expression, capture: :all_but_first) ->
          assignment_with_value(variable, "add", List.first(captures))

        captures = Regex.run(~r/^#{escaped_ref}\s*-\s*(.+)$/i, expression, capture: :all_but_first) ->
          assignment_with_value(variable, "subtract", List.first(captures))

        true ->
          assignment_with_value(variable, "set", expression)
      end
    end
  end

  defp assignment_with_value(variable, operator, raw_value) do
    case variable(raw_value) do
      {:ok, value_variable} ->
        {:ok,
         variable
         |> assignment_map(operator, value_variable)
         |> Map.put("value_type", "variable_ref")
         |> Map.put("value_sheet", "yarn")}

      {:error, _reason} ->
        with {:ok, value, type} <- literal(raw_value) do
          operator = boolean_operator(operator, value, type)
          {:ok, assignment_map(variable, operator, value)}
        end
    end
  end

  defp assignment_map(variable, operator, value) do
    %{
      "id" => stable_id("assignment", variable),
      "sheet" => "yarn",
      "variable" => variable,
      "operator" => operator,
      "value" => serialize_value(value),
      "value_type" => "literal",
      "value_sheet" => nil
    }
  end

  defp boolean_operator("set", true, "boolean"), do: "set_true"
  defp boolean_operator("set", false, "boolean"), do: "set_false"
  defp boolean_operator(operator, _value, _type), do: operator

  defp build_condition(logic, expressions) do
    with {:ok, rules} <- map_ok(expressions, &condition_rule/1) do
      {:ok,
       %{
         "logic" => logic,
         "blocks" => [
           %{
             "id" => stable_id("condition_block", Enum.join(expressions, "|")),
             "type" => "block",
             "logic" => logic,
             "rules" => rules
           }
         ]
       }}
    end
  end

  defp condition_rule(expression) do
    expression = expression |> String.trim() |> trim_outer_parentheses()

    cond do
      captures = Regex.run(~r/^not\s+(\$[A-Za-z_][A-Za-z0-9_.]*)$/i, expression, capture: :all_but_first) ->
        build_rule(List.first(captures), "is_false", nil)

      Regex.match?(~r/^\$[A-Za-z_][A-Za-z0-9_.]*$/, expression) ->
        build_rule(expression, "is_true", nil)

      true ->
        comparison_rule(expression)
    end
  end

  defp comparison_rule(expression) do
    Enum.find_value(
      @comparison_operators,
      {:error, :unsupported_yarn_condition},
      &comparison_candidate(expression, &1)
    )
  end

  defp comparison_candidate(expression, {regex, operator}) do
    case Regex.run(regex, expression, capture: :all_but_first) do
      [left, right] -> build_comparison_rule(left, right, operator)
      _other -> false
    end
  end

  defp build_comparison_rule(left, right, operator) do
    with {:ok, _variable} <- variable(left),
         {:ok, value, _type} <- literal(right) do
      build_rule(left, operator, value)
    else
      _other -> false
    end
  end

  defp build_rule(reference, operator, value) do
    with {:ok, variable} <- variable(reference) do
      {:ok,
       %{
         "id" => stable_id("condition_rule", "#{variable}:#{operator}"),
         "sheet" => "yarn",
         "variable" => variable,
         "operator" => operator,
         "value" => serialize_value(value)
       }}
    end
  end

  defp variable(value) when is_binary(value) do
    case Regex.run(~r/^\s*\$([A-Za-z_][A-Za-z0-9_.]*)\s*$/, value, capture: :all_but_first) do
      [name] ->
        case normalize_variable(name) do
          nil -> {:error, :invalid_yarn_variable}
          variable -> {:ok, variable}
        end

      _other ->
        {:error, :invalid_yarn_variable}
    end
  end

  defp normalize_variable(name), do: NameNormalizer.variablify(name)

  defp literal(value) when is_binary(value) do
    value = String.trim(value)

    cond do
      value == "true" -> {:ok, true, "boolean"}
      value == "false" -> {:ok, false, "boolean"}
      Regex.match?(~r/^-?\d+(?:\.\d+)?$/, value) -> parse_number(value)
      String.starts_with?(value, "\"") and String.ends_with?(value, "\"") -> parse_string(value)
      true -> {:error, :unsupported_yarn_literal}
    end
  end

  defp parse_number(value) do
    case Float.parse(value) do
      {number, ""} -> {:ok, number, "number"}
      _other -> {:error, :unsupported_yarn_literal}
    end
  end

  defp parse_string(value) do
    case Jason.decode(value) do
      {:ok, string} when is_binary(string) -> {:ok, string, "text"}
      _other -> {:error, :unsupported_yarn_literal}
    end
  end

  defp serialize_value(nil), do: nil
  defp serialize_value(value) when is_binary(value), do: value
  defp serialize_value(value), do: to_string(value)

  defp split_logic(expression, operator) do
    regex =
      case operator do
        :and -> ~r/^\s+(?:and|&&)\s+/i
        :or -> ~r/^\s+(?:or|\|\|)\s+/i
      end

    do_split_logic(expression, regex, [], [], false, false, 0)
  end

  defp do_split_logic("", _regex, current, parts, _quoted?, _escaped?, _depth) do
    [logic_part(current) | parts]
    |> Enum.reject(&(&1 == ""))
    |> Enum.reverse()
  end

  defp do_split_logic(rest, regex, current, parts, false, false, 0) do
    case Regex.run(regex, rest) do
      [separator] ->
        remaining = binary_part(rest, byte_size(separator), byte_size(rest) - byte_size(separator))
        do_split_logic(remaining, regex, [], [logic_part(current) | parts], false, false, 0)

      nil ->
        consume_logic_grapheme(rest, regex, current, parts, false, false, 0)
    end
  end

  defp do_split_logic(rest, regex, current, parts, quoted?, escaped?, depth) do
    consume_logic_grapheme(rest, regex, current, parts, quoted?, escaped?, depth)
  end

  defp consume_logic_grapheme(rest, regex, current, parts, quoted?, escaped?, depth) do
    {grapheme, remaining} = String.next_grapheme(rest)

    {next_quoted?, next_escaped?, next_depth} =
      logic_state(grapheme, quoted?, escaped?, depth)

    do_split_logic(
      remaining,
      regex,
      [grapheme | current],
      parts,
      next_quoted?,
      next_escaped?,
      next_depth
    )
  end

  defp logic_state(_grapheme, true, true, depth), do: {true, false, depth}
  defp logic_state("\\", true, false, depth), do: {true, true, depth}
  defp logic_state("\"", true, false, depth), do: {false, false, depth}
  defp logic_state("\"", false, false, depth), do: {true, false, depth}
  defp logic_state("(", false, false, depth), do: {false, false, depth + 1}
  defp logic_state(")", false, false, depth), do: {false, false, max(depth - 1, 0)}
  defp logic_state(_grapheme, quoted?, _escaped?, depth), do: {quoted?, false, depth}

  defp logic_part(graphemes) do
    graphemes
    |> Enum.reverse()
    |> Enum.join()
    |> String.trim()
  end

  defp trim_outer_parentheses(expression) do
    if String.starts_with?(expression, "(") and String.ends_with?(expression, ")"),
      do: expression |> String.trim_leading("(") |> String.trim_trailing(")") |> String.trim(),
      else: expression
  end

  defp map_ok(values, fun) do
    values
    |> Enum.reduce_while({:ok, []}, fn value, {:ok, acc} ->
      case fun.(value) do
        {:ok, mapped} -> {:cont, {:ok, [mapped | acc]}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
    |> case do
      {:ok, mapped} -> {:ok, Enum.reverse(mapped)}
      error -> error
    end
  end

  defp stable_id(prefix, value) do
    digest = :sha256 |> :crypto.hash(value) |> Base.url_encode64(padding: false) |> binary_part(0, 12)
    "#{prefix}_#{digest}"
  end
end
