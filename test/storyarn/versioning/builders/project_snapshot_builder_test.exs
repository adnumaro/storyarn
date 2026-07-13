defmodule Storyarn.Versioning.Builders.ProjectSnapshotBuilderTest do
  use Storyarn.DataCase, async: true

  import Storyarn.AccountsFixtures
  import Storyarn.FlowsFixtures
  import Storyarn.LocalizationFixtures
  import Storyarn.ProjectsFixtures
  import Storyarn.ScenesFixtures
  import Storyarn.SheetsFixtures

  alias Storyarn.Assets
  alias Storyarn.Assets.BlobStore
  alias Storyarn.Localization
  alias Storyarn.Versioning.Builders.ProjectSnapshotBuilder

  setup do
    user = user_fixture()
    project = project_fixture(user)
    sheet = sheet_fixture(project, %{name: "Hero Sheet"})
    _block = block_fixture(sheet, %{type: "text", config: %{"label" => "Name"}})
    flow = flow_fixture(project, %{name: "Main Flow"})
    _node = node_fixture(flow, %{type: "dialogue"})
    scene = scene_fixture(project, %{name: "World Map"})

    %{user: user, project: project, sheet: sheet, flow: flow, scene: scene}
  end

  describe "build_snapshot/1" do
    test "includes all entity types", %{project: project} do
      snapshot = ProjectSnapshotBuilder.build_snapshot(project.id)

      assert snapshot["format_version"] == 2
      assert is_map(snapshot["entity_counts"])
      assert snapshot["entity_counts"]["sheets"] >= 1
      assert snapshot["entity_counts"]["flows"] >= 1
      assert snapshot["entity_counts"]["scenes"] >= 1
      assert is_list(snapshot["sheets"])
      assert is_list(snapshot["flows"])
      assert is_list(snapshot["scenes"])
    end

    test "each entity entry has id and snapshot", %{project: project} do
      snapshot = ProjectSnapshotBuilder.build_snapshot(project.id)

      for entry <- snapshot["sheets"] do
        assert is_integer(entry["id"])
        assert is_map(entry["snapshot"])
        assert entry["snapshot"]["name"]
      end

      for entry <- snapshot["flows"] do
        assert is_integer(entry["id"])
        assert is_map(entry["snapshot"])
        assert entry["snapshot"]["name"]
      end

      for entry <- snapshot["scenes"] do
        assert is_integer(entry["id"])
        assert is_map(entry["snapshot"])
        assert entry["snapshot"]["name"]
      end
    end

    test "entity counts match actual entity lists", %{project: project} do
      snapshot = ProjectSnapshotBuilder.build_snapshot(project.id)

      assert snapshot["entity_counts"]["sheets"] == length(snapshot["sheets"])
      assert snapshot["entity_counts"]["flows"] == length(snapshot["flows"])
      assert snapshot["entity_counts"]["scenes"] == length(snapshot["scenes"])
    end

    test "handles empty project", %{user: user} do
      empty_project = project_fixture(user)
      snapshot = ProjectSnapshotBuilder.build_snapshot(empty_project.id)

      assert snapshot["format_version"] == 2
      assert snapshot["entity_counts"]["sheets"] == 0
      assert snapshot["entity_counts"]["flows"] == 0
      assert snapshot["entity_counts"]["scenes"] == 0
      assert snapshot["entity_counts"]["languages"] == 0
      assert snapshot["entity_counts"]["localized_texts"] == 0
      assert snapshot["entity_counts"]["glossary_entries"] == 0
      assert snapshot["sheets"] == []
      assert snapshot["flows"] == []
      assert snapshot["scenes"] == []
      assert snapshot["localization"]["languages"] == []
      assert snapshot["localization"]["texts"] == []
      assert snapshot["localization"]["glossary"] == []
    end
  end

  describe "localization restore integrity" do
    test "drops stale auxiliary foreign keys from snapshot rows", %{project: project} do
      source_language_fixture(project, %{locale_code: "en", name: "English"})
      language_fixture(project, %{locale_code: "es", name: "Spanish"})
      assert {:ok, _count} = Localization.extract_all(project.id)

      snapshot = ProjectSnapshotBuilder.build_snapshot(project.id)

      localization =
        update_in(snapshot, ["localization", "texts"], fn texts ->
          Enum.map(texts, fn text ->
            Map.merge(text, %{
              "vo_asset_id" => 9_999_991,
              "speaker_sheet_id" => 9_999_992,
              "translated_by_id" => 9_999_993,
              "reviewed_by_id" => 9_999_994
            })
          end)
        end)

      assert {:ok, _result} = ProjectSnapshotBuilder.restore_snapshot(project.id, localization)

      assert Enum.all?(Localization.list_all_texts(project.id), fn text ->
               is_nil(text.vo_asset_id) and is_nil(text.speaker_sheet_id) and
                 is_nil(text.translated_by_id) and is_nil(text.reviewed_by_id)
             end)
    end
  end

  describe "restore_snapshot/2" do
    test "restores modified entities", %{project: project, sheet: sheet} do
      snapshot = ProjectSnapshotBuilder.build_snapshot(project.id)

      # Modify an entity
      {:ok, _} = Storyarn.Sheets.update_sheet(sheet, %{name: "Changed Name"})

      # Restore
      assert {:ok, result} = ProjectSnapshotBuilder.restore_snapshot(project.id, snapshot)
      assert result.restored >= 1

      # Verify restoration
      restored = Storyarn.Sheets.get_sheet(project.id, sheet.id)
      assert restored.name == "Hero Sheet"
    end

    test "skips soft-deleted entities", %{project: project, sheet: sheet} do
      source_language_fixture(project, %{locale_code: "en", name: "English"})
      language_fixture(project, %{locale_code: "es", name: "Spanish"})
      snapshot = ProjectSnapshotBuilder.build_snapshot(project.id)

      # Soft-delete an entity
      {:ok, _} = Storyarn.Sheets.delete_sheet(sheet)

      # Restore should skip the deleted entity
      assert {:ok, result} = ProjectSnapshotBuilder.restore_snapshot(project.id, snapshot)
      assert result.skipped >= 1
      assert Localization.get_texts_for_source("sheet", sheet.id) == []
    end

    test "leaves entities not in snapshot untouched", %{project: project} do
      snapshot = ProjectSnapshotBuilder.build_snapshot(project.id)

      # Create a new entity after the snapshot
      new_sheet = sheet_fixture(project, %{name: "New After Snapshot"})

      # Restore
      {:ok, _} = ProjectSnapshotBuilder.restore_snapshot(project.id, snapshot)

      # New entity should still exist and be unmodified
      restored_new = Storyarn.Sheets.get_sheet(project.id, new_sheet.id)
      assert restored_new
      assert restored_new.name == "New After Snapshot"
    end
  end

  describe "localization in snapshot" do
    test "includes localization data", %{project: project} do
      source_language_fixture(project, %{locale_code: "en", name: "English"})
      language_fixture(project, %{locale_code: "es", name: "Spanish"})

      text =
        localized_text_fixture(project.id, %{
          locale_code: "es",
          source_text: "Hello",
          translated_text: "Hola"
        })

      Localization.create_glossary_entry(project, %{
        source_term: "Dragon",
        source_locale: "en",
        target_term: "Dragón",
        target_locale: "es"
      })

      snapshot = ProjectSnapshotBuilder.build_snapshot(project.id)

      assert snapshot["entity_counts"]["languages"] == 2

      assert snapshot["entity_counts"]["localized_texts"] ==
               length(snapshot["localization"]["texts"])

      assert snapshot["entity_counts"]["localized_texts"] >= 3
      assert snapshot["entity_counts"]["glossary_entries"] == 1

      assert length(snapshot["localization"]["languages"]) == 2
      assert length(snapshot["localization"]["glossary"]) == 1

      text_snapshot =
        Enum.find(snapshot["localization"]["texts"], fn entry ->
          entry["source_type"] == text.source_type and entry["source_id"] == text.source_id and
            entry["source_field"] == text.source_field
        end)

      assert text_snapshot["translated_text"] == "Hola"
      assert text_snapshot["content_role"] == "dialogue"
      assert text_snapshot["vo_eligible"]

      [glossary] = snapshot["localization"]["glossary"]
      assert glossary["source_term"] == "Dragon"
      assert glossary["target_term"] == "Dragón"
    end

    test "includes localization voice asset metadata", %{project: project, user: user} do
      source_language_fixture(project, %{locale_code: "en", name: "English"})
      language_fixture(project, %{locale_code: "es", name: "Spanish"})
      voice_asset = uploaded_asset(project, user, "localized-line.mp3", "voice-line", "audio/mpeg")

      text =
        localized_text_fixture(project.id, %{
          locale_code: "es",
          source_text: "Hello",
          translated_text: "Hola"
        })

      {:ok, _text} = Localization.update_text(text, %{vo_asset_id: voice_asset.id, vo_status: "recorded"})

      snapshot = ProjectSnapshotBuilder.build_snapshot(project.id)
      asset_id = to_string(voice_asset.id)

      assert snapshot["asset_blob_hashes"][asset_id] == voice_asset.blob_hash
      assert snapshot["asset_metadata"][asset_id]["blob_key"] =~ "projects/#{project.id}/blobs/"

      text_snapshot =
        Enum.find(snapshot["localization"]["texts"], fn entry ->
          entry["source_type"] == text.source_type and entry["source_id"] == text.source_id and
            entry["source_field"] == text.source_field
        end)

      assert text_snapshot["vo_asset_id"] == voice_asset.id
    end

    test "restores localization data", %{project: project, flow: flow} do
      source_language_fixture(project, %{locale_code: "en", name: "English"})
      language_fixture(project, %{locale_code: "es", name: "Spanish"})

      node =
        node_fixture(flow, %{
          type: "dialogue",
          data: %{"text" => "Hello", "responses" => []}
        })

      text = Localization.get_text_by_source("flow_node", node.id, "text", "es")
      {:ok, text} = Localization.update_text(text, %{translated_text: "Hola"})

      Localization.create_glossary_entry(project, %{
        source_term: "Dragon",
        source_locale: "en",
        target_term: "Dragón",
        target_locale: "es"
      })

      snapshot = ProjectSnapshotBuilder.build_snapshot(project.id)

      # Modify localization data
      Localization.update_text(text, %{translated_text: "Modified"})

      # Restore
      {:ok, _result} = ProjectSnapshotBuilder.restore_snapshot(project.id, snapshot)

      # Verify localization was restored
      languages = Localization.list_languages(project.id)
      assert length(languages) == 2

      restored_text =
        project.id
        |> Localization.list_texts_for_export(["es"])
        |> Enum.find(fn entry ->
          entry.source_type == text.source_type and entry.source_field == text.source_field and
            entry.source_text == "Hello"
        end)

      assert restored_text.translated_text == "Hola"
      assert restored_text.content_role == "dialogue"
      assert restored_text.vo_eligible

      glossary = Localization.list_glossary_for_export(project.id)
      assert length(glossary) == 1
      assert hd(glossary).target_term == "Dragón"
    end

    test "remaps localization when project restore replaces node and block IDs", %{
      project: project,
      sheet: sheet,
      flow: flow
    } do
      source_language_fixture(project, %{locale_code: "en", name: "English"})
      language_fixture(project, %{locale_code: "es", name: "Spanish"})

      node = node_fixture(flow, %{type: "dialogue", data: %{"text" => "Versioned line", "responses" => []}})

      block =
        block_fixture(sheet, %{
          type: "text",
          variable_name: "versioned_bio",
          value: %{"content" => "Versioned bio"}
        })

      [node_text] = Localization.get_texts_for_source("flow_node", node.id)
      [block_text] = Localization.get_texts_for_source("block", block.id)

      assert {:ok, _node_text} =
               Localization.update_text(node_text, %{translated_text: "Línea versionada", status: "final"})

      assert {:ok, _block_text} =
               Localization.update_text(block_text, %{translated_text: "Biografía versionada", status: "final"})

      snapshot = ProjectSnapshotBuilder.build_snapshot(project.id)
      assert {:ok, _result} = ProjectSnapshotBuilder.restore_snapshot(project.id, snapshot)

      restored_flow = Storyarn.Flows.get_flow(project.id, flow.id)
      restored_node = Enum.find(restored_flow.nodes, &((&1.data || %{})["text"] == "Versioned line"))
      restored_block = Enum.find(Storyarn.Sheets.list_blocks(sheet.id), &(&1.variable_name == "versioned_bio"))
      refute restored_node.id == node.id
      refute restored_block.id == block.id

      assert [%{translated_text: "Línea versionada", status: "final"}] =
               Localization.get_texts_for_source("flow_node", restored_node.id)

      assert [%{translated_text: "Biografía versionada", status: "final"}] =
               Localization.get_texts_for_source("block", restored_block.id)

      assert Localization.get_texts_for_source("flow_node", node.id) == []
      assert Localization.get_texts_for_source("block", block.id) == []
    end
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

      Assets.storage_delete(
        BlobStore.blob_key(project.id, asset.blob_hash, BlobStore.ext_from_content_type(content_type))
      )
    end)

    asset
  end
end
