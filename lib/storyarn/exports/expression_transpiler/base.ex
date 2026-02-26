defmodule Storyarn.Exports.ExpressionTranspiler.Base do
  @moduledoc """
  Shared scaffolding for expression transpiler emitters.

  Provides the common condition/instruction traversal logic that all 6
  engine emitters share. Each emitter `use`s this module and only needs
  to define its engine-specific callbacks:

  - `emit_condition_op/3` — how a single condition rule renders
  - `emit_assignment/3` — how a single instruction assignment renders
  - `condition_op/1` — operator symbol mapping
  - `format_value/2` — value formatting (literal or variable ref)

  Optional overrides:
  - `transpile_rule/1` — full rule rendering (Ink overrides for warnings)
  - `join_condition/2` — how condition parts combine (Unity overrides for parens)

  ## Usage

      defmodule MyEngine do
        use Storyarn.Exports.ExpressionTranspiler.Base,
          var_style: :underscore,
          logic_opts: [and_keyword: " and ", or_keyword: " or "],
          literal_opts: [null_keyword: "null"]
      end
  """

  defmacro __using__(opts) do
    var_style = Keyword.fetch!(opts, :var_style)
    logic_opts = Keyword.fetch!(opts, :logic_opts)
    literal_opts = Keyword.get(opts, :literal_opts, [])

    quote do
      @behaviour Storyarn.Exports.ExpressionTranspiler

      alias Storyarn.Exports.ExpressionTranspiler.Helpers

      @var_style unquote(var_style)
      @logic_opts unquote(logic_opts)
      @literal_opts unquote(literal_opts)

      # -----------------------------------------------------------------------
      # Conditions
      # -----------------------------------------------------------------------

      @impl true
      def transpile_condition(nil, _ctx), do: {:ok, "", []}
      def transpile_condition(%{"rules" => []}, _ctx), do: {:ok, "", []}
      def transpile_condition(%{"blocks" => []}, _ctx), do: {:ok, "", []}

      def transpile_condition(condition, _ctx) do
        case Helpers.extract_condition_structure(condition) do
          {:flat, logic, rules} ->
            {parts, warnings} = transpile_rules(rules)
            {:ok, join_condition(logic, parts), warnings}

          {:blocks, top_logic, groups} ->
            {parts, warnings} = transpile_groups(groups)
            {:ok, join_condition(top_logic, parts), warnings}
        end
      end

      defp join_condition(logic, parts) do
        Helpers.join_with_logic(logic, parts, @logic_opts)
      end

      defoverridable join_condition: 2

      defp transpile_groups(groups) do
        {parts, warnings} =
          Enum.reduce(groups, {[], []}, fn group, {parts_acc, warn_acc} ->
            case transpile_group(group) do
              {:ok, part, ws} -> {[part | parts_acc], ws ++ warn_acc}
              :skip -> {parts_acc, warn_acc}
            end
          end)

        {Enum.reverse(parts), Enum.reverse(warnings)}
      end

      defp transpile_group({logic, items}) when is_list(items) do
        {parts, warnings} =
          case classify_items(items) do
            :rules -> transpile_rules(items)
            :groups -> transpile_groups(items)
          end

        {:ok, maybe_paren(join_condition(logic, parts), parts), warnings}
      end

      defp transpile_group(_), do: :skip

      defp classify_items([%{"operator" => _} | _]), do: :rules
      defp classify_items(_), do: :groups

      defp maybe_paren(expr, [_, _ | _]), do: "(#{expr})"
      defp maybe_paren(expr, _), do: expr

      defp transpile_rules(rules) do
        {parts, warnings} =
          Enum.reduce(rules, {[], []}, fn rule, {parts_acc, warn_acc} ->
            case transpile_rule(rule) do
              {:ok, expr} -> {[expr | parts_acc], warn_acc}
              :skip -> {parts_acc, warn_acc}
            end
          end)

        {Enum.reverse(parts), Enum.reverse(warnings)}
      end

      defoverridable transpile_rules: 1

      defp transpile_rule(%{"sheet" => sheet, "variable" => var, "operator" => op} = rule)
           when is_binary(sheet) and sheet != "" and is_binary(var) and var != "" do
        ref = Helpers.format_var_ref(sheet, var, @var_style)
        {:ok, emit_condition_op(ref, op, rule["value"])}
      end

      defp transpile_rule(_), do: :skip

      defoverridable transpile_rule: 1

      # -----------------------------------------------------------------------
      # Instructions
      # -----------------------------------------------------------------------

      @impl true
      def transpile_instruction(assignments, _ctx) when is_list(assignments) do
        {lines, warnings} =
          Enum.reduce(assignments, {[], []}, fn a, {lines_acc, warn_acc} ->
            case transpile_assignment(a) do
              {:ok, line} -> {[line | lines_acc], warn_acc}
              :skip -> {lines_acc, warn_acc}
            end
          end)

        {:ok, lines |> Enum.reverse() |> Enum.join("\n"), warnings}
      end

      def transpile_instruction(_, _ctx), do: {:ok, "", []}

      defp transpile_assignment(%{"sheet" => s, "variable" => v, "operator" => op} = a)
           when is_binary(s) and s != "" and is_binary(v) and v != "" do
        ref = Helpers.format_var_ref(s, v, @var_style)
        {:ok, emit_assignment(ref, op, a)}
      end

      defp transpile_assignment(_), do: :skip

      defp format_value(_ref, %{"value_type" => "variable_ref", "value_sheet" => vs, "value" => v})
           when is_binary(vs) and vs != "" and is_binary(v) and v != "" do
        Helpers.format_var_ref(vs, v, @var_style)
      end

      defp format_value(_ref, %{"value" => value}),
        do: Helpers.format_literal(value, @literal_opts)

      defp format_value(_ref, _), do: "0"
    end
  end
end
