defmodule Storyarn.Flows.PlayerCatalogTest do
  use Storyarn.DataCase, async: true

  import Ecto.Query
  import Storyarn.AccountsFixtures
  import Storyarn.AssetsFixtures
  import Storyarn.ProjectsFixtures
  import Storyarn.SheetsFixtures

  alias Storyarn.Flows
  alias Storyarn.Flows.Runtime.Data.SheetRecord
  alias Storyarn.Platform.Shared.TimeHelpers
  alias Storyarn.Projects.Assets.Asset
  alias Storyarn.Repo
  alias Storyarn.Sheets
  alias StoryarnWeb.FlowLive.Helpers.FormHelpers
  alias StoryarnWeb.PrivateMedia

  describe "load_player_speakers/1" do
    test "returns the player-owned speaker projection with optimized avatar media" do
      user = user_fixture()
      project = project_fixture(user)
      optimized_asset = image_asset_fixture(project, user, %{filename: "speaker-web.webp"})

      original_asset =
        image_asset_fixture(project, user, %{
          filename: "speaker-original.png",
          metadata: %{"web_asset_id" => optimized_asset.id}
        })

      speaker = sheet_fixture(project, %{name: "Ada Lovelace", color: "#123456"})
      assert {:ok, avatar} = Sheets.add_avatar(speaker, original_asset.id, %{name: "portrait"})

      assert [projection] = Flows.load_player_speakers(project.id)

      assert projection == %{
               id: speaker.id,
               name: "Ada Lovelace",
               color: "#123456",
               avatars: [
                 %{
                   id: avatar.id,
                   name: "portrait",
                   position: 0,
                   is_default: true,
                   asset: %{id: optimized_asset.id, filename: "speaker-original.png"}
                 }
               ]
             }

      speaker_key = to_string(speaker.id)
      expected_avatar_url = PrivateMedia.asset_url(optimized_asset)

      assert %{^speaker_key => player_speaker} = FormHelpers.player_speakers_map([projection])

      assert player_speaker == %{
               id: speaker.id,
               name: "Ada Lovelace",
               color: "#123456",
               avatar_url: expected_avatar_url,
               avatars: [%{id: avatar.id, url: expected_avatar_url}]
             }
    end

    test "isolates projects, excludes deleted speakers and preserves ordering" do
      user = user_fixture()
      project = project_fixture(user)
      other_project = project_fixture(user)

      second = sheet_fixture(project, %{name: "Second"})
      first = sheet_fixture(project, %{name: "First"})
      deleted = sheet_fixture(project, %{name: "Deleted"})
      _foreign = sheet_fixture(other_project, %{name: "Foreign"})

      set_sheet_position(first.id, 0)
      set_sheet_position(second.id, 1)

      Repo.update_all(
        from(record in SheetRecord, where: record.id == ^deleted.id),
        set: [deleted_at: TimeHelpers.now()]
      )

      assert project.id
             |> Flows.load_player_speakers()
             |> Enum.map(& &1.id) == [first.id, second.id]
    end

    test "retains a speaker but drops deleted avatar media" do
      user = user_fixture()
      project = project_fixture(user)
      speaker = sheet_fixture(project, %{name: "Speaker"})
      asset = image_asset_fixture(project, user)
      assert {:ok, avatar} = Sheets.add_avatar(speaker, asset.id)

      Repo.update_all(
        from(record in Asset, where: record.id == ^asset.id),
        set: [deleted_at: TimeHelpers.now(), deletion_reason: "system", deletion_generation: 1]
      )

      assert [%{id: speaker_id, avatars: [%{id: avatar_id, asset: nil}] = avatars}] =
               Flows.load_player_speakers(project.id)

      assert speaker_id == speaker.id
      assert avatar_id == avatar.id

      speaker_key = to_string(speaker.id)

      assert %{^speaker_key => %{avatar_url: nil, avatars: []}} =
               FormHelpers.player_speakers_map([
                 %{id: speaker.id, name: speaker.name, color: speaker.color, avatars: avatars}
               ])
    end
  end

  defp set_sheet_position(sheet_id, position) do
    Repo.update_all(from(record in SheetRecord, where: record.id == ^sheet_id), set: [position: position])
  end
end
