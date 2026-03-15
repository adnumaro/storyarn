defmodule Storyarn.Versioning.Builders.FlowBuilderTest do
  use Storyarn.DataCase, async: true

  alias Storyarn.Versioning.Builders.FlowBuilder

  import Storyarn.AccountsFixtures
  import Storyarn.ProjectsFixtures
  import Storyarn.FlowsFixtures

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
      n1 = node_fixture(flow, %{type: "dialogue", position_x: 100.0, position_y: 100.0})
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
      Storyarn.Flows.delete_node(node)

      snapshot = FlowBuilder.build_snapshot(flow)
      # The dialogue node should be excluded
      assert Enum.all?(snapshot["nodes"], fn n -> n["type"] != "dialogue" end)
    end
  end

  describe "restore_snapshot/3" do
    test "restores flow with nodes and connections", %{flow: flow} do
      n1 = node_fixture(flow, %{type: "dialogue", position_x: 100.0, position_y: 100.0})
      n2 = node_fixture(flow, %{type: "hub", position_x: 200.0, position_y: 100.0})
      _conn = connection_fixture(flow, n1, n2)

      snapshot = FlowBuilder.build_snapshot(flow)

      # Modify the flow
      {:ok, modified_flow} = Storyarn.Flows.update_flow(flow, %{name: "Modified"})

      # Restore
      {:ok, restored} = FlowBuilder.restore_snapshot(modified_flow, snapshot)

      assert restored.name == flow.name

      restored = Storyarn.Repo.preload(restored, [:nodes, :connections], force: true)
      # Should have the same number of non-deleted nodes
      active_nodes = Enum.reject(restored.nodes, &(&1.deleted_at != nil))
      assert length(active_nodes) == length(snapshot["nodes"])
      assert length(restored.connections) == 1
    end
  end

  describe "instantiate_snapshot/3" do
    test "materializes a new flow and remaps connection node ids", %{project: project, flow: flow} do
      node_a = node_fixture(flow, %{type: "dialogue", position_x: 100.0, position_y: 100.0})
      node_b = node_fixture(flow, %{type: "hub", position_x: 200.0, position_y: 100.0})
      connection = connection_fixture(flow, node_a, node_b)

      snapshot = FlowBuilder.build_snapshot(flow)

      assert {:ok, materialized, id_maps} =
               FlowBuilder.instantiate_snapshot(project.id, snapshot,
                 reset_shortcut: true,
                 position: 11
               )

      assert materialized.id != flow.id
      assert materialized.draft_id == nil
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

      types_and_ids = Enum.map(refs, &{&1.type, &1.id}) |> Enum.sort()

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
end
