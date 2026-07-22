defmodule Storyarn.Versioning.ProjectSnapshotLocalizationLifecycleTest do
  use Storyarn.DataCase, async: true

  import Storyarn.AccountsFixtures
  import Storyarn.FlowsFixtures
  import Storyarn.LocalizationFixtures
  import Storyarn.ProjectsFixtures
  import Storyarn.SheetsFixtures

  alias Storyarn.Assets
  alias Storyarn.Assets.BlobStore
  alias Storyarn.Flows
  alias Storyarn.Flows.Flow
  alias Storyarn.Localization
  alias Storyarn.Localization.LocalizedText
  alias Storyarn.Sheets
  alias Storyarn.Sheets.Sheet
  alias Storyarn.Versioning.Builders.ProjectSnapshotBuilder

  test "archives current-only localization with its voice-over and preserves unrelated trash" do
    user = user_fixture()
    project = project_fixture(user)
    source_language_fixture(project, %{locale_code: "en", name: "English"})
    language_fixture(project, %{locale_code: "es", name: "Spanish"})

    prior_trash_flow = flow_fixture(project, %{name: "Prior trash"})

    prior_trash_node =
      node_fixture(prior_trash_flow, %{
        type: "dialogue",
        data: %{"text" => "Already deleted", "responses" => []}
      })

    prior_trash_text =
      Localization.get_text_by_source("flow_node", prior_trash_node.id, "text", "es")

    assert {:ok, prior_trash_text} =
             Localization.update_text(prior_trash_text, %{
               translated_text: "Ya eliminado",
               reviewer_notes: "Must survive untouched"
             })

    assert {:ok, _deleted_flow} = Flows.delete_flow(prior_trash_flow)
    prior_trash_state = localization_state(Repo.get!(LocalizedText, prior_trash_text.id))
    assert prior_trash_state.archived_at
    assert prior_trash_state.archive_reason == "source_deleted"

    target_flow = flow_fixture(project, %{name: "Snapshot flow"})

    target_node =
      node_fixture(target_flow, %{
        type: "dialogue",
        data: %{"text" => "Snapshot line", "responses" => []}
      })

    target_text =
      Localization.get_text_by_source("flow_node", target_node.id, "text", "es")

    assert {:ok, _target_text} =
             Localization.update_text(target_text, %{
               translated_text: "Versión del snapshot",
               reviewer_notes: "Snapshot state"
             })

    snapshot = ProjectSnapshotBuilder.build_snapshot(project.id)

    assert {:ok, _target_text} =
             target_text
             |> Repo.reload!()
             |> Localization.update_text(%{
               translated_text: "Current target value",
               reviewer_notes: "Must be replaced"
             })

    current_only_flow = flow_fixture(project, %{name: "Current-only flow"})

    current_only_node =
      node_fixture(current_only_flow, %{
        type: "dialogue",
        data: %{"text" => "Current-only line", "responses" => []}
      })

    voice_asset =
      uploaded_asset(
        project,
        user,
        "current-only-voice.mp3",
        "recoverable voice bytes",
        "audio/mpeg"
      )

    current_only_text =
      Localization.get_text_by_source("flow_node", current_only_node.id, "text", "es")

    assert {:ok, current_only_text} =
             Localization.update_text(current_only_text, %{
               translated_text: "Solo estado actual",
               reviewer_notes: "Must remain recoverable",
               vo_asset_id: voice_asset.id,
               vo_status: "recorded"
             })

    current_only_state = localization_state(current_only_text)
    recoverable_current_snapshot = ProjectSnapshotBuilder.build_snapshot(project.id)

    assert {:ok, _result} =
             ProjectSnapshotBuilder.restore_snapshot(project.id, snapshot, user_id: user.id)

    assert %Flow{deleted_at: %DateTime{}} = Repo.get!(Flow, current_only_flow.id)

    archived_current_only = Repo.get!(LocalizedText, current_only_text.id)

    assert archived_current_only.archived_at
    assert archived_current_only.archive_reason == "source_deleted"
    assert archived_current_only.translated_text == current_only_state.translated_text
    assert archived_current_only.reviewer_notes == current_only_state.reviewer_notes
    assert archived_current_only.vo_asset_id == current_only_state.vo_asset_id
    assert archived_current_only.vo_status == current_only_state.vo_status
    assert archived_current_only.lock_version == current_only_state.lock_version + 1
    assert Localization.get_texts_for_source("flow_node", current_only_node.id) == []

    assert localization_state(Repo.get!(LocalizedText, prior_trash_text.id)) ==
             prior_trash_state

    restored_target =
      Localization.get_text_by_source("flow_node", target_node.id, "text", "es")

    assert restored_target.translated_text == "Versión del snapshot"
    assert restored_target.reviewer_notes == "Snapshot state"

    assert {:ok, _restored_flow} =
             current_only_flow.id
             |> then(&Repo.get!(Flow, &1))
             |> Flows.restore_flow()

    current_safety_snapshot = ProjectSnapshotBuilder.build_snapshot(project.id)

    assert {:ok, _result} =
             ProjectSnapshotBuilder.restore_snapshot(
               project.id,
               recoverable_current_snapshot,
               user_id: user.id,
               pre_restore_snapshot: current_safety_snapshot
             )

    assert %Flow{deleted_at: nil} = Repo.get!(Flow, current_only_flow.id)

    recovered_current_only =
      Localization.get_text_by_source(
        "flow_node",
        current_only_node.id,
        "text",
        "es"
      )

    assert recovered_current_only.translated_text ==
             current_only_state.translated_text

    assert recovered_current_only.reviewer_notes ==
             current_only_state.reviewer_notes

    assert recovered_current_only.vo_asset_id == current_only_state.vo_asset_id
    assert recovered_current_only.vo_status == current_only_state.vo_status
    assert is_nil(recovered_current_only.archived_at)
    assert is_nil(recovered_current_only.archive_reason)

    assert localization_state(Repo.get!(LocalizedText, prior_trash_text.id)) ==
             prior_trash_state
  end

  test "archives sheet and block localization when their active source moves to trash" do
    user = user_fixture()
    project = project_fixture(user)
    source_language_fixture(project, %{locale_code: "en", name: "English"})
    language_fixture(project, %{locale_code: "es", name: "Spanish"})
    snapshot = ProjectSnapshotBuilder.build_snapshot(project.id)

    current_only_sheet =
      sheet_fixture(project, %{name: "Current-only character"})

    current_only_block =
      block_fixture(current_only_sheet, %{
        type: "text",
        variable_name: "current_only_bio",
        value: %{"content" => "Current-only biography"}
      })

    sheet_text =
      Localization.get_text_by_source(
        "sheet",
        current_only_sheet.id,
        "name",
        "es"
      )

    block_text =
      Localization.get_text_by_source(
        "block",
        current_only_block.id,
        "value.content",
        "es"
      )

    assert {:ok, sheet_text} =
             Localization.update_text(sheet_text, %{
               translated_text: "Personaje solo actual"
             })

    assert {:ok, block_text} =
             Localization.update_text(block_text, %{
               translated_text: "Biografía solo actual"
             })

    assert {:ok, _result} =
             ProjectSnapshotBuilder.restore_snapshot(project.id, snapshot)

    assert %Sheet{deleted_at: %DateTime{}} =
             Repo.get!(Sheet, current_only_sheet.id)

    archived_sheet_text = Repo.get!(LocalizedText, sheet_text.id)
    archived_block_text = Repo.get!(LocalizedText, block_text.id)

    assert archived_sheet_text.translated_text == "Personaje solo actual"
    assert archived_sheet_text.archived_at
    assert archived_sheet_text.archive_reason == "source_deleted"

    assert archived_block_text.translated_text == "Biografía solo actual"
    assert archived_block_text.archived_at
    assert archived_block_text.archive_reason == "source_deleted"
  end

  test "captures archived orphan localization but defers in-place materialization" do
    user = user_fixture()
    project = project_fixture(user)
    source_language_fixture(project, %{locale_code: "en", name: "English"})
    language_fixture(project, %{locale_code: "es", name: "Spanish"})
    sheet = sheet_fixture(project, %{name: "Character"})

    block =
      block_fixture(sheet, %{
        type: "text",
        variable_name: "archived_bio",
        value: %{"content" => "Archived biography"}
      })

    text =
      Localization.get_text_by_source(
        "block",
        block.id,
        "value.content",
        "es"
      )

    assert {:ok, text} =
             Localization.update_text(text, %{
               translated_text: "Biografía archivada",
               reviewer_notes: "Recovery-only state"
             })

    assert {:ok, _deleted_block} = Sheets.delete_block(block)
    archived_before = localization_state(Repo.get!(LocalizedText, text.id))
    assert archived_before.archived_at

    snapshot = ProjectSnapshotBuilder.build_snapshot(project.id)

    assert %{
             "archived_at" => archived_at,
             "archive_reason" => "source_deleted",
             "translated_text" => "Biografía archivada"
           } =
             Enum.find(
               snapshot["localization"]["texts"],
               &(&1["source_type"] == "block" and
                   &1["source_id"] == block.id and
                   &1["source_field"] == "value.content" and
                   &1["locale_code"] == "es")
             )

    assert archived_at

    assert {:ok, _result} =
             ProjectSnapshotBuilder.restore_snapshot(project.id, snapshot)

    assert localization_state(Repo.get!(LocalizedText, text.id)) ==
             archived_before
  end

  test "nilifies an archived speaker outside the target graph after its sheet is purged" do
    user = user_fixture()
    project = project_fixture(user)
    source_language_fixture(project, %{locale_code: "en", name: "English"})
    language_fixture(project, %{locale_code: "es", name: "Spanish"})
    speaker = sheet_fixture(project, %{name: "Archived speaker"})
    flow = flow_fixture(project)

    node =
      node_fixture(flow, %{
        type: "dialogue",
        data: %{
          "text" => "Current dialogue",
          "speaker_sheet_id" => speaker.id,
          "responses" => [%{"id" => "removed", "text" => "Removed response"}]
        }
      })

    response_text =
      Localization.get_text_by_source(
        "flow_node",
        node.id,
        "response.removed.text",
        "es"
      )

    assert {:ok, _node, _meta} =
             Flows.update_node_data(node, %{
               "text" => "Current dialogue",
               "speaker_sheet_id" => nil,
               "responses" => []
             })

    assert %LocalizedText{
             archived_at: %DateTime{},
             speaker_sheet_id: speaker_id
           } = Repo.get!(LocalizedText, response_text.id)

    assert speaker_id == speaker.id
    assert {:ok, _deleted_sheet} = Sheets.delete_sheet(speaker)

    target_snapshot = ProjectSnapshotBuilder.build_snapshot(project.id)

    archived_snapshot_text =
      Enum.find(
        target_snapshot["localization"]["texts"],
        &(&1["source_id"] == node.id and
            &1["source_field"] == "response.removed.text" and
            &1["locale_code"] == "es")
      )

    assert archived_snapshot_text["speaker_sheet_id"] == speaker.id

    assert {:ok, _purged_sheet} =
             speaker.id
             |> then(&Repo.get!(Sheet, &1))
             |> Sheets.permanently_delete_sheet()

    assert Repo.get!(LocalizedText, response_text.id).speaker_sheet_id == nil
    safety_snapshot = ProjectSnapshotBuilder.build_snapshot(project.id)

    assert {:ok, _result} =
             ProjectSnapshotBuilder.restore_snapshot(
               project.id,
               target_snapshot,
               pre_restore_snapshot: safety_snapshot
             )

    restored_archived_text =
      Repo.one!(
        from(text in LocalizedText,
          where:
            text.project_id == ^project.id and
              text.source_type == "flow_node" and
              text.source_id == ^node.id and
              text.source_field == "response.removed.text" and
              text.locale_code == "es"
        )
      )

    assert restored_archived_text.archived_at
    assert restored_archived_text.archive_reason == "source_field_removed"
    assert is_nil(restored_archived_text.speaker_sheet_id)
  end

  test "rejects an active dialogue speaker outside the target graph atomically" do
    user = user_fixture()
    project = project_fixture(user)
    source_language_fixture(project, %{locale_code: "en", name: "English"})
    language_fixture(project, %{locale_code: "es", name: "Spanish"})
    flow = flow_fixture(project)

    node =
      node_fixture(flow, %{
        type: "dialogue",
        data: %{
          "text" => "Active dialogue",
          "speaker_sheet_id" => nil,
          "responses" => []
        }
      })

    localized_text =
      Localization.get_text_by_source(
        "flow_node",
        node.id,
        "text",
        "es"
      )

    target_snapshot = ProjectSnapshotBuilder.build_snapshot(project.id)
    current_only_speaker = sheet_fixture(project, %{name: "Not in target graph"})

    invalid_snapshot =
      update_in(target_snapshot, ["localization", "texts"], fn texts ->
        Enum.map(texts, fn text ->
          if text["source_type"] == "flow_node" and
               text["source_id"] == node.id and
               text["source_field"] == "text" and
               text["locale_code"] == "es" do
            Map.put(text, "speaker_sheet_id", current_only_speaker.id)
          else
            text
          end
        end)
      end)

    safety_snapshot = ProjectSnapshotBuilder.build_snapshot(project.id)

    assert {:error, {:invalid_project_snapshot_localization_speaker, "flow_node", node_id, "text", speaker_id}} =
             ProjectSnapshotBuilder.restore_snapshot(
               project.id,
               invalid_snapshot,
               pre_restore_snapshot: safety_snapshot
             )

    assert node_id == node.id
    assert speaker_id == current_only_speaker.id
    assert %Sheet{deleted_at: nil} = Repo.get!(Sheet, current_only_speaker.id)
    assert Repo.get!(LocalizedText, localized_text.id).speaker_sheet_id == nil
  end

  defp localization_state(text) do
    Map.take(text, [
      :id,
      :source_type,
      :source_id,
      :source_field,
      :locale_code,
      :source_text,
      :source_text_hash,
      :translated_source_hash,
      :translated_text,
      :status,
      :vo_status,
      :vo_asset_id,
      :translator_notes,
      :reviewer_notes,
      :speaker_sheet_id,
      :word_count,
      :content_role,
      :vo_eligible,
      :machine_translated,
      :last_translated_at,
      :last_reviewed_at,
      :translated_by_id,
      :reviewed_by_id,
      :lock_version,
      :archived_at,
      :archive_reason,
      :inserted_at,
      :updated_at
    ])
  end

  defp uploaded_asset(project, user, filename, content, content_type) do
    {:ok, asset} =
      Assets.upload_binary_and_create_asset(
        content,
        %{filename: filename, content_type: content_type},
        project,
        user
      )

    on_exit(fn ->
      Assets.storage_delete(asset.key)

      delete_storage_blob(
        BlobStore.blob_key(
          project.id,
          asset.blob_hash,
          BlobStore.ext_from_content_type(content_type)
        )
      )
    end)

    asset
  end
end
