defmodule Storyarn.Scenes.TreeOperationsTest do
  use Storyarn.DataCase, async: true

  alias Storyarn.Scenes.TreeOperations

  import Storyarn.AccountsFixtures
  import Storyarn.ScenesFixtures
  import Storyarn.ProjectsFixtures

  defp create_project(_context \\ %{}) do
    user = user_fixture()
    project = project_fixture(user)
    %{user: user, project: project}
  end

  # =============================================================================
  # reorder_scenes/3
  # =============================================================================

  describe "reorder_scenes/3" do
    test "reorders scenes at root level" do
      %{project: project} = create_project()
      scene_a = scene_fixture(project, %{name: "Alpha"})
      scene_b = scene_fixture(project, %{name: "Bravo"})
      scene_c = scene_fixture(project, %{name: "Charlie"})

      # Reverse the order
      {:ok, reordered} =
        TreeOperations.reorder_scenes(project.id, nil, [scene_c.id, scene_b.id, scene_a.id])

      positions = Enum.map(reordered, &{&1.name, &1.position})
      assert positions == [{"Charlie", 0}, {"Bravo", 1}, {"Alpha", 2}]
    end

    test "reorders scenes within a parent" do
      %{project: project} = create_project()
      parent = scene_fixture(project, %{name: "Parent"})
      child_a = scene_fixture(project, %{name: "Child A", parent_id: parent.id})
      child_b = scene_fixture(project, %{name: "Child B", parent_id: parent.id})

      {:ok, reordered} =
        TreeOperations.reorder_scenes(project.id, parent.id, [child_b.id, child_a.id])

      positions = Enum.map(reordered, &{&1.name, &1.position})
      assert positions == [{"Child B", 0}, {"Child A", 1}]
    end
  end

  # =============================================================================
  # move_scene_to_position/3
  # =============================================================================

  describe "move_scene_to_position/3" do
    test "moves scene to a different parent" do
      %{project: project} = create_project()
      parent_a = scene_fixture(project, %{name: "Parent A"})
      parent_b = scene_fixture(project, %{name: "Parent B"})
      child = scene_fixture(project, %{name: "Child", parent_id: parent_a.id})

      {:ok, moved} = TreeOperations.move_scene_to_position(child, parent_b.id, 0)
      assert moved.parent_id == parent_b.id
    end

    test "moves scene to root level" do
      %{project: project} = create_project()
      parent = scene_fixture(project, %{name: "Parent"})
      child = scene_fixture(project, %{name: "Child", parent_id: parent.id})

      {:ok, moved} = TreeOperations.move_scene_to_position(child, nil, 0)
      assert moved.parent_id == nil
    end

    test "prevents cyclic parent assignment" do
      %{project: project} = create_project()
      parent = scene_fixture(project, %{name: "Parent"})
      child = scene_fixture(project, %{name: "Child", parent_id: parent.id})

      # Try to move parent under its own child
      assert {:error, :cyclic_parent} =
               TreeOperations.move_scene_to_position(parent, child.id, 0)
    end
  end

  # =============================================================================
  # next_position/2
  # =============================================================================

  describe "next_position/2" do
    test "returns 0 when no scenes exist" do
      %{project: project} = create_project()
      assert TreeOperations.next_position(project.id, nil) == 0
    end

    test "returns next position after existing scenes" do
      %{project: project} = create_project()
      _scene = scene_fixture(project, %{name: "First"})

      assert TreeOperations.next_position(project.id, nil) >= 1
    end
  end

  # =============================================================================
  # list_scenes_by_parent/2
  # =============================================================================

  describe "list_scenes_by_parent/2" do
    test "lists root-level scenes" do
      %{project: project} = create_project()
      scene = scene_fixture(project, %{name: "Root Scene"})

      scenes = TreeOperations.list_scenes_by_parent(project.id, nil)
      assert Enum.any?(scenes, &(&1.id == scene.id))
    end

    test "lists child scenes" do
      %{project: project} = create_project()
      parent = scene_fixture(project, %{name: "Parent"})
      child = scene_fixture(project, %{name: "Child", parent_id: parent.id})

      children = TreeOperations.list_scenes_by_parent(project.id, parent.id)
      assert length(children) == 1
      assert hd(children).id == child.id
    end

    test "excludes soft-deleted scenes" do
      %{project: project} = create_project()
      _active = scene_fixture(project, %{name: "Active"})
      deleted = scene_fixture(project, %{name: "Deleted"})

      Storyarn.Scenes.delete_scene(deleted)

      scenes = TreeOperations.list_scenes_by_parent(project.id, nil)
      refute Enum.any?(scenes, &(&1.id == deleted.id))
    end
  end
end
