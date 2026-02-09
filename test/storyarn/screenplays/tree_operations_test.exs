defmodule Storyarn.Screenplays.TreeOperationsTest do
  use Storyarn.DataCase

  alias Storyarn.Screenplays.TreeOperations

  import Storyarn.AccountsFixtures
  import Storyarn.ProjectsFixtures
  import Storyarn.ScreenplaysFixtures

  defp setup_project(_context) do
    user = user_fixture()
    project = project_fixture(user)
    %{project: project}
  end

  describe "reorder_screenplays/3" do
    setup :setup_project

    test "updates positions by ID order", %{project: project} do
      s1 = screenplay_fixture(project, %{name: "A", position: 0})
      s2 = screenplay_fixture(project, %{name: "B", position: 1})
      s3 = screenplay_fixture(project, %{name: "C", position: 2})

      {:ok, result} =
        TreeOperations.reorder_screenplays(project.id, nil, [s3.id, s1.id, s2.id])

      ids = Enum.map(result, & &1.id)
      positions = Enum.map(result, & &1.position)

      assert ids == [s3.id, s1.id, s2.id]
      assert positions == [0, 1, 2]
    end
  end

  describe "move_screenplay_to_position/3" do
    setup :setup_project

    test "moves to a new parent", %{project: project} do
      parent = screenplay_fixture(project, %{name: "Parent"})
      child = screenplay_fixture(project, %{name: "Child"})

      {:ok, moved} = TreeOperations.move_screenplay_to_position(child, parent.id, 0)

      assert moved.parent_id == parent.id
      assert moved.position == 0
    end

    test "moves to root (parent_id = nil)", %{project: project} do
      parent = screenplay_fixture(project, %{name: "Parent"})
      child = screenplay_fixture(project, %{name: "Child", parent_id: parent.id})

      {:ok, moved} = TreeOperations.move_screenplay_to_position(child, nil, 0)

      assert moved.parent_id == nil
    end
  end
end
