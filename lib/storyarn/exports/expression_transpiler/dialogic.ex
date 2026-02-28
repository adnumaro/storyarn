defmodule Storyarn.Exports.ExpressionTranspiler.Dialogic do
  @moduledoc """
  Godot Dialogic 2 expression emitter.

  Variable format: `{mc_jaime.health}` (curly braces, dot-scoped folder.var)
  Logic: `and` / `or`
  Instructions: `set {var} = value` prefix syntax
  """

  use Storyarn.Exports.ExpressionTranspiler.Base,
    var_style: :dialogic_curly,
    logic_opts: [and_keyword: " and ", or_keyword: " or "],
    literal_opts: [null_keyword: "null"]

  # ---------------------------------------------------------------------------
  # Conditions — override transpile_rules for semantic_loss warnings on set_if_unset
  # (conditions are identical to GDScript since Dialogic evaluates GDScript expressions)
  # ---------------------------------------------------------------------------

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
          message: "set_if_unset emits unconditional set in Dialogic (no conditional set syntax)",
          operator: "set_if_unset",
          engine: "Dialogic",
          variable: "#{s}.#{v}"
        }
      end)

    {:ok, result, warnings ++ extra_warnings}
  end

  def transpile_instruction(other, ctx), do: super(other, ctx)

  # ---------------------------------------------------------------------------
  # Instruction operators — Dialogic uses `set` prefix syntax
  # ---------------------------------------------------------------------------

  defp emit_assignment(ref, "set", a), do: "set #{ref} = #{format_value(ref, a)}"
  defp emit_assignment(ref, "add", a), do: "set #{ref} += #{format_value(ref, a)}"
  defp emit_assignment(ref, "subtract", a), do: "set #{ref} -= #{format_value(ref, a)}"
  defp emit_assignment(ref, "set_true", _), do: "set #{ref} = true"
  defp emit_assignment(ref, "set_false", _), do: "set #{ref} = false"
  defp emit_assignment(ref, "toggle", _), do: "set #{ref} = !#{ref}"
  defp emit_assignment(ref, "clear", _), do: ~s(set #{ref} = "")

  defp emit_assignment(ref, "set_if_unset", a) do
    "set #{ref} = #{format_value(ref, a)}"
  end

  defp emit_assignment(ref, _op, a), do: "set #{ref} = #{format_value(ref, a)}"
end
