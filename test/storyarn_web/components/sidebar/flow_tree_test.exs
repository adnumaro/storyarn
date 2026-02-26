defmodule StoryarnWeb.Components.Sidebar.FlowTreeTest do
  use StoryarnWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias StoryarnWeb.Components.Sidebar.FlowTree

  defp make_flow(id, opts \\ []) do
    %{
      id: id,
      name: Keyword.get(opts, :name, "Flow #{id}"),
      is_main: Keyword.get(opts, :is_main, false),
      children: Keyword.get(opts, :children, [])
    }
  end

  defp make_workspace, do: %{slug: "test-ws"}
  defp make_project, do: %{slug: "test-proj"}

  defp render_section(flows_tree, opts \\ []) do
    render_component(&FlowTree.flows_section/1,
      flows_tree: flows_tree,
      workspace: make_workspace(),
      project: make_project(),
      selected_flow_id: Keyword.get(opts, :selected_flow_id, nil),
      can_edit: Keyword.get(opts, :can_edit, true)
    )
  end

  # ── Empty state ────────────────────────────────────────────────

  describe "empty state" do
    test "shows empty message when no flows" do
      html = render_section([])
      assert html =~ "No flows yet"
    end

    test "hides search when no flows" do
      html = render_section([])
      refute html =~ "flows-tree-search"
    end

    test "still shows new flow button when can_edit" do
      html = render_section([], can_edit: true)
      assert html =~ "New Flow"
    end
  end

  # ── Search ──────────────────────────────────────────────────────

  describe "search" do
    test "renders search input when flows exist" do
      html = render_section([make_flow(1)])
      assert html =~ "flows-tree-search"
      assert html =~ "TreeSearch"
      assert html =~ "Filter flows"
    end

    test "search references tree container" do
      html = render_section([make_flow(1)])
      assert html =~ ~s(data-tree-id="flows-tree-container")
    end
  end

  # ── Tree rendering ──────────────────────────────────────────────

  describe "tree rendering" do
    test "renders flow names" do
      flows = [make_flow(1, name: "Main Story"), make_flow(2, name: "Side Quest")]
      html = render_section(flows)
      assert html =~ "Main Story"
      assert html =~ "Side Quest"
    end

    test "renders flow links with correct path" do
      html = render_section([make_flow(1)])
      assert html =~ "/workspaces/test-ws/projects/test-proj/flows/1"
    end

    test "renders git-branch icon" do
      html = render_section([make_flow(1)])
      assert html =~ "git-branch"
    end

    test "renders sortable when can_edit" do
      html = render_section([make_flow(1)], can_edit: true)
      assert html =~ "SortableTree"
      assert html =~ ~s(data-tree-type="flows")
    end

    test "no sortable hook when cannot edit" do
      html = render_section([make_flow(1)], can_edit: false)
      refute html =~ "SortableTree"
    end
  end

  # ── Child flows ─────────────────────────────────────────────────

  describe "child flows" do
    test "renders children recursively" do
      flows = [
        make_flow(1,
          name: "Parent",
          children: [make_flow(2, name: "Child")]
        )
      ]

      html = render_section(flows)
      assert html =~ "Parent"
      assert html =~ "Child"
    end

    test "renders add child button" do
      flows = [
        make_flow(1, children: [make_flow(2)])
      ]

      html = render_section(flows, can_edit: true)
      assert html =~ "create_child_flow"
    end
  end

  # ── New flow button ────────────────────────────────────────────

  describe "new flow button" do
    test "shows create button when can_edit" do
      html = render_section([make_flow(1)], can_edit: true)
      assert html =~ "create_flow"
      assert html =~ "New Flow"
    end

    test "hides create button when cannot edit" do
      html = render_section([make_flow(1)], can_edit: false)
      refute html =~ "New Flow"
    end
  end

  # ── Flow menu ──────────────────────────────────────────────────

  describe "flow menu" do
    test "shows menu when can_edit" do
      html = render_section([make_flow(1)], can_edit: true)
      assert html =~ "more-horizontal"
    end

    test "hides menu when cannot edit" do
      html = render_section([make_flow(1)], can_edit: false)
      refute html =~ "more-horizontal"
    end

    test "shows Set as main for non-main flow" do
      html = render_section([make_flow(1, is_main: false)], can_edit: true)
      assert html =~ "Set as main"
      assert html =~ "set_main_flow"
    end

    test "hides Set as main for main flow" do
      html = render_section([make_flow(1, is_main: true)], can_edit: true)
      refute html =~ "Set as main"
    end

    test "shows trash option" do
      html = render_section([make_flow(1)], can_edit: true)
      assert html =~ "Move to Trash"
      assert html =~ "set_pending_delete_flow"
    end

    test "renders confirm modal for delete" do
      html = render_section([make_flow(1)], can_edit: true)
      assert html =~ "delete-flow-sidebar-confirm"
      assert html =~ "Delete flow?"
    end
  end
end
