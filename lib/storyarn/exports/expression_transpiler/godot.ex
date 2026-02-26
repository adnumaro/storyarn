defmodule Storyarn.Exports.ExpressionTranspiler.Godot do
  @moduledoc """
  Godot (GDScript) expression emitter.

  Variable format: `mc_jaime_health` (dots → underscores)
  Logic: `and` / `or`
  """

  use Storyarn.Exports.ExpressionTranspiler.Base,
    var_style: :underscore,
    logic_opts: [and_keyword: " and ", or_keyword: " or "],
    literal_opts: [null_keyword: "null"]

  # ---------------------------------------------------------------------------
  # Condition operators
  # ---------------------------------------------------------------------------

  defp emit_condition_op(ref, "is_true", _), do: "#{ref} == true"
  defp emit_condition_op(ref, "is_false", _), do: "#{ref} == false"
  defp emit_condition_op(ref, "is_nil", _), do: "#{ref} == null"
  defp emit_condition_op(ref, "is_empty", _), do: ~s(#{ref} == "")

  defp emit_condition_op(ref, "contains", val),
    do: "#{Helpers.format_literal(val, @literal_opts)} in #{ref}"

  defp emit_condition_op(ref, "not_contains", val),
    do: "#{Helpers.format_literal(val, @literal_opts)} not in #{ref}"

  defp emit_condition_op(ref, "starts_with", val),
    do: "#{ref}.begins_with(#{Helpers.format_literal(val, @literal_opts)})"

  defp emit_condition_op(ref, "ends_with", val),
    do: "#{ref}.ends_with(#{Helpers.format_literal(val, @literal_opts)})"

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

  defp emit_assignment(ref, "set", a), do: "#{ref} = #{format_value(ref, a)}"
  defp emit_assignment(ref, "add", a), do: "#{ref} += #{format_value(ref, a)}"
  defp emit_assignment(ref, "subtract", a), do: "#{ref} -= #{format_value(ref, a)}"
  defp emit_assignment(ref, "set_true", _), do: "#{ref} = true"
  defp emit_assignment(ref, "set_false", _), do: "#{ref} = false"
  defp emit_assignment(ref, "toggle", _), do: "#{ref} = !#{ref}"
  defp emit_assignment(ref, "clear", _), do: ~s(#{ref} = "")

  defp emit_assignment(ref, "set_if_unset", a) do
    val = format_value(ref, a)
    "if #{ref} == null: #{ref} = #{val}"
  end

  defp emit_assignment(ref, _op, a), do: "#{ref} = #{format_value(ref, a)}"
end
