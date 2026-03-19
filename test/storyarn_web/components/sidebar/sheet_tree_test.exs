defmodule StoryarnWeb.Components.Sidebar.SheetTreeTest do
  use StoryarnWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias StoryarnWeb.Components.Sidebar.SheetTree

  defp make_sheet(id, opts \\ []) do
    %{
      id: id,
      name: Keyword.get(opts, :name, "Sheet #{id}"),
      avatars: Keyword.get(opts, :avatars, []),
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

  # ── SheetTree-unique: data-tree-type special case ────────────────

  describe "sheet-specific tree rendering" do
    test "does not render data-tree-type for sheets" do
      # sheets entity_type is special-cased in generic_tree: tree_type_attr is nil
      html = render_section([make_sheet(1)], can_edit: true)
      refute html =~ ~s(data-tree-type="sheets")
    end

    test "renders sheet links with correct path" do
      html = render_section([make_sheet(1)])
      assert html =~ "/workspaces/test-ws/projects/test-proj/sheets/1"
    end
  end

  # ── SheetTree-unique: avatar rendering ───────────────────────────

  describe "avatar rendering" do
    test "renders avatar URL when sheet has avatars" do
      sheet =
        make_sheet(1,
          avatars: [%{is_default: true, asset: %{url: "https://example.com/avatar.png"}}]
        )

      html = render_section([sheet])
      assert html =~ "https://example.com/avatar.png"
    end

    test "does not render avatar when avatars is empty" do
      sheet = make_sheet(1, avatars: [])
      html = render_section([sheet])
      refute html =~ "avatar"
    end
  end

  # ── SheetTree-unique: selection threading ─────────────────────────

  describe "selection state" do
    test "passes selected_sheet_id through to tree rendering" do
      sheets = [
        make_sheet(1,
          name: "Parent",
          children: [make_sheet(2, name: "Child")]
        )
      ]

      # Selected leaf gets active style
      leaf_html = render_section([make_sheet(1)], selected_sheet_id: "1")
      assert leaf_html =~ ~s(data-item-id="1")
      assert leaf_html =~ "bg-base-content/5"

      # Parent node gets its id
      parent_html = render_section(sheets, selected_sheet_id: "1")
      assert parent_html =~ ~s(id="sheet-1")

      # Child selection keeps parent visible
      child_html = render_section(sheets, selected_sheet_id: "2")
      assert child_html =~ "Parent"
      assert child_html =~ "Child"
    end
  end
end
