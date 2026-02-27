defmodule StoryarnWeb.Components.BlockToolbarTest do
  @moduledoc """
  Component tests for block_toolbar/1 — constant toggle, variable name,
  scope buttons, required checkbox, reference allowed_types, and config gear.
  """

  use StoryarnWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

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
  # Constant toggle
  # ===========================================================================

  describe "constant toggle" do
    test "renders for variable-capable types" do
      for type <- ~w(text rich_text number select multi_select boolean date) do
        html =
          render_component(&BlockToolbar.block_toolbar/1,
            block: make_block(%{type: type}),
            can_edit: true
          )

        assert html =~ "toolbar_toggle_constant",
               "Expected constant toggle for type #{type}"
      end
    end

    test "hides for reference and table" do
      for type <- ~w(reference table) do
        html =
          render_component(&BlockToolbar.block_toolbar/1,
            block: make_block(%{type: type}),
            can_edit: true
          )

        refute html =~ "toolbar_toggle_constant",
               "Expected NO constant toggle for type #{type}"
      end
    end

    test "shows lock icon and active state when is_constant is true" do
      html =
        render_component(&BlockToolbar.block_toolbar/1,
          block: make_block(%{is_constant: true}),
          can_edit: true
        )

      assert html =~ "lucide-lock"
      refute html =~ "lucide-unlock"
      assert html =~ ~r/btn-active[^"]*"[^>]*toolbar_toggle_constant/
    end

    test "shows unlock icon without active state when is_constant is false" do
      html =
        render_component(&BlockToolbar.block_toolbar/1,
          block: make_block(%{is_constant: false}),
          can_edit: true
        )

      assert html =~ "lucide-unlock"
      refute html =~ ~r/btn-active[^"]*"[^>]*toolbar_toggle_constant/
    end
  end

  # ===========================================================================
  # Config gear (ToolbarPopover)
  # ===========================================================================

  describe "config gear popover" do
    test "renders ToolbarPopover for text/rich_text types" do
      for type <- ~w(text rich_text) do
        html =
          render_component(&BlockToolbar.block_toolbar/1,
            block: make_block(%{type: type}),
            can_edit: true,
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

    test "renders ToolbarPopover for number type" do
      html =
        render_component(&BlockToolbar.block_toolbar/1,
          block: make_block(%{type: "number", config: %{"label" => "HP"}}),
          can_edit: true,
          component_id: "content-tab"
        )

      assert html =~ "ToolbarPopover"
      assert html =~ "config-popover-"
      assert html =~ "save_config_field"
    end

    test "renders ToolbarPopover for boolean type" do
      html =
        render_component(&BlockToolbar.block_toolbar/1,
          block: make_block(%{type: "boolean", config: %{"label" => "Is Alive"}}),
          can_edit: true,
          component_id: "content-tab"
        )

      assert html =~ "ToolbarPopover"
      assert html =~ "config-popover-"
      assert html =~ "save_config_field"
    end

    test "renders ToolbarPopover for select/multi_select types" do
      for type <- ~w(select multi_select) do
        html =
          render_component(&BlockToolbar.block_toolbar/1,
            block:
              make_block(%{
                type: type,
                config: %{"label" => "Choice", "options" => []}
              }),
            can_edit: true,
            component_id: "content-tab"
          )

        assert html =~ "ToolbarPopover",
               "Expected ToolbarPopover for type #{type}"

        assert html =~ "config-popover-",
               "Expected config-popover id for type #{type}"
      end
    end

    test "renders ToolbarPopover for date type" do
      html =
        render_component(&BlockToolbar.block_toolbar/1,
          block: make_block(%{type: "date", config: %{"label" => "Birthday"}}),
          can_edit: true,
          component_id: "content-tab"
        )

      assert html =~ "ToolbarPopover"
      assert html =~ "config-popover-"
      assert html =~ "save_config_field"
    end

    test "does NOT render ToolbarPopover for reference type" do
      html =
        render_component(&BlockToolbar.block_toolbar/1,
          block: make_block(%{type: "reference", config: %{"label" => "Link"}}),
          can_edit: true,
          component_id: "content-tab"
        )

      refute html =~ "ToolbarPopover"
      refute html =~ "config-popover-"
    end

    test "does NOT render ToolbarPopover for table type" do
      html =
        render_component(&BlockToolbar.block_toolbar/1,
          block: make_block(%{type: "table"}),
          can_edit: true,
          component_id: "content-tab"
        )

      refute html =~ "ToolbarPopover"
      refute html =~ "config-popover-"
    end

    test "hides toolbar when can_edit is false" do
      html =
        render_component(&BlockToolbar.block_toolbar/1,
          block: make_block(),
          can_edit: false
        )

      refute html =~ "toolbar_toggle_constant"
      refute html =~ "ToolbarPopover"
    end
  end

  # ===========================================================================
  # Scope buttons
  # ===========================================================================

  describe "scope buttons" do
    test "renders scope buttons for own blocks" do
      html =
        render_component(&BlockToolbar.block_toolbar/1,
          block: make_block(),
          can_edit: true
        )

      assert html =~ "change_block_scope"
      assert html =~ "Self"
      assert html =~ "Children"
    end

    test "Self button has btn-active when scope is self" do
      html =
        render_component(&BlockToolbar.block_toolbar/1,
          block: make_block(%{scope: "self"}),
          can_edit: true
        )

      assert html =~ ~r/btn-active[^"]*"[^>]*phx-value-scope="self"/
    end

    test "Children button has btn-active when scope is children" do
      html =
        render_component(&BlockToolbar.block_toolbar/1,
          block: make_block(%{scope: "children"}),
          can_edit: true
        )

      assert html =~ ~r/btn-active[^"]*"[^>]*phx-value-scope="children"/
    end

    test "hides scope buttons for inherited blocks" do
      html =
        render_component(&BlockToolbar.block_toolbar/1,
          block: make_block(%{inherited_from_block_id: 99}),
          can_edit: true
        )

      refute html =~ "change_block_scope"
    end

    test "renders scope buttons for table blocks" do
      html =
        render_component(&BlockToolbar.block_toolbar/1,
          block: make_block(%{type: "table"}),
          can_edit: true
        )

      assert html =~ "change_block_scope"
      assert html =~ "Self"
      assert html =~ "Children"
    end
  end

  # ===========================================================================
  # Required checkbox
  # ===========================================================================

  describe "required checkbox" do
    test "shows required checkbox when scope is children" do
      html =
        render_component(&BlockToolbar.block_toolbar/1,
          block: make_block(%{scope: "children"}),
          can_edit: true
        )

      assert html =~ "toggle_required"
      assert html =~ "Req"
    end

    test "hides required checkbox when scope is self" do
      html =
        render_component(&BlockToolbar.block_toolbar/1,
          block: make_block(%{scope: "self"}),
          can_edit: true
        )

      refute html =~ "toggle_required"
    end

    test "hides required checkbox for inherited blocks" do
      html =
        render_component(&BlockToolbar.block_toolbar/1,
          block: make_block(%{scope: "children", inherited_from_block_id: 99}),
          can_edit: true
        )

      refute html =~ "toggle_required"
    end

    test "shows checked icon when required is true" do
      html =
        render_component(&BlockToolbar.block_toolbar/1,
          block: make_block(%{scope: "children", required: true}),
          can_edit: true
        )

      assert html =~ "toggle_required"
      assert html =~ "square-check"
    end

    test "shows unchecked icon when required is false" do
      html =
        render_component(&BlockToolbar.block_toolbar/1,
          block: make_block(%{scope: "children", required: false}),
          can_edit: true
        )

      assert html =~ "toggle_required"
      assert html =~ "square"
      refute html =~ "square-check"
    end
  end

  # ===========================================================================
  # Reference allowed_types
  # ===========================================================================

  describe "reference allowed_types" do
    test "shows sheets and flows checkboxes for reference blocks" do
      html =
        render_component(&BlockToolbar.block_toolbar/1,
          block:
            make_block(%{
              type: "reference",
              config: %{"label" => "Link", "allowed_types" => ["sheet", "flow"]}
            }),
          can_edit: true
        )

      assert html =~ "toggle_allowed_type"
      assert html =~ "Sheets"
      assert html =~ "Flows"
    end

    test "does not show allowed_types for non-reference blocks" do
      html =
        render_component(&BlockToolbar.block_toolbar/1,
          block: make_block(%{type: "text"}),
          can_edit: true
        )

      refute html =~ "toggle_allowed_type"
    end

    test "does not show allowed_types for inherited reference blocks" do
      html =
        render_component(&BlockToolbar.block_toolbar/1,
          block:
            make_block(%{
              type: "reference",
              inherited_from_block_id: 99,
              config: %{"label" => "Link", "allowed_types" => ["sheet", "flow"]}
            }),
          can_edit: true
        )

      refute html =~ "toggle_allowed_type"
    end

    test "checkboxes reflect allowed_types from config" do
      html =
        render_component(&BlockToolbar.block_toolbar/1,
          block:
            make_block(%{
              type: "reference",
              config: %{"label" => "Link", "allowed_types" => ["sheet"]}
            }),
          can_edit: true
        )

      assert html =~ "Sheets"
      assert html =~ "Flows"
      # Only sheet should be checked
      assert html =~ "toggle_allowed_type"
    end
  end

  # ===========================================================================
  # Toolbar variable_name display
  # ===========================================================================

  describe "variable_name display" do
    test "shows variable_name for variable blocks (not referenced)" do
      html =
        render_component(&BlockToolbar.block_toolbar/1,
          block:
            make_block(%{
              variable_name: "health",
              is_constant: false,
              type: "text",
              is_referenced: false
            }),
          can_edit: true,
          target: nil,
          component_id: "content-tab"
        )

      assert html =~ "health"
      assert html =~ ~s(name="variable_name")
    end

    test "shows read-only variable_name when block is referenced" do
      html =
        render_component(&BlockToolbar.block_toolbar/1,
          block:
            make_block(%{
              variable_name: "health",
              is_constant: false,
              type: "text",
              is_referenced: true
            }),
          can_edit: true,
          target: nil,
          component_id: "content-tab"
        )

      assert html =~ "health"
      assert html =~ ~s(<code)
      refute html =~ ~s(name="variable_name")
    end

    test "hides variable_name for constant blocks" do
      html =
        render_component(&BlockToolbar.block_toolbar/1,
          block:
            make_block(%{
              variable_name: "health",
              is_constant: true,
              type: "text",
              is_referenced: false
            }),
          can_edit: true,
          target: nil,
          component_id: "content-tab"
        )

      refute html =~ ~s(name="variable_name")
      refute html =~ ~s(<code)
    end

    test "hides variable_name for non-variable types (table)" do
      html =
        render_component(&BlockToolbar.block_toolbar/1,
          block:
            make_block(%{
              variable_name: nil,
              is_constant: false,
              type: "table",
              is_referenced: false
            }),
          can_edit: true,
          target: nil,
          component_id: "content-tab"
        )

      refute html =~ ~s(name="variable_name")
    end
  end
end
