defmodule Storyarn.Exports.ExpressionTranspiler.Ink do
  @moduledoc """
  Ink script expression emitter.

  Variable format: `mc_jaime_health` (dots → underscores)
  Logic: `and` / `or`
  """

  use Storyarn.Exports.ExpressionTranspiler.Base,
    var_style: :underscore,
    logic_opts: [and_keyword: " and ", or_keyword: " or "],
    literal_opts: []

  # Operators that Ink cannot represent natively
  @unsupported_condition_ops ~w(contains not_contains starts_with ends_with is_nil before after)

  # ---------------------------------------------------------------------------
  # Conditions — override transpile_rules for unsupported-op warnings
  # ---------------------------------------------------------------------------

  defp transpile_rules(rules) do
    {parts, warnings} =
      Enum.reduce(rules, {[], []}, fn rule, {parts_acc, warn_acc} ->
        case ink_transpile_rule(rule) do
          {:ok, expr} -> {[expr | parts_acc], warn_acc}
          {:warning, expr, w} -> {[expr | parts_acc], [w | warn_acc]}
          :skip -> {parts_acc, warn_acc}
        end
      end)

    {Enum.reverse(parts), Enum.reverse(warnings)}
  end

  defp ink_transpile_rule(%{"sheet" => sheet, "variable" => var, "operator" => op} = rule)
       when is_binary(sheet) and sheet != "" and is_binary(var) and var != "" do
    ref = Helpers.format_var_ref(sheet, var, @var_style)

    if op in @unsupported_condition_ops do
      warning = Helpers.unsupported_op_warning(op, "Ink", "#{sheet}.#{var}")
      # H2 fix: emit valid expression instead of bare comment
      fallback = "true"
      {:warning, fallback, warning}
    else
      {:ok, emit_condition_op(ref, op, rule["value"])}
    end
  end

  defp ink_transpile_rule(_), do: :skip

  # ---------------------------------------------------------------------------
  # Condition operators
  # ---------------------------------------------------------------------------

  defp emit_condition_op(ref, "is_true", _), do: ref
  defp emit_condition_op(ref, "is_false", _), do: "not #{ref}"
  defp emit_condition_op(ref, "is_empty", _), do: ~s(#{ref} == "")

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
  # Instruction operators
  # ---------------------------------------------------------------------------

  defp emit_assignment(ref, "set", a), do: "~ #{ref} = #{format_value(ref, a)}"
  defp emit_assignment(ref, "add", a), do: "~ #{ref} += #{format_value(ref, a)}"
  defp emit_assignment(ref, "subtract", a), do: "~ #{ref} -= #{format_value(ref, a)}"
  defp emit_assignment(ref, "set_true", _), do: "~ #{ref} = true"
  defp emit_assignment(ref, "set_false", _), do: "~ #{ref} = false"
  defp emit_assignment(ref, "toggle", _), do: "~ #{ref} = not #{ref}"
  defp emit_assignment(ref, "clear", _), do: ~s(~ #{ref} = "")

  # M1/M2 fix: Ink has no null — all variables are initialized at declaration.
  # Emit unconditional assignment instead of broken null check.
  defp emit_assignment(ref, "set_if_unset", a) do
    val = format_value(ref, a)
    "~ #{ref} = #{val}"
  end

  defp emit_assignment(ref, _op, a), do: "~ #{ref} = #{format_value(ref, a)}"
end
