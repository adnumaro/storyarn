defmodule Storyarn.Flows.ConditionOperatorsTest do
  use ExUnit.Case, async: true

  alias Storyarn.Flows.Condition

  # =============================================================================
  # logic_types/0
  # =============================================================================

  describe "logic_types/0" do
    test "returns all and any" do
      assert Condition.logic_types() == ["all", "any"]
    end
  end

  # =============================================================================
  # operators_for_type/1
  # =============================================================================

  describe "operators_for_type/1" do
    test "text operators" do
      ops = Condition.operators_for_type("text")
      assert "equals" in ops
      assert "not_equals" in ops
      assert "contains" in ops
      assert "starts_with" in ops
      assert "ends_with" in ops
      assert "is_empty" in ops
    end

    test "rich_text uses same operators as text" do
      assert Condition.operators_for_type("rich_text") == Condition.operators_for_type("text")
    end

    test "number operators" do
      ops = Condition.operators_for_type("number")
      assert "equals" in ops
      assert "not_equals" in ops
      assert "greater_than" in ops
      assert "greater_than_or_equal" in ops
      assert "less_than" in ops
      assert "less_than_or_equal" in ops
    end

    test "boolean operators" do
      ops = Condition.operators_for_type("boolean")
      assert "is_true" in ops
      assert "is_false" in ops
      assert "is_nil" in ops
      assert length(ops) == 3
    end

    test "select operators" do
      ops = Condition.operators_for_type("select")
      assert "equals" in ops
      assert "not_equals" in ops
      assert "is_nil" in ops
    end

    test "multi_select operators" do
      ops = Condition.operators_for_type("multi_select")
      assert "contains" in ops
      assert "not_contains" in ops
      assert "is_empty" in ops
    end

    test "date operators" do
      ops = Condition.operators_for_type("date")
      assert "equals" in ops
      assert "not_equals" in ops
      assert "before" in ops
      assert "after" in ops
    end

    test "reference uses select operators" do
      assert Condition.operators_for_type("reference") == Condition.operators_for_type("select")
    end

    test "unknown type falls back to text operators" do
      assert Condition.operators_for_type("unknown") == Condition.operators_for_type("text")
    end
  end

  # =============================================================================
  # operator_label/1
  # =============================================================================

  describe "operator_label/1" do
    test "returns human-readable labels for all known operators" do
      assert Condition.operator_label("equals") == "equals"
      assert Condition.operator_label("not_equals") == "not equals"
      assert Condition.operator_label("contains") == "contains"
      assert Condition.operator_label("starts_with") == "starts with"
      assert Condition.operator_label("ends_with") == "ends with"
      assert Condition.operator_label("is_empty") == "is empty"
      assert Condition.operator_label("greater_than") == ">"
      assert Condition.operator_label("greater_than_or_equal") == ">="
      assert Condition.operator_label("less_than") == "<"
      assert Condition.operator_label("less_than_or_equal") == "<="
      assert Condition.operator_label("is_true") == "is true"
      assert Condition.operator_label("is_false") == "is false"
      assert Condition.operator_label("is_nil") == "is not set"
      assert Condition.operator_label("not_contains") == "does not contain"
      assert Condition.operator_label("before") == "before"
      assert Condition.operator_label("after") == "after"
    end

    test "unknown operator returns itself" do
      assert Condition.operator_label("custom_op") == "custom_op"
    end
  end

  # =============================================================================
  # operator_requires_value?/1
  # =============================================================================

  describe "operator_requires_value?/1" do
    test "returns false for valueless operators" do
      refute Condition.operator_requires_value?("is_empty")
      refute Condition.operator_requires_value?("is_true")
      refute Condition.operator_requires_value?("is_false")
      refute Condition.operator_requires_value?("is_nil")
    end

    test "returns true for operators needing a value" do
      assert Condition.operator_requires_value?("equals")
      assert Condition.operator_requires_value?("not_equals")
      assert Condition.operator_requires_value?("contains")
      assert Condition.operator_requires_value?("greater_than")
      assert Condition.operator_requires_value?("less_than")
      assert Condition.operator_requires_value?("before")
      assert Condition.operator_requires_value?("after")
    end
  end

  # =============================================================================
  # new/1 + add_rule + remove_rule + update_rule + set_logic
  # =============================================================================

  describe "new/1" do
    test "creates empty flat condition with default all logic" do
      condition = Condition.new()
      assert condition == %{"logic" => "all", "rules" => []}
    end

    test "creates with specified logic" do
      condition = Condition.new("any")
      assert condition == %{"logic" => "any", "rules" => []}
    end
  end

  describe "add_rule/2" do
    test "adds a rule with generated id" do
      condition = Condition.new()
      result = Condition.add_rule(condition)

      assert length(result["rules"]) == 1
      rule = hd(result["rules"])
      assert is_binary(rule["id"])
      assert String.starts_with?(rule["id"], "rule_")
      assert rule["operator"] == "equals"
      assert rule["sheet"] == nil
      assert rule["variable"] == nil
      assert rule["value"] == nil
    end

    test "adds multiple rules" do
      condition =
        Condition.new()
        |> Condition.add_rule()
        |> Condition.add_rule()
        |> Condition.add_rule()

      assert length(condition["rules"]) == 3

      ids = Enum.map(condition["rules"], & &1["id"])
      assert ids == Enum.uniq(ids)
    end

    test "adds rule with label for switch mode" do
      condition = Condition.new()
      result = Condition.add_rule(condition, with_label: true)

      rule = hd(result["rules"])
      assert Map.has_key?(rule, "label")
      assert rule["label"] == ""
    end

    test "adds rule without label by default" do
      condition = Condition.new()
      result = Condition.add_rule(condition)

      rule = hd(result["rules"])
      refute Map.has_key?(rule, "label")
    end
  end

  describe "remove_rule/2" do
    test "removes rule by id" do
      condition =
        Condition.new()
        |> Condition.add_rule()
        |> Condition.add_rule()

      rule_id = hd(condition["rules"])["id"]
      result = Condition.remove_rule(condition, rule_id)

      assert length(result["rules"]) == 1
      refute hd(result["rules"])["id"] == rule_id
    end

    test "removing non-existent id does nothing" do
      condition = Condition.add_rule(Condition.new())
      result = Condition.remove_rule(condition, "nonexistent")
      assert length(result["rules"]) == 1
    end

    test "removing from empty rules does nothing" do
      condition = Condition.new()
      result = Condition.remove_rule(condition, "any_id")
      assert result["rules"] == []
    end
  end

  describe "update_rule/4" do
    test "updates sheet field" do
      condition = Condition.add_rule(Condition.new())
      rule_id = hd(condition["rules"])["id"]

      result = Condition.update_rule(condition, rule_id, "sheet", "mc.jaime")
      assert hd(result["rules"])["sheet"] == "mc.jaime"
    end

    test "updates variable field" do
      condition = Condition.add_rule(Condition.new())
      rule_id = hd(condition["rules"])["id"]

      result = Condition.update_rule(condition, rule_id, "variable", "health")
      assert hd(result["rules"])["variable"] == "health"
    end

    test "updates operator field" do
      condition = Condition.add_rule(Condition.new())
      rule_id = hd(condition["rules"])["id"]

      result = Condition.update_rule(condition, rule_id, "operator", "greater_than")
      assert hd(result["rules"])["operator"] == "greater_than"
    end

    test "updates value field" do
      condition = Condition.add_rule(Condition.new())
      rule_id = hd(condition["rules"])["id"]

      result = Condition.update_rule(condition, rule_id, "value", "50")
      assert hd(result["rules"])["value"] == "50"
    end

    test "does not affect other rules" do
      condition =
        Condition.new()
        |> Condition.add_rule()
        |> Condition.add_rule()

      [first, second] = condition["rules"]

      result = Condition.update_rule(condition, first["id"], "sheet", "mc")
      [updated_first, unchanged_second] = result["rules"]

      assert updated_first["sheet"] == "mc"
      assert unchanged_second == second
    end
  end

  describe "set_logic/2" do
    test "changes logic from all to any" do
      condition = Condition.new("all")
      result = Condition.set_logic(condition, "any")
      assert result["logic"] == "any"
    end

    test "changes logic from any to all" do
      condition = Condition.new("any")
      result = Condition.set_logic(condition, "all")
      assert result["logic"] == "all"
    end

    test "preserves existing rules" do
      condition =
        Condition.new()
        |> Condition.add_rule()
        |> Condition.add_rule()

      result = Condition.set_logic(condition, "any")
      assert length(result["rules"]) == 2
    end
  end
end
