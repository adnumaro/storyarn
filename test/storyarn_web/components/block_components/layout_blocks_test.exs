defmodule StoryarnWeb.Components.BlockComponents.LayoutBlocksTest do
  use StoryarnWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias StoryarnWeb.Components.BlockComponents.LayoutBlocks

  defp make_block(value, opts \\ []) do
    label = Keyword.get(opts, :label, "Birthday")
    is_constant = Keyword.get(opts, :is_constant, false)

    %{
      id: "block-1",
      type: "date",
      config: %{"label" => label},
      value: %{"content" => value},
      is_constant: is_constant
    }
  end

  # ── date_block ────────────────────────────────────────────────────

  describe "date_block/1" do
    test "renders label" do
      html = render_component(&LayoutBlocks.date_block/1, block: make_block("2024-03-15"))
      assert html =~ "Birthday"
    end

    test "renders formatted date in read-only mode" do
      html = render_component(&LayoutBlocks.date_block/1, block: make_block("2024-03-15"))
      assert html =~ "March 15, 2024"
    end

    test "renders dash for nil date" do
      html = render_component(&LayoutBlocks.date_block/1, block: make_block(nil))
      assert html =~ "-"
    end

    test "renders dash for empty date" do
      html = render_component(&LayoutBlocks.date_block/1, block: make_block(""))
      assert html =~ "-"
    end

    test "renders original string for invalid date" do
      html = render_component(&LayoutBlocks.date_block/1, block: make_block("not-a-date"))
      assert html =~ "not-a-date"
    end

    test "shows date input when can_edit is true" do
      html =
        render_component(&LayoutBlocks.date_block/1,
          block: make_block("2024-03-15"),
          can_edit: true
        )

      assert html =~ ~s(type="date")
      assert html =~ "update_block_value"
    end

    test "does not show input when can_edit is false" do
      html = render_component(&LayoutBlocks.date_block/1, block: make_block("2024-03-15"))
      refute html =~ ~s(type="date")
    end

    test "shows faded text for nil value in read-only" do
      html = render_component(&LayoutBlocks.date_block/1, block: make_block(nil))
      assert html =~ "text-base-content/40"
    end

    test "renders different date formats correctly" do
      html = render_component(&LayoutBlocks.date_block/1, block: make_block("2025-12-31"))
      assert html =~ "December 31, 2025"
    end

    test "passes block id to date input" do
      html =
        render_component(&LayoutBlocks.date_block/1,
          block: make_block("2024-01-01"),
          can_edit: true
        )

      assert html =~ "block-1"
    end

    test "uses custom label from config" do
      html =
        render_component(&LayoutBlocks.date_block/1,
          block: make_block("2024-01-01", label: "Due Date")
        )

      assert html =~ "Due Date"
    end

    test "handles missing label gracefully" do
      block = %{
        id: "block-1",
        type: "date",
        config: %{},
        value: %{"content" => "2024-01-01"},
        is_constant: false
      }

      html = render_component(&LayoutBlocks.date_block/1, block: block)
      assert html =~ "January 01, 2024"
      # Should not render a label element when label is empty
      refute html =~ "lock"
    end

    test "renders is_constant block with lock icon" do
      html_constant =
        render_component(&LayoutBlocks.date_block/1,
          block: make_block("2024-01-01", is_constant: true)
        )

      html_variable =
        render_component(&LayoutBlocks.date_block/1,
          block: make_block("2024-01-01", is_constant: false)
        )

      assert html_constant =~ "Birthday"
      # is_constant renders a lock icon with error styling
      assert html_constant =~ "lock"
      assert html_constant =~ "text-error"
      # non-constant does NOT render lock icon
      refute html_variable =~ "text-error"
    end
  end
end
