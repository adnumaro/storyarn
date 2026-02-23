defmodule Storyarn.Sheets.VersioningTest do
  use Storyarn.DataCase, async: true

  alias Storyarn.Sheets
  alias Storyarn.Sheets.SheetVersion

  import Storyarn.AccountsFixtures
  import Storyarn.SheetsFixtures
  import Storyarn.ProjectsFixtures

  describe "create_version/3" do
    test "creates version with correct snapshot" do
      user = user_fixture()
      project = project_fixture(user)
      sheet = sheet_fixture(project, %{name: "Test Sheet", shortcut: "test-sheet"})

      _block1 =
        block_fixture(sheet, %{
          type: "text",
          config: %{"label" => "Name"},
          value: %{"content" => "John"}
        })

      _block2 =
        block_fixture(sheet, %{
          type: "number",
          config: %{"label" => "Age"},
          value: %{"content" => 30}
        })

      {:ok, version} = Sheets.create_version(sheet, user)

      assert version.sheet_id == sheet.id
      assert version.version_number == 1
      assert version.changed_by_id == user.id
      assert version.snapshot["name"] == "Test Sheet"
      assert version.snapshot["shortcut"] == "test-sheet"
      assert length(version.snapshot["blocks"]) == 2
    end

    test "increments version number" do
      user = user_fixture()
      project = project_fixture(user)
      sheet = sheet_fixture(project)

      {:ok, v1} = Sheets.create_version(sheet, user)
      {:ok, v2} = Sheets.create_version(sheet, user)
      {:ok, v3} = Sheets.create_version(sheet, user)

      assert v1.version_number == 1
      assert v2.version_number == 2
      assert v3.version_number == 3
    end

    test "generates change summary for first version" do
      user = user_fixture()
      project = project_fixture(user)
      sheet = sheet_fixture(project)
      _block = block_fixture(sheet)

      {:ok, version} = Sheets.create_version(sheet, user)

      assert version.change_summary =~ "Initial version"
      assert version.change_summary =~ "1 block"
    end

    test "includes all block data in snapshot" do
      user = user_fixture()
      project = project_fixture(user)
      sheet = sheet_fixture(project)

      {:ok, block} =
        Sheets.create_block(sheet, %{
          type: "text",
          config: %{"label" => "Custom Label", "placeholder" => "Enter..."},
          value: %{"content" => "Test content"}
        })

      # Update block to set is_constant (variable_name is auto-generated from label)
      {:ok, _} = Sheets.update_block(block, %{is_constant: true})

      # Reload sheet with blocks
      sheet = Sheets.get_sheet!(project.id, sheet.id)
      {:ok, version} = Sheets.create_version(sheet, user)

      [block_snapshot] = version.snapshot["blocks"]
      assert block_snapshot["type"] == "text"
      assert block_snapshot["config"]["label"] == "Custom Label"
      assert block_snapshot["value"]["content"] == "Test content"
      assert block_snapshot["is_constant"] == true
      # variable_name is auto-generated from the label
      assert block_snapshot["variable_name"] == "custom_label"
      # IDs are intentionally excluded from snapshots
      refute Map.has_key?(block_snapshot, "id")
    end

    test "accepts user struct or user_id" do
      user = user_fixture()
      project = project_fixture(user)
      sheet = sheet_fixture(project)

      {:ok, v1} = Sheets.create_version(sheet, user)
      {:ok, v2} = Sheets.create_version(sheet, user.id)

      assert v1.changed_by_id == user.id
      assert v2.changed_by_id == user.id
    end

    test "accepts custom title option" do
      user = user_fixture()
      project = project_fixture(user)
      sheet = sheet_fixture(project)

      {:ok, version} = Sheets.create_version(sheet, user, title: "Manual save")

      assert version.title == "Manual save"
      assert version.change_summary == nil
    end

    test "accepts custom description option" do
      user = user_fixture()
      project = project_fixture(user)
      sheet = sheet_fixture(project)

      {:ok, version} = Sheets.create_version(sheet, user, description: "Before major refactor")

      assert version.description == "Before major refactor"
    end
  end

  describe "list_versions/2" do
    test "returns versions ordered by version_number desc" do
      user = user_fixture()
      project = project_fixture(user)
      sheet = sheet_fixture(project)

      {:ok, _v1} = Sheets.create_version(sheet, user)
      {:ok, _v2} = Sheets.create_version(sheet, user)
      {:ok, _v3} = Sheets.create_version(sheet, user)

      versions = Sheets.list_versions(sheet.id)

      assert length(versions) == 3
      assert Enum.at(versions, 0).version_number == 3
      assert Enum.at(versions, 1).version_number == 2
      assert Enum.at(versions, 2).version_number == 1
    end

    test "respects limit option" do
      user = user_fixture()
      project = project_fixture(user)
      sheet = sheet_fixture(project)

      for _ <- 1..5, do: Sheets.create_version(sheet, user)

      versions = Sheets.list_versions(sheet.id, limit: 2)

      assert length(versions) == 2
      assert Enum.at(versions, 0).version_number == 5
      assert Enum.at(versions, 1).version_number == 4
    end

    test "respects offset option" do
      user = user_fixture()
      project = project_fixture(user)
      sheet = sheet_fixture(project)

      for _ <- 1..5, do: Sheets.create_version(sheet, user)

      versions = Sheets.list_versions(sheet.id, limit: 2, offset: 2)

      assert length(versions) == 2
      assert Enum.at(versions, 0).version_number == 3
      assert Enum.at(versions, 1).version_number == 2
    end

    test "preloads changed_by user" do
      user = user_fixture()
      project = project_fixture(user)
      sheet = sheet_fixture(project)

      {:ok, _} = Sheets.create_version(sheet, user)

      [version] = Sheets.list_versions(sheet.id)

      assert version.changed_by.id == user.id
      assert version.changed_by.email == user.email
    end

    test "returns empty list for sheet with no versions" do
      user = user_fixture()
      project = project_fixture(user)
      sheet = sheet_fixture(project)

      assert Sheets.list_versions(sheet.id) == []
    end
  end

  describe "get_version/2" do
    test "returns version by sheet_id and version_number" do
      user = user_fixture()
      project = project_fixture(user)
      sheet = sheet_fixture(project)

      {:ok, created} = Sheets.create_version(sheet, user)

      version = Sheets.get_version(sheet.id, 1)

      assert version.id == created.id
      assert version.version_number == 1
    end

    test "returns nil for non-existent version" do
      user = user_fixture()
      project = project_fixture(user)
      sheet = sheet_fixture(project)

      assert Sheets.get_version(sheet.id, 999) == nil
    end

    test "returns nil for wrong sheet_id" do
      user = user_fixture()
      project = project_fixture(user)
      sheet1 = sheet_fixture(project)
      sheet2 = sheet_fixture(project)

      {:ok, _} = Sheets.create_version(sheet1, user)

      assert Sheets.get_version(sheet2.id, 1) == nil
    end
  end

  describe "get_latest_version/1" do
    test "returns the most recent version" do
      user = user_fixture()
      project = project_fixture(user)
      sheet = sheet_fixture(project)

      {:ok, _v1} = Sheets.create_version(sheet, user)
      {:ok, v2} = Sheets.create_version(sheet, user)

      latest = Sheets.get_latest_version(sheet.id)

      assert latest.id == v2.id
      assert latest.version_number == 2
    end

    test "returns nil for sheet with no versions" do
      user = user_fixture()
      project = project_fixture(user)
      sheet = sheet_fixture(project)

      assert Sheets.get_latest_version(sheet.id) == nil
    end
  end

  describe "count_versions/1" do
    test "returns correct count" do
      user = user_fixture()
      project = project_fixture(user)
      sheet = sheet_fixture(project)

      assert Sheets.count_versions(sheet.id) == 0

      {:ok, _} = Sheets.create_version(sheet, user)
      assert Sheets.count_versions(sheet.id) == 1

      {:ok, _} = Sheets.create_version(sheet, user)
      {:ok, _} = Sheets.create_version(sheet, user)
      assert Sheets.count_versions(sheet.id) == 3
    end
  end

  describe "restore_version/2" do
    test "restores sheet metadata from snapshot" do
      user = user_fixture()
      project = project_fixture(user)
      {:ok, sheet} = Sheets.create_sheet(project, %{name: "Original Name", shortcut: "original"})

      {:ok, version} = Sheets.create_version(sheet, user)

      # Change the sheet
      {:ok, updated_sheet} =
        Sheets.update_sheet(sheet, %{name: "Changed Name", shortcut: "changed"})

      # Restore to original version
      {:ok, restored} = Sheets.restore_version(updated_sheet, version)

      assert restored.name == "Original Name"
      assert restored.shortcut == "original"
    end

    test "deletes current blocks and recreates from snapshot" do
      user = user_fixture()
      project = project_fixture(user)
      sheet = sheet_fixture(project)
      _original_block = block_fixture(sheet, %{type: "text", value: %{"content" => "Original"}})

      {:ok, version} = Sheets.create_version(sheet, user)

      # Delete original block and add new one
      sheet = Sheets.get_sheet!(project.id, sheet.id)
      [original_block] = sheet.blocks
      {:ok, _} = Sheets.delete_block(original_block)
      _new_block = block_fixture(sheet, %{type: "number", value: %{"content" => 42}})

      # Restore
      sheet = Sheets.get_sheet!(project.id, sheet.id)
      {:ok, restored} = Sheets.restore_version(sheet, version)

      blocks = Sheets.list_blocks(restored.id)
      assert length(blocks) == 1
      assert Enum.at(blocks, 0).type == "text"
      assert Enum.at(blocks, 0).value["content"] == "Original"
    end

    test "sets current_version_id on sheet" do
      user = user_fixture()
      project = project_fixture(user)
      sheet = sheet_fixture(project)

      {:ok, version} = Sheets.create_version(sheet, user)

      {:ok, restored} = Sheets.restore_version(sheet, version)

      assert restored.current_version_id == version.id
    end

    test "handles empty blocks snapshot" do
      user = user_fixture()
      project = project_fixture(user)
      sheet = sheet_fixture(project)
      # No blocks created

      {:ok, version} = Sheets.create_version(sheet, user)

      # Add a block
      _block = block_fixture(sheet, %{type: "text"})

      # Restore to version with no blocks
      sheet = Sheets.get_sheet!(project.id, sheet.id)
      {:ok, restored} = Sheets.restore_version(sheet, version)

      assert Sheets.list_blocks(restored.id) == []
    end
  end

  describe "delete_version/1" do
    test "deletes the version" do
      user = user_fixture()
      project = project_fixture(user)
      sheet = sheet_fixture(project)

      {:ok, version} = Sheets.create_version(sheet, user)
      assert Sheets.count_versions(sheet.id) == 1

      {:ok, _} = Sheets.delete_version(version)
      assert Sheets.count_versions(sheet.id) == 0
    end

    test "clears current_version_id if deleted version was current" do
      user = user_fixture()
      project = project_fixture(user)
      sheet = sheet_fixture(project)

      {:ok, version} = Sheets.create_version(sheet, user)
      {:ok, sheet} = Sheets.set_current_version(sheet, version)
      assert sheet.current_version_id == version.id

      {:ok, _} = Sheets.delete_version(version)

      sheet = Sheets.get_sheet!(project.id, sheet.id)
      assert sheet.current_version_id == nil
    end

    test "does not affect current_version_id if deleted version was not current" do
      user = user_fixture()
      project = project_fixture(user)
      sheet = sheet_fixture(project)

      {:ok, v1} = Sheets.create_version(sheet, user)
      {:ok, v2} = Sheets.create_version(sheet, user)
      {:ok, sheet} = Sheets.set_current_version(sheet, v2)

      {:ok, _} = Sheets.delete_version(v1)

      sheet = Sheets.get_sheet!(project.id, sheet.id)
      assert sheet.current_version_id == v2.id
    end
  end

  describe "set_current_version/2" do
    test "sets current_version_id on sheet" do
      user = user_fixture()
      project = project_fixture(user)
      sheet = sheet_fixture(project)

      {:ok, version} = Sheets.create_version(sheet, user)
      {:ok, updated_sheet} = Sheets.set_current_version(sheet, version)

      assert updated_sheet.current_version_id == version.id
    end

    test "clears current_version_id when passed nil" do
      user = user_fixture()
      project = project_fixture(user)
      sheet = sheet_fixture(project)

      {:ok, version} = Sheets.create_version(sheet, user)
      {:ok, sheet} = Sheets.set_current_version(sheet, version)
      assert sheet.current_version_id == version.id

      {:ok, cleared_sheet} = Sheets.set_current_version(sheet, nil)
      assert cleared_sheet.current_version_id == nil
    end
  end

  describe "maybe_create_version/3" do
    test "creates version when no previous version exists" do
      user = user_fixture()
      project = project_fixture(user)
      sheet = sheet_fixture(project)

      result = Sheets.maybe_create_version(sheet, user)

      assert {:ok, %SheetVersion{}} = result
    end

    test "creates version when rate limit allows" do
      user = user_fixture()
      project = project_fixture(user)
      sheet = sheet_fixture(project)

      # Create first version
      {:ok, _} = Sheets.create_version(sheet, user)

      # Set min_interval to 0 to allow immediate creation
      result = Sheets.maybe_create_version(sheet, user, min_interval: 0)

      assert {:ok, version} = result
      assert version.version_number == 2
    end

    test "skips creation within rate limit interval" do
      user = user_fixture()
      project = project_fixture(user)
      sheet = sheet_fixture(project)

      # Create first version
      {:ok, _} = Sheets.create_version(sheet, user)

      # Try to create another with high interval (should skip)
      result = Sheets.maybe_create_version(sheet, user, min_interval: 99_999_999)

      assert {:skipped, :too_recent} = result
    end
  end

  describe "change summary generation" do
    test "detects name change" do
      user = user_fixture()
      project = project_fixture(user)
      {:ok, sheet} = Sheets.create_sheet(project, %{name: "Original"})

      {:ok, _v1} = Sheets.create_version(sheet, user)
      {:ok, sheet} = Sheets.update_sheet(sheet, %{name: "Changed"})
      {:ok, v2} = Sheets.create_version(sheet, user)

      assert v2.change_summary =~ "Renamed sheet"
    end

    test "detects shortcut change" do
      user = user_fixture()
      project = project_fixture(user)
      {:ok, sheet} = Sheets.create_sheet(project, %{name: "Test", shortcut: "original"})

      {:ok, _v1} = Sheets.create_version(sheet, user)
      {:ok, sheet} = Sheets.update_sheet(sheet, %{shortcut: "changed"})
      {:ok, v2} = Sheets.create_version(sheet, user)

      assert v2.change_summary =~ "Changed shortcut"
    end

    test "detects added blocks" do
      user = user_fixture()
      project = project_fixture(user)
      sheet = sheet_fixture(project)

      {:ok, _v1} = Sheets.create_version(sheet, user)
      _block = block_fixture(sheet)
      sheet = Sheets.get_sheet!(project.id, sheet.id)
      {:ok, v2} = Sheets.create_version(sheet, user)

      assert v2.change_summary =~ "Added 1 block"
    end

    test "detects removed blocks" do
      user = user_fixture()
      project = project_fixture(user)
      sheet = sheet_fixture(project)
      block = block_fixture(sheet)

      sheet = Sheets.get_sheet!(project.id, sheet.id)
      {:ok, _v1} = Sheets.create_version(sheet, user)
      {:ok, _} = Sheets.permanently_delete_block(block)
      sheet = Sheets.get_sheet!(project.id, sheet.id)
      {:ok, v2} = Sheets.create_version(sheet, user)

      assert v2.change_summary =~ "Removed 1 block"
    end

    test "detects modified blocks" do
      user = user_fixture()
      project = project_fixture(user)
      sheet = sheet_fixture(project)
      block = block_fixture(sheet, %{type: "text", value: %{"content" => "Original"}})

      sheet = Sheets.get_sheet!(project.id, sheet.id)
      {:ok, _v1} = Sheets.create_version(sheet, user)
      {:ok, _} = Sheets.update_block_value(block, %{"content" => "Modified"})
      sheet = Sheets.get_sheet!(project.id, sheet.id)
      {:ok, v2} = Sheets.create_version(sheet, user)

      assert v2.change_summary =~ "Modified 1 block"
    end

    test "shows 'No changes detected' when nothing changed" do
      user = user_fixture()
      project = project_fixture(user)
      sheet = sheet_fixture(project)

      {:ok, _v1} = Sheets.create_version(sheet, user)
      {:ok, v2} = Sheets.create_version(sheet, user)

      assert v2.change_summary =~ "No changes detected"
    end
  end
end
