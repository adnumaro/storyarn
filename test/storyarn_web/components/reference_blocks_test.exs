defmodule StoryarnWeb.Components.BlockComponents.ReferenceBlocksTest do
  use StoryarnWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Storyarn.Sheets.Block
  alias StoryarnWeb.Components.BlockComponents.ReferenceBlocks

  defp build_block(attrs \\ %{}) do
    defaults = %{
      id: 177,
      type: "reference",
      config: %{"label" => "Companion", "allowed_types" => ["sheet", "flow"]},
      value: %{},
      is_constant: false,
      inherited_from_block_id: nil
    }

    struct!(Block, Map.merge(defaults, attrs))
  end

  describe "reference_block/1 when editable" do
    test "renders floating popover hook and trigger template" do
      html =
        render_component(&ReferenceBlocks.reference_block/1,
          block: build_block(),
          can_edit: true
        )

      assert html =~ ~s(phx-hook="ReferenceSelect")
      assert html =~ ~s(id="reference-select-177")
      assert html =~ ~s(data-role="trigger")
      assert html =~ ~s(data-role="popover-template")
      assert html =~ ~s(data-role="search")
      assert html =~ ~s(data-role="list")
      assert html =~ "Search sheets and flows..."
      assert html =~ "Type to search..."
    end

    test "exposes translated empty states and phx target on the hook root" do
      html =
        render_component(&ReferenceBlocks.reference_block/1,
          block: build_block(),
          can_edit: true,
          target: "#content-tab"
        )

      assert html =~ ~s(data-idle-text="Type to search...")
      assert html =~ ~s(data-no-results-text="No results found")
      assert html =~ ~s(data-phx-target="#content-tab")
    end

    test "renders clear button when a reference is set" do
      block = build_block(%{value: %{"target_type" => "sheet", "target_id" => 42}})

      html =
        render_component(&ReferenceBlocks.reference_block/1,
          block: block,
          can_edit: true
        )

      assert html =~ ~s(data-role="clear")
      assert html =~ "Clear reference"
    end

    test "renders selected reference in the trigger" do
      html =
        render_component(&ReferenceBlocks.reference_block/1,
          block: build_block(%{value: %{"target_type" => "sheet", "target_id" => 42}}),
          can_edit: true,
          reference_target: %{type: "sheet", id: 42, name: "Nox", shortcut: "guardian.nox"}
        )

      assert html =~ "Nox"
      assert html =~ "#guardian.nox"
    end
  end

  describe "reference_block/1 when read-only" do
    test "renders linked reference display" do
      html =
        render_component(&ReferenceBlocks.reference_block/1,
          block: build_block(%{value: %{"target_type" => "flow", "target_id" => 7}}),
          can_edit: false,
          reference_target: %{type: "flow", id: 7, name: "Main Flow", shortcut: "main.flow"}
        )

      assert html =~ "Main Flow"
      assert html =~ "#main.flow"
      refute html =~ ~s(phx-hook="ReferenceSelect")
    end
  end
end
