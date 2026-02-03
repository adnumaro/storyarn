defmodule Storyarn.Pages.VersioningTest do
  use Storyarn.DataCase

  alias Storyarn.Pages
  alias Storyarn.Pages.PageVersion

  import Storyarn.AccountsFixtures
  import Storyarn.PagesFixtures
  import Storyarn.ProjectsFixtures

  describe "create_version/3" do
    test "creates version with correct snapshot" do
      user = user_fixture()
      project = project_fixture(user)
      page = page_fixture(project, %{name: "Test Page", shortcut: "test-page"})

      _block1 =
        block_fixture(page, %{
          type: "text",
          config: %{"label" => "Name"},
          value: %{"content" => "John"}
        })

      _block2 =
        block_fixture(page, %{
          type: "number",
          config: %{"label" => "Age"},
          value: %{"content" => 30}
        })

      {:ok, version} = Pages.create_version(page, user)

      assert version.page_id == page.id
      assert version.version_number == 1
      assert version.changed_by_id == user.id
      assert version.snapshot["name"] == "Test Page"
      assert version.snapshot["shortcut"] == "test-page"
      assert length(version.snapshot["blocks"]) == 2
    end

    test "increments version number" do
      user = user_fixture()
      project = project_fixture(user)
      page = page_fixture(project)

      {:ok, v1} = Pages.create_version(page, user)
      {:ok, v2} = Pages.create_version(page, user)
      {:ok, v3} = Pages.create_version(page, user)

      assert v1.version_number == 1
      assert v2.version_number == 2
      assert v3.version_number == 3
    end

    test "generates change summary for first version" do
      user = user_fixture()
      project = project_fixture(user)
      page = page_fixture(project)
      _block = block_fixture(page)

      {:ok, version} = Pages.create_version(page, user)

      assert version.change_summary =~ "Initial version"
      assert version.change_summary =~ "1 block"
    end

    test "includes all block data in snapshot" do
      user = user_fixture()
      project = project_fixture(user)
      page = page_fixture(project)

      {:ok, block} =
        Pages.create_block(page, %{
          type: "text",
          config: %{"label" => "Custom Label", "placeholder" => "Enter..."},
          value: %{"content" => "Test content"}
        })

      # Update block to set is_constant (variable_name is auto-generated from label)
      {:ok, _} = Pages.update_block(block, %{is_constant: true})

      # Reload page with blocks
      page = Pages.get_page!(project.id, page.id)
      {:ok, version} = Pages.create_version(page, user)

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
      page = page_fixture(project)

      {:ok, v1} = Pages.create_version(page, user)
      {:ok, v2} = Pages.create_version(page, user.id)

      assert v1.changed_by_id == user.id
      assert v2.changed_by_id == user.id
    end

    test "accepts custom title option" do
      user = user_fixture()
      project = project_fixture(user)
      page = page_fixture(project)

      {:ok, version} = Pages.create_version(page, user, title: "Manual save")

      assert version.title == "Manual save"
      assert version.change_summary == nil
    end

    test "accepts custom description option" do
      user = user_fixture()
      project = project_fixture(user)
      page = page_fixture(project)

      {:ok, version} = Pages.create_version(page, user, description: "Before major refactor")

      assert version.description == "Before major refactor"
    end
  end

  describe "list_versions/2" do
    test "returns versions ordered by version_number desc" do
      user = user_fixture()
      project = project_fixture(user)
      page = page_fixture(project)

      {:ok, _v1} = Pages.create_version(page, user)
      {:ok, _v2} = Pages.create_version(page, user)
      {:ok, _v3} = Pages.create_version(page, user)

      versions = Pages.list_versions(page.id)

      assert length(versions) == 3
      assert Enum.at(versions, 0).version_number == 3
      assert Enum.at(versions, 1).version_number == 2
      assert Enum.at(versions, 2).version_number == 1
    end

    test "respects limit option" do
      user = user_fixture()
      project = project_fixture(user)
      page = page_fixture(project)

      for _ <- 1..5, do: Pages.create_version(page, user)

      versions = Pages.list_versions(page.id, limit: 2)

      assert length(versions) == 2
      assert Enum.at(versions, 0).version_number == 5
      assert Enum.at(versions, 1).version_number == 4
    end

    test "respects offset option" do
      user = user_fixture()
      project = project_fixture(user)
      page = page_fixture(project)

      for _ <- 1..5, do: Pages.create_version(page, user)

      versions = Pages.list_versions(page.id, limit: 2, offset: 2)

      assert length(versions) == 2
      assert Enum.at(versions, 0).version_number == 3
      assert Enum.at(versions, 1).version_number == 2
    end

    test "preloads changed_by user" do
      user = user_fixture()
      project = project_fixture(user)
      page = page_fixture(project)

      {:ok, _} = Pages.create_version(page, user)

      [version] = Pages.list_versions(page.id)

      assert version.changed_by.id == user.id
      assert version.changed_by.email == user.email
    end

    test "returns empty list for page with no versions" do
      user = user_fixture()
      project = project_fixture(user)
      page = page_fixture(project)

      assert Pages.list_versions(page.id) == []
    end
  end

  describe "get_version/2" do
    test "returns version by page_id and version_number" do
      user = user_fixture()
      project = project_fixture(user)
      page = page_fixture(project)

      {:ok, created} = Pages.create_version(page, user)

      version = Pages.get_version(page.id, 1)

      assert version.id == created.id
      assert version.version_number == 1
    end

    test "returns nil for non-existent version" do
      user = user_fixture()
      project = project_fixture(user)
      page = page_fixture(project)

      assert Pages.get_version(page.id, 999) == nil
    end

    test "returns nil for wrong page_id" do
      user = user_fixture()
      project = project_fixture(user)
      page1 = page_fixture(project)
      page2 = page_fixture(project)

      {:ok, _} = Pages.create_version(page1, user)

      assert Pages.get_version(page2.id, 1) == nil
    end
  end

  describe "get_latest_version/1" do
    test "returns the most recent version" do
      user = user_fixture()
      project = project_fixture(user)
      page = page_fixture(project)

      {:ok, _v1} = Pages.create_version(page, user)
      {:ok, v2} = Pages.create_version(page, user)

      latest = Pages.get_latest_version(page.id)

      assert latest.id == v2.id
      assert latest.version_number == 2
    end

    test "returns nil for page with no versions" do
      user = user_fixture()
      project = project_fixture(user)
      page = page_fixture(project)

      assert Pages.get_latest_version(page.id) == nil
    end
  end

  describe "count_versions/1" do
    test "returns correct count" do
      user = user_fixture()
      project = project_fixture(user)
      page = page_fixture(project)

      assert Pages.count_versions(page.id) == 0

      {:ok, _} = Pages.create_version(page, user)
      assert Pages.count_versions(page.id) == 1

      {:ok, _} = Pages.create_version(page, user)
      {:ok, _} = Pages.create_version(page, user)
      assert Pages.count_versions(page.id) == 3
    end
  end

  describe "restore_version/2" do
    test "restores page metadata from snapshot" do
      user = user_fixture()
      project = project_fixture(user)
      {:ok, page} = Pages.create_page(project, %{name: "Original Name", shortcut: "original"})

      {:ok, version} = Pages.create_version(page, user)

      # Change the page
      {:ok, updated_page} = Pages.update_page(page, %{name: "Changed Name", shortcut: "changed"})

      # Restore to original version
      {:ok, restored} = Pages.restore_version(updated_page, version)

      assert restored.name == "Original Name"
      assert restored.shortcut == "original"
    end

    test "deletes current blocks and recreates from snapshot" do
      user = user_fixture()
      project = project_fixture(user)
      page = page_fixture(project)
      _original_block = block_fixture(page, %{type: "text", value: %{"content" => "Original"}})

      {:ok, version} = Pages.create_version(page, user)

      # Delete original block and add new one
      page = Pages.get_page!(project.id, page.id)
      [original_block] = page.blocks
      {:ok, _} = Pages.delete_block(original_block)
      _new_block = block_fixture(page, %{type: "number", value: %{"content" => 42}})

      # Restore
      page = Pages.get_page!(project.id, page.id)
      {:ok, restored} = Pages.restore_version(page, version)

      blocks = Pages.list_blocks(restored.id)
      assert length(blocks) == 1
      assert Enum.at(blocks, 0).type == "text"
      assert Enum.at(blocks, 0).value["content"] == "Original"
    end

    test "sets current_version_id on page" do
      user = user_fixture()
      project = project_fixture(user)
      page = page_fixture(project)

      {:ok, version} = Pages.create_version(page, user)

      {:ok, restored} = Pages.restore_version(page, version)

      assert restored.current_version_id == version.id
    end

    test "handles empty blocks snapshot" do
      user = user_fixture()
      project = project_fixture(user)
      page = page_fixture(project)
      # No blocks created

      {:ok, version} = Pages.create_version(page, user)

      # Add a block
      _block = block_fixture(page, %{type: "text"})

      # Restore to version with no blocks
      page = Pages.get_page!(project.id, page.id)
      {:ok, restored} = Pages.restore_version(page, version)

      assert Pages.list_blocks(restored.id) == []
    end
  end

  describe "delete_version/1" do
    test "deletes the version" do
      user = user_fixture()
      project = project_fixture(user)
      page = page_fixture(project)

      {:ok, version} = Pages.create_version(page, user)
      assert Pages.count_versions(page.id) == 1

      {:ok, _} = Pages.delete_version(version)
      assert Pages.count_versions(page.id) == 0
    end

    test "clears current_version_id if deleted version was current" do
      user = user_fixture()
      project = project_fixture(user)
      page = page_fixture(project)

      {:ok, version} = Pages.create_version(page, user)
      {:ok, page} = Pages.set_current_version(page, version)
      assert page.current_version_id == version.id

      {:ok, _} = Pages.delete_version(version)

      page = Pages.get_page!(project.id, page.id)
      assert page.current_version_id == nil
    end

    test "does not affect current_version_id if deleted version was not current" do
      user = user_fixture()
      project = project_fixture(user)
      page = page_fixture(project)

      {:ok, v1} = Pages.create_version(page, user)
      {:ok, v2} = Pages.create_version(page, user)
      {:ok, page} = Pages.set_current_version(page, v2)

      {:ok, _} = Pages.delete_version(v1)

      page = Pages.get_page!(project.id, page.id)
      assert page.current_version_id == v2.id
    end
  end

  describe "set_current_version/2" do
    test "sets current_version_id on page" do
      user = user_fixture()
      project = project_fixture(user)
      page = page_fixture(project)

      {:ok, version} = Pages.create_version(page, user)
      {:ok, updated_page} = Pages.set_current_version(page, version)

      assert updated_page.current_version_id == version.id
    end

    test "clears current_version_id when passed nil" do
      user = user_fixture()
      project = project_fixture(user)
      page = page_fixture(project)

      {:ok, version} = Pages.create_version(page, user)
      {:ok, page} = Pages.set_current_version(page, version)
      assert page.current_version_id == version.id

      {:ok, cleared_page} = Pages.set_current_version(page, nil)
      assert cleared_page.current_version_id == nil
    end
  end

  describe "maybe_create_version/3" do
    test "creates version when no previous version exists" do
      user = user_fixture()
      project = project_fixture(user)
      page = page_fixture(project)

      result = Pages.maybe_create_version(page, user)

      assert {:ok, %PageVersion{}} = result
    end

    test "creates version when rate limit allows" do
      user = user_fixture()
      project = project_fixture(user)
      page = page_fixture(project)

      # Create first version
      {:ok, _} = Pages.create_version(page, user)

      # Set min_interval to 0 to allow immediate creation
      result = Pages.maybe_create_version(page, user, min_interval: 0)

      assert {:ok, version} = result
      assert version.version_number == 2
    end

    test "skips creation within rate limit interval" do
      user = user_fixture()
      project = project_fixture(user)
      page = page_fixture(project)

      # Create first version
      {:ok, _} = Pages.create_version(page, user)

      # Try to create another with high interval (should skip)
      result = Pages.maybe_create_version(page, user, min_interval: 99_999_999)

      assert {:skipped, :too_recent} = result
    end
  end

  describe "change summary generation" do
    test "detects name change" do
      user = user_fixture()
      project = project_fixture(user)
      {:ok, page} = Pages.create_page(project, %{name: "Original"})

      {:ok, _v1} = Pages.create_version(page, user)
      {:ok, page} = Pages.update_page(page, %{name: "Changed"})
      {:ok, v2} = Pages.create_version(page, user)

      assert v2.change_summary =~ "Renamed page"
    end

    test "detects shortcut change" do
      user = user_fixture()
      project = project_fixture(user)
      {:ok, page} = Pages.create_page(project, %{name: "Test", shortcut: "original"})

      {:ok, _v1} = Pages.create_version(page, user)
      {:ok, page} = Pages.update_page(page, %{shortcut: "changed"})
      {:ok, v2} = Pages.create_version(page, user)

      assert v2.change_summary =~ "Changed shortcut"
    end

    test "detects added blocks" do
      user = user_fixture()
      project = project_fixture(user)
      page = page_fixture(project)

      {:ok, _v1} = Pages.create_version(page, user)
      _block = block_fixture(page)
      page = Pages.get_page!(project.id, page.id)
      {:ok, v2} = Pages.create_version(page, user)

      assert v2.change_summary =~ "Added 1 block"
    end

    test "detects removed blocks" do
      user = user_fixture()
      project = project_fixture(user)
      page = page_fixture(project)
      block = block_fixture(page)

      page = Pages.get_page!(project.id, page.id)
      {:ok, _v1} = Pages.create_version(page, user)
      {:ok, _} = Pages.permanently_delete_block(block)
      page = Pages.get_page!(project.id, page.id)
      {:ok, v2} = Pages.create_version(page, user)

      assert v2.change_summary =~ "Removed 1 block"
    end

    test "detects modified blocks" do
      user = user_fixture()
      project = project_fixture(user)
      page = page_fixture(project)
      block = block_fixture(page, %{type: "text", value: %{"content" => "Original"}})

      page = Pages.get_page!(project.id, page.id)
      {:ok, _v1} = Pages.create_version(page, user)
      {:ok, _} = Pages.update_block_value(block, %{"content" => "Modified"})
      page = Pages.get_page!(project.id, page.id)
      {:ok, v2} = Pages.create_version(page, user)

      assert v2.change_summary =~ "Modified 1 block"
    end

    test "shows 'No changes detected' when nothing changed" do
      user = user_fixture()
      project = project_fixture(user)
      page = page_fixture(project)

      {:ok, _v1} = Pages.create_version(page, user)
      {:ok, v2} = Pages.create_version(page, user)

      assert v2.change_summary =~ "No changes detected"
    end
  end
end
