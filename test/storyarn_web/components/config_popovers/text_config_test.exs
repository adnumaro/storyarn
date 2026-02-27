defmodule StoryarnWeb.Components.ConfigPopovers.TextConfigTest do
  @moduledoc """
  Component tests for the text/rich_text config popover.
  """

  use StoryarnWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias StoryarnWeb.Components.BlockComponents.ConfigPopovers.TextConfig

  defp make_block(attrs \\ %{}) do
    Map.merge(
      %{
        id: 1,
        type: "text",
        is_constant: false,
        scope: "self",
        required: false,
        variable_name: "name",
        inherited_from_block_id: nil,
        detached: false,
        config: %{"label" => "Name", "placeholder" => "Enter name...", "max_length" => 100}
      },
      attrs
    )
  end

  describe "text_config/1" do
    test "renders placeholder input with value from config" do
      html =
        render_component(&TextConfig.text_config/1,
          block: make_block(),
          can_edit: true
        )

      assert html =~ "Enter name..."
      assert html =~ "save_config_field"
      assert html =~ "placeholder"
    end

    test "renders max_length input with value from config" do
      html =
        render_component(&TextConfig.text_config/1,
          block: make_block(),
          can_edit: true
        )

      assert html =~ ~s(value="100")
      assert html =~ "max_length"
    end

    test "renders empty max_length when nil" do
      html =
        render_component(&TextConfig.text_config/1,
          block: make_block(%{config: %{"label" => "Name"}}),
          can_edit: true
        )

      assert html =~ "max_length"
      refute html =~ ~s(value="100")
    end

    test "renders advanced section" do
      html =
        render_component(&TextConfig.text_config/1,
          block: make_block(),
          can_edit: true
        )

      assert html =~ "Advanced"
      assert html =~ "change_block_scope"
    end

    test "data-blur-event attributes are correct" do
      html =
        render_component(&TextConfig.text_config/1,
          block: make_block(),
          can_edit: true
        )

      assert html =~ ~s(data-blur-event="save_config_field")
      assert html =~ "block_id"
    end

    test "inputs are disabled when can_edit is false" do
      html =
        render_component(&TextConfig.text_config/1,
          block: make_block(),
          can_edit: false
        )

      assert html =~ "disabled"
    end

    test "works with rich_text block type" do
      html =
        render_component(&TextConfig.text_config/1,
          block: make_block(%{type: "rich_text"}),
          can_edit: true
        )

      assert html =~ "save_config_field"
      assert html =~ "Advanced"
    end
  end
end
