defmodule StoryarnWeb.Components.Sidebar.SceneTreeTest do
  use StoryarnWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias StoryarnWeb.Components.Sidebar.SceneTree

  defp make_scene(id, opts \\ []) do
    %{
      id: id,
      name: Keyword.get(opts, :name, "Scene #{id}"),
      children: Keyword.get(opts, :children, []),
      sidebar_zones: Keyword.get(opts, :sidebar_zones, []),
      sidebar_pins: Keyword.get(opts, :sidebar_pins, []),
      zone_count: Keyword.get(opts, :zone_count, 0),
      pin_count: Keyword.get(opts, :pin_count, 0)
    }
  end

  defp make_zone(id, opts \\ []) do
    %{
      id: id,
      name: Keyword.get(opts, :name, "Zone #{id}")
    }
  end

  defp make_pin(id, opts \\ []) do
    %{
      id: id,
      label: Keyword.get(opts, :label, nil)
    }
  end

  defp make_workspace, do: %{slug: "test-ws"}
  defp make_project, do: %{slug: "test-proj"}

  defp render_section(scenes_tree, opts \\ []) do
    render_component(&SceneTree.scenes_section/1,
      scenes_tree: scenes_tree,
      workspace: make_workspace(),
      project: make_project(),
      selected_scene_id: Keyword.get(opts, :selected_scene_id, nil),
      can_edit: Keyword.get(opts, :can_edit, true)
    )
  end

  # ── Empty state ────────────────────────────────────────────────

  describe "empty state" do
    test "shows empty message when no scenes" do
      html = render_section([])
      assert html =~ "No scenes yet"
    end

    test "hides search when no scenes" do
      html = render_section([])
      refute html =~ "scenes-tree-search"
    end

    test "shows new scene button when can_edit" do
      html = render_section([], can_edit: true)
      assert html =~ "New Scene"
    end

    test "hides new scene button when cannot edit" do
      html = render_section([], can_edit: false)
      refute html =~ "New Scene"
    end
  end

  # ── Search ──────────────────────────────────────────────────────

  describe "search" do
    test "renders search input when scenes exist" do
      html = render_section([make_scene(1)])
      assert html =~ "scenes-tree-search"
      assert html =~ "TreeSearch"
      assert html =~ "Filter scenes"
    end

    test "search references tree container" do
      html = render_section([make_scene(1)])
      assert html =~ ~s(data-tree-id="scenes-tree-container")
    end
  end

  # ── Tree rendering ──────────────────────────────────────────────

  describe "tree rendering" do
    test "renders scene names" do
      scenes = [make_scene(1, name: "Forest"), make_scene(2, name: "Castle")]
      html = render_section(scenes)
      assert html =~ "Forest"
      assert html =~ "Castle"
    end

    test "renders scene links with correct path" do
      html = render_section([make_scene(1)])
      assert html =~ "/workspaces/test-ws/projects/test-proj/scenes/1"
    end

    test "renders map icon" do
      html = render_section([make_scene(1)])
      assert html =~ "lucide-map"
    end

    test "renders sortable when can_edit" do
      html = render_section([make_scene(1)], can_edit: true)
      assert html =~ "SortableTree"
      assert html =~ ~s(data-tree-type="scenes")
    end

    test "no sortable hook when cannot edit" do
      html = render_section([make_scene(1)], can_edit: false)
      refute html =~ "SortableTree"
    end
  end

  # ── Child scenes ─────────────────────────────────────────────────

  describe "child scenes" do
    test "renders children recursively" do
      scenes = [
        make_scene(1,
          name: "World",
          children: [make_scene(2, name: "Dungeon")]
        )
      ]

      html = render_section(scenes)
      assert html =~ "World"
      assert html =~ "Dungeon"
    end

    test "renders add child button when can_edit" do
      scenes = [
        make_scene(1, children: [make_scene(2)])
      ]

      html = render_section(scenes, can_edit: true)
      assert html =~ "create_child_scene"
    end

    test "hides add child button when cannot edit" do
      scenes = [
        make_scene(1, children: [make_scene(2)])
      ]

      html = render_section(scenes, can_edit: false)
      refute html =~ "create_child_scene"
    end
  end

  # ── Extra children: zones ─────────────────────────────────────

  describe "zone extra children" do
    test "renders zone names inside scene node" do
      scene =
        make_scene(1,
          name: "Forest",
          sidebar_zones: [make_zone(10, name: "Dark Clearing")],
          zone_count: 1
        )

      html = render_section([scene])
      assert html =~ "Dark Clearing"
    end

    test "renders zone with pentagon icon" do
      scene =
        make_scene(1,
          sidebar_zones: [make_zone(10)],
          zone_count: 1
        )

      html = render_section([scene])
      assert html =~ "pentagon"
    end

    test "renders zone link with highlight parameter" do
      scene =
        make_scene(1,
          sidebar_zones: [make_zone(10)],
          zone_count: 1
        )

      html = render_section([scene])
      assert html =~ "highlight=zone:10"
    end

    test "shows 'more zones' text when zone_count exceeds displayed zones" do
      scene =
        make_scene(1,
          sidebar_zones: [make_zone(10)],
          zone_count: 5
        )

      html = render_section([scene])
      assert html =~ "4 more zones"
    end

    test "does not show 'more zones' when all zones are displayed" do
      scene =
        make_scene(1,
          sidebar_zones: [make_zone(10), make_zone(11)],
          zone_count: 2
        )

      html = render_section([scene])
      refute html =~ "more zones"
    end

    test "scene with zones renders as tree_node (expandable)" do
      scene =
        make_scene(1,
          sidebar_zones: [make_zone(10)],
          zone_count: 1
        )

      html = render_section([scene])
      # tree_node gets an id attribute
      assert html =~ ~s(id="scene-1")
    end
  end

  # ── Extra children: pins ──────────────────────────────────────

  describe "pin extra children" do
    test "renders pin with label" do
      scene =
        make_scene(1,
          sidebar_pins: [make_pin(20, label: "Treasure Chest")],
          pin_count: 1
        )

      html = render_section([scene])
      assert html =~ "Treasure Chest"
    end

    test "renders default label when pin has no label" do
      scene =
        make_scene(1,
          sidebar_pins: [make_pin(20, label: nil)],
          pin_count: 1
        )

      html = render_section([scene])
      assert html =~ "Pin"
    end

    test "renders pin with map-pin icon" do
      scene =
        make_scene(1,
          sidebar_pins: [make_pin(20)],
          pin_count: 1
        )

      html = render_section([scene])
      assert html =~ "map-pin"
    end

    test "renders pin link with highlight parameter" do
      scene =
        make_scene(1,
          sidebar_pins: [make_pin(20)],
          pin_count: 1
        )

      html = render_section([scene])
      assert html =~ "highlight=pin:20"
    end

    test "shows 'more pins' text when pin_count exceeds displayed pins" do
      scene =
        make_scene(1,
          sidebar_pins: [make_pin(20)],
          pin_count: 3
        )

      html = render_section([scene])
      assert html =~ "2 more pins"
    end

    test "does not show 'more pins' when all pins are displayed" do
      scene =
        make_scene(1,
          sidebar_pins: [make_pin(20)],
          pin_count: 1
        )

      html = render_section([scene])
      refute html =~ "more pins"
    end
  end

  # ── New scene button ────────────────────────────────────────────

  describe "new scene button" do
    test "shows create button when can_edit" do
      html = render_section([make_scene(1)], can_edit: true)
      assert html =~ "create_scene"
      assert html =~ "New Scene"
    end

    test "hides create button when cannot edit" do
      html = render_section([make_scene(1)], can_edit: false)
      refute html =~ "New Scene"
    end
  end

  # ── Scene menu ──────────────────────────────────────────────────

  describe "scene menu" do
    test "shows menu when can_edit" do
      html = render_section([make_scene(1)], can_edit: true)
      assert html =~ "more-horizontal"
    end

    test "hides menu when cannot edit" do
      html = render_section([make_scene(1)], can_edit: false)
      refute html =~ "more-horizontal"
    end

    test "shows trash option" do
      html = render_section([make_scene(1)], can_edit: true)
      assert html =~ "Move to Trash"
      assert html =~ "set_pending_delete_scene"
    end

    test "renders confirm modal for delete" do
      html = render_section([make_scene(1)], can_edit: true)
      assert html =~ "delete-scene-sidebar-confirm"
      assert html =~ "Delete scene?"
    end
  end

  # ── Selection + expansion ──────────────────────────────────────

  describe "selection and expansion" do
    test "expands parent when child scene is selected" do
      scenes = [
        make_scene(1,
          name: "World",
          children: [make_scene(2, name: "Dungeon")]
        )
      ]

      html = render_section(scenes, selected_scene_id: "2")
      assert html =~ "World"
      assert html =~ "Dungeon"
    end

    test "scene with both children and zones renders correctly" do
      scene =
        make_scene(1,
          name: "Overworld",
          children: [make_scene(2, name: "Cave")],
          sidebar_zones: [make_zone(10, name: "River Zone")],
          zone_count: 1
        )

      html = render_section([scene])
      assert html =~ "Overworld"
      assert html =~ "Cave"
      assert html =~ "River Zone"
    end
  end
end
