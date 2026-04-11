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

end
