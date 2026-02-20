defmodule StoryarnWeb.Components.ExpressionEditorTest do
  use StoryarnWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias StoryarnWeb.Components.ExpressionEditor

  describe "serialize_condition_to_text/1" do
    test "returns empty string for nil" do
      assert ExpressionEditor.serialize_condition_to_text(nil) == ""
    end

    test "returns empty string for empty rules" do
      assert ExpressionEditor.serialize_condition_to_text(%{"logic" => "all", "rules" => []}) ==
               ""
    end

    test "returns empty string for non-map input" do
      assert ExpressionEditor.serialize_condition_to_text("invalid") == ""
    end

    test "serializes a single rule with comparison" do
      condition = %{
        "logic" => "all",
        "rules" => [
          %{"sheet" => "mc.jaime", "variable" => "health", "operator" => "greater_than", "value" => "50"}
        ]
      }

      assert ExpressionEditor.serialize_condition_to_text(condition) == "mc.jaime.health > 50"
    end

    test "serializes is_true as bare reference" do
      condition = %{
        "logic" => "all",
        "rules" => [
          %{"sheet" => "mc.jaime", "variable" => "alive", "operator" => "is_true", "value" => nil}
        ]
      }

      assert ExpressionEditor.serialize_condition_to_text(condition) == "mc.jaime.alive"
    end

    test "serializes is_false with negation" do
      condition = %{
        "logic" => "all",
        "rules" => [
          %{"sheet" => "mc.jaime", "variable" => "alive", "operator" => "is_false", "value" => nil}
        ]
      }

      assert ExpressionEditor.serialize_condition_to_text(condition) == "!mc.jaime.alive"
    end

    test "serializes multiple rules with AND logic" do
      condition = %{
        "logic" => "all",
        "rules" => [
          %{"sheet" => "mc.jaime", "variable" => "health", "operator" => "greater_than", "value" => "50"},
          %{"sheet" => "mc.jaime", "variable" => "alive", "operator" => "is_true", "value" => nil}
        ]
      }

      result = ExpressionEditor.serialize_condition_to_text(condition)
      assert result == "mc.jaime.health > 50 && mc.jaime.alive"
    end

    test "serializes multiple rules with OR logic" do
      condition = %{
        "logic" => "any",
        "rules" => [
          %{"sheet" => "mc.jaime", "variable" => "health", "operator" => "equals", "value" => "0"},
          %{"sheet" => "mc.jaime", "variable" => "alive", "operator" => "is_false", "value" => nil}
        ]
      }

      result = ExpressionEditor.serialize_condition_to_text(condition)
      assert result == "mc.jaime.health == 0 || !mc.jaime.alive"
    end

    test "serializes string values with quotes" do
      condition = %{
        "logic" => "all",
        "rules" => [
          %{"sheet" => "mc.jaime", "variable" => "class", "operator" => "equals", "value" => "warrior"}
        ]
      }

      assert ExpressionEditor.serialize_condition_to_text(condition) ==
               ~s(mc.jaime.class == "warrior")
    end

    test "serializes numeric values without quotes" do
      condition = %{
        "logic" => "all",
        "rules" => [
          %{"sheet" => "global", "variable" => "progress", "operator" => "less_than", "value" => "100"}
        ]
      }

      assert ExpressionEditor.serialize_condition_to_text(condition) == "global.progress < 100"
    end

    test "skips rules with missing sheet or variable" do
      condition = %{
        "logic" => "all",
        "rules" => [
          %{"sheet" => "", "variable" => "health", "operator" => "equals", "value" => "50"},
          %{"sheet" => "mc.jaime", "variable" => "health", "operator" => "equals", "value" => "50"}
        ]
      }

      assert ExpressionEditor.serialize_condition_to_text(condition) == "mc.jaime.health == 50"
    end

    test "handles all comparison operators" do
      operators = [
        {"equals", "=="},
        {"not_equals", "!="},
        {"greater_than", ">"},
        {"less_than", "<"},
        {"greater_than_or_equal", ">="},
        {"less_than_or_equal", "<="}
      ]

      for {op, symbol} <- operators do
        condition = %{
          "logic" => "all",
          "rules" => [%{"sheet" => "a", "variable" => "b", "operator" => op, "value" => "1"}]
        }

        assert ExpressionEditor.serialize_condition_to_text(condition) == "a.b #{symbol} 1"
      end
    end

    test "handles nil value with ? placeholder" do
      condition = %{
        "logic" => "all",
        "rules" => [
          %{"sheet" => "mc.jaime", "variable" => "health", "operator" => "equals", "value" => nil}
        ]
      }

      assert ExpressionEditor.serialize_condition_to_text(condition) == "mc.jaime.health == ?"
    end

    test "serializes block format with single block" do
      condition = %{
        "logic" => "all",
        "blocks" => [
          %{
            "id" => "block_1",
            "type" => "block",
            "logic" => "all",
            "rules" => [
              %{"sheet" => "mc.jaime", "variable" => "health", "operator" => "greater_than", "value" => "50"}
            ]
          }
        ]
      }

      assert ExpressionEditor.serialize_condition_to_text(condition) == "mc.jaime.health > 50"
    end

    test "serializes block format with multiple blocks" do
      condition = %{
        "logic" => "all",
        "blocks" => [
          %{
            "id" => "block_1",
            "type" => "block",
            "logic" => "all",
            "rules" => [
              %{"sheet" => "mc.jaime", "variable" => "health", "operator" => "greater_than", "value" => "50"}
            ]
          },
          %{
            "id" => "block_2",
            "type" => "block",
            "logic" => "all",
            "rules" => [
              %{"sheet" => "mc.jaime", "variable" => "alive", "operator" => "is_true", "value" => nil}
            ]
          }
        ]
      }

      assert ExpressionEditor.serialize_condition_to_text(condition) ==
               "mc.jaime.health > 50 && mc.jaime.alive"
    end

    test "serializes block format with multi-rule blocks using parens" do
      condition = %{
        "logic" => "any",
        "blocks" => [
          %{
            "id" => "block_1",
            "type" => "block",
            "logic" => "all",
            "rules" => [
              %{"sheet" => "mc.jaime", "variable" => "health", "operator" => "greater_than", "value" => "50"},
              %{"sheet" => "mc.jaime", "variable" => "alive", "operator" => "is_true", "value" => nil}
            ]
          },
          %{
            "id" => "block_2",
            "type" => "block",
            "logic" => "all",
            "rules" => [
              %{"sheet" => "global", "variable" => "override", "operator" => "is_true", "value" => nil}
            ]
          }
        ]
      }

      assert ExpressionEditor.serialize_condition_to_text(condition) ==
               "(mc.jaime.health > 50 && mc.jaime.alive) || global.override"
    end

    test "serializes block format with group" do
      condition = %{
        "logic" => "all",
        "blocks" => [
          %{
            "id" => "group_1",
            "type" => "group",
            "logic" => "any",
            "blocks" => [
              %{
                "id" => "block_1",
                "type" => "block",
                "logic" => "all",
                "rules" => [
                  %{"sheet" => "mc.jaime", "variable" => "health", "operator" => "greater_than", "value" => "50"}
                ]
              },
              %{
                "id" => "block_2",
                "type" => "block",
                "logic" => "all",
                "rules" => [
                  %{"sheet" => "global", "variable" => "override", "operator" => "is_true", "value" => nil}
                ]
              }
            ]
          }
        ]
      }

      assert ExpressionEditor.serialize_condition_to_text(condition) ==
               "(mc.jaime.health > 50 || global.override)"
    end

    test "returns empty for block format with empty blocks" do
      condition = %{"logic" => "all", "blocks" => []}
      assert ExpressionEditor.serialize_condition_to_text(condition) == ""
    end

    test "escapes quotes in string values" do
      condition = %{
        "logic" => "all",
        "rules" => [
          %{
            "sheet" => "mc.jaime",
            "variable" => "quote",
            "operator" => "equals",
            "value" => ~s(say "hello")
          }
        ]
      }

      assert ExpressionEditor.serialize_condition_to_text(condition) ==
               ~s(mc.jaime.quote == "say \\"hello\\"")
    end
  end

  describe "serialize_assignments_to_text/1" do
    test "returns empty string for nil" do
      assert ExpressionEditor.serialize_assignments_to_text(nil) == ""
    end

    test "returns empty string for empty list" do
      assert ExpressionEditor.serialize_assignments_to_text([]) == ""
    end

    test "serializes a simple set assignment" do
      assignments = [
        %{"sheet" => "mc.jaime", "variable" => "health", "operator" => "set", "value" => "100"}
      ]

      assert ExpressionEditor.serialize_assignments_to_text(assignments) ==
               "mc.jaime.health = 100"
    end

    test "serializes add assignment" do
      assignments = [
        %{"sheet" => "mc.jaime", "variable" => "health", "operator" => "add", "value" => "10"}
      ]

      assert ExpressionEditor.serialize_assignments_to_text(assignments) ==
               "mc.jaime.health += 10"
    end

    test "serializes set_true" do
      assignments = [
        %{"sheet" => "mc.jaime", "variable" => "alive", "operator" => "set_true"}
      ]

      assert ExpressionEditor.serialize_assignments_to_text(assignments) == "mc.jaime.alive = true"
    end

    test "serializes multiple assignments joined by newlines" do
      assignments = [
        %{"sheet" => "mc.jaime", "variable" => "health", "operator" => "set", "value" => "100"},
        %{"sheet" => "mc.jaime", "variable" => "alive", "operator" => "set_true"}
      ]

      result = ExpressionEditor.serialize_assignments_to_text(assignments)
      assert result == "mc.jaime.health = 100\nmc.jaime.alive = true"
    end

    test "skips incomplete assignments" do
      assignments = [
        %{"sheet" => "", "variable" => "health", "operator" => "set", "value" => "100"},
        %{"sheet" => "mc.jaime", "variable" => "health", "operator" => "set", "value" => "50"}
      ]

      assert ExpressionEditor.serialize_assignments_to_text(assignments) == "mc.jaime.health = 50"
    end
  end

  describe "expression_editor/1 component" do
    test "renders Builder tab active by default" do
      html =
        render_component(&ExpressionEditor.expression_editor/1,
          id: "test-expr",
          mode: "condition",
          condition: nil,
          variables: [],
          can_edit: true
        )

      assert html =~ "btn-active"
      assert html =~ "Builder"
      assert html =~ "Code"
    end

    test "renders condition builder in condition mode" do
      html =
        render_component(&ExpressionEditor.expression_editor/1,
          id: "test-expr",
          mode: "condition",
          condition: nil,
          variables: [],
          can_edit: true,
          active_tab: "builder"
        )

      assert html =~ "ConditionBuilder"
      refute html =~ "InstructionBuilder"
    end

    test "renders instruction builder in instruction mode" do
      html =
        render_component(&ExpressionEditor.expression_editor/1,
          id: "test-expr",
          mode: "instruction",
          assignments: [],
          variables: [],
          can_edit: true,
          active_tab: "builder"
        )

      assert html =~ "InstructionBuilder"
      refute html =~ "ConditionBuilder"
    end

    test "renders code editor when active tab is code" do
      html =
        render_component(&ExpressionEditor.expression_editor/1,
          id: "test-expr",
          mode: "condition",
          condition: %{
            "logic" => "all",
            "rules" => [
              %{
                "sheet" => "mc.jaime",
                "variable" => "health",
                "operator" => "greater_than",
                "value" => "50"
              }
            ]
          },
          variables: [],
          can_edit: true,
          active_tab: "code"
        )

      assert html =~ "ExpressionEditor"
      assert html =~ "phx-hook"
      assert html =~ "mc.jaime.health &gt; 50"
      refute html =~ "ConditionBuilder"
    end

    test "code editor gets correct data attributes for condition mode" do
      html =
        render_component(&ExpressionEditor.expression_editor/1,
          id: "test-expr",
          mode: "condition",
          condition: nil,
          variables: [%{sheet_shortcut: "mc.jaime", variable_name: "health", block_type: "number"}],
          can_edit: true,
          active_tab: "code"
        )

      assert html =~ ~s(data-mode="expression")
      assert html =~ "data-variables="
      assert html =~ ~s(data-editable="true")
    end

    test "code editor gets correct data attributes for instruction mode" do
      html =
        render_component(&ExpressionEditor.expression_editor/1,
          id: "test-expr",
          mode: "instruction",
          assignments: [],
          variables: [],
          can_edit: false,
          active_tab: "code"
        )

      assert html =~ ~s(data-mode="assignments")
      assert html =~ ~s(data-editable="false")
    end

    test "tab buttons have correct phx-click and phx-value attributes" do
      html =
        render_component(&ExpressionEditor.expression_editor/1,
          id: "my-editor",
          mode: "condition",
          condition: nil,
          variables: [],
          can_edit: true
        )

      assert html =~ ~s(phx-click="toggle_expression_tab")
      assert html =~ ~s(phx-value-id="my-editor")
      assert html =~ ~s(phx-value-tab="builder")
      assert html =~ ~s(phx-value-tab="code")
    end
  end
end
