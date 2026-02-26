defmodule Storyarn.Exports.ExpressionTranspiler.BaseTest do
  @moduledoc """
  Tests for the shared scaffolding injected by ExpressionTranspiler.Base.

  Defines a minimal test emitter that uses the Base macro, then exercises
  the traversal logic (condition/instruction routing, nil handling, block
  format, rule skipping, etc.) that every concrete emitter inherits.
  """
  use ExUnit.Case, async: true

  # ---------------------------------------------------------------------------
  # Minimal test emitter — simplest possible callbacks so we can isolate
  # the Base-provided traversal logic from engine-specific formatting.
  # ---------------------------------------------------------------------------

  defmodule TestEmitter do
    use Storyarn.Exports.ExpressionTranspiler.Base,
      var_style: :underscore,
      logic_opts: [and_keyword: " AND ", or_keyword: " OR "],
      literal_opts: [null_keyword: "NULL"]

    defp emit_condition_op(ref, "is_true", _), do: "#{ref}"
    defp emit_condition_op(ref, "is_false", _), do: "NOT #{ref}"
    defp emit_condition_op(ref, "is_nil", _), do: "#{ref} IS NULL"
    defp emit_condition_op(ref, "is_empty", _), do: ~s(#{ref} == "")

    defp emit_condition_op(ref, op, value) do
      "#{ref} #{condition_op(op)} #{Helpers.format_literal(value, @literal_opts)}"
    end

    defp condition_op("equals"), do: "=="
    defp condition_op("not_equals"), do: "!="
    defp condition_op("greater_than"), do: ">"
    defp condition_op("less_than"), do: "<"
    defp condition_op(op), do: op

    defp emit_assignment(ref, "set", a), do: "#{ref} = #{format_value(ref, a)}"
    defp emit_assignment(ref, "add", a), do: "#{ref} += #{format_value(ref, a)}"
    defp emit_assignment(ref, "set_true", _), do: "#{ref} = true"
    defp emit_assignment(ref, "set_false", _), do: "#{ref} = false"
    defp emit_assignment(ref, _op, a), do: "#{ref} = #{format_value(ref, a)}"
  end

  # ---------------------------------------------------------------------------
  # Test data helpers
  # ---------------------------------------------------------------------------

  defp rule(sheet \\ "mc.jaime", variable \\ "health", operator \\ "equals", value \\ "50") do
    %{
      "id" => "rule_1",
      "sheet" => sheet,
      "variable" => variable,
      "operator" => operator,
      "value" => value
    }
  end

  defp flat_condition(logic \\ "all", rules) do
    %{"logic" => logic, "rules" => rules}
  end

  defp block_condition(logic, blocks) do
    %{"logic" => logic, "blocks" => blocks}
  end

  defp make_block(id, block_logic, rules) do
    %{"id" => id, "type" => "block", "logic" => block_logic, "rules" => rules}
  end

  defp make_group(id, group_logic, inner_blocks) do
    %{"id" => id, "type" => "group", "logic" => group_logic, "blocks" => inner_blocks}
  end

  defp assignment(operator, value \\ "10", opts \\ []) do
    %{
      "id" => "assign_1",
      "sheet" => Keyword.get(opts, :sheet, "mc.jaime"),
      "variable" => Keyword.get(opts, :variable, "health"),
      "operator" => operator,
      "value" => value,
      "value_type" => Keyword.get(opts, :value_type, "literal"),
      "value_sheet" => Keyword.get(opts, :value_sheet)
    }
  end

  # =============================================================================
  # transpile_condition/2 — nil and empty inputs
  # =============================================================================

  describe "transpile_condition/2 nil and empty inputs" do
    test "nil condition returns empty string with no warnings" do
      assert {:ok, "", []} = TestEmitter.transpile_condition(nil, %{})
    end

    test "condition with empty rules returns empty string" do
      assert {:ok, "", []} = TestEmitter.transpile_condition(%{"rules" => []}, %{})
    end

    test "condition with empty blocks returns empty string" do
      assert {:ok, "", []} = TestEmitter.transpile_condition(%{"blocks" => []}, %{})
    end
  end

  # =============================================================================
  # transpile_condition/2 — flat format
  # =============================================================================

  describe "transpile_condition/2 flat format" do
    test "single rule produces expected expression" do
      condition = flat_condition([rule()])
      {:ok, result, warnings} = TestEmitter.transpile_condition(condition, %{})

      assert result == "mc_jaime_health == 50"
      assert warnings == []
    end

    test "multiple rules joined with AND" do
      r1 = rule("mc.jaime", "health", "equals", "50")
      r2 = rule("mc.jaime", "mana", "greater_than", "30")
      condition = flat_condition("all", [r1, r2])

      {:ok, result, _} = TestEmitter.transpile_condition(condition, %{})
      assert result == "mc_jaime_health == 50 AND mc_jaime_mana > 30"
    end

    test "multiple rules joined with OR" do
      r1 = rule("mc.jaime", "health", "equals", "50")
      r2 = rule("mc.jaime", "mana", "less_than", "10")
      condition = flat_condition("any", [r1, r2])

      {:ok, result, _} = TestEmitter.transpile_condition(condition, %{})
      assert result == "mc_jaime_health == 50 OR mc_jaime_mana < 10"
    end

    test "boolean operators" do
      {:ok, result, _} =
        TestEmitter.transpile_condition(flat_condition([rule("player", "alive", "is_true")]), %{})

      assert result == "player_alive"

      {:ok, result, _} =
        TestEmitter.transpile_condition(
          flat_condition([rule("player", "dead", "is_false")]),
          %{}
        )

      assert result == "NOT player_dead"
    end

    test "is_nil operator" do
      {:ok, result, _} =
        TestEmitter.transpile_condition(
          flat_condition([rule("player", "quest", "is_nil")]),
          %{}
        )

      assert result == "player_quest IS NULL"
    end

    test "is_empty operator" do
      {:ok, result, _} =
        TestEmitter.transpile_condition(
          flat_condition([rule("player", "name", "is_empty")]),
          %{}
        )

      assert result == ~s(player_name == "")
    end
  end

  # =============================================================================
  # transpile_condition/2 — rule skipping
  # =============================================================================

  describe "transpile_condition/2 rule skipping" do
    test "rule with nil sheet is skipped" do
      r = rule(nil, "health", "equals", "50")
      condition = flat_condition([r])
      {:ok, result, _} = TestEmitter.transpile_condition(condition, %{})
      assert result == ""
    end

    test "rule with empty sheet is skipped" do
      r = rule("", "health", "equals", "50")
      condition = flat_condition([r])
      {:ok, result, _} = TestEmitter.transpile_condition(condition, %{})
      assert result == ""
    end

    test "rule with nil variable is skipped" do
      r = rule("mc.jaime", nil, "equals", "50")
      condition = flat_condition([r])
      {:ok, result, _} = TestEmitter.transpile_condition(condition, %{})
      assert result == ""
    end

    test "rule with empty variable is skipped" do
      r = rule("mc.jaime", "", "equals", "50")
      condition = flat_condition([r])
      {:ok, result, _} = TestEmitter.transpile_condition(condition, %{})
      assert result == ""
    end

    test "rule missing operator key is skipped" do
      r = %{"id" => "r1", "sheet" => "mc.jaime", "variable" => "health", "value" => "50"}
      condition = flat_condition([r])
      {:ok, result, _} = TestEmitter.transpile_condition(condition, %{})
      assert result == ""
    end

    test "completely malformed rule is skipped" do
      condition = flat_condition([%{"random" => "data"}, %{}])
      {:ok, result, _} = TestEmitter.transpile_condition(condition, %{})
      assert result == ""
    end

    test "valid rules are kept even when invalid ones are mixed in" do
      valid_rule = rule()
      invalid_rule = %{"sheet" => nil, "variable" => "x", "operator" => "equals", "value" => "1"}
      condition = flat_condition([invalid_rule, valid_rule])

      {:ok, result, _} = TestEmitter.transpile_condition(condition, %{})
      assert result == "mc_jaime_health == 50"
    end
  end

  # =============================================================================
  # transpile_condition/2 — block format
  # =============================================================================

  describe "transpile_condition/2 block format" do
    test "single block with one rule" do
      block = make_block("b1", "all", [rule()])
      condition = block_condition("all", [block])

      {:ok, result, _} = TestEmitter.transpile_condition(condition, %{})
      assert result == "mc_jaime_health == 50"
    end

    test "single block with multiple rules parenthesizes" do
      rules = [
        rule("mc.jaime", "health", "equals", "50"),
        rule("mc.jaime", "mana", "greater_than", "30")
      ]

      block = make_block("b1", "all", rules)
      condition = block_condition("all", [block])

      {:ok, result, _} = TestEmitter.transpile_condition(condition, %{})
      assert result == "(mc_jaime_health == 50 AND mc_jaime_mana > 30)"
    end

    test "multiple blocks joined with top-level logic" do
      b1 = make_block("b1", "all", [rule("mc.jaime", "health", "equals", "50")])
      b2 = make_block("b2", "all", [rule("mc.jaime", "mana", "greater_than", "30")])
      condition = block_condition("any", [b1, b2])

      {:ok, result, _} = TestEmitter.transpile_condition(condition, %{})
      assert result == "mc_jaime_health == 50 OR mc_jaime_mana > 30"
    end

    test "block with OR logic inside AND top-level" do
      b1 =
        make_block("b1", "any", [
          rule("mc.jaime", "health", "equals", "50"),
          rule("mc.jaime", "health", "equals", "100")
        ])

      condition = block_condition("all", [b1])

      {:ok, result, _} = TestEmitter.transpile_condition(condition, %{})
      assert result == "(mc_jaime_health == 50 OR mc_jaime_health == 100)"
    end

    test "nested group with inner blocks" do
      inner1 = make_block("b1", "all", [rule("mc.jaime", "health", "equals", "50")])
      inner2 = make_block("b2", "all", [rule("mc.jaime", "mana", "greater_than", "30")])
      group = make_group("g1", "all", [inner1, inner2])
      condition = block_condition("any", [group])

      {:ok, result, _} = TestEmitter.transpile_condition(condition, %{})
      assert result == "(mc_jaime_health == 50 AND mc_jaime_mana > 30)"
    end

    test "empty blocks list returns empty string" do
      condition = block_condition("all", [])
      {:ok, result, _} = TestEmitter.transpile_condition(condition, %{})
      assert result == ""
    end

    test "malformed blocks are filtered out" do
      bad_block = %{"type" => "unknown"}
      good_block = make_block("b1", "all", [rule()])
      condition = block_condition("all", [bad_block, good_block])

      {:ok, result, _} = TestEmitter.transpile_condition(condition, %{})
      assert result == "mc_jaime_health == 50"
    end
  end

  # =============================================================================
  # transpile_instruction/2 — basic operations
  # =============================================================================

  describe "transpile_instruction/2 basic operations" do
    test "single set assignment" do
      {:ok, result, warnings} = TestEmitter.transpile_instruction([assignment("set")], %{})
      assert result == "mc_jaime_health = 10"
      assert warnings == []
    end

    test "add assignment" do
      {:ok, result, _} = TestEmitter.transpile_instruction([assignment("add")], %{})
      assert result == "mc_jaime_health += 10"
    end

    test "set_true assignment" do
      {:ok, result, _} = TestEmitter.transpile_instruction([assignment("set_true", nil)], %{})
      assert result == "mc_jaime_health = true"
    end

    test "set_false assignment" do
      {:ok, result, _} = TestEmitter.transpile_instruction([assignment("set_false", nil)], %{})
      assert result == "mc_jaime_health = false"
    end

    test "multiple assignments joined with newlines" do
      a1 = assignment("set", "100")
      a2 = assignment("set_true", nil, variable: "alive")

      {:ok, result, _} = TestEmitter.transpile_instruction([a1, a2], %{})
      lines = String.split(result, "\n")
      assert length(lines) == 2
      assert Enum.at(lines, 0) == "mc_jaime_health = 100"
      assert Enum.at(lines, 1) == "mc_jaime_alive = true"
    end
  end

  # =============================================================================
  # transpile_instruction/2 — nil and empty inputs
  # =============================================================================

  describe "transpile_instruction/2 nil and empty inputs" do
    test "empty list returns empty string" do
      {:ok, result, warnings} = TestEmitter.transpile_instruction([], %{})
      assert result == ""
      assert warnings == []
    end

    test "non-list input returns empty string" do
      {:ok, result, _} = TestEmitter.transpile_instruction(nil, %{})
      assert result == ""

      {:ok, result, _} = TestEmitter.transpile_instruction("not a list", %{})
      assert result == ""
    end
  end

  # =============================================================================
  # transpile_instruction/2 — assignment skipping
  # =============================================================================

  describe "transpile_instruction/2 assignment skipping" do
    test "assignment with nil sheet is skipped" do
      a = %{assignment("set") | "sheet" => nil}
      {:ok, result, _} = TestEmitter.transpile_instruction([a], %{})
      assert result == ""
    end

    test "assignment with empty sheet is skipped" do
      a = %{assignment("set") | "sheet" => ""}
      {:ok, result, _} = TestEmitter.transpile_instruction([a], %{})
      assert result == ""
    end

    test "assignment with nil variable is skipped" do
      a = %{assignment("set") | "variable" => nil}
      {:ok, result, _} = TestEmitter.transpile_instruction([a], %{})
      assert result == ""
    end

    test "assignment with empty variable is skipped" do
      a = %{assignment("set") | "variable" => ""}
      {:ok, result, _} = TestEmitter.transpile_instruction([a], %{})
      assert result == ""
    end

    test "assignment missing required keys is skipped" do
      a = %{"random" => "data"}
      {:ok, result, _} = TestEmitter.transpile_instruction([a], %{})
      assert result == ""
    end

    test "valid assignments kept when mixed with invalid ones" do
      valid = assignment("set")
      invalid = %{assignment("set") | "sheet" => ""}

      {:ok, result, _} = TestEmitter.transpile_instruction([invalid, valid], %{})
      assert result == "mc_jaime_health = 10"
    end
  end

  # =============================================================================
  # transpile_instruction/2 — format_value (variable references)
  # =============================================================================

  describe "transpile_instruction/2 variable references" do
    test "variable_ref value type resolves to variable reference" do
      a = %{
        "sheet" => "mc.jaime",
        "variable" => "health",
        "operator" => "set",
        "value" => "max_health",
        "value_type" => "variable_ref",
        "value_sheet" => "stats.base"
      }

      {:ok, result, _} = TestEmitter.transpile_instruction([a], %{})
      assert result == "mc_jaime_health = stats_base_max_health"
    end

    test "variable_ref with empty value_sheet falls back to literal formatting" do
      a = %{
        "sheet" => "mc.jaime",
        "variable" => "health",
        "operator" => "set",
        "value" => "some_value",
        "value_type" => "variable_ref",
        "value_sheet" => ""
      }

      {:ok, result, _} = TestEmitter.transpile_instruction([a], %{})
      # Falls through to format_literal since value_sheet is empty
      assert result =~ "mc_jaime_health = "
    end

    test "variable_ref with nil value_sheet falls back to literal formatting" do
      a = %{
        "sheet" => "mc.jaime",
        "variable" => "health",
        "operator" => "set",
        "value" => "42",
        "value_type" => "variable_ref",
        "value_sheet" => nil
      }

      {:ok, result, _} = TestEmitter.transpile_instruction([a], %{})
      assert result == "mc_jaime_health = 42"
    end
  end

  # =============================================================================
  # transpile_instruction/2 — format_value (literal values)
  # =============================================================================

  describe "transpile_instruction/2 literal values" do
    test "numeric string value stays unquoted" do
      {:ok, result, _} = TestEmitter.transpile_instruction([assignment("set", "42")], %{})
      assert result == "mc_jaime_health = 42"
    end

    test "string value gets quoted" do
      a = assignment("set", "warrior", variable: "class")
      {:ok, result, _} = TestEmitter.transpile_instruction([a], %{})
      assert result == ~s(mc_jaime_class = "warrior")
    end

    test "nil value uses null keyword" do
      a = assignment("set", nil)
      {:ok, result, _} = TestEmitter.transpile_instruction([a], %{})
      assert result == "mc_jaime_health = NULL"
    end

    test "assignment with no value key defaults to 0" do
      a = %{"sheet" => "mc.jaime", "variable" => "health", "operator" => "set"}
      {:ok, result, _} = TestEmitter.transpile_instruction([a], %{})
      assert result == "mc_jaime_health = 0"
    end

    test "boolean string value stays unquoted" do
      {:ok, result, _} = TestEmitter.transpile_instruction([assignment("set", "true")], %{})
      assert result == "mc_jaime_health = true"
    end
  end

  # =============================================================================
  # var_style configuration
  # =============================================================================

  describe "var_style configuration" do
    test "underscore style flattens dots in variable references" do
      r = rule("mc.jaime", "health.max", "equals", "50")
      {:ok, result, _} = TestEmitter.transpile_condition(flat_condition([r]), %{})
      assert result == "mc_jaime_health_max == 50"
    end

    test "underscore style flattens hyphens in variable references" do
      r = rule("mc-jaime", "max-health", "equals", "50")
      {:ok, result, _} = TestEmitter.transpile_condition(flat_condition([r]), %{})
      assert result == "mc_jaime_max_health == 50"
    end
  end

  # =============================================================================
  # logic_opts configuration
  # =============================================================================

  describe "logic_opts configuration" do
    test "custom AND keyword is used" do
      r1 = rule("mc.jaime", "health", "equals", "50")
      r2 = rule("mc.jaime", "mana", "equals", "30")
      condition = flat_condition("all", [r1, r2])

      {:ok, result, _} = TestEmitter.transpile_condition(condition, %{})
      assert result =~ " AND "
    end

    test "custom OR keyword is used" do
      r1 = rule("mc.jaime", "health", "equals", "50")
      r2 = rule("mc.jaime", "mana", "equals", "30")
      condition = flat_condition("any", [r1, r2])

      {:ok, result, _} = TestEmitter.transpile_condition(condition, %{})
      assert result =~ " OR "
    end
  end

  # =============================================================================
  # Context parameter is passed through
  # =============================================================================

  describe "context parameter" do
    test "context is accepted by transpile_condition but does not affect Base logic" do
      condition = flat_condition([rule()])
      context = %{flow_id: "abc123", engine: :test}

      {:ok, result, _} = TestEmitter.transpile_condition(condition, context)
      assert result == "mc_jaime_health == 50"
    end

    test "context is accepted by transpile_instruction but does not affect Base logic" do
      context = %{flow_id: "abc123", engine: :test}
      {:ok, result, _} = TestEmitter.transpile_instruction([assignment("set")], context)
      assert result == "mc_jaime_health = 10"
    end
  end
end
