defmodule Storyarn.Shared.SoftDeleteTest do
  use Storyarn.DataCase, async: true

  alias Storyarn.Shared.SoftDelete
  alias Storyarn.Sheets.Sheet

  import Storyarn.AccountsFixtures
  import Storyarn.ProjectsFixtures
  import Storyarn.SheetsFixtures

  # ===========================================================================
  # soft_delete_children/3-4
  # ===========================================================================

  describe "soft_delete_children/3" do
    test "soft-deletes direct children of a parent" do
      user = user_fixture()
      project = project_fixture(user)

      parent = sheet_fixture(project, %{name: "Parent"})
      child1 = child_sheet_fixture(project, parent, %{name: "Child 1"})
      child2 = child_sheet_fixture(project, parent, %{name: "Child 2"})

      SoftDelete.soft_delete_children(Sheet, project.id, parent.id)

      updated1 = Storyarn.Repo.get!(Sheet, child1.id)
      updated2 = Storyarn.Repo.get!(Sheet, child2.id)

      assert updated1.deleted_at != nil
      assert updated2.deleted_at != nil
    end

    test "recursively soft-deletes grandchildren" do
      user = user_fixture()
      project = project_fixture(user)

      parent = sheet_fixture(project, %{name: "Parent"})
      child = child_sheet_fixture(project, parent, %{name: "Child"})
      grandchild = child_sheet_fixture(project, child, %{name: "Grandchild"})

      SoftDelete.soft_delete_children(Sheet, project.id, parent.id)

      updated_child = Storyarn.Repo.get!(Sheet, child.id)
      updated_grandchild = Storyarn.Repo.get!(Sheet, grandchild.id)

      assert updated_child.deleted_at != nil
      assert updated_grandchild.deleted_at != nil
    end

    test "does not affect the parent itself" do
      user = user_fixture()
      project = project_fixture(user)

      parent = sheet_fixture(project, %{name: "Parent"})
      _child = child_sheet_fixture(project, parent, %{name: "Child"})

      SoftDelete.soft_delete_children(Sheet, project.id, parent.id)

      updated_parent = Storyarn.Repo.get!(Sheet, parent.id)
      assert is_nil(updated_parent.deleted_at)
    end

    test "does not affect already soft-deleted children" do
      user = user_fixture()
      project = project_fixture(user)

      parent = sheet_fixture(project, %{name: "Parent"})
      child = child_sheet_fixture(project, parent, %{name: "Child"})

      # Already soft-deleted
      now = Storyarn.Shared.TimeHelpers.now()

      Storyarn.Repo.update_all(
        from(s in Sheet, where: s.id == ^child.id),
        set: [deleted_at: now]
      )

      # Should not error when no non-deleted children exist
      SoftDelete.soft_delete_children(Sheet, project.id, parent.id)

      updated = Storyarn.Repo.get!(Sheet, child.id)
      # Should keep the original deleted_at timestamp
      assert updated.deleted_at != nil
    end

    test "handles parent with no children" do
      user = user_fixture()
      project = project_fixture(user)

      parent = sheet_fixture(project, %{name: "Lonely Parent"})

      # Should not error
      SoftDelete.soft_delete_children(Sheet, project.id, parent.id)
    end

    test "does not affect entities from other projects" do
      user = user_fixture()
      project1 = project_fixture(user)
      project2 = project_fixture(user)

      parent1 = sheet_fixture(project1, %{name: "Parent 1"})
      _child1 = child_sheet_fixture(project1, parent1, %{name: "Child 1"})

      sheet2 = sheet_fixture(project2, %{name: "Sheet 2"})

      SoftDelete.soft_delete_children(Sheet, project1.id, parent1.id)

      updated2 = Storyarn.Repo.get!(Sheet, sheet2.id)
      assert is_nil(updated2.deleted_at)
    end
  end

  describe "soft_delete_children/4 with pre_delete callback" do
    test "calls pre_delete for each child before soft-deleting" do
      user = user_fixture()
      project = project_fixture(user)

      parent = sheet_fixture(project, %{name: "Parent"})
      child1 = child_sheet_fixture(project, parent, %{name: "Child 1"})
      child2 = child_sheet_fixture(project, parent, %{name: "Child 2"})

      # Track which children the callback was called for
      test_pid = self()

      pre_delete_fn = fn child ->
        send(test_pid, {:pre_delete_called, child.id})
      end

      SoftDelete.soft_delete_children(Sheet, project.id, parent.id, pre_delete: pre_delete_fn)

      assert_received {:pre_delete_called, id1}
      assert_received {:pre_delete_called, id2}

      called_ids = MapSet.new([id1, id2])
      assert MapSet.member?(called_ids, child1.id)
      assert MapSet.member?(called_ids, child2.id)
    end

    test "calls pre_delete for grandchildren too" do
      user = user_fixture()
      project = project_fixture(user)

      parent = sheet_fixture(project, %{name: "Parent"})
      child = child_sheet_fixture(project, parent, %{name: "Child"})
      grandchild = child_sheet_fixture(project, child, %{name: "Grandchild"})

      test_pid = self()

      pre_delete_fn = fn entity ->
        send(test_pid, {:pre_delete_called, entity.id})
      end

      SoftDelete.soft_delete_children(Sheet, project.id, parent.id, pre_delete: pre_delete_fn)

      assert_received {:pre_delete_called, child_id}
      assert_received {:pre_delete_called, grandchild_id}

      assert child_id == child.id
      assert grandchild_id == grandchild.id
    end
  end

  # ===========================================================================
  # list_deleted/2
  # ===========================================================================

  describe "list_deleted/2" do
    test "returns soft-deleted entities" do
      user = user_fixture()
      project = project_fixture(user)

      _active = sheet_fixture(project, %{name: "Active"})
      deleted = sheet_fixture(project, %{name: "Deleted"})

      now = Storyarn.Shared.TimeHelpers.now()

      Storyarn.Repo.update_all(
        from(s in Sheet, where: s.id == ^deleted.id),
        set: [deleted_at: now]
      )

      result = SoftDelete.list_deleted(Sheet, project.id)

      assert length(result) == 1
      assert hd(result).id == deleted.id
    end

    test "returns empty list when no deleted entities" do
      user = user_fixture()
      project = project_fixture(user)

      _active = sheet_fixture(project, %{name: "Active"})

      result = SoftDelete.list_deleted(Sheet, project.id)

      assert result == []
    end

    test "orders by deletion time, most recent first" do
      user = user_fixture()
      project = project_fixture(user)

      sheet1 = sheet_fixture(project, %{name: "First Deleted"})
      sheet2 = sheet_fixture(project, %{name: "Second Deleted"})

      early = DateTime.add(DateTime.utc_now(), -3600, :second) |> DateTime.truncate(:second)
      late = Storyarn.Shared.TimeHelpers.now()

      Storyarn.Repo.update_all(
        from(s in Sheet, where: s.id == ^sheet1.id),
        set: [deleted_at: early]
      )

      Storyarn.Repo.update_all(
        from(s in Sheet, where: s.id == ^sheet2.id),
        set: [deleted_at: late]
      )

      result = SoftDelete.list_deleted(Sheet, project.id)

      assert length(result) == 2
      # Most recent first
      assert hd(result).id == sheet2.id
      assert List.last(result).id == sheet1.id
    end

    test "scopes to project" do
      user = user_fixture()
      project1 = project_fixture(user)
      project2 = project_fixture(user)

      sheet1 = sheet_fixture(project1, %{name: "P1 Deleted"})
      sheet2 = sheet_fixture(project2, %{name: "P2 Deleted"})

      now = Storyarn.Shared.TimeHelpers.now()

      Storyarn.Repo.update_all(
        from(s in Sheet, where: s.id in ^[sheet1.id, sheet2.id]),
        set: [deleted_at: now]
      )

      result1 = SoftDelete.list_deleted(Sheet, project1.id)
      result2 = SoftDelete.list_deleted(Sheet, project2.id)

      assert length(result1) == 1
      assert hd(result1).id == sheet1.id
      assert length(result2) == 1
      assert hd(result2).id == sheet2.id
    end
  end
end
