defmodule Storyarn.Localization.WriterReferenceIntegrityTest do
  use Storyarn.DataCase, async: true

  import Storyarn.AccountsFixtures
  import Storyarn.AssetsFixtures
  import Storyarn.LocalizationFixtures
  import Storyarn.ProjectsFixtures
  import Storyarn.SheetsFixtures

  alias Storyarn.Assets
  alias Storyarn.Localization
  alias Storyarn.Localization.LocalizedText
  alias Storyarn.Repo

  test "recorded and approved voice-over states require an audio asset" do
    project = project_fixture(user_fixture())
    text = localized_text_fixture(project.id)

    assert {:error, changeset} =
             Localization.update_text(text, %{vo_status: "recorded"})

    assert errors_on(changeset).vo_asset_id == [
             "is required for recorded or approved voice-over"
           ]

    assert Repo.reload!(text).vo_status == "none"
  end

  test "translation updates accept only voice-over assets from the same project" do
    user = user_fixture()
    project = project_fixture(user)
    text = localized_text_fixture(project.id)
    audio = audio_asset_fixture(project, user)

    assert {:ok, recorded} =
             Localization.update_text(text, %{
               vo_asset_id: audio.id,
               vo_status: "recorded"
             })

    assert recorded.vo_asset_id == audio.id
    assert recorded.vo_status == "recorded"

    foreign_audio = audio_asset_fixture(project_fixture(user), user)

    assert {:error, changeset} =
             Localization.update_text(recorded, %{
               vo_asset_id: foreign_audio.id,
               vo_status: "approved"
             })

    assert errors_on(changeset).vo_asset_id == [
             "must reference an asset in this project"
           ]

    assert Repo.reload!(recorded).vo_asset_id == audio.id
  end

  test "translation updates reject non-audio assets and manual speaker rewrites" do
    user = user_fixture()
    project = project_fixture(user)
    text = localized_text_fixture(project.id)
    image = image_asset_fixture(project, user)

    assert {:error, changeset} =
             Localization.update_text(text, %{
               vo_asset_id: image.id,
               vo_status: "recorded"
             })

    assert errors_on(changeset).vo_asset_id == [
             "must reference an audio asset"
           ]

    speaker = sheet_fixture(project)

    assert {:error, changeset} =
             Localization.update_text(text, %{speaker_sheet_id: speaker.id})

    assert errors_on(changeset).speaker_sheet_id == [
             "cannot be changed manually"
           ]
  end

  test "archived texts and malformed references preserve the changeset error contract" do
    user = user_fixture()
    project = project_fixture(user)
    active_text = localized_text_fixture(project.id)

    assert {:error, malformed_changeset} =
             Localization.update_text(active_text, %{
               vo_asset_id: "not-an-id",
               vo_status: "recorded"
             })

    assert %Ecto.Changeset{} = malformed_changeset
    assert "is invalid" in errors_on(malformed_changeset).vo_asset_id

    archived_text =
      active_text
      |> Ecto.Changeset.change(archived_at: DateTime.utc_now(:second))
      |> Repo.update!()

    assert {:error, archived_changeset} =
             Localization.update_text(archived_text, %{translated_text: "No debe guardarse"})

    assert errors_on(archived_changeset).base == [
             "is archived and can no longer be edited"
           ]
  end

  test "deleting a voice asset atomically clears the FK and downgrades status" do
    user = user_fixture()
    project = project_fixture(user)
    text = localized_text_fixture(project.id)
    audio = audio_asset_fixture(project, user)

    assert {:ok, recorded} =
             Localization.update_text(text, %{
               vo_asset_id: audio.id,
               vo_status: "approved"
             })

    previous_lock_version = recorded.lock_version

    assert {:ok, _deleted_asset} = Assets.delete_asset(audio)

    repaired = Repo.reload!(recorded)
    assert repaired.vo_asset_id == nil
    assert repaired.vo_status == "needed"
    assert repaired.lock_version == previous_lock_version + 1
  end

  test "the localized text changeset enforces the voice-over invariant" do
    changeset =
      LocalizedText.create_changeset(%LocalizedText{}, %{
        source_type: "flow_node",
        source_id: 1,
        source_field: "text",
        locale_code: "es",
        vo_status: "recorded"
      })

    assert errors_on(changeset).vo_asset_id == [
             "is required for recorded or approved voice-over"
           ]
  end
end
