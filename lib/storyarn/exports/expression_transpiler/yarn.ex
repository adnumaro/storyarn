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

  # ---------------------------------------------------------------------------
  # Condition operators
  # ---------------------------------------------------------------------------

  defp emit_condition_op(ref, "is_true", _), do: "#{ref} == true"
  defp emit_condition_op(ref, "is_false", _), do: "#{ref} == false"
  defp emit_condition_op(ref, "is_nil", _), do: "#{ref} == null"
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

  defp emit_assignment(ref, "set_if_unset", a) do
    val = format_value(ref, a)
    "<<if #{ref} == null>>\n<<set #{ref} to #{val}>>\n<<endif>>"
  end

  defp emit_assignment(ref, _op, a), do: "<<set #{ref} to #{format_value(ref, a)}>>"
end
