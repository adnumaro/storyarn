defmodule Storyarn.Flows.Versioning.FlowSnapshotRestoreTest do
  use Storyarn.DataCase, async: false

  import Storyarn.AccountsFixtures
  import Storyarn.FlowsFixtures
  import Storyarn.LocalizationFixtures
  import Storyarn.ProjectsFixtures
  import Storyarn.ScenesFixtures, only: [scene_fixture: 1]
  import Storyarn.SheetsFixtures

  alias Storyarn.Assets
  alias Storyarn.Assets.Asset
  alias Storyarn.Assets.BlobStore
  alias Storyarn.Flows
  alias Storyarn.Flows.Flow
  alias Storyarn.Flows.FlowConnection
  alias Storyarn.Flows.FlowNode
  alias Storyarn.Flows.SequenceConfig
  alias Storyarn.Flows.SequenceTrack
  alias Storyarn.Flows.SequenceVisualLayer
  alias Storyarn.Flows.VariableReference
  alias Storyarn.Flows.Versioning.FlowSnapshot
  alias Storyarn.Flows.Versioning.LocalizationCodec
  alias Storyarn.Localization
  alias Storyarn.Localization.LocalizedText
  alias Storyarn.Projects.Project
  alias Storyarn.References
  alias Storyarn.Repo
  alias Storyarn.Sheets.EntityReference
  alias Storyarn.Versioning.EntityVersion

  setup do
    user = user_fixture(%{email: "flow-snapshot-restore-#{Ecto.UUID.generate()}@example.com"})
    project = project_fixture(user)
    flow = flow_fixture(project)

    %{user: user, project: project, flow: flow}
  end

  describe "restore_snapshot/3" do
    test "rejects a restore when its verified safety-version record is no longer durable", %{
      user: user,
      project: project,
      flow: flow
    } do
      target_snapshot = FlowSnapshot.build_snapshot(flow)
      {:ok, current_flow} = Flows.update_flow(flow, %{name: "Current state"})
      pre_restore_snapshot = FlowSnapshot.build_snapshot(current_flow)

      safety_version =
        %EntityVersion{}
        |> EntityVersion.changeset(%{
          entity_type: "flow",
          entity_id: flow.id,
          project_id: project.id,
          created_by_id: user.id,
          version_number: 1,
          storage_key: "snapshots/flow/#{flow.id}/1-safety.json.gz",
          snapshot_size_bytes: 1,
          checksum: String.duplicate("a", 64)
        })
        |> Repo.insert!()

      identity = entity_version_identity(safety_version)
      Repo.delete!(safety_version)

      assert {:error, :pre_restore_version_not_durable} =
               FlowSnapshot.restore_snapshot(current_flow, target_snapshot,
                 restore_action: {:entity_version_restore, "flow"},
                 user_id: user.id,
                 pre_restore_snapshot: pre_restore_snapshot,
                 pre_restore_version_identity: identity
               )

      assert Repo.get!(Flow, flow.id).name == "Current state"
    end

    test "does not overwrite a change made after the pre-restore snapshot", %{
      flow: flow
    } do
      target_snapshot = FlowSnapshot.build_snapshot(flow)
      {:ok, current_flow} = Flows.update_flow(flow, %{name: "Before safety"})
      pre_restore_snapshot = FlowSnapshot.build_snapshot(current_flow)
      {:ok, concurrent_flow} = Flows.update_flow(current_flow, %{name: "Concurrent change"})

      assert {:error, :flow_changed_since_pre_restore_snapshot} =
               FlowSnapshot.restore_snapshot(concurrent_flow, target_snapshot,
                 restore_action: {:entity_version_restore, "flow"},
                 pre_restore_snapshot: pre_restore_snapshot
               )

      assert Repo.get!(Flow, flow.id).name == "Concurrent change"
    end

    test "accepts the persisted JSON form of a matching localized pre-restore snapshot", %{
      project: project,
      flow: flow
    } do
      _en = source_language_fixture(project, %{locale_code: "en", name: "English"})
      _es = language_fixture(project, %{locale_code: "es", name: "Spanish"})

      node =
        node_fixture(flow, %{
          type: "dialogue",
          data: %{"text" => "Current localized line", "responses" => []}
        })

      [text] = Localization.get_texts_for_source("flow_node", node.id)
      timestamp = ~U[2026-08-12 12:30:00Z]

      assert {:ok, _translated} =
               Localization.update_text(text, %{
                 translated_text: "Línea localizada actual",
                 status: "final",
                 last_translated_at: timestamp
               })

      current_snapshot = FlowSnapshot.build_snapshot(flow)

      persisted_pre_restore_snapshot =
        current_snapshot
        |> Jason.encode!()
        |> Jason.decode!()

      target_snapshot = Map.put(current_snapshot, "name", "Historical name")

      assert {:ok, restored} =
               FlowSnapshot.restore_snapshot(flow, target_snapshot,
                 restore_action: {:entity_version_restore, "flow"},
                 pre_restore_snapshot: persisted_pre_restore_snapshot
               )

      assert restored.name == "Historical name"
    end

    test "restores flow with nodes and connections", %{flow: flow} do
      n1 =
        node_fixture(flow, %{
          type: "dialogue",
          position_x: 100.0,
          position_y: 100.0,
          data: %{"text" => "One two three", "responses" => []}
        })

      n2 = node_fixture(flow, %{type: "hub", position_x: 200.0, position_y: 100.0})
      conn = connection_fixture(flow, n1, n2)

      snapshot = FlowSnapshot.build_snapshot(flow)

      # Modify the flow
      {:ok, modified_flow} = Flows.update_flow(flow, %{name: "Modified"})
      {:ok, _deleted_node, _meta} = Flows.delete_node(n1)
      assert Repo.get!(FlowNode, n1.id).deleted_at

      # Restore
      {:ok, restored} =
        FlowSnapshot.restore_snapshot(modified_flow, snapshot, restore_action: {:entity_version_restore, "flow"})

      assert restored.name == flow.name

      restored = Repo.preload(restored, [:nodes, :connections], force: true)
      # Should have the same number of non-deleted nodes
      active_nodes = Enum.reject(restored.nodes, &(&1.deleted_at != nil))
      assert length(active_nodes) == length(snapshot["nodes"])
      assert length(restored.connections) == 1
      assert Enum.find(active_nodes, &(&1.type == "dialogue")).word_count == 3
      assert Repo.get!(FlowNode, n1.id).deleted_at == nil
      assert Repo.get!(FlowNode, n2.id).deleted_at == nil
      assert Repo.get!(FlowConnection, conn.id).source_node_id == n1.id
    end

    test "returns only the restored Flow and preserves entity identity", %{flow: flow} do
      snapshot = FlowSnapshot.build_snapshot(flow)
      {:ok, current_flow} = Flows.update_flow(flow, %{name: "Current name"})

      assert {:ok, %Flow{id: restored_id, name: restored_name}} =
               FlowSnapshot.restore_snapshot(current_flow, snapshot, restore_action: {:entity_version_restore, "flow"})

      assert restored_id == flow.id
      assert restored_name == flow.name
    end

    test "rejects empty, entry-less, duplicate-entry, and exit-less graphs without writing", %{
      flow: flow
    } do
      snapshot = FlowSnapshot.build_snapshot(flow)
      entry = Enum.find(snapshot["nodes"], &(&1["type"] == "entry"))
      next_id = snapshot["nodes"] |> Enum.map(& &1["original_id"]) |> Enum.max() |> Kernel.+(1)

      invalid_snapshots = [
        {{:invalid_snapshot_entry_count, 0},
         snapshot
         |> Map.put("nodes", [])
         |> Map.put("connections", [])},
        {{:invalid_snapshot_entry_count, 0},
         Map.update!(snapshot, "nodes", &Enum.reject(&1, fn node -> node["type"] == "entry" end))},
        {{:invalid_snapshot_entry_count, 2},
         Map.update!(snapshot, "nodes", &[Map.put(entry, "original_id", next_id) | &1])},
        {{:invalid_snapshot_exit_count, 0},
         Map.update!(snapshot, "nodes", &Enum.reject(&1, fn node -> node["type"] == "exit" end))}
      ]

      {:ok, current_flow} = Flows.update_flow(flow, %{name: "Current state"})
      post_snapshot_node = node_fixture(flow, %{type: "hub", position_x: 900.0})
      initial_node_ids = flow_node_ids(flow.id)

      for {expected_error, invalid_snapshot} <- invalid_snapshots do
        assert {:error, ^expected_error} =
                 FlowSnapshot.restore_snapshot(current_flow, invalid_snapshot,
                   restore_action: {:entity_version_restore, "flow"}
                 )

        assert Repo.get!(Flow, flow.id).name == "Current state"
        assert Repo.get!(FlowNode, post_snapshot_node.id).deleted_at == nil
        assert flow_node_ids(flow.id) == initial_node_ids
      end
    end

    test "restores translations on stable flow node IDs", %{project: project, flow: flow} do
      _en = source_language_fixture(project, %{locale_code: "en", name: "English"})
      _es = language_fixture(project, %{locale_code: "es", name: "Spanish"})
      node = node_fixture(flow, %{type: "dialogue", data: %{"text" => "Hello", "responses" => []}})
      [text] = Localization.get_texts_for_source("flow_node", node.id)

      assert {:ok, versioned_text} =
               Localization.update_text(text, %{
                 translated_text: "Hola",
                 status: "final",
                 translator_notes: "Versioned note"
               })

      snapshot = FlowSnapshot.build_snapshot(flow)
      assert [%{"translated_text" => "Hola"}] = snapshot["localization"]

      assert {:ok, restored} =
               FlowSnapshot.restore_snapshot(flow, snapshot, restore_action: {:entity_version_restore, "flow"})

      restored_node = Enum.find(restored.nodes, &(&1.type == "dialogue"))
      assert restored_node.id == node.id

      assert [restored_text] = Localization.get_texts_for_source("flow_node", restored_node.id)
      assert restored_text.id == text.id
      assert restored_text.translated_text == "Hola"
      assert restored_text.status == "final"
      assert restored_text.translator_notes == "Versioned note"
      assert restored_text.lock_version > versioned_text.lock_version

      assert {:error, stale_changeset} =
               Localization.update_text(versioned_text, %{
                 translated_text: "Stale overwrite",
                 status: "draft"
               })

      assert Keyword.has_key?(stale_changeset.errors, :lock_version)
      assert Repo.get!(LocalizedText, text.id).translated_text == "Hola"

      assert [single_text] =
               project.id
               |> Localization.list_all_texts(source_type: "flow_node", include_archived: true)
               |> Enum.filter(&(&1.source_id == node.id))

      assert is_nil(single_text.archived_at)
    end

    test "preserves a target locale archived after the snapshot byte-for-byte", %{
      project: project,
      flow: flow
    } do
      _en = source_language_fixture(project, %{locale_code: "en", name: "English"})
      _es = language_fixture(project, %{locale_code: "es", name: "Spanish"})
      fr = language_fixture(project, %{locale_code: "fr", name: "French"})
      node = node_fixture(flow, %{type: "dialogue", data: %{"text" => "Historical line", "responses" => []}})

      fr_text =
        "flow_node"
        |> Localization.get_texts_for_source(node.id)
        |> Enum.find(&(&1.locale_code == "fr"))

      assert {:ok, _translated} =
               Localization.update_text(fr_text, %{
                 translated_text: "Ligne historique",
                 status: "final",
                 reviewer_notes: "Preserve exactly"
               })

      snapshot = FlowSnapshot.build_snapshot(flow)
      assert length(snapshot["localization"]) == 2
      assert snapshot["localization_manifest"]["target_locales"] == ["es", "fr"]

      assert {:ok, _archived_fr} = Localization.remove_language(fr)

      assert {:ok, _current_node, _meta} =
               Flows.update_node_data(node, %{"text" => "Current line", "responses" => []})

      Repo.update_all(
        from(text in LocalizedText,
          where:
            text.project_id == ^project.id and text.source_type == "flow_node" and
              text.source_id == ^node.id and text.locale_code == "fr"
        ),
        set: [reviewer_notes: "State after language archive"],
        inc: [lock_version: 1]
      )

      archived_locale_state =
        project.id
        |> Localization.list_all_texts(source_type: "flow_node", include_archived: true)
        |> Enum.filter(&(&1.source_id == node.id and &1.locale_code == "fr"))

      assert [_fr_text] = archived_locale_state

      assert {:ok, _restored} =
               FlowSnapshot.restore_snapshot(flow, snapshot, restore_action: {:entity_version_restore, "flow"})

      assert project.id
             |> Localization.list_all_texts(source_type: "flow_node", include_archived: true)
             |> Enum.filter(&(&1.source_id == node.id and &1.locale_code == "fr")) ==
               archived_locale_state
    end

    test "recreates and remaps a deleted versioned voice asset", %{
      user: user,
      project: project,
      flow: flow
    } do
      _en = source_language_fixture(project, %{locale_code: "en", name: "English"})
      _es = language_fixture(project, %{locale_code: "es", name: "Spanish"})
      voice = uploaded_asset(project, user, "versioned-voice.mp3", "voice", "audio/mpeg")
      node = node_fixture(flow, %{type: "dialogue", data: %{"text" => "Historical line", "responses" => []}})
      [text] = Localization.get_texts_for_source("flow_node", node.id)

      assert {:ok, recorded_text} =
               Localization.update_text(text, %{
                 translated_text: "Línea histórica",
                 status: "final",
                 vo_asset_id: voice.id,
                 vo_status: "recorded"
               })

      snapshot = FlowSnapshot.build_snapshot(flow)
      assert [%{"vo_asset_id" => voice_id, "vo_status" => "recorded"}] = snapshot["localization"]
      assert voice_id == voice.id
      assert snapshot["asset_blob_hashes"][to_string(voice.id)] == voice.blob_hash
      assert snapshot["asset_metadata"][to_string(voice.id)]["project_id"] == project.id

      assert {:ok, _current_text} =
               Localization.update_text(recorded_text, %{
                 translated_text: "Current line",
                 status: "final",
                 vo_asset_id: nil,
                 vo_status: "needed"
               })

      assert {:ok, _deleted_voice} = Assets.delete_asset(voice)

      {:ok, current_flow} = Flows.update_flow(flow, %{name: "Current flow"})

      assert {:ok, current_node, _meta} =
               Flows.update_node_data(node, %{"text" => "Current line", "responses" => []})

      assert {:ok, _restored_flow} =
               FlowSnapshot.restore_snapshot(current_flow, snapshot, restore_action: {:entity_version_restore, "flow"})

      refute Repo.get!(FlowNode, node.id).data == current_node.data

      assert [%LocalizedText{vo_asset_id: restored_voice_id, vo_status: "recorded"}] =
               Localization.get_texts_for_source("flow_node", node.id)

      refute restored_voice_id == voice.id
      restored_voice = Repo.get!(Asset, restored_voice_id)
      assert restored_voice.project_id == project.id
      assert restored_voice.blob_hash == voice.blob_hash
      assert {:ok, "voice"} = Assets.storage_download(restored_voice.key)
      on_exit(fn -> Assets.storage_delete(restored_voice.key) end)
    end

    test "rolls back when a versioned asset blob is unavailable", %{
      user: user,
      project: project,
      flow: flow
    } do
      audio =
        uploaded_asset(
          project,
          user,
          "unavailable.mp3",
          "unavailable audio",
          "audio/mpeg"
        )

      node =
        node_fixture(flow, %{
          type: "dialogue",
          data: %{
            "text" => "Historical line",
            "responses" => [],
            "audio_asset_id" => audio.id
          }
        })

      snapshot = FlowSnapshot.build_snapshot(flow)

      assert {:ok, updated_node, _meta} =
               Flows.update_node_data(
                 node,
                 %{"text" => "Current line", "responses" => []}
               )

      assert {:ok, _deleted_asset} = Assets.delete_asset(audio)

      delete_storage_blob(
        BlobStore.blob_key(
          project.id,
          audio.blob_hash,
          BlobStore.ext_from_content_type(audio.content_type)
        )
      )

      assert {:ok, current_flow} = Flows.update_flow(flow, %{name: "Current flow"})

      assert {:error, {:snapshot_asset_blob_unavailable, :enoent}} =
               FlowSnapshot.restore_snapshot(current_flow, snapshot, restore_action: {:entity_version_restore, "flow"})

      assert Repo.get!(Flow, flow.id).name == "Current flow"
      assert Repo.get!(FlowNode, node.id).data == updated_node.data
    end

    test "rejects wrong MIME families for every Flow asset slot before writing", %{
      user: user,
      project: project,
      flow: flow
    } do
      _en = source_language_fixture(project, %{locale_code: "en", name: "English"})
      _es = language_fixture(project, %{locale_code: "es", name: "Spanish"})
      audio = uploaded_asset(project, user, "mime-audio.mp3", "audio bytes", "audio/mpeg")
      image = uploaded_asset(project, user, "mime-image.png", "image bytes", "image/png")

      dialogue =
        node_fixture(flow, %{
          type: "dialogue",
          data: %{
            "text" => "MIME line",
            "responses" => [],
            "audio_asset_id" => audio.id
          }
        })

      [localized_text] = Localization.get_texts_for_source("flow_node", dialogue.id)

      assert {:ok, _localized_text} =
               Localization.update_text(localized_text, %{
                 translated_text: "Línea MIME",
                 status: "final",
                 vo_asset_id: audio.id,
                 vo_status: "recorded"
               })

      {:ok, sequence} =
        Flows.create_sequence(flow.id, %{
          "name" => "MIME sequence",
          "width" => 640.0,
          "height" => 360.0
        })

      assert {:ok, track} =
               Flows.upsert_sequence_track(sequence.id, "music", %{
                 "asset_id" => audio.id
               })

      assert {:ok, layer} =
               Flows.create_sequence_visual_layer(sequence.id, %{
                 "asset_id" => image.id,
                 "kind" => "backdrop",
                 "label" => "Backdrop"
               })

      snapshot = FlowSnapshot.build_snapshot(flow)
      assert {:ok, current_flow} = Flows.update_flow(flow, %{name: "Keep MIME state"})

      invalid_snapshots = [
        {:flow_node_audio, image.id, "image/png",
         update_snapshot_node(snapshot, dialogue.id, fn node ->
           put_in(node, ["data", "audio_asset_id"], image.id)
         end)},
        {:sequence_track, image.id, "image/png",
         update_snapshot_node(snapshot, sequence.id, fn node ->
           update_in(node["sequence_tracks"], fn [track_data] ->
             [Map.put(track_data, "asset_id", image.id)]
           end)
         end)},
        {:sequence_visual_layer, audio.id, "audio/mpeg",
         update_snapshot_node(snapshot, sequence.id, fn node ->
           update_in(node["sequence_visual_layers"], fn [layer_data] ->
             [Map.put(layer_data, "asset_id", audio.id)]
           end)
         end)},
        {:localized_text_voice_over, image.id, "image/png",
         snapshot
         |> Map.update!("localization", fn [row] ->
           [Map.put(row, "vo_asset_id", image.id)]
         end)
         |> then(fn updated_snapshot ->
           Map.put(
             updated_snapshot,
             "localization_manifest",
             LocalizationCodec.manifest(
               updated_snapshot["localization"],
               snapshot["localization_manifest"]["target_locales"]
             )
           )
         end)}
      ]

      for {context, wrong_asset_id, content_type, invalid_snapshot} <- invalid_snapshots do
        assert {:error,
                {:snapshot_asset_blob_unavailable,
                 {:invalid_asset_content_type, ^context, ^wrong_asset_id, ^content_type}}} =
                 FlowSnapshot.restore_snapshot(current_flow, invalid_snapshot,
                   restore_action: {:entity_version_restore, "flow"}
                 )

        assert Repo.get!(Flow, flow.id).name == "Keep MIME state"
        assert Repo.get!(FlowNode, dialogue.id).data["audio_asset_id"] == audio.id
        assert Repo.get!(SequenceTrack, track.id).asset_id == audio.id
        assert Repo.get!(SequenceVisualLayer, layer.id).asset_id == image.id

        assert [%LocalizedText{vo_asset_id: voice_id}] =
                 Localization.get_texts_for_source("flow_node", dialogue.id)

        assert voice_id == audio.id
      end

      assert {:ok, _deleted_layer} = Flows.delete_sequence_visual_layer(layer)
      assert {:ok, _deleted_image} = Assets.delete_asset(image)

      historical_wrong_mime =
        update_snapshot_node(snapshot, dialogue.id, fn node ->
          put_in(node, ["data", "audio_asset_id"], image.id)
        end)

      assert {:error,
              {:snapshot_asset_blob_unavailable, {:invalid_asset_content_type, :flow_node_audio, image_id, "image/png"}}} =
               FlowSnapshot.restore_snapshot(current_flow, historical_wrong_mime,
                 restore_action: {:entity_version_restore, "flow"}
               )

      assert image_id == image.id
      assert Repo.get!(Flow, flow.id).name == "Keep MIME state"
    end

    test "rejects an asset catalog entry owned by another project before writing", %{
      user: user,
      project: project,
      flow: flow
    } do
      audio = uploaded_asset(project, user, "owned.mp3", "shared bytes", "audio/mpeg")
      foreign_project = project_fixture(user)

      _foreign_audio =
        uploaded_asset(
          foreign_project,
          user,
          "foreign.mp3",
          "shared bytes",
          "audio/mpeg"
        )

      node =
        node_fixture(flow, %{
          type: "dialogue",
          data: %{
            "text" => "Historical line",
            "responses" => [],
            "audio_asset_id" => audio.id
          }
        })

      snapshot = FlowSnapshot.build_snapshot(flow)

      cross_project_catalog =
        put_in(
          snapshot,
          ["asset_metadata", to_string(audio.id), "project_id"],
          foreign_project.id
        )

      {:ok, current_flow} = Flows.update_flow(flow, %{name: "Current flow"})

      assert {:error, {:snapshot_asset_blob_unavailable, :invalid_snapshot_asset_catalog_entry}} =
               FlowSnapshot.restore_snapshot(current_flow, cross_project_catalog,
                 restore_action: {:entity_version_restore, "flow"}
               )

      assert Repo.get!(Flow, flow.id).name == "Current flow"
      assert Repo.get!(FlowNode, node.id).data["audio_asset_id"] == audio.id
    end

    test "round-trips speaker IDs for dialogue and response localization", %{
      project: project,
      flow: flow
    } do
      _en = source_language_fixture(project, %{locale_code: "en", name: "English"})
      _es = language_fixture(project, %{locale_code: "es", name: "Spanish"})
      speaker = sheet_fixture(project)

      node =
        node_fixture(flow, %{
          type: "dialogue",
          data: %{
            "text" => "Hello",
            "speaker_sheet_id" => speaker.id,
            "responses" => [%{"id" => "continue", "text" => "Continue"}]
          }
        })

      snapshot = FlowSnapshot.build_snapshot(flow)

      assert Enum.all?(
               snapshot["localization"],
               &(&1["speaker_sheet_id"] == speaker.id)
             )

      assert {:ok, _restored} =
               FlowSnapshot.restore_snapshot(flow, snapshot, restore_action: {:entity_version_restore, "flow"})

      restored_rows = Localization.get_texts_for_source("flow_node", node.id)
      assert restored_rows |> Enum.map(& &1.source_field) |> Enum.sort() == ["response.continue.text", "text"]
      assert Enum.all?(restored_rows, &(&1.speaker_sheet_id == speaker.id))
    end

    test "restores historical locales and reconciles a target locale added later", %{
      project: project,
      flow: flow
    } do
      _en = source_language_fixture(project, %{locale_code: "en", name: "English"})
      _es = language_fixture(project, %{locale_code: "es", name: "Spanish"})
      node = node_fixture(flow, %{type: "dialogue", data: %{"text" => "Historical line", "responses" => []}})

      snapshot = FlowSnapshot.build_snapshot(flow)
      assert snapshot["localization_manifest"]["target_locales"] == ["es"]

      _fr = language_fixture(project, %{locale_code: "fr", name: "French"})

      fr_text =
        "flow_node"
        |> Localization.get_texts_for_source(node.id)
        |> Enum.find(&(&1.locale_code == "fr"))

      assert {:ok, translated_fr} =
               Localization.update_text(fr_text, %{
                 translated_text: "Traduction actuelle",
                 status: "final"
               })

      assert {:ok, _current_node, _meta} =
               Flows.update_node_data(node, %{"text" => "Current line", "responses" => []})

      assert {:ok, _restored} =
               FlowSnapshot.restore_snapshot(flow, snapshot, restore_action: {:entity_version_restore, "flow"})

      restored_fr = Repo.get!(LocalizedText, translated_fr.id)
      assert restored_fr.translated_text == "Traduction actuelle"
      assert restored_fr.source_text == "Historical line"
      assert restored_fr.status != "final"
    end

    test "keeps an empty localization inventory bound to its historical target locales", %{
      project: project,
      flow: flow
    } do
      _en = source_language_fixture(project, %{locale_code: "en", name: "English"})
      _es = language_fixture(project, %{locale_code: "es", name: "Spanish"})
      _hub = node_fixture(flow, %{type: "hub"})

      snapshot = FlowSnapshot.build_snapshot(flow)

      assert snapshot["localization"] == []
      assert snapshot["localization_manifest"]["target_locales"] == ["es"]

      assert :ok =
               LocalizationCodec.validate_manifest(
                 [],
                 snapshot["localization_manifest"]
               )

      {:ok, modified_flow} = Flows.update_flow(flow, %{name: "Current flow"})

      assert {:ok, restored} =
               FlowSnapshot.restore_snapshot(modified_flow, snapshot, restore_action: {:entity_version_restore, "flow"})

      assert restored.name == flow.name
    end

    test "rolls back a restore when transactional localization extraction raises", %{
      project: project,
      flow: flow
    } do
      node =
        node_fixture(flow, %{
          type: "dialogue",
          data: %{"speaker" => "Narrator", "text" => "Hello", "responses" => []}
        })

      snapshot = FlowSnapshot.build_snapshot(flow)
      {:ok, modified_flow} = Flows.update_flow(flow, %{name: "Keep this name"})
      _language = language_fixture(project, %{locale_code: "es", name: "Spanish"})
      constraint_name = "localized_texts_restore_#{System.unique_integer([:positive])}"

      Repo.query!(
        "ALTER TABLE localized_texts ADD CONSTRAINT #{constraint_name} " <>
          "CHECK (project_id <> #{project.id}) NOT VALID"
      )

      assert_raise Postgrex.Error, ~r/#{constraint_name}/, fn ->
        FlowSnapshot.restore_snapshot(modified_flow, snapshot, restore_action: {:entity_version_restore, "flow"})
      end

      assert Repo.reload!(modified_flow).name == "Keep this name"
      assert Repo.get!(FlowNode, node.id).flow_id == modified_flow.id
    end

    test "round-trips nested sequence resources", %{user: user, project: project, flow: flow} do
      audio = uploaded_asset(project, user, "restore.mp3", "restore audio", "audio/mpeg")
      image = uploaded_asset(project, user, "restore.png", "restore image", "image/png")

      {:ok, sequence} =
        Flows.create_sequence(flow.id, %{
          "name" => "Original sequence",
          "width" => 500.0,
          "height" => 280.0
        })

      _child = node_fixture(flow, %{type: "hub", parent_id: sequence.id, position_x: 150.0})

      {:ok, track} =
        Flows.upsert_sequence_track(sequence.id, "ambience", %{
          "asset_id" => audio.id,
          "volume" => Decimal.new("0.4")
        })

      {:ok, layer} =
        Flows.create_sequence_visual_layer(sequence.id, %{
          "asset_id" => image.id,
          "kind" => "overlay",
          "label" => "Mist",
          "opacity" => 0.6
        })

      snapshot = FlowSnapshot.build_snapshot(flow)

      assert {:ok, :cleared} = Flows.clear_sequence_track(sequence.id, "ambience")

      assert {:ok, replacement_track} =
               Flows.upsert_sequence_track(sequence.id, "ambience", %{
                 "asset_id" => audio.id,
                 "volume" => Decimal.new("0.9")
               })

      assert {:ok, _deleted_layer} = Flows.delete_sequence_visual_layer(layer)

      assert {:ok, replacement_layer} =
               Flows.create_sequence_visual_layer(sequence.id, %{
                 "asset_id" => image.id,
                 "kind" => "overlay",
                 "label" => "Replacement"
               })

      assert {:ok, _updated_sequence} =
               Flows.update_sequence(sequence, %{
                 "name" => "Modified sequence",
                 "width" => 700.0,
                 "height" => 400.0
               })

      assert {:ok, restored} =
               FlowSnapshot.restore_snapshot(flow, snapshot, restore_action: {:entity_version_restore, "flow"})

      rebuilt_snapshot = FlowSnapshot.build_snapshot(restored)

      assert FlowSnapshot.diff_snapshots(snapshot, rebuilt_snapshot) == []

      restored_sequence = Enum.find(restored.nodes, &(&1.type == "sequence"))
      restored_child = Enum.find(restored.nodes, &(&1.type == "hub"))

      assert restored_child.parent_id == restored_sequence.id
      assert restored_child.parent_id == sequence.id
      assert restored_sequence.id == sequence.id

      assert %SequenceConfig{name: "Original sequence", width: 500.0, height: 280.0} =
               restored_sequence.sequence_config

      assert [%SequenceTrack{kind: "ambience", asset_id: restored_audio_id, volume: volume}] =
               restored_sequence.sequence_tracks

      assert hd(restored_sequence.sequence_tracks).id == track.id
      refute Repo.get(SequenceTrack, replacement_track.id)
      assert restored_audio_id == audio.id
      assert Decimal.equal?(volume, Decimal.new("0.4"))

      assert [%SequenceVisualLayer{kind: "overlay", asset_id: restored_image_id, label: "Mist"}] =
               restored_sequence.sequence_visual_layers

      assert hd(restored_sequence.sequence_visual_layers).id == layer.id
      refute Repo.get(SequenceVisualLayer, replacement_layer.id)
      assert restored_image_id == image.id
    end

    test "rejects invalid sequence config, track, and layer payloads before any write", %{
      user: user,
      project: project,
      flow: flow
    } do
      image = uploaded_asset(project, user, "strict-sequence.png", "image", "image/png")

      {:ok, sequence} =
        Flows.create_sequence(flow.id, %{
          "name" => "Strict sequence",
          "width" => 400.0,
          "height" => 240.0
        })

      {:ok, _track} =
        Flows.upsert_sequence_track(sequence.id, "music", %{
          "volume" => Decimal.new("0.5")
        })

      {:ok, _layer} =
        Flows.create_sequence_visual_layer(sequence.id, %{
          "asset_id" => image.id,
          "kind" => "overlay",
          "label" => "Valid"
        })

      snapshot = FlowSnapshot.build_snapshot(flow)

      invalid_snapshots = [
        {:invalid_sequence_config_snapshot,
         update_snapshot_node(snapshot, sequence.id, &Map.put(&1, "sequence_config", nil))},
        {:invalid_sequence_config_snapshot,
         update_snapshot_node(snapshot, sequence.id, fn node ->
           put_in(node, ["sequence_config", "name"], "")
         end)},
        {:invalid_sequence_track_snapshot,
         update_snapshot_node(snapshot, sequence.id, fn node ->
           update_in(node["sequence_tracks"], fn [track] ->
             [Map.put(track, "volume", "1.1")]
           end)
         end)},
        {:invalid_sequence_visual_layer_snapshot,
         update_snapshot_node(snapshot, sequence.id, fn node ->
           update_in(node["sequence_visual_layers"], fn [layer] ->
             [Map.put(layer, "label", String.duplicate("x", 121))]
           end)
         end)},
        {:invalid_sequence_visual_layer_snapshot,
         update_snapshot_node(snapshot, sequence.id, fn node ->
           update_in(node["sequence_visual_layers"], fn [layer] ->
             [Map.put(layer, "x", -0.1)]
           end)
         end)},
        {:invalid_sequence_visual_layer_snapshot,
         update_snapshot_node(snapshot, sequence.id, fn node ->
           update_in(node["sequence_visual_layers"], fn [layer] ->
             [Map.put(layer, "width", 0.0)]
           end)
         end)},
        {:invalid_sequence_visual_layer_snapshot,
         update_snapshot_node(snapshot, sequence.id, fn node ->
           update_in(node["sequence_visual_layers"], fn [layer] ->
             [Map.put(layer, "opacity", 1.1)]
           end)
         end)}
      ]

      {:ok, current_flow} = Flows.update_flow(flow, %{name: "Current sequence state"})

      for {expected_tag, invalid_snapshot} <- invalid_snapshots do
        assert {:error, restore_reason} =
                 FlowSnapshot.restore_snapshot(current_flow, invalid_snapshot,
                   restore_action: {:entity_version_restore, "flow"}
                 )

        assert elem(restore_reason, 0) == expected_tag
        assert Repo.get!(Flow, flow.id).name == "Current sequence state"
        assert Repo.get!(SequenceConfig, sequence.id).name == "Strict sequence"
      end
    end

    test "round-trips false and zero values without replacing them with defaults", %{
      user: user,
      project: project,
      flow: flow
    } do
      image = uploaded_asset(project, user, "zero.png", "zero image", "image/png")

      {:ok, flow} =
        Flows.update_flow(flow, %{
          is_main: false,
          settings: %{"enabled" => false, "count" => 0}
        })

      annotation =
        node_fixture(flow, %{
          type: "annotation",
          position_x: 0.0,
          position_y: 0.0,
          data: %{"enabled" => false, "count" => 0}
        })

      {:ok, sequence} =
        Flows.create_sequence(flow.id, %{
          "name" => "Zero fidelity",
          "width" => 400.0,
          "height" => 240.0
        })

      {:ok, track} =
        Flows.upsert_sequence_track(sequence.id, "music", %{
          "position" => 0,
          "volume" => Decimal.new("0")
        })

      {:ok, layer} =
        Flows.create_sequence_visual_layer(sequence.id, %{
          "asset_id" => image.id,
          "kind" => "overlay",
          "x" => 0.0,
          "y" => 0.0,
          "anchor_x" => 0.0,
          "anchor_y" => 0.0,
          "opacity" => 0.0,
          "visible" => false
        })

      snapshot = FlowSnapshot.build_snapshot(flow)

      assert {:ok, modified_flow} =
               Flows.update_flow(flow, %{
                 is_main: true,
                 settings: %{"enabled" => true, "count" => 7}
               })

      assert {:ok, _annotation, _meta} =
               Flows.update_node_data(annotation, %{"enabled" => true, "count" => 7})

      assert {:ok, _track} =
               Flows.upsert_sequence_track(sequence.id, "music", %{
                 "position" => 9,
                 "volume" => Decimal.new("1")
               })

      assert {:ok, _layer} =
               Flows.update_sequence_visual_layer(layer, %{
                 "x" => 1.0,
                 "y" => 1.0,
                 "opacity" => 1.0,
                 "visible" => true
               })

      assert {:ok, restored} =
               FlowSnapshot.restore_snapshot(modified_flow, snapshot, restore_action: {:entity_version_restore, "flow"})

      assert restored.is_main == false
      assert restored.settings == %{"enabled" => false, "count" => 0}

      restored_annotation = Enum.find(restored.nodes, &(&1.id == annotation.id))
      assert restored_annotation.position_x == 0.0
      assert restored_annotation.position_y == 0.0
      assert restored_annotation.data == %{"enabled" => false, "count" => 0}

      restored_sequence = Enum.find(restored.nodes, &(&1.id == sequence.id))

      assert [%SequenceTrack{id: restored_track_id, position: 0, volume: volume}] =
               restored_sequence.sequence_tracks

      assert restored_track_id == track.id
      assert Decimal.equal?(volume, Decimal.new("0"))

      assert [%SequenceVisualLayer{id: restored_layer_id, visible: false} = restored_layer] =
               restored_sequence.sequence_visual_layers

      assert restored_layer_id == layer.id
      assert restored_layer.x == 0.0
      assert restored_layer.y == 0.0
      assert restored_layer.opacity == 0.0
    end

    test "restores main when the only other main flow is in recoverable trash", %{
      project: project,
      flow: flow
    } do
      assert {:ok, main_flow} = Flows.set_main_flow(flow)
      main_snapshot = FlowSnapshot.build_snapshot(main_flow)

      assert {:ok, demoted_flow} = Flows.update_flow(main_flow, %{is_main: false})

      assert {:ok, restored_main} =
               FlowSnapshot.restore_snapshot(demoted_flow, main_snapshot,
                 restore_action: {:entity_version_restore, "flow"}
               )

      assert restored_main.is_main

      other_flow = flow_fixture(project)
      assert {:ok, other_main} = Flows.set_main_flow(other_flow)
      assert {:ok, trashed_main} = Flows.delete_flow(other_main)
      assert trashed_main.is_main
      assert trashed_main.deleted_at

      assert {:ok, restored_main_again} =
               FlowSnapshot.restore_snapshot(restored_main, main_snapshot,
                 restore_action: {:entity_version_restore, "flow"}
               )

      assert restored_main_again.is_main

      persisted_other = Repo.get!(Flow, other_flow.id)
      assert persisted_other.is_main
      assert persisted_other.deleted_at == trashed_main.deleted_at
    end

    test "retries a main conflict before materializing restore assets", %{
      user: user,
      project: project,
      flow: flow
    } do
      audio =
        uploaded_asset(
          project,
          user,
          "restore-main-retry.mp3",
          "restore retry audio",
          "audio/mpeg"
        )

      dialogue =
        node_fixture(flow, %{
          type: "dialogue",
          data: %{
            "text" => "Retry restore",
            "responses" => [],
            "audio_asset_id" => audio.id
          }
        })

      assert {:ok, main_flow} = Flows.set_main_flow(flow)
      snapshot = FlowSnapshot.build_snapshot(main_flow)
      assert {:ok, demoted_flow} = Flows.update_flow(main_flow, %{is_main: false})
      competing_flow = flow_fixture(project)
      attempt_key = {__MODULE__, make_ref()}

      hook = fn ->
        attempt = Process.get(attempt_key, 0) + 1
        Process.put(attempt_key, attempt)

        if attempt == 1 do
          assert {1, nil} =
                   Repo.update_all(
                     from(candidate in Flow, where: candidate.id == ^competing_flow.id),
                     set: [is_main: true]
                   )
        end
      end

      matching_assets_before =
        Repo.aggregate(
          from(asset in Asset,
            where:
              asset.project_id == ^project.id and
                asset.blob_hash == ^audio.blob_hash
          ),
          :count
        )

      assert {:ok, restored} =
               FlowSnapshot.restore_snapshot(demoted_flow, snapshot,
                 asset_mode: :copy,
                 restore_action: {:entity_version_restore, "flow"},
                 __before_main_write_hook: hook
               )

      assert Process.get(attempt_key) == 2
      refute restored.is_main
      refute Repo.get!(Flow, competing_flow.id).is_main

      restored_audio_id = Repo.get!(FlowNode, dialogue.id).data["audio_asset_id"]
      refute restored_audio_id == audio.id

      restored_audio = Repo.get!(Asset, restored_audio_id)
      assert restored_audio.project_id == project.id
      assert {:ok, "restore retry audio"} = Assets.storage_download(restored_audio.key)

      assert Repo.aggregate(
               from(asset in Asset,
                 where:
                   asset.project_id == ^project.id and
                     asset.blob_hash == ^audio.blob_hash
               ),
               :count
             ) == matching_assets_before + 1

      on_exit(fn -> Assets.storage_delete(restored_audio.key) end)
    end

    test "recreates hard-deleted rows with their historical IDs", %{flow: flow} do
      source =
        node_fixture(flow, %{
          type: "dialogue",
          position_x: 100.0,
          data: %{"text" => "Historical", "responses" => []}
        })

      target = node_fixture(flow, %{type: "hub", position_x: 200.0})
      connection = connection_fixture(flow, source, target)
      snapshot = FlowSnapshot.build_snapshot(flow)

      Repo.delete!(source)
      refute Repo.get(FlowNode, source.id)
      refute Repo.get(FlowConnection, connection.id)

      assert {:ok, restored} =
               FlowSnapshot.restore_snapshot(flow, snapshot, restore_action: {:entity_version_restore, "flow"})

      assert Repo.get!(FlowNode, source.id).deleted_at == nil

      assert %FlowConnection{
               id: connection_id,
               source_node_id: source_id,
               target_node_id: target_id
             } = Repo.get!(FlowConnection, connection.id)

      assert connection_id == connection.id
      assert source_id == source.id
      assert target_id == target.id
      assert Enum.any?(restored.nodes, &(&1.id == source.id))
    end

    test "restores dialogue runtime IDs when current unique values are swapped", %{flow: flow} do
      first =
        node_fixture(flow, %{
          type: "dialogue",
          data: %{
            "localization_id" => "dialogue_first",
            "text" => "First",
            "responses" => []
          }
        })

      second =
        node_fixture(flow, %{
          type: "dialogue",
          data: %{
            "localization_id" => "dialogue_second",
            "text" => "Second",
            "responses" => []
          }
        })

      snapshot = FlowSnapshot.build_snapshot(flow)

      first =
        first
        |> Ecto.Changeset.change(data: Map.put(first.data, "localization_id", "dialogue_temporary"))
        |> Repo.update!()

      _second =
        second
        |> Ecto.Changeset.change(data: Map.put(second.data, "localization_id", "dialogue_first"))
        |> Repo.update!()

      _first =
        first
        |> Ecto.Changeset.change(data: Map.put(first.data, "localization_id", "dialogue_second"))
        |> Repo.update!()

      assert {:ok, restored} =
               FlowSnapshot.restore_snapshot(flow, snapshot, restore_action: {:entity_version_restore, "flow"})

      restored_by_id = Map.new(restored.nodes, &{&1.id, &1})
      assert restored_by_id[first.id].data["localization_id"] == "dialogue_first"
      assert restored_by_id[second.id].data["localization_id"] == "dialogue_second"
    end

    test "rolls back every mutation when reconciliation fails after it starts", %{
      user: user,
      project: project,
      flow: flow
    } do
      image = uploaded_asset(project, user, "rollback.png", "rollback image", "image/png")

      {:ok, sequence} =
        Flows.create_sequence(flow.id, %{
          "name" => "Rollback sequence",
          "width" => 400.0,
          "height" => 240.0
        })

      {:ok, layer} =
        Flows.create_sequence_visual_layer(sequence.id, %{
          "asset_id" => image.id,
          "kind" => "overlay",
          "label" => "Must survive"
        })

      snapshot = FlowSnapshot.build_snapshot(flow)
      {:ok, modified_flow} = Flows.update_flow(flow, %{name: "Must survive rollback"})
      post_snapshot = node_fixture(flow, %{type: "hub", position_x: 300.0})
      missing_asset_id = image.id + 10_000_000

      invalid_snapshot =
        Map.update!(snapshot, "nodes", fn nodes ->
          Enum.map(nodes, fn
            %{"original_id" => node_id, "sequence_visual_layers" => [layer_data]} = node
            when node_id == sequence.id ->
              Map.put(node, "sequence_visual_layers", [
                Map.put(layer_data, "asset_id", missing_asset_id)
              ])

            node ->
              node
          end)
        end)

      assert {:error, :missing_snapshot_asset_catalog_entry} =
               FlowSnapshot.restore_snapshot(modified_flow, invalid_snapshot,
                 restore_action: {:entity_version_restore, "flow"}
               )

      assert Repo.get!(Flow, flow.id).name == "Must survive rollback"
      assert Repo.get!(FlowNode, post_snapshot.id).deleted_at == nil
      assert Repo.get!(SequenceVisualLayer, layer.id).asset_id == image.id
    end

    test "does not compensate committed asset copies when post-commit finalization fails", %{
      user: user,
      project: project,
      flow: flow
    } do
      audio =
        uploaded_asset(
          project,
          user,
          "post-commit-copy.mp3",
          "committed asset copy",
          "audio/mpeg"
        )

      dialogue =
        node_fixture(flow, %{
          type: "dialogue",
          data: %{
            "text" => "The transaction must stay durable",
            "responses" => [],
            "audio_asset_id" => audio.id
          }
        })

      snapshot = FlowSnapshot.build_snapshot(flow)

      assert_raise RuntimeError, "post-commit finalization failed", fn ->
        FlowSnapshot.restore_snapshot(flow, snapshot,
          asset_mode: :copy,
          restore_action: {:entity_version_restore, "flow"},
          __post_commit_restore_hook: fn ->
            raise "post-commit finalization failed"
          end
        )
      end

      restored_audio_id = Repo.get!(FlowNode, dialogue.id).data["audio_asset_id"]
      refute restored_audio_id == audio.id

      restored_audio = Repo.get!(Asset, restored_audio_id)
      assert restored_audio.project_id == project.id
      assert {:ok, "committed asset copy"} = Assets.storage_download(restored_audio.key)
      on_exit(fn -> Assets.storage_delete(restored_audio.key) end)
    end

    test "drops every asset-bearing surface only with explicit asset_mode drop", %{
      user: user,
      project: project,
      flow: flow
    } do
      _source_en = source_language_fixture(project, %{locale_code: "en", name: "English"})
      _source_es = language_fixture(project, %{locale_code: "es", name: "Spanish"})
      audio = uploaded_asset(project, user, "drop-all.mp3", "drop all audio", "audio/mpeg")
      image = uploaded_asset(project, user, "drop-all.png", "drop all image", "image/png")

      dialogue =
        node_fixture(flow, %{
          type: "dialogue",
          data: %{
            "text" => "Drop all",
            "responses" => [],
            "audio_asset_id" => audio.id
          }
        })

      [localized_text] = Localization.get_texts_for_source("flow_node", dialogue.id)

      assert {:ok, _localized_text} =
               Localization.update_text(localized_text, %{
                 translated_text: "Eliminar todo",
                 status: "final",
                 vo_asset_id: audio.id,
                 vo_status: "recorded"
               })

      {:ok, sequence} =
        Flows.create_sequence(flow.id, %{
          "name" => "Drop assets",
          "width" => 640.0,
          "height" => 360.0
        })

      assert {:ok, _track} =
               Flows.upsert_sequence_track(sequence.id, "music", %{
                 "asset_id" => audio.id
               })

      assert {:ok, _visual_layer} =
               Flows.create_sequence_visual_layer(sequence.id, %{
                 "asset_id" => image.id,
                 "kind" => "backdrop",
                 "label" => "Drop me"
               })

      snapshot = FlowSnapshot.build_snapshot(flow)

      assert {:ok, _restored_flow} =
               FlowSnapshot.restore_snapshot(flow, snapshot,
                 asset_mode: :drop,
                 restore_action: {:entity_version_restore, "flow"}
               )

      restored_dialogue = Repo.get!(FlowNode, dialogue.id)

      restored_sequence =
        sequence.id
        |> then(&Repo.get!(FlowNode, &1))
        |> Repo.preload([:sequence_tracks, :sequence_visual_layers])

      assert is_nil(restored_dialogue.data["audio_asset_id"])
      assert [%SequenceTrack{asset_id: nil}] = restored_sequence.sequence_tracks
      assert restored_sequence.sequence_visual_layers == []

      assert [%LocalizedText{vo_asset_id: nil, vo_status: "needed"}] =
               Localization.get_texts_for_source("flow_node", dialogue.id)
    end

    test "preserves existing trash and soft-deletes post-snapshot nodes without deleting connections", %{
      flow: flow
    } do
      active_target = node_fixture(flow, %{type: "hub", position_x: 100.0})
      existing_trash = node_fixture(flow, %{type: "dialogue", position_x: 200.0})
      trash_connection = connection_fixture(flow, existing_trash, active_target)

      {:ok, trashed_node, _meta} = Flows.delete_node(existing_trash)
      existing_deleted_at = trashed_node.deleted_at

      {:ok, trashed_sequence} =
        Flows.create_sequence(flow.id, %{
          "name" => "Keep trash resources",
          "width" => 400.0,
          "height" => 240.0
        })

      {:ok, trash_track} =
        Flows.upsert_sequence_track(trashed_sequence.id, "music", %{
          "position" => 4,
          "volume" => Decimal.new("0.5")
        })

      {:ok, trashed_sequence, _meta} = Flows.delete_node(trashed_sequence)
      sequence_deleted_at = trashed_sequence.deleted_at

      snapshot = FlowSnapshot.build_snapshot(flow)

      post_snapshot = node_fixture(flow, %{type: "hub", position_x: 300.0})
      post_snapshot_connection = connection_fixture(flow, active_target, post_snapshot)

      {:ok, post_snapshot_parent} =
        Flows.create_sequence(flow.id, %{
          "name" => "Post-snapshot parent",
          "width" => 400.0,
          "height" => 240.0
        })

      protected_child =
        node_fixture(flow, %{
          type: "hub",
          parent_id: post_snapshot_parent.id,
          position_x: 350.0
        })

      {:ok, protected_child, _meta} = Flows.delete_node(protected_child)
      protected_child_deleted_at = protected_child.deleted_at

      assert {:ok, restored} =
               FlowSnapshot.restore_snapshot(flow, snapshot, restore_action: {:entity_version_restore, "flow"})

      persisted_trash = Repo.get!(FlowNode, existing_trash.id)
      persisted_sequence = Repo.get!(FlowNode, trashed_sequence.id)
      persisted_post_snapshot = Repo.get!(FlowNode, post_snapshot.id)
      persisted_post_snapshot_parent = Repo.get!(FlowNode, post_snapshot_parent.id)
      persisted_protected_child = Repo.get!(FlowNode, protected_child.id)

      assert persisted_trash.deleted_at == existing_deleted_at
      assert persisted_sequence.deleted_at == sequence_deleted_at
      assert persisted_post_snapshot.deleted_at
      assert persisted_post_snapshot_parent.deleted_at
      assert persisted_protected_child.deleted_at == protected_child_deleted_at
      assert persisted_protected_child.parent_id == post_snapshot_parent.id
      assert Repo.get!(SequenceTrack, trash_track.id).flow_node_id == trashed_sequence.id
      assert Repo.get!(FlowConnection, trash_connection.id)
      assert Repo.get!(FlowConnection, post_snapshot_connection.id)

      refute Enum.any?(
               restored.nodes,
               &(&1.id in [
                   existing_trash.id,
                   trashed_sequence.id,
                   post_snapshot.id,
                   post_snapshot_parent.id,
                   protected_child.id
                 ])
             )
    end

    test "keeps dynamic exit pins in other flows stable", %{project: project, flow: referenced_flow} do
      referenced_exit = node_fixture(referenced_flow, %{type: "exit", position_x: 300.0})
      snapshot = FlowSnapshot.build_snapshot(referenced_flow)

      caller = flow_fixture(project)

      subflow =
        node_fixture(caller, %{
          type: "subflow",
          data: %{"referenced_flow_id" => referenced_flow.id}
        })

      next_node = node_fixture(caller, %{type: "hub"})

      caller_connection =
        connection_fixture(caller, subflow, next_node, %{
          source_pin: "exit_#{referenced_exit.id}"
        })

      assert {:ok, _restored} =
               FlowSnapshot.restore_snapshot(referenced_flow, snapshot, restore_action: {:entity_version_restore, "flow"})

      assert Repo.get!(FlowNode, referenced_exit.id).deleted_at == nil

      assert Repo.get!(FlowConnection, caller_connection.id).source_pin ==
               "exit_#{referenced_exit.id}"
    end

    test "fails atomically before removing an exit used by a caller, including trash", %{
      project: project,
      flow: referenced_flow
    } do
      snapshot_without_new_exit = FlowSnapshot.build_snapshot(referenced_flow)
      referenced_exit = node_fixture(referenced_flow, %{type: "exit", position_x: 300.0})
      {:ok, current_flow} = Flows.update_flow(referenced_flow, %{name: "Current referenced flow"})

      caller = flow_fixture(project)

      subflow =
        node_fixture(caller, %{
          type: "subflow",
          data: %{"referenced_flow_id" => referenced_flow.id}
        })

      next_node = node_fixture(caller, %{type: "hub"})

      caller_connection =
        connection_fixture(caller, subflow, next_node, %{
          source_pin: "exit_#{referenced_exit.id}"
        })

      assert {:error,
              {:incoming_dynamic_exit_pin_would_break, connection_id, source_pin, restored_flow_id,
               :exit_missing_from_snapshot}} =
               FlowSnapshot.restore_snapshot(current_flow, snapshot_without_new_exit,
                 restore_action: {:entity_version_restore, "flow"}
               )

      assert connection_id == caller_connection.id
      assert source_pin == "exit_#{referenced_exit.id}"
      assert restored_flow_id == referenced_flow.id
      assert Repo.get!(Flow, referenced_flow.id).name == "Current referenced flow"
      assert Repo.get!(FlowNode, referenced_exit.id).deleted_at == nil
      assert Repo.get!(FlowConnection, caller_connection.id).source_pin == source_pin

      assert {:ok, _trashed_subflow, _meta} = Flows.delete_node(subflow)

      assert {:error,
              {:incoming_dynamic_exit_pin_would_break, ^connection_id, ^source_pin, ^restored_flow_id,
               :exit_missing_from_snapshot}} =
               FlowSnapshot.restore_snapshot(current_flow, snapshot_without_new_exit,
                 restore_action: {:entity_version_restore, "flow"}
               )
    end

    test "rejects a historical caller snapshot after its referenced exit is deleted", %{
      project: project,
      flow: flow
    } do
      referenced_flow = flow_fixture(project)
      referenced_exit = node_fixture(referenced_flow, %{type: "exit"})

      subflow =
        node_fixture(flow, %{
          type: "subflow",
          data: %{"referenced_flow_id" => referenced_flow.id}
        })

      next_node = node_fixture(flow, %{type: "hub"})

      connection =
        connection_fixture(flow, subflow, next_node, %{
          source_pin: "exit_#{referenced_exit.id}"
        })

      snapshot = FlowSnapshot.build_snapshot(flow)
      assert {:ok, _deleted_exit, _meta} = Flows.delete_node(referenced_exit)
      {:ok, current_flow} = Flows.update_flow(flow, %{name: "Current caller"})

      assert {:error, {:dynamic_exit_pin_not_materializable, connection_id, source_pin, :exit_in_trash}} =
               FlowSnapshot.restore_snapshot(current_flow, snapshot, restore_action: {:entity_version_restore, "flow"})

      assert connection_id == connection.id
      assert source_pin == "exit_#{referenced_exit.id}"
      assert Repo.get!(Flow, flow.id).name == "Current caller"
      assert Repo.get!(FlowConnection, connection.id)
    end

    test "rejects a cross-project terminal exit target before an in-place write", %{
      user: user,
      project: project,
      flow: flow
    } do
      exit_node = active_exit_node(flow.id)
      local_scene = scene_fixture(project)

      set_node_data(exit_node, %{
        "exit_mode" => "terminal",
        "target_type" => "scene",
        "target_id" => local_scene.id
      })

      snapshot = FlowSnapshot.build_snapshot(flow)
      {:ok, current_flow} = Flows.update_flow(flow, %{name: "Current flow"})
      foreign_scene = user |> project_fixture() |> scene_fixture()

      cross_project_snapshot =
        update_snapshot_node(snapshot, exit_node.id, fn node ->
          node
          |> put_in(["data", "target_type"], "scene")
          |> put_in(["data", "target_id"], foreign_scene.id)
        end)

      assert {:error, {:invalid_project_reference, {:flow_node, node_id, "target_id"}, target_id}} =
               FlowSnapshot.restore_snapshot(current_flow, cross_project_snapshot,
                 restore_action: {:entity_version_restore, "flow"}
               )

      assert node_id == exit_node.id
      assert target_id == foreign_scene.id
      assert Repo.get!(Flow, flow.id).name == "Current flow"
      assert Repo.get!(FlowNode, exit_node.id).data["target_id"] == local_scene.id
    end

    test "rejects cross-project and trashed external refs before an in-place write", %{
      user: user,
      project: project,
      flow: flow
    } do
      referenced_flow = flow_fixture(project)

      subflow =
        node_fixture(flow, %{
          type: "subflow",
          data: %{"referenced_flow_id" => referenced_flow.id}
        })

      snapshot = FlowSnapshot.build_snapshot(flow)
      {:ok, current_flow} = Flows.update_flow(flow, %{name: "Must remain current"})
      other_project = project_fixture(user)
      foreign_scene = scene_fixture(other_project)
      foreign_flow = flow_fixture(other_project)

      cross_project_flow_snapshot =
        update_snapshot_node(snapshot, subflow.id, fn node ->
          put_in(node, ["data", "referenced_flow_id"], foreign_flow.id)
        end)

      assert {:error, {:invalid_project_reference, {:flow_node, subflow_id, "referenced_flow_id"}, foreign_flow_id}} =
               FlowSnapshot.restore_snapshot(current_flow, cross_project_flow_snapshot,
                 restore_action: {:entity_version_restore, "flow"}
               )

      assert subflow_id == subflow.id
      assert foreign_flow_id == foreign_flow.id

      cross_project_scene_snapshot =
        Map.put(snapshot, "scene_id", foreign_scene.id)

      assert {:error, {:invalid_project_reference, {:flow, "scene_id"}, foreign_scene_id}} =
               FlowSnapshot.restore_snapshot(current_flow, cross_project_scene_snapshot,
                 restore_action: {:entity_version_restore, "flow"}
               )

      assert foreign_scene_id == foreign_scene.id

      deleted_at = DateTime.truncate(DateTime.utc_now(), :second)

      Repo.update_all(
        from(target in Flow, where: target.id == ^referenced_flow.id),
        set: [deleted_at: deleted_at]
      )

      assert {:error, {:invalid_project_reference, {:flow_node, ^subflow_id, "referenced_flow_id"}, deleted_flow_id}} =
               FlowSnapshot.restore_snapshot(current_flow, snapshot, restore_action: {:entity_version_restore, "flow"})

      assert deleted_flow_id == referenced_flow.id
      assert Repo.get!(Flow, flow.id).name == "Must remain current"
      assert Repo.get!(FlowNode, subflow.id).data["referenced_flow_id"] == referenced_flow.id
    end

    test "rejects a circular materialized flow reference atomically", %{
      project: project,
      flow: flow
    } do
      referenced_flow = flow_fixture(project)

      subflow =
        node_fixture(flow, %{
          type: "subflow",
          data: %{"referenced_flow_id" => referenced_flow.id}
        })

      snapshot = FlowSnapshot.build_snapshot(flow)
      {:ok, current_flow} = Flows.update_flow(flow, %{name: "Current name"})

      referenced_exit =
        Repo.one!(
          from(node in FlowNode,
            where:
              node.flow_id == ^referenced_flow.id and node.type == "exit" and
                is_nil(node.deleted_at),
            limit: 1
          )
        )

      Repo.update_all(
        from(node in FlowNode, where: node.id == ^referenced_exit.id),
        set: [
          data:
            referenced_exit.data
            |> Map.put("exit_mode", "flow_reference")
            |> Map.put("referenced_flow_id", flow.id)
        ]
      )

      assert {:error, {:circular_flow_reference, flow_id, node_id, target_flow_id}} =
               FlowSnapshot.restore_snapshot(current_flow, snapshot, restore_action: {:entity_version_restore, "flow"})

      assert {flow_id, node_id, target_flow_id} ==
               {flow.id, subflow.id, referenced_flow.id}

      assert Repo.get!(Flow, flow.id).name == "Current name"
      assert Repo.get!(FlowNode, subflow.id).data["referenced_flow_id"] == referenced_flow.id
    end

    test "rejects restore when the owning project is in trash", %{
      project: project,
      flow: flow
    } do
      snapshot = FlowSnapshot.build_snapshot(flow)
      {:ok, current_flow} = Flows.update_flow(flow, %{name: "Current name"})
      deleted_at = DateTime.truncate(DateTime.utc_now(), :second)

      Repo.update_all(
        from(owner_project in Project,
          where: owner_project.id == ^project.id
        ),
        set: [deleted_at: deleted_at]
      )

      assert {:error, :project_not_active} =
               FlowSnapshot.restore_snapshot(current_flow, snapshot, restore_action: {:entity_version_restore, "flow"})

      assert Repo.get!(Flow, flow.id).name == "Current name"
    end

    test "rejects restore while the flow root is in trash", %{
      flow: flow
    } do
      node = node_fixture(flow, %{type: "hub", position_x: 120.0})
      snapshot = FlowSnapshot.build_snapshot(flow)
      {:ok, current_flow} = Flows.update_flow(flow, %{name: "Current name"})
      deleted_at = DateTime.truncate(DateTime.utc_now(), :second)

      Repo.update_all(
        from(root in Flow, where: root.id == ^flow.id),
        set: [deleted_at: deleted_at]
      )

      assert {:error, :flow_not_active} =
               FlowSnapshot.restore_snapshot(current_flow, snapshot, restore_action: {:entity_version_restore, "flow"})

      assert Repo.get!(Flow, flow.id).name == "Current name"
      assert Repo.get!(FlowNode, node.id).deleted_at == nil
    end

    test "rejects truncated and malformed payloads before changing persisted state", %{
      project: project,
      flow: flow
    } do
      _en = source_language_fixture(project, %{locale_code: "en", name: "English"})
      _es = language_fixture(project, %{locale_code: "es", name: "Spanish"})
      node = node_fixture(flow, %{type: "hub", position_x: 100.0})

      dialogue =
        node_fixture(flow, %{
          type: "dialogue",
          data: %{"text" => "Hello", "responses" => []}
        })

      [localized_text] = Localization.get_texts_for_source("flow_node", dialogue.id)

      assert {:ok, _translated} =
               Localization.update_text(localized_text, %{
                 translated_text: "Hola",
                 status: "final"
               })

      snapshot = FlowSnapshot.build_snapshot(flow)
      {:ok, modified_flow} = Flows.update_flow(flow, %{name: "Must remain intact"})
      post_snapshot = node_fixture(flow, %{type: "hub", position_x: 200.0})

      for missing_field <- ["name", "nodes", "connections", "localization"] do
        assert {:error, {:missing_snapshot_fields, :flow, [^missing_field]}} =
                 FlowSnapshot.restore_snapshot(modified_flow, Map.delete(snapshot, missing_field),
                   restore_action: {:entity_version_restore, "flow"}
                 )
      end

      malformed_snapshot =
        Map.update!(snapshot, "nodes", fn nodes ->
          Enum.map(nodes, fn
            %{"original_id" => node_id} = node_data when node_id == node.id ->
              Map.put(node_data, "position_x", "not-a-number")

            node_data ->
              node_data
          end)
        end)

      assert {:error, {:invalid_snapshot_field, :node, "position_x", "not-a-number"}} =
               FlowSnapshot.restore_snapshot(modified_flow, malformed_snapshot,
                 restore_action: {:entity_version_restore, "flow"}
               )

      malformed_asset_snapshot =
        Map.update!(snapshot, "nodes", fn nodes ->
          Enum.map(nodes, fn
            %{"original_id" => node_id, "data" => data} = node_data
            when node_id == dialogue.id ->
              Map.put(node_data, "data", Map.put(data, "audio_asset_id", "not-an-id"))

            node_data ->
              node_data
          end)
        end)

      assert {:error, {:invalid_snapshot_field, :node, "audio_asset_id", "not-an-id"}} =
               FlowSnapshot.restore_snapshot(modified_flow, malformed_asset_snapshot,
                 restore_action: {:entity_version_restore, "flow"}
               )

      assert Repo.get!(Flow, flow.id).name == "Must remain intact"
      assert Repo.get!(FlowNode, post_snapshot.id).deleted_at == nil

      assert [%{translated_text: "Hola", archived_at: nil}] =
               Localization.get_texts_for_source("flow_node", dialogue.id)
    end

    test "rejects localization rows removed or changed without updating the manifest", %{
      project: project,
      flow: flow
    } do
      _en = source_language_fixture(project, %{locale_code: "en", name: "English"})
      _es = language_fixture(project, %{locale_code: "es", name: "Spanish"})

      dialogue =
        node_fixture(flow, %{
          type: "dialogue",
          data: %{"text" => "Hello", "responses" => []}
        })

      [text] = Localization.get_texts_for_source("flow_node", dialogue.id)

      assert {:ok, _translated} =
               Localization.update_text(text, %{
                 translated_text: "Hola",
                 status: "final"
               })

      snapshot = FlowSnapshot.build_snapshot(flow)
      {:ok, modified_flow} = Flows.update_flow(flow, %{name: "Must remain"})
      post_snapshot = node_fixture(flow, %{type: "hub", position_x: 400.0})
      [row] = snapshot["localization"]

      corrupted_snapshots = [
        Map.put(snapshot, "localization", []),
        Map.put(snapshot, "localization", [
          Map.put(row, "translated_text", "Corrupted")
        ])
      ]

      for corrupted_snapshot <- corrupted_snapshots do
        assert {:error, {:localization_manifest_mismatch, _provided, _expected}} =
                 FlowSnapshot.restore_snapshot(modified_flow, corrupted_snapshot,
                   restore_action: {:entity_version_restore, "flow"}
                 )

        assert Repo.get!(Flow, flow.id).name == "Must remain"
        assert Repo.get!(FlowNode, post_snapshot.id).deleted_at == nil

        assert [%{translated_text: "Hola", status: "final", archived_at: nil}] =
                 Localization.get_texts_for_source("flow_node", dialogue.id)
      end
    end

    test "rejects semantically inconsistent localization even with a recomputed manifest", %{
      project: project,
      flow: flow
    } do
      _en = source_language_fixture(project, %{locale_code: "en", name: "English"})
      _es = language_fixture(project, %{locale_code: "es", name: "Spanish"})
      _fr = language_fixture(project, %{locale_code: "fr", name: "French"})

      dialogue =
        node_fixture(flow, %{
          type: "dialogue",
          data: %{
            "text" => "Hello {name}",
            "stage_directions" => "Quietly",
            "responses" => [
              %{"id" => "response_one", "text" => "Continue"}
            ]
          }
        })

      snapshot = FlowSnapshot.build_snapshot(flow)
      assert length(snapshot["localization"]) == 6

      {:ok, modified_flow} = Flows.update_flow(flow, %{name: "Must remain"})
      post_snapshot = node_fixture(flow, %{type: "hub", position_x: 500.0})

      text_row =
        Enum.find(
          snapshot["localization"],
          &(&1["source_field"] == "text" and &1["locale_code"] == "es")
        )

      tampered_text = "Different source"
      tampered_hash = source_text_hash(tampered_text)

      source_mismatch_rows =
        replace_localization_row(snapshot["localization"], text_row, fn row ->
          row
          |> Map.put("source_text", tampered_text)
          |> Map.put("source_text_hash", tampered_hash)
        end)

      hash_mismatch_rows =
        replace_localization_row(snapshot["localization"], text_row, fn row ->
          Map.put(row, "source_text_hash", String.duplicate("0", 64))
        end)

      final_without_translation_rows =
        replace_localization_row(snapshot["localization"], text_row, fn row ->
          row
          |> Map.put("status", "final")
          |> Map.put("translated_text", nil)
          |> Map.put("translated_source_hash", nil)
        end)

      invalid_placeholder_rows =
        replace_localization_row(snapshot["localization"], text_row, fn row ->
          row
          |> Map.put("translated_text", "Hola")
          |> Map.put("translated_source_hash", row["source_text_hash"])
          |> Map.put("status", "final")
        end)

      [removed_row | incomplete_rows] = snapshot["localization"]
      assert removed_row["locale_code"] in ~w(es fr)

      omitted_locale_rows =
        Enum.reject(snapshot["localization"], &(&1["locale_code"] == "fr"))

      semantic_cases = [
        {source_mismatch_rows, :localization_source_text_mismatch},
        {hash_mismatch_rows, :localization_source_text_hash_mismatch},
        {final_without_translation_rows, :invalid_localization_translation_state},
        {invalid_placeholder_rows, :invalid_localization_placeholders},
        {incomplete_rows, :incomplete_flow_localization_snapshot},
        {omitted_locale_rows, :incomplete_flow_localization_snapshot}
      ]

      for {rows, expected_error} <- semantic_cases do
        corrupted_snapshot =
          snapshot
          |> Map.put("localization", rows)
          |> Map.put(
            "localization_manifest",
            LocalizationCodec.manifest(
              rows,
              snapshot["localization_manifest"]["target_locales"]
            )
          )

        assert {:error, reason} =
                 FlowSnapshot.restore_snapshot(modified_flow, corrupted_snapshot,
                   restore_action: {:entity_version_restore, "flow"}
                 )

        assert elem(reason, 0) == expected_error
        assert Repo.get!(Flow, flow.id).name == "Must remain"
        assert Repo.get!(FlowNode, post_snapshot.id).deleted_at == nil
        assert length(Localization.get_texts_for_source("flow_node", dialogue.id)) == 6
      end
    end

    test "rejects duplicate, cross-flow, and invalid endpoint IDs without mutating the flow", %{
      project: project,
      flow: flow
    } do
      source = node_fixture(flow, %{type: "hub", position_x: 100.0})
      target = node_fixture(flow, %{type: "hub", position_x: 200.0})
      _connection = connection_fixture(flow, source, target)
      snapshot = FlowSnapshot.build_snapshot(flow)
      {:ok, modified_flow} = Flows.update_flow(flow, %{name: "Must remain"})
      initial_node_ids = flow_node_ids(flow.id)

      [first_node | _rest] = snapshot["nodes"]
      duplicate_snapshot = Map.update!(snapshot, "nodes", &[first_node | &1])

      assert {:error, {:duplicate_snapshot_original_id, :node}} =
               FlowSnapshot.restore_snapshot(modified_flow, duplicate_snapshot,
                 restore_action: {:entity_version_restore, "flow"}
               )

      other_flow = flow_fixture(project)
      other_node = node_fixture(other_flow, %{type: "hub"})

      cross_flow_snapshot =
        Map.update!(snapshot, "nodes", fn [first | rest] ->
          [Map.put(first, "original_id", other_node.id) | rest]
        end)

      assert {:error, {:snapshot_node_owned_by_other_flow, _conflict}} =
               FlowSnapshot.restore_snapshot(modified_flow, cross_flow_snapshot,
                 restore_action: {:entity_version_restore, "flow"}
               )

      invalid_endpoint_snapshot =
        Map.update!(snapshot, "connections", fn [first | rest] ->
          [Map.put(first, "source_node_index", -1) | rest]
        end)

      assert {:error, {:invalid_snapshot_connection_endpoint, _id, :source, -1}} =
               FlowSnapshot.restore_snapshot(modified_flow, invalid_endpoint_snapshot,
                 restore_action: {:entity_version_restore, "flow"}
               )

      assert Repo.get!(Flow, flow.id).name == "Must remain"
      assert flow_node_ids(flow.id) == initial_node_ids
    end

    test "is idempotent", %{flow: flow} do
      source = node_fixture(flow, %{type: "dialogue", position_x: 100.0})
      target = node_fixture(flow, %{type: "hub", position_x: 200.0})
      connection = connection_fixture(flow, source, target)
      snapshot = FlowSnapshot.build_snapshot(flow)

      assert {:ok, first_restore} =
               FlowSnapshot.restore_snapshot(flow, snapshot, restore_action: {:entity_version_restore, "flow"})

      assert {:ok, second_restore} =
               FlowSnapshot.restore_snapshot(first_restore, snapshot, restore_action: {:entity_version_restore, "flow"})

      assert Repo.get!(FlowNode, source.id).flow_id == flow.id
      assert Repo.get!(FlowConnection, connection.id).flow_id == flow.id
      assert FlowSnapshot.build_snapshot(second_restore) == snapshot
    end

    test "resolves jump targets from the snapshot graph and rejects missing or ambiguous targets", %{
      flow: flow
    } do
      hub =
        node_fixture(flow, %{
          type: "hub",
          data: %{"hub_id" => "restore_target"},
          position_x: 200.0
        })

      second_hub =
        node_fixture(flow, %{
          type: "hub",
          data: %{"hub_id" => "other_target"},
          position_x: 300.0
        })

      jump =
        node_fixture(flow, %{
          type: "jump",
          data: %{"target_hub_id" => "restore_target"},
          position_x: 400.0
        })

      snapshot = FlowSnapshot.build_snapshot(flow)

      assert {:ok, _deleted_hub, _meta} = Flows.delete_node(hub)
      assert Repo.get!(FlowNode, jump.id).data["target_hub_id"] == ""
      assert {:ok, current_flow} = Flows.update_flow(flow, %{name: "Current graph"})

      assert {:ok, restored_flow} =
               FlowSnapshot.restore_snapshot(current_flow, snapshot, restore_action: {:entity_version_restore, "flow"})

      assert Repo.get!(FlowNode, hub.id).deleted_at == nil
      assert Repo.get!(FlowNode, jump.id).data["target_hub_id"] == "restore_target"

      assert {:ok, current_jump, _meta} =
               Flows.update_node_data(Repo.get!(FlowNode, jump.id), %{"target_hub_id" => ""})

      current_flow_record = Repo.get!(Flow, restored_flow.id)
      assert {:ok, current_flow} = Flows.update_flow(current_flow_record, %{name: "Keep graph current"})

      invalid_snapshots = [
        {{:invalid_jump_target, "missing_target"},
         update_snapshot_node(snapshot, jump.id, fn node ->
           put_in(node, ["data", "target_hub_id"], "missing_target")
         end)},
        {{:duplicate_snapshot_hub_id, "restore_target"},
         update_snapshot_node(snapshot, second_hub.id, fn node ->
           put_in(node, ["data", "hub_id"], "restore_target")
         end)},
        {{:invalid_jump_target, 17},
         update_snapshot_node(snapshot, jump.id, fn node ->
           put_in(node, ["data", "target_hub_id"], 17)
         end)}
      ]

      for {expected_error, invalid_snapshot} <- invalid_snapshots do
        assert {:error, ^expected_error} =
                 FlowSnapshot.restore_snapshot(current_flow, invalid_snapshot,
                   restore_action: {:entity_version_restore, "flow"}
                 )

        assert Repo.get!(Flow, flow.id).name == "Keep graph current"
        assert Repo.get!(FlowNode, jump.id).data == current_jump.data
      end

      whitespace_snapshot =
        update_snapshot_node(snapshot, jump.id, fn node ->
          put_in(node, ["data", "target_hub_id"], "   ")
        end)

      assert {:ok, _restored} =
               FlowSnapshot.restore_snapshot(current_flow, whitespace_snapshot,
                 restore_action: {:entity_version_restore, "flow"}
               )

      assert Repo.get!(FlowNode, jump.id).data["target_hub_id"] == ""
    end

    test "rejects invalid or duplicate snapshot hub definitions without a referencing jump", %{
      flow: flow
    } do
      first_hub =
        node_fixture(flow, %{
          type: "hub",
          data: %{"hub_id" => "first_hub"},
          position_x: 200.0
        })

      second_hub =
        node_fixture(flow, %{
          type: "hub",
          data: %{"hub_id" => "second_hub"},
          position_x: 300.0
        })

      snapshot = FlowSnapshot.build_snapshot(flow)
      assert {:ok, current_flow} = Flows.update_flow(flow, %{name: "Keep valid hubs"})

      for invalid_hub_id <- [nil, "", "   ", 17] do
        invalid_snapshot =
          update_snapshot_node(snapshot, first_hub.id, fn node ->
            put_in(node, ["data", "hub_id"], invalid_hub_id)
          end)

        assert {:error, {:invalid_snapshot_hub_id, node_id, ^invalid_hub_id}} =
                 FlowSnapshot.restore_snapshot(current_flow, invalid_snapshot,
                   restore_action: {:entity_version_restore, "flow"}
                 )

        assert node_id == first_hub.id
        assert Repo.get!(Flow, flow.id).name == "Keep valid hubs"
      end

      duplicate_snapshot =
        update_snapshot_node(snapshot, second_hub.id, fn node ->
          put_in(node, ["data", "hub_id"], "first_hub")
        end)

      assert {:error, {:duplicate_snapshot_hub_id, "first_hub"}} =
               FlowSnapshot.restore_snapshot(current_flow, duplicate_snapshot,
                 restore_action: {:entity_version_restore, "flow"}
               )

      assert Repo.get!(Flow, flow.id).name == "Keep valid hubs"
    end

    test "rebuilds entity and variable references for restored active nodes", %{
      project: project,
      flow: flow
    } do
      sheet = sheet_fixture(project, %{name: "Hero", shortcut: "actors.hero"})

      health =
        block_fixture(sheet, %{
          type: "number",
          config: %{"label" => "Health", "placeholder" => "0"}
        })

      dialogue =
        node_fixture(flow, %{
          type: "dialogue",
          data: %{
            "text" => "Hello",
            "responses" => [],
            "speaker_sheet_id" => sheet.id
          }
        })

      instruction =
        node_fixture(flow, %{
          type: "instruction",
          data: %{
            "assignments" => [
              %{
                "id" => "assignment_1",
                "sheet" => "actors.hero",
                "variable" => "health",
                "operator" => "set",
                "value" => "100",
                "value_type" => "literal"
              }
            ]
          }
        })

      snapshot = FlowSnapshot.build_snapshot(flow)

      assert {:ok, _dialogue, _meta} =
               Flows.update_node_data(dialogue, %{
                 "text" => "Changed",
                 "responses" => [],
                 "speaker_sheet_id" => nil
               })

      assert {:ok, _instruction, _meta} =
               Flows.update_node_data(instruction, %{"assignments" => []})

      refute Repo.exists?(
               from(reference in EntityReference,
                 where:
                   reference.source_type == "flow_node" and
                     reference.source_id == ^dialogue.id
               )
             )

      refute Repo.exists?(
               from(reference in VariableReference,
                 where:
                   reference.source_type == "flow_node" and
                     reference.source_id == ^instruction.id
               )
             )

      assert {:ok, _restored} =
               FlowSnapshot.restore_snapshot(flow, snapshot, restore_action: {:entity_version_restore, "flow"})

      assert Repo.exists?(
               from(reference in EntityReference,
                 where:
                   reference.source_type == "flow_node" and
                     reference.source_id == ^dialogue.id and
                     reference.target_type == "sheet" and
                     reference.target_id == ^sheet.id
               )
             )

      assert Repo.exists?(
               from(reference in VariableReference,
                 where:
                   reference.source_type == "flow_node" and
                     reference.source_id == ^instruction.id and
                     reference.block_id == ^health.id and
                     reference.kind == "write"
               )
             )
    end

    test "validates and rebuilds every dialogue response variable surface atomically", %{
      project: project,
      flow: flow
    } do
      sheet = sheet_fixture(project, %{name: "Dialogue stats", shortcut: "actors.dialogue.stats"})
      condition_block = block_fixture(sheet, %{type: "number", config: %{"label" => "Condition health"}})
      structured_block = block_fixture(sheet, %{type: "number", config: %{"label" => "Structured health"}})
      legacy_block = block_fixture(sheet, %{type: "number", config: %{"label" => "Legacy health"}})

      condition = fn variable_name ->
        %{
          "logic" => "all",
          "blocks" => [
            %{
              "id" => Ecto.UUID.generate(),
              "type" => "block",
              "logic" => "all",
              "rules" => [
                %{
                  "id" => Ecto.UUID.generate(),
                  "sheet" => sheet.shortcut,
                  "variable" => variable_name,
                  "operator" => "greater_than",
                  "value" => "0"
                }
              ]
            }
          ]
        }
      end

      assignment = fn variable_name ->
        %{
          "id" => Ecto.UUID.generate(),
          "sheet" => sheet.shortcut,
          "variable" => variable_name,
          "operator" => "set",
          "value" => "1",
          "value_type" => "literal"
        }
      end

      dialogue =
        node_fixture(flow, %{
          type: "dialogue",
          data: %{
            "text" => "Choose",
            "responses" => [
              %{
                "id" => "response_structured",
                "text" => "Structured",
                "condition" => Jason.encode!(condition.(condition_block.variable_name)),
                "instruction_assignments" => [assignment.(structured_block.variable_name)]
              },
              %{
                "id" => "response_legacy",
                "text" => "Legacy",
                "condition" => nil,
                "instruction_assignments" => [],
                "instruction" => Jason.encode!([assignment.(legacy_block.variable_name)])
              }
            ]
          }
        })

      snapshot = FlowSnapshot.build_snapshot(flow)

      assert {:ok, current_dialogue, _meta} =
               Flows.update_node_data(dialogue, %{
                 "text" => "Current",
                 "responses" => []
               })

      assert {:ok, current_flow} = Flows.update_flow(flow, %{name: "Keep response variables"})

      invalid_snapshots = [
        {"missing_condition",
         update_snapshot_node(snapshot, dialogue.id, fn node ->
           put_in(
             node,
             ["data", "responses", Access.at(0), "condition"],
             Jason.encode!(condition.("missing_condition"))
           )
         end)},
        {"missing_structured",
         update_snapshot_node(snapshot, dialogue.id, fn node ->
           put_in(
             node,
             ["data", "responses", Access.at(0), "instruction_assignments", Access.at(0), "variable"],
             "missing_structured"
           )
         end)},
        {"missing_legacy",
         update_snapshot_node(snapshot, dialogue.id, fn node ->
           put_in(
             node,
             ["data", "responses", Access.at(1), "instruction"],
             Jason.encode!([assignment.("missing_legacy")])
           )
         end)}
      ]

      for {missing_variable, invalid_snapshot} <- invalid_snapshots do
        assert {:error, {:unresolved_variable_reference, "flow_node", node_id, _kind, source_sheet, ^missing_variable}} =
                 FlowSnapshot.restore_snapshot(current_flow, invalid_snapshot,
                   restore_action: {:entity_version_restore, "flow"}
                 )

        assert node_id == dialogue.id
        assert source_sheet == sheet.shortcut
        assert Repo.get!(Flow, flow.id).name == "Keep response variables"
        assert Repo.get!(FlowNode, dialogue.id).data == current_dialogue.data
      end

      assert {:ok, _restored} =
               FlowSnapshot.restore_snapshot(current_flow, snapshot, restore_action: {:entity_version_restore, "flow"})

      assert from(reference in VariableReference,
               where:
                 reference.source_type == "flow_node" and
                   reference.source_id == ^dialogue.id,
               select: {reference.block_id, reference.kind}
             )
             |> Repo.all()
             |> MapSet.new() ==
               MapSet.new([
                 {condition_block.id, "read"},
                 {structured_block.id, "write"},
                 {legacy_block.id, "write"}
               ])
    end

    test "rejects foreign and inactive rich-text mentions atomically in place", %{
      user: user,
      project: project,
      flow: flow
    } do
      local_sheet = sheet_fixture(project, %{name: "Local mention"})
      other_project = project_fixture(user)
      foreign_sheet = sheet_fixture(other_project, %{name: "Foreign mention"})
      inactive_sheet = sheet_fixture(project, %{name: "Inactive mention"})

      dialogue =
        node_fixture(flow, %{
          type: "dialogue",
          data: %{
            "text" => ~s(<p><span class="mention" data-type="sheet" data-id="#{local_sheet.id}">Local</span></p>),
            "responses" => []
          }
        })

      snapshot = FlowSnapshot.build_snapshot(flow)

      assert {:ok, current_dialogue, _meta} =
               Flows.update_node_data(dialogue, %{
                 "text" => "Current text",
                 "responses" => []
               })

      {:ok, current_flow} = Flows.update_flow(flow, %{name: "Current flow"})
      deleted_at = DateTime.truncate(DateTime.utc_now(), :second)
      Repo.update!(Ecto.Changeset.change(inactive_sheet, deleted_at: deleted_at))

      for invalid_sheet <- [foreign_sheet, inactive_sheet] do
        text =
          ~s(<p><span class="mention" data-type="sheet" data-id="#{local_sheet.id}">Local</span><span class="mention" data-type="sheet" data-id="#{invalid_sheet.id}">Invalid</span></p>)

        invalid_snapshot =
          update_snapshot_node(snapshot, dialogue.id, fn node ->
            put_in(node, ["data", "text"], text)
          end)

        assert {:error, {:invalid_project_reference, {:flow_node, node_id, "mention"}, invalid_id}} =
                 FlowSnapshot.restore_snapshot(current_flow, invalid_snapshot,
                   restore_action: {:entity_version_restore, "flow"}
                 )

        assert node_id == dialogue.id
        assert invalid_id == to_string(invalid_sheet.id)
        assert Repo.get!(Flow, flow.id).name == "Current flow"
        assert Repo.get!(FlowNode, dialogue.id).data == current_dialogue.data

        refute Repo.exists?(
                 from(reference in EntityReference,
                   where:
                     reference.source_type == "flow_node" and
                       reference.source_id == ^dialogue.id
                 )
               )
      end
    end

    test "rejects unresolved and malformed nominal variable refs atomically", %{
      project: project,
      flow: flow
    } do
      sheet = sheet_fixture(project, %{name: "Stats", shortcut: "actors.stats"})

      health =
        block_fixture(sheet, %{
          type: "number",
          config: %{"label" => "Health", "placeholder" => "0"}
        })

      instruction =
        node_fixture(flow, %{
          type: "instruction",
          data: %{
            "assignments" => [
              %{
                "id" => "restore_variable",
                "sheet" => sheet.shortcut,
                "variable" => health.variable_name,
                "operator" => "set",
                "value" => "100",
                "value_type" => "literal"
              }
            ]
          }
        })

      snapshot = FlowSnapshot.build_snapshot(flow)
      assert {:ok, current_instruction, _meta} = Flows.update_node_data(instruction, %{"assignments" => []})
      assert {:ok, current_flow} = Flows.update_flow(flow, %{name: "Current variable state"})

      Repo.update!(
        Ecto.Changeset.change(health,
          deleted_at: DateTime.truncate(DateTime.utc_now(), :second)
        )
      )

      assert {:error, {:unresolved_variable_reference, "flow_node", node_id, "write", source_sheet, source_variable}} =
               FlowSnapshot.restore_snapshot(current_flow, snapshot, restore_action: {:entity_version_restore, "flow"})

      assert node_id == instruction.id
      assert source_sheet == sheet.shortcut
      assert source_variable == health.variable_name

      malformed_snapshot =
        update_snapshot_node(snapshot, instruction.id, fn node ->
          put_in(node, ["data", "assignments", Access.at(0), "sheet"], nil)
        end)

      assert {:error, {:malformed_variable_reference, "flow_node", ^node_id, :assignment_target, {nil, ^source_variable}}} =
               FlowSnapshot.restore_snapshot(current_flow, malformed_snapshot,
                 restore_action: {:entity_version_restore, "flow"}
               )

      assert Repo.get!(Flow, flow.id).name == "Current variable state"
      assert Repo.get!(FlowNode, instruction.id).data == current_instruction.data

      refute Repo.exists?(
               from(reference in VariableReference,
                 where:
                   reference.source_type == "flow_node" and
                     reference.source_id == ^instruction.id
               )
             )
    end

    test "removes derived references for post-snapshot nodes moved to trash", %{
      project: project,
      flow: flow
    } do
      snapshot = FlowSnapshot.build_snapshot(flow)
      sheet = sheet_fixture(project, %{name: "Target", shortcut: "actors.target"})

      health =
        block_fixture(sheet, %{
          type: "number",
          config: %{"label" => "Health", "placeholder" => "0"}
        })

      dialogue =
        node_fixture(flow, %{
          type: "dialogue",
          data: %{
            "text" => "Post snapshot",
            "responses" => [],
            "speaker_sheet_id" => sheet.id
          }
        })

      instruction =
        node_fixture(flow, %{
          type: "instruction",
          data: %{
            "assignments" => [
              %{
                "id" => "assignment_post_snapshot",
                "sheet" => "actors.target",
                "variable" => "health",
                "operator" => "set",
                "value" => "0",
                "value_type" => "literal"
              }
            ]
          }
        })

      :ok = References.update_flow_node_entity_references(dialogue)
      :ok = References.update_flow_node_variable_references(instruction)

      assert Repo.exists?(
               from(reference in EntityReference,
                 where:
                   reference.source_type == "flow_node" and
                     reference.source_id == ^dialogue.id
               )
             )

      assert Repo.exists?(
               from(reference in VariableReference,
                 where:
                   reference.source_type == "flow_node" and
                     reference.source_id == ^instruction.id and
                     reference.block_id == ^health.id
               )
             )

      assert {:ok, _restored} =
               FlowSnapshot.restore_snapshot(flow, snapshot, restore_action: {:entity_version_restore, "flow"})

      assert Repo.get!(FlowNode, dialogue.id).deleted_at
      assert Repo.get!(FlowNode, instruction.id).deleted_at

      refute Repo.exists?(
               from(reference in EntityReference,
                 where:
                   reference.source_type == "flow_node" and
                     reference.source_id == ^dialogue.id
               )
             )

      refute Repo.exists?(
               from(reference in VariableReference,
                 where:
                   reference.source_type == "flow_node" and
                     reference.source_id == ^instruction.id
               )
             )
    end

    test "rejects sequence resources without snapshot identities", %{flow: flow} do
      {:ok, sequence} =
        Flows.create_sequence(flow.id, %{
          "name" => "Strict sequence",
          "width" => 400.0,
          "height" => 240.0
        })

      {:ok, track} =
        Flows.upsert_sequence_track(sequence.id, "music", %{
          "volume" => Decimal.new("0.5")
        })

      snapshot = FlowSnapshot.build_snapshot(flow)

      malformed_snapshot =
        Map.update!(snapshot, "nodes", fn nodes ->
          Enum.map(nodes, fn
            %{"original_id" => node_id, "sequence_tracks" => [track_data]} = node
            when node_id == sequence.id ->
              Map.put(node, "sequence_tracks", [Map.delete(track_data, "original_id")])

            node ->
              node
          end)
        end)

      assert {:error, {:invalid_snapshot_original_id, :sequence_track, _invalid}} =
               FlowSnapshot.restore_snapshot(flow, malformed_snapshot, restore_action: {:entity_version_restore, "flow"})

      assert Repo.get!(SequenceTrack, track.id).flow_node_id == sequence.id
    end
  end

  defp replace_localization_row(rows, target, update_fun) do
    Enum.map(rows, fn row ->
      if row == target, do: update_fun.(row), else: row
    end)
  end

  defp entity_version_identity(%EntityVersion{} = version) do
    %{
      id: version.id,
      entity_type: version.entity_type,
      entity_id: version.entity_id,
      project_id: version.project_id,
      created_by_id: version.created_by_id,
      version_number: version.version_number,
      storage_key: version.storage_key,
      snapshot_size_bytes: version.snapshot_size_bytes,
      checksum: version.checksum
    }
  end

  defp source_text_hash(text) do
    :sha256
    |> :crypto.hash(text)
    |> Base.encode16(case: :lower)
  end

  defp flow_node_ids(flow_id) do
    FlowNode
    |> where([node], node.flow_id == ^flow_id)
    |> select([node], node.id)
    |> Repo.all()
    |> Enum.sort()
  end

  defp active_exit_node(flow_id) do
    Repo.one!(
      from(node in FlowNode,
        where:
          node.flow_id == ^flow_id and node.type == "exit" and
            is_nil(node.deleted_at),
        order_by: [asc: node.id],
        limit: 1
      )
    )
  end

  defp set_node_data(node, attrs) do
    Repo.update_all(
      from(current in FlowNode, where: current.id == ^node.id),
      set: [data: Map.merge(node.data || %{}, attrs)]
    )
  end

  defp update_snapshot_node(snapshot, node_id, update_fun) do
    Map.update!(snapshot, "nodes", fn nodes ->
      Enum.map(nodes, fn
        %{"original_id" => ^node_id} = node -> update_fun.(node)
        node -> node
      end)
    end)
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
end
