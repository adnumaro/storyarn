defmodule Storyarn.Versioning.ProjectSnapshotCrudTest do
  use Storyarn.DataCase, async: true

  alias Storyarn.Versioning
  alias Storyarn.Versioning.ProjectSnapshot

  import Storyarn.AccountsFixtures
  import Storyarn.FlowsFixtures
  import Storyarn.ProjectsFixtures
  import Storyarn.SheetsFixtures

  setup do
    user = user_fixture()
    project = project_fixture(user)
    sheet = sheet_fixture(project)
    _block = block_fixture(sheet, %{type: "text", config: %{"label" => "Name"}})
    flow = flow_fixture(project)
    _node = node_fixture(flow, %{type: "dialogue"})

    %{user: user, project: project, sheet: sheet, flow: flow}
  end

  describe "create_project_snapshot/3" do
    test "creates a snapshot with stored data", %{project: project, user: user} do
      assert {:ok, %ProjectSnapshot{} = snapshot} =
               Versioning.create_project_snapshot(project.id, user.id, title: "v1")

      assert snapshot.project_id == project.id
      assert snapshot.version_number == 1
      assert snapshot.title == "v1"
      assert snapshot.storage_key =~ "snapshots/project/#{snapshot.version_number}.json.gz"
      assert snapshot.snapshot_size_bytes > 0
      assert snapshot.created_by_id == user.id
      assert snapshot.entity_counts["sheets"] >= 1
      assert snapshot.entity_counts["flows"] >= 1
    end

    test "increments version numbers", %{project: project, user: user} do
      {:ok, s1} = Versioning.create_project_snapshot(project.id, user.id)
      {:ok, s2} = Versioning.create_project_snapshot(project.id, user.id)

      assert s1.version_number == 1
      assert s2.version_number == 2
    end

    test "creates snapshot without title", %{project: project, user: user} do
      assert {:ok, %ProjectSnapshot{title: nil}} =
               Versioning.create_project_snapshot(project.id, user.id)
    end
  end

  describe "list_project_snapshots/2" do
    test "returns snapshots ordered by version_number desc", %{project: project, user: user} do
      {:ok, _s1} = Versioning.create_project_snapshot(project.id, user.id, title: "First")
      {:ok, _s2} = Versioning.create_project_snapshot(project.id, user.id, title: "Second")

      snapshots = Versioning.list_project_snapshots(project.id)
      assert length(snapshots) == 2
      assert hd(snapshots).title == "Second"
    end

    test "preloads created_by", %{project: project, user: user} do
      {:ok, _} = Versioning.create_project_snapshot(project.id, user.id)

      [snapshot] = Versioning.list_project_snapshots(project.id)
      assert snapshot.created_by.id == user.id
    end

    test "respects limit and offset", %{project: project, user: user} do
      for _ <- 1..3, do: Versioning.create_project_snapshot(project.id, user.id)

      assert length(Versioning.list_project_snapshots(project.id, limit: 2)) == 2
      assert length(Versioning.list_project_snapshots(project.id, limit: 2, offset: 2)) == 1
    end
  end

  describe "get_project_snapshot/2" do
    test "returns snapshot by id", %{project: project, user: user} do
      {:ok, created} = Versioning.create_project_snapshot(project.id, user.id, title: "Test")

      snapshot = Versioning.get_project_snapshot(project.id, created.id)
      assert snapshot.id == created.id
      assert snapshot.title == "Test"
    end

    test "returns nil for non-existent snapshot", %{project: project} do
      assert Versioning.get_project_snapshot(project.id, 999_999) == nil
    end
  end

  describe "count_project_snapshots/1" do
    test "counts snapshots for project", %{project: project, user: user} do
      assert Versioning.count_project_snapshots(project.id) == 0

      {:ok, _} = Versioning.create_project_snapshot(project.id, user.id)
      assert Versioning.count_project_snapshots(project.id) == 1

      {:ok, _} = Versioning.create_project_snapshot(project.id, user.id)
      assert Versioning.count_project_snapshots(project.id) == 2
    end
  end

  describe "update_project_snapshot/2" do
    test "updates title and description", %{project: project, user: user} do
      {:ok, snapshot} = Versioning.create_project_snapshot(project.id, user.id)

      assert {:ok, updated} =
               Versioning.update_project_snapshot(snapshot, %{
                 title: "Renamed",
                 description: "Updated"
               })

      assert updated.title == "Renamed"
      assert updated.description == "Updated"
    end

    test "returns error changeset for invalid attrs", %{project: project, user: user} do
      {:ok, snapshot} = Versioning.create_project_snapshot(project.id, user.id)

      assert {:error, %Ecto.Changeset{}} =
               Versioning.update_project_snapshot(snapshot, %{
                 title: String.duplicate("a", 256)
               })
    end
  end

  describe "delete_project_snapshot/1" do
    test "deletes snapshot and cleans up storage", %{project: project, user: user} do
      {:ok, snapshot} = Versioning.create_project_snapshot(project.id, user.id)
      assert {:ok, _} = Versioning.delete_project_snapshot(snapshot)
      assert Versioning.count_project_snapshots(project.id) == 0
    end
  end

  describe "restore_project_snapshot/3" do
    test "restores entities from snapshot", %{project: project, user: user, sheet: sheet} do
      # Create snapshot with current state
      {:ok, snapshot} =
        Versioning.create_project_snapshot(project.id, user.id, title: "Baseline")

      # Modify the sheet
      {:ok, _} = Storyarn.Sheets.update_sheet(sheet, %{name: "Modified Name"})

      # Restore from snapshot
      assert {:ok, result} =
               Versioning.restore_project_snapshot(project.id, snapshot, user_id: user.id)

      assert result.restored >= 1
      assert is_integer(result.skipped)

      # Verify sheet was restored
      restored_sheet = Storyarn.Sheets.get_sheet(project.id, sheet.id)
      assert restored_sheet.name == sheet.name
    end

    test "creates safety snapshots when user_id provided", %{project: project, user: user} do
      {:ok, snapshot} = Versioning.create_project_snapshot(project.id, user.id, title: "Base")

      initial_count = Versioning.count_project_snapshots(project.id)

      {:ok, _} = Versioning.restore_project_snapshot(project.id, snapshot, user_id: user.id)

      # Should have 2 more: pre-restore + post-restore
      assert Versioning.count_project_snapshots(project.id) == initial_count + 2
    end

    test "skips deleted entities gracefully", %{project: project, user: user, sheet: sheet} do
      {:ok, snapshot} = Versioning.create_project_snapshot(project.id, user.id)

      # Soft-delete the sheet
      {:ok, _} = Storyarn.Sheets.delete_sheet(sheet)

      # Restore should succeed, skipping the deleted sheet
      assert {:ok, result} = Versioning.restore_project_snapshot(project.id, snapshot)
      assert result.skipped >= 1
    end
  end
end
