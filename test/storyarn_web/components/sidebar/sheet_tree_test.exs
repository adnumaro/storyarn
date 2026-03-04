defmodule StoryarnWeb.Components.Sidebar.SheetTreeTest do
  use StoryarnWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias StoryarnWeb.Components.Sidebar.SheetTree

  defp make_sheet(id, opts \\ []) do
    %{
      id: id,
      name: Keyword.get(opts, :name, "Sheet #{id}"),
      avatar_asset: Keyword.get(opts, :avatar_asset, nil),
      children: Keyword.get(opts, :children, [])
    }
  end

  defp make_workspace, do: %{slug: "test-ws"}
  defp make_project, do: %{slug: "test-proj"}

  defp render_section(sheets_tree, opts \\ []) do
    render_component(&SheetTree.sheets_section/1,
      sheets_tree: sheets_tree,
      workspace: make_workspace(),
      project: make_project(),
      selected_sheet_id: Keyword.get(opts, :selected_sheet_id, nil),
      can_edit: Keyword.get(opts, :can_edit, true)
    )
  end

  # ── Empty state ────────────────────────────────────────────────

  describe "empty state" do
    test "shows empty message when no sheets" do
      html = render_section([])
      assert html =~ "No sheets yet"
    end

    test "hides search when no sheets" do
      html = render_section([])
      refute html =~ "sheets-tree-search"
    end

    test "shows new sheet button when can_edit" do
      html = render_section([], can_edit: true)
      assert html =~ "New Sheet"
    end

    test "hides new sheet button when cannot edit" do
      html = render_section([], can_edit: false)
      refute html =~ "New Sheet"
    end
  end

  # ── Search ──────────────────────────────────────────────────────

  describe "search" do
    test "renders search input when sheets exist" do
      html = render_section([make_sheet(1)])
      assert html =~ "sheets-tree-search"
      assert html =~ "TreeSearch"
      assert html =~ "Filter sheets"
    end

    test "search references tree container" do
      html = render_section([make_sheet(1)])
      assert html =~ ~s(data-tree-id="sheets-tree-container")
    end
  end

  # ── Tree rendering ──────────────────────────────────────────────

  describe "tree rendering" do
    test "renders sheet names" do
      sheets = [make_sheet(1, name: "Characters"), make_sheet(2, name: "Locations")]
      html = render_section(sheets)
      assert html =~ "Characters"
      assert html =~ "Locations"
    end

    test "renders sheet links with correct path" do
      html = render_section([make_sheet(1)])
      assert html =~ "/workspaces/test-ws/projects/test-proj/sheets/1"
    end

    test "renders sortable when can_edit" do
      html = render_section([make_sheet(1)], can_edit: true)
      assert html =~ "SortableTree"
    end

    test "does not render data-tree-type for sheets" do
      # sheets entity_type is special-cased in generic_tree: tree_type_attr is nil
      html = render_section([make_sheet(1)], can_edit: true)
      refute html =~ ~s(data-tree-type="sheets")
    end

    test "no sortable hook when cannot edit" do
      html = render_section([make_sheet(1)], can_edit: false)
      refute html =~ "SortableTree"
    end
  end

  # ── Avatar rendering ───────────────────────────────────────────

  describe "avatar rendering" do
    test "renders avatar URL when sheet has avatar_asset" do
      sheet = make_sheet(1, avatar_asset: %{url: "https://example.com/avatar.png"})
      html = render_section([sheet])
      assert html =~ "https://example.com/avatar.png"
    end

    test "does not render avatar when avatar_asset is nil" do
      sheet = make_sheet(1, avatar_asset: nil)
      html = render_section([sheet])
      refute html =~ "avatar"
    end
  end

  # ── Child sheets ─────────────────────────────────────────────────

  describe "child sheets" do
    test "renders children recursively" do
      sheets = [
        make_sheet(1,
          name: "Parent",
          children: [make_sheet(2, name: "Child")]
        )
      ]

      html = render_section(sheets)
      assert html =~ "Parent"
      assert html =~ "Child"
    end

    test "renders add child button when can_edit" do
      sheets = [
        make_sheet(1, children: [make_sheet(2)])
      ]

      html = render_section(sheets, can_edit: true)
      assert html =~ "create_child_sheet"
    end

    test "hides add child button when cannot edit" do
      sheets = [
        make_sheet(1, children: [make_sheet(2)])
      ]

      html = render_section(sheets, can_edit: false)
      refute html =~ "create_child_sheet"
    end
  end

  # ── New sheet button ────────────────────────────────────────────

  describe "new sheet button" do
    test "shows create button when can_edit" do
      html = render_section([make_sheet(1)], can_edit: true)
      assert html =~ "create_sheet"
      assert html =~ "New Sheet"
    end

    test "hides create button when cannot edit" do
      html = render_section([make_sheet(1)], can_edit: false)
      refute html =~ "New Sheet"
    end
  end

  # ── Sheet menu ──────────────────────────────────────────────────

  describe "sheet menu" do
    test "shows menu when can_edit" do
      html = render_section([make_sheet(1)], can_edit: true)
      assert html =~ "more-horizontal"
    end

    test "hides menu when cannot edit" do
      html = render_section([make_sheet(1)], can_edit: false)
      refute html =~ "more-horizontal"
    end

    test "shows trash option" do
      html = render_section([make_sheet(1)], can_edit: true)
      assert html =~ "Move to Trash"
      assert html =~ "set_pending_delete_sheet"
    end

    test "renders confirm modal for delete" do
      html = render_section([make_sheet(1)], can_edit: true)
      assert html =~ "delete-sheet-sidebar-confirm"
      assert html =~ "Delete sheet?"
    end
  end

  # ── Selection state ────────────────────────────────────────────

  describe "selection state" do
    test "marks selected leaf sheet with active style" do
      html = render_section([make_sheet(1)], selected_sheet_id: "1")
      # The tree_leaf renders with bg-base-content/5 active class when selected
      assert html =~ ~s(data-item-id="1")
      assert html =~ "bg-base-content/5"
    end

    test "renders tree_node with id when sheet has children" do
      sheets = [
        make_sheet(1,
          name: "Parent",
          children: [make_sheet(2, name: "Child")]
        )
      ]

      html = render_section(sheets, selected_sheet_id: "1")
      assert html =~ ~s(id="sheet-1")
    end

    test "expands parent when child is selected" do
      sheets = [
        make_sheet(1,
          name: "Parent",
          children: [make_sheet(2, name: "Child")]
        )
      ]

      html = render_section(sheets, selected_sheet_id: "2")
      # Both parent and child should be visible
      assert html =~ "Parent"
      assert html =~ "Child"
    end
  end
end
