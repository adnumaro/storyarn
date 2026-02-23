defmodule Storyarn.FlowsTest do
  use Storyarn.DataCase, async: true

  alias Storyarn.Flows

  import Storyarn.AccountsFixtures
  import Storyarn.FlowsFixtures
  import Storyarn.ProjectsFixtures

  describe "flows" do
    test "list_flows/1 returns all flows for a project" do
      user = user_fixture()
      project = project_fixture(user)

      flow1 = flow_fixture(project, %{name: "Flow 1"})
      flow2 = flow_fixture(project, %{name: "Flow 2"})

      flows = Flows.list_flows(project.id)

      assert length(flows) == 2
      assert Enum.any?(flows, &(&1.id == flow1.id))
      assert Enum.any?(flows, &(&1.id == flow2.id))
    end

    test "get_flow/2 returns flow with nodes and connections preloaded" do
      user = user_fixture()
      project = project_fixture(user)
      flow = flow_fixture(project)
      node = node_fixture(flow)

      result = Flows.get_flow(project.id, flow.id)

      assert result.id == flow.id
      # Flow auto-creates entry + exit nodes + we added one more manually
      assert length(result.nodes) == 3
      assert Enum.any?(result.nodes, &(&1.id == node.id))
    end

    test "get_flow/2 returns nil for non-existent flow" do
      user = user_fixture()
      project = project_fixture(user)

      assert Flows.get_flow(project.id, -1) == nil
    end

    test "create_flow/2 creates a flow" do
      user = user_fixture()
      project = project_fixture(user)

      {:ok, flow} = Flows.create_flow(project, %{name: "Test Flow", description: "A test"})

      assert flow.name == "Test Flow"
      assert flow.description == "A test"
      assert flow.project_id == project.id
    end

    test "create_flow/2 validates required fields" do
      user = user_fixture()
      project = project_fixture(user)

      {:error, changeset} = Flows.create_flow(project, %{})

      assert "can't be blank" in errors_on(changeset).name
    end

    test "update_flow/2 updates a flow" do
      user = user_fixture()
      project = project_fixture(user)
      flow = flow_fixture(project)

      {:ok, updated} = Flows.update_flow(flow, %{name: "Updated Name"})

      assert updated.name == "Updated Name"
    end

    test "delete_flow/1 soft-deletes flow (nodes and connections preserved for restore)" do
      user = user_fixture()
      project = project_fixture(user)
      flow = flow_fixture(project)
      node1 = node_fixture(flow)
      node2 = node_fixture(flow)
      _connection = connection_fixture(flow, node1, node2)

      {:ok, deleted_flow} = Flows.delete_flow(flow)

      # Flow should not appear in normal queries
      assert Flows.get_flow(project.id, flow.id) == nil
      assert flow.id not in Enum.map(Flows.list_flows(project.id), & &1.id)

      # But nodes and connections are preserved (for restore)
      # Flow has auto-created entry + exit nodes + 2 manually created nodes = 4 total
      assert length(Flows.list_nodes(flow.id)) == 4
      assert length(Flows.list_connections(flow.id)) == 1

      # Flow appears in deleted list
      assert deleted_flow.id in Enum.map(Flows.list_deleted_flows(project.id), & &1.id)
    end

    test "restore_flow/1 restores a soft-deleted flow" do
      user = user_fixture()
      project = project_fixture(user)
      flow = flow_fixture(project)
      _node = node_fixture(flow)

      {:ok, _} = Flows.delete_flow(flow)
      assert Flows.get_flow(project.id, flow.id) == nil

      # Restore the flow
      deleted_flow = Enum.find(Flows.list_deleted_flows(project.id), &(&1.id == flow.id))
      {:ok, restored} = Flows.restore_flow(deleted_flow)

      assert restored.deleted_at == nil
      assert Flows.get_flow(project.id, flow.id) != nil
    end

    test "hard_delete_flow/1 permanently deletes flow and cascades to nodes" do
      user = user_fixture()
      project = project_fixture(user)
      flow = flow_fixture(project)
      _node1 = node_fixture(flow)
      _node2 = node_fixture(flow)

      {:ok, _} = Flows.hard_delete_flow(flow)

      assert Flows.get_flow(project.id, flow.id) == nil
      assert Flows.list_nodes(flow.id) == []
    end

    test "set_main_flow/1 sets flow as main and unsets previous main" do
      user = user_fixture()
      project = project_fixture(user)
      flow1 = flow_fixture(project, %{is_main: true})
      flow2 = flow_fixture(project)

      {:ok, updated_flow2} = Flows.set_main_flow(flow2)

      assert updated_flow2.is_main == true

      # Reload flow1 to check it's no longer main
      updated_flow1 = Flows.get_flow(project.id, flow1.id)
      assert updated_flow1.is_main == false
    end

    test "search_flows/2 finds flows by name" do
      user = user_fixture()
      project = project_fixture(user)
      _flow1 = flow_fixture(project, %{name: "Main Story"})
      _flow2 = flow_fixture(project, %{name: "Side Quest"})

      results = Flows.search_flows(project.id, "Main")

      assert length(results) == 1
      assert Enum.at(results, 0).name == "Main Story"
    end

    test "search_flows/2 finds flows by shortcut" do
      user = user_fixture()
      project = project_fixture(user)
      {:ok, flow1} = Flows.create_flow(project, %{name: "Story Flow", shortcut: "story.main"})
      _flow2 = flow_fixture(project, %{name: "Other Flow"})

      # Search by shortcut prefix
      results = Flows.search_flows(project.id, "story.main")

      assert length(results) == 1
      assert Enum.at(results, 0).id == flow1.id
    end

    test "search_flows/2 returns recent flows when query is empty" do
      user = user_fixture()
      project = project_fixture(user)
      _flow1 = flow_fixture(project, %{name: "Flow 1"})
      _flow2 = flow_fixture(project, %{name: "Flow 2"})

      results = Flows.search_flows(project.id, "")

      assert length(results) == 2
    end

    test "search_flows/3 respects custom limit" do
      user = user_fixture()
      project = project_fixture(user)
      for i <- 1..10, do: flow_fixture(project, %{name: "Flow #{i}"})

      assert length(Flows.search_flows(project.id, "Flow", limit: 5)) == 5
      assert length(Flows.search_flows(project.id, "Flow", limit: 3)) == 3
    end

    test "search_flows/3 offset enables pagination" do
      user = user_fixture()
      project = project_fixture(user)

      for i <- 1..10,
          do: flow_fixture(project, %{name: "Flow #{String.pad_leading("#{i}", 2, "0")}"})

      page1 = Flows.search_flows(project.id, "Flow", limit: 5, offset: 0)
      page2 = Flows.search_flows(project.id, "Flow", limit: 5, offset: 5)

      assert length(page1) == 5
      assert length(page2) == 5

      page1_ids = MapSet.new(Enum.map(page1, & &1.id))
      page2_ids = MapSet.new(Enum.map(page2, & &1.id))
      assert MapSet.disjoint?(page1_ids, page2_ids)
    end

    test "search_flows/3 offset beyond results returns empty" do
      user = user_fixture()
      project = project_fixture(user)
      _flow = flow_fixture(project, %{name: "Only One"})

      assert Flows.search_flows(project.id, "Only", offset: 100) == []
    end

    test "search_flows/3 exclude_id filters out specified flow" do
      user = user_fixture()
      project = project_fixture(user)
      flow1 = flow_fixture(project, %{name: "Flow A"})
      _flow2 = flow_fixture(project, %{name: "Flow B"})

      results = Flows.search_flows(project.id, "Flow", exclude_id: flow1.id)
      ids = Enum.map(results, & &1.id)
      refute flow1.id in ids
    end

    test "search_flows/3 empty query with pagination" do
      user = user_fixture()
      project = project_fixture(user)
      for i <- 1..10, do: flow_fixture(project, %{name: "Flow #{i}"})

      page1 = Flows.search_flows(project.id, "", limit: 5, offset: 0)
      page2 = Flows.search_flows(project.id, "", limit: 5, offset: 5)

      assert length(page1) == 5
      assert length(page2) == 5
    end

    test "search_flows_deep/3 finds flows by node dialogue text" do
      user = user_fixture()
      project = project_fixture(user)
      flow = flow_fixture(project, %{name: "Hive Scene 7"})
      node_fixture(flow, %{data: %{"text" => "Annah whispers about the Hive."}})

      results = Flows.search_flows_deep(project.id, "Annah whispers")
      ids = Enum.map(results, & &1.id)
      assert flow.id in ids
    end

    test "search_flows_deep/3 finds flows by name AND node content" do
      user = user_fixture()
      project = project_fixture(user)
      flow_by_name = flow_fixture(project, %{name: "Annah Dialogue"})
      flow_by_content = flow_fixture(project, %{name: "Hive Scene"})
      node_fixture(flow_by_content, %{data: %{"text" => "Annah speaks quietly."}})
      _unrelated = flow_fixture(project, %{name: "Morte Intro"})

      results = Flows.search_flows_deep(project.id, "Annah")
      ids = Enum.map(results, & &1.id)
      assert flow_by_name.id in ids
      assert flow_by_content.id in ids
      refute Enum.any?(results, &(&1.name == "Morte Intro"))
    end

    test "search_flows_deep/3 finds flows by technical_id" do
      user = user_fixture()
      project = project_fixture(user)
      flow = flow_fixture(project, %{name: "Tech Flow"})
      node_fixture(flow, %{data: %{"text" => "Hello", "technical_id" => "dlg_annah_01"}})

      results = Flows.search_flows_deep(project.id, "dlg_annah_01")
      ids = Enum.map(results, & &1.id)
      assert flow.id in ids
    end

    test "search_flows_deep/3 finds flows by hub_id" do
      user = user_fixture()
      project = project_fixture(user)
      flow = flow_fixture(project, %{name: "Hub Flow"})
      node_fixture(flow, %{type: "hub", data: %{"hub_id" => "central-plaza", "label" => "Plaza"}})

      results = Flows.search_flows_deep(project.id, "central-plaza")
      ids = Enum.map(results, & &1.id)
      assert flow.id in ids
    end

    test "search_flows_deep/3 empty query falls back to regular search" do
      user = user_fixture()
      project = project_fixture(user)
      _flow = flow_fixture(project, %{name: "Any Flow"})

      results = Flows.search_flows_deep(project.id, "")
      assert results != []
    end

    test "search_flows_deep/3 respects limit and offset" do
      user = user_fixture()
      project = project_fixture(user)
      for i <- 1..5, do: flow_fixture(project, %{name: "Deep #{i}"})

      assert length(Flows.search_flows_deep(project.id, "Deep", limit: 2)) == 2
      assert length(Flows.search_flows_deep(project.id, "Deep", limit: 2, offset: 4)) == 1
    end
  end

  describe "nodes" do
    test "list_nodes/1 returns all nodes for a flow" do
      user = user_fixture()
      project = project_fixture(user)
      flow = flow_fixture(project)

      node1 = node_fixture(flow)
      node2 = node_fixture(flow)

      nodes = Flows.list_nodes(flow.id)

      # Flow has auto-created entry + exit nodes + 2 manually created nodes = 4 total
      assert length(nodes) == 4
      assert Enum.any?(nodes, &(&1.id == node1.id))
      assert Enum.any?(nodes, &(&1.id == node2.id))
      assert Enum.any?(nodes, &(&1.type == "entry"))
      assert Enum.any?(nodes, &(&1.type == "exit"))
    end

    test "create_node/2 creates a node" do
      user = user_fixture()
      project = project_fixture(user)
      flow = flow_fixture(project)

      {:ok, node} =
        Flows.create_node(flow, %{
          type: "dialogue",
          position_x: 50.0,
          position_y: 75.0,
          data: %{"speaker" => "NPC"}
        })

      assert node.type == "dialogue"
      assert node.position_x == 50.0
      assert node.position_y == 75.0
      assert node.data["speaker"] == "NPC"
    end

    test "create_node/2 validates node type" do
      user = user_fixture()
      project = project_fixture(user)
      flow = flow_fixture(project)

      {:error, changeset} = Flows.create_node(flow, %{type: "invalid_type"})

      assert "is invalid" in errors_on(changeset).type
    end

    test "flow auto-creates entry and exit nodes on creation" do
      user = user_fixture()
      project = project_fixture(user)
      {:ok, flow} = Flows.create_flow(project, %{name: "Test Flow"})

      nodes = Flows.list_nodes(flow.id)
      assert length(nodes) == 2

      entry_node = Enum.find(nodes, &(&1.type == "entry"))
      assert entry_node != nil
      assert entry_node.position_x == 100.0
      assert entry_node.position_y == 300.0

      exit_node = Enum.find(nodes, &(&1.type == "exit"))
      assert exit_node != nil
      assert exit_node.position_x == 500.0
      assert exit_node.position_y == 300.0
      assert exit_node.data["outcome_tags"] == []
      assert exit_node.data["outcome_color"] == "#22c55e"
      assert exit_node.data["exit_mode"] == "terminal"
      assert exit_node.data["technical_id"] == ""
    end

    test "cannot create duplicate entry node" do
      user = user_fixture()
      project = project_fixture(user)
      flow = flow_fixture(project)

      # Try to create another entry node (should fail)
      result = Flows.create_node(flow, %{type: "entry", position_x: 200.0, position_y: 200.0})

      assert result == {:error, :entry_node_exists}
    end

    test "cannot delete entry node" do
      user = user_fixture()
      project = project_fixture(user)
      flow = flow_fixture(project)

      entry_node = Flows.list_nodes(flow.id) |> Enum.find(&(&1.type == "entry"))

      result = Flows.delete_node(entry_node)

      assert result == {:error, :cannot_delete_entry_node}
    end

    test "can create multiple exit nodes" do
      user = user_fixture()
      project = project_fixture(user)
      flow = flow_fixture(project)

      {:ok, exit1} =
        Flows.create_node(flow, %{
          type: "exit",
          position_x: 500.0,
          position_y: 200.0,
          data: %{"label" => "Victory"}
        })

      {:ok, exit2} =
        Flows.create_node(flow, %{
          type: "exit",
          position_x: 500.0,
          position_y: 400.0,
          data: %{"label" => "Defeat"}
        })

      assert exit1.type == "exit"
      assert exit1.data["label"] == "Victory"
      assert exit2.type == "exit"
      assert exit2.data["label"] == "Defeat"

      # Verify both exist
      nodes = Flows.list_nodes(flow.id)
      exit_nodes = Enum.filter(nodes, &(&1.type == "exit"))
      # 1 auto-created + 2 manually created = 3 total
      assert length(exit_nodes) == 3
    end

    test "can delete exit node when multiple exits exist" do
      user = user_fixture()
      project = project_fixture(user)
      flow = flow_fixture(project)

      {:ok, exit_node} =
        Flows.create_node(flow, %{
          type: "exit",
          position_x: 500.0,
          position_y: 200.0,
          data: %{"label" => "End"}
        })

      {:ok, deleted, _meta} = Flows.delete_node(exit_node)

      assert deleted.id == exit_node.id
    end

    test "cannot delete the last exit node" do
      user = user_fixture()
      project = project_fixture(user)
      flow = flow_fixture(project)

      exit_node = Flows.list_nodes(flow.id) |> Enum.find(&(&1.type == "exit"))
      assert exit_node != nil

      result = Flows.delete_node(exit_node)
      assert result == {:error, :cannot_delete_last_exit}
    end

    test "can delete exit then last remaining exit is protected" do
      user = user_fixture()
      project = project_fixture(user)
      flow = flow_fixture(project)

      {:ok, exit2} =
        Flows.create_node(flow, %{
          type: "exit",
          position_x: 500.0,
          position_y: 400.0,
          data: %{"label" => "Alternate"}
        })

      assert {:ok, _, _} = Flows.delete_node(exit2)

      remaining_exit = Flows.list_nodes(flow.id) |> Enum.find(&(&1.type == "exit"))
      assert remaining_exit != nil
      assert {:error, :cannot_delete_last_exit} = Flows.delete_node(remaining_exit)
    end

    test "hub node with unique hub_id" do
      user = user_fixture()
      project = project_fixture(user)
      flow = flow_fixture(project)

      {:ok, hub} =
        Flows.create_node(flow, %{
          type: "hub",
          position_x: 300.0,
          position_y: 200.0,
          data: %{"hub_id" => "merchant_done", "color" => "blue"}
        })

      assert hub.type == "hub"
      assert hub.data["hub_id"] == "merchant_done"
      assert hub.data["color"] == "blue"
    end

    test "cannot create duplicate hub_id in same flow" do
      user = user_fixture()
      project = project_fixture(user)
      flow = flow_fixture(project)

      # Create first hub
      {:ok, _hub1} =
        Flows.create_node(flow, %{
          type: "hub",
          position_x: 300.0,
          position_y: 200.0,
          data: %{"hub_id" => "my_hub", "color" => "purple"}
        })

      # Try to create second hub with same hub_id
      result =
        Flows.create_node(flow, %{
          type: "hub",
          position_x: 500.0,
          position_y: 200.0,
          data: %{"hub_id" => "my_hub", "color" => "blue"}
        })

      assert result == {:error, :hub_id_not_unique}
    end

    test "can have same hub_id in different flows" do
      user = user_fixture()
      project = project_fixture(user)
      flow1 = flow_fixture(project, %{name: "Flow 1"})
      flow2 = flow_fixture(project, %{name: "Flow 2"})

      {:ok, hub1} =
        Flows.create_node(flow1, %{
          type: "hub",
          position_x: 300.0,
          position_y: 200.0,
          data: %{"hub_id" => "shared_name"}
        })

      {:ok, hub2} =
        Flows.create_node(flow2, %{
          type: "hub",
          position_x: 300.0,
          position_y: 200.0,
          data: %{"hub_id" => "shared_name"}
        })

      assert hub1.data["hub_id"] == "shared_name"
      assert hub2.data["hub_id"] == "shared_name"
    end

    test "cannot update hub_id to duplicate value" do
      user = user_fixture()
      project = project_fixture(user)
      flow = flow_fixture(project)

      # Create two hubs with different hub_ids
      {:ok, _hub1} =
        Flows.create_node(flow, %{
          type: "hub",
          position_x: 300.0,
          position_y: 200.0,
          data: %{"hub_id" => "hub_a"}
        })

      {:ok, hub2} =
        Flows.create_node(flow, %{
          type: "hub",
          position_x: 500.0,
          position_y: 200.0,
          data: %{"hub_id" => "hub_b"}
        })

      # Try to update hub2's hub_id to match hub1's
      result = Flows.update_node_data(hub2, %{"hub_id" => "hub_a"})

      assert result == {:error, :hub_id_not_unique}
    end

    test "list_hubs returns all hubs in a flow" do
      user = user_fixture()
      project = project_fixture(user)
      flow = flow_fixture(project)

      {:ok, _hub1} =
        Flows.create_node(flow, %{
          type: "hub",
          position_x: 300.0,
          position_y: 200.0,
          data: %{"hub_id" => "alpha"}
        })

      {:ok, _hub2} =
        Flows.create_node(flow, %{
          type: "hub",
          position_x: 500.0,
          position_y: 200.0,
          data: %{"hub_id" => "beta"}
        })

      hubs = Flows.list_hubs(flow.id)

      assert length(hubs) == 2
      assert Enum.any?(hubs, &(&1.hub_id == "alpha"))
      assert Enum.any?(hubs, &(&1.hub_id == "beta"))
    end

    test "jump node can be created with target_hub_id" do
      user = user_fixture()
      project = project_fixture(user)
      flow = flow_fixture(project)

      # Create a hub first
      {:ok, _hub} =
        Flows.create_node(flow, %{
          type: "hub",
          position_x: 300.0,
          position_y: 200.0,
          data: %{"hub_id" => "meeting_point", "color" => "blue"}
        })

      # Create a jump node targeting the hub
      {:ok, jump} =
        Flows.create_node(flow, %{
          type: "jump",
          position_x: 500.0,
          position_y: 200.0,
          data: %{"target_hub_id" => "meeting_point"}
        })

      assert jump.type == "jump"
      assert jump.data["target_hub_id"] == "meeting_point"
    end

    test "jump node can update target_hub_id" do
      user = user_fixture()
      project = project_fixture(user)
      flow = flow_fixture(project)

      # Create two hubs
      {:ok, _hub1} =
        Flows.create_node(flow, %{
          type: "hub",
          position_x: 300.0,
          position_y: 200.0,
          data: %{"hub_id" => "hub_a"}
        })

      {:ok, _hub2} =
        Flows.create_node(flow, %{
          type: "hub",
          position_x: 400.0,
          position_y: 200.0,
          data: %{"hub_id" => "hub_b"}
        })

      # Create a jump node
      {:ok, jump} =
        Flows.create_node(flow, %{
          type: "jump",
          position_x: 500.0,
          position_y: 200.0,
          data: %{"target_hub_id" => "hub_a"}
        })

      # Update to target different hub
      {:ok, updated_jump, _meta} = Flows.update_node_data(jump, %{"target_hub_id" => "hub_b"})

      assert updated_jump.data["target_hub_id"] == "hub_b"
    end

    test "update_node_position/2 updates only position" do
      user = user_fixture()
      project = project_fixture(user)
      flow = flow_fixture(project)
      node = node_fixture(flow)

      {:ok, updated} = Flows.update_node_position(node, %{position_x: 200.0, position_y: 300.0})

      assert updated.position_x == 200.0
      assert updated.position_y == 300.0
    end

    test "update_node_data/2 updates only data" do
      user = user_fixture()
      project = project_fixture(user)
      flow = flow_fixture(project)
      node = node_fixture(flow)

      {:ok, updated, _meta} =
        Flows.update_node_data(node, %{"speaker" => "Hero", "text" => "Hi!"})

      assert updated.data["speaker"] == "Hero"
      assert updated.data["text"] == "Hi!"
    end

    test "delete_node/1 deletes node and its connections" do
      user = user_fixture()
      project = project_fixture(user)
      flow = flow_fixture(project)
      node1 = node_fixture(flow)
      node2 = node_fixture(flow)
      _connection = connection_fixture(flow, node1, node2)

      {:ok, _, _meta} = Flows.delete_node(node1)

      assert Flows.get_node(flow.id, node1.id) == nil
      assert Flows.list_connections(flow.id) == []
    end

    test "count_nodes_by_type/1 returns node counts" do
      user = user_fixture()
      project = project_fixture(user)
      flow = flow_fixture(project)

      node_fixture(flow, %{type: "dialogue"})
      node_fixture(flow, %{type: "dialogue"})
      node_fixture(flow, %{type: "condition"})

      counts = Flows.count_nodes_by_type(flow.id)

      assert counts["dialogue"] == 2
      assert counts["condition"] == 1
    end

    test "batch_update_positions/2 updates positions for multiple nodes" do
      user = user_fixture()
      project = project_fixture(user)
      flow = flow_fixture(project)
      node1 = node_fixture(flow, %{position_x: 0.0, position_y: 0.0})
      node2 = node_fixture(flow, %{position_x: 0.0, position_y: 0.0})

      positions = [
        %{id: node1.id, position_x: 100.0, position_y: 200.0},
        %{id: node2.id, position_x: 300.0, position_y: 400.0}
      ]

      assert {:ok, 2} = Flows.batch_update_positions(flow.id, positions)

      updated1 = Flows.get_node!(flow.id, node1.id)
      assert updated1.position_x == 100.0
      assert updated1.position_y == 200.0

      updated2 = Flows.get_node!(flow.id, node2.id)
      assert updated2.position_x == 300.0
      assert updated2.position_y == 400.0
    end

    test "batch_update_positions/2 ignores nodes from a different flow" do
      user = user_fixture()
      project = project_fixture(user)
      flow = flow_fixture(project)
      other_flow = flow_fixture(project, %{name: "Other"})
      other_node = node_fixture(other_flow, %{position_x: 0.0, position_y: 0.0})

      positions = [
        %{id: other_node.id, position_x: 999.0, position_y: 999.0}
      ]

      assert {:ok, 1} = Flows.batch_update_positions(flow.id, positions)

      unchanged = Flows.get_node!(other_flow.id, other_node.id)
      assert unchanged.position_x == 0.0
      assert unchanged.position_y == 0.0
    end

    test "batch_update_positions/2 handles empty positions list" do
      user = user_fixture()
      project = project_fixture(user)
      flow = flow_fixture(project)

      assert {:ok, 0} = Flows.batch_update_positions(flow.id, [])
    end
  end

  describe "connections" do
    test "create_connection/4 creates a connection" do
      user = user_fixture()
      project = project_fixture(user)
      flow = flow_fixture(project)
      source = node_fixture(flow)
      target = node_fixture(flow)

      {:ok, connection} =
        Flows.create_connection(flow, source, target, %{
          source_pin: "output",
          target_pin: "input"
        })

      assert connection.source_node_id == source.id
      assert connection.target_node_id == target.id
      assert connection.source_pin == "output"
      assert connection.target_pin == "input"
    end

    test "create_connection/4 prevents self-connection" do
      user = user_fixture()
      project = project_fixture(user)
      flow = flow_fixture(project)
      node = node_fixture(flow)

      {:error, changeset} =
        Flows.create_connection(flow, node, node, %{
          source_pin: "output",
          target_pin: "input"
        })

      assert "cannot connect a node to itself" in errors_on(changeset).target_node_id
    end

    test "create_connection/4 validates required fields" do
      user = user_fixture()
      project = project_fixture(user)
      flow = flow_fixture(project)
      source = node_fixture(flow)
      target = node_fixture(flow)

      {:error, changeset} = Flows.create_connection(flow, source, target, %{})

      assert "can't be blank" in errors_on(changeset).source_pin
      assert "can't be blank" in errors_on(changeset).target_pin
    end

    test "update_connection/2 updates connection properties" do
      user = user_fixture()
      project = project_fixture(user)
      flow = flow_fixture(project)
      source = node_fixture(flow)
      target = node_fixture(flow)
      connection = connection_fixture(flow, source, target)

      {:ok, updated} =
        Flows.update_connection(connection, %{label: "Choice 1"})

      assert updated.label == "Choice 1"
    end

    test "delete_connection_by_nodes/3 deletes connections between nodes" do
      user = user_fixture()
      project = project_fixture(user)
      flow = flow_fixture(project)
      source = node_fixture(flow)
      target = node_fixture(flow)
      _connection = connection_fixture(flow, source, target)

      {count, _} = Flows.delete_connection_by_nodes(flow.id, source.id, target.id)

      assert count == 1
      assert Flows.list_connections(flow.id) == []
    end

    test "delete_connection_by_pins/5 deletes only the matching pin pair" do
      user = user_fixture()
      project = project_fixture(user)
      flow = flow_fixture(project)
      source = node_fixture(flow)
      target = node_fixture(flow)

      _conn1 = connection_fixture(flow, source, target, %{source_pin: "out1", target_pin: "in"})
      _conn2 = connection_fixture(flow, source, target, %{source_pin: "out2", target_pin: "in"})

      {count, _} = Flows.delete_connection_by_pins(flow.id, source.id, "out1", target.id, "in")

      assert count == 1
      remaining = Flows.list_connections(flow.id)
      assert length(remaining) == 1
      assert hd(remaining).source_pin == "out2"
    end

    test "cannot create connection from exit node" do
      user = user_fixture()
      project = project_fixture(user)
      flow = flow_fixture(project)

      exit_node = Flows.list_nodes(flow.id) |> Enum.find(&(&1.type == "exit"))
      target = node_fixture(flow)

      result =
        Flows.create_connection_with_attrs(flow, %{
          source_node_id: exit_node.id,
          target_node_id: target.id,
          source_pin: "output",
          target_pin: "input"
        })

      assert result == {:error, :exit_has_no_outputs}
    end

    test "cannot create connection to entry node" do
      user = user_fixture()
      project = project_fixture(user)
      flow = flow_fixture(project)

      entry_node = Flows.list_nodes(flow.id) |> Enum.find(&(&1.type == "entry"))
      source = node_fixture(flow)

      result =
        Flows.create_connection_with_attrs(flow, %{
          source_node_id: source.id,
          target_node_id: entry_node.id,
          source_pin: "output",
          target_pin: "input"
        })

      assert result == {:error, :entry_has_no_inputs}
    end

    test "cannot create connection from jump node" do
      user = user_fixture()
      project = project_fixture(user)
      flow = flow_fixture(project)

      {:ok, jump} =
        Flows.create_node(flow, %{
          type: "jump",
          position_x: 300.0,
          position_y: 200.0,
          data: %{"target_hub_id" => ""}
        })

      target = node_fixture(flow)

      result =
        Flows.create_connection_with_attrs(flow, %{
          source_node_id: jump.id,
          target_node_id: target.id,
          source_pin: "output",
          target_pin: "input"
        })

      assert result == {:error, :jump_has_no_outputs}
    end

    test "get_outgoing_connections/1 returns connections from a node" do
      user = user_fixture()
      project = project_fixture(user)
      flow = flow_fixture(project)
      source = node_fixture(flow)
      target1 = node_fixture(flow)
      target2 = node_fixture(flow)

      connection_fixture(flow, source, target1, %{source_pin: "out1", target_pin: "in"})
      connection_fixture(flow, source, target2, %{source_pin: "out2", target_pin: "in"})

      connections = Flows.get_outgoing_connections(source.id)

      assert length(connections) == 2
    end

    test "get_incoming_connections/1 returns connections to a node" do
      user = user_fixture()
      project = project_fixture(user)
      flow = flow_fixture(project)
      source1 = node_fixture(flow)
      source2 = node_fixture(flow)
      target = node_fixture(flow)

      connection_fixture(flow, source1, target, %{source_pin: "out", target_pin: "in1"})
      connection_fixture(flow, source2, target, %{source_pin: "out", target_pin: "in2"})

      connections = Flows.get_incoming_connections(target.id)

      assert length(connections) == 2
    end
  end

  describe "serialization" do
    test "serialize_for_canvas/1 returns flow data in Rete.js format" do
      user = user_fixture()
      project = project_fixture(user)
      flow = flow_fixture(project, %{name: "Test Flow"})
      node1 = node_fixture(flow, %{position_x: 100.0, position_y: 200.0})
      node2 = node_fixture(flow, %{position_x: 300.0, position_y: 200.0})
      _connection = connection_fixture(flow, node1, node2)

      # Reload flow with associations
      flow = Flows.get_flow!(project.id, flow.id)
      serialized = Flows.serialize_for_canvas(flow)

      assert serialized.id == flow.id
      assert serialized.name == "Test Flow"
      # Flow has auto-created entry + exit nodes + 2 manually created nodes = 4 total
      assert length(serialized.nodes) == 4
      assert length(serialized.connections) == 1

      first_node = Enum.find(serialized.nodes, &(&1.id == node1.id))
      assert first_node.position.x == 100.0
      assert first_node.position.y == 200.0

      first_connection = Enum.at(serialized.connections, 0)
      assert first_connection.source_node_id == node1.id
      assert first_connection.target_node_id == node2.id
    end
  end

  describe "tree operations" do
    test "create_flow/2 auto-assigns position" do
      user = user_fixture()
      project = project_fixture(user)

      {:ok, flow1} = Flows.create_flow(project, %{name: "First"})
      {:ok, flow2} = Flows.create_flow(project, %{name: "Second"})
      {:ok, flow3} = Flows.create_flow(project, %{name: "Third"})

      assert flow1.position == 0
      assert flow2.position == 1
      assert flow3.position == 2
    end

    test "create_flow/2 with parent_id creates nested flow" do
      user = user_fixture()
      project = project_fixture(user)

      {:ok, parent} = Flows.create_flow(project, %{name: "Act 1"})
      {:ok, child} = Flows.create_flow(project, %{name: "Scene 1", parent_id: parent.id})

      assert child.parent_id == parent.id
      assert child.position == 0
    end

    test "list_flows_tree/1 returns hierarchical structure" do
      user = user_fixture()
      project = project_fixture(user)

      {:ok, parent} = Flows.create_flow(project, %{name: "Act 1"})
      {:ok, _child1} = Flows.create_flow(project, %{name: "Scene 1", parent_id: parent.id})
      {:ok, _child2} = Flows.create_flow(project, %{name: "Scene 2", parent_id: parent.id})
      {:ok, _root_flow} = Flows.create_flow(project, %{name: "Prologue"})

      tree = Flows.list_flows_tree(project.id)

      # Root level should have Act 1 and Prologue
      assert length(tree) == 2

      parent_in_tree = Enum.find(tree, &(&1.name == "Act 1"))
      assert parent_in_tree != nil
      assert length(parent_in_tree.children) == 2
    end

    test "list_flows_by_parent/2 lists flows at specific level" do
      user = user_fixture()
      project = project_fixture(user)

      {:ok, parent} = Flows.create_flow(project, %{name: "Act 1"})
      {:ok, child1} = Flows.create_flow(project, %{name: "Scene 1", parent_id: parent.id})
      {:ok, child2} = Flows.create_flow(project, %{name: "Scene 2", parent_id: parent.id})

      # List children of parent
      children = Flows.list_flows_by_parent(project.id, parent.id)
      assert length(children) == 2
      assert Enum.any?(children, &(&1.id == child1.id))
      assert Enum.any?(children, &(&1.id == child2.id))

      # List root level
      root = Flows.list_flows_by_parent(project.id, nil)
      assert length(root) == 1
      assert Enum.at(root, 0).id == parent.id
    end

    test "reorder_flows/3 reorders flows within parent" do
      user = user_fixture()
      project = project_fixture(user)

      {:ok, flow1} = Flows.create_flow(project, %{name: "First"})
      {:ok, flow2} = Flows.create_flow(project, %{name: "Second"})
      {:ok, flow3} = Flows.create_flow(project, %{name: "Third"})

      # Reorder: Third, First, Second
      {:ok, reordered} = Flows.reorder_flows(project.id, nil, [flow3.id, flow1.id, flow2.id])

      positions = Enum.map(reordered, &{&1.id, &1.position})
      assert {flow3.id, 0} in positions
      assert {flow1.id, 1} in positions
      assert {flow2.id, 2} in positions
    end

    test "move_flow_to_position/3 moves flow to new parent" do
      user = user_fixture()
      project = project_fixture(user)

      {:ok, parent} = Flows.create_flow(project, %{name: "Act 1"})
      {:ok, flow} = Flows.create_flow(project, %{name: "Scene"})

      # Move flow into parent
      {:ok, moved} = Flows.move_flow_to_position(flow, parent.id, 0)

      assert moved.parent_id == parent.id
      assert moved.position == 0
    end

    test "delete_flow/1 cascades soft delete to children" do
      user = user_fixture()
      project = project_fixture(user)

      {:ok, parent} = Flows.create_flow(project, %{name: "Act 1"})
      {:ok, child} = Flows.create_flow(project, %{name: "Scene 1", parent_id: parent.id})

      {:ok, _} = Flows.delete_flow(parent)

      # Both parent and child should be soft-deleted
      assert Flows.get_flow(project.id, parent.id) == nil
      assert Flows.get_flow(project.id, child.id) == nil

      # Both should appear in deleted list
      deleted = Flows.list_deleted_flows(project.id)
      deleted_ids = Enum.map(deleted, & &1.id)
      assert parent.id in deleted_ids
      assert child.id in deleted_ids
    end

    test "search_flows/2 finds all flows including those with children" do
      user = user_fixture()
      project = project_fixture(user)

      {:ok, parent} = Flows.create_flow(project, %{name: "Test Parent"})
      {:ok, _child} = Flows.create_flow(project, %{name: "Test Child", parent_id: parent.id})

      results = Flows.search_flows(project.id, "Test")

      # Both flows should be returned (any flow can have children AND content)
      assert length(results) == 2
      assert Enum.any?(results, &(&1.id == parent.id))
    end
  end

  describe "list_dialogue_nodes_by_speaker/2" do
    import Storyarn.SheetsFixtures

    test "returns dialogue nodes with matching speaker_sheet_id" do
      user = user_fixture()
      project = project_fixture(user)
      sheet = sheet_fixture(project)
      flow = flow_fixture(project)

      node =
        node_fixture(flow, %{
          type: "dialogue",
          data: %{"speaker_sheet_id" => sheet.id, "text" => "Hello"}
        })

      results = Flows.list_dialogue_nodes_by_speaker(project.id, sheet.id)

      assert length(results) == 1
      assert hd(results).id == node.id
    end

    test "preloads flow association" do
      user = user_fixture()
      project = project_fixture(user)
      sheet = sheet_fixture(project)
      flow = flow_fixture(project, %{name: "My Flow"})

      node_fixture(flow, %{
        type: "dialogue",
        data: %{"speaker_sheet_id" => sheet.id, "text" => "Hi"}
      })

      [result] = Flows.list_dialogue_nodes_by_speaker(project.id, sheet.id)

      assert result.flow.id == flow.id
      assert result.flow.name == "My Flow"
    end

    test "excludes soft-deleted nodes" do
      user = user_fixture()
      project = project_fixture(user)
      sheet = sheet_fixture(project)
      flow = flow_fixture(project)

      node =
        node_fixture(flow, %{
          type: "dialogue",
          data: %{"speaker_sheet_id" => sheet.id, "text" => "Gone"}
        })

      Flows.delete_node(node)

      assert Flows.list_dialogue_nodes_by_speaker(project.id, sheet.id) == []
    end

    test "excludes nodes from other projects" do
      user = user_fixture()
      project1 = project_fixture(user)
      project2 = project_fixture(user)
      sheet = sheet_fixture(project1)
      flow = flow_fixture(project2)

      node_fixture(flow, %{
        type: "dialogue",
        data: %{"speaker_sheet_id" => sheet.id, "text" => "Wrong project"}
      })

      assert Flows.list_dialogue_nodes_by_speaker(project1.id, sheet.id) == []
    end

    test "excludes non-dialogue node types" do
      user = user_fixture()
      project = project_fixture(user)
      sheet = sheet_fixture(project)
      flow = flow_fixture(project)

      node_fixture(flow, %{
        type: "condition",
        data: %{"speaker_sheet_id" => sheet.id, "expression" => ""}
      })

      assert Flows.list_dialogue_nodes_by_speaker(project.id, sheet.id) == []
    end

    test "returns empty list when no matches" do
      user = user_fixture()
      project = project_fixture(user)
      sheet = sheet_fixture(project)

      assert Flows.list_dialogue_nodes_by_speaker(project.id, sheet.id) == []
    end
  end
end
