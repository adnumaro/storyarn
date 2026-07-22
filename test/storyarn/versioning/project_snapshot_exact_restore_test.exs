defmodule Storyarn.Versioning.ProjectSnapshotExactRestoreTest do
  use Storyarn.DataCase, async: true

  import Storyarn.AccountsFixtures
  import Storyarn.FlowsFixtures
  import Storyarn.LocalizationFixtures
  import Storyarn.ProjectsFixtures
  import Storyarn.ScenesFixtures
  import Storyarn.SheetsFixtures

  alias Storyarn.Flows
  alias Storyarn.Flows.Flow
  alias Storyarn.Flows.FlowConnection
  alias Storyarn.Flows.FlowNode
  alias Storyarn.Flows.SequenceConfig
  alias Storyarn.Localization
  alias Storyarn.Projects
  alias Storyarn.Projects.Project
  alias Storyarn.Scenes
  alias Storyarn.Scenes.Scene
  alias Storyarn.Sheets
  alias Storyarn.Sheets.Block
  alias Storyarn.Sheets.Sheet
  alias Storyarn.Versioning.Builders.ProjectSnapshotBuilder

  setup do
    user = user_fixture()
    project = project_fixture(user)

    %{project: project, user: user}
  end

  describe "exact in-place restore contract" do
    test "soft-deletes roots created after the snapshot and removes their active localization", %{
      project: project
    } do
      source_language_fixture(project, %{locale_code: "en", name: "English"})
      language_fixture(project, %{locale_code: "es", name: "Spanish"})
      snapshot = ProjectSnapshotBuilder.build_snapshot(project.id)

      sheet = sheet_fixture(project, %{name: "Post-snapshot sheet"})
      flow = flow_fixture(project, %{name: "Post-snapshot flow"})
      scene = scene_fixture(project, %{name: "Post-snapshot scene"})

      node =
        node_fixture(flow, %{
          type: "dialogue",
          data: %{
            "text" => "This line did not exist yet",
            "responses" => [%{"id" => "continue", "text" => "Continue"}]
          }
        })

      assert [_dialogue, _response] =
               Localization.get_texts_for_source("flow_node", node.id)

      assert {:ok, _result} =
               ProjectSnapshotBuilder.restore_snapshot(project.id, snapshot)

      assert %Sheet{id: sheet_id, deleted_at: %DateTime{}} =
               Repo.get!(Sheet, sheet.id)

      assert sheet_id == sheet.id

      assert %Flow{id: flow_id, deleted_at: %DateTime{}} =
               Repo.get!(Flow, flow.id)

      assert flow_id == flow.id

      assert %Scene{id: scene_id, deleted_at: %DateTime{}} =
               Repo.get!(Scene, scene.id)

      assert scene_id == scene.id
      assert Localization.get_texts_for_source("flow_node", node.id) == []
    end

    test "restores snapshot roots directly from trash with their original IDs", %{
      project: project
    } do
      sheet = sheet_fixture(project, %{name: "Snapshot sheet"})
      flow = flow_fixture(project, %{name: "Snapshot flow"})
      scene = scene_fixture(project, %{name: "Snapshot scene"})
      target_snapshot = ProjectSnapshotBuilder.build_snapshot(project.id)

      assert {:ok, _deleted_sheet} = Sheets.delete_sheet(sheet)
      assert {:ok, _deleted_flow} = Flows.delete_flow(flow)
      assert {:ok, _deleted_scene} = Scenes.delete_scene(scene)

      assert %Sheet{deleted_at: %DateTime{}} = Repo.get!(Sheet, sheet.id)
      assert %Flow{deleted_at: %DateTime{}} = Repo.get!(Flow, flow.id)
      assert %Scene{deleted_at: %DateTime{}} = Repo.get!(Scene, scene.id)

      safety_snapshot = ProjectSnapshotBuilder.build_snapshot(project.id)

      assert {:ok, _result} =
               ProjectSnapshotBuilder.restore_snapshot(
                 project.id,
                 target_snapshot,
                 pre_restore_snapshot: safety_snapshot
               )

      assert %Sheet{id: sheet_id, deleted_at: nil} = Repo.get!(Sheet, sheet.id)
      assert %Flow{id: flow_id, deleted_at: nil} = Repo.get!(Flow, flow.id)
      assert %Scene{id: scene_id, deleted_at: nil} = Repo.get!(Scene, scene.id)

      assert sheet_id == sheet.id
      assert flow_id == flow.id
      assert scene_id == scene.id
    end

    test "restores snapshot children directly from trash with their original IDs", %{
      project: project
    } do
      sheet = sheet_fixture(project, %{name: "Snapshot sheet"})
      block = block_fixture(sheet, %{value: %{"content" => "Snapshot value"}})
      flow = flow_fixture(project, %{name: "Snapshot flow"})
      node = node_fixture(flow, %{type: "dialogue"})
      target_snapshot = ProjectSnapshotBuilder.build_snapshot(project.id)

      assert {:ok, _deleted_block} = Sheets.delete_block(block)
      assert {:ok, _deleted_node, _meta} = Flows.delete_node(node)

      assert %Block{deleted_at: %DateTime{}} = Repo.get!(Block, block.id)
      assert %FlowNode{deleted_at: %DateTime{}} = Repo.get!(FlowNode, node.id)

      safety_snapshot = ProjectSnapshotBuilder.build_snapshot(project.id)

      assert {:ok, _result} =
               ProjectSnapshotBuilder.restore_snapshot(
                 project.id,
                 target_snapshot,
                 pre_restore_snapshot: safety_snapshot
               )

      assert %Block{id: block_id, deleted_at: nil} = Repo.get!(Block, block.id)
      assert %FlowNode{id: node_id, deleted_at: nil} = Repo.get!(FlowNode, node.id)
      assert block_id == block.id
      assert node_id == node.id
    end

    test "recreates a hard-deleted snapshot root with the same root and child IDs", %{
      project: project
    } do
      sheet = sheet_fixture(project, %{name: "Original sheet name"})
      flow = flow_fixture(project, %{name: "Root that will be purged"})
      snapshot = ProjectSnapshotBuilder.build_snapshot(project.id)

      snapshot_flow =
        Enum.find(snapshot["flows"], &(&1["id"] == flow.id))

      snapshot_node_ids = MapSet.new(snapshot_flow["snapshot"]["nodes"], & &1["original_id"])

      assert {:ok, _changed_sheet} =
               Sheets.update_sheet(sheet, %{name: "Changed after snapshot"})

      assert {:ok, _deleted_flow} = Flows.hard_delete_flow(flow)
      assert Repo.get(Flow, flow.id) == nil

      assert {:ok, _result} =
               ProjectSnapshotBuilder.restore_snapshot(project.id, snapshot)

      restored_flow = Flows.get_flow(project.id, flow.id)

      assert restored_flow.id == flow.id
      assert restored_flow.name == "Root that will be purged"
      assert MapSet.new(restored_flow.nodes, & &1.id) == snapshot_node_ids
      assert Repo.get!(Sheet, sheet.id).name == "Original sheet name"
    end

    test "rejects a snapshot with more than one main flow before applying writes", %{
      project: project
    } do
      first_flow = flow_fixture(project, %{name: "Snapshot first"})
      second_flow = flow_fixture(project, %{name: "Snapshot second"})
      snapshot = ProjectSnapshotBuilder.build_snapshot(project.id)

      invalid_snapshot =
        Map.update!(snapshot, "flows", fn entries ->
          Enum.map(entries, fn entry ->
            if entry["id"] in [first_flow.id, second_flow.id],
              do: put_in(entry, ["snapshot", "is_main"], true),
              else: entry
          end)
        end)

      assert {:ok, _first_flow} =
               Flows.update_flow(first_flow, %{name: "Current first"})

      assert {:ok, _second_flow} =
               Flows.update_flow(second_flow, %{name: "Current second"})

      assert {:error, {:multiple_project_snapshot_main_flows, main_flow_ids}} =
               ProjectSnapshotBuilder.restore_snapshot(
                 project.id,
                 invalid_snapshot
               )

      assert main_flow_ids == Enum.sort([first_flow.id, second_flow.id])
      assert Repo.get!(Flow, first_flow.id).name == "Current first"
      assert Repo.get!(Flow, second_flow.id).name == "Current second"
    end

    test "fails before writes when a main flow absent from target remains in trash", %{
      project: project
    } do
      target_flow = flow_fixture(project, %{name: "Target main"})
      assert {:ok, target_flow} = Flows.set_main_flow(target_flow)
      target_snapshot = ProjectSnapshotBuilder.build_snapshot(project.id)

      assert {:ok, _target_flow} =
               Flows.update_flow(target_flow, %{name: "Current target name"})

      current_only_sheet = sheet_fixture(project, %{name: "Must remain active"})
      current_only_flow = flow_fixture(project, %{name: "Conflicting trash main"})
      assert {:ok, current_only_flow} = Flows.set_main_flow(current_only_flow)
      assert {:ok, trashed_main} = Flows.delete_flow(current_only_flow)
      safety_snapshot = ProjectSnapshotBuilder.build_snapshot(project.id)

      assert {:error, {:project_snapshot_main_flow_conflict_in_trash, target_main_id, [conflict_id]}} =
               ProjectSnapshotBuilder.restore_snapshot(
                 project.id,
                 target_snapshot,
                 pre_restore_snapshot: safety_snapshot
               )

      assert target_main_id == target_flow.id
      assert conflict_id == current_only_flow.id

      assert %Flow{name: "Current target name", is_main: false, deleted_at: nil} =
               Repo.get!(Flow, target_flow.id)

      assert %Flow{is_main: true, deleted_at: %DateTime{}} =
               Repo.get!(Flow, trashed_main.id)

      assert %Sheet{deleted_at: nil} = Repo.get!(Sheet, current_only_sheet.id)
    end

    test "replaces an active current-only main flow with the snapshot main", %{
      project: project
    } do
      target_flow = flow_fixture(project, %{name: "Target main"})
      assert {:ok, target_flow} = Flows.set_main_flow(target_flow)
      target_snapshot = ProjectSnapshotBuilder.build_snapshot(project.id)

      current_only_flow = flow_fixture(project, %{name: "Current-only main"})
      assert {:ok, current_only_flow} = Flows.set_main_flow(current_only_flow)
      safety_snapshot = ProjectSnapshotBuilder.build_snapshot(project.id)

      assert {:ok, _result} =
               ProjectSnapshotBuilder.restore_snapshot(
                 project.id,
                 target_snapshot,
                 pre_restore_snapshot: safety_snapshot
               )

      assert %Flow{is_main: true, deleted_at: nil} =
               Repo.get!(Flow, target_flow.id)

      assert %Flow{is_main: false, deleted_at: %DateTime{}} =
               Repo.get!(Flow, current_only_flow.id)
    end

    test "removes a safety-captured cross-boundary connection before its source pin becomes invalid", %{
      project: project
    } do
      flow = flow_fixture(project, %{name: "Recoverable cross-boundary pin"})

      dialogue =
        node_fixture(flow, %{
          type: "dialogue",
          data: %{
            "text" => "Historical line",
            "responses" => [
              %{"id" => "historical_response", "text" => "Historical"}
            ]
          }
        })

      target_snapshot = ProjectSnapshotBuilder.build_snapshot(project.id)

      current_data =
        dialogue.data
        |> Map.put("text", "Current line")
        |> Map.put("responses", [
          %{"id" => "current_response", "text" => "Current"}
        ])

      assert {:ok, current_dialogue, _meta} =
               Flows.update_node_data(dialogue, current_data)

      current_only_node =
        node_fixture(flow, %{
          type: "hub",
          data: %{"hub_id" => "current_only_target"}
        })

      connection =
        Storyarn.FlowsFixtures.connection_fixture(
          flow,
          current_dialogue,
          current_only_node,
          %{source_pin: "current_response"}
        )

      safety_snapshot = ProjectSnapshotBuilder.build_snapshot(project.id)

      assert {:ok, _result} =
               ProjectSnapshotBuilder.restore_snapshot(
                 project.id,
                 target_snapshot,
                 pre_restore_snapshot: safety_snapshot
               )

      assert is_nil(Repo.get(FlowConnection, connection.id))

      assert %FlowNode{deleted_at: %DateTime{}} =
               Repo.get!(FlowNode, current_only_node.id)

      restored_dialogue = Repo.get!(FlowNode, dialogue.id)

      assert Enum.map(
               restored_dialogue.data["responses"],
               & &1["id"]
             ) == ["historical_response"]

      assert {:ok, _restored_node} =
               Flows.restore_node(flow.id, current_only_node.id)

      assert Enum.all?(
               Flows.list_connections(flow.id),
               &(&1.id != connection.id)
             )

      pre_rollback_snapshot =
        ProjectSnapshotBuilder.build_snapshot(project.id)

      assert {:ok, _result} =
               ProjectSnapshotBuilder.restore_snapshot(
                 project.id,
                 safety_snapshot,
                 pre_restore_snapshot: pre_rollback_snapshot
               )

      assert %FlowConnection{id: restored_connection_id} =
               Repo.get!(FlowConnection, connection.id)

      assert restored_connection_id == connection.id

      assert Enum.map(Repo.get!(FlowNode, dialogue.id).data["responses"], & &1["id"]) == ["current_response"]
    end

    test "fails closed for an incompatible cross-boundary connection absent from safety", %{
      project: project
    } do
      flow = flow_fixture(project, %{name: "Uncaptured cross-boundary pin"})

      dialogue =
        node_fixture(flow, %{
          type: "dialogue",
          data: %{
            "text" => "Historical line",
            "responses" => [
              %{"id" => "historical_response", "text" => "Historical"}
            ]
          }
        })

      target_snapshot = ProjectSnapshotBuilder.build_snapshot(project.id)

      current_data =
        Map.put(dialogue.data, "responses", [
          %{"id" => "current_response", "text" => "Current"}
        ])

      assert {:ok, current_dialogue, _meta} =
               Flows.update_node_data(dialogue, current_data)

      trash_target =
        node_fixture(flow, %{
          type: "hub",
          data: %{"hub_id" => "uncaptured_target"}
        })

      connection =
        Storyarn.FlowsFixtures.connection_fixture(
          flow,
          current_dialogue,
          trash_target,
          %{source_pin: "current_response"}
        )

      assert {:ok, _deleted_target, _meta} =
               Flows.delete_node(trash_target)

      safety_snapshot = ProjectSnapshotBuilder.build_snapshot(project.id)

      assert {:error,
              {:restore_failed, "flows", flow_id,
               {:cross_boundary_connections_missing_from_pre_restore_snapshot, flow_id, [missing]}}} =
               ProjectSnapshotBuilder.restore_snapshot(
                 project.id,
                 target_snapshot,
                 pre_restore_snapshot: safety_snapshot
               )

      assert flow_id == flow.id
      assert missing.connection_id == connection.id

      assert {:invalid_future_source_pin, source_node_id, "current_response", "dialogue"} = missing.reason

      assert source_node_id == dialogue.id

      assert Enum.map(Repo.get!(FlowNode, dialogue.id).data["responses"], & &1["id"]) == ["current_response"]

      assert %FlowNode{deleted_at: %DateTime{}} =
               Repo.get!(FlowNode, trash_target.id)

      assert Repo.get!(FlowConnection, connection.id)
    end

    test "preserves a compatible cross-boundary connection through node trash restore", %{
      project: project
    } do
      flow = flow_fixture(project, %{name: "Compatible cross-boundary pin"})

      dialogue =
        node_fixture(flow, %{
          type: "dialogue",
          data: %{
            "text" => "Stable line",
            "responses" => [
              %{"id" => "stable_response", "text" => "Stable"}
            ]
          }
        })

      target_snapshot = ProjectSnapshotBuilder.build_snapshot(project.id)

      current_only_node =
        node_fixture(flow, %{
          type: "hub",
          data: %{"hub_id" => "compatible_target"}
        })

      connection =
        Storyarn.FlowsFixtures.connection_fixture(
          flow,
          dialogue,
          current_only_node,
          %{source_pin: "stable_response"}
        )

      safety_snapshot = ProjectSnapshotBuilder.build_snapshot(project.id)

      assert {:ok, _result} =
               ProjectSnapshotBuilder.restore_snapshot(
                 project.id,
                 target_snapshot,
                 pre_restore_snapshot: safety_snapshot
               )

      assert Repo.get!(FlowConnection, connection.id)

      assert %FlowNode{deleted_at: %DateTime{}} =
               Repo.get!(FlowNode, current_only_node.id)

      assert Flows.list_connections(flow.id) == []

      assert {:ok, _restored_node} =
               Flows.restore_node(flow.id, current_only_node.id)

      assert Enum.any?(
               Flows.list_connections(flow.id),
               &(&1.id == connection.id)
             )
    end

    test "removes only cross-boundary connections that block a snapshot transition to sequence", %{
      project: project
    } do
      flow = flow_fixture(project, %{name: "Sequence transition"})

      {:ok, sequence} =
        Flows.create_sequence(flow.id, %{
          "name" => "Snapshot sequence",
          "width" => 400.0,
          "height" => 240.0
        })

      trash_source = node_fixture(flow, %{type: "hub", position_x: 500.0})
      trash_target = node_fixture(flow, %{type: "hub", position_x: 600.0})

      unrelated_trash_connection =
        Storyarn.FlowsFixtures.connection_fixture(flow, trash_source, trash_target)

      assert {:ok, _trash_source, _meta} = Flows.delete_node(trash_source)
      assert {:ok, _trash_target, _meta} = Flows.delete_node(trash_target)

      snapshot = ProjectSnapshotBuilder.build_snapshot(project.id)

      Repo.delete_all(
        from(config in SequenceConfig,
          where: config.flow_node_id == ^sequence.id
        )
      )

      current_sequence =
        sequence
        |> change(type: "hub", data: %{"hub_id" => "former_sequence"})
        |> Repo.update!()

      post_snapshot_node = node_fixture(flow, %{type: "hub", position_x: 700.0})

      blocking_connection =
        Storyarn.FlowsFixtures.connection_fixture(flow, current_sequence, post_snapshot_node)

      safety_snapshot = ProjectSnapshotBuilder.build_snapshot(project.id)

      assert {:ok, _result} =
               ProjectSnapshotBuilder.restore_snapshot(
                 project.id,
                 snapshot,
                 pre_restore_snapshot: safety_snapshot
               )

      assert %FlowNode{type: "sequence", deleted_at: nil} =
               Repo.get!(FlowNode, sequence.id)

      assert %FlowNode{deleted_at: %DateTime{}} =
               Repo.get!(FlowNode, post_snapshot_node.id)

      assert is_nil(Repo.get(FlowConnection, blocking_connection.id))
      assert Repo.get!(FlowConnection, unrelated_trash_connection.id)
    end

    test "preserves and rejects an uncaptured trash connection that blocks a sequence transition", %{
      project: project
    } do
      flow = flow_fixture(project, %{name: "Sequence transition with trash"})

      {:ok, sequence} =
        Flows.create_sequence(flow.id, %{
          "name" => "Snapshot sequence",
          "width" => 400.0,
          "height" => 240.0
        })

      target_snapshot = ProjectSnapshotBuilder.build_snapshot(project.id)

      Repo.delete_all(
        from(config in SequenceConfig,
          where: config.flow_node_id == ^sequence.id
        )
      )

      current_sequence =
        sequence
        |> change(type: "hub", data: %{"hub_id" => "former_sequence"})
        |> Repo.update!()

      trash_target = node_fixture(flow, %{type: "hub", position_x: 700.0})

      trash_connection =
        Storyarn.FlowsFixtures.connection_fixture(
          flow,
          current_sequence,
          trash_target
        )

      assert {:ok, _trash_target, _meta} = Flows.delete_node(trash_target)
      safety_snapshot = ProjectSnapshotBuilder.build_snapshot(project.id)

      assert {:error,
              {:restore_failed, "flows", flow_id,
               {:sequence_transition_connections_missing_from_pre_restore_snapshot, flow_id, [connection_id]}}} =
               ProjectSnapshotBuilder.restore_snapshot(
                 project.id,
                 target_snapshot,
                 pre_restore_snapshot: safety_snapshot
               )

      assert flow_id == flow.id
      assert connection_id == trash_connection.id
      assert Repo.get!(FlowNode, sequence.id).type == "hub"
      assert Repo.get!(FlowConnection, trash_connection.id)
    end

    test "preserves a trash child's sequence parent across normal and idempotent restores", %{
      project: project
    } do
      flow = flow_fixture(project, %{name: "Sequence with protected trash"})

      {:ok, sequence} =
        Flows.create_sequence(flow.id, %{
          "name" => "Stable parent",
          "width" => 400.0,
          "height" => 240.0
        })

      target_snapshot = ProjectSnapshotBuilder.build_snapshot(project.id)

      trash_child =
        node_fixture(flow, %{
          type: "hub",
          parent_id: sequence.id,
          position_x: 300.0
        })

      assert {:ok, trash_child, _meta} = Flows.delete_node(trash_child)
      assert trash_child.parent_id == sequence.id

      first_safety_snapshot = ProjectSnapshotBuilder.build_snapshot(project.id)

      assert {:ok, _result} =
               ProjectSnapshotBuilder.restore_snapshot(
                 project.id,
                 target_snapshot,
                 pre_restore_snapshot: first_safety_snapshot
               )

      assert %FlowNode{deleted_at: %DateTime{}, parent_id: parent_id} =
               Repo.get!(FlowNode, trash_child.id)

      assert parent_id == sequence.id

      second_safety_snapshot = ProjectSnapshotBuilder.build_snapshot(project.id)

      assert {:ok, _result} =
               ProjectSnapshotBuilder.restore_snapshot(
                 project.id,
                 target_snapshot,
                 pre_restore_snapshot: second_safety_snapshot
               )

      assert %FlowNode{deleted_at: %DateTime{}, parent_id: parent_id} =
               Repo.get!(FlowNode, trash_child.id)

      assert parent_id == sequence.id
    end

    test "detaches only a safety-captured active child during a sequence-to-node transition", %{
      project: project
    } do
      flow = flow_fixture(project, %{name: "Sequence transition with active child"})
      target_node = node_fixture(flow, %{type: "hub"})
      target_snapshot = ProjectSnapshotBuilder.build_snapshot(project.id)

      assert %FlowNode{type: "sequence"} =
               target_node
               |> change(type: "sequence", data: %{})
               |> Repo.update!()

      Repo.insert!(%SequenceConfig{
        flow_node_id: target_node.id,
        name: "Temporary sequence",
        width: 400.0,
        height: 240.0
      })

      current_child =
        node_fixture(flow, %{
          type: "hub",
          parent_id: target_node.id,
          position_x: 300.0
        })

      safety_snapshot = ProjectSnapshotBuilder.build_snapshot(project.id)

      assert {:ok, _result} =
               ProjectSnapshotBuilder.restore_snapshot(
                 project.id,
                 target_snapshot,
                 pre_restore_snapshot: safety_snapshot
               )

      assert %FlowNode{type: "hub", deleted_at: nil} =
               Repo.get!(FlowNode, target_node.id)

      assert %FlowNode{deleted_at: %DateTime{}, parent_id: nil} =
               Repo.get!(FlowNode, current_child.id)
    end

    test "rejects a sequence-to-node transition with an uncaptured trash child", %{
      project: project
    } do
      flow = flow_fixture(project, %{name: "Sequence transition with trash child"})
      target_node = node_fixture(flow, %{type: "hub"})
      target_snapshot = ProjectSnapshotBuilder.build_snapshot(project.id)

      assert %FlowNode{type: "sequence"} =
               target_node
               |> change(type: "sequence", data: %{})
               |> Repo.update!()

      Repo.insert!(%SequenceConfig{
        flow_node_id: target_node.id,
        name: "Temporary sequence",
        width: 400.0,
        height: 240.0
      })

      trash_child =
        node_fixture(flow, %{
          type: "hub",
          parent_id: target_node.id,
          position_x: 300.0
        })

      assert {:ok, trash_child, _meta} = Flows.delete_node(trash_child)
      safety_snapshot = ProjectSnapshotBuilder.build_snapshot(project.id)

      assert {:error,
              {:restore_failed, "flows", flow_id,
               {:sequence_transition_children_missing_from_pre_restore_snapshot, flow_id, [{child_id, parent_id}]}}} =
               ProjectSnapshotBuilder.restore_snapshot(
                 project.id,
                 target_snapshot,
                 pre_restore_snapshot: safety_snapshot
               )

      assert flow_id == flow.id
      assert child_id == trash_child.id
      assert parent_id == target_node.id

      assert %FlowNode{type: "sequence", deleted_at: nil} =
               Repo.get!(FlowNode, target_node.id)

      assert %FlowNode{deleted_at: %DateTime{}, parent_id: persisted_parent_id} =
               Repo.get!(FlowNode, trash_child.id)

      assert persisted_parent_id == target_node.id
      assert %SequenceConfig{} = Repo.get!(SequenceConfig, target_node.id)
    end

    test "removes a safety-captured caller connection before its dynamic exit disappears", %{
      project: project
    } do
      referenced_flow = flow_fixture(project, %{name: "Referenced flow"})
      target_snapshot = ProjectSnapshotBuilder.build_snapshot(project.id)
      referenced_exit = node_fixture(referenced_flow, %{type: "exit", position_x: 300.0})
      caller = flow_fixture(project, %{name: "Current-only caller"})

      subflow =
        node_fixture(caller, %{
          type: "subflow",
          data: %{"referenced_flow_id" => referenced_flow.id}
        })

      next_node = node_fixture(caller, %{type: "hub"})
      source_pin = "exit_#{referenced_exit.id}"

      caller_connection =
        Storyarn.FlowsFixtures.connection_fixture(
          caller,
          subflow,
          next_node,
          %{source_pin: source_pin}
        )

      safety_snapshot = ProjectSnapshotBuilder.build_snapshot(project.id)

      assert {:ok, _result} =
               ProjectSnapshotBuilder.restore_snapshot(
                 project.id,
                 target_snapshot,
                 pre_restore_snapshot: safety_snapshot
               )

      assert %FlowNode{deleted_at: %DateTime{}} =
               Repo.get!(FlowNode, referenced_exit.id)

      assert %Flow{deleted_at: %DateTime{}} = Repo.get!(Flow, caller.id)

      assert is_nil(Repo.get(FlowConnection, caller_connection.id))

      assert {:ok, _restored_caller} =
               caller.id
               |> then(&Repo.get!(Flow, &1))
               |> Flows.restore_flow()

      assert Flows.list_connections(caller.id) == []

      assert {:ok, _restored_exit} =
               Flows.restore_node(referenced_flow.id, referenced_exit.id)

      pre_rollback_snapshot =
        ProjectSnapshotBuilder.build_snapshot(project.id)

      assert {:ok, _result} =
               ProjectSnapshotBuilder.restore_snapshot(
                 project.id,
                 safety_snapshot,
                 pre_restore_snapshot: pre_rollback_snapshot
               )

      assert %FlowConnection{
               id: restored_connection_id,
               source_pin: ^source_pin
             } = Repo.get!(FlowConnection, caller_connection.id)

      assert restored_connection_id == caller_connection.id
    end

    test "fails closed for an uncaptured trash connection whose source caller remains active", %{
      project: project
    } do
      referenced_flow = flow_fixture(project, %{name: "Referenced flow"})
      target_snapshot = ProjectSnapshotBuilder.build_snapshot(project.id)
      referenced_exit = node_fixture(referenced_flow, %{type: "exit", position_x: 300.0})
      caller = flow_fixture(project, %{name: "Active caller with trash target"})

      subflow =
        node_fixture(caller, %{
          type: "subflow",
          data: %{"referenced_flow_id" => referenced_flow.id}
        })

      next_node = node_fixture(caller, %{type: "hub"})
      source_pin = "exit_#{referenced_exit.id}"

      caller_connection =
        Storyarn.FlowsFixtures.connection_fixture(
          caller,
          subflow,
          next_node,
          %{source_pin: source_pin}
        )

      assert {:ok, _trash_target, _meta} = Flows.delete_node(next_node)
      safety_snapshot = ProjectSnapshotBuilder.build_snapshot(project.id)

      assert {:error, {:restore_failed, "flows", restored_flow_id, reason}} =
               ProjectSnapshotBuilder.restore_snapshot(
                 project.id,
                 target_snapshot,
                 pre_restore_snapshot: safety_snapshot
               )

      assert {:incoming_dynamic_exit_pin_would_break, connection_id, ^source_pin, ^restored_flow_id, pin_reason} =
               reason

      assert pin_reason == :exit_missing_from_snapshot
      assert restored_flow_id == referenced_flow.id
      assert connection_id == caller_connection.id
      assert Repo.get!(FlowNode, referenced_exit.id).deleted_at == nil
      assert Repo.get!(FlowConnection, caller_connection.id).source_pin == source_pin
      assert %Flow{deleted_at: nil} = Repo.get!(Flow, caller.id)
      assert %FlowNode{deleted_at: nil} = Repo.get!(FlowNode, subflow.id)
      assert %FlowNode{deleted_at: %DateTime{}} = Repo.get!(FlowNode, next_node.id)
    end

    test "restores parent and position for sheet, flow, and scene trees", %{
      project: project
    } do
      sheet_parent = sheet_fixture(project, %{name: "Sheet parent"})
      sheet_child = child_sheet_fixture(project, sheet_parent, %{name: "Sheet child", position: 4})

      flow_parent = flow_fixture(project, %{name: "Flow parent"})

      flow_child =
        flow_fixture(project, %{
          name: "Flow child",
          parent_id: flow_parent.id,
          position: 4
        })

      scene_parent = scene_fixture(project, %{name: "Scene parent"})

      scene_child =
        scene_fixture(project, %{
          name: "Scene child",
          parent_id: scene_parent.id,
          position: 4
        })

      roots = [
        {Sheet, sheet_parent.id},
        {Sheet, sheet_child.id},
        {Flow, flow_parent.id},
        {Flow, flow_child.id},
        {Scene, scene_parent.id},
        {Scene, scene_child.id}
      ]

      expected_tree = tree_state(roots)
      snapshot = ProjectSnapshotBuilder.build_snapshot(project.id)

      assert {:ok, _moved_sheet} = Sheets.move_sheet(sheet_child, nil, 0)
      assert {:ok, _moved_flow} = Flows.move_flow_to_position(flow_child, nil, 0)
      assert {:ok, _moved_scene} = Scenes.move_scene_to_position(scene_child, nil, 0)
      refute tree_state(roots) == expected_tree

      assert {:ok, _result} =
               ProjectSnapshotBuilder.restore_snapshot(project.id, snapshot)

      assert tree_state(roots) == expected_tree
    end

    test "captures all restorable project metadata but excludes visible identity", %{
      project: project
    } do
      metadata = snapshot_project_metadata()
      assert {:ok, project} = Projects.update_project(project, metadata)

      snapshot = ProjectSnapshotBuilder.build_snapshot(project.id)
      serialized_metadata = stringify_keys(metadata)

      assert Map.take(snapshot["project"], Map.keys(serialized_metadata)) ==
               serialized_metadata

      refute Map.has_key?(snapshot["project"], "name")
      refute Map.has_key?(snapshot["project"], "slug")
    end

    test "restores project metadata while preserving the current name and slug", %{
      project: project
    } do
      snapshot_metadata = snapshot_project_metadata()
      assert {:ok, project} = Projects.update_project(project, snapshot_metadata)

      snapshot =
        project.id
        |> ProjectSnapshotBuilder.build_snapshot()
        |> update_in(["project"], &Map.merge(&1, stringify_keys(snapshot_metadata)))

      current_metadata = %{
        name: "Current visible project name",
        description: "Current description",
        project_type: "game",
        project_subtype: "rpg",
        project_type_other: nil,
        settings: %{"theme" => "current"},
        auto_snapshots_enabled: false,
        auto_version_flows: true,
        auto_version_scenes: false,
        auto_version_sheets: true
      }

      assert {:ok, current_project} =
               Projects.update_project(project, current_metadata)

      assert {:ok, _result} =
               ProjectSnapshotBuilder.restore_snapshot(project.id, snapshot)

      restored_project = Repo.get!(Project, project.id)

      assert restored_project.name == current_project.name
      assert restored_project.slug == current_project.slug
      assert restored_project.description == snapshot_metadata.description
      assert restored_project.project_type == snapshot_metadata.project_type
      assert restored_project.project_subtype == snapshot_metadata.project_subtype
      assert restored_project.project_type_other == snapshot_metadata.project_type_other
      assert restored_project.settings == snapshot_metadata.settings
      assert restored_project.auto_snapshots_enabled == snapshot_metadata.auto_snapshots_enabled
      assert restored_project.auto_version_flows == snapshot_metadata.auto_version_flows
      assert restored_project.auto_version_scenes == snapshot_metadata.auto_version_scenes
      assert restored_project.auto_version_sheets == snapshot_metadata.auto_version_sheets
    end

    test "preserves response speaker_sheet_id when restoring global localization", %{
      project: project
    } do
      source_language_fixture(project, %{locale_code: "en", name: "English"})
      language_fixture(project, %{locale_code: "es", name: "Spanish"})
      speaker = sheet_fixture(project, %{name: "Response speaker"})
      flow = flow_fixture(project, %{name: "Localized responses"})

      node =
        node_fixture(flow, %{
          type: "dialogue",
          data: %{
            "speaker_sheet_id" => speaker.id,
            "text" => "Choose",
            "responses" => [%{"id" => "continue", "text" => "Continue"}]
          }
        })

      response =
        Localization.get_text_by_source(
          "flow_node",
          node.id,
          "response.continue.text",
          "es"
        )

      assert response.content_role == "response"
      assert response.speaker_sheet_id == speaker.id

      assert {:ok, translated_response} =
               Localization.update_text(response, %{
                 translated_text: "Continuar",
                 status: "final"
               })

      snapshot = ProjectSnapshotBuilder.build_snapshot(project.id)

      assert {:ok, _response} =
               Localization.update_text(translated_response, %{
                 translated_text: "Seguir",
                 status: "draft"
               })

      assert {:ok, _result} =
               ProjectSnapshotBuilder.restore_snapshot(project.id, snapshot)

      restored_response =
        Localization.get_text_by_source(
          "flow_node",
          node.id,
          "response.continue.text",
          "es"
        )

      assert restored_response.translated_text == "Continuar"
      assert restored_response.status == "final"
      assert restored_response.content_role == "response"
      assert restored_response.speaker_sheet_id == speaker.id
    end
  end

  defp tree_state(roots) do
    Map.new(roots, fn {schema, id} ->
      root = Repo.get!(schema, id)
      {{schema, id}, {root.parent_id, root.position}}
    end)
  end

  defp snapshot_project_metadata do
    %{
      description: "Snapshot description",
      project_type: "other",
      project_subtype: nil,
      project_type_other: "Audio drama",
      settings: %{
        "theme" => %{"primary" => "#112233", "accent" => "#445566"},
        "workflow" => %{"strict" => true}
      },
      auto_snapshots_enabled: true,
      auto_version_flows: false,
      auto_version_scenes: true,
      auto_version_sheets: false
    }
  end

  defp stringify_keys(map) do
    Map.new(map, fn {key, value} -> {Atom.to_string(key), value} end)
  end
end
