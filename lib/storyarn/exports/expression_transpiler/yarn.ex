defmodule Storyarn.Exports.ExpressionTranspiler.Yarn do
  @moduledoc """
  Yarn Spinner expression emitter.

  Variable format: `$mc_jaime_health` ($ prefix + dots → underscores)
  Logic: `and` / `or`
  """

  use Storyarn.Exports.ExpressionTranspiler.Base,
    var_style: :dollar_underscore,
    logic_opts: [and_keyword: " and ", or_keyword: " or "],
    literal_opts: []

  # Operators that require custom function registration in the Yarn runtime
  @custom_function_ops ~w(contains not_contains starts_with ends_with)

  # ---------------------------------------------------------------------------
  # Conditions — override transpile_rules for custom-function warnings
  # ---------------------------------------------------------------------------

  defp transpile_rules(rules) do
    {parts, warnings} =
      Enum.reduce(rules, {[], []}, fn rule, {parts_acc, warn_acc} ->
        case yarn_transpile_rule(rule) do
          {:ok, expr} -> {[expr | parts_acc], warn_acc}
          {:warning, expr, w} -> {[expr | parts_acc], [w | warn_acc]}
          :skip -> {parts_acc, warn_acc}
        end
      end)

    {Enum.reverse(parts), Enum.reverse(warnings)}
  end

  defp yarn_transpile_rule(%{"sheet" => sheet, "variable" => var, "operator" => op} = rule)
       when is_binary(sheet) and sheet != "" and is_binary(var) and var != "" do
    ref = Helpers.format_var_ref(sheet, var, @var_style)

    if op in @custom_function_ops do
      expr = emit_condition_op(ref, op, rule["value"])
      warning = Helpers.custom_function_warning(op, "Yarn", "#{sheet}.#{var}")
      {:warning, expr, warning}
    else
      {:ok, emit_condition_op(ref, op, rule["value"])}
    end
  end

  defp yarn_transpile_rule(_), do: :skip

  # ---------------------------------------------------------------------------
  # Condition operators
  # ---------------------------------------------------------------------------

  defp emit_condition_op(ref, "is_true", _), do: "#{ref} == true"
  defp emit_condition_op(ref, "is_false", _), do: "#{ref} == false"
  # Yarn v2 has no null — compare against type default instead
  defp emit_condition_op(ref, "is_nil", _), do: ~s(#{ref} == "")
  defp emit_condition_op(ref, "is_empty", _), do: ~s(#{ref} == "")

  defp emit_condition_op(ref, "contains", val),
    do: "string_contains(#{ref}, #{Helpers.format_literal(val, @literal_opts)})"

  defp emit_condition_op(ref, "not_contains", val),
    do: "!string_contains(#{ref}, #{Helpers.format_literal(val, @literal_opts)})"

  defp emit_condition_op(ref, "starts_with", val),
    do: "string_starts_with(#{ref}, #{Helpers.format_literal(val, @literal_opts)})"

  defp emit_condition_op(ref, "ends_with", val),
    do: "string_ends_with(#{ref}, #{Helpers.format_literal(val, @literal_opts)})"

  defp emit_condition_op(ref, "before", val),
    do: "#{ref} < #{Helpers.format_literal(val, @literal_opts)}"

  defp emit_condition_op(ref, "after", val),
    do: "#{ref} > #{Helpers.format_literal(val, @literal_opts)}"

  defp emit_condition_op(ref, op, value) do
    "#{ref} #{condition_op(op)} #{Helpers.format_literal(value, @literal_opts)}"
  end

  defp condition_op("equals"), do: "=="
  defp condition_op("not_equals"), do: "!="
  defp condition_op("greater_than"), do: ">"
  defp condition_op("less_than"), do: "<"
  defp condition_op("greater_than_or_equal"), do: ">="
  defp condition_op("less_than_or_equal"), do: "<="
  defp condition_op(op), do: op

  # ---------------------------------------------------------------------------
  # Instructions — override to add set_if_unset semantic loss warnings
  # ---------------------------------------------------------------------------

  @impl true
  def transpile_instruction(assignments, ctx) when is_list(assignments) do
    {:ok, result, warnings} = super(assignments, ctx)

    extra_warnings =
      assignments
      |> Enum.filter(fn
        %{"sheet" => s, "variable" => v, "operator" => "set_if_unset"}
        when is_binary(s) and s != "" and is_binary(v) and v != "" ->
          true

        _ ->
          false
      end)
      |> Enum.map(fn %{"sheet" => s, "variable" => v} ->
        %{
          type: :semantic_loss,
          message: "set_if_unset emits unconditional set in Yarn (no null type)",
          operator: "set_if_unset",
          engine: "Yarn",
          variable: "#{s}.#{v}"
        }
      end)

    {:ok, result, warnings ++ extra_warnings}
  end

  def transpile_instruction(other, ctx), do: super(other, ctx)

  # ---------------------------------------------------------------------------
  # Instruction operators
  # ---------------------------------------------------------------------------

  defp emit_assignment(ref, "set", a), do: "<<set #{ref} to #{format_value(ref, a)}>>"
  defp emit_assignment(ref, "add", a), do: "<<set #{ref} to #{ref} + #{format_value(ref, a)}>>"

  defp emit_assignment(ref, "subtract", a),
    do: "<<set #{ref} to #{ref} - #{format_value(ref, a)}>>"

  defp emit_assignment(ref, "set_true", _), do: "<<set #{ref} to true>>"
  defp emit_assignment(ref, "set_false", _), do: "<<set #{ref} to false>>"
  defp emit_assignment(ref, "toggle", _), do: "<<set #{ref} to !#{ref}>>"
  defp emit_assignment(ref, "clear", _), do: ~s(<<set #{ref} to "">>)

  # Yarn v2 has no null — emit unconditional set (all vars have declared defaults)
  defp emit_assignment(ref, "set_if_unset", a) do
    "<<set #{ref} to #{format_value(ref, a)}>>"
  end

  defp emit_assignment(ref, _op, a), do: "<<set #{ref} to #{format_value(ref, a)}>>"
end
