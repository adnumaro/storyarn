defmodule Storyarn.Screenplays.ScreenplayCrudTest do
  use Storyarn.DataCase, async: true

  alias Storyarn.Screenplays.{Screenplay, ScreenplayCrud}

  import Storyarn.AccountsFixtures
  import Storyarn.ProjectsFixtures
  import Storyarn.ScreenplaysFixtures

  defp setup_project(_context) do
    user = user_fixture()
    project = project_fixture(user)
    %{user: user, project: project}
  end

  # ===========================================================================
  # create_screenplay/2
  # ===========================================================================

  describe "create_screenplay/2" do
    setup :setup_project

    test "creates with valid attrs", %{project: project} do
      {:ok, screenplay} =
        ScreenplayCrud.create_screenplay(project, %{name: "Act 1", description: "The beginning"})

      assert screenplay.name == "Act 1"
      assert screenplay.description == "The beginning"
      assert screenplay.project_id == project.id
    end

    test "auto-generates shortcut from name", %{project: project} do
      {:ok, screenplay} = ScreenplayCrud.create_screenplay(project, %{name: "Tavern Scene"})
      assert screenplay.shortcut == "tavern-scene"
    end

    test "does not overwrite explicit shortcut", %{project: project} do
      {:ok, screenplay} =
        ScreenplayCrud.create_screenplay(project, %{name: "Tavern Scene", shortcut: "custom"})

      assert screenplay.shortcut == "custom"
    end

    test "auto-assigns position", %{project: project} do
      {:ok, s1} = ScreenplayCrud.create_screenplay(project, %{name: "First"})
      {:ok, s2} = ScreenplayCrud.create_screenplay(project, %{name: "Second"})

      assert s1.position == 0
      assert s2.position == 1
    end

    test "auto-assigns position within a parent", %{project: project} do
      {:ok, parent} = ScreenplayCrud.create_screenplay(project, %{name: "Parent"})

      {:ok, c1} =
        ScreenplayCrud.create_screenplay(project, %{name: "Child 1", parent_id: parent.id})

      {:ok, c2} =
        ScreenplayCrud.create_screenplay(project, %{name: "Child 2", parent_id: parent.id})

      assert c1.position == 0
      assert c2.position == 1
    end

    test "fails without name", %{project: project} do
      {:error, changeset} = ScreenplayCrud.create_screenplay(project, %{})
      assert "can't be blank" in errors_on(changeset).name
    end

    test "fails with empty name", %{project: project} do
      {:error, changeset} = ScreenplayCrud.create_screenplay(project, %{name: ""})
      assert "can't be blank" in errors_on(changeset).name
    end

    test "fails with name exceeding 200 chars", %{project: project} do
      long_name = String.duplicate("x", 201)
      {:error, changeset} = ScreenplayCrud.create_screenplay(project, %{name: long_name})
      assert "should be at most 200 character(s)" in errors_on(changeset).name
    end

    test "accepts atom key attrs", %{project: project} do
      {:ok, screenplay} =
        ScreenplayCrud.create_screenplay(project, %{name: "Atom Keys", description: "desc"})

      assert screenplay.name == "Atom Keys"
      assert screenplay.description == "desc"
    end

    test "accepts string key attrs", %{project: project} do
      {:ok, screenplay} =
        ScreenplayCrud.create_screenplay(project, %{
          "name" => "String Keys",
          "description" => "desc"
        })

      assert screenplay.name == "String Keys"
    end

    test "fails with description exceeding 2000 chars", %{project: project} do
      long_desc = String.duplicate("x", 2001)

      {:error, changeset} =
        ScreenplayCrud.create_screenplay(project, %{name: "X", description: long_desc})

      assert "should be at most 2000 character(s)" in errors_on(changeset).description
    end
  end

  # ===========================================================================
  # list_screenplays/1
  # ===========================================================================

  describe "list_screenplays/1" do
    setup :setup_project

    test "returns non-deleted, non-draft screenplays", %{project: project} do
      s1 = screenplay_fixture(project, %{name: "Active"})
      s2 = screenplay_fixture(project, %{name: "Also Active"})
      s3 = screenplay_fixture(project, %{name: "Will Delete"})
      {:ok, _} = ScreenplayCrud.delete_screenplay(s3)

      result = ScreenplayCrud.list_screenplays(project.id)
      ids = Enum.map(result, & &1.id)

      assert s1.id in ids
      assert s2.id in ids
      refute s3.id in ids
    end

    test "excludes drafts", %{project: project} do
      original = screenplay_fixture(project, %{name: "Original"})

      {:ok, _draft} =
        %Screenplay{project_id: project.id, draft_of_id: original.id}
        |> Screenplay.create_changeset(%{name: "Draft"})
        |> Repo.insert()

      result = ScreenplayCrud.list_screenplays(project.id)
      names = Enum.map(result, & &1.name)

      assert original.name in names
      refute "Draft" in names
    end

    test "returns empty list for project with no screenplays", %{project: project} do
      assert ScreenplayCrud.list_screenplays(project.id) == []
    end

    test "orders by position then name", %{project: project} do
      _s_b = screenplay_fixture(project, %{name: "B", position: 1})
      _s_a = screenplay_fixture(project, %{name: "A", position: 0})
      _s_c = screenplay_fixture(project, %{name: "C", position: 1})

      result = ScreenplayCrud.list_screenplays(project.id)
      names = Enum.map(result, & &1.name)

      # position 0 first, then position 1 sorted by name
      assert names == ["A", "B", "C"]
    end
  end

  # ===========================================================================
  # list_screenplays_tree/1
  # ===========================================================================

  describe "list_screenplays_tree/1" do
    setup :setup_project

    test "returns root-level screenplays with children", %{project: project} do
      {:ok, parent} = ScreenplayCrud.create_screenplay(project, %{name: "Root"})

      {:ok, _child} =
        ScreenplayCrud.create_screenplay(project, %{name: "Child", parent_id: parent.id})

      tree = ScreenplayCrud.list_screenplays_tree(project.id)

      assert length(tree) == 1
      root = hd(tree)
      assert root.name == "Root"
      assert length(root.children) == 1
      assert hd(root.children).name == "Child"
    end

    test "returns nested tree structure", %{project: project} do
      {:ok, root} = ScreenplayCrud.create_screenplay(project, %{name: "Root"})

      {:ok, child} =
        ScreenplayCrud.create_screenplay(project, %{name: "Child", parent_id: root.id})

      {:ok, _grandchild} =
        ScreenplayCrud.create_screenplay(project, %{name: "Grandchild", parent_id: child.id})

      tree = ScreenplayCrud.list_screenplays_tree(project.id)

      assert length(tree) == 1
      root_node = hd(tree)
      assert length(root_node.children) == 1
      child_node = hd(root_node.children)
      assert length(child_node.children) == 1
      assert hd(child_node.children).name == "Grandchild"
    end

    test "excludes deleted screenplays from tree", %{project: project} do
      {:ok, active} = ScreenplayCrud.create_screenplay(project, %{name: "Active"})
      {:ok, deleted} = ScreenplayCrud.create_screenplay(project, %{name: "Deleted"})
      {:ok, _} = ScreenplayCrud.delete_screenplay(deleted)

      tree = ScreenplayCrud.list_screenplays_tree(project.id)
      ids = Enum.map(tree, & &1.id)

      assert active.id in ids
      refute deleted.id in ids
    end

    test "excludes drafts from tree", %{project: project} do
      original = screenplay_fixture(project, %{name: "Original"})

      {:ok, _draft} =
        %Screenplay{project_id: project.id, draft_of_id: original.id}
        |> Screenplay.create_changeset(%{name: "Draft"})
        |> Repo.insert()

      tree = ScreenplayCrud.list_screenplays_tree(project.id)
      names = tree |> Enum.map(& &1.name)

      assert "Original" in names
      refute "Draft" in names
    end

    test "returns empty list for empty project", %{project: project} do
      assert ScreenplayCrud.list_screenplays_tree(project.id) == []
    end

    test "multiple roots with children", %{project: project} do
      {:ok, r1} = ScreenplayCrud.create_screenplay(project, %{name: "Root 1"})
      {:ok, r2} = ScreenplayCrud.create_screenplay(project, %{name: "Root 2"})

      {:ok, _c1} =
        ScreenplayCrud.create_screenplay(project, %{name: "Child of R1", parent_id: r1.id})

      {:ok, _c2} =
        ScreenplayCrud.create_screenplay(project, %{name: "Child of R2", parent_id: r2.id})

      tree = ScreenplayCrud.list_screenplays_tree(project.id)

      assert length(tree) == 2
      root1 = Enum.find(tree, &(&1.id == r1.id))
      root2 = Enum.find(tree, &(&1.id == r2.id))
      assert length(root1.children) == 1
      assert length(root2.children) == 1
    end
  end

  # ===========================================================================
  # get_screenplay/2
  # ===========================================================================

  describe "get_screenplay/2" do
    setup :setup_project

    test "returns screenplay with elements preloaded", %{project: project} do
      screenplay = screenplay_fixture(project, %{name: "Test"})
      _el = element_fixture(screenplay, %{type: "scene_heading", content: "INT. TAVERN"})

      result = ScreenplayCrud.get_screenplay(project.id, screenplay.id)

      assert result.id == screenplay.id
      assert length(result.elements) == 1
      assert hd(result.elements).content == "INT. TAVERN"
    end

    test "returns nil for deleted screenplay", %{project: project} do
      screenplay = screenplay_fixture(project)
      {:ok, _} = ScreenplayCrud.delete_screenplay(screenplay)

      assert ScreenplayCrud.get_screenplay(project.id, screenplay.id) == nil
    end

    test "returns nil for non-existent id", %{project: project} do
      assert ScreenplayCrud.get_screenplay(project.id, -1) == nil
    end

    test "returns nil for draft screenplay", %{project: project} do
      original = screenplay_fixture(project)

      {:ok, draft} =
        %Screenplay{project_id: project.id, draft_of_id: original.id}
        |> Screenplay.create_changeset(%{name: "Draft"})
        |> Repo.insert()

      assert ScreenplayCrud.get_screenplay(project.id, draft.id) == nil
    end

    test "returns nil for screenplay from different project", %{project: project} do
      other_user = user_fixture()
      other_project = project_fixture(other_user)
      screenplay = screenplay_fixture(other_project)

      assert ScreenplayCrud.get_screenplay(project.id, screenplay.id) == nil
    end

    test "elements are ordered by position", %{project: project} do
      screenplay = screenplay_fixture(project)
      _el2 = element_fixture(screenplay, %{type: "action", content: "Second", position: 2})
      _el0 = element_fixture(screenplay, %{type: "scene_heading", content: "First", position: 0})
      _el1 = element_fixture(screenplay, %{type: "character", content: "Middle", position: 1})

      result = ScreenplayCrud.get_screenplay(project.id, screenplay.id)
      positions = Enum.map(result.elements, & &1.position)

      assert positions == [0, 1, 2]
    end
  end

  # ===========================================================================
  # get_screenplay!/2
  # ===========================================================================

  describe "get_screenplay!/2" do
    setup :setup_project

    test "returns screenplay", %{project: project} do
      screenplay = screenplay_fixture(project)
      result = ScreenplayCrud.get_screenplay!(project.id, screenplay.id)
      assert result.id == screenplay.id
    end

    test "raises for deleted screenplay", %{project: project} do
      screenplay = screenplay_fixture(project)
      {:ok, _} = ScreenplayCrud.delete_screenplay(screenplay)

      assert_raise Ecto.NoResultsError, fn ->
        ScreenplayCrud.get_screenplay!(project.id, screenplay.id)
      end
    end

    test "raises for non-existent id", %{project: project} do
      assert_raise Ecto.NoResultsError, fn ->
        ScreenplayCrud.get_screenplay!(project.id, -1)
      end
    end

    test "raises for draft screenplay", %{project: project} do
      original = screenplay_fixture(project)

      {:ok, draft} =
        %Screenplay{project_id: project.id, draft_of_id: original.id}
        |> Screenplay.create_changeset(%{name: "Draft"})
        |> Repo.insert()

      assert_raise Ecto.NoResultsError, fn ->
        ScreenplayCrud.get_screenplay!(project.id, draft.id)
      end
    end
  end

  # ===========================================================================
  # update_screenplay/2
  # ===========================================================================

  describe "update_screenplay/2" do
    setup :setup_project

    test "updates name and description", %{project: project} do
      screenplay = screenplay_fixture(project)

      {:ok, updated} =
        ScreenplayCrud.update_screenplay(screenplay, %{name: "New Name", description: "New desc"})

      assert updated.name == "New Name"
      assert updated.description == "New desc"
    end

    test "regenerates shortcut when name changes", %{project: project} do
      screenplay = screenplay_fixture(project, %{name: "Old Name"})

      {:ok, updated} = ScreenplayCrud.update_screenplay(screenplay, %{name: "New Name"})
      assert updated.shortcut == "new-name"
    end

    test "does not regenerate shortcut when name stays the same", %{project: project} do
      {:ok, screenplay} =
        ScreenplayCrud.create_screenplay(project, %{name: "Stable", shortcut: "custom-sc"})

      {:ok, updated} =
        ScreenplayCrud.update_screenplay(screenplay, %{description: "Updated desc"})

      assert updated.shortcut == "custom-sc"
    end

    test "fails with empty name", %{project: project} do
      screenplay = screenplay_fixture(project)
      {:error, changeset} = ScreenplayCrud.update_screenplay(screenplay, %{name: ""})
      assert "can't be blank" in errors_on(changeset).name
    end

    test "fails with name exceeding 200 chars", %{project: project} do
      screenplay = screenplay_fixture(project)
      long_name = String.duplicate("x", 201)
      {:error, changeset} = ScreenplayCrud.update_screenplay(screenplay, %{name: long_name})
      assert "should be at most 200 character(s)" in errors_on(changeset).name
    end

    test "updates only description without touching name or shortcut", %{project: project} do
      {:ok, screenplay} =
        ScreenplayCrud.create_screenplay(project, %{name: "Original", shortcut: "original"})

      {:ok, updated} =
        ScreenplayCrud.update_screenplay(screenplay, %{description: "New description"})

      assert updated.name == "Original"
      assert updated.shortcut == "original"
      assert updated.description == "New description"
    end
  end

  # ===========================================================================
  # delete_screenplay/1
  # ===========================================================================

  describe "delete_screenplay/1" do
    setup :setup_project

    test "soft-deletes (sets deleted_at)", %{project: project} do
      screenplay = screenplay_fixture(project)

      {:ok, deleted} = ScreenplayCrud.delete_screenplay(screenplay)
      assert deleted.deleted_at != nil
    end

    test "recursively deletes children", %{project: project} do
      parent = screenplay_fixture(project, %{name: "Parent"})
      child = screenplay_fixture(project, %{name: "Child", parent_id: parent.id})

      {:ok, _} = ScreenplayCrud.delete_screenplay(parent)

      # Child should also be deleted
      assert ScreenplayCrud.get_screenplay(project.id, child.id) == nil
    end

    test "recursively deletes grandchildren", %{project: project} do
      parent = screenplay_fixture(project, %{name: "Parent"})
      child = screenplay_fixture(project, %{name: "Child", parent_id: parent.id})
      grandchild = screenplay_fixture(project, %{name: "Grandchild", parent_id: child.id})

      {:ok, _} = ScreenplayCrud.delete_screenplay(parent)

      assert ScreenplayCrud.get_screenplay(project.id, grandchild.id) == nil
    end

    test "deleted screenplay appears in list_deleted_screenplays", %{project: project} do
      screenplay = screenplay_fixture(project)
      {:ok, _} = ScreenplayCrud.delete_screenplay(screenplay)

      deleted = ScreenplayCrud.list_deleted_screenplays(project.id)
      assert Enum.any?(deleted, &(&1.id == screenplay.id))
    end
  end

  # ===========================================================================
  # restore_screenplay/1
  # ===========================================================================

  describe "restore_screenplay/1" do
    setup :setup_project

    test "clears deleted_at", %{project: project} do
      screenplay = screenplay_fixture(project)
      {:ok, deleted} = ScreenplayCrud.delete_screenplay(screenplay)

      {:ok, restored} = ScreenplayCrud.restore_screenplay(deleted)
      assert restored.deleted_at == nil
    end

    test "screenplay visible again after restore", %{project: project} do
      screenplay = screenplay_fixture(project)
      {:ok, deleted} = ScreenplayCrud.delete_screenplay(screenplay)
      {:ok, _restored} = ScreenplayCrud.restore_screenplay(deleted)

      assert ScreenplayCrud.get_screenplay(project.id, screenplay.id) != nil
    end
  end

  # ===========================================================================
  # change_screenplay/2
  # ===========================================================================

  describe "change_screenplay/2" do
    setup :setup_project

    test "returns a valid changeset with valid attrs", %{project: project} do
      screenplay = %Screenplay{project_id: project.id}
      changeset = ScreenplayCrud.change_screenplay(screenplay, %{name: "Act 1"})

      assert %Ecto.Changeset{} = changeset
      assert changeset.valid?
    end

    test "returns a changeset with errors for invalid attrs", %{project: project} do
      screenplay = %Screenplay{project_id: project.id}
      changeset = ScreenplayCrud.change_screenplay(screenplay, %{name: ""})

      assert %Ecto.Changeset{} = changeset
      refute changeset.valid?
      assert {"can't be blank", _} = changeset.errors[:name]
    end

    test "returns changeset with no attrs (default)", %{project: project} do
      screenplay = screenplay_fixture(project, %{name: "Existing"})
      changeset = ScreenplayCrud.change_screenplay(screenplay)

      assert %Ecto.Changeset{} = changeset
      assert changeset.valid?
    end
  end

  # ===========================================================================
  # screenplay_exists?/2
  # ===========================================================================

  describe "screenplay_exists?/2" do
    setup :setup_project

    test "returns true for existing screenplay", %{project: project} do
      screenplay = screenplay_fixture(project)
      assert ScreenplayCrud.screenplay_exists?(project.id, screenplay.id)
    end

    test "returns false for deleted screenplay", %{project: project} do
      screenplay = screenplay_fixture(project)
      {:ok, _} = ScreenplayCrud.delete_screenplay(screenplay)
      refute ScreenplayCrud.screenplay_exists?(project.id, screenplay.id)
    end

    test "returns false for non-existent id", %{project: project} do
      refute ScreenplayCrud.screenplay_exists?(project.id, -1)
    end

    test "returns false for draft screenplay", %{project: project} do
      original = screenplay_fixture(project)

      {:ok, draft} =
        %Screenplay{project_id: project.id, draft_of_id: original.id}
        |> Screenplay.create_changeset(%{name: "Draft"})
        |> Repo.insert()

      refute ScreenplayCrud.screenplay_exists?(project.id, draft.id)
    end

    test "returns false for screenplay from another project", %{project: project} do
      other_user = user_fixture()
      other_project = project_fixture(other_user)
      screenplay = screenplay_fixture(other_project)

      refute ScreenplayCrud.screenplay_exists?(project.id, screenplay.id)
    end
  end

  # ===========================================================================
  # list_deleted_screenplays/1
  # ===========================================================================

  describe "list_deleted_screenplays/1" do
    setup :setup_project

    test "returns only deleted screenplays", %{project: project} do
      active = screenplay_fixture(project, %{name: "Active"})
      deleted_sp = screenplay_fixture(project, %{name: "Deleted"})
      {:ok, _} = ScreenplayCrud.delete_screenplay(deleted_sp)

      result = ScreenplayCrud.list_deleted_screenplays(project.id)
      ids = Enum.map(result, & &1.id)

      assert deleted_sp.id in ids
      refute active.id in ids
    end

    test "returns empty list when no deleted screenplays", %{project: project} do
      _active = screenplay_fixture(project)
      assert ScreenplayCrud.list_deleted_screenplays(project.id) == []
    end
  end

  # ===========================================================================
  # list_screenplays_for_export/1
  # ===========================================================================

  describe "list_screenplays_for_export/1" do
    setup :setup_project

    test "returns screenplays with elements preloaded", %{project: project} do
      {:ok, sp} = ScreenplayCrud.create_screenplay(project, %{name: "Export Me"})
      element_fixture(sp, %{type: "scene_heading", content: "INT. ROOM"})
      element_fixture(sp, %{type: "action", content: "Walk in."})

      result = ScreenplayCrud.list_screenplays_for_export(project.id)

      assert length(result) == 1
      sp_result = hd(result)
      assert sp_result.name == "Export Me"
      assert length(sp_result.elements) == 2
    end

    test "excludes deleted screenplays", %{project: project} do
      {:ok, sp} = ScreenplayCrud.create_screenplay(project, %{name: "Active"})
      {:ok, deleted} = ScreenplayCrud.create_screenplay(project, %{name: "Deleted"})
      {:ok, _} = ScreenplayCrud.delete_screenplay(deleted)

      result = ScreenplayCrud.list_screenplays_for_export(project.id)
      ids = Enum.map(result, & &1.id)

      assert sp.id in ids
      refute deleted.id in ids
    end

    test "includes drafts (unlike list_screenplays)", %{project: project} do
      original = screenplay_fixture(project, %{name: "Original"})

      {:ok, draft} =
        %Screenplay{project_id: project.id, draft_of_id: original.id}
        |> Screenplay.create_changeset(%{name: "Draft"})
        |> Repo.insert()

      result = ScreenplayCrud.list_screenplays_for_export(project.id)
      ids = Enum.map(result, & &1.id)

      # export includes drafts (no draft_of_id filter)
      assert original.id in ids
      assert draft.id in ids
    end

    test "elements are ordered by position", %{project: project} do
      {:ok, sp} = ScreenplayCrud.create_screenplay(project, %{name: "Ordered"})
      element_fixture(sp, %{type: "action", content: "Second", position: 1})
      element_fixture(sp, %{type: "scene_heading", content: "First", position: 0})

      result = ScreenplayCrud.list_screenplays_for_export(project.id)
      sp_result = hd(result)
      positions = Enum.map(sp_result.elements, & &1.position)

      assert positions == [0, 1]
    end

    test "returns empty list for empty project", %{project: project} do
      assert ScreenplayCrud.list_screenplays_for_export(project.id) == []
    end
  end

  # ===========================================================================
  # count_screenplays/1
  # ===========================================================================

  describe "count_screenplays/1" do
    setup :setup_project

    test "counts non-deleted screenplays", %{project: project} do
      screenplay_fixture(project, %{name: "One"})
      screenplay_fixture(project, %{name: "Two"})
      s3 = screenplay_fixture(project, %{name: "Three"})
      {:ok, _} = ScreenplayCrud.delete_screenplay(s3)

      assert ScreenplayCrud.count_screenplays(project.id) == 2
    end

    test "returns 0 for empty project", %{project: project} do
      assert ScreenplayCrud.count_screenplays(project.id) == 0
    end

    test "includes drafts in count", %{project: project} do
      original = screenplay_fixture(project, %{name: "Original"})

      {:ok, _draft} =
        %Screenplay{project_id: project.id, draft_of_id: original.id}
        |> Screenplay.create_changeset(%{name: "Draft"})
        |> Repo.insert()

      # count_screenplays has no draft_of_id filter
      assert ScreenplayCrud.count_screenplays(project.id) == 2
    end
  end

  # ===========================================================================
  # list_shortcuts/1
  # ===========================================================================

  describe "list_shortcuts/1" do
    setup :setup_project

    test "returns MapSet of shortcuts", %{project: project} do
      {:ok, _} = ScreenplayCrud.create_screenplay(project, %{name: "Scene One"})
      {:ok, _} = ScreenplayCrud.create_screenplay(project, %{name: "Scene Two"})

      result = ScreenplayCrud.list_shortcuts(project.id)

      assert %MapSet{} = result
      assert MapSet.member?(result, "scene-one")
      assert MapSet.member?(result, "scene-two")
    end

    test "excludes deleted screenplay shortcuts", %{project: project} do
      {:ok, active} = ScreenplayCrud.create_screenplay(project, %{name: "Active"})
      {:ok, deleted} = ScreenplayCrud.create_screenplay(project, %{name: "Deleted"})
      {:ok, _} = ScreenplayCrud.delete_screenplay(deleted)

      result = ScreenplayCrud.list_shortcuts(project.id)

      assert MapSet.member?(result, active.shortcut)
      refute MapSet.member?(result, deleted.shortcut)
    end

    test "returns empty MapSet for empty project", %{project: project} do
      result = ScreenplayCrud.list_shortcuts(project.id)
      assert MapSet.size(result) == 0
    end
  end

  # ===========================================================================
  # detect_shortcut_conflicts/2
  # ===========================================================================

  describe "detect_shortcut_conflicts/2" do
    setup :setup_project

    test "returns conflicting shortcuts", %{project: project} do
      {:ok, _} = ScreenplayCrud.create_screenplay(project, %{name: "Existing"})

      result = ScreenplayCrud.detect_shortcut_conflicts(project.id, ["existing", "new-one"])

      assert "existing" in result
      refute "new-one" in result
    end

    test "returns empty list when no conflicts", %{project: project} do
      {:ok, _} = ScreenplayCrud.create_screenplay(project, %{name: "Existing"})

      assert ScreenplayCrud.detect_shortcut_conflicts(project.id, ["completely-new"]) == []
    end

    test "returns empty list for empty input", %{project: project} do
      assert ScreenplayCrud.detect_shortcut_conflicts(project.id, []) == []
    end

    test "excludes deleted screenplay shortcuts from conflicts", %{project: project} do
      {:ok, sp} = ScreenplayCrud.create_screenplay(project, %{name: "Deleted One"})
      {:ok, _} = ScreenplayCrud.delete_screenplay(sp)

      result = ScreenplayCrud.detect_shortcut_conflicts(project.id, ["deleted-one"])
      assert result == []
    end
  end

  # ===========================================================================
  # soft_delete_by_shortcut/2
  # ===========================================================================

  describe "soft_delete_by_shortcut/2" do
    setup :setup_project

    test "soft-deletes screenplays with matching shortcut", %{project: project} do
      {:ok, sp} = ScreenplayCrud.create_screenplay(project, %{name: "Target"})

      {count, _} = ScreenplayCrud.soft_delete_by_shortcut(project.id, sp.shortcut)

      assert count == 1
      assert ScreenplayCrud.get_screenplay(project.id, sp.id) == nil
    end

    test "does nothing for non-existent shortcut", %{project: project} do
      {count, _} = ScreenplayCrud.soft_delete_by_shortcut(project.id, "nonexistent")
      assert count == 0
    end

    test "does not affect screenplays in other projects", %{project: project} do
      other_user = user_fixture()
      other_project = project_fixture(other_user)
      {:ok, sp} = ScreenplayCrud.create_screenplay(other_project, %{name: "Other"})

      {count, _} = ScreenplayCrud.soft_delete_by_shortcut(project.id, sp.shortcut)
      assert count == 0

      # Still visible in other project
      assert ScreenplayCrud.get_screenplay(other_project.id, sp.id) != nil
    end

    test "skips already-deleted screenplays", %{project: project} do
      {:ok, sp} = ScreenplayCrud.create_screenplay(project, %{name: "Already Deleted"})
      {:ok, _} = ScreenplayCrud.delete_screenplay(sp)

      {count, _} = ScreenplayCrud.soft_delete_by_shortcut(project.id, sp.shortcut)
      assert count == 0
    end
  end

  # ===========================================================================
  # import_screenplay/3
  # ===========================================================================

  describe "import_screenplay/3" do
    setup :setup_project

    test "creates screenplay with raw attrs", %{project: project} do
      attrs = %{name: "Imported", shortcut: "imported", position: 5}

      {:ok, sp} = ScreenplayCrud.import_screenplay(project.id, attrs)

      assert sp.name == "Imported"
      assert sp.shortcut == "imported"
      assert sp.position == 5
      assert sp.project_id == project.id
    end

    test "applies extra_changes", %{project: project} do
      attrs = %{name: "With Extras", shortcut: "extras"}

      {:ok, sp} =
        ScreenplayCrud.import_screenplay(project.id, attrs, %{
          draft_label: "v2",
          draft_status: "draft"
        })

      assert sp.draft_label == "v2"
      assert sp.draft_status == "draft"
    end

    test "ignores nil values in extra_changes", %{project: project} do
      attrs = %{name: "No Nulls", shortcut: "no-nulls"}

      {:ok, sp} =
        ScreenplayCrud.import_screenplay(project.id, attrs, %{
          draft_label: nil,
          draft_status: "active"
        })

      assert sp.draft_label == nil
      assert sp.draft_status == "active"
    end

    test "fails with invalid attrs", %{project: project} do
      {:error, changeset} = ScreenplayCrud.import_screenplay(project.id, %{})
      assert "can't be blank" in errors_on(changeset).name
    end
  end

  # ===========================================================================
  # import_element/3
  # ===========================================================================

  describe "import_element/3" do
    setup :setup_project

    test "creates element with raw attrs", %{project: project} do
      {:ok, sp} = ScreenplayCrud.create_screenplay(project, %{name: "Host"})

      attrs = %{type: "action", content: "Walk in.", position: 0}
      {:ok, el} = ScreenplayCrud.import_element(sp.id, attrs)

      assert el.type == "action"
      assert el.content == "Walk in."
      assert el.position == 0
      assert el.screenplay_id == sp.id
    end

    test "applies extra_changes", %{project: project} do
      {:ok, sp} = ScreenplayCrud.create_screenplay(project, %{name: "Host"})

      attrs = %{type: "dialogue", content: "Hello", position: 0}

      {:ok, el} =
        ScreenplayCrud.import_element(sp.id, attrs, %{data: %{"some_key" => "some_value"}})

      assert el.data == %{"some_key" => "some_value"}
    end

    test "ignores nil extra_changes", %{project: project} do
      {:ok, sp} = ScreenplayCrud.create_screenplay(project, %{name: "Host"})

      attrs = %{type: "action", content: "Test", position: 0}
      {:ok, el} = ScreenplayCrud.import_element(sp.id, attrs, %{linked_node_id: nil})

      assert el.linked_node_id == nil
    end

    test "fails with invalid element type", %{project: project} do
      {:ok, sp} = ScreenplayCrud.create_screenplay(project, %{name: "Host"})
      {:error, changeset} = ScreenplayCrud.import_element(sp.id, %{type: "invalid"})
      assert errors_on(changeset).type != []
    end
  end

  # ===========================================================================
  # link_import_refs/2
  # ===========================================================================

  describe "link_import_refs/2" do
    setup :setup_project

    test "updates parent_id on screenplay", %{project: project} do
      {:ok, parent} = ScreenplayCrud.create_screenplay(project, %{name: "Parent"})
      {:ok, child} = ScreenplayCrud.create_screenplay(project, %{name: "Child"})

      result = ScreenplayCrud.link_import_refs(child, %{parent_id: parent.id})

      assert result.parent_id == parent.id
    end

    test "updates draft_of_id on screenplay", %{project: project} do
      {:ok, original} = ScreenplayCrud.create_screenplay(project, %{name: "Original"})
      {:ok, draft} = ScreenplayCrud.create_screenplay(project, %{name: "Draft"})

      result = ScreenplayCrud.link_import_refs(draft, %{draft_of_id: original.id})

      assert result.draft_of_id == original.id
    end

    test "returns :ok for empty changes", %{project: project} do
      {:ok, sp} = ScreenplayCrud.create_screenplay(project, %{name: "No Changes"})

      assert ScreenplayCrud.link_import_refs(sp, %{}) == :ok
    end
  end
end
