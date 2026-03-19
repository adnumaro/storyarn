defmodule Storyarn.Sheets.AvatarCrudTest do
  use Storyarn.DataCase, async: true

  alias Storyarn.Sheets

  import Storyarn.AccountsFixtures
  import Storyarn.AssetsFixtures
  import Storyarn.ProjectsFixtures
  import Storyarn.SheetsFixtures

  setup do
    user = user_fixture()
    project = project_fixture(user)
    sheet = sheet_fixture(project)
    asset1 = image_asset_fixture(project, user, %{filename: "happy.png"})
    asset2 = image_asset_fixture(project, user, %{filename: "angry.png"})
    asset3 = image_asset_fixture(project, user, %{filename: "sad.png"})

    %{project: project, sheet: sheet, user: user, asset1: asset1, asset2: asset2, asset3: asset3}
  end

  describe "add_avatar/3" do
    test "first avatar is set as default at position 0", %{sheet: sheet, asset1: asset1} do
      assert {:ok, avatar} = Sheets.add_avatar(sheet, asset1.id)
      assert avatar.is_default == true
      assert avatar.position == 0
      assert avatar.sheet_id == sheet.id
      assert avatar.asset_id == asset1.id
    end

    test "subsequent avatars are not default with incrementing position", %{
      sheet: sheet,
      asset1: asset1,
      asset2: asset2
    } do
      {:ok, _} = Sheets.add_avatar(sheet, asset1.id)
      {:ok, second} = Sheets.add_avatar(sheet, asset2.id)

      assert second.is_default == false
      assert second.position == 1
    end

    test "applies variablify to name", %{sheet: sheet, asset1: asset1} do
      {:ok, avatar} = Sheets.add_avatar(sheet, asset1.id, %{name: "Happy Face"})
      assert avatar.name == "happy_face"
    end

    test "accepts notes", %{sheet: sheet, asset1: asset1} do
      {:ok, avatar} = Sheets.add_avatar(sheet, asset1.id, %{notes: "Smiling expression"})
      assert avatar.notes == "Smiling expression"
    end

    test "rejects duplicate asset for same sheet", %{sheet: sheet, asset1: asset1} do
      {:ok, _} = Sheets.add_avatar(sheet, asset1.id)
      assert {:error, _changeset} = Sheets.add_avatar(sheet, asset1.id)
    end

    test "allows same asset on different sheets", %{project: project, sheet: sheet, asset1: asset1} do
      other_sheet = sheet_fixture(project, %{name: "Other"})
      {:ok, _} = Sheets.add_avatar(sheet, asset1.id)
      assert {:ok, _} = Sheets.add_avatar(other_sheet, asset1.id)
    end
  end

  describe "list_avatars/1" do
    test "returns avatars ordered by position with preloaded asset", %{
      sheet: sheet,
      asset1: asset1,
      asset2: asset2,
      asset3: asset3
    } do
      {:ok, _} = Sheets.add_avatar(sheet, asset1.id)
      {:ok, _} = Sheets.add_avatar(sheet, asset2.id)
      {:ok, _} = Sheets.add_avatar(sheet, asset3.id)

      avatars = Sheets.list_avatars(sheet.id)
      assert length(avatars) == 3
      assert Enum.map(avatars, & &1.position) == [0, 1, 2]
      assert Enum.all?(avatars, &(&1.asset.id != nil))
    end

    test "returns empty list for sheet without avatars", %{project: project} do
      other_sheet = sheet_fixture(project, %{name: "Empty"})
      assert Sheets.list_avatars(other_sheet.id) == []
    end
  end

  describe "get_avatar/1" do
    test "returns avatar with preloaded asset", %{sheet: sheet, asset1: asset1} do
      {:ok, created} = Sheets.add_avatar(sheet, asset1.id)
      avatar = Sheets.get_avatar(created.id)
      assert avatar.id == created.id
      assert avatar.asset.id == asset1.id
    end

    test "returns nil for non-existent id" do
      assert Sheets.get_avatar(0) == nil
    end
  end

  describe "get_default_avatar/1" do
    test "returns the default avatar", %{sheet: sheet, asset1: asset1, asset2: asset2} do
      {:ok, _} = Sheets.add_avatar(sheet, asset1.id)
      {:ok, _} = Sheets.add_avatar(sheet, asset2.id)

      default = Sheets.get_default_avatar(sheet.id)
      assert default.asset_id == asset1.id
      assert default.is_default == true
    end

    test "returns nil when no avatars exist", %{project: project} do
      other_sheet = sheet_fixture(project, %{name: "No Avatar"})
      assert Sheets.get_default_avatar(other_sheet.id) == nil
    end
  end

  describe "set_avatar_default/1" do
    test "changes default to specified avatar and unsets previous", %{
      sheet: sheet,
      asset1: asset1,
      asset2: asset2
    } do
      {:ok, first} = Sheets.add_avatar(sheet, asset1.id)
      {:ok, second} = Sheets.add_avatar(sheet, asset2.id)

      {:ok, updated} = Sheets.set_avatar_default(second)
      assert updated.is_default == true

      reloaded_first = Sheets.get_avatar(first.id)
      assert reloaded_first.is_default == false
    end

    test "is idempotent when already default", %{sheet: sheet, asset1: asset1} do
      {:ok, avatar} = Sheets.add_avatar(sheet, asset1.id)
      assert avatar.is_default == true

      {:ok, same} = Sheets.set_avatar_default(avatar)
      assert same.is_default == true
    end
  end

  describe "remove_avatar/1" do
    test "removes default avatar and promotes next", %{
      sheet: sheet,
      asset1: asset1,
      asset2: asset2
    } do
      {:ok, first} = Sheets.add_avatar(sheet, asset1.id)
      {:ok, _} = Sheets.add_avatar(sheet, asset2.id)

      assert {:ok, _} = Sheets.remove_avatar(first.id)

      remaining = Sheets.list_avatars(sheet.id)
      assert length(remaining) == 1
      assert hd(remaining).is_default == true
    end

    test "removes non-default avatar without affecting default", %{
      sheet: sheet,
      asset1: asset1,
      asset2: asset2
    } do
      {:ok, first} = Sheets.add_avatar(sheet, asset1.id)
      {:ok, second} = Sheets.add_avatar(sheet, asset2.id)

      assert {:ok, _} = Sheets.remove_avatar(second.id)

      remaining = Sheets.list_avatars(sheet.id)
      assert length(remaining) == 1
      assert hd(remaining).id == first.id
      assert hd(remaining).is_default == true
    end

    test "removes last avatar gracefully", %{sheet: sheet, asset1: asset1} do
      {:ok, avatar} = Sheets.add_avatar(sheet, asset1.id)

      assert {:ok, _} = Sheets.remove_avatar(avatar.id)
      assert Sheets.list_avatars(sheet.id) == []
      assert Sheets.get_default_avatar(sheet.id) == nil
    end

    test "returns error for non-existent id" do
      assert {:error, :not_found} = Sheets.remove_avatar(0)
    end
  end

  describe "update_avatar/2" do
    test "updates name with variablify and notes", %{sheet: sheet, asset1: asset1} do
      {:ok, avatar} = Sheets.add_avatar(sheet, asset1.id)

      {:ok, updated} = Sheets.update_avatar(avatar, %{name: "Angry Face", notes: "Used in combat"})
      assert updated.name == "angry_face"
      assert updated.notes == "Used in combat"
    end

    test "clears name with nil", %{sheet: sheet, asset1: asset1} do
      {:ok, avatar} = Sheets.add_avatar(sheet, asset1.id, %{name: "happy"})

      {:ok, updated} = Sheets.update_avatar(avatar, %{name: nil})
      assert updated.name == nil
    end
  end

  describe "reorder_avatars/2" do
    test "reorders by given ID list", %{
      sheet: sheet,
      asset1: asset1,
      asset2: asset2,
      asset3: asset3
    } do
      {:ok, a1} = Sheets.add_avatar(sheet, asset1.id)
      {:ok, a2} = Sheets.add_avatar(sheet, asset2.id)
      {:ok, a3} = Sheets.add_avatar(sheet, asset3.id)

      {:ok, _} = Sheets.reorder_avatars(sheet.id, [a3.id, a1.id, a2.id])

      avatars = Sheets.list_avatars(sheet.id)
      assert Enum.map(avatars, & &1.id) == [a3.id, a1.id, a2.id]
    end
  end

  describe "batch_load_avatars_by_sheet/1" do
    test "groups avatars by sheet_id with preloaded assets", %{
      project: project,
      sheet: sheet,
      asset1: asset1
    } do
      {:ok, _} = Sheets.add_avatar(sheet, asset1.id)

      result = Sheets.batch_load_avatars_by_sheet(project.id)
      assert Map.has_key?(result, sheet.id)
      assert length(result[sheet.id]) == 1
      assert hd(result[sheet.id]).asset != nil
    end

    test "excludes soft-deleted sheets", %{project: project, asset1: asset1} do
      deleted_sheet = sheet_fixture(project, %{name: "Deleted"})
      {:ok, _} = Sheets.add_avatar(deleted_sheet, asset1.id)

      Ecto.Changeset.change(deleted_sheet, deleted_at: Storyarn.Shared.TimeHelpers.now())
      |> Storyarn.Repo.update!()

      result = Sheets.batch_load_avatars_by_sheet(project.id)
      refute Map.has_key?(result, deleted_sheet.id)
    end

    test "returns empty map for project without avatars" do
      empty_project = project_fixture()
      assert Sheets.batch_load_avatars_by_sheet(empty_project.id) == %{}
    end
  end
end
