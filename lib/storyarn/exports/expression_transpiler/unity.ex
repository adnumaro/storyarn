defmodule Storyarn.Exports.ExpressionTranspiler.Unity do
  @moduledoc """
  Unity (Lua) expression emitter for Dialogue System for Unity.

  Variable format: `Variable["mc.jaime.health"]`
  Logic: `and` / `or` (parenthesized)
  Not-equals: `~=` (Lua style)
  """

  use Storyarn.Exports.ExpressionTranspiler.Base,
    var_style: :lua_dict,
    logic_opts: [and_keyword: " and ", or_keyword: " or "],
    literal_opts: [null_keyword: "nil"]

  # ---------------------------------------------------------------------------
  # Override join_condition — Unity wraps each part in parentheses
  # ---------------------------------------------------------------------------

  defp join_condition(logic, [_, _ | _] = parts) do
    wrapped = Enum.map(parts, &"(#{&1})")
    Helpers.join_with_logic(logic, wrapped, @logic_opts)
  end

  defp join_condition(_logic, parts), do: Enum.join(parts)

  # ---------------------------------------------------------------------------
  # Condition operators
  # ---------------------------------------------------------------------------

  defp emit_condition_op(ref, "is_true", _), do: "#{ref} == true"
  defp emit_condition_op(ref, "is_false", _), do: "#{ref} == false"
  defp emit_condition_op(ref, "is_nil", _), do: "#{ref} == nil"
  defp emit_condition_op(ref, "is_empty", _), do: ~s(#{ref} == "")

  defp emit_condition_op(ref, "contains", val),
    do: "string.find(#{ref}, #{Helpers.format_literal(val, @literal_opts)}) ~= nil"

  defp emit_condition_op(ref, "not_contains", val),
    do: "string.find(#{ref}, #{Helpers.format_literal(val, @literal_opts)}) == nil"

  defp emit_condition_op(ref, "starts_with", val) do
    lit = Helpers.format_literal(val, @literal_opts)
    "string.sub(#{ref}, 1, string.len(#{lit})) == #{lit}"
  end

  defp emit_condition_op(ref, "ends_with", val) do
    lit = Helpers.format_literal(val, @literal_opts)
    "string.sub(#{ref}, -string.len(#{lit})) == #{lit}"
  end

  defp emit_condition_op(ref, "before", val),
    do: "#{ref} < #{Helpers.format_literal(val, @literal_opts)}"

  defp emit_condition_op(ref, "after", val),
    do: "#{ref} > #{Helpers.format_literal(val, @literal_opts)}"

  defp emit_condition_op(ref, op, value) do
    "#{ref} #{condition_op(op)} #{Helpers.format_literal(value, @literal_opts)}"
  end

  defp condition_op("equals"), do: "=="
  defp condition_op("not_equals"), do: "~="
  defp condition_op("greater_than"), do: ">"
  defp condition_op("less_than"), do: "<"
  defp condition_op("greater_than_or_equal"), do: ">="
  defp condition_op("less_than_or_equal"), do: "<="
  defp condition_op(op), do: op

  # ---------------------------------------------------------------------------
  # Instruction operators
  # ---------------------------------------------------------------------------

  defp emit_assignment(ref, "set", a), do: "#{ref} = #{format_value(ref, a)}"
  defp emit_assignment(ref, "add", a), do: "#{ref} = #{ref} + #{format_value(ref, a)}"
  defp emit_assignment(ref, "subtract", a), do: "#{ref} = #{ref} - #{format_value(ref, a)}"
  defp emit_assignment(ref, "set_true", _), do: "#{ref} = true"
  defp emit_assignment(ref, "set_false", _), do: "#{ref} = false"
  defp emit_assignment(ref, "toggle", _), do: "#{ref} = not #{ref}"
  defp emit_assignment(ref, "clear", _), do: ~s(#{ref} = "")

  defp emit_assignment(ref, "set_if_unset", a) do
    val = format_value(ref, a)
    "if #{ref} == nil then #{ref} = #{val} end"
  end

  defp emit_assignment(ref, _op, a), do: "#{ref} = #{format_value(ref, a)}"
end
