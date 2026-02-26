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
    test "renders select element with all options" do
      html =
        render_component(&SelectBlocks.select_block/1,
          block: build_block(),
          can_edit: true
        )

      assert html =~ "<select"
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

    test "renders placeholder as first option" do
      html =
        render_component(&SelectBlocks.select_block/1,
          block: build_block(),
          can_edit: true
        )

      assert html =~ "Choose..."
    end

    test "marks selected option when content matches" do
      block = build_block(%{value: %{"content" => "mage"}})

      html =
        render_component(&SelectBlocks.select_block/1,
          block: block,
          can_edit: true
        )

      assert html =~ "<select"
      # The select should contain the options with mage selected
      assert html =~ ~s(value="mage")
      assert html =~ "selected"
    end

    test "includes phx-change and phx-value-id attributes" do
      html =
        render_component(&SelectBlocks.select_block/1,
          block: build_block(),
          can_edit: true
        )

      assert html =~ ~s(phx-change="update_block_value")
      assert html =~ ~s(phx-value-id="block-1")
    end

    test "does not render read-only display div" do
      html =
        render_component(&SelectBlocks.select_block/1,
          block: build_block(),
          can_edit: true
        )

      # Should not show the read-only dash display
      refute html =~ "text-base-content/40"
    end

    test "renders with phx-target when target is provided" do
      html =
        render_component(&SelectBlocks.select_block/1,
          block: build_block(),
          can_edit: true,
          target: "#my-component"
        )

      assert html =~ ~s(phx-target="#my-component")
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
      refute html =~ "<select"
    end

    test "renders dash when no selection" do
      block = build_block(%{value: %{"content" => nil}})

      html =
        render_component(&SelectBlocks.select_block/1,
          block: block,
          can_edit: false
        )

      # Should show "-" fallback and dim styling
      assert html =~ "text-base-content/40"
      assert html =~ "-"
      refute html =~ "<select"
    end

    test "renders dash when content does not match any option" do
      block = build_block(%{value: %{"content" => "nonexistent"}})

      html =
        render_component(&SelectBlocks.select_block/1,
          block: block,
          can_edit: false
        )

      # find_option_label returns nil for non-matching key, display_value is nil
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

      # block_label renders a lock icon + "Constant" tooltip for constants
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

      # Falls back to dgettext("sheets", "Select...")
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

      assert html =~ "<select"
      assert html =~ "Pick one"
      # No option values other than placeholder
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

      # block_label with empty label renders nothing inside <label :if={@label != ""}>
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

      # nil || "" => "" which means no label rendered
      refute html =~ "<label"
    end

    test "renders with entirely nil config" do
      block = build_block(%{config: %{}})

      html =
        render_component(&SelectBlocks.select_block/1,
          block: block,
          can_edit: true
        )

      # All values fallback to defaults
      assert html =~ "<select"
      assert html =~ "Select..."
    end
  end

  describe "select_block/1 — default attr values" do
    test "can_edit defaults to false" do
      html =
        render_component(&SelectBlocks.select_block/1,
          block: build_block(%{value: %{"content" => "warrior"}})
        )

      # Should render read-only view (no select element)
      refute html =~ "<select"
      assert html =~ "Warrior"
    end

    test "is_editing defaults to false without error" do
      html =
        render_component(&SelectBlocks.select_block/1,
          block: build_block(),
          can_edit: true,
          is_editing: true
        )

      # Should render without error
      assert html =~ "<select"
    end
  end

  # ===========================================================================
  # multi_select_block/1
  # ===========================================================================

  describe "multi_select_block/1 — can_edit true, with selections" do
    test "renders selected tags with labels" do
      block = build_multi_block(%{value: %{"content" => ["stealth", "magic"]}})

      html =
        render_component(&SelectBlocks.multi_select_block/1,
          block: block,
          can_edit: true
        )

      assert html =~ "Stealth"
      assert html =~ "Magic"
    end

    test "renders remove buttons (X icon) on each tag" do
      block = build_multi_block(%{value: %{"content" => ["stealth"]}})

      html =
        render_component(&SelectBlocks.multi_select_block/1,
          block: block,
          can_edit: true
        )

      assert html =~ ~s(phx-click="toggle_multi_select")
      assert html =~ ~s(phx-value-key="stealth")
      assert html =~ ~s(phx-value-id="block-2")
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

    test "renders text input for adding new tags" do
      block = build_multi_block(%{value: %{"content" => ["stealth"]}})

      html =
        render_component(&SelectBlocks.multi_select_block/1,
          block: block,
          can_edit: true
        )

      assert html =~ ~s(type="text")
      assert html =~ ~s(phx-keydown="multi_select_keydown")
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

      # resolve_placeholder("", []) => "Type and press Enter to add..."
      assert html =~ "Type and press Enter to add..."
    end

    test "renders 'Add more...' placeholder when has selection and empty placeholder" do
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

      # resolve_placeholder("", _selected) => "Add more..."
      assert html =~ "Add more..."
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

      # resolve_placeholder("Search skills...", _) => "Search skills..."
      assert html =~ "Search skills..."
    end

    test "renders custom placeholder even when has selections" do
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

      # Custom placeholder always wins when non-empty
      assert html =~ "Search skills..."
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
      # No remove buttons or input
      refute html =~ ~s(phx-click="toggle_multi_select")
      refute html =~ ~s(phx-keydown="multi_select_keydown")
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

    test "does not render editable input or remove buttons" do
      block = build_multi_block(%{value: %{"content" => ["stealth"]}})

      html =
        render_component(&SelectBlocks.multi_select_block/1,
          block: block,
          can_edit: false
        )

      refute html =~ "block-input"
      refute html =~ ~s(type="text")
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

      # resolve_selected_options falls back to key as label
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

      # label defaults to "", placeholder resolves through resolve_placeholder
      # No label element rendered for empty label
      refute html =~ "<label"
      # Default placeholder for empty placeholder + no selections
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

      # Should render read-only view
      assert html =~ "Stealth"
      refute html =~ "block-input"
    end
  end

  describe "multi_select_block/1 — phx-target propagation" do
    test "passes target to toggle_multi_select and input" do
      block = build_multi_block(%{value: %{"content" => ["stealth"]}})

      html =
        render_component(&SelectBlocks.multi_select_block/1,
          block: block,
          can_edit: true,
          target: "#sheet-editor"
        )

      # target should be present on both remove button and input
      assert html =~ ~s(phx-target="#sheet-editor")
    end
  end
end
