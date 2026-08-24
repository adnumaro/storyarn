defmodule Storyarn.Projects.Versioning.Builders.FlowBuilderTest do
  use Storyarn.DataCase, async: false
  use Oban.Testing, repo: Storyarn.Repo

  import Storyarn.AccountsFixtures
  import Storyarn.FlowsFixtures
  import Storyarn.LocalizationFixtures
  import Storyarn.ProjectsFixtures
  import Storyarn.ScenesFixtures, only: [scene_fixture: 1]
  import Storyarn.SheetsFixtures

  alias Storyarn.Flows
  alias Storyarn.Localization
  alias Storyarn.Localization.LocalizedText
  alias Storyarn.Projects.Assets
  alias Storyarn.Projects.Assets.Asset
  alias Storyarn.Projects.Assets.BlobStore
  alias Storyarn.Projects.Persistence.FlowConnectionRecord, as: ProjectFlowConnection
  alias Storyarn.Projects.Persistence.FlowNodeRecord, as: FlowNode
  alias Storyarn.Projects.Persistence.FlowRecord, as: Flow
  alias Storyarn.Projects.Persistence.SequenceConfigRecord, as: SequenceConfig
  alias Storyarn.Projects.Persistence.SequenceTrackRecord, as: SequenceTrack
  alias Storyarn.Projects.Persistence.SequenceVisualLayerRecord, as: SequenceVisualLayer
  alias Storyarn.Projects.Persistence.VariableReferenceRecord, as: VariableReference
  alias Storyarn.Projects.Project
  alias Storyarn.Projects.Versioning.Builders.FlowBuilder
  alias Storyarn.Projects.Versioning.LocalizationSnapshotCodec
  alias Storyarn.Projects.Workers.DeleteStorageObjectsWorker
  alias Storyarn.Repo
  alias Storyarn.Scenes.Scene
  alias Storyarn.Sheets.EntityReference
  alias Storyarn.Sheets.SheetAvatar

  setup do
    user = user_fixture(%{email: "flow-builder-#{Ecto.UUID.generate()}@example.com"})
    project = project_fixture(user)
    flow = flow_fixture(project)

    %{user: user, project: project, flow: flow}
  end

  describe "build_snapshot/1" do
    test "captures flow metadata", %{flow: flow} do
      snapshot = FlowBuilder.build_snapshot(flow)

      assert snapshot["name"] == flow.name
      assert snapshot["shortcut"] == flow.shortcut
      assert snapshot["description"] == flow.description
      assert is_list(snapshot["nodes"])
      assert is_list(snapshot["connections"])
      refute Enum.any?(snapshot["nodes"], &Map.has_key?(&1, "word_count"))
    end

    test "captures nodes sorted deterministically", %{flow: flow} do
      _n1 = node_fixture(flow, %{type: "dialogue", position_x: 200.0, position_y: 100.0})
      _n2 = node_fixture(flow, %{type: "hub", position_x: 100.0, position_y: 100.0})

      snapshot = FlowBuilder.build_snapshot(flow)

      # Hub at x=100 should come before dialogue at x=200
      types = Enum.map(snapshot["nodes"], & &1["type"])
      hub_idx = Enum.find_index(types, &(&1 == "hub"))
      dialogue_idx = Enum.find_index(types, &(&1 == "dialogue"))
      assert hub_idx < dialogue_idx
    end

    test "fails closed instead of emitting an internally inconsistent localization snapshot", %{
      project: project,
      flow: flow
    } do
      _en = source_language_fixture(project, %{locale_code: "en", name: "English"})
      _es = language_fixture(project, %{locale_code: "es", name: "Spanish"})
      node = node_fixture(flow, %{type: "dialogue", data: %{"text" => "Runtime line", "responses" => []}})
      [text] = Localization.get_texts_for_source("flow_node", node.id)

      Repo.update_all(
        from(localized_text in LocalizedText, where: localized_text.id == ^text.id),
        set: [source_text: "Corrupt source"]
      )

      assert_raise ArgumentError, ~r/internally inconsistent flow snapshot/, fn ->
        FlowBuilder.build_snapshot(flow)
      end
    end

    test "captures untranslated active-locale gaps as explicit pending rows", %{
      project: project,
      flow: flow
    } do
      _en = source_language_fixture(project, %{locale_code: "en", name: "English"})
      _ca = language_fixture(project, %{locale_code: "ca", name: "Catalan"})

      node =
        node_fixture(flow, %{
          type: "dialogue",
          data: %{"text" => "Runtime line", "responses" => []}
        })

      assert {1, _rows} =
               Repo.delete_all(
                 from(text in LocalizedText,
                   where:
                     text.source_type == "flow_node" and text.source_id == ^node.id and
                       text.source_field == "text" and text.locale_code == "ca"
                 )
               )

      snapshot = FlowBuilder.build_snapshot(flow)

      assert [
               %{
                 "locale_code" => "ca",
                 "source_field" => "text",
                 "source_id" => source_id,
                 "source_text" => "Runtime line",
                 "status" => "pending",
                 "translated_source_hash" => nil,
                 "translated_text" => nil,
                 "vo_status" => "none"
               }
             ] = snapshot["localization"]

      assert source_id == node.id

      assert snapshot["localization_manifest"] ==
               LocalizationSnapshotCodec.manifest(snapshot["localization"], ["ca"])

      assert [] = Localization.get_texts_for_source("flow_node", node.id)
    end

    test "still rejects an active localization row for a source outside the snapshot contract", %{
      project: project,
      flow: flow
    } do
      _en = source_language_fixture(project, %{locale_code: "en", name: "English"})
      _ca = language_fixture(project, %{locale_code: "ca", name: "Catalan"})

      node =
        node_fixture(flow, %{
          type: "dialogue",
          data: %{"text" => "Runtime line", "responses" => []}
        })

      assert [_row] = Localization.get_texts_for_source("flow_node", node.id)

      Repo.update_all(
        from(current in FlowNode, where: current.id == ^node.id),
        set: [type: "hub"]
      )

      assert_raise ArgumentError, ~r/internally inconsistent flow snapshot/, fn ->
        FlowBuilder.build_snapshot(flow)
      end
    end

    test "captures connections with index references", %{flow: flow} do
      n1 =
        node_fixture(flow, %{
          type: "dialogue",
          position_x: 100.0,
          position_y: 100.0,
          data: %{"text" => "One two three", "responses" => []}
        })

      n2 = node_fixture(flow, %{type: "hub", position_x: 200.0, position_y: 100.0})
      _conn = connection_fixture(flow, n1, n2)

      snapshot = FlowBuilder.build_snapshot(flow)
      assert length(snapshot["connections"]) == 1

      [conn] = snapshot["connections"]
      assert is_integer(conn["source_node_index"])
      assert is_integer(conn["target_node_index"])
      assert conn["source_pin"] == "output"
      assert conn["target_pin"] == "input"
    end

    test "excludes soft-deleted nodes", %{flow: flow} do
      node = node_fixture(flow)
      Flows.delete_node(node)

      snapshot = FlowBuilder.build_snapshot(flow)
      # The dialogue node should be excluded
      assert Enum.all?(snapshot["nodes"], fn n -> n["type"] != "dialogue" end)
    end

    test "captures sequence hierarchy, config, tracks, visual layers, and assets", %{
      user: user,
      project: project,
      flow: flow
    } do
      audio = uploaded_asset(project, user, "sequence.mp3", "sequence audio", "audio/mpeg")
      image = uploaded_asset(project, user, "sequence.png", "sequence image", "image/png")

      {:ok, sequence} =
        Flows.create_sequence(flow.id, %{
          "name" => "Arrival",
          "width" => 640.0,
          "height" => 360.0,
          "position_x" => 50.0,
          "position_y" => 75.0
        })

      child = node_fixture(flow, %{type: "hub", parent_id: sequence.id, position_x: 100.0})

      assert {:ok, track_row} =
               Flows.upsert_sequence_track(sequence.id, "music", %{
                 "asset_id" => audio.id,
                 "position" => 2,
                 "start_time" => Decimal.new("1.25"),
                 "end_time" => Decimal.new("9.5"),
                 "volume" => Decimal.new("0.75")
               })

      assert {:ok, layer_row} =
               Flows.create_sequence_visual_layer(sequence.id, %{
                 "asset_id" => image.id,
                 "kind" => "backdrop",
                 "label" => "Castle",
                 "z_index" => 3,
                 "opacity" => 0.8
               })

      snapshot = FlowBuilder.build_snapshot(flow)
      sequence_snapshot = Enum.find(snapshot["nodes"], &(&1["original_id"] == sequence.id))
      child_snapshot = Enum.find(snapshot["nodes"], &(&1["original_id"] == child.id))

      assert child_snapshot["parent_id"] == sequence.id

      assert sequence_snapshot["sequence_config"] == %{
               "name" => "Arrival",
               "width" => 640.0,
               "height" => 360.0
             }

      assert [track] = sequence_snapshot["sequence_tracks"]
      assert track["original_id"] == track_row.id
      assert track["kind"] == "music"
      assert track["asset_id"] == audio.id
      assert track["start_time"] == "1.250"
      assert track["end_time"] == "9.500"
      assert track["volume"] == "0.750"

      assert [layer] = sequence_snapshot["sequence_visual_layers"]
      assert layer["original_id"] == layer_row.id
      assert layer["asset_id"] == image.id
      assert layer["label"] == "Castle"
      assert layer["z_index"] == 3
      assert layer["opacity"] == 0.8

      assert snapshot["asset_blob_hashes"][to_string(audio.id)] == audio.blob_hash
      assert snapshot["asset_blob_hashes"][to_string(image.id)] == image.blob_hash
    end

    test "rejects cross-project assets from every Flow asset-bearing surface", %{
      user: user,
      project: project,
      flow: flow
    } do
      foreign_project = project_fixture(user)

      foreign_audio =
        uploaded_asset(
          foreign_project,
          user,
          "foreign-audio.mp3",
          "foreign audio",
          "audio/mpeg"
        )

      foreign_image =
        uploaded_asset(
          foreign_project,
          user,
          "foreign-image.png",
          "foreign image",
          "image/png"
        )

      audio_node =
        node_fixture(flow, %{
          type: "dialogue",
          data: %{
            "text" => "Corrupt audio reference",
            "responses" => []
          }
        })

      set_node_data(audio_node, %{"audio_asset_id" => foreign_audio.id})

      assert_raise ArgumentError, ~r/owned by another project/, fn ->
        FlowBuilder.build_snapshot(flow)
      end

      sequence_flow = flow_fixture(project)

      {:ok, sequence} =
        Flows.create_sequence(sequence_flow.id, %{
          "name" => "Corrupt sequence",
          "width" => 640.0,
          "height" => 360.0
        })

      track =
        %SequenceTrack{}
        |> SequenceTrack.create_changeset(%{
          flow_node_id: sequence.id,
          kind: "music",
          asset_id: foreign_audio.id
        })
        |> Repo.insert!()

      assert_raise ArgumentError, ~r/owned by another project/, fn ->
        FlowBuilder.build_snapshot(sequence_flow)
      end

      Repo.update_all(
        from(current in SequenceTrack, where: current.id == ^track.id),
        set: [asset_id: nil]
      )

      %SequenceVisualLayer{}
      |> SequenceVisualLayer.create_changeset(%{
        flow_node_id: sequence.id,
        kind: "overlay",
        asset_id: foreign_image.id
      })
      |> Repo.insert!()

      assert_raise ArgumentError, ~r/owned by another project/, fn ->
        FlowBuilder.build_snapshot(sequence_flow)
      end

      _en = source_language_fixture(project, %{locale_code: "en", name: "English"})
      _es = language_fixture(project, %{locale_code: "es", name: "Spanish"})
      voice_flow = flow_fixture(project)

      voice_node =
        node_fixture(voice_flow, %{
          type: "dialogue",
          data: %{"text" => "Corrupt voice reference", "responses" => []}
        })

      [voice_text] = Localization.get_texts_for_source("flow_node", voice_node.id)

      Repo.update_all(
        from(current in LocalizedText, where: current.id == ^voice_text.id),
        set: [vo_asset_id: foreign_audio.id, vo_status: "recorded"]
      )

      assert_raise ArgumentError, ~r/owned by another project/, fn ->
        FlowBuilder.build_snapshot(voice_flow)
      end
    end

    test "reloads stale node, connection, and sequence preloads from the database", %{
      user: user,
      project: project,
      flow: flow
    } do
      image = uploaded_asset(project, user, "fresh.png", "fresh image", "image/png")

      {:ok, sequence} =
        Flows.create_sequence(flow.id, %{
          "name" => "Fresh sequence",
          "width" => 640.0,
          "height" => 360.0
        })

      anchor = node_fixture(flow, %{type: "hub", position_x: 100.0})
      obsolete = node_fixture(flow, %{type: "hub", position_x: 200.0})
      obsolete_connection = connection_fixture(flow, anchor, obsolete)

      stale_flow =
        Repo.preload(
          flow,
          [
            :connections,
            nodes: [:sequence_config, :sequence_tracks, :sequence_visual_layers]
          ],
          force: true
        )

      assert {:ok, _updated_flow} =
               Flows.update_flow(flow, %{name: "Fresh database root"})

      assert {:ok, _deleted, _meta} = Flows.delete_node(obsolete)

      current = node_fixture(flow, %{type: "hub", position_x: 300.0})
      current_connection = connection_fixture(flow, anchor, current)

      assert {:ok, track} =
               Flows.upsert_sequence_track(sequence.id, "music", %{
                 "position" => 2,
                 "volume" => Decimal.new("0.25")
               })

      assert {:ok, layer} =
               Flows.create_sequence_visual_layer(sequence.id, %{
                 "asset_id" => image.id,
                 "kind" => "overlay",
                 "label" => "Fresh layer"
               })

      snapshot = FlowBuilder.build_snapshot(stale_flow)
      node_ids = MapSet.new(snapshot["nodes"], & &1["original_id"])
      connection_ids = MapSet.new(snapshot["connections"], & &1["original_id"])
      sequence_snapshot = Enum.find(snapshot["nodes"], &(&1["original_id"] == sequence.id))

      assert snapshot["name"] == "Fresh database root"
      assert MapSet.member?(node_ids, current.id)
      refute MapSet.member?(node_ids, obsolete.id)
      assert MapSet.member?(connection_ids, current_connection.id)
      refute MapSet.member?(connection_ids, obsolete_connection.id)
      assert [%{"original_id" => track_id}] = sequence_snapshot["sequence_tracks"]
      assert [%{"original_id" => layer_id}] = sequence_snapshot["sequence_visual_layers"]
      assert track_id == track.id
      assert layer_id == layer.id
    end

    test "fails closed when a connection endpoint belongs to another flow", %{
      project: project,
      flow: flow
    } do
      source = node_fixture(flow, %{type: "hub"})
      other_flow = flow_fixture(project)
      foreign_target = node_fixture(other_flow, %{type: "hub"})

      assert {:ok, _corrupt_connection} =
               %ProjectFlowConnection{flow_id: flow.id}
               |> ProjectFlowConnection.create_changeset(%{
                 source_node_id: source.id,
                 target_node_id: foreign_target.id,
                 source_pin: "output",
                 target_pin: "input"
               })
               |> Repo.insert()

      assert_raise ArgumentError, ~r/endpoint outside flow/, fn ->
        FlowBuilder.build_snapshot(flow)
      end
    end

    test "fails closed when the persisted graph has no exit or more than one entry", %{
      project: project,
      flow: flow
    } do
      Repo.delete_all(
        from(node in FlowNode,
          where: node.flow_id == ^flow.id and node.type == "exit"
        )
      )

      assert_raise ArgumentError, ~r/invalid_snapshot_exit_count/, fn ->
        FlowBuilder.build_snapshot(flow)
      end

      duplicate_entry_flow = flow_fixture(project)

      %FlowNode{flow_id: duplicate_entry_flow.id}
      |> FlowNode.create_changeset(%{
        type: "entry",
        position_x: 700.0,
        position_y: 300.0,
        data: %{},
        source: "manual"
      })
      |> Repo.insert!()

      assert_raise ArgumentError, ~r/invalid_snapshot_entry_count/, fn ->
        FlowBuilder.build_snapshot(duplicate_entry_flow)
      end
    end

    test "fails closed on cross-flow parents and parent cycles", %{
      project: project,
      flow: flow
    } do
      other_flow = flow_fixture(project)

      {:ok, foreign_sequence} =
        Flows.create_sequence(other_flow.id, %{
          "name" => "Foreign sequence",
          "width" => 400.0,
          "height" => 240.0
        })

      child = node_fixture(flow, %{type: "hub"})

      Repo.update_all(
        from(node in FlowNode, where: node.id == ^child.id),
        set: [parent_id: foreign_sequence.id]
      )

      assert_raise ArgumentError, ~r/invalid_snapshot_node_parent/, fn ->
        FlowBuilder.build_snapshot(flow)
      end

      Repo.update_all(
        from(node in FlowNode, where: node.id == ^child.id),
        set: [parent_id: nil]
      )

      {:ok, first_sequence} =
        Flows.create_sequence(flow.id, %{
          "name" => "First sequence",
          "width" => 400.0,
          "height" => 240.0
        })

      {:ok, second_sequence} =
        Flows.create_sequence(flow.id, %{
          "name" => "Second sequence",
          "width" => 400.0,
          "height" => 240.0
        })

      Repo.update_all(
        from(node in FlowNode, where: node.id == ^first_sequence.id),
        set: [parent_id: second_sequence.id]
      )

      Repo.update_all(
        from(node in FlowNode, where: node.id == ^second_sequence.id),
        set: [parent_id: first_sequence.id]
      )

      assert_raise ArgumentError, ~r/snapshot_node_parent_cycle/, fn ->
        FlowBuilder.build_snapshot(flow)
      end
    end

    test "fails closed when a persisted sequence has lost its mandatory config", %{
      flow: flow
    } do
      {:ok, sequence} =
        Flows.create_sequence(flow.id, %{
          "name" => "Validated sequence",
          "width" => 400.0,
          "height" => 240.0
        })

      Repo.delete_all(from(config in SequenceConfig, where: config.flow_node_id == ^sequence.id))

      assert_raise ArgumentError, ~r/invalid_sequence_config_snapshot/, fn ->
        FlowBuilder.build_snapshot(flow)
      end
    end

    test "fails closed on cross-project or trashed external roots", %{
      user: user,
      project: project,
      flow: flow
    } do
      other_project = project_fixture(user)
      foreign_scene = scene_fixture(other_project)
      foreign_sheet = sheet_fixture(other_project)
      foreign_flow = flow_fixture(other_project)

      Repo.update_all(
        from(persisted_flow in Flow, where: persisted_flow.id == ^flow.id),
        set: [scene_id: foreign_scene.id]
      )

      assert_raise ArgumentError, ~r/flow_external_reference_not_materializable/, fn ->
        FlowBuilder.build_snapshot(flow)
      end

      Repo.update_all(
        from(persisted_flow in Flow, where: persisted_flow.id == ^flow.id),
        set: [scene_id: nil]
      )

      dialogue = node_fixture(flow, %{type: "dialogue", data: %{"text" => "Line", "responses" => []}})

      Repo.update_all(
        from(node in FlowNode, where: node.id == ^dialogue.id),
        set: [data: Map.put(dialogue.data, "speaker_sheet_id", foreign_sheet.id)]
      )

      assert_raise ArgumentError, ~r/flow_external_reference_not_materializable/, fn ->
        FlowBuilder.build_snapshot(flow)
      end

      subflow = node_fixture(flow, %{type: "subflow"})

      Repo.update_all(
        from(node in FlowNode, where: node.id == ^dialogue.id),
        set: [data: Map.delete(dialogue.data, "speaker_sheet_id")]
      )

      Repo.update_all(
        from(node in FlowNode, where: node.id == ^subflow.id),
        set: [data: %{"referenced_flow_id" => foreign_flow.id}]
      )

      assert_raise ArgumentError, ~r/flow_external_reference_not_materializable/, fn ->
        FlowBuilder.build_snapshot(flow)
      end

      local_scene = scene_fixture(project)
      deleted_at = DateTime.truncate(DateTime.utc_now(), :second)

      Repo.update_all(
        from(scene in Scene, where: scene.id == ^local_scene.id),
        set: [deleted_at: deleted_at]
      )

      Repo.update_all(
        from(node in FlowNode, where: node.id == ^subflow.id),
        set: [data: %{"referenced_flow_id" => nil}]
      )

      Repo.update_all(
        from(persisted_flow in Flow, where: persisted_flow.id == ^flow.id),
        set: [scene_id: local_scene.id]
      )

      assert_raise ArgumentError, ~r/flow_external_reference_not_materializable/, fn ->
        FlowBuilder.build_snapshot(flow)
      end
    end

    test "canonicalizes repeated missing optional avatars to nil in the snapshot without mutating nodes", %{
      user: user,
      project: project,
      flow: flow
    } do
      speaker = sheet_fixture(project, %{name: "Speaker"})

      avatar_asset =
        uploaded_asset(
          project,
          user,
          "missing-snapshot-avatar.png",
          "missing snapshot avatar",
          "image/png"
        )

      {:ok, avatar} = Storyarn.Sheets.add_avatar(speaker, avatar_asset.id)

      dialogues =
        Enum.map(["First dangling avatar", "Second dangling avatar"], fn text ->
          node_fixture(flow, %{
            type: "dialogue",
            data: %{
              "speaker_sheet_id" => nil,
              "avatar_id" => avatar.id,
              "text" => text
            }
          })
        end)

      Repo.delete_all(from(persisted_avatar in SheetAvatar, where: persisted_avatar.id == ^avatar.id))

      snapshot = FlowBuilder.build_snapshot(flow)
      dialogue_ids = MapSet.new(dialogues, & &1.id)
      snapshot_dialogues = Enum.filter(snapshot["nodes"], &MapSet.member?(dialogue_ids, &1["original_id"]))

      assert length(snapshot_dialogues) == 2
      assert Enum.all?(snapshot_dialogues, &is_nil(&1["data"]["speaker_sheet_id"]))
      assert Enum.all?(snapshot_dialogues, &is_nil(&1["data"]["avatar_id"]))
      assert Enum.all?(dialogues, &(Repo.get!(FlowNode, &1.id).data["avatar_id"] == avatar.id))
    end

    test "continues to fail closed for a cross-project avatar without mutating the node", %{
      user: user,
      flow: flow
    } do
      other_project = project_fixture(user)
      other_speaker = sheet_fixture(other_project, %{name: "Foreign speaker"})

      avatar_asset =
        uploaded_asset(
          other_project,
          user,
          "foreign-snapshot-avatar.png",
          "foreign snapshot avatar",
          "image/png"
        )

      {:ok, avatar} = Storyarn.Sheets.add_avatar(other_speaker, avatar_asset.id)

      dialogue =
        node_fixture(flow, %{
          type: "dialogue",
          data: %{"speaker_sheet_id" => nil, "text" => "Foreign avatar"}
        })

      persisted_data = Map.put(dialogue.data, "avatar_id", avatar.id)

      Repo.update_all(
        from(node in FlowNode, where: node.id == ^dialogue.id),
        set: [data: persisted_data]
      )

      assert_raise ArgumentError, ~r/flow_external_reference_not_materializable/, fn ->
        FlowBuilder.build_snapshot(flow)
      end

      assert Repo.get!(FlowNode, dialogue.id).data["avatar_id"] == avatar.id
    end

    test "continues to fail closed for a malformed avatar without mutating the node", %{flow: flow} do
      dialogue =
        node_fixture(flow, %{
          type: "dialogue",
          data: %{"speaker_sheet_id" => nil, "text" => "Malformed avatar"}
        })

      persisted_data = Map.put(dialogue.data, "avatar_id", "not-an-avatar-id")

      Repo.update_all(
        from(node in FlowNode, where: node.id == ^dialogue.id),
        set: [data: persisted_data]
      )

      assert_raise ArgumentError, ~r/flow_external_reference_not_materializable/, fn ->
        FlowBuilder.build_snapshot(flow)
      end

      assert Repo.get!(FlowNode, dialogue.id).data["avatar_id"] == "not-an-avatar-id"
    end

    test "continues to fail closed for an avatar speaker mismatch without mutating the node", %{
      user: user,
      project: project,
      flow: flow
    } do
      first_speaker = sheet_fixture(project, %{name: "First speaker"})
      second_speaker = sheet_fixture(project, %{name: "Second speaker"})

      avatar_asset =
        uploaded_asset(
          project,
          user,
          "invalid-speaker-avatar.png",
          "invalid speaker avatar",
          "image/png"
        )

      {:ok, avatar} = Storyarn.Sheets.add_avatar(first_speaker, avatar_asset.id)

      dialogue =
        node_fixture(flow, %{
          type: "dialogue",
          data: %{
            "speaker_sheet_id" => first_speaker.id,
            "avatar_id" => avatar.id,
            "text" => "Corrupted speaker"
          }
        })

      Repo.update_all(
        from(node in FlowNode, where: node.id == ^dialogue.id),
        set: [
          data:
            dialogue.data
            |> Map.put("speaker_sheet_id", second_speaker.id)
            |> Map.put("avatar_id", avatar.id)
        ]
      )

      assert_raise ArgumentError, ~r/flow_external_reference_not_materializable/, fn ->
        FlowBuilder.build_snapshot(flow)
      end

      persisted_dialogue = Repo.get!(FlowNode, dialogue.id)
      assert persisted_dialogue.data["speaker_sheet_id"] == second_speaker.id
      assert persisted_dialogue.data["avatar_id"] == avatar.id
    end

    test "validates terminal exit scene and flow targets against the owning project", %{
      user: user,
      project: project,
      flow: flow
    } do
      exit_node = active_exit_node(flow.id)
      local_scene = scene_fixture(project)
      local_flow = flow_fixture(project)

      set_node_data(exit_node, %{
        "exit_mode" => "terminal",
        "target_type" => "scene",
        "target_id" => local_scene.id
      })

      snapshot = FlowBuilder.build_snapshot(flow)
      snapshot_exit = Enum.find(snapshot["nodes"], &(&1["original_id"] == exit_node.id))
      assert snapshot_exit["data"]["target_id"] == local_scene.id

      set_node_data(exit_node, %{
        "exit_mode" => "terminal",
        "target_type" => "flow",
        "target_id" => local_flow.id
      })

      assert FlowBuilder.build_snapshot(flow)

      other_project = project_fixture(user)
      foreign_scene = scene_fixture(other_project)

      set_node_data(exit_node, %{
        "exit_mode" => "terminal",
        "target_type" => "scene",
        "target_id" => foreign_scene.id
      })

      assert_raise ArgumentError, ~r/flow_external_reference_not_materializable/, fn ->
        FlowBuilder.build_snapshot(flow)
      end

      set_node_data(exit_node, %{
        "exit_mode" => "terminal",
        "target_type" => "flow",
        "target_id" => nil
      })

      assert_raise ArgumentError, ~r/invalid_flow_exit_target/, fn ->
        FlowBuilder.build_snapshot(flow)
      end
    end

    test "validates every persisted dynamic subflow pin against an active exit in its referenced flow", %{
      project: project,
      flow: flow
    } do
      referenced_flow = flow_fixture(project)
      referenced_exit = node_fixture(referenced_flow, %{type: "exit"})
      other_flow = flow_fixture(project)
      other_exit = active_exit_node(other_flow.id)

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

      Repo.update_all(
        from(current in ProjectFlowConnection, where: current.id == ^connection.id),
        set: [source_pin: "exit_#{other_exit.id}"]
      )

      assert_raise ArgumentError, ~r/exit_not_in_referenced_flow/, fn ->
        FlowBuilder.build_snapshot(flow)
      end

      assert {:ok, _connection} =
               Flows.update_connection(connection, %{
                 source_pin: "exit_#{referenced_exit.id}"
               })

      assert FlowBuilder.build_snapshot(flow)
      assert {:ok, _deleted_exit, _meta} = Flows.delete_node(referenced_exit)

      assert_raise ArgumentError, ~r/exit_in_trash/, fn ->
        FlowBuilder.build_snapshot(flow)
      end
    end

    test "rejects snapshots for flow or project roots in trash", %{
      user: user,
      flow: flow
    } do
      deleted_at = DateTime.truncate(DateTime.utc_now(), :second)

      Repo.update_all(
        from(root in Flow, where: root.id == ^flow.id),
        set: [deleted_at: deleted_at]
      )

      assert_raise ArgumentError, ~r/flow .* while it is in trash/, fn ->
        FlowBuilder.build_snapshot(flow)
      end

      trashed_project = project_fixture(user)
      project_flow = flow_fixture(trashed_project)

      Repo.update_all(
        from(project in Project,
          where: project.id == ^trashed_project.id
        ),
        set: [deleted_at: deleted_at]
      )

      assert_raise ArgumentError, ~r/project .* is in trash/, fn ->
        FlowBuilder.build_snapshot(project_flow)
      end
    end

    test "fails closed when a subflow reaches a circular exit reference", %{
      project: project,
      flow: flow
    } do
      referenced_flow = flow_fixture(project)

      _subflow =
        node_fixture(flow, %{
          type: "subflow",
          data: %{"referenced_flow_id" => referenced_flow.id}
        })

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

      assert_raise ArgumentError, ~r/circular_flow_reference/, fn ->
        FlowBuilder.build_snapshot(flow)
      end
    end
  end

  describe "validate_materialized_reference_cycles/1" do
    test "validates the final persisted graph after cross-flow IDs are remapped", %{
      project: project,
      flow: flow
    } do
      referenced_flow = flow_fixture(project)

      _outbound =
        node_fixture(flow, %{
          type: "subflow",
          data: %{"referenced_flow_id" => referenced_flow.id}
        })

      assert :ok = FlowBuilder.validate_materialized_reference_cycles(flow.id)

      back_reference = node_fixture(referenced_flow, %{type: "subflow"})

      set_node_data(back_reference, %{
        "referenced_flow_id" => flow.id
      })

      assert {:error, {:circular_flow_reference, flow_id, node_id, target_flow_id}} =
               FlowBuilder.validate_materialized_reference_cycles(flow.id)

      assert flow_id == flow.id
      assert target_flow_id == referenced_flow.id
      assert is_integer(node_id)
    end
  end

  describe "instantiate_snapshot/3" do
    test "exact capture and materialization preserve dangling speaker and avatar values", %{
      user: user,
      flow: flow
    } do
      dialogue =
        node_fixture(flow, %{
          type: "dialogue",
          data: %{"text" => "Authored as stored", "responses" => []}
        })

      dangling_speaker_id = 9_000_000_000 + System.unique_integer([:positive])
      dangling_avatar_id = dangling_speaker_id + 1

      raw_data =
        dialogue.data
        |> Map.put("speaker_sheet_id", dangling_speaker_id)
        |> Map.put("avatar_id", dangling_avatar_id)

      Repo.update_all(
        from(node in FlowNode, where: node.id == ^dialogue.id),
        set: [data: raw_data]
      )

      snapshot = FlowBuilder.build_capture_snapshot(flow)
      captured_dialogue = Enum.find(snapshot["nodes"], &(&1["original_id"] == dialogue.id))

      assert captured_dialogue["data"]["speaker_sheet_id"] == dangling_speaker_id
      assert captured_dialogue["data"]["avatar_id"] == dangling_avatar_id

      target_project = project_fixture(user)

      assert {:ok, materialized, id_maps} =
               FlowBuilder.instantiate_snapshot(target_project.id, snapshot,
                 materialization_mode: :exact,
                 reset_shortcut: true,
                 preserve_external_refs: false,
                 restore_localization: false,
                 rebuild_references: false
               )

      restored_dialogue = Enum.find(materialized.nodes, &(&1.id == id_maps.node[dialogue.id]))

      assert restored_dialogue.data["speaker_sheet_id"] == dangling_speaker_id
      assert restored_dialogue.data["avatar_id"] == dangling_avatar_id
    end

    test "exact materialization scopes physical scene and parent fallbacks to the target project", %{
      user: user,
      flow: source_flow
    } do
      child = node_fixture(source_flow, %{type: "hub", position_x: 140.0})
      snapshot = FlowBuilder.build_capture_snapshot(source_flow)
      target_project = project_fixture(user)
      target_scene = scene_fixture(target_project)
      target_flow = flow_fixture(target_project)

      {:ok, archived_parent} =
        Flows.create_sequence(target_flow.id, %{
          "name" => "Archived parent",
          "width" => 320.0,
          "height" => 180.0
        })

      now = DateTime.utc_now(:second)
      Repo.update_all(from(scene in Scene, where: scene.id == ^target_scene.id), set: [deleted_at: now])
      Repo.update_all(from(node in FlowNode, where: node.id == ^archived_parent.id), set: [deleted_at: now])

      exact_snapshot =
        snapshot
        |> Map.put("scene_id", target_scene.id)
        |> update_in(["nodes"], fn nodes ->
          Enum.map(nodes, fn
            %{"original_id" => id} = node when id == child.id -> Map.put(node, "parent_id", archived_parent.id)
            node -> node
          end)
        end)

      assert {:ok, restored, id_maps} =
               FlowBuilder.instantiate_snapshot(target_project.id, exact_snapshot,
                 materialization_mode: :exact,
                 reset_shortcut: true,
                 preserve_external_refs: false,
                 restore_localization: false,
                 rebuild_references: false
               )

      assert restored.scene_id == target_scene.id
      assert Repo.get!(FlowNode, id_maps.node[child.id]).parent_id == archived_parent.id

      foreign_project = project_fixture(user)
      foreign_scene = scene_fixture(foreign_project)
      foreign_flow = flow_fixture(foreign_project)

      {:ok, foreign_parent} =
        Flows.create_sequence(foreign_flow.id, %{
          "name" => "Foreign parent",
          "width" => 320.0,
          "height" => 180.0
        })

      flow_count = Repo.aggregate(from(flow in Flow, where: flow.project_id == ^target_project.id), :count)

      assert {:error, {:exact_snapshot_fk_not_materializable, :flow, :scene_id, foreign_scene_id, _context}} =
               FlowBuilder.instantiate_snapshot(target_project.id, Map.put(snapshot, "scene_id", foreign_scene.id),
                 materialization_mode: :exact,
                 reset_shortcut: true,
                 preserve_external_refs: false,
                 restore_localization: false,
                 rebuild_references: false
               )

      assert foreign_scene_id == foreign_scene.id
      assert Repo.aggregate(from(flow in Flow, where: flow.project_id == ^target_project.id), :count) == flow_count

      foreign_parent_snapshot =
        update_in(snapshot, ["nodes"], fn nodes ->
          Enum.map(nodes, fn
            %{"original_id" => id} = node when id == child.id -> Map.put(node, "parent_id", foreign_parent.id)
            node -> node
          end)
        end)

      assert {:error,
              {:invalid_snapshot_node_parent, child_id, foreign_parent_id,
               {:error, {:exact_snapshot_fk_not_materializable, :flow_node, :parent_id, foreign_parent_id}}}} =
               FlowBuilder.instantiate_snapshot(target_project.id, foreign_parent_snapshot,
                 materialization_mode: :exact,
                 reset_shortcut: true,
                 preserve_external_refs: false,
                 restore_localization: false,
                 rebuild_references: false
               )

      assert child_id == child.id
      assert foreign_parent_id == foreign_parent.id
      assert Repo.aggregate(from(flow in Flow, where: flow.project_id == ^target_project.id), :count) == flow_count
    end

    test "exact materialization remaps captured raw connection endpoints and rejects foreign fallbacks", %{
      user: user,
      flow: source_flow
    } do
      source = node_fixture(source_flow, %{type: "hub", position_x: 120.0})
      target = node_fixture(source_flow, %{type: "hub", position_x: 240.0})
      _connection = connection_fixture(source_flow, source, target)
      snapshot = FlowBuilder.build_capture_snapshot(source_flow)

      raw_snapshot =
        update_in(snapshot, ["connections"], fn [connection] ->
          [
            connection
            |> Map.put("source_node_index", nil)
            |> Map.put("source_node_id", source.id)
          ]
        end)

      target_project = project_fixture(user)

      assert {:ok, materialized, id_maps} =
               FlowBuilder.instantiate_snapshot(target_project.id, raw_snapshot,
                 materialization_mode: :exact,
                 reset_shortcut: true,
                 preserve_external_refs: false,
                 restore_localization: false,
                 rebuild_references: false
               )

      assert [%ProjectFlowConnection{source_node_id: source_node_id}] = materialized.connections
      assert source_node_id == id_maps.node[source.id]

      archived_flow = flow_fixture(target_project)
      archived_node = node_fixture(archived_flow, %{type: "hub"})

      Repo.update_all(
        from(node in FlowNode, where: node.id == ^archived_node.id),
        set: [deleted_at: DateTime.utc_now(:second)]
      )

      archived_snapshot =
        update_in(raw_snapshot, ["connections"], fn [connection] ->
          [Map.put(connection, "source_node_id", archived_node.id)]
        end)

      assert {:ok, archived_materialized, _archived_id_maps} =
               FlowBuilder.instantiate_snapshot(target_project.id, archived_snapshot,
                 materialization_mode: :exact,
                 reset_shortcut: true,
                 preserve_external_refs: false,
                 restore_localization: false,
                 rebuild_references: false
               )

      assert [%ProjectFlowConnection{source_node_id: archived_source_node_id}] = archived_materialized.connections
      assert archived_source_node_id == archived_node.id

      foreign_project = project_fixture(user)
      foreign_flow = flow_fixture(foreign_project)
      foreign_node = node_fixture(foreign_flow, %{type: "hub"})

      foreign_snapshot =
        update_in(raw_snapshot, ["connections"], fn [connection] ->
          [Map.put(connection, "source_node_id", foreign_node.id)]
        end)

      flow_count = Repo.aggregate(from(flow in Flow, where: flow.project_id == ^target_project.id), :count)

      assert {:error,
              {:connection_materialization_failed, _connection_id,
               {:error,
                {:exact_snapshot_fk_not_materializable, :flow_connection, _snapshot_connection_id, :source,
                 foreign_node_id}}}} =
               FlowBuilder.instantiate_snapshot(target_project.id, foreign_snapshot,
                 materialization_mode: :exact,
                 reset_shortcut: true,
                 preserve_external_refs: false,
                 restore_localization: false,
                 rebuild_references: false
               )

      assert foreign_node_id == foreign_node.id
      assert Repo.aggregate(from(flow in Flow, where: flow.project_id == ^target_project.id), :count) == flow_count
    end

    test "exact capture materializes residual sequence rows and a missing sequence config", %{
      user: user,
      project: project,
      flow: flow
    } do
      audio = uploaded_asset(project, user, "residual.mp3", "residual audio", "audio/mpeg")
      image = uploaded_asset(project, user, "residual.png", "residual image", "image/png")

      {:ok, residual_node} =
        Flows.create_sequence(flow.id, %{
          "name" => "Residual sequence",
          "width" => 640.0,
          "height" => 360.0
        })

      assert {:ok, source_track} =
               Flows.upsert_sequence_track(residual_node.id, "music", %{
                 "asset_id" => audio.id,
                 "position" => 0
               })

      assert {:ok, source_layer} =
               Flows.create_sequence_visual_layer(residual_node.id, %{
                 "asset_id" => image.id,
                 "kind" => "backdrop",
                 "label" => "Residual layer"
               })

      Repo.update_all(
        from(node in FlowNode, where: node.id == ^residual_node.id),
        set: [type: "hub"]
      )

      {:ok, configless_sequence} =
        Flows.create_sequence(flow.id, %{
          "name" => "Configless sequence",
          "width" => 320.0,
          "height" => 180.0
        })

      Repo.delete_all(
        from(config in SequenceConfig,
          where: config.flow_node_id == ^configless_sequence.id
        )
      )

      snapshot = FlowBuilder.build_capture_snapshot(flow)
      captured_residual = Enum.find(snapshot["nodes"], &(&1["original_id"] == residual_node.id))
      captured_configless = Enum.find(snapshot["nodes"], &(&1["original_id"] == configless_sequence.id))

      assert captured_residual["type"] == "hub"
      assert captured_residual["sequence_config"]["name"] == "Residual sequence"
      assert [%{"original_id" => captured_track_id}] = captured_residual["sequence_tracks"]
      assert [%{"original_id" => captured_layer_id}] = captured_residual["sequence_visual_layers"]
      assert captured_track_id == source_track.id
      assert captured_layer_id == source_layer.id
      assert captured_configless["sequence_config"] == nil

      target_project = project_fixture(user)

      assert {:ok, materialized, id_maps} =
               FlowBuilder.instantiate_snapshot(target_project.id, snapshot,
                 materialization_mode: :exact,
                 reset_shortcut: true,
                 preserve_external_refs: false,
                 restore_localization: false,
                 rebuild_references: false
               )

      restored_residual = Enum.find(materialized.nodes, &(&1.id == id_maps.node[residual_node.id]))
      restored_configless = Enum.find(materialized.nodes, &(&1.id == id_maps.node[configless_sequence.id]))

      assert restored_residual.type == "hub"
      assert restored_residual.sequence_config.name == "Residual sequence"
      assert [restored_track] = restored_residual.sequence_tracks
      assert [restored_layer] = restored_residual.sequence_visual_layers
      assert restored_track.id == id_maps.sequence_track[source_track.id]
      assert restored_layer.id == id_maps.sequence_visual_layer[source_layer.id]
      assert restored_track.asset_id != audio.id
      assert restored_layer.asset_id != image.id
      assert restored_configless.type == "sequence"
      assert restored_configless.sequence_config == nil

      copied_assets = Enum.map([restored_track.asset_id, restored_layer.asset_id], &Repo.get!(Asset, &1))

      on_exit(fn -> Enum.each(copied_assets, &Assets.storage_delete(&1.key)) end)
    end

    test "rejects missing or duplicate response identities atomically", %{
      user: user,
      flow: flow
    } do
      response_one = "response_snapshot_one"
      response_two = "response_snapshot_two"

      dialogue =
        node_fixture(flow, %{
          type: "dialogue",
          data: %{
            "text" => "Choose",
            "responses" => [
              %{"id" => response_one, "text" => "One"},
              %{"id" => response_two, "text" => "Two"}
            ]
          }
        })

      snapshot = FlowBuilder.build_snapshot(flow)
      target_project = project_fixture(user)

      count_before =
        Repo.aggregate(
          from(candidate in Flow, where: candidate.project_id == ^target_project.id),
          :count
        )

      invalid_snapshots = [
        {
          Map.update!(snapshot, "nodes", fn nodes ->
            Enum.map(nodes, fn
              %{"original_id" => id, "data" => data} = node when id == dialogue.id ->
                responses = List.update_at(data["responses"], 1, &Map.delete(&1, "id"))

                put_in(node, ["data", "responses"], responses)

              node ->
                node
            end)
          end),
          {:invalid_snapshot_dialogue_response_id, dialogue.id, [response_one, nil]}
        },
        {
          Map.update!(snapshot, "nodes", fn nodes ->
            Enum.map(nodes, fn
              %{"original_id" => id, "data" => data} = node when id == dialogue.id ->
                responses = List.update_at(data["responses"], 1, &Map.put(&1, "id", response_one))

                put_in(node, ["data", "responses"], responses)

              node ->
                node
            end)
          end),
          {:duplicate_snapshot_dialogue_response_id, dialogue.id}
        }
      ]

      for {invalid_snapshot, expected_error} <- invalid_snapshots do
        assert {:error, ^expected_error} =
                 FlowBuilder.instantiate_snapshot(
                   target_project.id,
                   invalid_snapshot,
                   reset_shortcut: true
                 )

        assert Repo.aggregate(
                 from(candidate in Flow,
                   where: candidate.project_id == ^target_project.id
                 ),
                 :count
               ) == count_before
      end
    end

    test "rejects malformed node payloads before materializing anything", %{
      user: user,
      flow: flow
    } do
      node = node_fixture(flow, %{type: "dialogue", data: %{"text" => "Line", "responses" => []}})
      snapshot = FlowBuilder.build_snapshot(flow)

      malformed_snapshot =
        Map.update!(snapshot, "nodes", fn nodes ->
          Enum.map(nodes, fn
            %{"original_id" => node_id} = entry when node_id == node.id ->
              Map.put(entry, "data", "not-a-map")

            entry ->
              entry
          end)
        end)

      target_project = project_fixture(user)

      count_before =
        Repo.aggregate(
          from(target_flow in Flow, where: target_flow.project_id == ^target_project.id),
          :count
        )

      assert {:error, {:invalid_snapshot_field, :node, "data", "not-a-map"}} =
               FlowBuilder.instantiate_snapshot(
                 target_project.id,
                 malformed_snapshot,
                 reset_shortcut: true
               )

      assert Repo.aggregate(
               from(target_flow in Flow,
                 where: target_flow.project_id == ^target_project.id
               ),
               :count
             ) == count_before
    end

    test "rejects a missing destination project before materializing anything", %{
      flow: flow
    } do
      snapshot = FlowBuilder.build_snapshot(flow)
      maximum_project_id = Repo.aggregate(Project, :max, :id) || 0
      missing_project_id = maximum_project_id + 1_000_000

      assert {:error, {:project_not_found, ^missing_project_id}} =
               FlowBuilder.instantiate_snapshot(missing_project_id, snapshot, reset_shortcut: true)

      refute Repo.exists?(
               from(materialized_flow in Flow,
                 where: materialized_flow.project_id == ^missing_project_id
               )
             )
    end

    test "rejects a destination project in trash before materializing anything", %{
      user: user,
      flow: flow
    } do
      snapshot = FlowBuilder.build_snapshot(flow)
      target_project = project_fixture(user)
      deleted_at = DateTime.truncate(DateTime.utc_now(), :second)

      Repo.update_all(
        from(project in Project,
          where: project.id == ^target_project.id
        ),
        set: [deleted_at: deleted_at]
      )

      assert {:error, {:project_deleted, project_id}} =
               FlowBuilder.instantiate_snapshot(
                 target_project.id,
                 snapshot,
                 reset_shortcut: true
               )

      assert project_id == target_project.id

      refute Repo.exists?(
               from(materialized_flow in Flow,
                 where: materialized_flow.project_id == ^target_project.id
               )
             )
    end

    test "can explicitly defer localization to the project recovery phase", %{
      user: user,
      project: project,
      flow: flow
    } do
      _en = source_language_fixture(project, %{locale_code: "en", name: "English"})
      _es = language_fixture(project, %{locale_code: "es", name: "Spanish"})

      _node =
        node_fixture(flow, %{
          type: "dialogue",
          data: %{"text" => "Deferred localized line", "responses" => []}
        })

      snapshot = FlowBuilder.build_snapshot(flow)
      assert [_row] = snapshot["localization"]

      target_project = project_fixture(user)
      _target_en = source_language_fixture(target_project, %{locale_code: "en", name: "English"})
      _target_es = language_fixture(target_project, %{locale_code: "es", name: "Spanish"})

      assert {:ok, materialized, _id_maps} =
               FlowBuilder.instantiate_snapshot(target_project.id, snapshot,
                 reset_shortcut: true,
                 restore_localization: false
               )

      [materialized_node] = Enum.filter(materialized.nodes, &(&1.type == "dialogue"))
      assert Localization.get_texts_for_source("flow_node", materialized_node.id) == []
    end

    test "copies and remaps voice assets while instantiating localization", %{
      user: user,
      project: project,
      flow: flow
    } do
      _source_en = source_language_fixture(project, %{locale_code: "en", name: "English"})
      _source_es = language_fixture(project, %{locale_code: "es", name: "Spanish"})
      voice = uploaded_asset(project, user, "instantiate-voice.mp3", "voice", "audio/mpeg")

      dialogue =
        node_fixture(flow, %{
          type: "dialogue",
          data: %{
            "text" => "Line with a missing voice asset",
            "responses" => []
          }
        })

      [text] = Localization.get_texts_for_source("flow_node", dialogue.id)

      assert {:ok, _text} =
               Localization.update_text(text, %{
                 translated_text: "Línea con voz",
                 status: "final",
                 vo_asset_id: voice.id,
                 vo_status: "recorded"
               })

      snapshot = FlowBuilder.build_snapshot(flow)
      assert [%{"vo_asset_id" => voice_id}] = snapshot["localization"]
      assert voice_id == voice.id
      assert snapshot["asset_blob_hashes"][to_string(voice.id)] == voice.blob_hash

      target_project = project_fixture(user)
      _target_en = source_language_fixture(target_project, %{locale_code: "en", name: "English"})
      _target_es = language_fixture(target_project, %{locale_code: "es", name: "Spanish"})

      count_before =
        Repo.aggregate(
          from(target_flow in Flow, where: target_flow.project_id == ^target_project.id),
          :count
        )

      assert {:ok, materialized, id_maps} =
               FlowBuilder.instantiate_snapshot(target_project.id, snapshot, reset_shortcut: true)

      assert Repo.aggregate(
               from(target_flow in Flow,
                 where: target_flow.project_id == ^target_project.id
               ),
               :count
             ) == count_before + 1

      assert [%LocalizedText{vo_asset_id: restored_voice_id, vo_status: "recorded"}] =
               Localization.get_texts_for_source(
                 "flow_node",
                 id_maps.node[dialogue.id]
               )

      refute restored_voice_id == voice.id
      restored_voice = Repo.get!(Asset, restored_voice_id)
      assert restored_voice.project_id == target_project.id
      assert restored_voice.blob_hash == voice.blob_hash
      assert {:ok, "voice"} = Assets.storage_download(restored_voice.key)
      on_exit(fn -> Assets.storage_delete(restored_voice.key) end)
      assert materialized.project_id == target_project.id
    end

    test "validates localization integrity before materializing even when recovery defers writes", %{
      user: user,
      project: project,
      flow: flow
    } do
      _en = source_language_fixture(project, %{locale_code: "en", name: "English"})
      _es = language_fixture(project, %{locale_code: "es", name: "Spanish"})

      _node =
        node_fixture(flow, %{
          type: "dialogue",
          data: %{"text" => "Versioned line", "responses" => []}
        })

      snapshot = FlowBuilder.build_snapshot(flow)
      [row] = snapshot["localization"]
      target_project = project_fixture(user)

      flow_count_before =
        Repo.aggregate(
          from(target_flow in Flow, where: target_flow.project_id == ^target_project.id),
          :count
        )

      stale_manifest_snapshot = Map.put(snapshot, "localization", [])

      semantic_corruption_rows = [Map.put(row, "source_text", "Forged source")]

      semantic_corruption_snapshot =
        snapshot
        |> Map.put("localization", semantic_corruption_rows)
        |> Map.put(
          "localization_manifest",
          LocalizationSnapshotCodec.manifest(
            semantic_corruption_rows,
            snapshot["localization_manifest"]["target_locales"]
          )
        )

      for invalid_snapshot <- [stale_manifest_snapshot, semantic_corruption_snapshot] do
        assert {:error, _reason} =
                 FlowBuilder.instantiate_snapshot(target_project.id, invalid_snapshot,
                   reset_shortcut: true,
                   restore_localization: false
                 )

        assert Repo.aggregate(
                 from(target_flow in Flow, where: target_flow.project_id == ^target_project.id),
                 :count
               ) == flow_count_before
      end
    end

    test "materializes a new flow, preserves runtime identities and remaps connection node ids",
         %{user: user, flow: flow} do
      node_a =
        node_fixture(flow, %{
          type: "dialogue",
          position_x: 100.0,
          position_y: 100.0,
          data: %{"text" => "One two three", "responses" => []}
        })

      node_b = node_fixture(flow, %{type: "hub", position_x: 200.0, position_y: 100.0})
      connection = connection_fixture(flow, node_a, node_b)

      snapshot = FlowBuilder.build_snapshot(flow)
      target_project = project_fixture(user)

      assert {:ok, materialized, id_maps} =
               FlowBuilder.instantiate_snapshot(target_project.id, snapshot,
                 reset_shortcut: true,
                 position: 11
               )

      assert materialized.id != flow.id
      assert materialized.position == 11
      assert materialized.shortcut == nil
      assert id_maps.flow == %{flow.id => materialized.id}
      assert id_maps.node[node_a.id]
      assert id_maps.node[node_b.id]
      assert id_maps.connection[connection.id]

      node_ids = Enum.map(materialized.nodes, & &1.id)
      cloned_connection = hd(materialized.connections)

      assert cloned_connection.source_node_id in node_ids
      assert cloned_connection.target_node_id in node_ids
      assert cloned_connection.source_node_id != node_a.id
      assert cloned_connection.target_node_id != node_b.id

      cloned_dialogue = Enum.find(materialized.nodes, &(&1.type == "dialogue"))
      assert cloned_dialogue.data["localization_id"] == node_a.data["localization_id"]
      assert cloned_dialogue.word_count == 3
    end

    test "preserves snapshot main only when the destination has no current main", %{
      user: user,
      flow: flow
    } do
      assert {:ok, source_main} = Flows.set_main_flow(flow)
      snapshot = FlowBuilder.build_snapshot(source_main)

      occupied_project = project_fixture(user)
      existing_flow = flow_fixture(occupied_project)
      assert {:ok, existing_main} = Flows.set_main_flow(existing_flow)

      assert {:ok, occupied_clone, _id_maps} =
               FlowBuilder.instantiate_snapshot(occupied_project.id, snapshot, reset_shortcut: true)

      refute occupied_clone.is_main
      assert Repo.get!(Flow, existing_main.id).is_main

      empty_project = project_fixture(user)

      assert {:ok, first_clone, _id_maps} =
               FlowBuilder.instantiate_snapshot(empty_project.id, snapshot, reset_shortcut: true)

      assert first_clone.is_main
    end

    test "retries a main conflict before materializing instantiated assets", %{
      user: user,
      project: project,
      flow: flow
    } do
      audio =
        uploaded_asset(
          project,
          user,
          "instantiate-main-retry.mp3",
          "instantiate retry audio",
          "audio/mpeg"
        )

      _dialogue =
        node_fixture(flow, %{
          type: "dialogue",
          data: %{
            "text" => "Retry instantiate",
            "responses" => [],
            "audio_asset_id" => audio.id
          }
        })

      assert {:ok, source_main} = Flows.set_main_flow(flow)
      snapshot = FlowBuilder.build_snapshot(source_main)
      target_project = project_fixture(user)
      competing_flow = flow_fixture(target_project)
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

      assert {:ok, materialized, _id_maps} =
               FlowBuilder.instantiate_snapshot(target_project.id, snapshot,
                 asset_mode: :copy,
                 reset_shortcut: true,
                 __before_main_write_hook: hook
               )

      assert Process.get(attempt_key) == 2
      refute materialized.is_main
      refute Repo.get!(Flow, competing_flow.id).is_main

      cloned_dialogue =
        Enum.find(
          materialized.nodes,
          &(&1.data || %{})["audio_asset_id"]
        )

      cloned_audio_id = cloned_dialogue.data["audio_asset_id"]
      cloned_audio = Repo.get!(Asset, cloned_audio_id)

      assert cloned_audio.project_id == target_project.id
      assert cloned_audio.blob_hash == audio.blob_hash
      assert {:ok, "instantiate retry audio"} = Assets.storage_download(cloned_audio.key)

      assert 1 ==
               Repo.aggregate(
                 from(asset in Asset,
                   where:
                     asset.project_id == ^target_project.id and
                       asset.blob_hash == ^audio.blob_hash
                 ),
                 :count
               )

      on_exit(fn -> Assets.storage_delete(cloned_audio.key) end)
    end

    test "rejects a dialogue snapshot without a runtime identity before materializing", %{
      project: project,
      flow: flow
    } do
      snapshot = FlowBuilder.build_snapshot(flow)

      invalid_dialogue = %{
        "original_id" => 99_999,
        "type" => "dialogue",
        "position_x" => 10.0,
        "position_y" => 20.0,
        "data" => %{"text" => "No identity", "responses" => []},
        "parent_id" => nil
      }

      snapshot = Map.put(snapshot, "nodes", [invalid_dialogue | snapshot["nodes"]])
      flow_count = Repo.aggregate(from(candidate in Flow, where: candidate.project_id == ^project.id), :count)

      assert {:error, {:invalid_snapshot_dialogue_localization_id, 99_999, nil}} =
               FlowBuilder.instantiate_snapshot(project.id, snapshot, reset_shortcut: true)

      assert Repo.aggregate(from(candidate in Flow, where: candidate.project_id == ^project.id), :count) ==
               flow_count
    end

    test "rejects malformed response identities instead of normalizing pins", %{
      project: project,
      flow: flow
    } do
      snapshot = FlowBuilder.build_snapshot(flow)

      malformed_nodes =
        [
          %{
            "original_id" => 99_998,
            "type" => "dialogue",
            "position_x" => 10.0,
            "position_y" => 20.0,
            "data" => %{
              "localization_id" => "invalid.dialogue",
              "text" => "Choose",
              "responses" => [%{"id" => "invalid.choice", "text" => "Continue"}]
            },
            "parent_id" => nil
          },
          %{
            "original_id" => 99_999,
            "type" => "hub",
            "position_x" => 30.0,
            "position_y" => 40.0,
            "data" => %{},
            "parent_id" => nil
          }
        ] ++ Enum.filter(snapshot["nodes"], &(&1["type"] in ~w(entry exit)))

      malformed_connection = %{
        "original_id" => 88_888,
        "source_node_index" => 0,
        "target_node_index" => 1,
        "source_pin" => "invalid.choice",
        "target_pin" => "input",
        "label" => nil
      }

      snapshot = Map.merge(snapshot, %{"nodes" => malformed_nodes, "connections" => [malformed_connection]})
      flow_count = Repo.aggregate(from(candidate in Flow, where: candidate.project_id == ^project.id), :count)

      assert {:error, {:invalid_snapshot_dialogue_localization_id, 99_998, "invalid.dialogue"}} =
               FlowBuilder.instantiate_snapshot(project.id, snapshot, reset_shortcut: true)

      assert Repo.aggregate(from(candidate in Flow, where: candidate.project_id == ^project.id), :count) ==
               flow_count
    end

    test "remaps external scene refs with explicit id maps", %{
      user: user,
      project: project,
      flow: flow
    } do
      source_scene = scene_fixture(project)
      {:ok, flow} = Flows.update_flow(flow, %{scene_id: source_scene.id})
      snapshot = FlowBuilder.build_snapshot(flow)

      target_project = project_fixture(user)
      target_scene = scene_fixture(target_project)

      assert {:ok, materialized, _id_maps} =
               FlowBuilder.instantiate_snapshot(target_project.id, snapshot,
                 external_id_maps: %{scene: %{source_scene.id => target_scene.id}}
               )

      assert materialized.scene_id == target_scene.id
    end

    test "remaps terminal exit targets as typed project references and clears unmapped pairs", %{
      user: user,
      project: project,
      flow: flow
    } do
      source_scene = scene_fixture(project)
      source_target_flow = flow_fixture(project)
      scene_exit = active_exit_node(flow.id)
      flow_exit = node_fixture(flow, %{type: "exit", position_x: 300.0})

      set_node_data(scene_exit, %{
        "exit_mode" => "terminal",
        "target_type" => "scene",
        "target_id" => source_scene.id
      })

      set_node_data(flow_exit, %{
        "exit_mode" => "terminal",
        "target_type" => "flow",
        "target_id" => source_target_flow.id
      })

      snapshot = FlowBuilder.build_snapshot(flow)
      target_project = project_fixture(user)
      target_scene = scene_fixture(target_project)
      target_flow = flow_fixture(target_project)

      assert {:ok, materialized, id_maps} =
               FlowBuilder.instantiate_snapshot(target_project.id, snapshot,
                 preserve_external_refs: false,
                 external_id_maps: %{
                   scene: %{source_scene.id => target_scene.id},
                   flow: %{source_target_flow.id => target_flow.id}
                 }
               )

      materialized_by_id = Map.new(materialized.nodes, &{&1.id, &1})
      materialized_scene_exit = materialized_by_id[id_maps.node[scene_exit.id]]
      materialized_flow_exit = materialized_by_id[id_maps.node[flow_exit.id]]

      assert materialized_scene_exit.data["target_type"] == "scene"
      assert materialized_scene_exit.data["target_id"] == target_scene.id
      assert materialized_flow_exit.data["target_type"] == "flow"
      assert materialized_flow_exit.data["target_id"] == target_flow.id

      unmapped_project = project_fixture(user)

      assert {:ok, unmapped, unmapped_id_maps} =
               FlowBuilder.instantiate_snapshot(unmapped_project.id, snapshot, preserve_external_refs: false)

      unmapped_by_id = Map.new(unmapped.nodes, &{&1.id, &1})

      for old_exit_id <- [scene_exit.id, flow_exit.id] do
        unmapped_exit = unmapped_by_id[unmapped_id_maps.node[old_exit_id]]
        assert unmapped_exit.data["target_type"] == nil
        assert unmapped_exit.data["target_id"] == nil
      end
    end

    test "rebuilds only active same-project rich-text mentions when instantiating", %{
      user: user,
      project: project,
      flow: flow
    } do
      local_sheet = sheet_fixture(project, %{name: "Local mention"})
      other_project = project_fixture(user)
      foreign_sheet = sheet_fixture(other_project, %{name: "Foreign mention"})

      text =
        ~s(<p><span class="mention" data-type="sheet" data-id="#{local_sheet.id}">Local</span><span class="mention" data-type="sheet" data-id="#{foreign_sheet.id}">Foreign</span></p>)

      dialogue =
        node_fixture(flow, %{
          type: "annotation",
          data: %{
            "text" => ~s(<p><span class="mention" data-type="sheet" data-id="#{local_sheet.id}">Local</span></p>)
          }
        })

      set_node_data(dialogue, %{"text" => text})

      snapshot = FlowBuilder.build_snapshot(flow)

      assert {:ok, materialized, id_maps} =
               FlowBuilder.instantiate_snapshot(project.id, snapshot, reset_shortcut: true)

      cloned_dialogue =
        Enum.find(materialized.nodes, &(&1.id == id_maps.node[dialogue.id]))

      assert cloned_dialogue.data["text"] == text

      assert Repo.exists?(
               from(reference in EntityReference,
                 where:
                   reference.source_type == "flow_node" and
                     reference.source_id == ^cloned_dialogue.id and
                     reference.target_type == "sheet" and
                     reference.target_id == ^local_sheet.id
               )
             )

      refute Repo.exists?(
               from(reference in EntityReference,
                 where:
                   reference.source_type == "flow_node" and
                     reference.source_id == ^cloned_dialogue.id and
                     reference.target_id == ^foreign_sheet.id
               )
             )
    end

    test "remaps node entity refs before rebuilding entity and variable references", %{
      user: user,
      project: project,
      flow: flow
    } do
      _source_en = source_language_fixture(project, %{locale_code: "en", name: "English"})
      _source_es = language_fixture(project, %{locale_code: "es", name: "Spanish"})

      source_sheet =
        sheet_fixture(project, %{
          name: "Hero",
          shortcut: "actors.hero"
        })

      _source_health =
        block_fixture(source_sheet, %{
          type: "number",
          config: %{"label" => "Health", "placeholder" => "0"}
        })

      referenced_flow = flow_fixture(project)

      dialogue =
        node_fixture(flow, %{
          type: "dialogue",
          data: %{
            "text" => "Mapped speaker",
            "speaker_sheet_id" => source_sheet.id,
            "location_sheet_id" => source_sheet.id,
            "responses" => []
          }
        })

      instruction =
        node_fixture(flow, %{
          type: "instruction",
          data: %{
            "assignments" => [
              %{
                "id" => "mapped_assignment",
                "sheet" => "actors.hero",
                "variable" => "health",
                "operator" => "set",
                "value" => "10",
                "value_type" => "literal"
              }
            ]
          }
        })

      subflow =
        node_fixture(flow, %{
          type: "subflow",
          data: %{"referenced_flow_id" => referenced_flow.id}
        })

      snapshot =
        flow
        |> FlowBuilder.build_snapshot()
        |> update_snapshot_node(dialogue.id, fn node ->
          put_in(node, ["data", "location_sheet_id"], to_string(source_sheet.id))
        end)
        |> update_snapshot_node(subflow.id, fn node ->
          put_in(node, ["data", "referenced_flow_id"], to_string(referenced_flow.id))
        end)

      target_project = project_fixture(user)
      _target_en = source_language_fixture(target_project, %{locale_code: "en", name: "English"})
      _target_es = language_fixture(target_project, %{locale_code: "es", name: "Spanish"})

      target_sheet =
        sheet_fixture(target_project, %{
          name: "Hero",
          shortcut: "actors.hero"
        })

      target_health =
        block_fixture(target_sheet, %{
          type: "number",
          config: %{"label" => "Health", "placeholder" => "0"}
        })

      target_referenced_flow = flow_fixture(target_project)

      assert {:ok, materialized, id_maps} =
               FlowBuilder.instantiate_snapshot(target_project.id, snapshot,
                 reset_shortcut: true,
                 preserve_external_refs: false,
                 external_id_maps: %{
                   sheet: %{source_sheet.id => target_sheet.id},
                   flow: %{referenced_flow.id => target_referenced_flow.id}
                 }
               )

      materialized_by_id = Map.new(materialized.nodes, &{&1.id, &1})
      cloned_dialogue = materialized_by_id[id_maps.node[dialogue.id]]
      cloned_instruction = materialized_by_id[id_maps.node[instruction.id]]
      cloned_subflow = materialized_by_id[id_maps.node[subflow.id]]

      assert cloned_dialogue.data["speaker_sheet_id"] == target_sheet.id
      assert cloned_dialogue.data["location_sheet_id"] == target_sheet.id
      assert cloned_subflow.data["referenced_flow_id"] == target_referenced_flow.id

      assert [%LocalizedText{speaker_sheet_id: speaker_sheet_id}] =
               Localization.get_texts_for_source("flow_node", cloned_dialogue.id)

      assert speaker_sheet_id == target_sheet.id

      assert Repo.aggregate(
               from(reference in EntityReference,
                 where:
                   reference.source_type == "flow_node" and
                     reference.source_id == ^cloned_dialogue.id and
                     reference.target_type == "sheet" and
                     reference.target_id == ^target_sheet.id
               ),
               :count
             ) == 2

      assert Repo.exists?(
               from(reference in VariableReference,
                 where:
                   reference.source_type == "flow_node" and
                     reference.source_id == ^cloned_instruction.id and
                     reference.block_id == ^target_health.id and
                     reference.kind == "write"
               )
             )

      unmapped_project = project_fixture(user)
      _unmapped_en = source_language_fixture(unmapped_project, %{locale_code: "en", name: "English"})
      _unmapped_es = language_fixture(unmapped_project, %{locale_code: "es", name: "Spanish"})

      assert {:ok, unmapped, unmapped_maps} =
               FlowBuilder.instantiate_snapshot(unmapped_project.id, snapshot, reset_shortcut: true)

      unmapped_by_id = Map.new(unmapped.nodes, &{&1.id, &1})
      unmapped_dialogue = unmapped_by_id[unmapped_maps.node[dialogue.id]]
      unmapped_subflow = unmapped_by_id[unmapped_maps.node[subflow.id]]

      assert unmapped_dialogue.data["speaker_sheet_id"] == nil
      assert unmapped_dialogue.data["location_sheet_id"] == nil
      assert unmapped_subflow.data["referenced_flow_id"] == nil

      assert [%LocalizedText{speaker_sheet_id: nil}] =
               Localization.get_texts_for_source("flow_node", unmapped_dialogue.id)

      refute Repo.exists?(
               from(reference in EntityReference,
                 where:
                   reference.source_type == "flow_node" and
                     reference.source_id == ^unmapped_dialogue.id
               )
             )

      wrong_map_project = project_fixture(user_fixture())

      assert {:ok, wrong_map_clone, wrong_map_id_maps} =
               FlowBuilder.instantiate_snapshot(wrong_map_project.id, snapshot,
                 reset_shortcut: true,
                 preserve_external_refs: false,
                 external_id_maps: %{
                   sheet: %{source_sheet.id => target_sheet.id},
                   flow: %{referenced_flow.id => target_referenced_flow.id}
                 }
               )

      wrong_map_by_id = Map.new(wrong_map_clone.nodes, &{&1.id, &1})
      wrong_map_dialogue = wrong_map_by_id[wrong_map_id_maps.node[dialogue.id]]
      wrong_map_subflow = wrong_map_by_id[wrong_map_id_maps.node[subflow.id]]

      assert wrong_map_dialogue.data["speaker_sheet_id"] == nil
      assert wrong_map_dialogue.data["location_sheet_id"] == nil
      assert wrong_map_subflow.data["referenced_flow_id"] == nil
    end

    test "remaps speaker and avatar together and drops an unmapped avatar", %{
      user: user,
      project: project,
      flow: flow
    } do
      source_speaker = sheet_fixture(project, %{name: "Source speaker"})

      source_asset =
        uploaded_asset(
          project,
          user,
          "source-flow-avatar.png",
          "source flow avatar",
          "image/png"
        )

      {:ok, source_avatar} =
        Storyarn.Sheets.add_avatar(source_speaker, source_asset.id)

      dialogue =
        node_fixture(flow, %{
          type: "dialogue",
          data: %{
            "speaker_sheet_id" => source_speaker.id,
            "avatar_id" => source_avatar.id,
            "text" => "Mapped avatar"
          }
        })

      snapshot = FlowBuilder.build_snapshot(flow)
      target_project = project_fixture(user)
      target_speaker = sheet_fixture(target_project, %{name: "Target speaker"})

      target_asset =
        uploaded_asset(
          target_project,
          user,
          "target-flow-avatar.png",
          "target flow avatar",
          "image/png"
        )

      {:ok, target_avatar} =
        Storyarn.Sheets.add_avatar(target_speaker, target_asset.id)

      assert {:ok, materialized, id_maps} =
               FlowBuilder.instantiate_snapshot(
                 target_project.id,
                 snapshot,
                 reset_shortcut: true,
                 preserve_external_refs: false,
                 external_id_maps: %{
                   sheet: %{source_speaker.id => target_speaker.id},
                   avatar: %{source_avatar.id => target_avatar.id}
                 }
               )

      materialized_dialogue =
        Enum.find(
          materialized.nodes,
          &(&1.id == id_maps.node[dialogue.id])
        )

      assert materialized_dialogue.data["speaker_sheet_id"] ==
               target_speaker.id

      assert materialized_dialogue.data["avatar_id"] ==
               target_avatar.id

      refute materialized_dialogue.data["avatar_id"] ==
               source_avatar.id

      no_avatar_project = project_fixture(user)
      no_avatar_speaker = sheet_fixture(no_avatar_project)

      assert {:ok, without_avatar, without_avatar_maps} =
               FlowBuilder.instantiate_snapshot(
                 no_avatar_project.id,
                 snapshot,
                 reset_shortcut: true,
                 preserve_external_refs: false,
                 external_id_maps: %{
                   sheet: %{
                     source_speaker.id => no_avatar_speaker.id
                   }
                 }
               )

      without_avatar_dialogue =
        Enum.find(
          without_avatar.nodes,
          &(&1.id == without_avatar_maps.node[dialogue.id])
        )

      assert without_avatar_dialogue.data["speaker_sheet_id"] ==
               no_avatar_speaker.id

      assert without_avatar_dialogue.data["avatar_id"] == nil
    end

    test "rolls back instantiation when avatar and speaker maps disagree", %{
      user: user,
      project: project,
      flow: flow
    } do
      source_speaker = sheet_fixture(project)

      source_asset =
        uploaded_asset(
          project,
          user,
          "source-invalid-map-avatar.png",
          "source invalid map avatar",
          "image/png"
        )

      {:ok, source_avatar} =
        Storyarn.Sheets.add_avatar(source_speaker, source_asset.id)

      _dialogue =
        node_fixture(flow, %{
          type: "dialogue",
          data: %{
            "speaker_sheet_id" => source_speaker.id,
            "avatar_id" => source_avatar.id,
            "text" => "Invalid map"
          }
        })

      snapshot = FlowBuilder.build_snapshot(flow)
      target_project = project_fixture(user)
      mapped_speaker = sheet_fixture(target_project)
      avatar_owner = sheet_fixture(target_project)

      target_asset =
        uploaded_asset(
          target_project,
          user,
          "wrong-target-avatar.png",
          "wrong target avatar",
          "image/png"
        )

      {:ok, wrong_avatar} =
        Storyarn.Sheets.add_avatar(avatar_owner, target_asset.id)

      count_before =
        Repo.aggregate(
          from(target_flow in Flow,
            where: target_flow.project_id == ^target_project.id
          ),
          :count
        )

      assert {:error, {:avatar_speaker_mismatch, avatar_id, avatar_sheet_id, requested_speaker_id}} =
               FlowBuilder.instantiate_snapshot(
                 target_project.id,
                 snapshot,
                 reset_shortcut: true,
                 preserve_external_refs: false,
                 external_id_maps: %{
                   sheet: %{
                     source_speaker.id => mapped_speaker.id
                   },
                   avatar: %{
                     source_avatar.id => wrong_avatar.id
                   }
                 }
               )

      assert avatar_id == wrong_avatar.id
      assert avatar_sheet_id == avatar_owner.id
      assert requested_speaker_id == mapped_speaker.id

      assert Repo.aggregate(
               from(target_flow in Flow,
                 where: target_flow.project_id == ^target_project.id
               ),
               :count
             ) == count_before
    end

    test "clears cross-project scene refs when no external map is provided", %{
      user: user,
      project: project,
      flow: flow
    } do
      source_scene = scene_fixture(project)
      {:ok, flow} = Flows.update_flow(flow, %{scene_id: source_scene.id})
      snapshot = FlowBuilder.build_snapshot(flow)

      target_project = project_fixture(user)

      assert {:ok, materialized, _id_maps} =
               FlowBuilder.instantiate_snapshot(target_project.id, snapshot)

      assert materialized.scene_id == nil
    end

    test "drops entity refs but preserves assets when preserve_external_refs is false", %{
      user: user,
      project: project,
      flow: flow
    } do
      scene = scene_fixture(project)

      audio_asset =
        uploaded_asset(
          project,
          user,
          "preserved-line.mp3",
          "preserved audio",
          "audio/mpeg"
        )

      {:ok, flow} = Flows.update_flow(flow, %{scene_id: scene.id})

      {:ok, sequence} =
        Flows.create_sequence(flow.id, %{
          "name" => "Asset preservation",
          "width" => 640.0,
          "height" => 360.0
        })

      assert {:ok, _track} =
               Flows.upsert_sequence_track(sequence.id, "music", %{
                 "asset_id" => audio_asset.id
               })

      snapshot = FlowBuilder.build_snapshot(flow)

      assert {:ok, materialized, _id_maps} =
               FlowBuilder.instantiate_snapshot(project.id, snapshot,
                 preserve_external_refs: false,
                 reset_shortcut: true
               )

      assert materialized.scene_id == nil

      cloned_sequence = Enum.find(materialized.nodes, &(&1.type == "sequence"))
      assert Enum.any?(cloned_sequence.sequence_tracks, &(&1.asset_id == audio_asset.id))
    end

    test "drops assets only when asset_mode is explicitly drop", %{
      user: user,
      project: project,
      flow: flow
    } do
      audio_asset =
        uploaded_asset(
          project,
          user,
          "dropped-line.mp3",
          "dropped audio",
          "audio/mpeg"
        )

      {:ok, sequence} =
        Flows.create_sequence(flow.id, %{
          "name" => "Asset drop",
          "width" => 640.0,
          "height" => 360.0
        })

      assert {:ok, _track} =
               Flows.upsert_sequence_track(sequence.id, "music", %{
                 "asset_id" => audio_asset.id
               })

      snapshot = FlowBuilder.build_snapshot(flow)

      assert {:ok, materialized, _id_maps} =
               FlowBuilder.instantiate_snapshot(project.id, snapshot,
                 asset_mode: :drop,
                 reset_shortcut: true
               )

      cloned_sequence = Enum.find(materialized.nodes, &(&1.type == "sequence"))
      assert Enum.all?(cloned_sequence.sequence_tracks, &is_nil(&1.asset_id))
    end

    test "copies audio assets into destination project", %{user: user, project: project, flow: flow} do
      audio_asset = uploaded_asset(project, user, "line.mp3", "audio content", "audio/mpeg")

      _node =
        node_fixture(flow, %{
          type: "dialogue",
          data: %{"speaker" => "Narrator", "text" => "Hello", "audio_asset_id" => audio_asset.id}
        })

      snapshot = FlowBuilder.build_snapshot(flow)
      target_project = project_fixture(user)

      assert {:ok, materialized, _id_maps} =
               FlowBuilder.instantiate_snapshot(target_project.id, snapshot,
                 asset_mode: :copy,
                 user_id: user.id,
                 reset_shortcut: true
               )

      cloned_node = Enum.find(materialized.nodes, &(&1.data || %{})["audio_asset_id"])
      cloned_audio_id = cloned_node.data["audio_asset_id"]
      cloned_audio = Repo.get!(Asset, cloned_audio_id)

      assert cloned_audio.project_id == target_project.id
      refute cloned_audio.id == audio_asset.id
      assert {:ok, _binary} = Assets.storage_download(cloned_audio.key)

      cloned_blob_key =
        BlobStore.blob_key(
          target_project.id,
          cloned_audio.blob_hash,
          BlobStore.ext_from_content_type(cloned_audio.content_type)
        )

      assert {:ok, "audio content"} = Assets.storage_download(cloned_blob_key)

      on_exit(fn ->
        Assets.storage_delete(cloned_audio.key)
        Assets.storage_delete(cloned_blob_key)
      end)
    end

    test "rolls back and compensates copied assets when transactional localization raises", %{
      user: user,
      project: project,
      flow: flow
    } do
      audio = uploaded_asset(project, user, "post-commit.mp3", "post-commit audio", "audio/mpeg")

      _node =
        node_fixture(flow, %{
          type: "dialogue",
          data: %{"speaker" => "Narrator", "text" => "Hello", "audio_asset_id" => audio.id}
        })

      snapshot = FlowBuilder.build_snapshot(flow)
      target_project = project_fixture(user)
      _language = language_fixture(target_project, %{locale_code: "es", name: "Spanish"})
      constraint_name = "localized_texts_post_commit_#{System.unique_integer([:positive])}"
      copied_asset_paths_before = stored_asset_paths(target_project.id, audio.filename)

      copied_blob_key =
        BlobStore.blob_key(
          target_project.id,
          audio.blob_hash,
          BlobStore.ext_from_content_type(audio.content_type)
        )

      on_exit(fn -> Assets.storage_delete(copied_blob_key) end)

      Repo.query!(
        "ALTER TABLE localized_texts ADD CONSTRAINT #{constraint_name} " <>
          "CHECK (project_id <> #{target_project.id})"
      )

      assert_raise Postgrex.Error, ~r/#{constraint_name}/, fn ->
        FlowBuilder.instantiate_snapshot(target_project.id, snapshot,
          asset_mode: :copy,
          user_id: user.id,
          reset_shortcut: true
        )
      end

      refute Repo.exists?(from flow in Flow, where: flow.project_id == ^target_project.id)
      refute Repo.exists?(from asset in Asset, where: asset.project_id == ^target_project.id)
      assert stored_asset_paths(target_project.id, audio.filename) == copied_asset_paths_before
      assert {:ok, "post-commit audio"} = Assets.storage_download(copied_blob_key)
      assert [] = all_enqueued(worker: DeleteStorageObjectsWorker)
    end

    test "immediately cleans unique copied assets and retains the canonical blob after rollback", %{
      user: user,
      project: project,
      flow: flow
    } do
      audio = uploaded_asset(project, user, "copied-before-failure.mp3", "copied audio", "audio/mpeg")
      broken_track_asset = uploaded_asset(project, user, "broken-track.mp3", "broken audio", "audio/mpeg")

      _node =
        node_fixture(flow, %{
          type: "dialogue",
          data: %{"speaker" => "Narrator", "text" => "Hello", "audio_asset_id" => audio.id}
        })

      {:ok, sequence} =
        Flows.create_sequence(flow.id, %{
          "name" => "Broken copy",
          "width" => 720.0,
          "height" => 420.0
        })

      {:ok, _track} =
        Flows.upsert_sequence_track(sequence.id, "music", %{
          "asset_id" => broken_track_asset.id
        })

      snapshot =
        flow
        |> FlowBuilder.build_snapshot()
        |> put_in(["asset_metadata", to_string(broken_track_asset.id)], %{})

      target_project = project_fixture(user)
      copied_asset_paths_before = stored_asset_paths(target_project.id, audio.filename)

      copied_blob_key =
        BlobStore.blob_key(
          target_project.id,
          audio.blob_hash,
          BlobStore.ext_from_content_type(audio.content_type)
        )

      on_exit(fn -> Assets.storage_delete(copied_blob_key) end)

      assert {:error, {:asset_materialization_failed, broken_track_asset_id, :missing_asset_metadata}} =
               FlowBuilder.instantiate_snapshot(target_project.id, snapshot,
                 asset_mode: :copy,
                 user_id: user.id,
                 reset_shortcut: true
               )

      assert broken_track_asset_id == broken_track_asset.id

      refute Repo.exists?(from asset in Asset, where: asset.project_id == ^target_project.id)
      assert stored_asset_paths(target_project.id, audio.filename) == copied_asset_paths_before
      assert {:ok, "copied audio"} = Assets.storage_download(copied_blob_key)
      assert [] = all_enqueued(worker: DeleteStorageObjectsWorker)
    end

    test "rejects an untracked copy inside an existing transaction before writing", %{
      user: user,
      project: project,
      flow: flow
    } do
      snapshot = FlowBuilder.build_snapshot(flow)
      flow_count = Repo.aggregate(Flow, :count)

      assert {:ok, {:error, :asset_copy_tracker_required_in_transaction}} =
               Repo.transaction(fn ->
                 FlowBuilder.instantiate_snapshot(project.id, snapshot,
                   asset_mode: :copy,
                   user_id: user.id,
                   reset_shortcut: true
                 )
               end)

      assert Repo.aggregate(Flow, :count) == flow_count
    end

    test "materializes one destination asset for node, sequence, and voice references", %{
      user: user,
      project: project,
      flow: flow
    } do
      _source_en = source_language_fixture(project, %{locale_code: "en", name: "English"})
      _source_es = language_fixture(project, %{locale_code: "es", name: "Spanish"})

      shared_asset =
        uploaded_asset(
          project,
          user,
          "shared-voice.mp3",
          "shared voice and sequence",
          "audio/mpeg"
        )

      dialogue =
        node_fixture(flow, %{
          type: "dialogue",
          data: %{
            "text" => "Shared line",
            "responses" => [],
            "audio_asset_id" => shared_asset.id
          }
        })

      [localized_text] = Localization.get_texts_for_source("flow_node", dialogue.id)

      assert {:ok, _localized_text} =
               Localization.update_text(localized_text, %{
                 translated_text: "Línea compartida",
                 status: "final",
                 vo_asset_id: shared_asset.id,
                 vo_status: "recorded"
               })

      {:ok, sequence} =
        Flows.create_sequence(flow.id, %{
          "name" => "Shared sequence",
          "width" => 640.0,
          "height" => 360.0
        })

      assert {:ok, _track} =
               Flows.upsert_sequence_track(sequence.id, "sfx", %{
                 "asset_id" => shared_asset.id
               })

      snapshot = FlowBuilder.build_snapshot(flow)
      target_project = project_fixture(user)
      _target_en = source_language_fixture(target_project, %{locale_code: "en", name: "English"})
      _target_es = language_fixture(target_project, %{locale_code: "es", name: "Spanish"})

      assert {:ok, materialized, id_maps} =
               FlowBuilder.instantiate_snapshot(target_project.id, snapshot,
                 asset_mode: :copy,
                 user_id: user.id,
                 reset_shortcut: true
               )

      cloned_dialogue = Enum.find(materialized.nodes, &(&1.id == id_maps.node[dialogue.id]))
      cloned_sequence = Enum.find(materialized.nodes, &(&1.id == id_maps.node[sequence.id]))
      [cloned_track] = cloned_sequence.sequence_tracks

      assert [%LocalizedText{vo_asset_id: cloned_voice_id}] =
               Localization.get_texts_for_source(
                 "flow_node",
                 cloned_dialogue.id
               )

      cloned_audio_id = cloned_dialogue.data["audio_asset_id"]
      assert cloned_audio_id == cloned_track.asset_id
      assert cloned_audio_id == cloned_voice_id

      assert Repo.aggregate(
               from(asset in Asset,
                 where:
                   asset.project_id == ^target_project.id and
                     asset.blob_hash == ^shared_asset.blob_hash
               ),
               :count
             ) == 1

      cloned_asset = Repo.get!(Asset, cloned_audio_id)
      on_exit(fn -> Assets.storage_delete(cloned_asset.key) end)
    end

    test "copies nested sequence resources and remaps their parent and assets", %{
      user: user,
      project: project,
      flow: flow
    } do
      audio = uploaded_asset(project, user, "clone-sequence.mp3", "clone audio", "audio/mpeg")
      image = uploaded_asset(project, user, "clone-sequence.png", "clone image", "image/png")

      {:ok, sequence} =
        Flows.create_sequence(flow.id, %{
          "name" => "Clone me",
          "width" => 720.0,
          "height" => 420.0
        })

      child = node_fixture(flow, %{type: "hub", parent_id: sequence.id, position_x: 250.0})

      {:ok, track} =
        Flows.upsert_sequence_track(sequence.id, "music", %{
          "asset_id" => audio.id,
          "volume" => Decimal.new("0.65")
        })

      {:ok, layer} =
        Flows.create_sequence_visual_layer(sequence.id, %{
          "asset_id" => image.id,
          "kind" => "backdrop",
          "label" => "Cloned stage"
        })

      snapshot = FlowBuilder.build_snapshot(flow)
      target_project = project_fixture(user)

      assert {:ok, materialized, id_maps} =
               FlowBuilder.instantiate_snapshot(target_project.id, snapshot,
                 asset_mode: :copy,
                 user_id: user.id,
                 reset_shortcut: true
               )

      cloned_sequence = Enum.find(materialized.nodes, &(&1.type == "sequence"))
      cloned_child = Enum.find(materialized.nodes, &(&1.type == "hub"))

      assert cloned_sequence.id == id_maps.node[sequence.id]
      assert cloned_child.id == id_maps.node[child.id]
      assert cloned_child.parent_id == cloned_sequence.id

      assert %SequenceConfig{name: "Clone me", width: 720.0, height: 420.0} =
               cloned_sequence.sequence_config

      assert [%SequenceTrack{id: cloned_track_id, asset_id: cloned_audio_id}] =
               cloned_sequence.sequence_tracks

      assert [
               %SequenceVisualLayer{
                 id: cloned_layer_id,
                 asset_id: cloned_image_id,
                 label: "Cloned stage"
               }
             ] =
               cloned_sequence.sequence_visual_layers

      assert id_maps.sequence_track == %{track.id => cloned_track_id}
      assert id_maps.sequence_visual_layer == %{layer.id => cloned_layer_id}

      refute cloned_audio_id == audio.id
      refute cloned_image_id == image.id
      cloned_audio = Repo.get!(Asset, cloned_audio_id)
      cloned_image = Repo.get!(Asset, cloned_image_id)
      assert cloned_audio.project_id == target_project.id
      assert cloned_image.project_id == target_project.id

      cloned_audio_blob_key =
        BlobStore.blob_key(
          target_project.id,
          cloned_audio.blob_hash,
          BlobStore.ext_from_content_type(cloned_audio.content_type)
        )

      cloned_image_blob_key =
        BlobStore.blob_key(
          target_project.id,
          cloned_image.blob_hash,
          BlobStore.ext_from_content_type(cloned_image.content_type)
        )

      assert {:ok, "clone audio"} = Assets.storage_download(cloned_audio_blob_key)
      assert {:ok, "clone image"} = Assets.storage_download(cloned_image_blob_key)

      on_exit(fn ->
        Assets.storage_delete(cloned_audio.key)
        Assets.storage_delete(cloned_image.key)
        Assets.storage_delete(cloned_audio_blob_key)
        Assets.storage_delete(cloned_image_blob_key)
      end)
    end

    test "remaps dynamic exit pins with the referenced flow node map", %{
      user: user,
      project: project,
      flow: flow
    } do
      referenced_flow = flow_fixture(project)

      referenced_exit =
        node_fixture(referenced_flow, %{
          type: "exit",
          position_x: 300.0,
          data: %{"label" => "Referenced branch", "technical_id" => "referenced_branch"}
        })

      subflow_node =
        node_fixture(flow, %{
          type: "subflow",
          position_x: 100.0,
          position_y: 100.0,
          data: %{"referenced_flow_id" => referenced_flow.id}
        })

      next_node = node_fixture(flow, %{type: "dialogue", position_x: 200.0, position_y: 100.0})

      _connection =
        connection_fixture(flow, subflow_node, next_node, %{
          source_pin: "exit_#{referenced_exit.id}",
          target_pin: "input"
        })

      snapshot = FlowBuilder.build_snapshot(flow)
      target_project = project_fixture(user)
      target_referenced_flow = flow_fixture(target_project)

      target_referenced_exit =
        node_fixture(target_referenced_flow, %{
          type: "exit",
          position_x: 300.0,
          data: %{"label" => "Referenced branch", "technical_id" => "referenced_branch"}
        })

      assert {:ok, materialized, _id_maps} =
               FlowBuilder.instantiate_snapshot(target_project.id, snapshot,
                 reset_shortcut: true,
                 preserve_external_refs: false,
                 external_id_maps: %{
                   flow: %{referenced_flow.id => target_referenced_flow.id},
                   node: %{referenced_exit.id => target_referenced_exit.id}
                 }
               )

      [cloned_connection] = materialized.connections
      assert cloned_connection.source_pin == "exit_#{target_referenced_exit.id}"
      assert cloned_connection.target_pin == "input"
    end

    test "rolls back when a remapped referenced flow has no exit node map", %{
      user: user,
      project: project,
      flow: flow
    } do
      referenced_flow = flow_fixture(project)
      referenced_exit = node_fixture(referenced_flow, %{type: "exit", position_x: 300.0})

      subflow_node =
        node_fixture(flow, %{
          type: "subflow",
          data: %{"referenced_flow_id" => referenced_flow.id}
        })

      next_node = node_fixture(flow, %{type: "dialogue", position_x: 200.0})

      connection =
        connection_fixture(flow, subflow_node, next_node, %{
          source_pin: "exit_#{referenced_exit.id}"
        })

      snapshot = FlowBuilder.build_snapshot(flow)
      target_project = project_fixture(user)
      target_referenced_flow = flow_fixture(target_project)

      count_before =
        Repo.aggregate(
          from(target_flow in Flow, where: target_flow.project_id == ^target_project.id),
          :count
        )

      assert {:error, {:dynamic_exit_pin_not_materializable, connection_id, source_pin, :missing_exit_node_mapping}} =
               FlowBuilder.instantiate_snapshot(target_project.id, snapshot,
                 reset_shortcut: true,
                 preserve_external_refs: false,
                 external_id_maps: %{
                   flow: %{referenced_flow.id => target_referenced_flow.id}
                 }
               )

      assert connection_id == connection.id
      assert source_pin == "exit_#{referenced_exit.id}"

      assert Repo.aggregate(
               from(target_flow in Flow, where: target_flow.project_id == ^target_project.id),
               :count
             ) == count_before
    end

    test "exact materialization keeps an authored dynamic pin when no exit map exists", %{
      user: user,
      project: project,
      flow: flow
    } do
      referenced_flow = flow_fixture(project)
      referenced_exit = node_fixture(referenced_flow, %{type: "exit", position_x: 300.0})

      subflow_node =
        node_fixture(flow, %{
          type: "subflow",
          data: %{"referenced_flow_id" => referenced_flow.id}
        })

      next_node = node_fixture(flow, %{type: "dialogue", position_x: 200.0})
      source_pin = "exit_#{referenced_exit.id}"

      _connection =
        connection_fixture(flow, subflow_node, next_node, %{
          source_pin: source_pin
        })

      snapshot = FlowBuilder.build_snapshot(flow)
      target_project = project_fixture(user)
      target_referenced_flow = flow_fixture(target_project)

      assert {:ok, materialized, _id_maps} =
               FlowBuilder.instantiate_snapshot(target_project.id, snapshot,
                 materialization_mode: :exact,
                 reset_shortcut: true,
                 preserve_external_refs: false,
                 restore_localization: false,
                 rebuild_references: false,
                 external_id_maps: %{
                   flow: %{referenced_flow.id => target_referenced_flow.id}
                 }
               )

      assert [%ProjectFlowConnection{source_pin: ^source_pin}] = materialized.connections
    end

    test "keeps exit-shaped pins unchanged for non-subflow source nodes", %{project: project, flow: flow} do
      source = node_fixture(flow, %{type: "hub", position_x: 100.0, position_y: 100.0})
      target = node_fixture(flow, %{type: "hub", position_x: 200.0, position_y: 100.0})
      source_pin = "exit_#{target.id}"

      connection =
        connection_fixture(flow, source, target, %{
          source_pin: "output",
          target_pin: "input"
        })

      Repo.update_all(
        from(current in ProjectFlowConnection, where: current.id == ^connection.id),
        set: [source_pin: source_pin]
      )

      snapshot = FlowBuilder.build_snapshot(flow)

      assert {:ok, materialized, _id_maps} =
               FlowBuilder.instantiate_snapshot(project.id, snapshot, reset_shortcut: true)

      assert [cloned_connection] = materialized.connections
      assert cloned_connection.source_pin == source_pin
    end

    test "rejects sequence snapshots without config", %{project: project, flow: flow} do
      snapshot = FlowBuilder.build_snapshot(flow)

      malformed_sequence = %{
        "original_id" => 99_997,
        "type" => "sequence",
        "position_x" => 10.0,
        "position_y" => 20.0,
        "data" => %{},
        "source" => "manual",
        "parent_id" => nil,
        "sequence_config" => nil,
        "sequence_tracks" => [],
        "sequence_visual_layers" => []
      }

      snapshot = Map.put(snapshot, "nodes", [malformed_sequence | snapshot["nodes"]])
      flow_count_before = Repo.aggregate(Flow, :count)

      assert {:error, {:invalid_sequence_config_snapshot, 99_997, nil}} =
               FlowBuilder.instantiate_snapshot(project.id, snapshot, reset_shortcut: true)

      assert Repo.aggregate(Flow, :count) == flow_count_before
    end

    test "rejects malformed sequence resource items without crashing", %{project: project, flow: flow} do
      snapshot = FlowBuilder.build_snapshot(flow)

      malformed_sequence = %{
        "original_id" => 99_996,
        "type" => "sequence",
        "position_x" => 10.0,
        "position_y" => 20.0,
        "data" => %{},
        "source" => "manual",
        "parent_id" => nil,
        "sequence_config" => %{"name" => "Malformed", "width" => 300.0, "height" => 200.0},
        "sequence_tracks" => ["not-a-track"],
        "sequence_visual_layers" => []
      }

      snapshot = Map.put(snapshot, "nodes", [malformed_sequence | snapshot["nodes"]])

      assert {:error, {:invalid_snapshot_original_id, :sequence_track, "not-a-track"}} =
               FlowBuilder.instantiate_snapshot(project.id, snapshot, reset_shortcut: true)
    end
  end

  describe "scan_references/1" do
    test "extracts every authoritative external Flow reference surface" do
      nested_mention =
        ~s(<p><span class="mention" data-type="sheet" data-id="12">Nested</span></p>)

      snapshot = %{
        "scene_id" => 42,
        "nodes" => [
          %{
            "type" => "dialogue",
            "data" => %{
              "speaker_sheet_id" => 10,
              "location_sheet_id" => 11,
              "avatar_id" => 13,
              "audio_asset_id" => 20,
              "responses" => [%{"text" => nested_mention}]
            }
          },
          %{
            "type" => "subflow",
            "data" => %{
              "referenced_flow_id" => 30
            }
          },
          %{
            "type" => "exit",
            "data" => %{"target_type" => "scene", "target_id" => 41}
          },
          %{
            "type" => "sequence",
            "data" => %{},
            "sequence_tracks" => [%{"asset_id" => 52}],
            "sequence_visual_layers" => [%{"asset_id" => 53}]
          }
        ],
        "localization" => [
          %{"vo_asset_id" => 51, "speaker_sheet_id" => 14}
        ]
      }

      refs = FlowBuilder.scan_references(snapshot)

      types_and_ids = refs |> Enum.map(&{&1.type, &1.id}) |> Enum.sort()

      assert {:asset, 20} in types_and_ids
      assert {:asset, 51} in types_and_ids
      assert {:asset, 52} in types_and_ids
      assert {:asset, 53} in types_and_ids
      assert {:avatar, 13} in types_and_ids
      assert {:flow, 30} in types_and_ids
      assert {:scene, 41} in types_and_ids
      assert {:scene, 42} in types_and_ids
      assert {:sheet, 10} in types_and_ids
      assert {:sheet, 11} in types_and_ids
      assert {:sheet, "12"} in types_and_ids
      assert {:sheet, 14} in types_and_ids
      assert length(refs) == 12

      assert Enum.find(refs, &(&1.type == :avatar && &1.id == 13)).speaker_sheet_id == 10

      for audio_asset_id <- [20, 51, 52] do
        assert Enum.find(refs, &(&1.type == :asset && &1.id == audio_asset_id)).expected_content_type_prefix ==
                 "audio/"
      end

      assert Enum.find(refs, &(&1.type == :asset && &1.id == 53)).expected_content_type_prefix == "image/"
    end

    test "skips nil references" do
      snapshot = %{
        "scene_id" => nil,
        "nodes" => [
          %{
            "type" => "dialogue",
            "data" => %{
              "speaker_sheet_id" => nil,
              "audio_asset_id" => nil
            }
          }
        ]
      }

      refs = FlowBuilder.scan_references(snapshot)
      assert refs == []
    end

    test "extracts voice-over assets from localization rows" do
      snapshot = %{
        "nodes" => [],
        "localization" => [
          %{"vo_asset_id" => 51},
          %{"vo_asset_id" => nil},
          "malformed"
        ]
      }

      assert [%{type: :asset, id: 51}] = FlowBuilder.scan_references(snapshot)
    end

    test "surfaces malformed nested rich-text mentions instead of omitting them" do
      snapshot = %{
        "nodes" => [
          %{
            "type" => "dialogue",
            "data" => %{
              "responses" => [
                %{
                  "text" => ~s(<p><span class="mention" data-type="sheet">Missing target id</span></p>)
                }
              ]
            }
          }
        ]
      }

      assert [%{type: :reference, id: malformed_id, context: context}] =
               FlowBuilder.scan_references(snapshot)

      assert is_binary(malformed_id)
      assert context =~ "rich-text mention"
    end

    test "ignores malformed sequence collections and items while scanning references" do
      snapshot = %{
        "nodes" => [
          %{
            "type" => "sequence",
            "data" => %{},
            "sequence_tracks" => ["bad", %{"asset_id" => 42}],
            "sequence_visual_layers" => %{"asset_id" => 43}
          }
        ]
      }

      assert [%{type: :asset, id: 42}] = FlowBuilder.scan_references(snapshot)
    end
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

  defp stored_asset_paths(project_id, filename) do
    upload_dir =
      :storyarn
      |> Application.fetch_env!(:storage)
      |> Keyword.fetch!(:upload_dir)
      |> Path.expand()

    upload_dir
    |> Path.join("projects/#{project_id}/assets/*/#{filename}")
    |> Path.wildcard()
    |> MapSet.new()
  end
end
