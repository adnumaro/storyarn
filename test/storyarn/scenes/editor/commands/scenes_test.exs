defmodule Storyarn.Scenes.Editor.Commands.ScenesTest do
  use Storyarn.DataCase, async: true

  import Ecto.Query
  import Storyarn.AccountsFixtures
  import Storyarn.ProjectsFixtures
  import Storyarn.ScenesFixtures

  alias Storyarn.Repo
  alias Storyarn.Scenes
  alias Storyarn.Scenes.Editor
  alias Storyarn.Scenes.References.Projections.EntityReferenceRecord

  # Shared setup that creates a user and project for most tests
  defp create_project(_context \\ %{}) do
    user = user_fixture()
    project = project_fixture(user)
    %{user: user, project: project}
  end

  # =============================================================================
  # list_scenes/1
  # =============================================================================

  describe "list_scenes/1" do
    test "returns empty list when no scenes exist" do
      %{project: project} = create_project()
      assert Editor.list_scenes(project.id) == []
    end

    test "excludes soft-deleted scenes" do
      %{project: project} = create_project()
      scene = scene_fixture(project, %{name: "Active"})
      deleted = scene_fixture(project, %{name: "Deleted"})

      {:ok, _} = Scenes.delete_scene(deleted)

      scenes = Editor.list_scenes(project.id)
      assert length(scenes) == 1
      assert hd(scenes).id == scene.id
    end

    test "orders by position then name" do
      %{project: project} = create_project()
      _scene_b = scene_fixture(project, %{name: "Bravo", position: 1})
      _scene_a = scene_fixture(project, %{name: "Alpha", position: 0})
      _scene_c = scene_fixture(project, %{name: "Charlie", position: 1})

      scenes = Editor.list_scenes(project.id)
      names = Enum.map(scenes, & &1.name)
      assert names == ["Alpha", "Bravo", "Charlie"]
    end

    test "does not return scenes from other projects" do
      %{project: project1} = create_project()
      %{project: project2} = create_project()

      _scene1 = scene_fixture(project1, %{name: "Project 1 Scene"})
      _scene2 = scene_fixture(project2, %{name: "Project 2 Scene"})

      scenes = Editor.list_scenes(project1.id)
      assert length(scenes) == 1
      assert hd(scenes).name == "Project 1 Scene"
    end
  end

  # =============================================================================
  # list_scenes_tree/1
  # =============================================================================

  describe "list_scenes_tree/1" do
    test "returns empty list for project with no scenes" do
      %{project: project} = create_project()
      assert Editor.list_scenes_tree(project.id) == []
    end

    test "returns flat list when no hierarchy exists" do
      %{project: project} = create_project()
      _scene1 = scene_fixture(project, %{name: "Scene A"})
      _scene2 = scene_fixture(project, %{name: "Scene B"})

      tree = Editor.list_scenes_tree(project.id)
      assert length(tree) == 2
      assert Enum.all?(tree, fn node -> node.children == [] end)
    end

    test "builds nested tree with grandchildren" do
      %{project: project} = create_project()
      world = scene_fixture(project, %{name: "World"})
      continent = scene_fixture(project, %{name: "Continent", parent_id: world.id})
      _city = scene_fixture(project, %{name: "City", parent_id: continent.id})

      tree = Editor.list_scenes_tree(project.id)
      assert length(tree) == 1
      assert hd(tree).name == "World"
      assert length(hd(tree).children) == 1
      assert hd(hd(tree).children).name == "Continent"
      assert length(hd(hd(tree).children).children) == 1
      assert hd(hd(hd(tree).children).children).name == "City"
    end
  end

  # =============================================================================
  # list_scenes_tree_with_elements/1
  # =============================================================================

  describe "list_scenes_tree_with_elements/1" do
    test "returns tree with sidebar element counts" do
      %{project: project} = create_project()
      scene = scene_fixture(project, %{name: "World"})
      _zone = zone_fixture(scene, %{"name" => "Kingdom"})
      _pin = pin_fixture(scene, %{"label" => "Castle"})

      tree = Editor.list_scenes_tree_with_elements(project.id)
      assert length(tree) == 1

      node = hd(tree)
      assert node.zone_count == 1
      assert node.pin_count == 1
      assert length(node.sidebar_zones) == 1
      assert length(node.sidebar_pins) == 1
    end

    test "returns empty sidebar elements for scene with no zones/pins" do
      %{project: project} = create_project()
      _scene = scene_fixture(project, %{name: "Empty Scene"})

      tree = Editor.list_scenes_tree_with_elements(project.id)
      node = hd(tree)

      assert node.zone_count == 0
      assert node.pin_count == 0
      assert node.sidebar_zones == []
      assert node.sidebar_pins == []
    end

    test "limits sidebar elements to 10" do
      %{project: project} = create_project()
      scene = scene_fixture(project, %{name: "Busy Scene"})

      # Create 12 zones (exceeds limit of 10)
      for i <- 1..12 do
        zone_fixture(scene, %{"name" => "Zone #{String.pad_leading("#{i}", 2, "0")}"})
      end

      tree = Editor.list_scenes_tree_with_elements(project.id)
      node = hd(tree)

      assert node.zone_count == 12
      assert length(node.sidebar_zones) == 10
    end

    test "sidebar zones include only named zones ordered by position" do
      %{project: project} = create_project()
      scene = scene_fixture(project, %{name: "Scene"})
      _zone1 = zone_fixture(scene, %{"name" => "Zone Alpha"})
      _zone2 = zone_fixture(scene, %{"name" => "Zone Beta"})

      tree = Editor.list_scenes_tree_with_elements(project.id)
      node = hd(tree)

      assert node.zone_count == 2
      assert length(node.sidebar_zones) == 2
      names = Enum.map(node.sidebar_zones, & &1.name)
      assert "Zone Alpha" in names
      assert "Zone Beta" in names
    end
  end

  # =============================================================================
  # search_scenes/2
  # =============================================================================

  describe "search_scenes/2" do
    test "empty query returns most recently updated scenes" do
      %{project: project} = create_project()
      _scene1 = scene_fixture(project, %{name: "World"})
      _scene2 = scene_fixture(project, %{name: "City"})

      results = Editor.search_scenes(project.id, "")
      assert length(results) == 2
    end

    test "whitespace-only query returns most recently updated scenes" do
      %{project: project} = create_project()
      _scene = scene_fixture(project, %{name: "World"})

      results = Editor.search_scenes(project.id, "   ")
      assert length(results) == 1
    end

    test "matches by shortcut" do
      %{project: project} = create_project()
      _scene = scene_fixture(project, %{name: "World Map"})

      results = Editor.search_scenes(project.id, "world-map")
      assert length(results) == 1
      assert hd(results).shortcut == "world-map"
    end

    test "excludes deleted scenes from search" do
      %{project: project} = create_project()
      scene = scene_fixture(project, %{name: "World"})
      deleted = scene_fixture(project, %{name: "Worldview"})

      {:ok, _} = Scenes.delete_scene(deleted)

      results = Editor.search_scenes(project.id, "World")
      assert length(results) == 1
      assert hd(results).id == scene.id
    end

    test "limits results to default of 20" do
      %{project: project} = create_project()

      for i <- 1..25 do
        scene_fixture(project, %{name: "Scene #{i}"})
      end

      results = Editor.search_scenes(project.id, "Scene")
      assert length(results) == 20
    end

    test "handles special characters in search query" do
      %{project: project} = create_project()
      _scene = scene_fixture(project, %{name: "100% Complete"})

      results = Editor.search_scenes(project.id, "100%")
      assert length(results) == 1
    end
  end

  # =============================================================================
  # get_scene/2 and get_scene!/2
  # =============================================================================

  describe "get_scene/2" do
    test "returns nil for deleted scene" do
      %{project: project} = create_project()
      scene = scene_fixture(project)

      {:ok, _} = Scenes.delete_scene(scene)
      assert Editor.get_scene(project.id, scene.id) == nil
    end

    test "returns nil for scene in different project" do
      %{project: project1} = create_project()
      %{project: project2} = create_project()
      scene = scene_fixture(project1)

      assert Editor.get_scene(project2.id, scene.id) == nil
    end

    test "preloads layers, zones, pins, annotations, connections, and background_asset" do
      %{project: project} = create_project()
      scene = scene_fixture(project)
      _zone = zone_fixture(scene)
      _pin = pin_fixture(scene)
      _annotation = annotation_fixture(scene)

      result = Editor.get_scene(project.id, scene.id)

      assert result.layers != []
      assert length(result.zones) == 1
      assert length(result.pins) == 1
      assert length(result.annotations) == 1
      assert result.connections == []
    end
  end

  describe "get_scene!/2" do
    test "returns scene with preloads" do
      %{project: project} = create_project()
      scene = scene_fixture(project)

      result = Editor.get_scene!(project.id, scene.id)
      assert result.id == scene.id
      assert is_list(result.layers)
    end

    test "raises for non-existent scene" do
      %{project: project} = create_project()

      assert_raise Ecto.NoResultsError, fn ->
        Editor.get_scene!(project.id, -1)
      end
    end

    test "raises for deleted scene" do
      %{project: project} = create_project()
      scene = scene_fixture(project)
      {:ok, _} = Scenes.delete_scene(scene)

      assert_raise Ecto.NoResultsError, fn ->
        Editor.get_scene!(project.id, scene.id)
      end
    end
  end

  # =============================================================================
  # get_scene_by_id/1
  # =============================================================================

  describe "get_scene_by_id/1" do
    test "returns scene without project scoping" do
      %{project: project} = create_project()
      scene = scene_fixture(project)

      result = Editor.get_scene_by_id(scene.id)
      assert result.id == scene.id
    end

    test "returns nil for non-existent id" do
      assert Editor.get_scene_by_id(-1) == nil
    end

    test "returns nil for deleted scene" do
      %{project: project} = create_project()
      scene = scene_fixture(project)
      {:ok, _} = Scenes.delete_scene(scene)

      assert Editor.get_scene_by_id(scene.id) == nil
    end
  end

  # =============================================================================
  # get_scene_brief/2
  # =============================================================================

  describe "get_scene_brief/2" do
    test "returns scene without preloads" do
      %{project: project} = create_project()
      scene = scene_fixture(project)

      result = Editor.get_scene_brief(project.id, scene.id)
      assert result.id == scene.id
      assert result.name == scene.name
      # Associations should not be loaded
      assert %Ecto.Association.NotLoaded{} = result.layers
    end

    test "returns nil for deleted scene" do
      %{project: project} = create_project()
      scene = scene_fixture(project)
      {:ok, _} = Scenes.delete_scene(scene)

      assert Editor.get_scene_brief(project.id, scene.id) == nil
    end
  end

  # =============================================================================
  # get_scene_including_deleted/2
  # =============================================================================

  describe "get_scene_including_deleted/2" do
    test "returns deleted scene" do
      %{project: project} = create_project()
      scene = scene_fixture(project)
      {:ok, _} = Scenes.delete_scene(scene)

      result = Editor.get_scene_including_deleted(project.id, scene.id)
      assert result.id == scene.id
      assert result.deleted_at
    end

    test "returns non-deleted scene" do
      %{project: project} = create_project()
      scene = scene_fixture(project)

      result = Editor.get_scene_including_deleted(project.id, scene.id)
      assert result.id == scene.id
      assert result.deleted_at == nil
    end

    test "preloads layers, zones, pins, and connections" do
      %{project: project} = create_project()
      scene = scene_fixture(project)

      result = Editor.get_scene_including_deleted(project.id, scene.id)
      assert is_list(result.layers)
      assert is_list(result.zones)
      assert is_list(result.pins)
      assert is_list(result.connections)
    end

    test "returns nil for non-existent scene" do
      %{project: project} = create_project()
      assert Editor.get_scene_including_deleted(project.id, -1) == nil
    end
  end

  # =============================================================================
  # create_scene/2
  # =============================================================================

  describe "create_scene/2" do
    test "creates scene with atom-keyed attrs" do
      %{project: project} = create_project()

      {:ok, scene} = Editor.create_scene(project, %{name: "My Scene"})
      assert scene.name == "My Scene"
      assert scene.project_id == project.id
    end

    test "creates scene with string-keyed attrs" do
      %{project: project} = create_project()

      {:ok, scene} = Editor.create_scene(project, %{"name" => "String Scene"})
      assert scene.name == "String Scene"
    end

    test "auto-generates shortcut from name" do
      %{project: project} = create_project()

      {:ok, scene} = Editor.create_scene(project, %{name: "The Great Forest"})
      assert scene.shortcut == "the-great-forest"
    end

    test "respects provided shortcut" do
      %{project: project} = create_project()

      {:ok, scene} =
        Editor.create_scene(project, %{name: "Test", shortcut: "custom-shortcut"})

      assert scene.shortcut == "custom-shortcut"
    end

    test "auto-assigns position in correct parent scope" do
      %{project: project} = create_project()
      parent = scene_fixture(project, %{name: "Parent"})

      {:ok, child1} =
        Editor.create_scene(project, %{name: "Child 1", parent_id: parent.id})

      {:ok, child2} =
        Editor.create_scene(project, %{name: "Child 2", parent_id: parent.id})

      # Root scenes are independent from children positions
      {:ok, root} = Editor.create_scene(project, %{name: "Root"})

      assert child1.position == 0
      assert child2.position == 1
      # Root should have position after the parent
      assert root.position >= 0
    end

    test "creates default layer as part of transaction" do
      %{project: project} = create_project()

      {:ok, scene} = Editor.create_scene(project, %{name: "With Layer"})

      layers = Scenes.list_layers(scene.id)
      assert length(layers) == 1
      assert hd(layers).name == "Default"
      assert hd(layers).is_default == true
      assert hd(layers).position == 0
    end

    test "returns error for missing name" do
      %{project: project} = create_project()

      {:error, changeset} = Editor.create_scene(project, %{})
      assert "can't be blank" in errors_on(changeset).name
    end

    test "returns error for name exceeding 200 chars" do
      %{project: project} = create_project()

      {:error, changeset} =
        Editor.create_scene(project, %{name: String.duplicate("a", 201)})

      assert errors_on(changeset).name != []
    end

    test "returns error for invalid shortcut format" do
      %{project: project} = create_project()

      {:error, changeset} =
        Editor.create_scene(project, %{name: "Test", shortcut: "INVALID!"})

      assert errors_on(changeset).shortcut != []
    end
  end

  # =============================================================================
  # update_scene/2
  # =============================================================================

  describe "update_scene/2" do
    test "updates name" do
      %{project: project} = create_project()
      scene = scene_fixture(project, %{name: "Old"})

      {:ok, updated} = Editor.update_scene(scene, %{name: "New"})
      assert updated.name == "New"
    end

    test "regenerates shortcut when name changes" do
      %{project: project} = create_project()
      scene = scene_fixture(project, %{name: "Original Name"})
      assert scene.shortcut == "original-name"

      {:ok, updated} = Editor.update_scene(scene, %{name: "Changed Name"})
      assert updated.shortcut == "changed-name"
    end

    test "regenerates shortcut when a referenced Scene changes name" do
      %{project: project} = create_project()
      source = scene_fixture(project, %{name: "Source"})
      referenced = scene_fixture(project, %{name: "Original Name"})

      zone_fixture(source, %{
        "target_type" => "scene",
        "target_id" => referenced.id
      })

      assert Repo.exists?(
               from reference in EntityReferenceRecord,
                 where:
                   reference.target_type == "scene" and
                     reference.target_id == ^referenced.id
             )

      assert {:ok, updated} = Editor.update_scene(referenced, %{name: "Changed Name"})
      assert updated.shortcut == "changed-name"
    end

    test "does not change shortcut when name is not updated" do
      %{project: project} = create_project()
      scene = scene_fixture(project, %{name: "Stable"})

      {:ok, updated} = Editor.update_scene(scene, %{description: "New description"})
      assert updated.shortcut == scene.shortcut
    end

    test "updates canvas settings" do
      %{project: project} = create_project()
      scene = scene_fixture(project)

      {:ok, updated} =
        Editor.update_scene(scene, %{
          width: 1920,
          height: 1080,
          default_zoom: 2.0,
          default_center_x: 75.0,
          default_center_y: 25.0
        })

      assert updated.width == 1920
      assert updated.height == 1080
      assert updated.default_zoom == 2.0
      assert updated.default_center_x == 75.0
      assert updated.default_center_y == 25.0
    end

    test "validates default_zoom must be positive" do
      %{project: project} = create_project()
      scene = scene_fixture(project)

      {:error, changeset} = Editor.update_scene(scene, %{default_zoom: 0})
      assert errors_on(changeset).default_zoom != []
    end

    test "validates default_center_x range 0-100" do
      %{project: project} = create_project()
      scene = scene_fixture(project)

      {:error, changeset} = Editor.update_scene(scene, %{default_center_x: 101.0})
      assert errors_on(changeset).default_center_x != []

      {:error, changeset} = Editor.update_scene(scene, %{default_center_x: -1.0})
      assert errors_on(changeset).default_center_x != []
    end

    test "validates description max length" do
      %{project: project} = create_project()
      scene = scene_fixture(project)

      {:error, changeset} =
        Editor.update_scene(scene, %{description: String.duplicate("a", 2001)})

      assert errors_on(changeset).description != []
    end
  end

  # =============================================================================
  # delete_scene/1
  # =============================================================================

  describe "delete_scene/1" do
    test "soft-deletes scene and sets deleted_at" do
      %{project: project} = create_project()
      scene = scene_fixture(project)

      {:ok, deleted} = Editor.delete_scene(scene)
      assert deleted.deleted_at
    end

    test "soft-deletes children recursively" do
      %{project: project} = create_project()
      parent = scene_fixture(project, %{name: "Parent"})
      child = scene_fixture(project, %{name: "Child", parent_id: parent.id})
      grandchild = scene_fixture(project, %{name: "Grandchild", parent_id: child.id})

      {:ok, _} = Editor.delete_scene(parent)

      assert Editor.get_scene(project.id, parent.id) == nil
      assert Editor.get_scene(project.id, child.id) == nil
      assert Editor.get_scene(project.id, grandchild.id) == nil
    end

    test "does not affect siblings when deleting a child" do
      %{project: project} = create_project()
      parent = scene_fixture(project, %{name: "Parent"})
      child1 = scene_fixture(project, %{name: "Child 1", parent_id: parent.id})
      child2 = scene_fixture(project, %{name: "Child 2", parent_id: parent.id})

      {:ok, _} = Editor.delete_scene(child1)

      assert Editor.get_scene(project.id, child1.id) == nil
      assert Editor.get_scene(project.id, child2.id)
      assert Editor.get_scene(project.id, parent.id)
    end
  end

  # =============================================================================
  # hard_delete_scene/1
  # =============================================================================

  describe "hard_delete_scene/1" do
    test "permanently removes scene from database" do
      %{project: project} = create_project()
      scene = scene_fixture(project)

      {:ok, _} = Editor.hard_delete_scene(scene)

      assert Editor.get_scene(project.id, scene.id) == nil
      assert Editor.get_scene_including_deleted(project.id, scene.id) == nil
    end
  end

  # =============================================================================
  # restore_scene/1
  # =============================================================================

  describe "restore_scene/1" do
    test "clears deleted_at timestamp" do
      %{project: project} = create_project()
      scene = scene_fixture(project)
      {:ok, _} = Editor.delete_scene(scene)

      deleted = Editor.get_scene_including_deleted(project.id, scene.id)
      {:ok, restored} = Editor.restore_scene(deleted)

      assert restored.deleted_at == nil
    end

    test "restores children that were deleted at the same time" do
      %{project: project} = create_project()
      parent = scene_fixture(project, %{name: "Parent"})
      _child = scene_fixture(project, %{name: "Child", parent_id: parent.id})

      {:ok, _} = Editor.delete_scene(parent)

      deleted_parent = Editor.get_scene_including_deleted(project.id, parent.id)
      {:ok, _} = Editor.restore_scene(deleted_parent)

      # Both parent and child should be restored
      assert Editor.get_scene(project.id, parent.id)
      children = Editor.list_scenes(project.id)
      assert length(children) == 2
    end
  end

  # =============================================================================
  # list_deleted_scenes/1
  # =============================================================================

  describe "list_deleted_scenes/1" do
    test "returns only soft-deleted scenes" do
      %{project: project} = create_project()
      _active = scene_fixture(project, %{name: "Active"})
      deleted = scene_fixture(project, %{name: "Deleted"})

      {:ok, _} = Editor.delete_scene(deleted)

      deleted_scenes = Editor.list_deleted_scenes(project.id)
      assert length(deleted_scenes) == 1
      assert hd(deleted_scenes).id == deleted.id
    end

    test "returns empty list when no deleted scenes" do
      %{project: project} = create_project()
      _scene = scene_fixture(project)

      assert Editor.list_deleted_scenes(project.id) == []
    end
  end

  # =============================================================================
  # list_ancestors/1
  # =============================================================================

  describe "list_ancestors/1" do
    test "returns empty list for root scene" do
      %{project: project} = create_project()
      scene = scene_fixture(project, %{name: "Root"})

      assert Editor.list_ancestors(scene) == []
    end

    test "returns parent for first-level child" do
      %{project: project} = create_project()
      parent = scene_fixture(project, %{name: "Parent"})
      child = scene_fixture(project, %{name: "Child", parent_id: parent.id})

      ancestors = Editor.list_ancestors(child)
      assert length(ancestors) == 1
      assert hd(ancestors).id == parent.id
    end

    test "returns ancestors in root-to-parent order" do
      %{project: project} = create_project()
      grandparent = scene_fixture(project, %{name: "Grandparent"})
      parent = scene_fixture(project, %{name: "Parent", parent_id: grandparent.id})
      child = scene_fixture(project, %{name: "Child", parent_id: parent.id})

      ancestors = Editor.list_ancestors(child)
      assert length(ancestors) == 2
      assert Enum.at(ancestors, 0).id == grandparent.id
      assert Enum.at(ancestors, 1).id == parent.id
    end

    test "handles deep hierarchy" do
      %{project: project} = create_project()

      # Create a 5-level deep hierarchy
      l1 = scene_fixture(project, %{name: "Level 1"})
      l2 = scene_fixture(project, %{name: "Level 2", parent_id: l1.id})
      l3 = scene_fixture(project, %{name: "Level 3", parent_id: l2.id})
      l4 = scene_fixture(project, %{name: "Level 4", parent_id: l3.id})
      l5 = scene_fixture(project, %{name: "Level 5", parent_id: l4.id})

      ancestors = Editor.list_ancestors(l5)
      assert length(ancestors) == 4
      ids = Enum.map(ancestors, & &1.id)
      assert ids == [l1.id, l2.id, l3.id, l4.id]
    end
  end

  # =============================================================================
  # change_scene/2
  # =============================================================================

  describe "change_scene/2" do
    test "returns a changeset for the scene" do
      %{project: project} = create_project()
      scene = scene_fixture(project)

      changeset = Editor.change_scene(scene)
      assert %Ecto.Changeset{} = changeset
    end

    test "tracks changes when attrs provided" do
      %{project: project} = create_project()
      scene = scene_fixture(project)

      changeset = Editor.change_scene(scene, %{name: "New Name"})
      assert changeset.changes.name == "New Name"
    end
  end

  # =============================================================================
  # Scene.deleted?/1
  # =============================================================================

  describe "Scene.deleted?/1" do
    alias Storyarn.Scenes.Scene

    test "returns false for a scene that is not soft-deleted" do
      %{project: project} = create_project()
      scene = scene_fixture(project)

      refute Scene.deleted?(scene)
    end

    test "returns true for a scene that has been soft-deleted" do
      %{project: project} = create_project()
      scene = scene_fixture(project)

      {:ok, deleted_scene} = Scenes.delete_scene(scene)
      assert Scene.deleted?(deleted_scene)
    end
  end
end
