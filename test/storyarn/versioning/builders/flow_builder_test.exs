defmodule Storyarn.Versioning.Builders.FlowBuilderTest do
  use Storyarn.DataCase, async: false

  import Storyarn.AccountsFixtures
  import Storyarn.AssetsFixtures
  import Storyarn.FlowsFixtures
  import Storyarn.LocalizationFixtures
  import Storyarn.ProjectsFixtures
  import Storyarn.ScenesFixtures, only: [scene_fixture: 1]

  alias Storyarn.Assets
  alias Storyarn.Assets.Asset
  alias Storyarn.Assets.BlobStore
  alias Storyarn.Flows
  alias Storyarn.Flows.SequenceConfig
  alias Storyarn.Flows.SequenceTrack
  alias Storyarn.Flows.SequenceVisualLayer
  alias Storyarn.Localization
  alias Storyarn.Localization.RuntimeKey
  alias Storyarn.Repo
  alias Storyarn.Versioning.Builders.FlowBuilder

  setup do
    user = user_fixture()
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
      assert track["kind"] == "music"
      assert track["asset_id"] == audio.id
      assert track["start_time"] == "1.250"
      assert track["end_time"] == "9.500"
      assert track["volume"] == "0.750"

      assert [layer] = sequence_snapshot["sequence_visual_layers"]
      assert layer["asset_id"] == image.id
      assert layer["label"] == "Castle"
      assert layer["z_index"] == 3
      assert layer["opacity"] == 0.8

      assert snapshot["asset_blob_hashes"][to_string(audio.id)] == audio.blob_hash
      assert snapshot["asset_blob_hashes"][to_string(image.id)] == image.blob_hash
    end
  end

  describe "restore_snapshot/3" do
    test "restores flow with nodes and connections", %{flow: flow} do
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

      # Modify the flow
      {:ok, modified_flow} = Flows.update_flow(flow, %{name: "Modified"})

      # Restore
      {:ok, restored} = FlowBuilder.restore_snapshot(modified_flow, snapshot)

      assert restored.name == flow.name

      restored = Repo.preload(restored, [:nodes, :connections], force: true)
      # Should have the same number of non-deleted nodes
      active_nodes = Enum.reject(restored.nodes, &(&1.deleted_at != nil))
      assert length(active_nodes) == length(snapshot["nodes"])
      assert length(restored.connections) == 1
      assert Enum.find(active_nodes, &(&1.type == "dialogue")).word_count == 3
    end

    test "restores translations after flow node IDs are replaced", %{project: project, flow: flow} do
      _en = source_language_fixture(project, %{locale_code: "en", name: "English"})
      _es = language_fixture(project, %{locale_code: "es", name: "Spanish"})
      node = node_fixture(flow, %{type: "dialogue", data: %{"text" => "Hello", "responses" => []}})
      [text] = Localization.get_texts_for_source("flow_node", node.id)

      assert {:ok, _translated} =
               Localization.update_text(text, %{
                 translated_text: "Hola",
                 status: "final",
                 translator_notes: "Versioned note"
               })

      snapshot = FlowBuilder.build_snapshot(flow)
      assert [%{"translated_text" => "Hola"}] = snapshot["localization"]

      assert {:ok, restored} = FlowBuilder.restore_snapshot(flow, snapshot)
      restored_node = Enum.find(restored.nodes, &(&1.type == "dialogue"))
      refute restored_node.id == node.id

      assert [restored_text] = Localization.get_texts_for_source("flow_node", restored_node.id)
      assert restored_text.translated_text == "Hola"
      assert restored_text.status == "final"
      assert restored_text.translator_notes == "Versioned note"

      assert [%{archived_at: archived_at, archive_reason: "version_replaced"}] =
               project.id
               |> Localization.list_all_texts(source_type: "flow_node")
               |> Enum.filter(&(&1.source_id == node.id))

      assert archived_at
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

      {:ok, _track} =
        Flows.upsert_sequence_track(sequence.id, "ambience", %{
          "asset_id" => audio.id,
          "volume" => Decimal.new("0.4")
        })

      {:ok, _layer} =
        Flows.create_sequence_visual_layer(sequence.id, %{
          "asset_id" => image.id,
          "kind" => "overlay",
          "label" => "Mist",
          "opacity" => 0.6
        })

      snapshot = FlowBuilder.build_snapshot(flow)

      assert {:ok, restored} = FlowBuilder.restore_snapshot(flow, snapshot)
      rebuilt_snapshot = FlowBuilder.build_snapshot(restored)

      assert FlowBuilder.diff_snapshots(snapshot, rebuilt_snapshot) == []

      restored_sequence = Enum.find(restored.nodes, &(&1.type == "sequence"))
      restored_child = Enum.find(restored.nodes, &(&1.type == "hub"))

      assert restored_child.parent_id == restored_sequence.id
      refute restored_child.parent_id == sequence.id

      assert %SequenceConfig{name: "Original sequence", width: 500.0, height: 280.0} =
               restored_sequence.sequence_config

      assert [%SequenceTrack{kind: "ambience", asset_id: restored_audio_id, volume: volume}] =
               restored_sequence.sequence_tracks

      assert restored_audio_id == audio.id
      assert Decimal.equal?(volume, Decimal.new("0.4"))

      assert [%SequenceVisualLayer{kind: "overlay", asset_id: restored_image_id, label: "Mist"}] =
               restored_sequence.sequence_visual_layers

      assert restored_image_id == image.id
    end
  end

  describe "instantiate_snapshot/3" do
    test "materializes a new flow and remaps connection node ids", %{project: project, flow: flow} do
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

      assert {:ok, materialized, id_maps} =
               FlowBuilder.instantiate_snapshot(project.id, snapshot,
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
      refute cloned_dialogue.data["localization_id"] == node_a.data["localization_id"]
      assert cloned_dialogue.word_count == 3
    end

    test "materializes a legacy dialogue snapshot without a runtime identity", %{project: project, flow: flow} do
      snapshot = FlowBuilder.build_snapshot(flow)

      invalid_dialogue = %{
        "original_id" => 99_999,
        "type" => "dialogue",
        "position_x" => 10.0,
        "position_y" => 20.0,
        "data" => %{"text" => "No identity", "responses" => []},
        "source" => "manual"
      }

      snapshot = Map.put(snapshot, "nodes", [invalid_dialogue | snapshot["nodes"]])

      assert {:ok, materialized, _id_maps} =
               FlowBuilder.instantiate_snapshot(project.id, snapshot, reset_shortcut: true)

      legacy_dialogue = Enum.find(materialized.nodes, &(&1.data["text"] == "No identity"))
      assert RuntimeKey.valid_dialogue_id?(legacy_dialogue.data["localization_id"])
    end

    test "keeps legacy response connections aligned when ids are normalized", %{project: project, flow: flow} do
      snapshot = FlowBuilder.build_snapshot(flow)

      legacy_nodes = [
        %{
          "original_id" => 99_998,
          "type" => "dialogue",
          "position_x" => 10.0,
          "position_y" => 20.0,
          "data" => %{
            "localization_id" => "legacy.dialogue",
            "text" => "Choose",
            "responses" => [%{"id" => "legacy.choice", "text" => "Continue"}]
          },
          "source" => "manual"
        },
        %{
          "original_id" => 99_999,
          "type" => "hub",
          "position_x" => 30.0,
          "position_y" => 40.0,
          "data" => %{},
          "source" => "manual"
        }
      ]

      legacy_connection = %{
        "original_id" => 88_888,
        "source_node_index" => 0,
        "target_node_index" => 1,
        "source_pin" => "legacy.choice",
        "target_pin" => "input",
        "label" => nil
      }

      snapshot = Map.merge(snapshot, %{"nodes" => legacy_nodes, "connections" => [legacy_connection]})

      assert {:ok, materialized, _id_maps} =
               FlowBuilder.instantiate_snapshot(project.id, snapshot, reset_shortcut: true)

      dialogue = Enum.find(materialized.nodes, &(&1.type == "dialogue"))
      [response] = dialogue.data["responses"]
      [connection] = materialized.connections

      assert response["id"] == "legacy_choice"
      assert connection.source_pin == response["id"]
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

    test "drops external refs when preserve_external_refs is false", %{
      user: user,
      project: project,
      flow: flow
    } do
      scene = scene_fixture(project)
      audio_asset = audio_asset_fixture(project, user)
      {:ok, flow} = Flows.update_flow(flow, %{scene_id: scene.id})

      _node =
        node_fixture(flow, %{
          data: %{"speaker" => "Narrator", "text" => "Hello", "audio_asset_id" => audio_asset.id}
        })

      snapshot = FlowBuilder.build_snapshot(flow)

      assert {:ok, materialized, _id_maps} =
               FlowBuilder.instantiate_snapshot(project.id, snapshot,
                 preserve_external_refs: false,
                 reset_shortcut: true
               )

      assert materialized.scene_id == nil
      assert Enum.all?(materialized.nodes, &is_nil((&1.data || %{})["audio_asset_id"]))
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
      on_exit(fn -> Assets.storage_delete(cloned_audio.key) end)
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

      {:ok, _track} =
        Flows.upsert_sequence_track(sequence.id, "music", %{
          "asset_id" => audio.id,
          "volume" => Decimal.new("0.65")
        })

      {:ok, _layer} =
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

      assert [%SequenceTrack{asset_id: cloned_audio_id}] = cloned_sequence.sequence_tracks

      assert [%SequenceVisualLayer{asset_id: cloned_image_id, label: "Cloned stage"}] =
               cloned_sequence.sequence_visual_layers

      refute cloned_audio_id == audio.id
      refute cloned_image_id == image.id
      cloned_audio = Repo.get!(Asset, cloned_audio_id)
      cloned_image = Repo.get!(Asset, cloned_image_id)
      assert cloned_audio.project_id == target_project.id
      assert cloned_image.project_id == target_project.id

      on_exit(fn ->
        Assets.storage_delete(cloned_audio.key)
        Assets.storage_delete(cloned_image.key)
      end)
    end

    test "remaps dynamic exit pins to cloned node ids", %{project: project, flow: flow} do
      subflow_node = node_fixture(flow, %{type: "subflow", position_x: 100.0, position_y: 100.0})
      next_node = node_fixture(flow, %{type: "dialogue", position_x: 200.0, position_y: 100.0})

      _connection =
        connection_fixture(flow, subflow_node, next_node, %{
          source_pin: "exit_#{next_node.id}",
          target_pin: "input"
        })

      snapshot = FlowBuilder.build_snapshot(flow)

      assert {:ok, materialized, id_maps} =
               FlowBuilder.instantiate_snapshot(project.id, snapshot, reset_shortcut: true)

      [cloned_connection] = materialized.connections
      assert cloned_connection.source_pin == "exit_#{id_maps.node[next_node.id]}"
      assert cloned_connection.target_pin == "input"
    end

    test "keeps exit-shaped pins unchanged for non-subflow source nodes", %{project: project, flow: flow} do
      source = node_fixture(flow, %{type: "hub", position_x: 100.0, position_y: 100.0})
      target = node_fixture(flow, %{type: "hub", position_x: 200.0, position_y: 100.0})
      source_pin = "exit_#{target.id}"

      _connection =
        connection_fixture(flow, source, target, %{
          source_pin: source_pin,
          target_pin: "input"
        })

      snapshot = FlowBuilder.build_snapshot(flow)

      assert {:ok, materialized, _id_maps} =
               FlowBuilder.instantiate_snapshot(project.id, snapshot, reset_shortcut: true)

      assert [cloned_connection] = materialized.connections
      assert cloned_connection.source_pin == source_pin
    end

    test "materializes legacy sequence snapshots without config", %{project: project, flow: flow} do
      snapshot = FlowBuilder.build_snapshot(flow)

      legacy_sequence = %{
        "original_id" => 99_997,
        "type" => "sequence",
        "position_x" => 10.0,
        "position_y" => 20.0,
        "data" => %{},
        "source" => "manual"
      }

      snapshot = Map.put(snapshot, "nodes", [legacy_sequence | snapshot["nodes"]])

      assert {:ok, materialized, _id_maps} =
               FlowBuilder.instantiate_snapshot(project.id, snapshot, reset_shortcut: true)

      materialized_sequence = Enum.find(materialized.nodes, &(&1.type == "sequence"))
      assert materialized_sequence
      assert materialized_sequence.sequence_config == nil
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
        "sequence_config" => %{"name" => "Malformed", "width" => 300.0, "height" => 200.0},
        "sequence_tracks" => ["not-a-track"],
        "sequence_visual_layers" => []
      }

      snapshot = Map.put(snapshot, "nodes", [malformed_sequence | snapshot["nodes"]])

      assert {:error, {:invalid_sequence_resource_snapshot, "not-a-track"}} =
               FlowBuilder.instantiate_snapshot(project.id, snapshot, reset_shortcut: true)
    end
  end

  describe "scan_references/1" do
    test "extracts speaker, subflow, and audio refs from nodes" do
      snapshot = %{
        "scene_id" => 42,
        "nodes" => [
          %{
            "type" => "dialogue",
            "data" => %{
              "speaker_sheet_id" => 10,
              "audio_asset_id" => 20
            }
          },
          %{
            "type" => "subflow",
            "data" => %{
              "referenced_flow_id" => 30
            }
          },
          %{
            "type" => "hub",
            "data" => %{}
          }
        ]
      }

      refs = FlowBuilder.scan_references(snapshot)

      types_and_ids = refs |> Enum.map(&{&1.type, &1.id}) |> Enum.sort()

      assert {:asset, 20} in types_and_ids
      assert {:flow, 30} in types_and_ids
      assert {:scene, 42} in types_and_ids
      assert {:sheet, 10} in types_and_ids
      assert length(refs) == 4
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

  describe "diff_snapshots/2" do
    test "detects name change" do
      old = %{"name" => "Old", "shortcut" => "old", "nodes" => [], "connections" => []}
      new = %{"name" => "New", "shortcut" => "old", "nodes" => [], "connections" => []}

      changes = FlowBuilder.diff_snapshots(old, new)
      assert [%{category: :property, action: :modified, detail: detail}] = changes
      assert detail =~ "Renamed"
    end

    test "detects added nodes" do
      old = %{"name" => "F", "nodes" => [], "connections" => []}
      new = %{"name" => "F", "nodes" => [%{"type" => "dialogue"}], "connections" => []}

      changes = FlowBuilder.diff_snapshots(old, new)
      assert Enum.any?(changes, &(&1.category == :node && &1.action == :added))
    end

    test "detects removed nodes" do
      old = %{"name" => "F", "nodes" => [%{"type" => "hub"}], "connections" => []}
      new = %{"name" => "F", "nodes" => [], "connections" => []}

      changes = FlowBuilder.diff_snapshots(old, new)
      assert Enum.any?(changes, &(&1.category == :node && &1.action == :removed))
    end

    test "detects modified nodes" do
      node_old = %{
        "type" => "dialogue",
        "original_id" => 1,
        "data" => %{"text" => "Hello"},
        "position_x" => 0,
        "position_y" => 0
      }

      node_new = %{
        "type" => "dialogue",
        "original_id" => 1,
        "data" => %{"text" => "Goodbye"},
        "position_x" => 0,
        "position_y" => 0
      }

      old = %{"name" => "F", "nodes" => [node_old], "connections" => []}
      new = %{"name" => "F", "nodes" => [node_new], "connections" => []}

      changes = FlowBuilder.diff_snapshots(old, new)
      assert Enum.any?(changes, &(&1.category == :node && &1.action == :modified))
    end

    test "ignores position-only changes" do
      node_old = %{
        "type" => "dialogue",
        "original_id" => 1,
        "data" => %{"text" => "Hi"},
        "position_x" => 0,
        "position_y" => 0
      }

      node_new = %{
        "type" => "dialogue",
        "original_id" => 1,
        "data" => %{"text" => "Hi"},
        "position_x" => 100,
        "position_y" => 200
      }

      old = %{"name" => "F", "nodes" => [node_old], "connections" => []}
      new = %{"name" => "F", "nodes" => [node_new], "connections" => []}

      changes = FlowBuilder.diff_snapshots(old, new)
      assert changes == []
    end

    test "ignores legacy denormalized word counts" do
      current_node = %{
        "type" => "dialogue",
        "original_id" => 1,
        "data" => %{"text" => "Hi"},
        "position_x" => 0,
        "position_y" => 0
      }

      legacy_node = Map.put(current_node, "word_count", 1)
      old = %{"name" => "F", "nodes" => [legacy_node], "connections" => []}
      new = %{"name" => "F", "nodes" => [current_node], "connections" => []}

      assert FlowBuilder.diff_snapshots(old, new) == []
    end

    test "returns empty list for identical snapshots" do
      snapshot = %{"name" => "F", "shortcut" => "f", "nodes" => [], "connections" => []}
      assert FlowBuilder.diff_snapshots(snapshot, snapshot) == []
    end

    test "detects connection changes" do
      conn = %{
        "source_node_index" => 0,
        "target_node_index" => 1,
        "source_pin" => "out",
        "target_pin" => "in",
        "label" => nil
      }

      old = %{"name" => "F", "nodes" => [], "connections" => []}
      new = %{"name" => "F", "nodes" => [], "connections" => [conn]}

      changes = FlowBuilder.diff_snapshots(old, new)
      assert Enum.any?(changes, &(&1.category == :connection && &1.action == :added))
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
