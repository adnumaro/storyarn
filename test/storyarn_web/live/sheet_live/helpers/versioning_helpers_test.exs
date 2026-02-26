defmodule StoryarnWeb.SheetLive.Helpers.VersioningHelpersTest do
  @moduledoc """
  Unit tests for VersioningHelpers, which handle version create, restore,
  delete, and pagination on sheet sockets.
  """

  use Storyarn.DataCase, async: true

  import Storyarn.AccountsFixtures
  import Storyarn.ProjectsFixtures
  import Storyarn.SheetsFixtures

  alias Storyarn.Repo
  alias Storyarn.Sheets
  alias StoryarnWeb.SheetLive.Helpers.VersioningHelpers

  # ===========================================================================
  # Helpers
  # ===========================================================================

  defp build_socket(project, sheet, user, extra_assigns \\ %{}) do
    scope = Storyarn.Accounts.Scope.for_user(user)

    base_assigns = %{
      __changed__: %{},
      flash: %{},
      project: project,
      sheet: sheet,
      current_scope: scope,
      save_status: :idle,
      sheets_tree: [],
      versions: nil,
      versions_page: 1,
      has_more_versions: false,
      show_create_version_modal: false
    }

    %Phoenix.LiveView.Socket{
      assigns: Map.merge(base_assigns, extra_assigns)
    }
  end

  # ===========================================================================
  # Setup
  # ===========================================================================

  setup do
    user = user_fixture()
    project = project_fixture(user) |> Repo.preload(:workspace)
    sheet = sheet_fixture(project)
    sheet_full = Sheets.get_sheet_full!(project.id, sheet.id)

    %{user: user, project: project, sheet: sheet_full}
  end

  # ===========================================================================
  # create_version/3
  # ===========================================================================

  describe "create_version/3" do
    test "creates a version with title and description", %{
      project: project,
      sheet: sheet,
      user: user
    } do
      socket = build_socket(project, sheet, user)

      {:noreply, updated_socket} =
        VersioningHelpers.create_version(socket, "v1 title", "v1 description")

      assert updated_socket.assigns.flash["info"] =~ "Version created"
      assert updated_socket.assigns.show_create_version_modal == false

      # Versions should be loaded
      assert is_list(updated_socket.assigns.versions)
      assert length(updated_socket.assigns.versions) == 1

      # Sheet should have current_version set
      assert updated_socket.assigns.sheet.current_version_id != nil
    end

    test "creates a version with empty title (becomes nil)", %{
      project: project,
      sheet: sheet,
      user: user
    } do
      socket = build_socket(project, sheet, user)

      {:noreply, updated_socket} = VersioningHelpers.create_version(socket, "", "")

      assert updated_socket.assigns.flash["info"] =~ "Version created"
      assert length(updated_socket.assigns.versions) == 1

      version = hd(updated_socket.assigns.versions)
      assert version.title == nil
      assert version.description == nil
    end

    test "creates multiple versions", %{project: project, sheet: sheet, user: user} do
      socket = build_socket(project, sheet, user)

      {:noreply, socket2} = VersioningHelpers.create_version(socket, "v1", "")
      {:noreply, socket3} = VersioningHelpers.create_version(socket2, "v2", "")

      assert length(socket3.assigns.versions) == 2
    end
  end

  # ===========================================================================
  # restore_version/2
  # ===========================================================================

  describe "restore_version/2" do
    test "restores sheet to a specific version", %{project: project, sheet: sheet, user: user} do
      # Create a version
      {:ok, version} = Sheets.create_version(sheet, user.id, title: "Original")

      # Change the sheet name
      {:ok, _} = Sheets.update_sheet(sheet, %{name: "Modified Name"})
      modified_sheet = Sheets.get_sheet_full!(project.id, sheet.id)

      socket = build_socket(project, modified_sheet, user)

      {:noreply, updated_socket} =
        VersioningHelpers.restore_version(socket, to_string(version.version_number))

      assert updated_socket.assigns.flash["info"] =~ "Restored to version"
      assert updated_socket.assigns.save_status == :saved
    end

    test "returns error for non-existent version", %{project: project, sheet: sheet, user: user} do
      socket = build_socket(project, sheet, user)

      {:noreply, updated_socket} = VersioningHelpers.restore_version(socket, "9999")

      assert updated_socket.assigns.flash["error"] =~ "Version not found"
    end

    test "updates blocks after restore", %{project: project, sheet: sheet, user: user} do
      # Create a block, then create a version
      _block = block_fixture(sheet, %{type: "text", config: %{"label" => "Field 1"}})
      {:ok, version} = Sheets.create_version(sheet, user.id, title: "With block")

      socket = build_socket(project, sheet, user)

      {:noreply, updated_socket} =
        VersioningHelpers.restore_version(socket, to_string(version.version_number))

      # Should have blocks reloaded
      assert is_list(updated_socket.assigns.blocks)
    end
  end

  # ===========================================================================
  # delete_version/2
  # ===========================================================================

  describe "delete_version/2" do
    test "deletes a version", %{project: project, sheet: sheet, user: user} do
      {:ok, version} = Sheets.create_version(sheet, user.id, title: "To Delete")

      socket =
        build_socket(project, sheet, user, %{
          versions: [version]
        })

      {:noreply, updated_socket} =
        VersioningHelpers.delete_version(socket, to_string(version.version_number))

      assert updated_socket.assigns.flash["info"] =~ "Version deleted"
      assert updated_socket.assigns.versions == []
    end

    test "returns error for non-existent version", %{project: project, sheet: sheet, user: user} do
      socket = build_socket(project, sheet, user)

      {:noreply, updated_socket} = VersioningHelpers.delete_version(socket, "9999")

      assert updated_socket.assigns.flash["error"] =~ "Version not found"
    end

    test "refreshes sheet after deleting current version", %{
      project: project,
      sheet: sheet,
      user: user
    } do
      {:ok, version} = Sheets.create_version(sheet, user.id, title: "Current")
      {:ok, _} = Sheets.set_current_version(sheet, version)
      updated_sheet = Sheets.get_sheet_full!(project.id, sheet.id)

      socket =
        build_socket(project, updated_sheet, user, %{
          versions: [version]
        })

      {:noreply, updated_socket} =
        VersioningHelpers.delete_version(socket, to_string(version.version_number))

      assert updated_socket.assigns.flash["info"] =~ "Version deleted"
      # Sheet should be refreshed
      assert updated_socket.assigns.sheet != nil
    end
  end

  # ===========================================================================
  # load_versions/2
  # ===========================================================================

  describe "load_versions/2" do
    test "loads versions for page 1", %{project: project, sheet: sheet, user: user} do
      {:ok, _v1} = Sheets.create_version(sheet, user.id, title: "v1")
      {:ok, _v2} = Sheets.create_version(sheet, user.id, title: "v2")

      socket = build_socket(project, sheet, user)

      updated_socket = VersioningHelpers.load_versions(socket, 1)

      assert is_list(updated_socket.assigns.versions)
      assert length(updated_socket.assigns.versions) == 2
      assert updated_socket.assigns.versions_page == 1
      assert updated_socket.assigns.has_more_versions == false
    end

    test "returns empty list when no versions exist", %{
      project: project,
      sheet: sheet,
      user: user
    } do
      socket = build_socket(project, sheet, user)

      updated_socket = VersioningHelpers.load_versions(socket, 1)

      assert updated_socket.assigns.versions == []
      assert updated_socket.assigns.has_more_versions == false
    end

    test "appends versions for page > 1", %{project: project, sheet: sheet, user: user} do
      {:ok, v1} = Sheets.create_version(sheet, user.id, title: "v1")

      existing_versions = [v1]

      socket =
        build_socket(project, sheet, user, %{
          versions: existing_versions
        })

      updated_socket = VersioningHelpers.load_versions(socket, 2)

      # Page 2 with no additional versions should still have the existing ones
      assert updated_socket.assigns.versions_page == 2
    end
  end

  # ===========================================================================
  # load_more_versions/1
  # ===========================================================================

  # ===========================================================================
  # restore_version/2 with reference blocks
  # ===========================================================================

  describe "restore_version with reference blocks" do
    test "handles reference blocks during restore", %{project: project, sheet: sheet, user: user} do
      # Create a reference block that will exercise add_reference_target for type "reference"
      {:ok, ref_block} =
        Sheets.create_block(sheet, %{
          type: "reference",
          config: %{"label" => "Ref Block"},
          value: %{"target_type" => "sheet", "target_id" => nil}
        })

      assert ref_block.type == "reference"

      # Reload sheet to ensure blocks are fresh for snapshot
      fresh_sheet = Sheets.get_sheet_full!(project.id, sheet.id)

      # Create a version with the reference block present
      {:ok, version} = Sheets.create_version(fresh_sheet, user.id, title: "With ref block")

      socket = build_socket(project, fresh_sheet, user)

      {:noreply, updated_socket} =
        VersioningHelpers.restore_version(socket, to_string(version.version_number))

      assert updated_socket.assigns.flash["info"] =~ "Restored to version"
      # Blocks should be loaded and include reference_target
      assert is_list(updated_socket.assigns.blocks)

      ref = Enum.find(updated_socket.assigns.blocks, &(&1.type == "reference"))
      assert ref != nil
      assert Map.has_key?(ref, :reference_target)
    end

    test "handles non-reference blocks during restore", %{
      project: project,
      sheet: sheet,
      user: user
    } do
      # Create a text block (non-reference)
      _block = block_fixture(sheet, %{type: "text", config: %{"label" => "Text Block"}})

      # Reload sheet to ensure blocks are fresh for snapshot
      fresh_sheet = Sheets.get_sheet_full!(project.id, sheet.id)

      {:ok, version} = Sheets.create_version(fresh_sheet, user.id, title: "With text block")

      socket = build_socket(project, fresh_sheet, user)

      {:noreply, updated_socket} =
        VersioningHelpers.restore_version(socket, to_string(version.version_number))

      assert updated_socket.assigns.flash["info"] =~ "Restored to version"
      text_block = Enum.find(updated_socket.assigns.blocks, &(&1.type == "text"))
      assert text_block != nil
      assert text_block.reference_target == nil
    end
  end

  # ===========================================================================
  # load_more_versions/1
  # ===========================================================================

  describe "load_more_versions/1" do
    test "increments page and loads versions", %{project: project, sheet: sheet, user: user} do
      {:ok, _v1} = Sheets.create_version(sheet, user.id, title: "v1")

      socket =
        build_socket(project, sheet, user, %{
          versions: [],
          versions_page: 1
        })

      {:noreply, updated_socket} = VersioningHelpers.load_more_versions(socket)

      assert updated_socket.assigns.versions_page == 2
    end
  end
end
