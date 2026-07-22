defmodule Storyarn.Versioning.Builders.ProjectSnapshotBuilderTest do
  use Storyarn.DataCase, async: true

  import Storyarn.AccountsFixtures
  import Storyarn.FlowsFixtures
  import Storyarn.LocalizationFixtures
  import Storyarn.ProjectsFixtures
  import Storyarn.ScenesFixtures
  import Storyarn.SheetsFixtures

  alias Storyarn.Assets
  alias Storyarn.Assets.Asset
  alias Storyarn.Assets.BlobStore
  alias Storyarn.Assets.StorageCompensation
  alias Storyarn.Localization
  alias Storyarn.Projects
  alias Storyarn.Sheets.Sheet
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
    test "drops stale auxiliary foreign keys only where the source role does not support them", %{
      project: project,
      flow: flow
    } do
      source_language_fixture(project, %{locale_code: "en", name: "English"})
      language_fixture(project, %{locale_code: "es", name: "Spanish"})
      speaker = sheet_fixture(project, %{name: "Snapshot speaker"})

      node =
        node_fixture(flow, %{
          type: "dialogue",
          data: %{
            "speaker_sheet_id" => speaker.id,
            "text" => "Spoken line",
            "responses" => [%{"id" => "continue", "text" => "Continue"}]
          }
        })

      assert {:ok, _count} = Localization.extract_all(project.id)

      snapshot = ProjectSnapshotBuilder.build_snapshot(project.id)

      localization =
        update_in(snapshot, ["localization", "texts"], fn texts ->
          Enum.map(texts, fn text ->
            stale_auxiliary_ids = %{
              "vo_asset_id" => 9_999_991,
              "translated_by_id" => 9_999_993,
              "reviewed_by_id" => 9_999_994
            }

            if text["content_role"] in ~w(dialogue response) do
              Map.merge(text, stale_auxiliary_ids)
            else
              Map.merge(text, Map.put(stale_auxiliary_ids, "speaker_sheet_id", 9_999_992))
            end
          end)
        end)

      assert {:ok, _result} = ProjectSnapshotBuilder.restore_snapshot(project.id, localization)

      assert Enum.all?(Localization.list_all_texts(project.id), fn text ->
               is_nil(text.vo_asset_id) and is_nil(text.translated_by_id) and
                 is_nil(text.reviewed_by_id)
             end)

      spoken_rows = Localization.get_texts_for_source("flow_node", node.id)

      assert spoken_rows |> Enum.map(& &1.source_field) |> Enum.sort() ==
               ["response.continue.text", "text"]

      assert Enum.all?(spoken_rows, &(&1.speaker_sheet_id == speaker.id))

      assert project.id
             |> Localization.list_all_texts()
             |> Enum.reject(&(&1.source_type == "flow_node" and &1.source_id == node.id))
             |> Enum.all?(&is_nil(&1.speaker_sheet_id))
    end

    test "recreates a missing voice asset once and keeps global localization attached", %{
      project: project,
      user: user,
      flow: flow
    } do
      source_language_fixture(project, %{locale_code: "en", name: "English"})
      language_fixture(project, %{locale_code: "es", name: "Spanish"})

      node =
        node_fixture(flow, %{
          type: "dialogue",
          data: %{"text" => "Recover this recording", "responses" => []}
        })

      voice_asset =
        uploaded_asset(
          project,
          user,
          "snapshot-voice-#{System.unique_integer([:positive])}.mp3",
          "recorded voice",
          "audio/mpeg"
        )

      text = Localization.get_text_by_source("flow_node", node.id, "text", "es")

      assert {:ok, text} =
               Localization.update_text(text, %{
                 translated_text: "Recupera esta grabación",
                 vo_asset_id: voice_asset.id,
                 vo_status: "recorded"
               })

      snapshot = ProjectSnapshotBuilder.build_snapshot(project.id)

      assert {:ok, _text} =
               Localization.update_text(text, %{
                 vo_asset_id: nil,
                 vo_status: "needed"
               })

      Repo.delete!(voice_asset)

      assert {:ok, _result} =
               ProjectSnapshotBuilder.restore_snapshot(project.id, snapshot, user_id: user.id)

      restored_text =
        Localization.get_text_by_source(
          "flow_node",
          node.id,
          "text",
          "es"
        )

      refute restored_text.vo_asset_id == voice_asset.id
      assert restored_text.vo_status == "recorded"

      restored_asset = Repo.get!(Asset, restored_text.vo_asset_id)
      assert restored_asset.project_id == project.id
      assert restored_asset.blob_hash == voice_asset.blob_hash
      assert {:ok, "recorded voice"} = Assets.storage_download(restored_asset.key)

      assert 1 ==
               Repo.aggregate(
                 from(asset in Asset,
                   where:
                     asset.project_id == ^project.id and
                       asset.blob_hash == ^voice_asset.blob_hash
                 ),
                 :count
               )

      on_exit(fn -> Assets.storage_delete(restored_asset.key) end)
    end
  end

  describe "restore_snapshot/2" do
    test "rejects an empty-root localization restore after the project enters trash", %{
      user: user
    } do
      project = project_fixture(user)
      source = source_language_fixture(project, %{locale_code: "en", name: "English"})
      snapshot = ProjectSnapshotBuilder.build_snapshot(project.id)

      assert snapshot["sheets"] == []
      assert snapshot["flows"] == []
      assert snapshot["scenes"] == []
      assert snapshot["localization"]["languages"] != []

      assert {:ok, _deleted} = Projects.delete_project(project, user.id)

      assert {:error, :project_not_active} =
               ProjectSnapshotBuilder.restore_snapshot(project.id, snapshot)

      assert Localization.get_language(project.id, source.id).name == "English"
    end

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

    test "restores soft-deleted snapshot entities in the exact restore transaction", %{
      project: project,
      sheet: sheet
    } do
      source_language_fixture(project, %{locale_code: "en", name: "English"})
      language_fixture(project, %{locale_code: "es", name: "Spanish"})
      assert {:ok, _count} = Localization.extract_all(project.id)
      snapshot = ProjectSnapshotBuilder.build_snapshot(project.id)

      assert {:ok, _deleted_sheet} = Storyarn.Sheets.delete_sheet(sheet)
      assert Repo.get!(Sheet, sheet.id).deleted_at

      safety_snapshot = ProjectSnapshotBuilder.build_snapshot(project.id)

      assert {:ok, result} =
               ProjectSnapshotBuilder.restore_snapshot(
                 project.id,
                 snapshot,
                 pre_restore_snapshot: safety_snapshot
               )

      assert result.skipped == 0

      restored_sheet = Repo.get!(Sheet, sheet.id)
      assert restored_sheet.id == sheet.id
      assert is_nil(restored_sheet.deleted_at)
      assert Localization.get_texts_for_source("sheet", sheet.id) != []
    end

    test "soft-deletes entities not present in the exact snapshot", %{project: project} do
      snapshot = ProjectSnapshotBuilder.build_snapshot(project.id)

      new_sheet = sheet_fixture(project, %{name: "New After Snapshot"})

      assert {:ok, result} =
               ProjectSnapshotBuilder.restore_snapshot(project.id, snapshot)

      assert result.removed.sheets == 1
      assert Storyarn.Sheets.get_sheet(project.id, new_sheet.id) == nil

      removed_sheet = Repo.get!(Sheet, new_sheet.id)
      assert removed_sheet.name == "New After Snapshot"
      assert removed_sheet.deleted_at
    end

    test "requires an external tracker when composed inside another transaction", %{
      project: project
    } do
      snapshot = ProjectSnapshotBuilder.build_snapshot(project.id)

      assert {:ok, {:error, :asset_copy_tracker_required_in_transaction}} =
               Repo.transaction(fn ->
                 ProjectSnapshotBuilder.restore_snapshot(project.id, snapshot)
               end)
    end

    test "leaves externally supplied tracker lifecycle to its transaction owner", %{
      project: project
    } do
      snapshot = ProjectSnapshotBuilder.build_snapshot(project.id)
      tracker = StorageCompensation.new()
      sentinel_key = "projects/#{project.id}/assets/#{Ecto.UUID.generate()}/tracker-sentinel.bin"
      assert :ok = StorageCompensation.track(tracker, sentinel_key)

      assert {:ok, {:ok, _result}} =
               Repo.transaction(fn ->
                 ProjectSnapshotBuilder.restore_snapshot(project.id, snapshot, asset_copy_tracker: tracker)
               end)

      assert :ok =
               StorageCompensation.cleanup(tracker,
                 enqueue_fun: fn cleanup_keys ->
                   send(self(), {:external_tracker_cleanup, cleanup_keys})
                   :ok
                 end
               )

      assert_receive {:external_tracker_cleanup, [^sentinel_key]}
    end

    test "retains copied asset storage after the restore transaction commits", %{
      project: project,
      user: user,
      sheet: sheet
    } do
      filename = "project-restore-success-#{System.unique_integer([:positive])}.png"
      source_asset = uploaded_asset(project, user, filename, "copied banner", "image/png")
      assert {:ok, _sheet} = Storyarn.Sheets.update_sheet(sheet, %{banner_asset_id: source_asset.id})
      snapshot = ProjectSnapshotBuilder.build_snapshot(project.id)

      assert {:ok, _result} =
               ProjectSnapshotBuilder.restore_snapshot(project.id, snapshot,
                 asset_mode: :copy,
                 user_id: user.id
               )

      restored_sheet = Storyarn.Sheets.get_sheet(project.id, sheet.id)
      restored_asset = Repo.get!(Asset, restored_sheet.banner_asset_id)

      refute restored_asset.id == source_asset.id
      assert {:ok, "copied banner"} = Assets.storage_download(restored_asset.key)
      on_exit(fn -> Assets.storage_delete(restored_asset.key) end)
    end

    test "rolls back database writes and compensates copied storage when a later entity fails", %{
      project: project,
      user: user,
      sheet: sheet,
      flow: flow
    } do
      filename = "project-restore-rollback-#{System.unique_integer([:positive])}.png"
      source_asset = uploaded_asset(project, user, filename, "rollback banner", "image/png")
      assert {:ok, _sheet} = Storyarn.Sheets.update_sheet(sheet, %{banner_asset_id: source_asset.id})

      broken_snapshot =
        project.id
        |> ProjectSnapshotBuilder.build_snapshot()
        |> update_in(["flows"], fn flows ->
          Enum.map(flows, fn
            %{"id" => flow_id, "snapshot" => flow_snapshot} = entry
            when flow_id == flow.id ->
              Map.put(entry, "snapshot", Map.delete(flow_snapshot, "name"))

            entry ->
              entry
          end)
        end)

      asset_count_before = Repo.aggregate(Asset, :count)
      stored_paths_before = stored_asset_paths(filename)

      assert {:error, {:restore_failed, "flows", flow_id, {:missing_snapshot_fields, :flow, ["name"]}}} =
               ProjectSnapshotBuilder.restore_snapshot(project.id, broken_snapshot,
                 asset_mode: :copy,
                 user_id: user.id
               )

      assert flow_id == flow.id
      assert Repo.aggregate(Asset, :count) == asset_count_before

      assert Storyarn.Sheets.get_sheet(project.id, sheet.id).banner_asset_id ==
               source_asset.id

      assert stored_asset_paths(filename) == stored_paths_before
      assert {:ok, "rollback banner"} = Assets.storage_download(source_asset.key)
    end

    test "preserves a localization asset error after compensating earlier copies", %{
      project: project,
      user: user,
      sheet: sheet,
      flow: flow
    } do
      source_language_fixture(project, %{locale_code: "en", name: "English"})
      language_fixture(project, %{locale_code: "es", name: "Spanish"})

      dialogue =
        node_fixture(flow, %{
          type: "dialogue",
          data: %{"text" => "Missing recorded line", "responses" => []}
        })

      filename = "project-restore-asset-error-#{System.unique_integer([:positive])}.png"
      source_asset = uploaded_asset(project, user, filename, "cleanup banner", "image/png")
      assert {:ok, _sheet} = Storyarn.Sheets.update_sheet(sheet, %{banner_asset_id: source_asset.id})

      missing_asset_id = 9_000_000_000 + System.unique_integer([:positive])
      missing_content = "missing global voice"
      missing_hash = BlobStore.compute_hash(missing_content)
      asset_id = to_string(missing_asset_id)

      broken_snapshot =
        project.id
        |> ProjectSnapshotBuilder.build_snapshot()
        |> update_in(["localization", "texts"], fn texts ->
          Enum.map(texts, fn
            %{
              "source_type" => "flow_node",
              "source_id" => source_id,
              "source_field" => "text"
            } = text
            when source_id == dialogue.id ->
              Map.merge(text, %{
                "vo_asset_id" => missing_asset_id,
                "vo_status" => "recorded"
              })

            text ->
              text
          end)
        end)
        |> put_in(["asset_blob_hashes", asset_id], missing_hash)
        |> put_in(["asset_metadata", asset_id], %{
          "filename" => "missing-global-voice.mp3",
          "content_type" => "audio/mpeg",
          "size" => byte_size(missing_content),
          "project_id" => project.id
        })

      asset_count_before = Repo.aggregate(Asset, :count)
      stored_paths_before = stored_asset_paths(filename)

      assert {:error, {:asset_materialization_failed, ^missing_asset_id, {:asset_blob_unavailable, :enoent}}} =
               ProjectSnapshotBuilder.restore_snapshot(project.id, broken_snapshot,
                 asset_mode: :copy,
                 user_id: user.id
               )

      assert Repo.aggregate(Asset, :count) == asset_count_before
      assert Storyarn.Sheets.get_sheet(project.id, sheet.id).banner_asset_id == source_asset.id
      assert stored_asset_paths(filename) == stored_paths_before
    end
  end

  describe "localization in snapshot" do
    test "includes localization data for sources in the active project graph", %{
      project: project,
      flow: flow
    } do
      source_language_fixture(project, %{locale_code: "en", name: "English"})
      language_fixture(project, %{locale_code: "es", name: "Spanish"})

      node =
        node_fixture(flow, %{
          type: "dialogue",
          data: %{"text" => "Hello", "responses" => []}
        })

      text = Localization.get_text_by_source("flow_node", node.id, "text", "es")
      assert {:ok, text} = Localization.update_text(text, %{translated_text: "Hola"})

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

    test "includes localization voice asset metadata", %{
      project: project,
      user: user,
      flow: flow
    } do
      source_language_fixture(project, %{locale_code: "en", name: "English"})
      language_fixture(project, %{locale_code: "es", name: "Spanish"})
      voice_asset = uploaded_asset(project, user, "localized-line.mp3", "voice-line", "audio/mpeg")

      node =
        node_fixture(flow, %{
          type: "dialogue",
          data: %{"text" => "Localized voice line", "responses" => []}
        })

      text = Localization.get_text_by_source("flow_node", node.id, "text", "es")

      {:ok, text} =
        Localization.update_text(text, %{
          translated_text: "Línea de voz localizada",
          vo_asset_id: voice_asset.id,
          vo_status: "recorded"
        })

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

    test "rejects localization voice assets owned by another project", %{
      project: project,
      user: user,
      flow: flow
    } do
      source_language_fixture(project, %{locale_code: "en", name: "English"})
      language_fixture(project, %{locale_code: "es", name: "Spanish"})

      foreign_project = project_fixture(user)

      foreign_voice =
        uploaded_asset(
          foreign_project,
          user,
          "foreign-localized-line.mp3",
          "foreign voice",
          "audio/mpeg"
        )

      node =
        node_fixture(flow, %{
          type: "dialogue",
          data: %{"text" => "Corrupt foreign voice", "responses" => []}
        })

      text = Localization.get_text_by_source("flow_node", node.id, "text", "es")

      # The public writer now rejects this corruption. Inject it below the
      # context boundary to retain coverage for the snapshot builder's
      # defensive ownership check.
      text
      |> Ecto.Changeset.change(
        vo_asset_id: foreign_voice.id,
        vo_status: "recorded"
      )
      |> Repo.update!()

      assert_raise ArgumentError, ~r/owned by another project/, fn ->
        ProjectSnapshotBuilder.build_snapshot(project.id)
      end
    end

    test "rejects localization voice assets whose recovery blob is unavailable", %{
      project: project,
      user: user,
      flow: flow
    } do
      source_language_fixture(project, %{locale_code: "en", name: "English"})
      language_fixture(project, %{locale_code: "es", name: "Spanish"})

      voice_asset =
        uploaded_asset(
          project,
          user,
          "missing-localized-line.mp3",
          "missing voice",
          "audio/mpeg"
        )

      node =
        node_fixture(flow, %{
          type: "dialogue",
          data: %{"text" => "Missing localized voice", "responses" => []}
        })

      text = Localization.get_text_by_source("flow_node", node.id, "text", "es")

      assert {:ok, _text} =
               Localization.update_text(text, %{
                 vo_asset_id: voice_asset.id,
                 vo_status: "recorded"
               })

      delete_storage_blob(
        BlobStore.blob_key(
          project.id,
          voice_asset.blob_hash,
          BlobStore.ext_from_content_type(voice_asset.content_type)
        )
      )

      assert_raise ArgumentError, ~r/asset_blob_unavailable/, fn ->
        ProjectSnapshotBuilder.build_snapshot(project.id)
      end
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

    test "keeps localization attached when project restore preserves node and block IDs", %{
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
      assert restored_node.id == node.id
      assert restored_block.id == block.id

      assert [%{translated_text: "Línea versionada", status: "final"}] =
               Localization.get_texts_for_source("flow_node", restored_node.id)

      assert [%{translated_text: "Biografía versionada", status: "final"}] =
               Localization.get_texts_for_source("block", restored_block.id)
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

      delete_storage_blob(BlobStore.blob_key(project.id, asset.blob_hash, BlobStore.ext_from_content_type(content_type)))
    end)

    asset
  end

  defp stored_asset_paths(filename) do
    upload_dir =
      :storyarn
      |> Application.fetch_env!(:storage)
      |> Keyword.fetch!(:upload_dir)
      |> Path.expand()

    upload_dir
    |> Path.join("projects/*/assets/*/#{filename}")
    |> Path.wildcard()
    |> MapSet.new()
  end
end
