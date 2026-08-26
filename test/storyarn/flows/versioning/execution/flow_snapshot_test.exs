defmodule Storyarn.Flows.VersioningFlowSnapshotTest do
  use Storyarn.DataCase, async: false

  import Ecto.Query, warn: false
  import Storyarn.AccountsFixtures
  import Storyarn.AssetsFixtures
  import Storyarn.FlowsFixtures
  import Storyarn.LocalizationFixtures
  import Storyarn.ProjectsFixtures

  alias Storyarn.Flows
  alias Storyarn.Flows.Flow
  alias Storyarn.Flows.FlowConnection
  alias Storyarn.Flows.FlowNode
  alias Storyarn.Flows.SequenceConfig
  alias Storyarn.Flows.SequenceTrack
  alias Storyarn.Flows.SequenceVisualLayer
  alias Storyarn.Flows.Versioning
  alias Storyarn.Flows.Versioning.FlowSnapshot
  alias Storyarn.Flows.Versioning.RestorePolicy
  alias Storyarn.Localization
  alias Storyarn.Localization.LocalizedText
  alias Storyarn.Projects.Assets
  alias Storyarn.Projects.Assets.Asset
  alias Storyarn.Projects.Assets.BlobStore
  alias Storyarn.Projects.Persistence.FlowRecord, as: ProjectFlowRecord
  alias Storyarn.Projects.Versioning.Builders.FlowBuilder, as: LegacyFlowBuilder
  alias Storyarn.Repo

  setup do
    previous_policy = Application.get_env(:storyarn, RestorePolicy)
    Application.put_env(:storyarn, RestorePolicy, flow_version_restore: true)

    on_exit(fn ->
      if is_nil(previous_policy),
        do: Application.delete_env(:storyarn, RestorePolicy),
        else: Application.put_env(:storyarn, RestorePolicy, previous_policy)
    end)

    user = user_fixture(%{email: "flow-versioning-#{Ecto.UUID.generate()}@example.com"})
    project = project_fixture(user)
    flow = flow_fixture(project, %{name: "Opening", shortcut: "opening"})

    %{user: user, project: project, flow: flow}
  end

  describe "shared snapshot contract" do
    test "keeps localized conflict contexts and reports malformed rich-text mentions" do
      snapshot = %{
        "nodes" => [
          %{
            "type" => "dialogue",
            "data" => %{
              "speaker_sheet_id" => 101,
              "location_sheet_id" => 102,
              "referenced_flow_id" => 103,
              "target_type" => "scene",
              "target_id" => 104,
              "text" => ~s(<span class="mention" data-type="sheet">Broken</span>)
            }
          }
        ]
      }

      references =
        Gettext.with_locale(Storyarn.Gettext, "es", fn ->
          FlowSnapshot.scan_references(snapshot)
        end)

      contexts = MapSet.new(references, & &1.context)

      assert MapSet.member?(contexts, "Nodo #1 (dialogue) — hablante")
      assert MapSet.member?(contexts, "Nodo #1 (dialogue) — ubicación")
      assert MapSet.member?(contexts, "Nodo #1 (dialogue) — flujo referenciado")
      assert MapSet.member?(contexts, "Nodo #1 (dialogue) — destino terminal")
      assert MapSet.member?(contexts, "Nodo #1 (dialogue) — mención de texto enriquecido")

      assert Enum.any?(references, fn reference ->
               reference.type == :reference and
                 reference.context == "Nodo #1 (dialogue) — mención de texto enriquecido"
             end)
    end

    test "local capture is byte-compatible with the Project reader", %{
      user: user,
      project: project,
      flow: flow
    } do
      _source = source_language_fixture(project, %{locale_code: "en", name: "English"})
      _target = language_fixture(project, %{locale_code: "es", name: "Spanish"})

      _dialogue =
        node_fixture(flow, %{
          type: "dialogue",
          data: %{
            "localization_id" => "opening_dialogue",
            "text" => "A local snapshot",
            "responses" => [%{"id" => "continue", "text" => "Continue"}]
          }
        })

      audio = uploaded_asset(project, user, "golden-sequence.mp3", "golden audio", "audio/mpeg")
      image = uploaded_asset(project, user, "golden-sequence.png", "golden image", "image/png")

      assert {:ok, sequence} =
               Flows.create_sequence(flow.id, %{
                 "name" => "Golden sequence",
                 "width" => 640.0,
                 "height" => 360.0,
                 "position_x" => 50.0,
                 "position_y" => 75.0
               })

      _child = node_fixture(flow, %{type: "hub", parent_id: sequence.id, position_x: 100.0})

      assert {:ok, _track} =
               Flows.upsert_sequence_track(sequence.id, "music", %{
                 "asset_id" => audio.id,
                 "position" => 2,
                 "start_time" => Decimal.new("1.25"),
                 "end_time" => Decimal.new("9.5"),
                 "volume" => Decimal.new("0.75")
               })

      assert {:ok, _layer} =
               Flows.create_sequence_visual_layer(sequence.id, %{
                 "asset_id" => image.id,
                 "kind" => "backdrop",
                 "label" => "Golden backdrop",
                 "z_index" => 3,
                 "opacity" => 0.8
               })

      local = FlowSnapshot.build_snapshot(flow)
      legacy = flow.id |> then(&Repo.get!(ProjectFlowRecord, &1)) |> LegacyFlowBuilder.build_snapshot()

      assert local == legacy
      assert :ok = LegacyFlowBuilder.validate_portable_snapshot(local)

      assert Enum.all?(local["localization"], fn row ->
               row |> Map.keys() |> Enum.sort() ==
                 Enum.sort(~w(
                     archive_reason archived_at last_reviewed_at last_translated_at locale_code
                     machine_translated reviewer_notes reviewed_by_id source_field source_id source_text
                     source_text_hash source_type speaker_sheet_id status translated_by_id
                     translated_source_hash translated_text translator_notes vo_asset_id vo_status word_count
                   ))
             end)

      assert {:ok, changed} = Flows.update_flow(flow, %{name: "Changed"})

      assert {:ok, restored} =
               FlowSnapshot.restore_snapshot(changed, legacy, restore_action: {:entity_version_restore, "flow"})

      assert restored.name == flow.name
    end

    test "round-trips nested sequence state with exact persistent identities", %{
      user: user,
      project: project,
      flow: flow
    } do
      audio = uploaded_asset(project, user, "restore-sequence.mp3", "restore audio", "audio/mpeg")
      image = uploaded_asset(project, user, "restore-sequence.png", "restore image", "image/png")

      assert {:ok, sequence} =
               Flows.create_sequence(flow.id, %{
                 "name" => "Original sequence",
                 "width" => 500.0,
                 "height" => 280.0
               })

      child = node_fixture(flow, %{type: "hub", parent_id: sequence.id, position_x: 150.0})

      assert {:ok, track} =
               Flows.upsert_sequence_track(sequence.id, "ambience", %{
                 "asset_id" => audio.id,
                 "volume" => Decimal.new("0.4")
               })

      assert {:ok, layer} =
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

      assert FlowSnapshot.build_snapshot(restored) == snapshot

      restored_sequence = Enum.find(restored.nodes, &(&1.id == sequence.id))
      restored_child = Enum.find(restored.nodes, &(&1.id == child.id))

      assert restored_child.parent_id == sequence.id

      assert %SequenceConfig{name: "Original sequence", width: 500.0, height: 280.0} =
               restored_sequence.sequence_config

      assert [%SequenceTrack{id: track_id, kind: "ambience", asset_id: restored_audio_id, volume: volume}] =
               restored_sequence.sequence_tracks

      assert track_id == track.id
      assert restored_audio_id == audio.id
      assert Decimal.equal?(volume, Decimal.new("0.4"))
      refute Repo.get(SequenceTrack, replacement_track.id)

      assert [
               %SequenceVisualLayer{
                 id: layer_id,
                 kind: "overlay",
                 asset_id: restored_image_id,
                 label: "Mist"
               }
             ] = restored_sequence.sequence_visual_layers

      assert layer_id == layer.id
      assert restored_image_id == image.id
      refute Repo.get(SequenceVisualLayer, replacement_layer.id)
    end

    test "builder restore fails closed unless the entity action is explicit", %{flow: flow} do
      snapshot = FlowSnapshot.build_snapshot(flow)
      assert {:ok, changed} = Flows.update_flow(flow, %{name: "Must remain"})

      assert {:error, :restore_temporarily_disabled} =
               FlowSnapshot.restore_snapshot(changed, snapshot)

      assert Repo.get!(Flow, flow.id).name == "Must remain"

      assert {:ok, restored} =
               FlowSnapshot.restore_snapshot(changed, snapshot, restore_action: {:entity_version_restore, "flow"})

      assert restored.name == flow.name
    end

    test "exhaustive validation rejects invalid dialogue identities before writing", %{flow: flow} do
      dialogue =
        node_fixture(flow, %{
          type: "dialogue",
          data: %{
            "localization_id" => "stable_dialogue",
            "text" => "Historical",
            "responses" => []
          }
        })

      snapshot = FlowSnapshot.build_snapshot(flow)

      invalid =
        update_snapshot_node(snapshot, dialogue.id, fn node ->
          update_in(node["data"], &Map.delete(&1, "localization_id"))
        end)

      assert {:error, _reason} =
               FlowSnapshot.restore_snapshot(flow, invalid, restore_action: {:entity_version_restore, "flow"})

      assert Repo.get!(FlowNode, dialogue.id).data["localization_id"] == "stable_dialogue"
    end
  end

  describe "graph and trash integrity" do
    test "build rejects malformed and unbound dynamic exit pins", %{project: project, flow: flow} do
      referenced_flow = flow_fixture(project)
      referenced_exit = active_node!(referenced_flow.id, "exit")

      subflow =
        node_fixture(flow, %{
          type: "subflow",
          data: %{"referenced_flow_id" => referenced_flow.id}
        })

      target = node_fixture(flow, %{type: "hub"})

      connection =
        connection_fixture(flow, subflow, target, %{
          source_pin: "exit_#{referenced_exit.id}"
        })

      Repo.update_all(
        from(current in FlowConnection, where: current.id == ^connection.id),
        set: [source_pin: "exit_not-an-id"]
      )

      assert_raise ArgumentError, ~r/dynamic_exit_pin_not_materializable/, fn ->
        FlowSnapshot.build_snapshot(flow)
      end

      Repo.update_all(
        from(current in FlowConnection, where: current.id == ^connection.id),
        set: [source_pin: "exit_#{referenced_exit.id}"]
      )

      Repo.update_all(
        from(current in FlowNode, where: current.id == ^subflow.id),
        set: [data: %{}]
      )

      assert_raise ArgumentError, ~r/missing_referenced_flow/, fn ->
        FlowSnapshot.build_snapshot(flow)
      end
    end

    test "incoming dynamic exits block restore atomically, including callers in trash", %{
      project: project,
      flow: referenced_flow
    } do
      snapshot_without_new_exit = FlowSnapshot.build_snapshot(referenced_flow)
      referenced_exit = node_fixture(referenced_flow, %{type: "exit", position_x: 700.0})
      assert {:ok, current_flow} = Flows.update_flow(referenced_flow, %{name: "Current"})

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
      assert Repo.get!(Flow, referenced_flow.id).name == "Current"
      assert Repo.get!(FlowNode, referenced_exit.id).deleted_at == nil

      assert {:ok, _trashed_subflow, _metadata} = Flows.delete_node(subflow)

      assert {:error,
              {:incoming_dynamic_exit_pin_would_break, ^connection_id, ^source_pin, ^restored_flow_id,
               :exit_missing_from_snapshot}} =
               FlowSnapshot.restore_snapshot(current_flow, snapshot_without_new_exit,
                 restore_action: {:entity_version_restore, "flow"}
               )
    end

    test "preserves prior trash and only soft-deletes active post-snapshot state", %{flow: flow} do
      active_target = node_fixture(flow, %{type: "hub", position_x: 100.0})
      existing_trash = node_fixture(flow, %{type: "dialogue", position_x: 200.0})
      trash_connection = connection_fixture(flow, existing_trash, active_target)
      assert {:ok, trashed_node, _metadata} = Flows.delete_node(existing_trash)

      assert {:ok, trashed_sequence} =
               Flows.create_sequence(flow.id, %{
                 "name" => "Keep trash resources",
                 "width" => 400.0,
                 "height" => 240.0
               })

      assert {:ok, trash_track} =
               Flows.upsert_sequence_track(trashed_sequence.id, "music", %{
                 "position" => 4,
                 "volume" => Decimal.new("0.5")
               })

      assert {:ok, trashed_sequence, _metadata} = Flows.delete_node(trashed_sequence)
      snapshot = FlowSnapshot.build_snapshot(flow)

      post_snapshot = node_fixture(flow, %{type: "hub", position_x: 300.0})
      post_snapshot_connection = connection_fixture(flow, active_target, post_snapshot)

      assert {:ok, restored} =
               FlowSnapshot.restore_snapshot(flow, snapshot, restore_action: {:entity_version_restore, "flow"})

      assert Repo.get!(FlowNode, existing_trash.id).deleted_at == trashed_node.deleted_at
      assert Repo.get!(FlowNode, trashed_sequence.id).deleted_at == trashed_sequence.deleted_at
      assert Repo.get!(FlowNode, post_snapshot.id).deleted_at
      assert Repo.get!(SequenceTrack, trash_track.id).flow_node_id == trashed_sequence.id
      assert Repo.get!(FlowConnection, trash_connection.id)
      assert Repo.get!(FlowConnection, post_snapshot_connection.id)
      refute Enum.any?(restored.nodes, &(&1.id in [existing_trash.id, trashed_sequence.id, post_snapshot.id]))
    end
  end

  describe "asset materialization and compensation" do
    test "captures and restores a zero-byte Flow asset", %{
      user: user,
      project: project,
      flow: flow
    } do
      audio = zero_byte_asset(project, user, "empty.mp3", "audio/mpeg")

      dialogue =
        node_fixture(flow, %{
          type: "dialogue",
          data: %{
            "localization_id" => "empty_audio",
            "text" => "Historical",
            "responses" => [],
            "audio_asset_id" => audio.id
          }
        })

      snapshot = FlowSnapshot.build_snapshot(flow)
      assert snapshot["asset_metadata"][Integer.to_string(audio.id)]["size"] == 0

      assert {:ok, _current, _metadata} =
               Flows.update_node_data(dialogue, %{
                 "localization_id" => "empty_audio",
                 "text" => "Current",
                 "responses" => []
               })

      assert {:ok, _deleted} = Assets.delete_asset(audio)

      assert {:ok, _restored} =
               FlowSnapshot.restore_snapshot(flow, snapshot, restore_action: {:entity_version_restore, "flow"})

      restored_asset_id = Repo.get!(FlowNode, dialogue.id).data["audio_asset_id"]
      refute restored_asset_id == audio.id

      restored_asset = Repo.get!(Asset, restored_asset_id)
      assert restored_asset.size == 0
      assert restored_asset.blob_hash == audio.blob_hash
      assert {:ok, ""} = Assets.storage_download(restored_asset.key)
      on_exit(fn -> Assets.storage_delete(restored_asset.key) end)
    end

    test "active asset fingerprint drift is previewed and fails closed before committing restore state", %{
      user: user,
      project: project,
      flow: flow
    } do
      audio = uploaded_asset(project, user, "drifted.mp3", "historical audio", "audio/mpeg")

      _dialogue =
        node_fixture(flow, %{
          type: "dialogue",
          data: %{
            "localization_id" => "drifted_audio",
            "text" => "Historical",
            "responses" => [],
            "audio_asset_id" => audio.id
          }
        })

      snapshot = FlowSnapshot.build_snapshot(flow)
      assert {:ok, changed} = Flows.update_flow(flow, %{name: "Must survive failed restore"})

      Repo.update_all(
        from(asset in Asset, where: asset.id == ^audio.id),
        set: [size: audio.size + 1]
      )

      report = Versioning.detect_restore_conflicts(snapshot, changed)
      assert Enum.any?(report.conflicts, &(&1.type == :asset and &1.id == audio.id))

      assert {:error, :existing_asset_fingerprint_mismatch} =
               FlowSnapshot.restore_snapshot(changed, snapshot, restore_action: {:entity_version_restore, "flow"})

      assert Repo.get!(Flow, flow.id).name == "Must survive failed restore"
    end

    test "preview accepts and restore recreates a deleted historical asset", %{
      user: user,
      project: project,
      flow: flow
    } do
      audio = uploaded_asset(project, user, "historical.mp3", "historical audio", "audio/mpeg")

      dialogue =
        node_fixture(flow, %{
          type: "dialogue",
          data: %{
            "localization_id" => "historical_audio",
            "text" => "Historical",
            "responses" => [],
            "audio_asset_id" => audio.id
          }
        })

      snapshot = FlowSnapshot.build_snapshot(flow)

      assert {:ok, _current, _metadata} =
               Flows.update_node_data(dialogue, %{
                 "localization_id" => "historical_audio",
                 "text" => "Current",
                 "responses" => []
               })

      assert {:ok, _deleted} = Assets.delete_asset(audio)

      report = Versioning.detect_restore_conflicts(snapshot, flow)
      refute Enum.any?(report.conflicts, &(&1.type == :asset and &1.id == audio.id))

      assert {:ok, _restored} =
               FlowSnapshot.restore_snapshot(flow, snapshot, restore_action: {:entity_version_restore, "flow"})

      restored_asset_id = Repo.get!(FlowNode, dialogue.id).data["audio_asset_id"]
      refute restored_asset_id == audio.id

      restored_asset = Repo.get!(Asset, restored_asset_id)
      assert restored_asset.blob_hash == audio.blob_hash
      assert {:ok, "historical audio"} = Assets.storage_download(restored_asset.key)
      on_exit(fn -> Assets.storage_delete(restored_asset.key) end)
    end

    test "post-commit failure never compensates an asset already referenced by the commit", %{
      user: user,
      project: project,
      flow: flow
    } do
      audio = uploaded_asset(project, user, "committed.mp3", "committed audio", "audio/mpeg")

      dialogue =
        node_fixture(flow, %{
          type: "dialogue",
          data: %{
            "localization_id" => "committed_audio",
            "text" => "Committed",
            "responses" => [],
            "audio_asset_id" => audio.id
          }
        })

      snapshot = FlowSnapshot.build_snapshot(flow)

      assert_raise RuntimeError, "post-commit finalization failed", fn ->
        FlowSnapshot.restore_snapshot(flow, snapshot,
          asset_mode: :copy,
          restore_action: {:entity_version_restore, "flow"},
          __post_commit_restore_hook: fn -> raise "post-commit finalization failed" end
        )
      end

      restored_asset_id = Repo.get!(FlowNode, dialogue.id).data["audio_asset_id"]
      refute restored_asset_id == audio.id

      restored_asset = Repo.get!(Asset, restored_asset_id)
      assert {:ok, "committed audio"} = Assets.storage_download(restored_asset.key)
      on_exit(fn -> Assets.storage_delete(restored_asset.key) end)
    end
  end

  describe "diff and main-flow concurrency" do
    test "diff ignores canvas-only moves and matches legacy semantics", %{flow: flow} do
      dialogue = node_fixture(flow, %{type: "dialogue", data: %{"text" => "Diff", "responses" => []}})
      old_snapshot = FlowSnapshot.build_snapshot(flow)

      moved =
        update_snapshot_node(old_snapshot, dialogue.id, fn node ->
          node
          |> Map.put("position_x", node["position_x"] + 200.0)
          |> Map.put("position_y", node["position_y"] + 100.0)
        end)

      assert FlowSnapshot.diff_snapshots(old_snapshot, moved) == []

      renamed = Map.put(moved, "name", "Renamed")

      assert [
               %{
                 category: :property,
                 action: :modified,
                 detail: detail
               }
             ] = FlowSnapshot.diff_snapshots(old_snapshot, renamed)

      assert detail =~ "Renamed flow"
    end

    test "retries a concurrent main collision before committing graph state", %{
      project: project,
      flow: flow
    } do
      assert {:ok, main_flow} = Flows.set_main_flow(flow)
      snapshot = FlowSnapshot.build_snapshot(main_flow)
      assert {:ok, demoted_flow} = Flows.update_flow(main_flow, %{is_main: false})
      competing_flow = flow_fixture(project)
      attempt_key = {__MODULE__, make_ref()}

      hook = fn ->
        attempt = Process.get(attempt_key, 0) + 1
        Process.put(attempt_key, attempt)

        if attempt == 1 do
          Repo.update_all(
            from(candidate in Flow, where: candidate.id == ^competing_flow.id),
            set: [is_main: true]
          )
        end
      end

      assert {:ok, restored} =
               FlowSnapshot.restore_snapshot(demoted_flow, snapshot,
                 restore_action: {:entity_version_restore, "flow"},
                 __before_main_write_hook: hook
               )

      assert Process.get(attempt_key) == 2
      refute restored.is_main
      refute Repo.get!(Flow, competing_flow.id).is_main
    end
  end

  describe "localization reconciliation" do
    test "preserves archived-language rows and creates pending rows for a newly active locale", %{
      project: project,
      flow: flow
    } do
      _source = source_language_fixture(project, %{locale_code: "en", name: "English"})
      es = language_fixture(project, %{locale_code: "es", name: "Spanish"})

      dialogue =
        node_fixture(flow, %{
          type: "dialogue",
          data: %{
            "localization_id" => "localized_dialogue",
            "text" => "Historical line",
            "responses" => []
          }
        })

      snapshot = FlowSnapshot.build_snapshot(flow)
      assert {:ok, _archived_es} = Localization.remove_language(es)
      _fr = language_fixture(project, %{locale_code: "fr", name: "French"})

      archived_state =
        project.id
        |> Localization.list_all_texts(source_type: "flow_node", include_archived: true)
        |> Enum.filter(&(&1.source_id == dialogue.id and &1.locale_code == "es"))

      assert {:ok, _restored} =
               FlowSnapshot.restore_snapshot(flow, snapshot, restore_action: {:entity_version_restore, "flow"})

      assert project.id
             |> Localization.list_all_texts(source_type: "flow_node", include_archived: true)
             |> Enum.filter(&(&1.source_id == dialogue.id and &1.locale_code == "es")) ==
               archived_state

      assert [%LocalizedText{locale_code: "fr", status: "pending", translated_text: nil}] =
               "flow_node"
               |> Localization.get_texts_for_source(dialogue.id)
               |> Enum.filter(&(&1.locale_code == "fr"))
    end
  end

  defp active_node!(flow_id, type) do
    Repo.one!(
      from(node in FlowNode,
        where:
          node.flow_id == ^flow_id and node.type == ^type and
            is_nil(node.deleted_at),
        limit: 1
      )
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

      Assets.storage_delete(
        BlobStore.blob_key(
          project.id,
          asset.blob_hash,
          BlobStore.ext_from_content_type(content_type)
        )
      )
    end)

    asset
  end

  defp zero_byte_asset(project, user, filename, content_type) do
    asset = asset_fixture(project, user, %{filename: filename, content_type: content_type})
    blob_hash = BlobStore.compute_hash("")
    blob_key = BlobStore.blob_key(project.id, blob_hash, BlobStore.ext_from_content_type(content_type))

    assert {:ok, _url} = Assets.storage_upload(asset.key, "", content_type)

    Repo.update_all(
      from(candidate in Asset, where: candidate.id == ^asset.id),
      set: [size: 0, blob_hash: blob_hash]
    )

    on_exit(fn ->
      Assets.storage_delete(asset.key)
      Assets.storage_delete(blob_key)
    end)

    Repo.get!(Asset, asset.id)
  end
end
