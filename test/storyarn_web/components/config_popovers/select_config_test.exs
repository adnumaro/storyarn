defmodule StoryarnWeb.Components.ConfigPopovers.SelectConfigTest do
  @moduledoc """
  Component tests for the select/multi_select config popover.
  """

  use StoryarnWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias StoryarnWeb.Components.BlockComponents.ConfigPopovers.SelectConfig

  defp make_block(attrs \\ %{}) do
    Map.merge(
      %{
        id: 1,
        type: "select",
        is_constant: false,
        scope: "self",
        required: false,
        variable_name: "class",
        inherited_from_block_id: nil,
        detached: false,
        config: %{
          "label" => "Class",
          "options" => [
            %{"key" => "warrior", "value" => "Warrior"},
            %{"key" => "mage", "value" => "Mage"}
          ],
          "placeholder" => "Choose class..."
        }
      },
      attrs
    )
  end

  describe "select_config/1" do
    test "renders existing options with key and label inputs" do
      html =
        render_component(&SelectConfig.select_config/1,
          block: make_block(),
          can_edit: true
        )

      assert html =~ ~s(value="warrior")
      assert html =~ ~s(value="Warrior")
      assert html =~ ~s(value="mage")
      assert html =~ ~s(value="Mage")
    end

    test "renders empty options list" do
      html =
        render_component(&SelectConfig.select_config/1,
          block: make_block(%{config: %{"label" => "Class"}}),
          can_edit: true
        )

      assert html =~ "Add option"
      refute html =~ ~s(value="warrior")
    end

    test "renders add option button" do
      html =
        render_component(&SelectConfig.select_config/1,
          block: make_block(),
          can_edit: true
        )

      assert html =~ "add_select_option"
      assert html =~ "Add option"
    end

    test "renders remove button for each option" do
      html =
        render_component(&SelectConfig.select_config/1,
          block: make_block(),
          can_edit: true
        )

      assert html =~ "remove_select_option"
    end

    test "renders placeholder input" do
      html =
        render_component(&SelectConfig.select_config/1,
          block: make_block(),
          can_edit: true
        )

      assert html =~ "Choose class..."
      assert html =~ "placeholder"
    end

    test "hides max_selections for select type" do
      html =
        render_component(&SelectConfig.select_config/1,
          block: make_block(%{type: "select"}),
          can_edit: true
        )

      refute html =~ "max_options"
      refute html =~ "Max Selections"
    end

    test "shows max_selections for multi_select type" do
      html =
        render_component(&SelectConfig.select_config/1,
          block: make_block(%{type: "multi_select"}),
          can_edit: true
        )

      assert html =~ "max_options"
      assert html =~ "Max Selections"
    end

    test "renders advanced section" do
      html =
        render_component(&SelectConfig.select_config/1,
          block: make_block(),
          can_edit: true
        )

      assert html =~ "Advanced"
      assert html =~ "change_block_scope"
    end

    test "data-blur-event attributes are correct for option inputs" do
      html =
        render_component(&SelectConfig.select_config/1,
          block: make_block(),
          can_edit: true
        )

      assert html =~ ~s(data-blur-event="update_select_option")
      assert html =~ "key_field"
    end

    test "hides add/remove buttons when can_edit is false" do
      html =
        render_component(&SelectConfig.select_config/1,
          block: make_block(),
          can_edit: false
        )

      refute html =~ "add_select_option"
      refute html =~ "remove_select_option"
      assert html =~ "disabled"
    end
  end
end
