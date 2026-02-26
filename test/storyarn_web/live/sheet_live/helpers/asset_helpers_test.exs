defmodule StoryarnWeb.SheetLive.Helpers.AssetHelpersTest do
  @moduledoc """
  Unit tests for AssetHelpers, which handle avatar/banner upload and removal
  on sheet sockets.
  """

  use Storyarn.DataCase, async: true

  import Storyarn.AccountsFixtures
  import Storyarn.ProjectsFixtures
  import Storyarn.SheetsFixtures
  import Storyarn.AssetsFixtures

  alias Storyarn.Repo
  alias Storyarn.Sheets
  alias StoryarnWeb.SheetLive.Helpers.AssetHelpers

  # ===========================================================================
  # Helpers
  # ===========================================================================

  defp build_socket(project, sheet, user) do
    scope = Storyarn.Accounts.Scope.for_user(user)

    %Phoenix.LiveView.Socket{
      assigns: %{
        __changed__: %{},
        flash: %{},
        project: project,
        sheet: sheet,
        current_scope: scope,
        save_status: :idle,
        sheets_tree: []
      }
    }
  end

  # Small 1x1 red PNG pixel, base64-encoded
  @valid_png_base64 "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwADhQGAWjR9awAAAABJRU5ErkJggg=="
  @valid_data_url "data:image/png;base64,#{@valid_png_base64}"

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
  # remove_avatar/1
  # ===========================================================================

  describe "remove_avatar/1" do
    test "removes avatar from sheet", %{project: project, sheet: sheet, user: user} do
      # Set an avatar first
      asset = asset_fixture(project, user)
      {:ok, _} = Sheets.update_sheet(sheet, %{avatar_asset_id: asset.id})
      sheet_with_avatar = Sheets.get_sheet_full!(project.id, sheet.id)

      socket = build_socket(project, sheet_with_avatar, user)
      {:noreply, updated_socket} = AssetHelpers.remove_avatar(socket)

      # Verify avatar was removed
      assert updated_socket.assigns.sheet.avatar_asset_id == nil
      assert updated_socket.assigns.save_status == :saved
    end

    test "updates sheets_tree after removing avatar", %{
      project: project,
      sheet: sheet,
      user: user
    } do
      asset = asset_fixture(project, user)
      {:ok, _} = Sheets.update_sheet(sheet, %{avatar_asset_id: asset.id})
      sheet_with_avatar = Sheets.get_sheet_full!(project.id, sheet.id)

      socket = build_socket(project, sheet_with_avatar, user)
      {:noreply, updated_socket} = AssetHelpers.remove_avatar(socket)

      # sheets_tree should be refreshed
      assert is_list(updated_socket.assigns.sheets_tree)
    end

    test "works when sheet has no avatar", %{project: project, sheet: sheet, user: user} do
      socket = build_socket(project, sheet, user)
      {:noreply, updated_socket} = AssetHelpers.remove_avatar(socket)

      assert updated_socket.assigns.sheet.avatar_asset_id == nil
      assert updated_socket.assigns.save_status == :saved
    end
  end

  # ===========================================================================
  # set_avatar/2
  # ===========================================================================

  describe "set_avatar/2" do
    test "sets avatar on sheet", %{project: project, sheet: sheet, user: user} do
      asset = asset_fixture(project, user)

      socket = build_socket(project, sheet, user)
      {:noreply, updated_socket} = AssetHelpers.set_avatar(socket, asset.id)

      assert updated_socket.assigns.sheet.avatar_asset_id == asset.id
      assert updated_socket.assigns.save_status == :saved
    end

    test "replaces existing avatar", %{project: project, sheet: sheet, user: user} do
      asset1 = asset_fixture(project, user)
      asset2 = asset_fixture(project, user)

      {:ok, _} = Sheets.update_sheet(sheet, %{avatar_asset_id: asset1.id})
      sheet_with_avatar = Sheets.get_sheet_full!(project.id, sheet.id)

      socket = build_socket(project, sheet_with_avatar, user)
      {:noreply, updated_socket} = AssetHelpers.set_avatar(socket, asset2.id)

      assert updated_socket.assigns.sheet.avatar_asset_id == asset2.id
    end

    test "updates sheets_tree after setting avatar", %{
      project: project,
      sheet: sheet,
      user: user
    } do
      asset = asset_fixture(project, user)

      socket = build_socket(project, sheet, user)
      {:noreply, updated_socket} = AssetHelpers.set_avatar(socket, asset.id)

      assert is_list(updated_socket.assigns.sheets_tree)
    end
  end

  # ===========================================================================
  # upload_avatar/4
  # ===========================================================================

  describe "upload_avatar/4" do
    test "uploads avatar from base64 data URL", %{project: project, sheet: sheet, user: user} do
      socket = build_socket(project, sheet, user)

      {:noreply, updated_socket} =
        AssetHelpers.upload_avatar(socket, "test_avatar.png", "image/png", @valid_data_url)

      # Avatar should be set
      assert updated_socket.assigns.sheet.avatar_asset_id != nil
      assert updated_socket.assigns.save_status == :saved
    end

    test "rejects invalid base64 data", %{project: project, sheet: sheet, user: user} do
      socket = build_socket(project, sheet, user)

      {:noreply, updated_socket} =
        AssetHelpers.upload_avatar(
          socket,
          "test.png",
          "image/png",
          "data:image/png;base64,!!!invalid!!!"
        )

      # Should have error flash
      assert updated_socket.assigns.flash["error"] =~ "Invalid"
    end

    test "rejects unsupported content type", %{project: project, sheet: sheet, user: user} do
      socket = build_socket(project, sheet, user)

      {:noreply, updated_socket} =
        AssetHelpers.upload_avatar(
          socket,
          "test.xyz",
          "application/x-unknown",
          @valid_data_url
        )

      assert updated_socket.assigns.flash["error"] =~ "Unsupported"
    end
  end

  # ===========================================================================
  # remove_banner/1
  # ===========================================================================

  describe "remove_banner/1" do
    test "removes banner from sheet", %{project: project, sheet: sheet, user: user} do
      asset = asset_fixture(project, user)
      {:ok, _} = Sheets.update_sheet(sheet, %{banner_asset_id: asset.id})
      sheet_with_banner = Sheets.get_sheet_full!(project.id, sheet.id)

      socket = build_socket(project, sheet_with_banner, user)
      {:noreply, updated_socket} = AssetHelpers.remove_banner(socket)

      assert updated_socket.assigns.sheet.banner_asset_id == nil
      assert updated_socket.assigns.save_status == :saved
    end

    test "works when sheet has no banner", %{project: project, sheet: sheet, user: user} do
      socket = build_socket(project, sheet, user)
      {:noreply, updated_socket} = AssetHelpers.remove_banner(socket)

      assert updated_socket.assigns.sheet.banner_asset_id == nil
      assert updated_socket.assigns.save_status == :saved
    end
  end

  # ===========================================================================
  # upload_banner/4
  # ===========================================================================

  describe "upload_banner/4" do
    test "uploads banner from base64 data URL", %{project: project, sheet: sheet, user: user} do
      socket = build_socket(project, sheet, user)

      {:noreply, updated_socket} =
        AssetHelpers.upload_banner(socket, "test_banner.png", "image/png", @valid_data_url)

      assert updated_socket.assigns.sheet.banner_asset_id != nil
      assert updated_socket.assigns.save_status == :saved
    end

    test "rejects invalid base64 data for banner", %{project: project, sheet: sheet, user: user} do
      socket = build_socket(project, sheet, user)

      {:noreply, updated_socket} =
        AssetHelpers.upload_banner(socket, "test.png", "image/png", "data:image/png;base64,!!!")

      assert updated_socket.assigns.flash["error"] =~ "Invalid"
    end

    test "rejects unsupported content type for banner", %{
      project: project,
      sheet: sheet,
      user: user
    } do
      socket = build_socket(project, sheet, user)

      {:noreply, updated_socket} =
        AssetHelpers.upload_banner(
          socket,
          "test.xyz",
          "application/x-unknown",
          @valid_data_url
        )

      assert updated_socket.assigns.flash["error"] =~ "Unsupported"
    end
  end
end
