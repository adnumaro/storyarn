defmodule Storyarn.Versioning.Builders.FlowBuilderTest do
  use Storyarn.DataCase, async: false
  use Oban.Testing, repo: Storyarn.Repo

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
  alias Storyarn.Localization
  alias Storyarn.Localization.LocalizedText
  alias Storyarn.Projects.Project
  alias Storyarn.References
  alias Storyarn.Repo
  alias Storyarn.Sheets.EntityReference
  alias Storyarn.Versioning.Builders.FlowBuilder
  alias Storyarn.Versioning.LocalizationSnapshotCodec
  alias Storyarn.Workers.DeleteStorageObjectsWorker

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
               %FlowConnection{flow_id: flow.id}
               |> FlowConnection.create_changeset(%{
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
        from(scene in Storyarn.Scenes.Scene, where: scene.id == ^local_scene.id),
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

    test "fails closed when a persisted avatar does not belong to the selected speaker", %{
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
        from(current in FlowConnection, where: current.id == ^connection.id),
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
      conn = connection_fixture(flow, n1, n2)

      snapshot = FlowBuilder.build_snapshot(flow)

      # Modify the flow
      {:ok, modified_flow} = Flows.update_flow(flow, %{name: "Modified"})
      {:ok, _deleted_node, _meta} = Flows.delete_node(n1)
      assert Repo.get!(FlowNode, n1.id).deleted_at

      # Restore
      {:ok, restored, id_maps} =
        FlowBuilder.restore_snapshot(modified_flow, snapshot,
          restore_action: {:entity_version_restore, "flow"},
          return_id_maps: true
        )

      assert restored.name == flow.name

      restored = Repo.preload(restored, [:nodes, :connections], force: true)
      # Should have the same number of non-deleted nodes
      active_nodes = Enum.reject(restored.nodes, &(&1.deleted_at != nil))
      assert length(active_nodes) == length(snapshot["nodes"])
      assert length(restored.connections) == 1
      assert Enum.find(active_nodes, &(&1.type == "dialogue")).word_count == 3
      assert id_maps.node[n1.id] == n1.id
      assert id_maps.node[n2.id] == n2.id
      assert id_maps.connection[conn.id] == conn.id
      assert Repo.get!(FlowNode, n1.id).deleted_at == nil
      assert Repo.get!(FlowConnection, conn.id).source_node_id == n1.id
    end

    test "rejects empty, entry-less, duplicate-entry, and exit-less graphs without writing", %{
      user: user,
      flow: flow
    } do
      snapshot = FlowBuilder.build_snapshot(flow)
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
      target_project = project_fixture(user)

      for {expected_error, invalid_snapshot} <- invalid_snapshots do
        assert {:error, ^expected_error} =
                 FlowBuilder.restore_snapshot(current_flow, invalid_snapshot,
                   restore_action: {:entity_version_restore, "flow"}
                 )

        assert Repo.get!(Flow, flow.id).name == "Current state"
        assert Repo.get!(FlowNode, post_snapshot_node.id).deleted_at == nil
        assert flow_node_ids(flow.id) == initial_node_ids

        count_before =
          Repo.aggregate(
            from(target_flow in Flow, where: target_flow.project_id == ^target_project.id),
            :count
          )

        assert {:error, ^expected_error} =
                 FlowBuilder.instantiate_snapshot(target_project.id, invalid_snapshot, reset_shortcut: true)

        assert Repo.aggregate(
                 from(target_flow in Flow,
                   where: target_flow.project_id == ^target_project.id
                 ),
                 :count
               ) == count_before
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

      snapshot = FlowBuilder.build_snapshot(flow)
      assert [%{"translated_text" => "Hola"}] = snapshot["localization"]

      assert {:ok, restored} =
               FlowBuilder.restore_snapshot(flow, snapshot, restore_action: {:entity_version_restore, "flow"})

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

      snapshot = FlowBuilder.build_snapshot(flow)
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
               FlowBuilder.restore_snapshot(flow, snapshot, restore_action: {:entity_version_restore, "flow"})

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

      assert {:ok, _text} =
               Localization.update_text(text, %{
                 translated_text: "Línea histórica",
                 status: "final",
                 vo_asset_id: voice.id,
                 vo_status: "recorded"
               })

      snapshot = FlowBuilder.build_snapshot(flow)
      assert [%{"vo_asset_id" => voice_id, "vo_status" => "recorded"}] = snapshot["localization"]
      assert voice_id == voice.id
      assert snapshot["asset_blob_hashes"][to_string(voice.id)] == voice.blob_hash
      assert snapshot["asset_metadata"][to_string(voice.id)]["project_id"] == project.id
      assert {:ok, _deleted_voice} = Assets.delete_asset(voice)

      {:ok, current_flow} = Flows.update_flow(flow, %{name: "Current flow"})

      assert {:ok, current_node, _meta} =
               Flows.update_node_data(node, %{"text" => "Current line", "responses" => []})

      assert {:ok, _restored_flow} =
               FlowBuilder.restore_snapshot(current_flow, snapshot, restore_action: {:entity_version_restore, "flow"})

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

      snapshot = FlowBuilder.build_snapshot(flow)
      assert {:ok, _deleted_asset} = Assets.delete_asset(audio)

      delete_storage_blob(
        BlobStore.blob_key(
          project.id,
          audio.blob_hash,
          BlobStore.ext_from_content_type(audio.content_type)
        )
      )

      assert {:ok, current_flow} = Flows.update_flow(flow, %{name: "Current flow"})

      current_node = Repo.get!(FlowNode, node.id)

      assert {:ok, updated_node, _meta} =
               Flows.update_node_data(
                 current_node,
                 %{"text" => "Current line", "responses" => []}
               )

      assert {:error, {:asset_materialization_failed, asset_id, {:asset_blob_unavailable, :enoent}}} =
               FlowBuilder.restore_snapshot(current_flow, snapshot, restore_action: {:entity_version_restore, "flow"})

      assert asset_id == audio.id
      assert Repo.get!(Flow, flow.id).name == "Current flow"
      assert Repo.get!(FlowNode, node.id).data == updated_node.data
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

      snapshot = FlowBuilder.build_snapshot(flow)

      assert Enum.all?(
               snapshot["localization"],
               &(&1["speaker_sheet_id"] == speaker.id)
             )

      assert {:ok, _restored} =
               FlowBuilder.restore_snapshot(flow, snapshot, restore_action: {:entity_version_restore, "flow"})

      restored_rows = Localization.get_texts_for_source("flow_node", node.id)
      assert restored_rows |> Enum.map(& &1.source_field) |> Enum.sort() == ["response.continue.text", "text"]
      assert Enum.all?(restored_rows, &(&1.speaker_sheet_id == speaker.id))
    end

    test "remaps in-place node and localization speaker IDs through the same map", %{
      project: project,
      flow: flow
    } do
      _en = source_language_fixture(project, %{locale_code: "en", name: "English"})
      _es = language_fixture(project, %{locale_code: "es", name: "Spanish"})
      old_speaker = sheet_fixture(project, %{name: "Old speaker"})

      node =
        node_fixture(flow, %{
          type: "dialogue",
          data: %{
            "text" => "Mapped line",
            "speaker_sheet_id" => old_speaker.id,
            "responses" => []
          }
        })

      snapshot = FlowBuilder.build_snapshot(flow)
      new_speaker = sheet_fixture(project, %{name: "New speaker"})
      deleted_at = DateTime.truncate(DateTime.utc_now(), :second)

      Repo.update_all(
        from(sheet in Storyarn.Sheets.Sheet, where: sheet.id == ^old_speaker.id),
        set: [deleted_at: deleted_at]
      )

      assert {:ok, restored} =
               FlowBuilder.restore_snapshot(flow, snapshot,
                 restore_action: {:entity_version_restore, "flow"},
                 external_id_maps: %{
                   sheet: %{old_speaker.id => new_speaker.id}
                 }
               )

      restored_node = Enum.find(restored.nodes, &(&1.id == node.id))
      assert restored_node.data["speaker_sheet_id"] == new_speaker.id

      assert [%LocalizedText{speaker_sheet_id: speaker_sheet_id}] =
               Localization.get_texts_for_source("flow_node", node.id)

      assert speaker_sheet_id == new_speaker.id
    end

    test "rejects an in-place restore whose avatar and speaker maps disagree without mutation", %{
      user: user,
      project: project,
      flow: flow
    } do
      original_speaker =
        sheet_fixture(project, %{name: "Original speaker"})

      other_speaker =
        sheet_fixture(project, %{name: "Other speaker"})

      avatar_asset =
        uploaded_asset(
          project,
          user,
          "restore-speaker-avatar.png",
          "restore speaker avatar",
          "image/png"
        )

      {:ok, avatar} =
        Storyarn.Sheets.add_avatar(
          original_speaker,
          avatar_asset.id
        )

      dialogue =
        node_fixture(flow, %{
          type: "dialogue",
          data: %{
            "speaker_sheet_id" => original_speaker.id,
            "avatar_id" => avatar.id,
            "text" => "Snapshot line"
          }
        })

      snapshot = FlowBuilder.build_snapshot(flow)

      assert {:ok, current_flow} =
               Flows.update_flow(flow, %{name: "Current flow"})

      assert {:ok, current_dialogue, %{renamed_jumps: 0}} =
               Flows.update_node_data(
                 dialogue,
                 Map.put(dialogue.data, "text", "Current line")
               )

      assert {:error, {:avatar_speaker_mismatch, avatar_id, avatar_sheet_id, requested_speaker_id}} =
               FlowBuilder.restore_snapshot(
                 current_flow,
                 snapshot,
                 restore_action: {
                   :entity_version_restore,
                   "flow"
                 },
                 external_id_maps: %{
                   sheet: %{
                     original_speaker.id => other_speaker.id
                   }
                 }
               )

      assert avatar_id == avatar.id
      assert avatar_sheet_id == original_speaker.id
      assert requested_speaker_id == other_speaker.id
      assert Repo.get!(Flow, flow.id).name == "Current flow"

      assert Repo.get!(FlowNode, dialogue.id).data ==
               current_dialogue.data
    end

    test "restores historical locales and reconciles a target locale added later", %{
      project: project,
      flow: flow
    } do
      _en = source_language_fixture(project, %{locale_code: "en", name: "English"})
      _es = language_fixture(project, %{locale_code: "es", name: "Spanish"})
      node = node_fixture(flow, %{type: "dialogue", data: %{"text" => "Historical line", "responses" => []}})

      snapshot = FlowBuilder.build_snapshot(flow)
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
               FlowBuilder.restore_snapshot(flow, snapshot, restore_action: {:entity_version_restore, "flow"})

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

      snapshot = FlowBuilder.build_snapshot(flow)

      assert snapshot["localization"] == []
      assert snapshot["localization_manifest"]["target_locales"] == ["es"]

      assert :ok =
               LocalizationSnapshotCodec.validate_manifest(
                 [],
                 snapshot["localization_manifest"]
               )

      {:ok, modified_flow} = Flows.update_flow(flow, %{name: "Current flow"})

      assert {:ok, restored} =
               FlowBuilder.restore_snapshot(modified_flow, snapshot, restore_action: {:entity_version_restore, "flow"})

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

      snapshot = FlowBuilder.build_snapshot(flow)
      {:ok, modified_flow} = Flows.update_flow(flow, %{name: "Keep this name"})
      _language = language_fixture(project, %{locale_code: "es", name: "Spanish"})
      constraint_name = "localized_texts_restore_#{System.unique_integer([:positive])}"

      Repo.query!(
        "ALTER TABLE localized_texts ADD CONSTRAINT #{constraint_name} " <>
          "CHECK (project_id <> #{project.id}) NOT VALID"
      )

      assert_raise Postgrex.Error, ~r/#{constraint_name}/, fn ->
        FlowBuilder.restore_snapshot(modified_flow, snapshot, restore_action: {:entity_version_restore, "flow"})
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

      snapshot = FlowBuilder.build_snapshot(flow)

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

      assert {:ok, restored, id_maps} =
               FlowBuilder.restore_snapshot(flow, snapshot,
                 restore_action: {:entity_version_restore, "flow"},
                 return_id_maps: true
               )

      rebuilt_snapshot = FlowBuilder.build_snapshot(restored)

      assert FlowBuilder.diff_snapshots(snapshot, rebuilt_snapshot) == []

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
      assert id_maps.sequence_track == %{track.id => track.id}
      assert id_maps.sequence_visual_layer == %{layer.id => layer.id}
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

      snapshot = FlowBuilder.build_snapshot(flow)

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
      target_project = project_fixture(user)

      for {expected_tag, invalid_snapshot} <- invalid_snapshots do
        assert {:error, restore_reason} =
                 FlowBuilder.restore_snapshot(current_flow, invalid_snapshot,
                   restore_action: {:entity_version_restore, "flow"}
                 )

        assert elem(restore_reason, 0) == expected_tag
        assert Repo.get!(Flow, flow.id).name == "Current sequence state"
        assert Repo.get!(SequenceConfig, sequence.id).name == "Strict sequence"

        count_before =
          Repo.aggregate(
            from(target_flow in Flow, where: target_flow.project_id == ^target_project.id),
            :count
          )

        assert {:error, instantiate_reason} =
                 FlowBuilder.instantiate_snapshot(target_project.id, invalid_snapshot, reset_shortcut: true)

        assert elem(instantiate_reason, 0) == expected_tag

        assert Repo.aggregate(
                 from(target_flow in Flow,
                   where: target_flow.project_id == ^target_project.id
                 ),
                 :count
               ) == count_before
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

      snapshot = FlowBuilder.build_snapshot(flow)

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
               FlowBuilder.restore_snapshot(modified_flow, snapshot, restore_action: {:entity_version_restore, "flow"})

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

    test "restores main only when no other active or trashed flow is already main", %{
      project: project,
      flow: flow
    } do
      assert {:ok, main_flow} = Flows.set_main_flow(flow)
      main_snapshot = FlowBuilder.build_snapshot(main_flow)

      assert {:ok, demoted_flow} = Flows.update_flow(main_flow, %{is_main: false})

      assert {:ok, restored_main} =
               FlowBuilder.restore_snapshot(demoted_flow, main_snapshot,
                 restore_action: {:entity_version_restore, "flow"}
               )

      assert restored_main.is_main

      other_flow = flow_fixture(project)
      assert {:ok, other_main} = Flows.set_main_flow(other_flow)
      assert {:ok, trashed_main} = Flows.delete_flow(other_main)
      assert trashed_main.is_main
      assert trashed_main.deleted_at

      assert {:ok, restored_non_main} =
               FlowBuilder.restore_snapshot(restored_main, main_snapshot,
                 restore_action: {:entity_version_restore, "flow"}
               )

      refute restored_non_main.is_main

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
      snapshot = FlowBuilder.build_snapshot(main_flow)
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
               FlowBuilder.restore_snapshot(demoted_flow, snapshot,
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
      snapshot = FlowBuilder.build_snapshot(flow)

      Repo.delete!(source)
      refute Repo.get(FlowNode, source.id)
      refute Repo.get(FlowConnection, connection.id)

      assert {:ok, restored} =
               FlowBuilder.restore_snapshot(flow, snapshot, restore_action: {:entity_version_restore, "flow"})

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

      snapshot = FlowBuilder.build_snapshot(flow)

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
               FlowBuilder.restore_snapshot(flow, snapshot, restore_action: {:entity_version_restore, "flow"})

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

      snapshot = FlowBuilder.build_snapshot(flow)
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

      assert {:error, {:asset_materialization_failed, ^missing_asset_id, :missing_blob_hash}} =
               FlowBuilder.restore_snapshot(modified_flow, invalid_snapshot,
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

      snapshot = FlowBuilder.build_snapshot(flow)

      assert_raise RuntimeError, "post-commit finalization failed", fn ->
        FlowBuilder.restore_snapshot(flow, snapshot,
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

      snapshot = FlowBuilder.build_snapshot(flow)

      assert {:ok, _restored_flow} =
               FlowBuilder.restore_snapshot(flow, snapshot,
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

      snapshot = FlowBuilder.build_snapshot(flow)

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
               FlowBuilder.restore_snapshot(flow, snapshot, restore_action: {:entity_version_restore, "flow"})

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
      snapshot = FlowBuilder.build_snapshot(referenced_flow)

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
               FlowBuilder.restore_snapshot(referenced_flow, snapshot, restore_action: {:entity_version_restore, "flow"})

      assert Repo.get!(FlowNode, referenced_exit.id).deleted_at == nil

      assert Repo.get!(FlowConnection, caller_connection.id).source_pin ==
               "exit_#{referenced_exit.id}"
    end

    test "fails atomically before removing an exit used by a caller, including trash", %{
      project: project,
      flow: referenced_flow
    } do
      snapshot_without_new_exit = FlowBuilder.build_snapshot(referenced_flow)
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
               FlowBuilder.restore_snapshot(current_flow, snapshot_without_new_exit,
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
               FlowBuilder.restore_snapshot(current_flow, snapshot_without_new_exit,
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

      snapshot = FlowBuilder.build_snapshot(flow)
      assert {:ok, _deleted_exit, _meta} = Flows.delete_node(referenced_exit)
      {:ok, current_flow} = Flows.update_flow(flow, %{name: "Current caller"})

      assert {:error, {:dynamic_exit_pin_not_materializable, connection_id, source_pin, :exit_not_in_referenced_flow}} =
               FlowBuilder.restore_snapshot(current_flow, snapshot, restore_action: {:entity_version_restore, "flow"})

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

      snapshot = FlowBuilder.build_snapshot(flow)
      {:ok, current_flow} = Flows.update_flow(flow, %{name: "Current flow"})
      foreign_scene = user |> project_fixture() |> scene_fixture()

      cross_project_snapshot =
        update_snapshot_node(snapshot, exit_node.id, fn node ->
          node
          |> put_in(["data", "target_type"], "scene")
          |> put_in(["data", "target_id"], foreign_scene.id)
        end)

      assert {:error,
              {:flow_external_reference_not_materializable, {:flow_node, node_id, "target_id", "scene"}, target_id}} =
               FlowBuilder.restore_snapshot(current_flow, cross_project_snapshot,
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

      snapshot = FlowBuilder.build_snapshot(flow)
      {:ok, current_flow} = Flows.update_flow(flow, %{name: "Must remain current"})
      other_project = project_fixture(user)
      foreign_scene = scene_fixture(other_project)
      foreign_flow = flow_fixture(other_project)

      cross_project_flow_snapshot =
        update_snapshot_node(snapshot, subflow.id, fn node ->
          put_in(node, ["data", "referenced_flow_id"], foreign_flow.id)
        end)

      assert {:error,
              {:flow_external_reference_not_materializable, {:flow_node, subflow_id, "referenced_flow_id"},
               foreign_flow_id}} =
               FlowBuilder.restore_snapshot(current_flow, cross_project_flow_snapshot,
                 restore_action: {:entity_version_restore, "flow"}
               )

      assert subflow_id == subflow.id
      assert foreign_flow_id == foreign_flow.id

      cross_project_scene_snapshot =
        Map.put(snapshot, "scene_id", foreign_scene.id)

      assert {:error, {:flow_external_reference_not_materializable, {:flow, flow_id, "scene_id"}, foreign_scene_id}} =
               FlowBuilder.restore_snapshot(current_flow, cross_project_scene_snapshot,
                 restore_action: {:entity_version_restore, "flow"}
               )

      assert flow_id == flow.id
      assert foreign_scene_id == foreign_scene.id

      deleted_at = DateTime.truncate(DateTime.utc_now(), :second)

      Repo.update_all(
        from(target in Flow, where: target.id == ^referenced_flow.id),
        set: [deleted_at: deleted_at]
      )

      assert {:error,
              {:flow_external_reference_not_materializable, {:flow_node, ^subflow_id, "referenced_flow_id"},
               deleted_flow_id}} =
               FlowBuilder.restore_snapshot(current_flow, snapshot, restore_action: {:entity_version_restore, "flow"})

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

      snapshot = FlowBuilder.build_snapshot(flow)
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
               FlowBuilder.restore_snapshot(current_flow, snapshot, restore_action: {:entity_version_restore, "flow"})

      assert {flow_id, node_id, target_flow_id} ==
               {flow.id, subflow.id, referenced_flow.id}

      assert Repo.get!(Flow, flow.id).name == "Current name"
      assert Repo.get!(FlowNode, subflow.id).data["referenced_flow_id"] == referenced_flow.id
    end

    test "rejects restore when the owning project is in trash", %{
      project: project,
      flow: flow
    } do
      snapshot = FlowBuilder.build_snapshot(flow)
      {:ok, current_flow} = Flows.update_flow(flow, %{name: "Current name"})
      deleted_at = DateTime.truncate(DateTime.utc_now(), :second)

      Repo.update_all(
        from(owner_project in Project,
          where: owner_project.id == ^project.id
        ),
        set: [deleted_at: deleted_at]
      )

      assert {:error, {:project_deleted, project_id}} =
               FlowBuilder.restore_snapshot(current_flow, snapshot, restore_action: {:entity_version_restore, "flow"})

      assert project_id == project.id
      assert Repo.get!(Flow, flow.id).name == "Current name"
    end

    test "rejects restore while the flow root is in trash", %{
      flow: flow
    } do
      node = node_fixture(flow, %{type: "hub", position_x: 120.0})
      snapshot = FlowBuilder.build_snapshot(flow)
      {:ok, current_flow} = Flows.update_flow(flow, %{name: "Current name"})
      deleted_at = DateTime.truncate(DateTime.utc_now(), :second)

      Repo.update_all(
        from(root in Flow, where: root.id == ^flow.id),
        set: [deleted_at: deleted_at]
      )

      assert {:error, {:flow_deleted, flow_id}} =
               FlowBuilder.restore_snapshot(current_flow, snapshot, restore_action: {:entity_version_restore, "flow"})

      assert flow_id == flow.id
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

      snapshot = FlowBuilder.build_snapshot(flow)
      {:ok, modified_flow} = Flows.update_flow(flow, %{name: "Must remain intact"})
      post_snapshot = node_fixture(flow, %{type: "hub", position_x: 200.0})

      for missing_field <- ["name", "nodes", "connections", "localization"] do
        assert {:error, {:missing_snapshot_fields, :flow, [^missing_field]}} =
                 FlowBuilder.restore_snapshot(modified_flow, Map.delete(snapshot, missing_field),
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
               FlowBuilder.restore_snapshot(modified_flow, malformed_snapshot,
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
               FlowBuilder.restore_snapshot(modified_flow, malformed_asset_snapshot,
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

      snapshot = FlowBuilder.build_snapshot(flow)
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
                 FlowBuilder.restore_snapshot(modified_flow, corrupted_snapshot,
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

      snapshot = FlowBuilder.build_snapshot(flow)
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
            LocalizationSnapshotCodec.manifest(
              rows,
              snapshot["localization_manifest"]["target_locales"]
            )
          )

        assert {:error, reason} =
                 FlowBuilder.restore_snapshot(modified_flow, corrupted_snapshot,
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
      snapshot = FlowBuilder.build_snapshot(flow)
      {:ok, modified_flow} = Flows.update_flow(flow, %{name: "Must remain"})
      initial_node_ids = flow_node_ids(flow.id)

      [first_node | _rest] = snapshot["nodes"]
      duplicate_snapshot = Map.update!(snapshot, "nodes", &[first_node | &1])

      assert {:error, {:duplicate_snapshot_original_id, :node}} =
               FlowBuilder.restore_snapshot(modified_flow, duplicate_snapshot,
                 restore_action: {:entity_version_restore, "flow"}
               )

      other_flow = flow_fixture(project)
      other_node = node_fixture(other_flow, %{type: "hub"})

      cross_flow_snapshot =
        Map.update!(snapshot, "nodes", fn [first | rest] ->
          [Map.put(first, "original_id", other_node.id) | rest]
        end)

      assert {:error, {:snapshot_node_owned_by_other_flow, _conflict}} =
               FlowBuilder.restore_snapshot(modified_flow, cross_flow_snapshot,
                 restore_action: {:entity_version_restore, "flow"}
               )

      invalid_endpoint_snapshot =
        Map.update!(snapshot, "connections", fn [first | rest] ->
          [Map.put(first, "source_node_index", -1) | rest]
        end)

      assert {:error, {:invalid_snapshot_connection_endpoint, _id, :source, -1}} =
               FlowBuilder.restore_snapshot(modified_flow, invalid_endpoint_snapshot,
                 restore_action: {:entity_version_restore, "flow"}
               )

      assert Repo.get!(Flow, flow.id).name == "Must remain"
      assert flow_node_ids(flow.id) == initial_node_ids
    end

    test "is idempotent", %{flow: flow} do
      source = node_fixture(flow, %{type: "dialogue", position_x: 100.0})
      target = node_fixture(flow, %{type: "hub", position_x: 200.0})
      connection = connection_fixture(flow, source, target)
      snapshot = FlowBuilder.build_snapshot(flow)

      assert {:ok, first_restore, first_maps} =
               FlowBuilder.restore_snapshot(flow, snapshot,
                 restore_action: {:entity_version_restore, "flow"},
                 return_id_maps: true
               )

      assert {:ok, second_restore, second_maps} =
               FlowBuilder.restore_snapshot(first_restore, snapshot,
                 restore_action: {:entity_version_restore, "flow"},
                 return_id_maps: true
               )

      assert first_maps == second_maps
      assert first_maps.node[source.id] == source.id
      assert first_maps.connection[connection.id] == connection.id
      assert FlowBuilder.build_snapshot(second_restore) == snapshot
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

      snapshot = FlowBuilder.build_snapshot(flow)

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
               FlowBuilder.restore_snapshot(flow, snapshot, restore_action: {:entity_version_restore, "flow"})

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

    test "rebuilds only active same-project rich-text mentions in place", %{
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
          type: "dialogue",
          data: %{
            "text" => ~s(<p><span class="mention" data-type="sheet" data-id="#{local_sheet.id}">Local</span></p>),
            "responses" => []
          }
        })

      set_node_data(dialogue, %{"text" => text})

      snapshot = FlowBuilder.build_snapshot(flow)

      assert {:ok, _dialogue, _meta} =
               Flows.update_node_data(dialogue, %{
                 "text" => "Changed",
                 "responses" => []
               })

      assert {:ok, _restored} =
               FlowBuilder.restore_snapshot(flow, snapshot, restore_action: {:entity_version_restore, "flow"})

      restored_dialogue = Repo.get!(FlowNode, dialogue.id)
      assert restored_dialogue.data["text"] == text

      assert Repo.exists?(
               from(reference in EntityReference,
                 where:
                   reference.source_type == "flow_node" and
                     reference.source_id == ^dialogue.id and
                     reference.target_type == "sheet" and
                     reference.target_id == ^local_sheet.id
               )
             )

      refute Repo.exists?(
               from(reference in EntityReference,
                 where:
                   reference.source_type == "flow_node" and
                     reference.source_id == ^dialogue.id and
                     reference.target_id == ^foreign_sheet.id
               )
             )
    end

    test "removes derived references for post-snapshot nodes moved to trash", %{
      project: project,
      flow: flow
    } do
      snapshot = FlowBuilder.build_snapshot(flow)
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
               FlowBuilder.restore_snapshot(flow, snapshot, restore_action: {:entity_version_restore, "flow"})

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

    test "rejects legacy sequence resources without historical IDs", %{flow: flow} do
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

      snapshot = FlowBuilder.build_snapshot(flow)

      legacy_snapshot =
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
               FlowBuilder.restore_snapshot(flow, legacy_snapshot, restore_action: {:entity_version_restore, "flow"})

      assert Repo.get!(SequenceTrack, track.id).flow_node_id == sequence.id
    end
  end

  describe "instantiate_snapshot/3" do
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
        "source" => "manual",
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

      legacy_nodes =
        [
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
            "source" => "manual",
            "parent_id" => nil
          },
          %{
            "original_id" => 99_999,
            "type" => "hub",
            "position_x" => 30.0,
            "position_y" => 40.0,
            "data" => %{},
            "source" => "manual",
            "parent_id" => nil
          }
        ] ++ Enum.filter(snapshot["nodes"], &(&1["type"] in ~w(entry exit)))

      legacy_connection = %{
        "original_id" => 88_888,
        "source_node_index" => 0,
        "target_node_index" => 1,
        "source_pin" => "legacy.choice",
        "target_pin" => "input",
        "label" => nil
      }

      snapshot = Map.merge(snapshot, %{"nodes" => legacy_nodes, "connections" => [legacy_connection]})
      flow_count = Repo.aggregate(from(candidate in Flow, where: candidate.project_id == ^project.id), :count)

      assert {:error, {:invalid_snapshot_dialogue_localization_id, 99_998, "legacy.dialogue"}} =
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
                 asset_error_mode: :strict,
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
        from(current in FlowConnection, where: current.id == ^connection.id),
        set: [source_pin: source_pin]
      )

      snapshot = FlowBuilder.build_snapshot(flow)

      assert {:ok, materialized, _id_maps} =
               FlowBuilder.instantiate_snapshot(project.id, snapshot, reset_shortcut: true)

      assert [cloned_connection] = materialized.connections
      assert cloned_connection.source_pin == source_pin
    end

    test "rejects legacy sequence snapshots without config", %{project: project, flow: flow} do
      snapshot = FlowBuilder.build_snapshot(flow)

      legacy_sequence = %{
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

      snapshot = Map.put(snapshot, "nodes", [legacy_sequence | snapshot["nodes"]])
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

  defp replace_localization_row(rows, target, update_fun) do
    Enum.map(rows, fn row ->
      if row == target, do: update_fun.(row), else: row
    end)
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
