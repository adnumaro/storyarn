defmodule StoryarnWeb.Components.ConfigPopovers.NumberConfigTest do
  @moduledoc """
  Component tests for the number config popover.
  """

  use StoryarnWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias StoryarnWeb.Components.BlockComponents.ConfigPopovers.NumberConfig

  defp make_block(attrs \\ %{}) do
    Map.merge(
      %{
        id: 1,
        type: "number",
        is_constant: false,
        scope: "self",
        required: false,
        variable_name: "health",
        inherited_from_block_id: nil,
        detached: false,
        config: %{
          "label" => "Health",
          "min" => 0,
          "max" => 100,
          "step" => 0.5,
          "placeholder" => "Enter value..."
        }
      },
      attrs
    )
  end

  describe "number_config/1" do
    test "renders min input with value from config" do
      html =
        render_component(&NumberConfig.number_config/1,
          block: make_block(),
          can_edit: true
        )

      assert html =~ ~s(value="0")
      assert html =~ "min"
      assert html =~ "save_config_field"
    end

    test "renders max input with value from config" do
      html =
        render_component(&NumberConfig.number_config/1,
          block: make_block(),
          can_edit: true
        )

      assert html =~ ~s(value="100")
      assert html =~ "max"
    end

    test "renders step input with value from config" do
      html =
        render_component(&NumberConfig.number_config/1,
          block: make_block(),
          can_edit: true
        )

      assert html =~ ~s(value="0.5")
      assert html =~ "step"
    end

    test "renders empty inputs when config values are nil" do
      html =
        render_component(&NumberConfig.number_config/1,
          block: make_block(%{config: %{"label" => "Health"}}),
          can_edit: true
        )

      assert html =~ "min"
      assert html =~ "max"
      assert html =~ "step"
      refute html =~ ~s(value="0")
      refute html =~ ~s(value="100")
    end

    test "renders placeholder input" do
      html =
        render_component(&NumberConfig.number_config/1,
          block: make_block(),
          can_edit: true
        )

      assert html =~ "Enter value..."
      assert html =~ "placeholder"
    end

    test "renders advanced section" do
      html =
        render_component(&NumberConfig.number_config/1,
          block: make_block(),
          can_edit: true
        )

      assert html =~ "Advanced"
      assert html =~ "change_block_scope"
    end

    test "data-blur-event attributes are correct" do
      html =
        render_component(&NumberConfig.number_config/1,
          block: make_block(),
          can_edit: true
        )

      assert html =~ ~s(data-blur-event="save_config_field")
      assert html =~ "block_id"
    end

    test "inputs are disabled when can_edit is false" do
      html =
        render_component(&NumberConfig.number_config/1,
          block: make_block(),
          can_edit: false
        )

      assert html =~ "disabled"
    end
  end
end
