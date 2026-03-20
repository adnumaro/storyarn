defmodule StoryarnWeb.Components.BlockComponents.SelectBlocksTest do
  @moduledoc """
  Tests for SelectBlocks: select_block/1 and multi_select_block/1.
  Covers all rendering branches, private helpers (indirectly), and edge cases.
  """

  use StoryarnWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias StoryarnWeb.Components.BlockComponents.SelectBlocks

  # ===========================================================================
  # Helpers
  # ===========================================================================

  defp build_block(overrides \\ %{}) do
    Map.merge(
      %{
        id: "block-1",
        type: "select",
        config: %{
          "label" => "Class",
          "placeholder" => "Choose...",
          "options" => [
            %{"key" => "warrior", "value" => "Warrior"},
            %{"key" => "mage", "value" => "Mage"},
            %{"key" => "rogue", "value" => "Rogue"}
          ]
        },
        value: %{"content" => nil},
        is_constant: false
      },
      overrides
    )
  end

  defp build_multi_block(overrides) do
    Map.merge(
      %{
        id: "block-2",
        type: "multi_select",
        config: %{
          "label" => "Skills",
          "placeholder" => "Add skill...",
          "options" => [
            %{"key" => "stealth", "value" => "Stealth"},
            %{"key" => "magic", "value" => "Magic"},
            %{"key" => "archery", "value" => "Archery"}
          ]
        },
        value: %{"content" => []},
        is_constant: false
      },
      overrides
    )
  end

  # ===========================================================================
  # select_block/1
  # ===========================================================================

  describe "select_block/1 — can_edit true" do
    test "renders hook container with all options in template" do
      html =
        render_component(&SelectBlocks.select_block/1,
          block: build_block(),
          can_edit: true
        )

      assert html =~ ~s(phx-hook="BlockSelect")
      assert html =~ ~s(data-mode="select")
      assert html =~ "Warrior"
      assert html =~ "Mage"
      assert html =~ "Rogue"
    end

    test "renders label from config" do
      html =
        render_component(&SelectBlocks.select_block/1,
          block: build_block(),
          can_edit: true
        )

      assert html =~ "Class"
    end

    test "renders placeholder in trigger and as clear option" do
      html =
        render_component(&SelectBlocks.select_block/1,
          block: build_block(),
          can_edit: true
        )

      assert html =~ "Choose..."
    end

    test "highlights selected option and shows value in trigger" do
      block = build_block(%{value: %{"content" => "mage"}})

      html =
        render_component(&SelectBlocks.select_block/1,
          block: block,
          can_edit: true
        )

      # Trigger shows the display value
      assert html =~ "Mage"
      # Selected option has primary styling
      assert html =~ "bg-primary/10"
    end

    test "includes data-event and data-params on options" do
      html =
        render_component(&SelectBlocks.select_block/1,
          block: build_block(),
          can_edit: true
        )

      assert html =~ ~s(data-event="update_block_value")
      assert html =~ "block-1"
    end

    test "renders with data-phx-target when target is provided" do
      html =
        render_component(&SelectBlocks.select_block/1,
          block: build_block(),
          can_edit: true,
          target: "#my-component"
        )

      assert html =~ ~s(data-phx-target="#my-component")
    end
  end

  describe "select_block/1 — can_edit false" do
    test "renders display value when content matches an option" do
      block = build_block(%{value: %{"content" => "warrior"}})

      html =
        render_component(&SelectBlocks.select_block/1,
          block: block,
          can_edit: false
        )

      assert html =~ "Warrior"
      refute html =~ "BlockSelect"
    end

    test "renders dash when no selection" do
      block = build_block(%{value: %{"content" => nil}})

      html =
        render_component(&SelectBlocks.select_block/1,
          block: block,
          can_edit: false
        )

      assert html =~ "text-base-content/40"
      assert html =~ "-"
      refute html =~ "BlockSelect"
    end

    test "renders dash when content does not match any option" do
      block = build_block(%{value: %{"content" => "nonexistent"}})

      html =
        render_component(&SelectBlocks.select_block/1,
          block: block,
          can_edit: false
        )

      assert html =~ "text-base-content/40"
      assert html =~ "-"
    end
  end

  describe "select_block/1 — constant indicator" do
    test "renders lock icon when is_constant is true" do
      block = build_block(%{is_constant: true})

      html =
        render_component(&SelectBlocks.select_block/1,
          block: block,
          can_edit: true
        )

      assert html =~ "Constant"
      assert html =~ "lock"
    end

    test "does not render lock icon when is_constant is false" do
      block = build_block(%{is_constant: false})

      html =
        render_component(&SelectBlocks.select_block/1,
          block: block,
          can_edit: true
        )

      refute html =~ "Constant"
    end
  end

  describe "select_block/1 — nil/empty config values" do
    test "renders default placeholder when config placeholder is nil" do
      block =
        build_block(%{
          config: %{
            "label" => "Class",
            "placeholder" => nil,
            "options" => [%{"key" => "warrior", "value" => "Warrior"}]
          }
        })

      html =
        render_component(&SelectBlocks.select_block/1,
          block: block,
          can_edit: true
        )

      assert html =~ "Select..."
    end

    test "renders with empty options list when options are nil" do
      block =
        build_block(%{
          config: %{"label" => "Class", "placeholder" => "Pick one", "options" => nil}
        })

      html =
        render_component(&SelectBlocks.select_block/1,
          block: block,
          can_edit: true
        )

      assert html =~ "BlockSelect"
      assert html =~ "Pick one"
      refute html =~ "Warrior"
    end

    test "renders empty label (no label element)" do
      block =
        build_block(%{
          config: %{"label" => "", "placeholder" => "Choose...", "options" => []}
        })

      html =
        render_component(&SelectBlocks.select_block/1,
          block: block,
          can_edit: true
        )

      refute html =~ "<label"
    end

    test "renders with nil label (falls back to empty string)" do
      block =
        build_block(%{
          config: %{"label" => nil, "placeholder" => "Choose...", "options" => []}
        })

      html =
        render_component(&SelectBlocks.select_block/1,
          block: block,
          can_edit: true
        )

      refute html =~ "<label"
    end

    test "renders with entirely nil config" do
      block = build_block(%{config: %{}})

      html =
        render_component(&SelectBlocks.select_block/1,
          block: block,
          can_edit: true
        )

      assert html =~ "BlockSelect"
      assert html =~ "Select..."
    end
  end

  describe "select_block/1 — default attr values" do
    test "can_edit defaults to false" do
      html =
        render_component(&SelectBlocks.select_block/1,
          block: build_block(%{value: %{"content" => "warrior"}})
        )

      refute html =~ "BlockSelect"
      assert html =~ "Warrior"
    end

    test "is_editing defaults to false without error" do
      html =
        render_component(&SelectBlocks.select_block/1,
          block: build_block(),
          can_edit: true,
          is_editing: true
        )

      assert html =~ "BlockSelect"
    end
  end

  # ===========================================================================
  # multi_select_block/1
  # ===========================================================================

  describe "multi_select_block/1 — can_edit true, with selections" do
    test "renders selected tags in trigger" do
      block = build_multi_block(%{value: %{"content" => ["stealth", "magic"]}})

      html =
        render_component(&SelectBlocks.multi_select_block/1,
          block: block,
          can_edit: true
        )

      assert html =~ "Stealth"
      assert html =~ "Magic"
    end

    test "renders toggle options with checkboxes in template" do
      block = build_multi_block(%{value: %{"content" => ["stealth"]}})

      html =
        render_component(&SelectBlocks.multi_select_block/1,
          block: block,
          can_edit: true
        )

      assert html =~ ~s(data-event="toggle_multi_select")
      assert html =~ "stealth"
      assert html =~ "block-2"
    end

    test "renders badge-primary class on tags" do
      block = build_multi_block(%{value: %{"content" => ["archery"]}})

      html =
        render_component(&SelectBlocks.multi_select_block/1,
          block: block,
          can_edit: true
        )

      assert html =~ "badge badge-primary"
    end

    test "renders add-input in template for new tags" do
      block = build_multi_block(%{value: %{"content" => ["stealth"]}})

      html =
        render_component(&SelectBlocks.multi_select_block/1,
          block: block,
          can_edit: true
        )

      assert html =~ ~s(data-role="add-input")
      assert html =~ ~s(data-block-id="block-2")
    end
  end

  describe "multi_select_block/1 — can_edit true, no selections" do
    test "renders input with default placeholder when no selection and empty placeholder" do
      block =
        build_multi_block(%{
          config: %{
            "label" => "Skills",
            "placeholder" => "",
            "options" => [%{"key" => "stealth", "value" => "Stealth"}]
          },
          value: %{"content" => []}
        })

      html =
        render_component(&SelectBlocks.multi_select_block/1,
          block: block,
          can_edit: true
        )

      assert html =~ "Type and press Enter to add..."
    end

    test "shows badges in trigger when has selection and empty placeholder" do
      block =
        build_multi_block(%{
          config: %{
            "label" => "Skills",
            "placeholder" => "",
            "options" => [%{"key" => "stealth", "value" => "Stealth"}]
          },
          value: %{"content" => ["stealth"]}
        })

      html =
        render_component(&SelectBlocks.multi_select_block/1,
          block: block,
          can_edit: true
        )

      # Trigger shows badges when selections exist
      assert html =~ "Stealth"
      assert html =~ "badge badge-primary"
    end

    test "renders custom placeholder when placeholder is set" do
      block =
        build_multi_block(%{
          config: %{
            "label" => "Skills",
            "placeholder" => "Search skills...",
            "options" => [%{"key" => "stealth", "value" => "Stealth"}]
          },
          value: %{"content" => []}
        })

      html =
        render_component(&SelectBlocks.multi_select_block/1,
          block: block,
          can_edit: true
        )

      assert html =~ "Search skills..."
    end

    test "shows badges instead of placeholder when has selections" do
      block =
        build_multi_block(%{
          config: %{
            "label" => "Skills",
            "placeholder" => "Search skills...",
            "options" => [%{"key" => "stealth", "value" => "Stealth"}]
          },
          value: %{"content" => ["stealth"]}
        })

      html =
        render_component(&SelectBlocks.multi_select_block/1,
          block: block,
          can_edit: true
        )

      # Trigger shows badges, not placeholder
      assert html =~ "Stealth"
      assert html =~ "badge badge-primary"
    end
  end

  describe "multi_select_block/1 — can_edit false" do
    test "renders read-only badges when has selections" do
      block = build_multi_block(%{value: %{"content" => ["stealth", "archery"]}})

      html =
        render_component(&SelectBlocks.multi_select_block/1,
          block: block,
          can_edit: false
        )

      assert html =~ "Stealth"
      assert html =~ "Archery"
      assert html =~ "badge-sm badge-primary"
      refute html =~ "BlockSelect"
    end

    test "renders dash when no selection" do
      block = build_multi_block(%{value: %{"content" => []}})

      html =
        render_component(&SelectBlocks.multi_select_block/1,
          block: block,
          can_edit: false
        )

      assert html =~ "text-base-content/40"
      assert html =~ "-"
    end

    test "renders dash when content is nil (falls back to empty list)" do
      block = build_multi_block(%{value: %{"content" => nil}})

      html =
        render_component(&SelectBlocks.multi_select_block/1,
          block: block,
          can_edit: false
        )

      assert html =~ "-"
    end

    test "does not render editable hook or add-input" do
      block = build_multi_block(%{value: %{"content" => ["stealth"]}})

      html =
        render_component(&SelectBlocks.multi_select_block/1,
          block: block,
          can_edit: false
        )

      refute html =~ "BlockSelect"
      refute html =~ ~s(data-role="add-input")
    end
  end

  describe "multi_select_block/1 — resolve_selected_options edge cases" do
    test "uses key as label when option key does not match any option" do
      block =
        build_multi_block(%{
          config: %{
            "label" => "Skills",
            "placeholder" => "",
            "options" => [%{"key" => "stealth", "value" => "Stealth"}]
          },
          value: %{"content" => ["unknown_skill"]}
        })

      html =
        render_component(&SelectBlocks.multi_select_block/1,
          block: block,
          can_edit: true
        )

      assert html =~ "unknown_skill"
    end

    test "resolves mixed known and unknown keys" do
      block =
        build_multi_block(%{
          config: %{
            "label" => "Skills",
            "placeholder" => "",
            "options" => [%{"key" => "stealth", "value" => "Stealth"}]
          },
          value: %{"content" => ["stealth", "missing_key"]}
        })

      html =
        render_component(&SelectBlocks.multi_select_block/1,
          block: block,
          can_edit: true
        )

      assert html =~ "Stealth"
      assert html =~ "missing_key"
    end

    test "handles empty options list with selections (all keys shown raw)" do
      block =
        build_multi_block(%{
          config: %{"label" => "Skills", "placeholder" => "", "options" => []},
          value: %{"content" => ["alpha", "beta"]}
        })

      html =
        render_component(&SelectBlocks.multi_select_block/1,
          block: block,
          can_edit: true
        )

      assert html =~ "alpha"
      assert html =~ "beta"
    end
  end

  describe "multi_select_block/1 — constant indicator" do
    test "renders lock icon when is_constant is true" do
      block = build_multi_block(%{is_constant: true})

      html =
        render_component(&SelectBlocks.multi_select_block/1,
          block: block,
          can_edit: true
        )

      assert html =~ "Constant"
      assert html =~ "lock"
    end

    test "does not render lock icon when is_constant is false" do
      block = build_multi_block(%{is_constant: false})

      html =
        render_component(&SelectBlocks.multi_select_block/1,
          block: block,
          can_edit: true
        )

      refute html =~ "Constant"
    end
  end

  describe "multi_select_block/1 — nil/empty config values" do
    test "renders with entirely nil config (all defaults)" do
      block = build_multi_block(%{config: %{}})

      html =
        render_component(&SelectBlocks.multi_select_block/1,
          block: block,
          can_edit: true
        )

      refute html =~ "<label"
      assert html =~ "Type and press Enter to add..."
    end

    test "renders with nil options in config" do
      block =
        build_multi_block(%{
          config: %{"label" => "Tags", "placeholder" => "Add tag", "options" => nil}
        })

      html =
        render_component(&SelectBlocks.multi_select_block/1,
          block: block,
          can_edit: true
        )

      assert html =~ "Tags"
      assert html =~ "Add tag"
    end

    test "renders empty label (no label element)" do
      block =
        build_multi_block(%{
          config: %{"label" => "", "placeholder" => "Add...", "options" => []}
        })

      html =
        render_component(&SelectBlocks.multi_select_block/1,
          block: block,
          can_edit: true
        )

      refute html =~ "<label"
    end
  end

  describe "multi_select_block/1 — default attr values" do
    test "can_edit defaults to false" do
      block = build_multi_block(%{value: %{"content" => ["stealth"]}})

      html =
        render_component(&SelectBlocks.multi_select_block/1,
          block: block
        )

      assert html =~ "Stealth"
      refute html =~ "BlockSelect"
    end
  end

  describe "multi_select_block/1 — data-phx-target propagation" do
    test "passes target to hook container" do
      block = build_multi_block(%{value: %{"content" => ["stealth"]}})

      html =
        render_component(&SelectBlocks.multi_select_block/1,
          block: block,
          can_edit: true,
          target: "#sheet-editor"
        )

      assert html =~ ~s(data-phx-target="#sheet-editor")
    end
  end
end
