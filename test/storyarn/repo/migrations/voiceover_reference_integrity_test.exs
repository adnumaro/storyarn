Code.require_file(
  Path.expand(
    "../../../../priv/repo/migration_helpers/voiceover_reference_integrity.exs",
    __DIR__
  )
)

defmodule Storyarn.Repo.Migrations.VoiceoverReferenceIntegrityTest do
  use Storyarn.DataCase, async: false

  import Storyarn.AccountsFixtures
  import Storyarn.AssetsFixtures
  import Storyarn.LocalizationFixtures
  import Storyarn.ProjectsFixtures
  import Storyarn.SheetsFixtures

  alias Storyarn.Localization
  alias Storyarn.Localization.LocalizedText
  alias Storyarn.Repo
  alias Storyarn.Repo.Migrations.VoiceoverReferenceIntegrity

  test "quiesces project-first writers before targets and freezes source lock upgrades" do
    [project_lock, target_lock, source_lock] = VoiceoverReferenceIntegrity.lock_sql()

    assert project_lock =~ "FROM projects"
    assert project_lock =~ "ORDER BY id"
    assert project_lock =~ "FOR UPDATE"
    assert target_lock =~ "LOCK TABLE assets, sheets"
    assert target_lock =~ "IN SHARE MODE"
    assert source_lock =~ "LOCK TABLE localized_texts"
    assert source_lock =~ "IN ACCESS EXCLUSIVE MODE"
  end

  test "backfill clears cross-project and non-audio voice assets plus invalid speakers" do
    user = user_fixture()
    project = project_fixture(user)
    foreign_project = project_fixture(user)
    valid_audio = audio_asset_fixture(project, user)
    foreign_audio = audio_asset_fixture(foreign_project, user)
    local_image = image_asset_fixture(project, user)
    foreign_speaker = sheet_fixture(foreign_project)
    deleted_speaker = sheet_fixture(project)

    deleted_speaker
    |> Ecto.Changeset.change(deleted_at: DateTime.utc_now(:second))
    |> Repo.update!()

    foreign_asset_text =
      voiced_text_fixture(project.id, valid_audio.id, %{
        source_id: System.unique_integer([:positive])
      })

    image_asset_text =
      voiced_text_fixture(project.id, valid_audio.id, %{
        source_id: System.unique_integer([:positive])
      })

    foreign_speaker_text =
      localized_text_fixture(project.id, %{
        source_id: System.unique_integer([:positive])
      })

    deleted_speaker_text =
      localized_text_fixture(project.id, %{
        source_id: System.unique_integer([:positive])
      })

    Repo.query!(
      """
      UPDATE localized_texts
      SET vo_asset_id = $1
      WHERE id = $2
      """,
      [foreign_audio.id, foreign_asset_text.id]
    )

    Repo.query!(
      """
      UPDATE localized_texts
      SET vo_asset_id = $1
      WHERE id = $2
      """,
      [local_image.id, image_asset_text.id]
    )

    Repo.query!(
      """
      UPDATE localized_texts
      SET speaker_sheet_id = $1
      WHERE id = $2
      """,
      [foreign_speaker.id, foreign_speaker_text.id]
    )

    Repo.query!(
      """
      UPDATE localized_texts
      SET speaker_sheet_id = $1
      WHERE id = $2
      """,
      [deleted_speaker.id, deleted_speaker_text.id]
    )

    Enum.each(VoiceoverReferenceIntegrity.repair_sql(), &Repo.query!/1)

    for text <- [foreign_asset_text, image_asset_text] do
      repaired = Repo.get!(LocalizedText, text.id)
      assert repaired.vo_asset_id == nil
      assert repaired.vo_status == "needed"
      assert repaired.lock_version > text.lock_version
    end

    assert Repo.get!(LocalizedText, foreign_speaker_text.id).speaker_sheet_id == nil
    assert Repo.get!(LocalizedText, deleted_speaker_text.id).speaker_sheet_id == nil
  end

  test "database trigger downgrades recorded voice before an asset FK is nilified" do
    install_voiceover_asset_removal_trigger!()

    user = user_fixture()
    project = project_fixture(user)
    audio = audio_asset_fixture(project, user)
    text = voiced_text_fixture(project.id, audio.id)

    previous_lock_version = text.lock_version
    Repo.delete!(audio)

    repaired = Repo.reload!(text)
    assert repaired.vo_asset_id == nil
    assert repaired.vo_status == "needed"
    assert repaired.lock_version == previous_lock_version + 1
  end

  defp install_voiceover_asset_removal_trigger! do
    Repo.query!(VoiceoverReferenceIntegrity.trigger_function_sql())

    Enum.each(VoiceoverReferenceIntegrity.trigger_sql(), fn sql ->
      Repo.query!(sql)
    end)
  end

  defp voiced_text_fixture(project_id, asset_id, attrs \\ %{}) do
    text = localized_text_fixture(project_id, attrs)

    {:ok, voiced} =
      Localization.update_text(text, %{
        vo_asset_id: asset_id,
        vo_status: "recorded"
      })

    voiced
  end
end
