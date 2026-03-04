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

  # ── SceneTree-unique: icon and URL ───────────────────────────────

  describe "scene-specific tree rendering" do
    test "renders map icon" do
      html = render_section([make_scene(1)])
      assert html =~ "lucide-map"
    end

    test "renders scene links with correct path" do
      html = render_section([make_scene(1)])
      assert html =~ "/workspaces/test-ws/projects/test-proj/scenes/1"
    end
  end

  # ── SceneTree-unique: zone extra children ────────────────────────

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

    test "renders zone with pentagon icon and highlight link" do
      scene =
        make_scene(1,
          sidebar_zones: [make_zone(10)],
          zone_count: 1
        )

      html = render_section([scene])
      assert html =~ "pentagon"
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

  # ── SceneTree-unique: pin extra children ─────────────────────────

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

    test "renders pin with map-pin icon and highlight link" do
      scene =
        make_scene(1,
          sidebar_pins: [make_pin(20)],
          pin_count: 1
        )

      html = render_section([scene])
      assert html =~ "map-pin"
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

  # ── SceneTree-unique: composite rendering ────────────────────────

  describe "composite rendering" do
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
