defmodule StoryarnWeb.Components.ConditionBuilderTest do
  use StoryarnWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias StoryarnWeb.Components.ConditionBuilder

  # =============================================================================
  # condition_builder/1 rendering
  # =============================================================================

  describe "condition_builder/1" do
    test "renders with nil condition (defaults to new condition)" do
      html =
        render_component(&ConditionBuilder.condition_builder/1, %{
          id: "test-cond",
          condition: nil,
          variables: [],
          can_edit: true,
          context: %{},
          switch_mode: false,
          event_name: nil
        })

      assert html =~ "condition-builder"
      assert html =~ "phx-hook=\"ConditionBuilder\""
      assert html =~ "data-condition="
      assert html =~ "data-variables="
    end

    test "renders with existing condition map and serializes payload" do
      condition = %{
        "logic" => "all",
        "rules" => [
          %{
            "sheet" => "mc",
            "variable" => "health",
            "operator" => "greater_than",
            "value" => "50"
          }
        ]
      }

      html =
        render_component(&ConditionBuilder.condition_builder/1, %{
          id: "test-cond",
          condition: condition,
          variables: [],
          can_edit: true,
          context: %{},
          switch_mode: false,
          event_name: nil
        })

      assert html =~ "condition-builder"
      assert html =~ "data-condition="
      # Verify the condition payload is actually serialized into the attribute
      assert html =~ "greater_than"
      assert html =~ "&quot;mc&quot;"
      assert html =~ "&quot;health&quot;"
    end

    test "renders with blocks-based condition and preserves structure" do
      condition = %{
        "logic" => "any",
        "blocks" => [
          %{
            "logic" => "all",
            "rules" => [
              %{
                "sheet" => "npc",
                "variable" => "mood",
                "operator" => "equals",
                "value" => "happy"
              }
            ]
          }
        ]
      }

      html =
        render_component(&ConditionBuilder.condition_builder/1, %{
          id: "test-cond",
          condition: condition,
          variables: [],
          can_edit: true,
          context: %{},
          switch_mode: false,
          event_name: nil
        })

      assert html =~ "condition-builder"
      # Verify blocks-format condition is serialized (not replaced with default)
      assert html =~ "&quot;npc&quot;"
      assert html =~ "&quot;mood&quot;"
      assert html =~ "&quot;any&quot;"
    end

    test "renders with legacy condition (falls back to new empty condition)" do
      html =
        render_component(&ConditionBuilder.condition_builder/1, %{
          id: "test-cond",
          condition: :legacy,
          variables: [],
          can_edit: true,
          context: %{},
          switch_mode: false,
          event_name: nil
        })

      assert html =~ "condition-builder"
      # Should fall back to a new condition with "all" logic
      assert html =~ "&quot;all&quot;"
      assert html =~ "data-condition="
    end

    test "renders with string condition (falls back to new empty condition)" do
      html =
        render_component(&ConditionBuilder.condition_builder/1, %{
          id: "test-cond",
          condition: "invalid_string",
          variables: [],
          can_edit: true,
          context: %{},
          switch_mode: false,
          event_name: nil
        })

      assert html =~ "condition-builder"
      # Should fall back to a new condition, not use the raw string
      assert html =~ "&quot;all&quot;"
      assert html =~ "data-condition="
    end

    test "passes variables to data attribute" do
      variables = [
        %{sheet_shortcut: "mc.jaime", variable_name: "health", block_type: "number"}
      ]

      html =
        render_component(&ConditionBuilder.condition_builder/1, %{
          id: "test-cond",
          condition: nil,
          variables: variables,
          can_edit: true,
          context: %{},
          switch_mode: false,
          event_name: nil
        })

      assert html =~ "data-variables="
      assert html =~ "mc.jaime"
    end

    test "passes can_edit flag" do
      html =
        render_component(&ConditionBuilder.condition_builder/1, %{
          id: "test-cond",
          condition: nil,
          variables: [],
          can_edit: false,
          context: %{},
          switch_mode: false,
          event_name: nil
        })

      assert html =~ "data-can-edit=\"false\""
    end

    test "passes switch_mode flag" do
      html =
        render_component(&ConditionBuilder.condition_builder/1, %{
          id: "test-cond",
          condition: nil,
          variables: [],
          can_edit: true,
          context: %{},
          switch_mode: true,
          event_name: nil
        })

      assert html =~ "data-switch-mode=\"true\""
    end

    test "passes event_name" do
      html =
        render_component(&ConditionBuilder.condition_builder/1, %{
          id: "test-cond",
          condition: nil,
          variables: [],
          can_edit: true,
          context: %{},
          switch_mode: false,
          event_name: "save_condition"
        })

      assert html =~ "data-event-name=\"save_condition\""
    end
  end

  # =============================================================================
  # translations/0
  # =============================================================================

  describe "translations/0" do
    test "returns translations map with expected keys" do
      translations = ConditionBuilder.translations()
      assert is_map(translations)
      assert is_map(translations.operator_labels)
      assert is_binary(translations.match)
      assert is_binary(translations.all)
      assert is_binary(translations.any)
      assert is_binary(translations.add_condition)
      assert is_binary(translations.add_block)
      assert is_binary(translations.group)
      assert is_binary(translations.cancel)
      assert is_binary(translations.no_conditions)
    end

    test "operator_labels contains all expected operators" do
      labels = ConditionBuilder.translations().operator_labels
      expected_ops = ~w(equals not_equals contains starts_with ends_with is_empty
                        greater_than greater_than_or_equal less_than less_than_or_equal
                        is_true is_false is_nil not_contains before after)

      for op <- expected_ops do
        assert Map.has_key?(labels, op), "Missing operator label for: #{op}"
        assert is_binary(labels[op]), "Label for #{op} should be a string"
      end
    end
  end
end
