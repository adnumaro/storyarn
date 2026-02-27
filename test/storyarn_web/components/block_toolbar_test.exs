defmodule StoryarnWeb.Components.BlockToolbarTest do
  @moduledoc """
  Component tests for block_toolbar/1 and block_advanced_config/1.
  """

  use StoryarnWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias StoryarnWeb.Components.BlockComponents.BlockAdvancedConfig
  alias StoryarnWeb.Components.BlockComponents.BlockToolbar

  # ===========================================================================
  # Helpers
  # ===========================================================================

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
        config: %{"label" => "Name"}
      },
      attrs
    )
  end

  # ===========================================================================
  # block_toolbar/1
  # ===========================================================================

  describe "block_toolbar/1" do
    test "renders duplicate button for own blocks" do
      html =
        render_component(&BlockToolbar.block_toolbar/1,
          block: make_block(),
          can_edit: true,
          is_inherited: false
        )

      assert html =~ "duplicate_block"
      assert html =~ "copy"
    end

    test "renders constant toggle for variable-capable types" do
      for type <- ~w(text rich_text number select multi_select boolean date) do
        html =
          render_component(&BlockToolbar.block_toolbar/1,
            block: make_block(%{type: type}),
            can_edit: true,
            is_inherited: false
          )

        assert html =~ "toolbar_toggle_constant",
               "Expected constant toggle for type #{type}"
      end
    end

    test "hides constant toggle for reference and table" do
      for type <- ~w(reference table) do
        html =
          render_component(&BlockToolbar.block_toolbar/1,
            block: make_block(%{type: type}),
            can_edit: true,
            is_inherited: false
          )

        refute html =~ "toolbar_toggle_constant",
               "Expected NO constant toggle for type #{type}"
      end
    end

    test "renders ToolbarPopover gear for text/rich_text types" do
      for type <- ~w(text rich_text) do
        html =
          render_component(&BlockToolbar.block_toolbar/1,
            block: make_block(%{type: type}),
            can_edit: true,
            is_inherited: false,
            component_id: "content-tab"
          )

        assert html =~ "ToolbarPopover",
               "Expected ToolbarPopover for type #{type}"

        assert html =~ "config-popover-",
               "Expected config-popover id for type #{type}"

        assert html =~ "save_config_field",
               "Expected save_config_field data attribute for type #{type}"
      end
    end

    test "renders ToolbarPopover gear for number type" do
      html =
        render_component(&BlockToolbar.block_toolbar/1,
          block: make_block(%{type: "number", config: %{"label" => "HP"}}),
          can_edit: true,
          is_inherited: false,
          component_id: "content-tab"
        )

      assert html =~ "ToolbarPopover"
      assert html =~ "config-popover-"
      assert html =~ "save_config_field"
      refute html =~ "disabled"
    end

    test "renders ToolbarPopover gear for boolean type" do
      html =
        render_component(&BlockToolbar.block_toolbar/1,
          block: make_block(%{type: "boolean", config: %{"label" => "Is Alive"}}),
          can_edit: true,
          is_inherited: false,
          component_id: "content-tab"
        )

      assert html =~ "ToolbarPopover"
      assert html =~ "config-popover-"
      assert html =~ "save_config_field"
      refute html =~ "disabled"
    end

    test "renders ToolbarPopover gear for select/multi_select types" do
      for type <- ~w(select multi_select) do
        html =
          render_component(&BlockToolbar.block_toolbar/1,
            block:
              make_block(%{
                type: type,
                config: %{"label" => "Choice", "options" => []}
              }),
            can_edit: true,
            is_inherited: false,
            component_id: "content-tab"
          )

        assert html =~ "ToolbarPopover",
               "Expected ToolbarPopover for type #{type}"

        assert html =~ "config-popover-",
               "Expected config-popover id for type #{type}"

        refute html =~ "disabled"
      end
    end

    test "renders ToolbarPopover gear for date type" do
      html =
        render_component(&BlockToolbar.block_toolbar/1,
          block: make_block(%{type: "date", config: %{"label" => "Birthday"}}),
          can_edit: true,
          is_inherited: false,
          component_id: "content-tab"
        )

      assert html =~ "ToolbarPopover"
      assert html =~ "config-popover-"
      assert html =~ "save_config_field"
      refute html =~ "disabled"
    end

    test "renders ToolbarPopover gear for reference type" do
      html =
        render_component(&BlockToolbar.block_toolbar/1,
          block: make_block(%{type: "reference", config: %{"label" => "Link"}}),
          can_edit: true,
          is_inherited: false,
          component_id: "content-tab"
        )

      assert html =~ "ToolbarPopover"
      assert html =~ "config-popover-"
      assert html =~ "toggle_allowed_type"
      refute html =~ "disabled"
    end

    test "renders ToolbarPopover gear for table with only Advanced section" do
      html =
        render_component(&BlockToolbar.block_toolbar/1,
          block: make_block(%{type: "table"}),
          can_edit: true,
          is_inherited: false,
          component_id: "content-tab"
        )

      assert html =~ "ToolbarPopover"
      assert html =~ "config-popover-"
      # Table popover shows Advanced section (scope selector)
      assert html =~ "change_block_scope"
      refute html =~ "disabled"
    end

    test "renders overflow menu with delete" do
      html =
        render_component(&BlockToolbar.block_toolbar/1,
          block: make_block(),
          can_edit: true,
          is_inherited: false
        )

      assert html =~ "delete_block"
      assert html =~ "trash-2"
    end

    test "renders inherited actions in overflow menu for inherited blocks" do
      html =
        render_component(&BlockToolbar.block_toolbar/1,
          block: make_block(%{inherited_from_block_id: 99}),
          can_edit: true,
          is_inherited: true
        )

      assert html =~ "navigate_to_source"
      assert html =~ "detach_inherited_block"
      assert html =~ "hide_inherited_for_children"
    end

    test "hides inherited actions for own blocks" do
      html =
        render_component(&BlockToolbar.block_toolbar/1,
          block: make_block(),
          can_edit: true,
          is_inherited: false
        )

      refute html =~ "navigate_to_source"
      refute html =~ "detach_inherited_block"
      refute html =~ "hide_inherited_for_children"
    end

    test "hides toolbar when can_edit is false" do
      html =
        render_component(&BlockToolbar.block_toolbar/1,
          block: make_block(),
          can_edit: false,
          is_inherited: false
        )

      refute html =~ "duplicate_block"
      refute html =~ "delete_block"
    end

    test "shows lock icon and active state when is_constant is true" do
      html =
        render_component(&BlockToolbar.block_toolbar/1,
          block: make_block(%{is_constant: true}),
          can_edit: true,
          is_inherited: false
        )

      assert html =~ "lucide-lock"
      refute html =~ "lucide-unlock"
      # The constant toggle button specifically has btn-active in its class
      assert html =~ ~r/btn-active[^"]*"[^>]*toolbar_toggle_constant/
    end

    test "shows unlock icon without active state when is_constant is false" do
      html =
        render_component(&BlockToolbar.block_toolbar/1,
          block: make_block(%{is_constant: false}),
          can_edit: true,
          is_inherited: false
        )

      assert html =~ "lucide-unlock"
      # The constant toggle button should NOT have btn-active
      refute html =~ ~r/btn-active[^"]*"[^>]*toolbar_toggle_constant/
    end

    test "table block shows duplicate, config gear, and overflow menu but no constant toggle" do
      html =
        render_component(&BlockToolbar.block_toolbar/1,
          block: make_block(%{type: "table"}),
          can_edit: true,
          is_inherited: false,
          component_id: "content-tab"
        )

      assert html =~ "duplicate_block"
      assert html =~ "delete_block"
      assert html =~ "ToolbarPopover"
      refute html =~ "toolbar_toggle_constant"
    end

    test "inherited table block shows inherited actions and config but no constant toggle" do
      html =
        render_component(&BlockToolbar.block_toolbar/1,
          block: make_block(%{type: "table", inherited_from_block_id: 99}),
          can_edit: true,
          is_inherited: true,
          component_id: "content-tab"
        )

      # Has duplicate + config gear + overflow menu with inherited actions
      assert html =~ "duplicate_block"
      assert html =~ "delete_block"
      assert html =~ "ToolbarPopover"
      assert html =~ "navigate_to_source"
      assert html =~ "detach_inherited_block"
      assert html =~ "hide_inherited_for_children"

      # No constant toggle for table type
      refute html =~ "toolbar_toggle_constant"
    end
  end

  # ===========================================================================
  # block_advanced_config/1
  # ===========================================================================

  describe "block_advanced_config/1" do
    test "renders scope selector buttons for own blocks" do
      html =
        render_component(&BlockAdvancedConfig.block_advanced_config/1,
          block: make_block(),
          can_edit: true
        )

      assert html =~ "change_block_scope"
      assert html =~ "Self"
      assert html =~ "Children"
      # Verify button-based scope selector (data-params is HTML-encoded)
      assert html =~ "data-event"
      assert html =~ "data-params"
    end

    test "hides scope selector for inherited blocks" do
      html =
        render_component(&BlockAdvancedConfig.block_advanced_config/1,
          block: make_block(%{inherited_from_block_id: 99}),
          can_edit: true
        )

      refute html =~ "change_block_scope"
    end

    test "shows required toggle when scope is children" do
      html =
        render_component(&BlockAdvancedConfig.block_advanced_config/1,
          block: make_block(%{scope: "children"}),
          can_edit: true
        )

      assert html =~ "toggle_required"
    end

    test "hides required toggle when scope is self" do
      html =
        render_component(&BlockAdvancedConfig.block_advanced_config/1,
          block: make_block(%{scope: "self"}),
          can_edit: true
        )

      refute html =~ "toggle_required"
    end

    test "shows variable name for non-constant variable-capable blocks" do
      html =
        render_component(&BlockAdvancedConfig.block_advanced_config/1,
          block: make_block(%{variable_name: "health", is_constant: false, type: "text"}),
          can_edit: true
        )

      assert html =~ "health"
      assert html =~ "variable"
    end

    test "hides variable name for constant blocks" do
      html =
        render_component(&BlockAdvancedConfig.block_advanced_config/1,
          block: make_block(%{variable_name: "health", is_constant: true, type: "text"}),
          can_edit: true
        )

      refute html =~ ~s(<code)
    end
  end
end
