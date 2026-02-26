defmodule StoryarnWeb.Components.Sidebar.ScreenplayTreeTest do
  use StoryarnWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias StoryarnWeb.Components.Sidebar.ScreenplayTree

  defp make_screenplay(id, opts \\ []) do
    %{
      id: id,
      name: Keyword.get(opts, :name, "Screenplay #{id}"),
      children: Keyword.get(opts, :children, [])
    }
  end

  defp make_workspace, do: %{slug: "test-ws"}
  defp make_project, do: %{slug: "test-proj"}

  defp render_section(screenplays_tree, opts \\ []) do
    render_component(&ScreenplayTree.screenplays_section/1,
      screenplays_tree: screenplays_tree,
      workspace: make_workspace(),
      project: make_project(),
      selected_screenplay_id: Keyword.get(opts, :selected_screenplay_id, nil),
      can_edit: Keyword.get(opts, :can_edit, true)
    )
  end

  # ── Empty state ────────────────────────────────────────────────

  describe "empty state" do
    test "shows empty message when no screenplays" do
      html = render_section([])
      assert html =~ "No screenplays yet"
    end

    test "hides search when no screenplays" do
      html = render_section([])
      refute html =~ "screenplays-tree-search"
    end

    test "still shows new screenplay button when can_edit" do
      html = render_section([], can_edit: true)
      assert html =~ "New Screenplay"
    end

    test "hides new screenplay button when cannot edit" do
      html = render_section([], can_edit: false)
      refute html =~ "New Screenplay"
    end
  end

  # ── Search ──────────────────────────────────────────────────────

  describe "search" do
    test "renders search input when screenplays exist" do
      html = render_section([make_screenplay(1)])
      assert html =~ "screenplays-tree-search"
      assert html =~ "TreeSearch"
      assert html =~ "Filter screenplays"
    end

    test "search references tree container" do
      html = render_section([make_screenplay(1)])
      assert html =~ ~s(data-tree-id="screenplays-tree-container")
    end
  end

  # ── Tree rendering ──────────────────────────────────────────────

  describe "tree rendering" do
    test "renders screenplay names" do
      screenplays = [
        make_screenplay(1, name: "Main Story"),
        make_screenplay(2, name: "Side Arc")
      ]

      html = render_section(screenplays)
      assert html =~ "Main Story"
      assert html =~ "Side Arc"
    end

    test "renders screenplay links with correct path" do
      html = render_section([make_screenplay(1)])
      assert html =~ "/workspaces/test-ws/projects/test-proj/screenplays/1"
    end

    test "renders scroll-text icon" do
      html = render_section([make_screenplay(1)])
      assert html =~ "scroll-text"
    end

    test "renders sortable when can_edit" do
      html = render_section([make_screenplay(1)], can_edit: true)
      assert html =~ "SortableTree"
      assert html =~ ~s(data-tree-type="screenplays")
    end

    test "no sortable hook when cannot edit" do
      html = render_section([make_screenplay(1)], can_edit: false)
      refute html =~ "SortableTree"
    end
  end

  # ── Child screenplays ─────────────────────────────────────────

  describe "child screenplays" do
    test "renders children recursively" do
      screenplays = [
        make_screenplay(1,
          name: "Parent",
          children: [make_screenplay(2, name: "Child")]
        )
      ]

      html = render_section(screenplays)
      assert html =~ "Parent"
      assert html =~ "Child"
    end

    test "renders add child button when can_edit" do
      screenplays = [
        make_screenplay(1, children: [make_screenplay(2)])
      ]

      html = render_section(screenplays, can_edit: true)
      assert html =~ "create_child_screenplay"
    end

    test "hides add child button when cannot edit" do
      screenplays = [
        make_screenplay(1, children: [make_screenplay(2)])
      ]

      html = render_section(screenplays, can_edit: false)
      refute html =~ "create_child_screenplay"
    end
  end

  # ── New screenplay button ─────────────────────────────────────

  describe "new screenplay button" do
    test "shows create button when can_edit" do
      html = render_section([make_screenplay(1)], can_edit: true)
      assert html =~ "create_screenplay"
      assert html =~ "New Screenplay"
    end

    test "hides create button when cannot edit" do
      html = render_section([make_screenplay(1)], can_edit: false)
      refute html =~ "New Screenplay"
    end
  end

  # ── Screenplay menu ──────────────────────────────────────────

  describe "screenplay menu" do
    test "shows menu when can_edit" do
      html = render_section([make_screenplay(1)], can_edit: true)
      assert html =~ "more-horizontal"
    end

    test "hides menu when cannot edit" do
      html = render_section([make_screenplay(1)], can_edit: false)
      refute html =~ "more-horizontal"
    end

    test "shows trash option" do
      html = render_section([make_screenplay(1)], can_edit: true)
      assert html =~ "Move to Trash"
      assert html =~ "set_pending_delete_screenplay"
    end

    test "renders confirm modal for delete" do
      html = render_section([make_screenplay(1)], can_edit: true)
      assert html =~ "delete-screenplay-sidebar-confirm"
      assert html =~ "Delete screenplay?"
    end
  end
end
