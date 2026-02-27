defmodule StoryarnWeb.Components.ConfigPopovers.BooleanConfigTest do
  @moduledoc """
  Component tests for the boolean config popover.
  """

  use StoryarnWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias StoryarnWeb.Components.BlockComponents.ConfigPopovers.BooleanConfig

  defp make_block(attrs \\ %{}) do
    Map.merge(
      %{
        id: 1,
        type: "boolean",
        is_constant: false,
        scope: "self",
        required: false,
        variable_name: "is_alive",
        inherited_from_block_id: nil,
        detached: false,
        config: %{
          "label" => "Is Alive",
          "mode" => "two_state",
          "true_label" => "Alive",
          "false_label" => "Dead"
        }
      },
      attrs
    )
  end

  describe "boolean_config/1" do
    test "renders mode toggle unchecked for two_state (default)" do
      html =
        render_component(&BooleanConfig.boolean_config/1,
          block: make_block(),
          can_edit: true
        )

      assert html =~ "Three states"
      assert html =~ "toggle"
      # Toggle should not be checked when mode is two_state
      refute html =~ "checked"
    end

    test "renders mode toggle checked when tri_state" do
      html =
        render_component(&BooleanConfig.boolean_config/1,
          block: make_block(%{config: %{"label" => "Is Alive", "mode" => "tri_state"}}),
          can_edit: true
        )

      assert html =~ "checked"
    end

    test "renders true/false label inputs" do
      html =
        render_component(&BooleanConfig.boolean_config/1,
          block: make_block(),
          can_edit: true
        )

      assert html =~ ~s(value="Alive")
      assert html =~ ~s(value="Dead")
      assert html =~ "true_label"
      assert html =~ "false_label"
    end

    test "renders neutral label only when mode is tri_state" do
      html =
        render_component(&BooleanConfig.boolean_config/1,
          block:
            make_block(%{
              config: %{
                "label" => "Is Alive",
                "mode" => "tri_state",
                "neutral_label" => "Unknown"
              }
            }),
          can_edit: true
        )

      assert html =~ "neutral_label"
      assert html =~ ~s(value="Unknown")
      assert html =~ "Neutral"
    end

    test "hides neutral label when mode is two_state" do
      html =
        render_component(&BooleanConfig.boolean_config/1,
          block: make_block(),
          can_edit: true
        )

      refute html =~ "neutral_label"
    end

    test "renders advanced section" do
      html =
        render_component(&BooleanConfig.boolean_config/1,
          block: make_block(),
          can_edit: true
        )

      assert html =~ "Advanced"
      assert html =~ "change_block_scope"
    end

    test "data-event and data-blur-event attributes are correct" do
      html =
        render_component(&BooleanConfig.boolean_config/1,
          block: make_block(),
          can_edit: true
        )

      assert html =~ ~s(data-event="save_config_field")
      assert html =~ ~s(data-blur-event="save_config_field")
      assert html =~ "block_id"
    end

    test "mode toggle has data-close-on-click=false" do
      html =
        render_component(&BooleanConfig.boolean_config/1,
          block: make_block(),
          can_edit: true
        )

      assert html =~ ~s(data-close-on-click="false")
    end

    test "inputs are disabled when can_edit is false" do
      html =
        render_component(&BooleanConfig.boolean_config/1,
          block: make_block(),
          can_edit: false
        )

      assert html =~ "disabled"
    end
  end
end
