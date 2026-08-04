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
  @interpolation_regex ~r/\{\$([A-Za-z_][A-Za-z0-9_.]*)\}/

  @spec declaration(String.t()) :: {:ok, map()} | {:error, atom()}
  def declaration(args) when is_binary(args) do
    case Regex.run(~r/^\s*(\$[A-Za-z_][A-Za-z0-9_.]*)\s*=\s*(.+?)\s*$/, args, capture: :all_but_first) do
      [reference, raw_value] ->
        with {:ok, variable} <- variable(reference),
             {:ok, value, type} <- literal(raw_value) do
          # `source_name` keeps the author's own spelling for display; the
          # normalized `variable` is the identifier everything else references.
          {:ok,
           %{
             variable: variable,
             source_name: String.trim_leading(reference, "$"),
             value: value,
             type: type
           }}
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
    text
    |> referenced_variable_occurrences()
    |> Enum.map(& &1.variable)
    |> Enum.uniq()
  end

  @doc false
  @spec referenced_variable_occurrences(String.t()) :: [%{variable: String.t(), source_name: String.t()}]
  def referenced_variable_occurrences(text) when is_binary(text) do
    text
    |> without_string_literals()
    |> then(&Regex.scan(~r/\$([A-Za-z_][A-Za-z0-9_.]*)/, &1, capture: :all_but_first))
    |> variable_occurrences()
  end

  @doc false
  @spec interpolated_variables(String.t()) :: [String.t()]
  def interpolated_variables(text) when is_binary(text) do
    text
    |> interpolated_variable_occurrences()
    |> Enum.map(& &1.variable)
    |> Enum.uniq()
  end

  @doc false
  @spec interpolated_variable_occurrences(String.t()) :: [%{variable: String.t(), source_name: String.t()}]
  def interpolated_variable_occurrences(text) when is_binary(text) do
    @interpolation_regex
    |> Regex.scan(text, capture: :all_but_first)
    |> variable_occurrences()
  end

  @doc false
  # An interpolation that matches the syntax but normalizes to nothing — `{$_}`
  # — would otherwise be silently rewritten to the shared fallback variable
  # and materialize as a dangling reference.
  @spec invalid_interpolation?(String.t()) :: boolean()
  def invalid_interpolation?(text) when is_binary(text) do
    @interpolation_regex
    |> Regex.scan(text, capture: :all_but_first)
    |> Enum.any?(fn [name] -> is_nil(normalize_variable(name)) end)
  end

  @spec interpolate(String.t(), :dialogue | :response, String.t()) :: String.t()
  def interpolate(text, mode, shortcut \\ "yarn") when is_binary(text) and is_binary(shortcut) do
    Regex.replace(@interpolation_regex, text, fn _match, name ->
      variable = normalize_variable(name) || "variable"
      if mode == :dialogue, do: "{#{shortcut}.#{variable}}", else: "$#{shortcut}.#{variable}"
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

      captures = Regex.run(~r/^!\s*(\$[A-Za-z_][A-Za-z0-9_.]*)$/, expression, capture: :all_but_first) ->
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

  # Yarn variables are conventionally camelCase (`$hasClueA`). `variablify/1`
  # only lowercases, so on its own it would flatten that to `hascluea`; splitting
  # the word boundaries into underscores first yields `has_clue_a`. Repeated or
  # leading underscores do not need guarding here — `variablify/1` collapses and
  # trims them.
  # `variablify/1` returns "" (not nil) for a name with no usable characters,
  # such as `$_` — collapsing that to nil here keeps every `|| fallback` and
  # nil guard downstream honest, so an unusable name fails the parse instead
  # of persisting an empty `variable_name` that aborts materialization later.
  defp normalize_variable(name) do
    normalized =
      name
      |> String.replace(~r/([A-Z]+)([A-Z][a-z])/, "\\1_\\2")
      |> String.replace(~r/([^A-Z_.])([A-Z][a-z]+)/, "\\1_\\2")
      |> String.replace(~r/([a-z0-9])([A-Z])/, "\\1_\\2")
      |> NameNormalizer.variablify()

    if normalized == "", do: nil, else: normalized
  end

  defp variable_occurrences(captures) do
    captures
    |> Enum.reduce([], fn [source_name], occurrences ->
      case normalize_variable(source_name) do
        nil -> occurrences
        variable -> [%{variable: variable, source_name: source_name} | occurrences]
      end
    end)
    |> Enum.reverse()
    |> Enum.uniq()
  end

  defp without_string_literals(text) do
    text
    |> do_without_string_literals(false, false, [])
    |> IO.iodata_to_binary()
  end

  defp do_without_string_literals(<<>>, _quoted?, _escaped?, acc), do: Enum.reverse(acc)

  defp do_without_string_literals(<<?", rest::binary>>, false, _escaped?, acc) do
    do_without_string_literals(rest, true, false, acc)
  end

  defp do_without_string_literals(<<byte, rest::binary>>, false, _escaped?, acc) do
    do_without_string_literals(rest, false, false, [<<byte>> | acc])
  end

  defp do_without_string_literals(<<?\\, rest::binary>>, true, false, acc) do
    do_without_string_literals(rest, true, true, acc)
  end

  defp do_without_string_literals(<<_byte, rest::binary>>, true, true, acc) do
    do_without_string_literals(rest, true, false, acc)
  end

  defp do_without_string_literals(<<?", rest::binary>>, true, false, acc) do
    do_without_string_literals(rest, false, false, acc)
  end

  defp do_without_string_literals(<<_byte, rest::binary>>, true, false, acc) do
    do_without_string_literals(rest, true, false, acc)
  end

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
  rescue
    # OTP raises for syntactically numeric values outside the finite float
    # range. Treat them like every other unsupported Yarn literal instead of
    # letting an uploaded source escape the parser's tagged-error contract.
    ArgumentError -> {:error, :unsupported_yarn_literal}
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
        :and -> ~r/^(?:\s*&&\s*|\s+and\s+)/i
        :or -> ~r/^(?:\s*\|\|\s*|\s+or\s+)/i
      end

    do_split_logic(expression, regex, [], [], false, false, 0)
  end

  defp do_split_logic("", _regex, current, parts, _quoted?, _escaped?, _depth) do
    Enum.reverse([logic_part(current) | parts])
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
