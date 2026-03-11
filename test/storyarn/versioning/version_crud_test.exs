defmodule Storyarn.Versioning.VersionCrudTest do
  use Storyarn.DataCase, async: true

  alias Storyarn.Versioning
  alias Storyarn.Versioning.EntityVersion

  import Storyarn.AccountsFixtures
  import Storyarn.ProjectsFixtures
  import Storyarn.SheetsFixtures

  setup do
    user = user_fixture()
    project = project_fixture(user)
    sheet = sheet_fixture(project)
    _block = block_fixture(sheet, %{type: "text", config: %{"label" => "Name"}})
    sheet = Storyarn.Repo.preload(sheet, :blocks, force: true)

    %{user: user, project: project, sheet: sheet}
  end

  describe "create_version/5" do
    test "creates a version with stored snapshot", %{sheet: sheet, project: project, user: user} do
      assert {:ok, %EntityVersion{} = version} =
               Versioning.create_version("sheet", sheet, project.id, user.id, title: "v1")

      assert version.entity_type == "sheet"
      assert version.entity_id == sheet.id
      assert version.project_id == project.id
      assert version.version_number == 1
      assert version.title == "v1"
      assert version.storage_key =~ "snapshots/sheet/#{sheet.id}/1.json.gz"
      assert version.snapshot_size_bytes > 0
      assert version.created_by_id == user.id
    end

    test "increments version numbers", %{sheet: sheet, project: project, user: user} do
      {:ok, v1} = Versioning.create_version("sheet", sheet, project.id, user.id)
      {:ok, v2} = Versioning.create_version("sheet", sheet, project.id, user.id)

      assert v1.version_number == 1
      assert v2.version_number == 2
    end

    test "generates change_summary when no title given", %{
      sheet: sheet,
      project: project,
      user: user
    } do
      {:ok, version} = Versioning.create_version("sheet", sheet, project.id, user.id)
      assert version.change_summary != nil
      assert version.title == nil
    end

    test "skips change_summary when title is provided", %{
      sheet: sheet,
      project: project,
      user: user
    } do
      {:ok, version} =
        Versioning.create_version("sheet", sheet, project.id, user.id, title: "Manual")

      assert version.change_summary == nil
      assert version.title == "Manual"
    end
  end

  describe "maybe_create_version/5" do
    test "creates first version always", %{sheet: sheet, project: project, user: user} do
      assert {:ok, %EntityVersion{}} =
               Versioning.maybe_create_version("sheet", sheet, project.id, user.id)
    end

    test "skips if too recent", %{sheet: sheet, project: project, user: user} do
      {:ok, _} = Versioning.create_version("sheet", sheet, project.id, user.id)

      assert {:skipped, :too_recent} =
               Versioning.maybe_create_version("sheet", sheet, project.id, user.id)
    end

    test "respects custom min_interval", %{sheet: sheet, project: project, user: user} do
      {:ok, _} = Versioning.create_version("sheet", sheet, project.id, user.id)

      # With 0 second interval, should always create
      assert {:ok, %EntityVersion{}} =
               Versioning.maybe_create_version("sheet", sheet, project.id, user.id,
                 min_interval: 0
               )
    end
  end

  describe "list_versions/3" do
    test "returns versions in descending order", %{sheet: sheet, project: project, user: user} do
      {:ok, _v1} = Versioning.create_version("sheet", sheet, project.id, user.id)
      {:ok, _v2} = Versioning.create_version("sheet", sheet, project.id, user.id)

      versions = Versioning.list_versions("sheet", sheet.id)
      assert length(versions) == 2
      assert hd(versions).version_number == 2
    end

    test "supports limit and offset", %{sheet: sheet, project: project, user: user} do
      for _ <- 1..5, do: Versioning.create_version("sheet", sheet, project.id, user.id)

      assert length(Versioning.list_versions("sheet", sheet.id, limit: 2)) == 2
      assert length(Versioning.list_versions("sheet", sheet.id, limit: 2, offset: 4)) == 1
    end
  end

  describe "get_version/3" do
    test "returns the version by number", %{sheet: sheet, project: project, user: user} do
      {:ok, created} = Versioning.create_version("sheet", sheet, project.id, user.id)
      found = Versioning.get_version("sheet", sheet.id, 1)
      assert found.id == created.id
    end

    test "returns nil for non-existent version" do
      assert Versioning.get_version("sheet", 999_999, 1) == nil
    end
  end

  describe "get_latest_version/2" do
    test "returns the most recent version", %{sheet: sheet, project: project, user: user} do
      {:ok, _} = Versioning.create_version("sheet", sheet, project.id, user.id)
      {:ok, v2} = Versioning.create_version("sheet", sheet, project.id, user.id)

      latest = Versioning.get_latest_version("sheet", sheet.id)
      assert latest.id == v2.id
    end

    test "returns nil when no versions exist" do
      assert Versioning.get_latest_version("sheet", 999_999) == nil
    end
  end

  describe "count_versions/2" do
    test "counts versions for an entity", %{sheet: sheet, project: project, user: user} do
      assert Versioning.count_versions("sheet", sheet.id) == 0

      {:ok, _} = Versioning.create_version("sheet", sheet, project.id, user.id)
      {:ok, _} = Versioning.create_version("sheet", sheet, project.id, user.id)

      assert Versioning.count_versions("sheet", sheet.id) == 2
    end
  end

  describe "delete_version/1" do
    test "deletes version and snapshot from storage", %{
      sheet: sheet,
      project: project,
      user: user
    } do
      {:ok, version} = Versioning.create_version("sheet", sheet, project.id, user.id)
      storage_key = version.storage_key

      assert {:ok, _} = Versioning.delete_version(version)
      assert Versioning.get_version("sheet", sheet.id, 1) == nil

      # Snapshot should be deleted from storage
      assert {:error, _} = Storyarn.Versioning.SnapshotStorage.load_snapshot(storage_key)
    end
  end

  describe "load_version_snapshot/1" do
    test "loads the full snapshot data", %{sheet: sheet, project: project, user: user} do
      {:ok, version} = Versioning.create_version("sheet", sheet, project.id, user.id)
      assert {:ok, snapshot} = Versioning.load_version_snapshot(version)
      assert is_map(snapshot)
      assert Map.has_key?(snapshot, "name")
      assert Map.has_key?(snapshot, "blocks")
    end
  end
end
