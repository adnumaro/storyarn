defmodule Storyarn.Exports.ExpressionTranspiler.ConditionTest do
  use ExUnit.Case, async: true

  alias Storyarn.Exports.ExpressionTranspiler

  # =============================================================================
  # Test Data
  # =============================================================================

  defp simple_rule(operator, value \\ "50") do
    %{
      "id" => "rule_1",
      "sheet" => "mc.jaime",
      "variable" => "health",
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

  # =============================================================================
  # Comparison operators (all engines) — exact assertions
  # =============================================================================

  @comparison_operators [
    {"equals", "=="},
    {"not_equals", "!="},
    {"greater_than", ">"},
    {"less_than", "<"},
    {"greater_than_or_equal", ">="},
    {"less_than_or_equal", "<="}
  ]

  @engines_with_var_ref %{
    ink: "mc_jaime_health",
    yarn: "$mc_jaime_health",
    unity: ~s(Variable["mc.jaime.health"]),
    godot: "mc_jaime_health",
    unreal: "mc.jaime.health",
    articy: "mc.jaime.health"
  }

  for {operator, default_op} <- @comparison_operators do
    describe "condition operator #{operator}" do
      for {engine, var_ref} <- @engines_with_var_ref do
        # Unity uses ~= for not_equals
        expected =
          case {operator, engine} do
            {"not_equals", :unity} -> "~="
            _ -> default_op
          end

        test "#{engine} emits exact expression" do
          condition = flat_condition([simple_rule(unquote(operator))])

          {:ok, result, warnings} =
            ExpressionTranspiler.transpile_condition(condition, unquote(engine))

          assert result == "#{unquote(var_ref)} #{unquote(expected)} 50"
          assert warnings == []
        end
      end
    end
  end

  # =============================================================================
  # Boolean operators — all engines with exact assertions
  # =============================================================================

  describe "is_true operator" do
    @is_true_expected %{
      ink: "mc_jaime_health",
      yarn: "$mc_jaime_health == true",
      unity: ~s(Variable["mc.jaime.health"] == true),
      godot: "mc_jaime_health == true",
      unreal: "mc.jaime.health == true",
      articy: "mc.jaime.health == true"
    }

    for {engine, expected} <- @is_true_expected do
      test "#{engine} emits #{inspect(expected)}" do
        condition = flat_condition([simple_rule("is_true", nil)])
        {:ok, result, _} = ExpressionTranspiler.transpile_condition(condition, unquote(engine))
        assert result == unquote(expected)
      end
    end
  end

  describe "is_false operator" do
    @is_false_expected %{
      ink: "not mc_jaime_health",
      yarn: "$mc_jaime_health == false",
      unity: ~s(Variable["mc.jaime.health"] == false),
      godot: "mc_jaime_health == false",
      unreal: "mc.jaime.health == false",
      articy: "mc.jaime.health == false"
    }

    for {engine, expected} <- @is_false_expected do
      test "#{engine} emits #{inspect(expected)}" do
        condition = flat_condition([simple_rule("is_false", nil)])
        {:ok, result, _} = ExpressionTranspiler.transpile_condition(condition, unquote(engine))
        assert result == unquote(expected)
      end
    end
  end

  describe "is_nil operator" do
    test "ink emits warning" do
      condition = flat_condition([simple_rule("is_nil", nil)])
      {:ok, _result, warnings} = ExpressionTranspiler.transpile_condition(condition, :ink)
      assert Enum.any?(warnings, &(&1.type == :unsupported_operator))
    end

    @is_nil_expected %{
      yarn: ~s($mc_jaime_health == ""),
      unity: ~s(Variable["mc.jaime.health"] == nil),
      godot: "mc_jaime_health == null",
      unreal: "mc.jaime.health == None",
      articy: "mc.jaime.health == null"
    }

    for {engine, expected} <- @is_nil_expected do
      test "#{engine} emits #{inspect(expected)}" do
        condition = flat_condition([simple_rule("is_nil", nil)])
        {:ok, result, _} = ExpressionTranspiler.transpile_condition(condition, unquote(engine))
        assert result == unquote(expected)
      end
    end
  end

  describe "is_empty operator" do
    @is_empty_expected %{
      ink: ~s(mc_jaime_health == ""),
      yarn: ~s($mc_jaime_health == ""),
      unity: ~s(Variable["mc.jaime.health"] == ""),
      godot: ~s(mc_jaime_health == ""),
      unreal: ~s(mc.jaime.health == ""),
      articy: ~s(mc.jaime.health == "")
    }

    for {engine, expected} <- @is_empty_expected do
      test "#{engine} emits exact empty string check" do
        condition = flat_condition([simple_rule("is_empty", nil)])
        {:ok, result, _} = ExpressionTranspiler.transpile_condition(condition, unquote(engine))
        assert result == unquote(expected)
      end
    end
  end

  # =============================================================================
  # String operators — all engines with exact assertions
  # =============================================================================

  describe "ink string operator warnings" do
    for op <- ~w(contains not_contains starts_with ends_with) do
      test "#{op} emits unsupported_operator warning" do
        condition = flat_condition([simple_rule(unquote(op), "test")])
        {:ok, result, warnings} = ExpressionTranspiler.transpile_condition(condition, :ink)

        assert Enum.any?(warnings, &(&1.type == :unsupported_operator))
        assert result =~ "/*"
      end
    end
  end

  describe "yarn string operators" do
    test "contains" do
      condition = flat_condition([simple_rule("contains", "test")])
      {:ok, result, _} = ExpressionTranspiler.transpile_condition(condition, :yarn)
      assert result == ~s[string_contains($mc_jaime_health, "test")]
    end

    test "not_contains" do
      condition = flat_condition([simple_rule("not_contains", "test")])
      {:ok, result, _} = ExpressionTranspiler.transpile_condition(condition, :yarn)
      assert result == ~s[!string_contains($mc_jaime_health, "test")]
    end

    test "starts_with" do
      condition = flat_condition([simple_rule("starts_with", "test")])
      {:ok, result, _} = ExpressionTranspiler.transpile_condition(condition, :yarn)
      assert result == ~s[string_starts_with($mc_jaime_health, "test")]
    end

    test "ends_with" do
      condition = flat_condition([simple_rule("ends_with", "test")])
      {:ok, result, _} = ExpressionTranspiler.transpile_condition(condition, :yarn)
      assert result == ~s[string_ends_with($mc_jaime_health, "test")]
    end
  end

  describe "unity string operators" do
    test "contains uses string.find" do
      condition = flat_condition([simple_rule("contains", "test")])
      {:ok, result, _} = ExpressionTranspiler.transpile_condition(condition, :unity)
      assert result == ~s|string.find(Variable["mc.jaime.health"], "test") ~= nil|
    end

    test "not_contains uses string.find == nil" do
      condition = flat_condition([simple_rule("not_contains", "test")])
      {:ok, result, _} = ExpressionTranspiler.transpile_condition(condition, :unity)
      assert result == ~s|string.find(Variable["mc.jaime.health"], "test") == nil|
    end

    test "starts_with uses string.sub" do
      condition = flat_condition([simple_rule("starts_with", "test")])
      {:ok, result, _} = ExpressionTranspiler.transpile_condition(condition, :unity)

      assert result ==
               ~s|string.sub(Variable["mc.jaime.health"], 1, string.len("test")) == "test"|
    end

    test "ends_with uses string.sub with negative index" do
      condition = flat_condition([simple_rule("ends_with", "test")])
      {:ok, result, _} = ExpressionTranspiler.transpile_condition(condition, :unity)
      assert result == ~s|string.sub(Variable["mc.jaime.health"], -string.len("test")) == "test"|
    end
  end

  describe "godot string operators" do
    test "contains uses in keyword" do
      condition = flat_condition([simple_rule("contains", "test")])
      {:ok, result, _} = ExpressionTranspiler.transpile_condition(condition, :godot)
      assert result == ~s("test" in mc_jaime_health)
    end

    test "not_contains uses not in" do
      condition = flat_condition([simple_rule("not_contains", "test")])
      {:ok, result, _} = ExpressionTranspiler.transpile_condition(condition, :godot)
      assert result == ~s("test" not in mc_jaime_health)
    end

    test "starts_with uses begins_with" do
      condition = flat_condition([simple_rule("starts_with", "test")])
      {:ok, result, _} = ExpressionTranspiler.transpile_condition(condition, :godot)
      assert result == ~s[mc_jaime_health.begins_with("test")]
    end

    test "ends_with uses ends_with" do
      condition = flat_condition([simple_rule("ends_with", "test")])
      {:ok, result, _} = ExpressionTranspiler.transpile_condition(condition, :godot)
      assert result == ~s[mc_jaime_health.ends_with("test")]
    end
  end

  describe "unreal string operators" do
    test "contains uses Contains function" do
      condition = flat_condition([simple_rule("contains", "test")])
      {:ok, result, _} = ExpressionTranspiler.transpile_condition(condition, :unreal)
      assert result == ~s[Contains(mc.jaime.health, "test")]
    end

    test "not_contains uses !Contains function" do
      condition = flat_condition([simple_rule("not_contains", "test")])
      {:ok, result, _} = ExpressionTranspiler.transpile_condition(condition, :unreal)
      assert result == ~s[!Contains(mc.jaime.health, "test")]
    end

    test "starts_with uses StartsWith function" do
      condition = flat_condition([simple_rule("starts_with", "test")])
      {:ok, result, _} = ExpressionTranspiler.transpile_condition(condition, :unreal)
      assert result == ~s[StartsWith(mc.jaime.health, "test")]
    end

    test "ends_with uses EndsWith function" do
      condition = flat_condition([simple_rule("ends_with", "test")])
      {:ok, result, _} = ExpressionTranspiler.transpile_condition(condition, :unreal)
      assert result == ~s[EndsWith(mc.jaime.health, "test")]
    end
  end

  describe "articy string operators" do
    test "contains uses contains function" do
      condition = flat_condition([simple_rule("contains", "test")])
      {:ok, result, _} = ExpressionTranspiler.transpile_condition(condition, :articy)
      assert result == ~s[contains(mc.jaime.health, "test")]
    end

    test "not_contains uses !contains function" do
      condition = flat_condition([simple_rule("not_contains", "test")])
      {:ok, result, _} = ExpressionTranspiler.transpile_condition(condition, :articy)
      assert result == ~s[!contains(mc.jaime.health, "test")]
    end

    test "starts_with uses startsWith function" do
      condition = flat_condition([simple_rule("starts_with", "test")])
      {:ok, result, _} = ExpressionTranspiler.transpile_condition(condition, :articy)
      assert result == ~s[startsWith(mc.jaime.health, "test")]
    end

    test "ends_with uses endsWith function" do
      condition = flat_condition([simple_rule("ends_with", "test")])
      {:ok, result, _} = ExpressionTranspiler.transpile_condition(condition, :articy)
      assert result == ~s[endsWith(mc.jaime.health, "test")]
    end
  end

  # =============================================================================
  # Date operators — all engines
  # =============================================================================

  describe "date operators" do
    @date_engines [:yarn, :unity, :godot, :unreal, :articy]

    for engine <- @date_engines do
      test "#{engine} emits < for before" do
        condition = flat_condition([simple_rule("before", "2026-01-01")])
        {:ok, result, _} = ExpressionTranspiler.transpile_condition(condition, unquote(engine))
        assert result =~ "< " and result =~ "2026-01-01"
      end

      test "#{engine} emits > for after" do
        condition = flat_condition([simple_rule("after", "2026-01-01")])
        {:ok, result, _} = ExpressionTranspiler.transpile_condition(condition, unquote(engine))
        assert result =~ "> " and result =~ "2026-01-01"
      end
    end

    test "ink emits warning for before" do
      condition = flat_condition([simple_rule("before", "2026-01-01")])
      {:ok, _result, warnings} = ExpressionTranspiler.transpile_condition(condition, :ink)
      assert Enum.any?(warnings, &(&1.type == :unsupported_operator))
    end

    test "ink emits warning for after" do
      condition = flat_condition([simple_rule("after", "2026-01-01")])
      {:ok, _result, warnings} = ExpressionTranspiler.transpile_condition(condition, :ink)
      assert Enum.any?(warnings, &(&1.type == :unsupported_operator))
    end
  end

  # =============================================================================
  # Logic combinators
  # =============================================================================

  describe "logic combinators" do
    setup do
      rule1 = simple_rule("equals", "50")
      rule2 = %{rule1 | "id" => "rule_2", "variable" => "mana", "value" => "30"}
      %{rule1: rule1, rule2: rule2}
    end

    test "all (AND) joins with engine-specific AND", %{rule1: r1, rule2: r2} do
      condition = flat_condition("all", [r1, r2])

      {:ok, ink, _} = ExpressionTranspiler.transpile_condition(condition, :ink)
      assert ink == "mc_jaime_health == 50 and mc_jaime_mana == 30"

      {:ok, unreal, _} = ExpressionTranspiler.transpile_condition(condition, :unreal)
      assert unreal == "mc.jaime.health == 50 AND mc.jaime.mana == 30"

      {:ok, articy, _} = ExpressionTranspiler.transpile_condition(condition, :articy)
      assert articy == "mc.jaime.health == 50 && mc.jaime.mana == 30"
    end

    test "any (OR) joins with engine-specific OR", %{rule1: r1, rule2: r2} do
      condition = flat_condition("any", [r1, r2])

      {:ok, ink, _} = ExpressionTranspiler.transpile_condition(condition, :ink)
      assert ink == "mc_jaime_health == 50 or mc_jaime_mana == 30"

      {:ok, unreal, _} = ExpressionTranspiler.transpile_condition(condition, :unreal)
      assert unreal == "mc.jaime.health == 50 OR mc.jaime.mana == 30"

      {:ok, articy, _} = ExpressionTranspiler.transpile_condition(condition, :articy)
      assert articy == "mc.jaime.health == 50 || mc.jaime.mana == 30"
    end

    test "unity wraps each part in parentheses for OR", %{rule1: r1, rule2: r2} do
      condition = flat_condition("any", [r1, r2])
      {:ok, result, _} = ExpressionTranspiler.transpile_condition(condition, :unity)

      assert result ==
               ~s|(Variable["mc.jaime.health"] == 50) or (Variable["mc.jaime.mana"] == 30)|
    end
  end

  # =============================================================================
  # Variable reference formats
  # =============================================================================

  describe "variable reference formats" do
    setup do
      %{condition: flat_condition([simple_rule("equals")])}
    end

    test "ink uses underscore", %{condition: c} do
      {:ok, result, _} = ExpressionTranspiler.transpile_condition(c, :ink)
      assert result == "mc_jaime_health == 50"
    end

    test "yarn uses $ + underscore", %{condition: c} do
      {:ok, result, _} = ExpressionTranspiler.transpile_condition(c, :yarn)
      assert result == "$mc_jaime_health == 50"
    end

    test "unity uses Variable dict", %{condition: c} do
      {:ok, result, _} = ExpressionTranspiler.transpile_condition(c, :unity)
      assert result == ~s(Variable["mc.jaime.health"] == 50)
    end

    test "godot uses underscore", %{condition: c} do
      {:ok, result, _} = ExpressionTranspiler.transpile_condition(c, :godot)
      assert result == "mc_jaime_health == 50"
    end

    test "unreal preserves dots", %{condition: c} do
      {:ok, result, _} = ExpressionTranspiler.transpile_condition(c, :unreal)
      assert result == "mc.jaime.health == 50"
    end

    test "articy preserves dots", %{condition: c} do
      {:ok, result, _} = ExpressionTranspiler.transpile_condition(c, :articy)
      assert result == "mc.jaime.health == 50"
    end
  end

  # =============================================================================
  # Block format conditions
  # =============================================================================

  describe "block format" do
    test "single block transpiles like flat rules" do
      block = make_block("b1", "all", [simple_rule("equals")])
      condition = block_condition("all", [block])

      {:ok, result, _} = ExpressionTranspiler.transpile_condition(condition, :ink)
      assert result == "mc_jaime_health == 50"
    end

    test "multiple blocks with top-level OR produce parenthesized groups" do
      b1 = make_block("b1", "all", [simple_rule("equals")])
      mana_rule = %{simple_rule("greater_than") | "variable" => "mana", "value" => "30"}
      b2 = make_block("b2", "all", [mana_rule])

      condition = block_condition("any", [b1, b2])

      {:ok, ink, _} = ExpressionTranspiler.transpile_condition(condition, :ink)
      assert ink == "mc_jaime_health == 50 or mc_jaime_mana > 30"

      {:ok, unreal, _} = ExpressionTranspiler.transpile_condition(condition, :unreal)
      assert unreal == "mc.jaime.health == 50 OR mc.jaime.mana > 30"

      {:ok, articy, _} = ExpressionTranspiler.transpile_condition(condition, :articy)
      assert articy == "mc.jaime.health == 50 || mc.jaime.mana > 30"
    end

    test "block with multiple rules joins with block logic" do
      rules = [
        simple_rule("equals"),
        %{simple_rule("greater_than") | "variable" => "mana", "value" => "30"}
      ]

      block = make_block("b1", "all", rules)
      condition = block_condition("all", [block])

      {:ok, result, _} = ExpressionTranspiler.transpile_condition(condition, :ink)
      assert result == "(mc_jaime_health == 50 and mc_jaime_mana > 30)"
    end

    test "group with nested blocks" do
      inner1 = make_block("b1", "all", [simple_rule("equals")])
      mana_rule = %{simple_rule("greater_than") | "variable" => "mana", "value" => "30"}
      inner2 = make_block("b2", "all", [mana_rule])

      group = make_group("g1", "all", [inner1, inner2])
      condition = block_condition("any", [group])

      {:ok, result, _} = ExpressionTranspiler.transpile_condition(condition, :ink)
      assert result == "(mc_jaime_health == 50 and mc_jaime_mana > 30)"
    end

    test "empty blocks returns empty string" do
      condition = block_condition("all", [])

      for engine <- [:ink, :yarn, :unity, :godot, :unreal, :articy] do
        {:ok, result, _} = ExpressionTranspiler.transpile_condition(condition, engine)
        assert result == "", "#{engine} should return empty for empty blocks"
      end
    end
  end

  # =============================================================================
  # Edge cases
  # =============================================================================

  describe "edge cases" do
    test "nil condition returns ok with empty string" do
      for engine <- [:ink, :yarn, :unity, :godot, :unreal, :articy] do
        {:ok, result, warnings} = ExpressionTranspiler.transpile_condition(nil, engine)
        assert result == ""
        assert warnings == []
      end
    end

    test "empty rules returns ok with empty string" do
      condition = flat_condition([])

      for engine <- [:ink, :yarn, :unity, :godot, :unreal, :articy] do
        {:ok, result, _} = ExpressionTranspiler.transpile_condition(condition, engine)
        assert result == ""
      end
    end

    test "JSON string condition is decoded" do
      json = Jason.encode!(%{"logic" => "all", "rules" => [simple_rule("equals")]})
      {:ok, result, _} = ExpressionTranspiler.transpile_condition(json, :ink)
      assert result == "mc_jaime_health == 50"
    end

    test "legacy string condition returns error" do
      result = ExpressionTranspiler.transpile_condition("player.health > 50", :ink)
      assert {:error, {:legacy_condition, _}} = result
    end

    test "unknown engine returns error" do
      condition = flat_condition([simple_rule("equals")])

      assert {:error, {:unknown_engine, :unknown}} =
               ExpressionTranspiler.transpile_condition(condition, :unknown)
    end

    test "incomplete rule (missing sheet) is skipped" do
      rule = %{
        "id" => "r1",
        "sheet" => nil,
        "variable" => "health",
        "operator" => "equals",
        "value" => "50"
      }

      condition = flat_condition([rule])
      {:ok, result, _} = ExpressionTranspiler.transpile_condition(condition, :ink)
      assert result == ""
    end

    test "incomplete rule (empty variable) is skipped" do
      rule = %{
        "id" => "r1",
        "sheet" => "mc.jaime",
        "variable" => "",
        "operator" => "equals",
        "value" => "50"
      }

      condition = flat_condition([rule])
      {:ok, result, _} = ExpressionTranspiler.transpile_condition(condition, :ink)
      assert result == ""
    end

    test "rule missing operator key is skipped" do
      rule = %{"id" => "r1", "sheet" => "mc.jaime", "variable" => "health", "value" => "50"}
      condition = flat_condition([rule])
      {:ok, result, _} = ExpressionTranspiler.transpile_condition(condition, :ink)
      assert result == ""
    end
  end
end
