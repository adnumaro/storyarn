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

    test "hides constant toggle for divider, reference, and table" do
      for type <- ~w(divider reference table) do
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

    test "renders config gear for configurable types" do
      for type <- ~w(text rich_text number select multi_select boolean date reference) do
        html =
          render_component(&BlockToolbar.block_toolbar/1,
            block: make_block(%{type: type}),
            can_edit: true,
            is_inherited: false
          )

        assert html =~ "configure_block",
               "Expected config gear for type #{type}"
      end
    end

    test "hides config gear for divider and table" do
      for type <- ~w(divider table) do
        html =
          render_component(&BlockToolbar.block_toolbar/1,
            block: make_block(%{type: type}),
            can_edit: true,
            is_inherited: false
          )

        refute html =~ "configure_block",
               "Expected NO config gear for type #{type}"
      end
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
      assert html =~ "btn-active"
    end

    test "shows unlock icon without active state when is_constant is false" do
      html =
        render_component(&BlockToolbar.block_toolbar/1,
          block: make_block(%{is_constant: false}),
          can_edit: true,
          is_inherited: false
        )

      assert html =~ "lucide-unlock"
      refute html =~ "btn-active"
    end

    test "divider block only shows duplicate and overflow menu" do
      html =
        render_component(&BlockToolbar.block_toolbar/1,
          block: make_block(%{type: "divider"}),
          can_edit: true,
          is_inherited: false
        )

      assert html =~ "duplicate_block"
      assert html =~ "delete_block"
      refute html =~ "toolbar_toggle_constant"
      refute html =~ "configure_block"
    end

    test "table block only shows duplicate and overflow menu" do
      html =
        render_component(&BlockToolbar.block_toolbar/1,
          block: make_block(%{type: "table"}),
          can_edit: true,
          is_inherited: false
        )

      assert html =~ "duplicate_block"
      assert html =~ "delete_block"
      refute html =~ "toolbar_toggle_constant"
      refute html =~ "configure_block"
    end
  end

  # ===========================================================================
  # block_advanced_config/1
  # ===========================================================================

  describe "block_advanced_config/1" do
    test "renders scope selector for own blocks" do
      html =
        render_component(&BlockAdvancedConfig.block_advanced_config/1,
          block: make_block(),
          can_edit: true
        )

      assert html =~ "change_block_scope"
      assert html =~ "Self"
      assert html =~ "Children"
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
