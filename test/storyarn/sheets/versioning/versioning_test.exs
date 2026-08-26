defmodule Storyarn.Sheets.VersioningTest do
  use Storyarn.DataCase, async: true

  import Ecto.Query, warn: false
  import Storyarn.AccountsFixtures
  import Storyarn.ProjectsFixtures
  import Storyarn.SheetsFixtures

  alias Storyarn.Platform.Collaboration
  alias Storyarn.Repo
  alias Storyarn.Sheets
  alias Storyarn.Sheets.Sheet

  setup do
    user = user_fixture()
    project = project_fixture(user)
    sheet = sheet_fixture(project)
    _block = block_fixture(sheet, %{type: "text", config: %{"label" => "Name"}})
    sheet = Repo.preload(sheet, :blocks, force: true)

    %{user: user, project: project, sheet: sheet}
  end

  describe "Sheet versioning lifecycle" do
    test "create, list, restore, delete cycle", %{project: project, user: user} do
      sheet = sheet_fixture(project)

      _block =
        block_fixture(sheet, %{
          type: "text",
          config: %{"label" => "Name"},
          value: %{"content" => "Alice"}
        })

      sheet = Repo.preload(sheet, :blocks, force: true)

      {:ok, version} = Sheets.create_version(sheet, user.id, title: "v1")

      assert version.entity_type == "sheet"
      assert version.version_number == 1

      {:ok, sheet} = Sheets.update_sheet(sheet, %{name: "Modified Sheet"})

      versions = Sheets.list_versions(sheet.id)
      assert length(versions) == 1

      {:ok, restored} = Sheets.restore_version(sheet, version)
      assert restored.name != "Modified Sheet"

      {:ok, _} = Sheets.delete_version(version)

      assert [safety_version] = Sheets.list_versions(sheet.id)
      assert safety_version.is_auto
      assert safety_version.title == "Before restore to v1"
    end
  end

  describe "restore_version/4" do
    test "creates pre-restore and post-restore versions when user_id provided", %{
      sheet: sheet,
      user: user
    } do
      {:ok, version} =
        Sheets.create_version(sheet, user.id, title: "Original")

      # Modify the sheet
      {:ok, modified_sheet} = Sheets.update_sheet(sheet, %{name: "Modified"})
      modified_sheet = Repo.preload(modified_sheet, :blocks, force: true)

      # Restore with user_id
      {:ok, _restored} =
        Sheets.restore_version(modified_sheet, version, user_id: user.id)

      # Should have: Original (v1) + Before restore (v2) + Restored from (v3)
      versions = Sheets.list_versions(sheet.id)
      assert length(versions) == 3

      titles = Enum.map(versions, & &1.title)
      assert Enum.any?(titles, &(&1 =~ "Before restore"))
      assert Enum.any?(titles, &(&1 =~ "Restored from"))
    end

    test "always creates a safety version even when user_id is nil", %{
      sheet: sheet,
      project: project,
      user: user
    } do
      {:ok, version} =
        Sheets.create_version(sheet, user.id, title: "v1")

      :ok = Collaboration.subscribe_dashboard(project.id)
      {:ok, _restored} = Sheets.restore_version(sheet, version)
      assert_received {:dashboard_invalidate, :sheets}

      # Anonymous/internal callers still get a durable safety point. A post
      # version is omitted because there is no actor to attribute it to.
      versions = Sheets.list_versions(sheet.id)
      assert length(versions) == 2
      assert Enum.any?(versions, &(&1.title =~ "Before restore"))
      assert Enum.any?(versions, &is_nil(&1.created_by_id))
    end

    test "rejects an ambient transaction before creating a safety snapshot", %{
      sheet: sheet,
      project: project,
      user: user
    } do
      {:ok, version} =
        Sheets.create_version(sheet, user.id, title: "Original")

      version_count = length(Sheets.list_versions(sheet.id))
      stored_paths = stored_version_paths(project.id, sheet.id)

      assert {:ok, {:error, :version_restore_requires_transaction_boundary}} =
               Repo.transaction(fn ->
                 Sheets.restore_version(sheet, version, user_id: user.id)
               end)

      assert length(Sheets.list_versions(sheet.id)) == version_count
      assert stored_version_paths(project.id, sheet.id) == stored_paths
    end

    test "does not allow skip_pre_snapshot to bypass the safety version", %{
      sheet: sheet,
      user: user
    } do
      {:ok, version} =
        Sheets.create_version(sheet, user.id, title: "Original")

      {:ok, modified_sheet} = Sheets.update_sheet(sheet, %{name: "Modified"})
      modified_sheet = Repo.preload(modified_sheet, :blocks, force: true)

      {:ok, _restored} =
        Sheets.restore_version(modified_sheet, version,
          user_id: user.id,
          skip_pre_snapshot: true
        )

      # Should have: Original + mandatory Before restore + Restored from.
      versions = Sheets.list_versions(sheet.id)
      assert length(versions) == 3

      titles = Enum.map(versions, & &1.title)
      assert Enum.any?(titles, &(&1 =~ "Before restore"))
      assert Enum.any?(titles, &(&1 =~ "Restored from"))
    end

    test "rejects a version owned by another entity before creating safety state", %{
      sheet: sheet,
      project: project,
      user: user
    } do
      other_sheet = sheet_fixture(project)
      other_sheet = Repo.preload(other_sheet, :blocks, force: true)

      {:ok, other_version} =
        Sheets.create_version(other_sheet, user.id)

      assert {:error, :entity_version_scope_mismatch} =
               Sheets.restore_version(sheet, other_version, user_id: user.id)

      assert Sheets.count_versions(sheet.id) == 0
    end

    test "rejects restore if the verified safety record disappears", %{
      sheet: sheet,
      user: user
    } do
      {:ok, target} =
        Sheets.create_version(sheet, user.id)

      assert {:error, :pre_restore_version_not_durable} =
               Sheets.restore_version(sheet, target,
                 user_id: user.id,
                 __after_pre_restore_version_verified_hook: fn safety_version ->
                   assert {:ok, _deleted} =
                            Sheets.delete_version(safety_version)
                 end
               )

      assert Sheets.count_versions(sheet.id) == 1
    end

    test "aborts without overwriting a change made after the safety version", %{
      sheet: sheet,
      user: user
    } do
      {:ok, target} =
        Sheets.create_version(sheet, user.id)

      {:ok, modified_sheet} =
        Sheets.update_sheet(sheet, %{name: "Before safety"})

      assert {:error, :sheet_changed_since_pre_restore_snapshot} =
               Sheets.restore_version(modified_sheet, target,
                 user_id: user.id,
                 __after_pre_restore_version_verified_hook: fn _safety_version ->
                   current = Repo.get!(Sheet, sheet.id)

                   assert {:ok, _changed} =
                            Sheets.update_sheet(current, %{
                              name: "Concurrent change"
                            })
                 end
               )

      assert Repo.get!(Sheet, sheet.id).name ==
               "Concurrent change"

      versions = Sheets.list_versions(sheet.id)
      assert length(versions) == 2
      assert Enum.any?(versions, &(&1.title =~ "Before restore"))

      refute Enum.any?(versions, fn version ->
               is_binary(version.title) and version.title =~ "Restored from"
             end)
    end

    test "resolves shortcut collision with -restored suffix", %{
      project: project,
      user: user
    } do
      sheet1 = sheet_fixture(project, %{name: "Alpha"})
      _block = block_fixture(sheet1, %{type: "text"})
      sheet1 = Repo.preload(sheet1, :blocks, force: true)

      # Create version of sheet1 with its current shortcut
      {:ok, version} =
        Sheets.create_version(sheet1, user.id, title: "v1")

      {:ok, snapshot} = Sheets.load_version_snapshot(version)
      old_shortcut = snapshot["shortcut"]

      # Change sheet1's shortcut to something different
      {:ok, sheet1} = Sheets.update_sheet(sheet1, %{shortcut: "different-shortcut"})

      # Create sheet2 with the old shortcut to create a collision
      sheet2 = sheet_fixture(project, %{name: "Beta"})
      {:ok, _sheet2} = Sheets.update_sheet(sheet2, %{shortcut: old_shortcut})

      # Reload sheet1
      sheet1 = Repo.preload(sheet1, :blocks, force: true)

      # Restore — should use random suffix to avoid collision
      {:ok, restored} = Sheets.restore_version(sheet1, version)
      assert String.starts_with?(restored.shortcut, old_shortcut <> "-")
      assert restored.shortcut != old_shortcut
    end
  end

  defp stored_version_paths(project_id, sheet_id) do
    upload_dir =
      :storyarn
      |> Application.fetch_env!(:storage)
      |> Keyword.fetch!(:upload_dir)
      |> Path.expand()

    upload_dir
    |> Path.join("projects/#{project_id}/snapshots/sheet/#{sheet_id}/*.json.gz")
    |> Path.wildcard()
    |> MapSet.new()
  end
end
