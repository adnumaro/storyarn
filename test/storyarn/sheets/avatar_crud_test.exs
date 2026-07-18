defmodule Storyarn.Sheets.AvatarCrudTest do
  use Storyarn.DataCase, async: true

  import Storyarn.AccountsFixtures
  import Storyarn.AssetsFixtures
  import Storyarn.FlowsFixtures
  import Storyarn.ProjectsFixtures
  import Storyarn.SheetsFixtures

  alias Storyarn.Flows
  alias Storyarn.Flows.FlowNode
  alias Storyarn.Repo
  alias Storyarn.Shared.TimeHelpers
  alias Storyarn.Sheets

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

    test "allows same asset on different sheets", %{
      project: project,
      sheet: sheet,
      asset1: asset1
    } do
      other_sheet = sheet_fixture(project, %{name: "Other"})
      {:ok, _} = Sheets.add_avatar(sheet, asset1.id)
      assert {:ok, _} = Sheets.add_avatar(other_sheet, asset1.id)
    end

    test "rejects a same-project non-image asset", %{
      project: project,
      sheet: sheet,
      user: user
    } do
      audio = audio_asset_fixture(project, user)

      assert {:error, {:invalid_asset_content_type, :avatar_asset_id, audio_id}} =
               Sheets.add_avatar(sheet, audio.id)

      assert audio_id == audio.id
      assert Sheets.list_avatars(sheet.id) == []
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

    test "rejects a forged owner without changing either sheet", %{
      project: project,
      sheet: sheet,
      asset1: asset1,
      asset2: asset2
    } do
      other_sheet = sheet_fixture(project, %{name: "Other"})
      {:ok, local_avatar} = Sheets.add_avatar(sheet, asset1.id)
      {:ok, foreign_avatar} = Sheets.add_avatar(other_sheet, asset2.id)

      forged_avatar = %{foreign_avatar | sheet_id: sheet.id}

      assert {:error, :avatar_not_found} =
               Sheets.set_avatar_default(forged_avatar)

      assert Sheets.get_avatar(local_avatar.id).is_default
      assert Sheets.get_avatar(foreign_avatar.id).is_default
    end

    test "rejects an avatar whose sheet is in trash", %{
      sheet: sheet,
      asset1: asset1,
      asset2: asset2
    } do
      {:ok, first} = Sheets.add_avatar(sheet, asset1.id)
      {:ok, second} = Sheets.add_avatar(sheet, asset2.id)

      sheet
      |> Ecto.Changeset.change(deleted_at: TimeHelpers.now())
      |> Repo.update!()

      assert {:error, :sheet_not_active} =
               Sheets.set_avatar_default(second)

      assert Sheets.get_avatar(first.id).is_default
      refute Sheets.get_avatar(second.id).is_default
    end
  end

  describe "remove_avatar/2" do
    test "removes default avatar and promotes next", %{
      sheet: sheet,
      asset1: asset1,
      asset2: asset2
    } do
      {:ok, first} = Sheets.add_avatar(sheet, asset1.id)
      {:ok, _} = Sheets.add_avatar(sheet, asset2.id)

      assert {:ok, _} = Sheets.remove_avatar(sheet.id, first.id)

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

      assert {:ok, _} = Sheets.remove_avatar(sheet.id, second.id)

      remaining = Sheets.list_avatars(sheet.id)
      assert length(remaining) == 1
      assert hd(remaining).id == first.id
      assert hd(remaining).is_default == true
    end

    test "removes last avatar gracefully", %{sheet: sheet, asset1: asset1} do
      {:ok, avatar} = Sheets.add_avatar(sheet, asset1.id)

      assert {:ok, _} = Sheets.remove_avatar(sheet.id, avatar.id)
      assert Sheets.list_avatars(sheet.id) == []
      assert Sheets.get_default_avatar(sheet.id) == nil
    end

    test "returns error for non-existent id", %{sheet: sheet} do
      assert {:error, :not_found} = Sheets.remove_avatar(sheet.id, 0)
    end

    test "rejects a forged sheet owner without deleting the avatar", %{
      project: project,
      sheet: sheet,
      asset1: asset1
    } do
      other_sheet = sheet_fixture(project, %{name: "Other"})
      {:ok, avatar} = Sheets.add_avatar(other_sheet, asset1.id)

      assert {:error, :not_found} =
               Sheets.remove_avatar(sheet.id, avatar.id)

      assert Sheets.get_avatar(avatar.id)
    end

    test "rejects deleting an avatar whose sheet is in trash", %{
      sheet: sheet,
      asset1: asset1
    } do
      {:ok, avatar} = Sheets.add_avatar(sheet, asset1.id)

      sheet
      |> Ecto.Changeset.change(deleted_at: TimeHelpers.now())
      |> Repo.update!()

      assert {:error, :sheet_not_active} =
               Sheets.remove_avatar(sheet.id, avatar.id)

      assert Sheets.get_avatar(avatar.id)
    end

    test "keeps an avatar referenced by an active flow node", %{
      project: project,
      sheet: sheet,
      asset1: asset
    } do
      {:ok, avatar} = Sheets.add_avatar(sheet, asset.id)
      flow = flow_fixture(project)

      node =
        node_fixture(flow, %{
          data: %{
            "speaker_sheet_id" => sheet.id,
            "avatar_id" => avatar.id,
            "text" => "Hello"
          }
        })

      assert {:error, {:avatar_in_use, avatar_id, {:referenced_by_flow_nodes, 1}}} =
               Sheets.remove_avatar(sheet.id, avatar.id)

      assert avatar_id == avatar.id
      assert Sheets.get_avatar(avatar.id)
      assert Repo.get!(FlowNode, node.id).data["avatar_id"] == avatar.id
    end

    test "keeps an avatar needed to restore a soft-deleted node", %{
      project: project,
      sheet: sheet,
      asset1: asset
    } do
      {:ok, avatar} = Sheets.add_avatar(sheet, asset.id)
      flow = flow_fixture(project)

      node =
        node_fixture(flow, %{
          data: %{
            "speaker_sheet_id" => sheet.id,
            "avatar_id" => avatar.id,
            "text" => "Recoverable"
          }
        })

      assert {:ok, deleted_node, _meta} = Flows.delete_node(node)

      assert {:error, {:avatar_in_use, avatar_id, {:referenced_by_flow_nodes, 1}}} =
               Sheets.remove_avatar(sheet.id, avatar.id)

      assert avatar_id == avatar.id
      assert {:ok, restored_node} = Flows.restore_node(flow.id, deleted_node.id)
      assert restored_node.data["avatar_id"] == avatar.id
      assert Sheets.get_avatar(avatar.id)
    end
  end

  describe "update_avatar/2" do
    test "updates name with variablify and notes", %{sheet: sheet, asset1: asset1} do
      {:ok, avatar} = Sheets.add_avatar(sheet, asset1.id)

      {:ok, updated} =
        Sheets.update_avatar(avatar, %{name: "Angry Face", notes: "Used in combat"})

      assert updated.name == "angry_face"
      assert updated.notes == "Used in combat"
    end

    test "clears name with nil", %{sheet: sheet, asset1: asset1} do
      {:ok, avatar} = Sheets.add_avatar(sheet, asset1.id, %{name: "happy"})

      {:ok, updated} = Sheets.update_avatar(avatar, %{name: nil})
      assert updated.name == nil
    end

    test "cannot bypass set_default through generic updates", %{
      sheet: sheet,
      asset1: asset1,
      asset2: asset2
    } do
      {:ok, first} = Sheets.add_avatar(sheet, asset1.id)
      {:ok, second} = Sheets.add_avatar(sheet, asset2.id)

      assert {:ok, updated} =
               Sheets.update_avatar(second, %{name: "Alternate", is_default: true})

      refute updated.is_default
      assert Sheets.get_avatar(first.id).is_default
      refute Sheets.get_avatar(second.id).is_default
    end

    test "rejects a forged sheet owner without mutating either avatar", %{
      project: project,
      sheet: sheet,
      asset1: asset1,
      asset2: asset2
    } do
      other_sheet = sheet_fixture(project, %{name: "Other"})
      {:ok, local} = Sheets.add_avatar(sheet, asset1.id, %{name: "local"})
      {:ok, foreign} = Sheets.add_avatar(other_sheet, asset2.id, %{name: "foreign"})

      assert {:error, :avatar_not_found} =
               Sheets.update_avatar(%{foreign | sheet_id: sheet.id}, %{name: "forged"})

      assert Sheets.get_avatar(local.id).name == "local"
      assert Sheets.get_avatar(foreign.id).name == "foreign"
    end

    test "rejects updates beneath a sheet in trash", %{
      sheet: sheet,
      asset1: asset1
    } do
      {:ok, avatar} = Sheets.add_avatar(sheet, asset1.id, %{name: "original"})

      sheet
      |> Ecto.Changeset.change(deleted_at: TimeHelpers.now())
      |> Repo.update!()

      assert {:error, :sheet_not_active} =
               Sheets.update_avatar(avatar, %{name: "changed"})

      assert Sheets.get_avatar(avatar.id).name == "original"
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

    test "rejects incomplete, duplicate, malformed, and foreign sets atomically", %{
      project: project,
      sheet: sheet,
      asset1: asset1,
      asset2: asset2,
      asset3: asset3
    } do
      other_sheet = sheet_fixture(project, %{name: "Other"})
      {:ok, a1} = Sheets.add_avatar(sheet, asset1.id)
      {:ok, a2} = Sheets.add_avatar(sheet, asset2.id)
      {:ok, foreign} = Sheets.add_avatar(other_sheet, asset3.id)

      original = avatar_positions(sheet.id)

      invalid_payloads = [
        [a2.id],
        [a2.id, a2.id],
        [a2.id, foreign.id],
        [a2.id, a1.id, "invalid"],
        [a2.id, a1.id, 0]
      ]

      Enum.each(invalid_payloads, fn payload ->
        assert {:error, {:invalid_avatar_reorder, ^payload}} =
                 Sheets.reorder_avatars(sheet.id, payload)

        assert avatar_positions(sheet.id) == original
      end)
    end

    test "rejects reordering avatars under a sheet in trash without mutation", %{
      sheet: sheet,
      asset1: asset1,
      asset2: asset2
    } do
      {:ok, a1} = Sheets.add_avatar(sheet, asset1.id)
      {:ok, a2} = Sheets.add_avatar(sheet, asset2.id)
      original = avatar_positions(sheet.id)

      sheet
      |> Ecto.Changeset.change(deleted_at: TimeHelpers.now())
      |> Repo.update!()

      assert {:error, :sheet_not_active} =
               Sheets.reorder_avatars(sheet.id, [a2.id, a1.id])

      assert avatar_positions(sheet.id) == original
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
      assert hd(result[sheet.id]).asset
    end

    test "excludes soft-deleted sheets", %{project: project, asset1: asset1} do
      deleted_sheet = sheet_fixture(project, %{name: "Deleted"})
      {:ok, _} = Sheets.add_avatar(deleted_sheet, asset1.id)

      deleted_sheet
      |> Ecto.Changeset.change(deleted_at: TimeHelpers.now())
      |> Repo.update!()

      result = Sheets.batch_load_avatars_by_sheet(project.id)
      refute Map.has_key?(result, deleted_sheet.id)
    end

    test "returns empty map for project without avatars" do
      empty_project = project_fixture()
      assert Sheets.batch_load_avatars_by_sheet(empty_project.id) == %{}
    end
  end

  defp avatar_positions(sheet_id) do
    sheet_id
    |> Sheets.list_avatars()
    |> Map.new(&{&1.id, &1.position})
  end
end
