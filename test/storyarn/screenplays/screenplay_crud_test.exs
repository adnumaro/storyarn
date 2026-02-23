defmodule Storyarn.Screenplays.ScreenplayCrudTest do
  use Storyarn.DataCase, async: true

  alias Storyarn.Screenplays.ScreenplayCrud

  import Storyarn.AccountsFixtures
  import Storyarn.ProjectsFixtures
  import Storyarn.ScreenplaysFixtures

  defp setup_project(_context) do
    user = user_fixture()
    project = project_fixture(user)
    %{user: user, project: project}
  end

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

    test "fails without name", %{project: project} do
      {:error, changeset} = ScreenplayCrud.create_screenplay(project, %{})
      assert "can't be blank" in errors_on(changeset).name
    end
  end

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
  end

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
  end

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
  end

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

    test "deleted screenplay appears in list_deleted_screenplays", %{project: project} do
      screenplay = screenplay_fixture(project)
      {:ok, _} = ScreenplayCrud.delete_screenplay(screenplay)

      deleted = ScreenplayCrud.list_deleted_screenplays(project.id)
      assert Enum.any?(deleted, &(&1.id == screenplay.id))
    end
  end

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

  describe "change_screenplay/2" do
    setup :setup_project

    test "returns a valid changeset with valid attrs", %{project: project} do
      screenplay = %Storyarn.Screenplays.Screenplay{project_id: project.id}
      changeset = ScreenplayCrud.change_screenplay(screenplay, %{name: "Act 1"})

      assert %Ecto.Changeset{} = changeset
      assert changeset.valid?
    end

    test "returns a changeset with errors for invalid attrs", %{project: project} do
      screenplay = %Storyarn.Screenplays.Screenplay{project_id: project.id}
      changeset = ScreenplayCrud.change_screenplay(screenplay, %{name: ""})

      assert %Ecto.Changeset{} = changeset
      refute changeset.valid?
      assert {"can't be blank", _} = changeset.errors[:name]
    end
  end

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
  end
end
