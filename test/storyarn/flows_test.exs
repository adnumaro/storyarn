defmodule Storyarn.FlowsTest do
  use Storyarn.DataCase

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
      assert length(result.nodes) == 1
      assert Enum.at(result.nodes, 0).id == node.id
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

    test "delete_flow/1 deletes flow and cascades to nodes and connections" do
      user = user_fixture()
      project = project_fixture(user)
      flow = flow_fixture(project)
      node1 = node_fixture(flow)
      node2 = node_fixture(flow)
      _connection = connection_fixture(flow, node1, node2)

      {:ok, _} = Flows.delete_flow(flow)

      assert Flows.get_flow(project.id, flow.id) == nil
      assert Flows.list_nodes(flow.id) == []
      assert Flows.list_connections(flow.id) == []
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
  end

  describe "nodes" do
    test "list_nodes/1 returns all nodes for a flow" do
      user = user_fixture()
      project = project_fixture(user)
      flow = flow_fixture(project)

      node1 = node_fixture(flow)
      node2 = node_fixture(flow)

      nodes = Flows.list_nodes(flow.id)

      assert length(nodes) == 2
      assert Enum.any?(nodes, &(&1.id == node1.id))
      assert Enum.any?(nodes, &(&1.id == node2.id))
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

      {:ok, updated} = Flows.update_node_data(node, %{"speaker" => "Hero", "text" => "Hi!"})

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

      {:ok, _} = Flows.delete_node(node1)

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
        Flows.update_connection(connection, %{label: "Choice 1", condition: "score > 10"})

      assert updated.label == "Choice 1"
      assert updated.condition == "score > 10"
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
      assert length(serialized.nodes) == 2
      assert length(serialized.connections) == 1

      first_node = Enum.find(serialized.nodes, &(&1.id == node1.id))
      assert first_node.position.x == 100.0
      assert first_node.position.y == 200.0

      first_connection = Enum.at(serialized.connections, 0)
      assert first_connection.source_node_id == node1.id
      assert first_connection.target_node_id == node2.id
    end
  end
end
