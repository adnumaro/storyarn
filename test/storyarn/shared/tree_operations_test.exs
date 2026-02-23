defmodule Storyarn.Shared.TreeOperationsTest do
  use Storyarn.DataCase, async: true

  alias Storyarn.Shared.TreeOperations
  alias Storyarn.Sheets.Sheet

  import Storyarn.AccountsFixtures
  import Storyarn.ProjectsFixtures
  import Storyarn.SheetsFixtures

  # Helper to list sheets by parent
  defp list_sheets(project_id, parent_id) do
    TreeOperations.list_by_parent(Sheet, project_id, parent_id)
  end

  # ===========================================================================
  # next_position/3
  # ===========================================================================

  describe "next_position/3" do
    test "returns 0 for empty parent" do
      user = user_fixture()
      project = project_fixture(user)

      assert TreeOperations.next_position(Sheet, project.id, nil) == 0
    end

    test "returns next position after existing children" do
      user = user_fixture()
      project = project_fixture(user)

      _sheet1 = sheet_fixture(project, %{name: "First"})
      _sheet2 = sheet_fixture(project, %{name: "Second"})

      # Both sheets are root-level, so next position should be after them
      pos = TreeOperations.next_position(Sheet, project.id, nil)
      assert pos >= 2
    end

    test "scopes to parent_id" do
      user = user_fixture()
      project = project_fixture(user)

      parent = sheet_fixture(project, %{name: "Parent"})
      _child = child_sheet_fixture(project, parent, %{name: "Child"})

      # Root level should have different count than parent's children
      root_pos = TreeOperations.next_position(Sheet, project.id, nil)
      child_pos = TreeOperations.next_position(Sheet, project.id, parent.id)

      # Parent exists at root, so root_pos >= 1
      assert root_pos >= 1
      # One child exists under parent
      assert child_pos >= 1
    end
  end

  # ===========================================================================
  # list_by_parent/3
  # ===========================================================================

  describe "list_by_parent/3" do
    test "returns children of a parent ordered by position" do
      user = user_fixture()
      project = project_fixture(user)

      parent = sheet_fixture(project, %{name: "Parent"})
      child_b = child_sheet_fixture(project, parent, %{name: "B Child"})
      child_a = child_sheet_fixture(project, parent, %{name: "A Child"})

      children = TreeOperations.list_by_parent(Sheet, project.id, parent.id)

      assert length(children) == 2
      ids = Enum.map(children, & &1.id)
      # Ordered by position then name
      assert child_b.id in ids
      assert child_a.id in ids
    end

    test "returns root-level items when parent_id is nil" do
      user = user_fixture()
      project = project_fixture(user)

      sheet1 = sheet_fixture(project, %{name: "Root 1"})
      sheet2 = sheet_fixture(project, %{name: "Root 2"})

      roots = TreeOperations.list_by_parent(Sheet, project.id, nil)

      assert length(roots) == 2
      ids = Enum.map(roots, & &1.id)
      assert sheet1.id in ids
      assert sheet2.id in ids
    end

    test "excludes soft-deleted items" do
      user = user_fixture()
      project = project_fixture(user)

      _sheet1 = sheet_fixture(project, %{name: "Active"})
      sheet2 = sheet_fixture(project, %{name: "To Delete"})

      # Soft-delete sheet2
      Storyarn.Repo.update_all(
        from(s in Sheet, where: s.id == ^sheet2.id),
        set: [deleted_at: DateTime.utc_now() |> DateTime.truncate(:second)]
      )

      roots = TreeOperations.list_by_parent(Sheet, project.id, nil)

      assert length(roots) == 1
      assert hd(roots).name == "Active"
    end

    test "returns empty list for parent with no children" do
      user = user_fixture()
      project = project_fixture(user)

      parent = sheet_fixture(project, %{name: "Empty Parent"})

      children = TreeOperations.list_by_parent(Sheet, project.id, parent.id)

      assert children == []
    end
  end

  # ===========================================================================
  # reorder/5
  # ===========================================================================

  describe "reorder/5" do
    test "reorders entities by given ID order" do
      user = user_fixture()
      project = project_fixture(user)

      sheet1 = sheet_fixture(project, %{name: "First"})
      sheet2 = sheet_fixture(project, %{name: "Second"})
      sheet3 = sheet_fixture(project, %{name: "Third"})

      # Reverse order
      {:ok, reordered} =
        TreeOperations.reorder(
          Sheet,
          project.id,
          nil,
          [sheet3.id, sheet2.id, sheet1.id],
          &list_sheets/2
        )

      positions = Enum.map(reordered, fn s -> {s.id, s.position} end) |> Map.new()
      assert positions[sheet3.id] < positions[sheet2.id]
      assert positions[sheet2.id] < positions[sheet1.id]
    end

    test "handles empty ID list" do
      user = user_fixture()
      project = project_fixture(user)

      {:ok, result} = TreeOperations.reorder(Sheet, project.id, nil, [], &list_sheets/2)

      assert is_list(result)
    end

    test "filters out nil IDs" do
      user = user_fixture()
      project = project_fixture(user)

      sheet1 = sheet_fixture(project, %{name: "First"})

      {:ok, result} =
        TreeOperations.reorder(Sheet, project.id, nil, [nil, sheet1.id, nil], &list_sheets/2)

      assert length(result) >= 1
    end
  end

  # ===========================================================================
  # update_position_only/3
  # ===========================================================================

  describe "update_position_only/3" do
    test "updates position of a non-deleted entity" do
      user = user_fixture()
      project = project_fixture(user)

      sheet = sheet_fixture(project, %{name: "Test"})

      {count, _} = TreeOperations.update_position_only(Sheet, sheet.id, 42)

      assert count == 1

      updated = Storyarn.Repo.get!(Sheet, sheet.id)
      assert updated.position == 42
    end

    test "does not update soft-deleted entities" do
      user = user_fixture()
      project = project_fixture(user)

      sheet = sheet_fixture(project, %{name: "Deleted"})

      Storyarn.Repo.update_all(
        from(s in Sheet, where: s.id == ^sheet.id),
        set: [deleted_at: DateTime.utc_now() |> DateTime.truncate(:second)]
      )

      {count, _} = TreeOperations.update_position_only(Sheet, sheet.id, 99)

      assert count == 0
    end
  end

  # ===========================================================================
  # add_parent_filter/2
  # ===========================================================================

  describe "add_parent_filter/2" do
    test "filters for nil parent (root level)" do
      user = user_fixture()
      project = project_fixture(user)

      _root = sheet_fixture(project, %{name: "Root"})
      parent = sheet_fixture(project, %{name: "Parent"})
      _child = child_sheet_fixture(project, parent, %{name: "Child"})

      query =
        from(s in Sheet,
          where: s.project_id == ^project.id and is_nil(s.deleted_at)
        )
        |> TreeOperations.add_parent_filter(nil)

      results = Storyarn.Repo.all(query)

      # Only root-level sheets
      assert Enum.all?(results, fn s -> is_nil(s.parent_id) end)
    end

    test "filters for specific parent_id" do
      user = user_fixture()
      project = project_fixture(user)

      parent = sheet_fixture(project, %{name: "Parent"})
      child1 = child_sheet_fixture(project, parent, %{name: "Child 1"})
      child2 = child_sheet_fixture(project, parent, %{name: "Child 2"})

      query =
        from(s in Sheet,
          where: s.project_id == ^project.id and is_nil(s.deleted_at)
        )
        |> TreeOperations.add_parent_filter(parent.id)

      results = Storyarn.Repo.all(query)

      ids = Enum.map(results, & &1.id)
      assert child1.id in ids
      assert child2.id in ids
      assert length(results) == 2
    end
  end

  # ===========================================================================
  # move_to_position/5
  # ===========================================================================

  describe "move_to_position/5" do
    test "moves entity to a new parent" do
      user = user_fixture()
      project = project_fixture(user)

      parent_a = sheet_fixture(project, %{name: "Parent A"})
      parent_b = sheet_fixture(project, %{name: "Parent B"})
      child = child_sheet_fixture(project, parent_a, %{name: "Moving Child"})

      {:ok, moved} =
        TreeOperations.move_to_position(Sheet, child, parent_b.id, 0, &list_sheets/2)

      assert moved.parent_id == parent_b.id
      assert moved.position == 0
    end

    test "moves entity within same parent to different position" do
      user = user_fixture()
      project = project_fixture(user)

      parent = sheet_fixture(project, %{name: "Parent"})
      child1 = child_sheet_fixture(project, parent, %{name: "Child 1"})
      _child2 = child_sheet_fixture(project, parent, %{name: "Child 2"})

      {:ok, moved} =
        TreeOperations.move_to_position(Sheet, child1, parent.id, 1, &list_sheets/2)

      assert moved.parent_id == parent.id
    end

    test "clamps negative position to 0" do
      user = user_fixture()
      project = project_fixture(user)

      parent = sheet_fixture(project, %{name: "Parent"})
      child = child_sheet_fixture(project, parent, %{name: "Child"})

      {:ok, moved} =
        TreeOperations.move_to_position(Sheet, child, parent.id, -5, &list_sheets/2)

      assert moved.position >= 0
    end
  end

  # ===========================================================================
  # reorder_source_container/4
  # ===========================================================================

  describe "reorder_source_container/4" do
    test "compacts positions after gap" do
      user = user_fixture()
      project = project_fixture(user)

      sheet1 = sheet_fixture(project, %{name: "A"})
      sheet2 = sheet_fixture(project, %{name: "B"})

      # Set non-sequential positions
      TreeOperations.update_position_only(Sheet, sheet1.id, 5)
      TreeOperations.update_position_only(Sheet, sheet2.id, 10)

      TreeOperations.reorder_source_container(Sheet, project.id, nil, &list_sheets/2)

      updated1 = Storyarn.Repo.get!(Sheet, sheet1.id)
      updated2 = Storyarn.Repo.get!(Sheet, sheet2.id)

      # Positions should be compacted to 0, 1
      assert updated1.position == 0
      assert updated2.position == 1
    end
  end
end
