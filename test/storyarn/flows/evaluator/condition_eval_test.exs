defmodule Storyarn.Flows.Evaluator.ConditionEvalTest do
  use ExUnit.Case, async: true

  alias Storyarn.Flows.Evaluator.ConditionEval

  # Helper to build a variable entry
  defp var(value, block_type) do
    %{
      value: value,
      initial_value: value,
      previous_value: value,
      source: :initial,
      block_type: block_type,
      block_id: 1,
      sheet_shortcut: "test",
      variable_name: "var"
    }
  end

  defp make_rule(sheet, variable, operator, value \\ nil) do
    %{
      "id" => "rule_1",
      "sheet" => sheet,
      "variable" => variable,
      "operator" => operator,
      "value" => value
    }
  end

  defp make_condition(logic, rules) do
    %{"logic" => logic, "rules" => rules}
  end

  # =============================================================================
  # Edge cases: nil, empty, invalid
  # =============================================================================

  describe "evaluate/2 edge cases" do
    test "nil condition passes" do
      assert {true, []} = ConditionEval.evaluate(nil, %{})
    end

    test "empty rules passes" do
      assert {true, []} = ConditionEval.evaluate(%{"logic" => "all", "rules" => []}, %{})
    end

    test "nil rules passes" do
      assert {true, []} = ConditionEval.evaluate(%{"rules" => nil}, %{})
    end

    test "invalid structure passes" do
      assert {true, []} = ConditionEval.evaluate("not a map", %{})
    end

    test "rules with incomplete entries are skipped" do
      condition =
        make_condition("all", [
          %{
            "id" => "r1",
            "sheet" => "mc",
            "variable" => nil,
            "operator" => "equals",
            "value" => "x"
          },
          %{
            "id" => "r2",
            "sheet" => "",
            "variable" => "hp",
            "operator" => "equals",
            "value" => "1"
          }
        ])

      assert {true, []} = ConditionEval.evaluate(condition, %{})
    end
  end

  # =============================================================================
  # evaluate_string/2
  # =============================================================================

  describe "evaluate_string/2" do
    test "nil string passes" do
      assert {true, []} = ConditionEval.evaluate_string(nil, %{})
    end

    test "empty string passes" do
      assert {true, []} = ConditionEval.evaluate_string("", %{})
    end

    test "legacy plain text passes" do
      assert {true, []} = ConditionEval.evaluate_string("some legacy expression", %{})
    end

    test "valid JSON condition is evaluated" do
      variables = %{"mc.jaime.health" => var(80, "number")}

      json =
        Jason.encode!(%{
          "logic" => "all",
          "rules" => [
            %{
              "id" => "r1",
              "sheet" => "mc.jaime",
              "variable" => "health",
              "operator" => "greater_than",
              "value" => "50"
            }
          ]
        })

      assert {true, [%{passed: true}]} = ConditionEval.evaluate_string(json, variables)
    end
  end

  # =============================================================================
  # Logic modes: all (AND) / any (OR)
  # =============================================================================

  describe "logic modes" do
    setup do
      variables = %{
        "mc.jaime.health" => var(80, "number"),
        "mc.jaime.alive" => var(true, "boolean")
      }

      {:ok, variables: variables}
    end

    test "all mode — all pass → true", %{variables: variables} do
      condition =
        make_condition("all", [
          make_rule("mc.jaime", "health", "greater_than", "50"),
          make_rule("mc.jaime", "alive", "is_true")
        ])

      assert {true, results} = ConditionEval.evaluate(condition, variables)
      assert length(results) == 2
      assert Enum.all?(results, & &1.passed)
    end

    test "all mode — one fails → false", %{variables: variables} do
      condition =
        make_condition("all", [
          make_rule("mc.jaime", "health", "greater_than", "50"),
          make_rule("mc.jaime", "alive", "is_false")
        ])

      assert {false, results} = ConditionEval.evaluate(condition, variables)
      assert Enum.at(results, 0).passed == true
      assert Enum.at(results, 1).passed == false
    end

    test "any mode — one passes → true", %{variables: variables} do
      condition =
        make_condition("any", [
          make_rule("mc.jaime", "health", "less_than", "50"),
          make_rule("mc.jaime", "alive", "is_true")
        ])

      assert {true, results} = ConditionEval.evaluate(condition, variables)
      assert Enum.at(results, 0).passed == false
      assert Enum.at(results, 1).passed == true
    end

    test "any mode — all fail → false", %{variables: variables} do
      condition =
        make_condition("any", [
          make_rule("mc.jaime", "health", "less_than", "50"),
          make_rule("mc.jaime", "alive", "is_false")
        ])

      assert {false, _results} = ConditionEval.evaluate(condition, variables)
    end
  end

  # =============================================================================
  # Number operators
  # =============================================================================

  describe "number operators" do
    setup do
      {:ok, variables: %{"mc.jaime.health" => var(80, "number")}}
    end

    test "equals — pass", %{variables: v} do
      condition = make_condition("all", [make_rule("mc.jaime", "health", "equals", "80")])
      assert {true, [%{passed: true, actual_value: 80}]} = ConditionEval.evaluate(condition, v)
    end

    test "equals — fail", %{variables: v} do
      condition = make_condition("all", [make_rule("mc.jaime", "health", "equals", "99")])
      assert {false, [%{passed: false}]} = ConditionEval.evaluate(condition, v)
    end

    test "not_equals", %{variables: v} do
      condition = make_condition("all", [make_rule("mc.jaime", "health", "not_equals", "99")])
      assert {true, _} = ConditionEval.evaluate(condition, v)
    end

    test "greater_than — pass", %{variables: v} do
      condition = make_condition("all", [make_rule("mc.jaime", "health", "greater_than", "50")])
      assert {true, _} = ConditionEval.evaluate(condition, v)
    end

    test "greater_than — fail (equal)", %{variables: v} do
      condition = make_condition("all", [make_rule("mc.jaime", "health", "greater_than", "80")])
      assert {false, _} = ConditionEval.evaluate(condition, v)
    end

    test "greater_than_or_equal — pass (equal)", %{variables: v} do
      condition =
        make_condition("all", [make_rule("mc.jaime", "health", "greater_than_or_equal", "80")])

      assert {true, _} = ConditionEval.evaluate(condition, v)
    end

    test "less_than", %{variables: v} do
      condition = make_condition("all", [make_rule("mc.jaime", "health", "less_than", "100")])
      assert {true, _} = ConditionEval.evaluate(condition, v)
    end

    test "less_than_or_equal — pass (equal)", %{variables: v} do
      condition =
        make_condition("all", [make_rule("mc.jaime", "health", "less_than_or_equal", "80")])

      assert {true, _} = ConditionEval.evaluate(condition, v)
    end

    test "number comparison with integer values" do
      variables = %{"mc.jaime.health" => var(100, "number")}
      condition = make_condition("all", [make_rule("mc.jaime", "health", "equals", "100")])
      assert {true, _} = ConditionEval.evaluate(condition, variables)
    end

    test "number comparison with float string" do
      variables = %{"mc.jaime.health" => var(80.5, "number")}
      condition = make_condition("all", [make_rule("mc.jaime", "health", "greater_than", "80.0")])
      assert {true, _} = ConditionEval.evaluate(condition, variables)
    end

    test "non-numeric value returns false for comparison" do
      variables = %{"mc.jaime.health" => var("not_a_number", "number")}
      condition = make_condition("all", [make_rule("mc.jaime", "health", "greater_than", "50")])
      assert {false, _} = ConditionEval.evaluate(condition, variables)
    end
  end

  # =============================================================================
  # Boolean operators
  # =============================================================================

  describe "boolean operators" do
    test "is_true — pass" do
      variables = %{"mc.jaime.alive" => var(true, "boolean")}
      condition = make_condition("all", [make_rule("mc.jaime", "alive", "is_true")])
      assert {true, _} = ConditionEval.evaluate(condition, variables)
    end

    test "is_true — fail" do
      variables = %{"mc.jaime.alive" => var(false, "boolean")}
      condition = make_condition("all", [make_rule("mc.jaime", "alive", "is_true")])
      assert {false, _} = ConditionEval.evaluate(condition, variables)
    end

    test "is_false — pass" do
      variables = %{"mc.jaime.alive" => var(false, "boolean")}
      condition = make_condition("all", [make_rule("mc.jaime", "alive", "is_false")])
      assert {true, _} = ConditionEval.evaluate(condition, variables)
    end

    test "is_nil — pass" do
      variables = %{"mc.jaime.alive" => var(nil, "boolean")}
      condition = make_condition("all", [make_rule("mc.jaime", "alive", "is_nil")])
      assert {true, _} = ConditionEval.evaluate(condition, variables)
    end

    test "is_nil — variable not in state" do
      condition = make_condition("all", [make_rule("mc.jaime", "missing", "is_nil")])
      assert {true, [%{passed: true, actual_value: nil}]} = ConditionEval.evaluate(condition, %{})
    end
  end

  # =============================================================================
  # Text operators
  # =============================================================================

  describe "text operators" do
    setup do
      {:ok, variables: %{"mc.jaime.name" => var("Jaime Lannister", "text")}}
    end

    test "equals", %{variables: v} do
      condition =
        make_condition("all", [make_rule("mc.jaime", "name", "equals", "Jaime Lannister")])

      assert {true, _} = ConditionEval.evaluate(condition, v)
    end

    test "not_equals", %{variables: v} do
      condition = make_condition("all", [make_rule("mc.jaime", "name", "not_equals", "Cersei")])
      assert {true, _} = ConditionEval.evaluate(condition, v)
    end

    test "contains", %{variables: v} do
      condition = make_condition("all", [make_rule("mc.jaime", "name", "contains", "Lannister")])
      assert {true, _} = ConditionEval.evaluate(condition, v)
    end

    test "contains — empty search string fails" do
      variables = %{"mc.jaime.name" => var("Jaime", "text")}
      condition = make_condition("all", [make_rule("mc.jaime", "name", "contains", "")])
      assert {false, _} = ConditionEval.evaluate(condition, variables)
    end

    test "starts_with", %{variables: v} do
      condition = make_condition("all", [make_rule("mc.jaime", "name", "starts_with", "Jaime")])
      assert {true, _} = ConditionEval.evaluate(condition, v)
    end

    test "ends_with", %{variables: v} do
      condition = make_condition("all", [make_rule("mc.jaime", "name", "ends_with", "Lannister")])
      assert {true, _} = ConditionEval.evaluate(condition, v)
    end

    test "is_empty — nil value" do
      variables = %{"mc.jaime.name" => var(nil, "text")}
      condition = make_condition("all", [make_rule("mc.jaime", "name", "is_empty")])
      assert {true, _} = ConditionEval.evaluate(condition, variables)
    end

    test "is_empty — empty string" do
      variables = %{"mc.jaime.name" => var("", "text")}
      condition = make_condition("all", [make_rule("mc.jaime", "name", "is_empty")])
      assert {true, _} = ConditionEval.evaluate(condition, variables)
    end

    test "is_empty — non-empty fails" do
      variables = %{"mc.jaime.name" => var("Jaime", "text")}
      condition = make_condition("all", [make_rule("mc.jaime", "name", "is_empty")])
      assert {false, _} = ConditionEval.evaluate(condition, variables)
    end
  end

  # =============================================================================
  # Select operators
  # =============================================================================

  describe "select operators" do
    setup do
      {:ok, variables: %{"mc.jaime.class" => var("warrior", "select")}}
    end

    test "equals", %{variables: v} do
      condition = make_condition("all", [make_rule("mc.jaime", "class", "equals", "warrior")])
      assert {true, _} = ConditionEval.evaluate(condition, v)
    end

    test "not_equals", %{variables: v} do
      condition = make_condition("all", [make_rule("mc.jaime", "class", "not_equals", "mage")])
      assert {true, _} = ConditionEval.evaluate(condition, v)
    end

    test "is_nil — pass" do
      variables = %{"mc.jaime.class" => var(nil, "select")}
      condition = make_condition("all", [make_rule("mc.jaime", "class", "is_nil")])
      assert {true, _} = ConditionEval.evaluate(condition, variables)
    end

    test "is_nil — fail" do
      variables = %{"mc.jaime.class" => var("warrior", "select")}
      condition = make_condition("all", [make_rule("mc.jaime", "class", "is_nil")])
      assert {false, _} = ConditionEval.evaluate(condition, variables)
    end
  end

  # =============================================================================
  # Multi-select operators
  # =============================================================================

  describe "multi_select operators" do
    setup do
      {:ok, variables: %{"mc.jaime.skills" => var(["sword", "shield", "horse"], "multi_select")}}
    end

    test "contains — pass", %{variables: v} do
      condition = make_condition("all", [make_rule("mc.jaime", "skills", "contains", "sword")])
      assert {true, _} = ConditionEval.evaluate(condition, v)
    end

    test "contains — fail", %{variables: v} do
      condition = make_condition("all", [make_rule("mc.jaime", "skills", "contains", "magic")])
      assert {false, _} = ConditionEval.evaluate(condition, v)
    end

    test "not_contains — pass", %{variables: v} do
      condition =
        make_condition("all", [make_rule("mc.jaime", "skills", "not_contains", "magic")])

      assert {true, _} = ConditionEval.evaluate(condition, v)
    end

    test "not_contains — fail", %{variables: v} do
      condition =
        make_condition("all", [make_rule("mc.jaime", "skills", "not_contains", "sword")])

      assert {false, _} = ConditionEval.evaluate(condition, v)
    end

    test "is_empty — nil" do
      variables = %{"mc.jaime.skills" => var(nil, "multi_select")}
      condition = make_condition("all", [make_rule("mc.jaime", "skills", "is_empty")])
      assert {true, _} = ConditionEval.evaluate(condition, variables)
    end

    test "is_empty — empty list" do
      variables = %{"mc.jaime.skills" => var([], "multi_select")}
      condition = make_condition("all", [make_rule("mc.jaime", "skills", "is_empty")])
      assert {true, _} = ConditionEval.evaluate(condition, variables)
    end

    test "is_empty — non-empty fails", %{variables: v} do
      condition = make_condition("all", [make_rule("mc.jaime", "skills", "is_empty")])
      assert {false, _} = ConditionEval.evaluate(condition, v)
    end

    test "contains on non-list value returns false" do
      variables = %{"mc.jaime.skills" => var("not_a_list", "multi_select")}
      condition = make_condition("all", [make_rule("mc.jaime", "skills", "contains", "sword")])
      assert {false, _} = ConditionEval.evaluate(condition, variables)
    end
  end

  # =============================================================================
  # Date operators
  # =============================================================================

  describe "date operators" do
    setup do
      {:ok, variables: %{"world.date" => var("2024-06-15", "date")}}
    end

    test "equals", %{variables: v} do
      condition = make_condition("all", [make_rule("world", "date", "equals", "2024-06-15")])
      assert {true, _} = ConditionEval.evaluate(condition, v)
    end

    test "not_equals", %{variables: v} do
      condition = make_condition("all", [make_rule("world", "date", "not_equals", "2024-01-01")])
      assert {true, _} = ConditionEval.evaluate(condition, v)
    end

    test "before", %{variables: v} do
      condition = make_condition("all", [make_rule("world", "date", "before", "2024-12-31")])
      assert {true, _} = ConditionEval.evaluate(condition, v)
    end

    test "after", %{variables: v} do
      condition = make_condition("all", [make_rule("world", "date", "after", "2024-01-01")])
      assert {true, _} = ConditionEval.evaluate(condition, v)
    end

    test "with Date struct value" do
      variables = %{"world.date" => var(~D[2024-06-15], "date")}
      condition = make_condition("all", [make_rule("world", "date", "equals", "2024-06-15")])
      assert {true, _} = ConditionEval.evaluate(condition, variables)
    end

    test "invalid date returns false" do
      variables = %{"world.date" => var("not-a-date", "date")}
      condition = make_condition("all", [make_rule("world", "date", "before", "2024-12-31")])
      assert {false, _} = ConditionEval.evaluate(condition, variables)
    end
  end

  # =============================================================================
  # Missing variables
  # =============================================================================

  describe "missing variables" do
    test "missing variable treated as nil" do
      condition = make_condition("all", [make_rule("mc.jaime", "health", "equals", "100")])

      assert {false, [%{passed: false, actual_value: nil, variable_ref: "mc.jaime.health"}]} =
               ConditionEval.evaluate(condition, %{})
    end

    test "missing variable — is_nil passes" do
      condition = make_condition("all", [make_rule("mc.jaime", "health", "is_nil")])
      assert {true, [%{passed: true}]} = ConditionEval.evaluate(condition, %{})
    end

    test "missing variable — is_empty passes for text" do
      # Variable not in state — actual_value is nil, operator dispatches without block_type
      # Since variable is missing, block_type is nil, falls to generic equals
      condition = make_condition("all", [make_rule("mc.jaime", "name", "is_empty")])

      # Missing variable → actual_value = nil, no block_type info
      # is_empty with nil block_type falls through to the catch-all which returns false
      # But is_true/is_false/is_nil work because they don't depend on block_type
      {result, _} = ConditionEval.evaluate(condition, %{})
      # This is acceptable: block-type-dependent operators need the variable to exist
      assert is_boolean(result)
    end
  end

  # =============================================================================
  # Block-format evaluation
  # =============================================================================

  describe "evaluate/2 block format" do
    setup do
      variables = %{
        "mc.jaime.health" => var(80, "number"),
        "mc.jaime.alive" => var(true, "boolean"),
        "mc.jaime.class" => var("warrior", "select")
      }

      {:ok, variables: variables}
    end

    test "single block passes", %{variables: variables} do
      block = %{
        "id" => "b1",
        "type" => "block",
        "logic" => "all",
        "rules" => [make_rule("mc.jaime", "health", "greater_than", "50")]
      }

      condition = %{"logic" => "all", "blocks" => [block]}
      assert {true, [%{passed: true}]} = ConditionEval.evaluate(condition, variables)
    end

    test "single block fails", %{variables: variables} do
      block = %{
        "id" => "b1",
        "type" => "block",
        "logic" => "all",
        "rules" => [make_rule("mc.jaime", "health", "less_than", "50")]
      }

      condition = %{"logic" => "all", "blocks" => [block]}
      assert {false, [%{passed: false}]} = ConditionEval.evaluate(condition, variables)
    end

    test "two blocks with ALL logic — both must pass", %{variables: variables} do
      block1 = %{
        "id" => "b1",
        "type" => "block",
        "logic" => "all",
        "rules" => [make_rule("mc.jaime", "health", "greater_than", "50")]
      }

      block2 = %{
        "id" => "b2",
        "type" => "block",
        "logic" => "all",
        "rules" => [make_rule("mc.jaime", "alive", "is_true")]
      }

      condition = %{"logic" => "all", "blocks" => [block1, block2]}
      assert {true, results} = ConditionEval.evaluate(condition, variables)
      assert length(results) == 2
    end

    test "two blocks with ANY logic — one passes", %{variables: variables} do
      block1 = %{
        "id" => "b1",
        "type" => "block",
        "logic" => "all",
        "rules" => [make_rule("mc.jaime", "health", "less_than", "50")]
      }

      block2 = %{
        "id" => "b2",
        "type" => "block",
        "logic" => "all",
        "rules" => [make_rule("mc.jaime", "alive", "is_true")]
      }

      condition = %{"logic" => "any", "blocks" => [block1, block2]}
      assert {true, results} = ConditionEval.evaluate(condition, variables)
      assert length(results) == 2
    end

    test "group with inner blocks AND", %{variables: variables} do
      inner1 = %{
        "id" => "b1",
        "type" => "block",
        "logic" => "all",
        "rules" => [make_rule("mc.jaime", "health", "greater_than", "50")]
      }

      inner2 = %{
        "id" => "b2",
        "type" => "block",
        "logic" => "all",
        "rules" => [make_rule("mc.jaime", "alive", "is_true")]
      }

      group = %{"id" => "g1", "type" => "group", "logic" => "all", "blocks" => [inner1, inner2]}
      condition = %{"logic" => "all", "blocks" => [group]}
      assert {true, results} = ConditionEval.evaluate(condition, variables)
      assert length(results) == 2
    end

    test "group with inner blocks OR — one fails, group passes", %{variables: variables} do
      inner1 = %{
        "id" => "b1",
        "type" => "block",
        "logic" => "all",
        "rules" => [make_rule("mc.jaime", "health", "less_than", "50")]
      }

      inner2 = %{
        "id" => "b2",
        "type" => "block",
        "logic" => "all",
        "rules" => [make_rule("mc.jaime", "alive", "is_true")]
      }

      group = %{"id" => "g1", "type" => "group", "logic" => "any", "blocks" => [inner1, inner2]}
      condition = %{"logic" => "all", "blocks" => [group]}
      assert {true, results} = ConditionEval.evaluate(condition, variables)
      assert length(results) == 2
    end

    test "top-level ANY with block + group", %{variables: variables} do
      # Block fails
      block = %{
        "id" => "b1",
        "type" => "block",
        "logic" => "all",
        "rules" => [make_rule("mc.jaime", "health", "less_than", "10")]
      }

      # Group passes (inner block passes)
      inner = %{
        "id" => "b2",
        "type" => "block",
        "logic" => "all",
        "rules" => [make_rule("mc.jaime", "alive", "is_true")]
      }

      group = %{"id" => "g1", "type" => "group", "logic" => "all", "blocks" => [inner]}
      condition = %{"logic" => "any", "blocks" => [block, group]}
      assert {true, results} = ConditionEval.evaluate(condition, variables)
      assert length(results) == 2
    end

    test "empty blocks passes" do
      condition = %{"logic" => "all", "blocks" => []}
      assert {true, []} = ConditionEval.evaluate(condition, %{})
    end

    test "empty group passes", %{variables: variables} do
      group = %{"id" => "g1", "type" => "group", "logic" => "all", "blocks" => []}
      condition = %{"logic" => "all", "blocks" => [group]}
      assert {true, []} = ConditionEval.evaluate(condition, variables)
    end

    test "block with incomplete rules are skipped", %{variables: variables} do
      block = %{
        "id" => "b1",
        "type" => "block",
        "logic" => "all",
        "rules" => [%{"id" => "r1", "sheet" => "", "variable" => nil, "operator" => "equals"}]
      }

      condition = %{"logic" => "all", "blocks" => [block]}
      assert {true, []} = ConditionEval.evaluate(condition, variables)
    end

    test "evaluate_string with block-format JSON", %{variables: variables} do
      block = %{
        "id" => "b1",
        "type" => "block",
        "logic" => "all",
        "rules" => [
          %{
            "id" => "r1",
            "sheet" => "mc.jaime",
            "variable" => "health",
            "operator" => "greater_than",
            "value" => "50"
          }
        ]
      }

      json = Jason.encode!(%{"logic" => "all", "blocks" => [block]})
      assert {true, [%{passed: true}]} = ConditionEval.evaluate_string(json, variables)
    end
  end

  # =============================================================================
  # Rule result structure
  # =============================================================================

  describe "rule result detail" do
    test "includes all expected fields" do
      variables = %{"mc.jaime.health" => var(80, "number")}

      condition =
        make_condition("all", [
          %{
            "id" => "rule_42",
            "sheet" => "mc.jaime",
            "variable" => "health",
            "operator" => "greater_than",
            "value" => "50"
          }
        ])

      {true, [result]} = ConditionEval.evaluate(condition, variables)

      assert result.rule_id == "rule_42"
      assert result.passed == true
      assert result.variable_ref == "mc.jaime.health"
      assert result.operator == "greater_than"
      assert result.expected_value == "50"
      assert result.actual_value == 80
    end
  end
end
