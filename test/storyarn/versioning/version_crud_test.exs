defmodule Storyarn.Versioning.VersionCrudTest do
  use Storyarn.DataCase, async: true

  import Ecto.Query, warn: false
  import Storyarn.AccountsFixtures
  import Storyarn.ProjectsFixtures
  import Storyarn.SheetsFixtures

  alias Storyarn.Assets.Storage
  alias Storyarn.Repo
  alias Storyarn.Versioning
  alias Storyarn.Versioning.EntityVersion
  alias Storyarn.Versioning.SnapshotStorage

  setup do
    user = user_fixture()
    project = project_fixture(user)
    sheet = sheet_fixture(project)
    _block = block_fixture(sheet, %{type: "text", config: %{"label" => "Name"}})
    sheet = Repo.preload(sheet, :blocks, force: true)

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
      assert version.storage_key =~ ~r|snapshots/sheet/#{sheet.id}/1-[a-f0-9]{16}\.json\.gz$|
      assert version.snapshot_size_bytes > 0
      assert version.checksum =~ ~r/\A[0-9a-f]{64}\z/
      assert version.created_by_id == user.id
    end

    test "rejects mismatched entity type or project before storing a snapshot", %{
      sheet: sheet,
      user: user
    } do
      other_project = project_fixture(user)

      assert {:error, :entity_scope_mismatch} =
               Versioning.create_version("sheet", sheet, other_project.id, user.id)

      assert {:error, :unknown_entity_type} =
               Versioning.create_version("flow", sheet, sheet.project_id, user.id)

      assert {:error, :unknown_entity_type} =
               Versioning.create_version("scene", sheet, sheet.project_id, user.id)

      assert Versioning.count_versions("sheet", sheet.id) == 0
      assert Versioning.count_versions("flow", sheet.id) == 0
      assert Versioning.count_versions("scene", sheet.id) == 0
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
      assert version.change_summary
      assert version.title == nil
    end

    test "generates change_summary even when title is provided", %{
      sheet: sheet,
      project: project,
      user: user
    } do
      {:ok, version} =
        Versioning.create_version("sheet", sheet, project.id, user.id, title: "Manual")

      assert version.change_summary
      assert version.title == "Manual"
    end

    test "stores structured change_details with diff data", %{
      sheet: sheet,
      project: project,
      user: user
    } do
      # First version — initial, no previous to diff against
      {:ok, v1} = Versioning.create_version("sheet", sheet, project.id, user.id)
      assert v1.change_details == nil

      # Modify the sheet and create a second version
      {:ok, modified_sheet} = Storyarn.Sheets.update_sheet(sheet, %{name: "Modified Name"})
      modified_sheet = Repo.preload(modified_sheet, :blocks, force: true)

      {:ok, v2} = Versioning.create_version("sheet", modified_sheet, project.id, user.id)
      assert v2.change_summary
      assert v2.change_details
      assert is_map(v2.change_details)
      assert is_list(v2.change_details["changes"])
      assert is_map(v2.change_details["stats"])

      # Should have at least one change (name modified)
      assert v2.change_details["changes"] != []

      # Each change has the expected structure
      change = hd(v2.change_details["changes"])
      assert change["category"] in ["property", "block", "node", "connection", "layer"]
      assert change["action"] in ["added", "modified", "removed"]
      assert is_binary(change["detail"])
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
               Versioning.maybe_create_version("sheet", sheet, project.id, user.id, min_interval: 0)
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
      assert {:error, _} = SnapshotStorage.load_snapshot(storage_key)
    end

    test "uses persisted metadata instead of a caller-supplied storage key", %{
      sheet: sheet,
      project: project,
      user: user
    } do
      {:ok, first} = Versioning.create_version("sheet", sheet, project.id, user.id)
      {:ok, second} = Versioning.create_version("sheet", sheet, project.id, user.id)

      forged = %{first | storage_key: second.storage_key, checksum: second.checksum}

      assert {:ok, deleted} = Versioning.delete_version(forged)
      assert deleted.id == first.id
      assert {:ok, _snapshot} = Versioning.load_version_snapshot(second)
      assert Repo.get!(EntityVersion, second.id).storage_key == second.storage_key
    end

    test "rejects a corrupted persisted key before deleting the record or unrelated blob", %{
      sheet: sheet,
      project: project,
      user: user
    } do
      {:ok, first} = Versioning.create_version("sheet", sheet, project.id, user.id)
      {:ok, second} = Versioning.create_version("sheet", sheet, project.id, user.id)

      Repo.update_all(
        from(version in EntityVersion, where: version.id == ^first.id),
        set: [storage_key: second.storage_key]
      )

      assert {:error, :entity_version_storage_key_mismatch} =
               Versioning.delete_version(first)

      assert Repo.get(EntityVersion, first.id)
      assert Repo.get(EntityVersion, second.id)
      assert {:ok, _snapshot} = Versioning.load_version_snapshot(second)
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

    test "rejects a same-size replaced object before decoding", %{
      sheet: sheet,
      project: project,
      user: user
    } do
      {:ok, version} =
        Versioning.create_version("sheet", sheet, project.id, user.id)

      {:ok, compressed} = Storage.download(version.storage_key)
      <<first_byte, rest::binary>> = compressed
      replaced = <<Bitwise.bxor(first_byte, 0xFF), rest::binary>>
      assert byte_size(replaced) == version.snapshot_size_bytes
      assert {:ok, _url} = Storage.upload(version.storage_key, replaced, "application/gzip")

      actual_checksum =
        :sha256
        |> :crypto.hash(replaced)
        |> Base.encode16(case: :lower)

      assert {:error, {:checksum_mismatch, expected_checksum, ^actual_checksum}} =
               Versioning.load_version_snapshot(version)

      assert expected_checksum == version.checksum
    end

    test "rejects a database row pointing outside its entity-version keyspace", %{
      sheet: sheet,
      project: project,
      user: user
    } do
      {:ok, version} =
        Versioning.create_version("sheet", sheet, project.id, user.id)

      wrong_key =
        SnapshotStorage.build_key(
          project.id + 1,
          "sheet",
          sheet.id,
          1,
          SnapshotStorage.unique_key_suffix()
        )

      Repo.update_all(
        from(candidate in EntityVersion, where: candidate.id == ^version.id),
        set: [storage_key: wrong_key]
      )

      assert {:error, :entity_version_storage_key_mismatch} =
               Versioning.load_version_snapshot(version)
    end
  end

  describe "update_version/2" do
    test "updates title and description", %{sheet: sheet, project: project, user: user} do
      {:ok, version} =
        Versioning.create_version("sheet", sheet, project.id, user.id, is_auto: true)

      assert version.title == nil

      assert {:ok, updated} =
               Versioning.update_version(version, %{
                 title: "Milestone 1",
                 description: "Before refactor"
               })

      assert updated.title == "Milestone 1"
      assert updated.description == "Before refactor"
      # Promotion flips is_auto so it counts against the named version quota
      assert updated.is_auto == false
    end

    test "requires title", %{sheet: sheet, project: project, user: user} do
      {:ok, version} =
        Versioning.create_version("sheet", sheet, project.id, user.id, is_auto: true)

      assert {:error, changeset} = Versioning.update_version(version, %{title: nil})
      assert errors_on(changeset).title
    end

    test "rejects empty string title", %{sheet: sheet, project: project, user: user} do
      {:ok, version} =
        Versioning.create_version("sheet", sheet, project.id, user.id, is_auto: true)

      assert {:error, changeset} = Versioning.update_version(version, %{title: ""})
      assert errors_on(changeset).title
    end

    test "validates title max length", %{sheet: sheet, project: project, user: user} do
      {:ok, version} = Versioning.create_version("sheet", sheet, project.id, user.id)
      long_title = String.duplicate("a", 256)

      assert {:error, changeset} = Versioning.update_version(version, %{title: long_title})
      assert errors_on(changeset).title
    end

    test "validates description max length", %{sheet: sheet, project: project, user: user} do
      {:ok, version} = Versioning.create_version("sheet", sheet, project.id, user.id)
      long_desc = String.duplicate("a", 501)

      assert {:error, changeset} =
               Versioning.update_version(version, %{title: "OK", description: long_desc})

      assert errors_on(changeset).description
    end
  end

  describe "count_named_versions/1" do
    test "counts versions with non-nil title", %{sheet: sheet, project: project, user: user} do
      assert Versioning.count_named_versions(project.id) == 0

      # Auto-snapshot (no title)
      {:ok, _} =
        Versioning.create_version("sheet", sheet, project.id, user.id, is_auto: true)

      assert Versioning.count_named_versions(project.id) == 0

      # Manual version (with title)
      {:ok, _} =
        Versioning.create_version("sheet", sheet, project.id, user.id, title: "v1")

      assert Versioning.count_named_versions(project.id) == 1

      # Promote auto-snapshot (add title)
      {:ok, auto} =
        Versioning.create_version("sheet", sheet, project.id, user.id, is_auto: true)

      {:ok, _} = Versioning.update_version(auto, %{title: "Promoted"})

      assert Versioning.count_named_versions(project.id) == 2
    end
  end
end
