defmodule Storyarn.Flows.ConnectionCrudTest do
  use Storyarn.DataCase, async: true

  alias Storyarn.Flows

  import Storyarn.AccountsFixtures
  import Storyarn.FlowsFixtures
  import Storyarn.ProjectsFixtures

  # ===========================================================================
  # Setup helpers
  # ===========================================================================

  defp create_project_and_flow(_context \\ %{}) do
    user = user_fixture()
    project = project_fixture(user)
    flow = flow_fixture(project)
    %{user: user, project: project, flow: flow}
  end

  defp get_entry_node(flow) do
    Flows.list_nodes(flow.id) |> Enum.find(&(&1.type == "entry"))
  end

  defp get_exit_node(flow) do
    Flows.list_nodes(flow.id) |> Enum.find(&(&1.type == "exit"))
  end

  # ===========================================================================
  # list_connections/1
  # ===========================================================================

  describe "list_connections/1" do
    test "returns empty list for flow with no connections" do
      %{flow: flow} = create_project_and_flow()
      assert Flows.list_connections(flow.id) == []
    end

    test "returns connections for a flow" do
      %{flow: flow} = create_project_and_flow()
      entry = get_entry_node(flow)
      dialogue = node_fixture(flow, %{type: "dialogue"})
      _conn = connection_fixture(flow, entry, dialogue)

      connections = Flows.list_connections(flow.id)
      assert length(connections) == 1

      [conn] = connections
      assert conn.source_node_id == entry.id
      assert conn.target_node_id == dialogue.id
    end

    test "preloads source_node and target_node" do
      %{flow: flow} = create_project_and_flow()
      entry = get_entry_node(flow)
      dialogue = node_fixture(flow, %{type: "dialogue"})
      _conn = connection_fixture(flow, entry, dialogue)

      [conn] = Flows.list_connections(flow.id)
      assert conn.source_node.id == entry.id
      assert conn.target_node.id == dialogue.id
    end

    test "excludes connections where source node is soft-deleted" do
      %{flow: flow} = create_project_and_flow()
      dialogue1 = node_fixture(flow, %{type: "dialogue"})
      dialogue2 = node_fixture(flow, %{type: "dialogue"})
      _conn = connection_fixture(flow, dialogue1, dialogue2)

      # Soft-delete the source node
      Flows.delete_node(dialogue1)

      connections = Flows.list_connections(flow.id)
      assert connections == []
    end

    test "excludes connections where target node is soft-deleted" do
      %{flow: flow} = create_project_and_flow()
      dialogue1 = node_fixture(flow, %{type: "dialogue"})
      dialogue2 = node_fixture(flow, %{type: "dialogue"})
      _conn = connection_fixture(flow, dialogue1, dialogue2)

      Flows.delete_node(dialogue2)

      connections = Flows.list_connections(flow.id)
      assert connections == []
    end

    test "orders connections by inserted_at" do
      %{flow: flow} = create_project_and_flow()
      entry = get_entry_node(flow)
      d1 = node_fixture(flow, %{type: "dialogue"})
      d2 = node_fixture(flow, %{type: "dialogue"})

      conn1 = connection_fixture(flow, entry, d1, %{source_pin: "output"})
      conn2 = connection_fixture(flow, d1, d2, %{source_pin: "output"})

      connections = Flows.list_connections(flow.id)
      ids = Enum.map(connections, & &1.id)
      assert ids == [conn1.id, conn2.id]
    end

    test "does not return connections from another flow" do
      %{project: project} = create_project_and_flow()
      flow2 = flow_fixture(project)
      entry2 = get_entry_node(flow2)
      dialogue2 = node_fixture(flow2, %{type: "dialogue"})
      _conn = connection_fixture(flow2, entry2, dialogue2)

      %{flow: flow1} = create_project_and_flow()
      assert Flows.list_connections(flow1.id) == []
    end
  end

  # ===========================================================================
  # get_connection/2
  # ===========================================================================

  describe "get_connection/2" do
    test "returns connection by flow_id and connection_id" do
      %{flow: flow} = create_project_and_flow()
      entry = get_entry_node(flow)
      dialogue = node_fixture(flow, %{type: "dialogue"})
      conn = connection_fixture(flow, entry, dialogue)

      result = Flows.get_connection(flow.id, conn.id)
      assert result.id == conn.id
      assert result.source_node_id == entry.id
      assert result.target_node_id == dialogue.id
    end

    test "preloads source_node and target_node" do
      %{flow: flow} = create_project_and_flow()
      entry = get_entry_node(flow)
      dialogue = node_fixture(flow, %{type: "dialogue"})
      conn = connection_fixture(flow, entry, dialogue)

      result = Flows.get_connection(flow.id, conn.id)
      assert result.source_node.id == entry.id
      assert result.target_node.id == dialogue.id
    end

    test "returns nil when connection does not exist" do
      %{flow: flow} = create_project_and_flow()
      assert Flows.get_connection(flow.id, 0) == nil
    end

    test "returns nil when connection belongs to different flow" do
      %{project: project, flow: flow1} = create_project_and_flow()
      flow2 = flow_fixture(project)
      entry2 = get_entry_node(flow2)
      dialogue2 = node_fixture(flow2, %{type: "dialogue"})
      conn = connection_fixture(flow2, entry2, dialogue2)

      assert Flows.get_connection(flow1.id, conn.id) == nil
    end
  end

  # ===========================================================================
  # get_connection!/2
  # ===========================================================================

  describe "get_connection!/2" do
    test "returns connection when it exists" do
      %{flow: flow} = create_project_and_flow()
      entry = get_entry_node(flow)
      dialogue = node_fixture(flow, %{type: "dialogue"})
      conn = connection_fixture(flow, entry, dialogue)

      result = Flows.get_connection!(flow.id, conn.id)
      assert result.id == conn.id
    end

    test "raises Ecto.NoResultsError when not found" do
      %{flow: flow} = create_project_and_flow()

      assert_raise Ecto.NoResultsError, fn ->
        Flows.get_connection!(flow.id, 0)
      end
    end
  end

  # ===========================================================================
  # get_connection_by_id!/1
  # ===========================================================================

  describe "get_connection_by_id!/1" do
    test "returns connection by ID without flow scoping" do
      %{flow: flow} = create_project_and_flow()
      entry = get_entry_node(flow)
      dialogue = node_fixture(flow, %{type: "dialogue"})
      conn = connection_fixture(flow, entry, dialogue)

      result = Flows.get_connection_by_id!(conn.id)
      assert result.id == conn.id
    end

    test "raises Ecto.NoResultsError when not found" do
      assert_raise Ecto.NoResultsError, fn ->
        Flows.get_connection_by_id!(0)
      end
    end
  end

  # ===========================================================================
  # create_connection/4 (with source_node, target_node structs)
  # ===========================================================================

  describe "create_connection/4" do
    test "creates a connection between two nodes" do
      %{flow: flow} = create_project_and_flow()
      entry = get_entry_node(flow)
      dialogue = node_fixture(flow, %{type: "dialogue"})

      {:ok, conn} =
        Flows.create_connection(flow, entry, dialogue, %{
          source_pin: "output",
          target_pin: "input"
        })

      assert conn.source_node_id == entry.id
      assert conn.target_node_id == dialogue.id
      assert conn.source_pin == "output"
      assert conn.target_pin == "input"
      assert conn.flow_id == flow.id
    end

    test "creates a connection with a label" do
      %{flow: flow} = create_project_and_flow()
      entry = get_entry_node(flow)
      dialogue = node_fixture(flow, %{type: "dialogue"})

      {:ok, conn} =
        Flows.create_connection(flow, entry, dialogue, %{
          source_pin: "output",
          target_pin: "input",
          label: "True"
        })

      assert conn.label == "True"
    end

    test "fails when source_pin is missing" do
      %{flow: flow} = create_project_and_flow()
      entry = get_entry_node(flow)
      dialogue = node_fixture(flow, %{type: "dialogue"})

      {:error, changeset} =
        Flows.create_connection(flow, entry, dialogue, %{target_pin: "input"})

      assert errors_on(changeset).source_pin
    end

    test "fails when target_pin is missing" do
      %{flow: flow} = create_project_and_flow()
      entry = get_entry_node(flow)
      dialogue = node_fixture(flow, %{type: "dialogue"})

      {:error, changeset} =
        Flows.create_connection(flow, entry, dialogue, %{source_pin: "output"})

      assert errors_on(changeset).target_pin
    end

    test "fails with self-connection (same node)" do
      %{flow: flow} = create_project_and_flow()
      dialogue = node_fixture(flow, %{type: "dialogue"})

      {:error, changeset} =
        Flows.create_connection(flow, dialogue, dialogue, %{
          source_pin: "output",
          target_pin: "input"
        })

      assert errors_on(changeset).target_node_id
    end

    test "prevents duplicate connections (same nodes + same pins)" do
      %{flow: flow} = create_project_and_flow()
      entry = get_entry_node(flow)
      dialogue = node_fixture(flow, %{type: "dialogue"})

      {:ok, _conn} =
        Flows.create_connection(flow, entry, dialogue, %{
          source_pin: "output",
          target_pin: "input"
        })

      {:error, changeset} =
        Flows.create_connection(flow, entry, dialogue, %{
          source_pin: "output",
          target_pin: "input"
        })

      assert errors_on(changeset).source_node_id
    end

    test "allows multiple connections between same nodes on different pins" do
      %{flow: flow} = create_project_and_flow()
      dialogue = node_fixture(flow, %{type: "dialogue"})
      d2 = node_fixture(flow, %{type: "dialogue"})

      {:ok, conn1} =
        Flows.create_connection(flow, dialogue, d2, %{
          source_pin: "response-1",
          target_pin: "input"
        })

      {:ok, conn2} =
        Flows.create_connection(flow, dialogue, d2, %{
          source_pin: "response-2",
          target_pin: "input"
        })

      assert conn1.id != conn2.id
    end
  end

  # ===========================================================================
  # create_connection_with_attrs/2 (2-arity via facade)
  # ===========================================================================

  describe "create_connection_with_attrs/2" do
    test "creates connection using node IDs in attrs" do
      %{flow: flow} = create_project_and_flow()
      entry = get_entry_node(flow)
      dialogue = node_fixture(flow, %{type: "dialogue"})

      {:ok, conn} =
        Flows.create_connection_with_attrs(flow, %{
          source_node_id: entry.id,
          target_node_id: dialogue.id,
          source_pin: "output",
          target_pin: "input"
        })

      assert conn.source_node_id == entry.id
      assert conn.target_node_id == dialogue.id
    end

    test "rejects connection from exit node (exit has no outputs)" do
      %{flow: flow} = create_project_and_flow()
      exit_node = get_exit_node(flow)
      dialogue = node_fixture(flow, %{type: "dialogue"})

      result =
        Flows.create_connection_with_attrs(flow, %{
          source_node_id: exit_node.id,
          target_node_id: dialogue.id,
          source_pin: "output",
          target_pin: "input"
        })

      assert result == {:error, :exit_has_no_outputs}
    end

    test "rejects connection to entry node (entry has no inputs)" do
      %{flow: flow} = create_project_and_flow()
      entry = get_entry_node(flow)
      dialogue = node_fixture(flow, %{type: "dialogue"})

      result =
        Flows.create_connection_with_attrs(flow, %{
          source_node_id: dialogue.id,
          target_node_id: entry.id,
          source_pin: "output",
          target_pin: "input"
        })

      assert result == {:error, :entry_has_no_inputs}
    end

    test "rejects connection from jump node (jump has no outputs)" do
      %{flow: flow} = create_project_and_flow()
      jump = node_fixture(flow, %{type: "jump", data: %{"hub_id" => "test"}})
      dialogue = node_fixture(flow, %{type: "dialogue"})

      result =
        Flows.create_connection_with_attrs(flow, %{
          source_node_id: jump.id,
          target_node_id: dialogue.id,
          source_pin: "output",
          target_pin: "input"
        })

      assert result == {:error, :jump_has_no_outputs}
    end

    test "returns error when source node does not exist" do
      %{flow: flow} = create_project_and_flow()
      dialogue = node_fixture(flow, %{type: "dialogue"})

      result =
        Flows.create_connection_with_attrs(flow, %{
          source_node_id: 0,
          target_node_id: dialogue.id,
          source_pin: "output",
          target_pin: "input"
        })

      assert result == {:error, :source_node_not_found}
    end

    test "returns error when target node does not exist" do
      %{flow: flow} = create_project_and_flow()
      entry = get_entry_node(flow)

      result =
        Flows.create_connection_with_attrs(flow, %{
          source_node_id: entry.id,
          target_node_id: 0,
          source_pin: "output",
          target_pin: "input"
        })

      assert result == {:error, :target_node_not_found}
    end

    test "allows valid connection between dialogue nodes" do
      %{flow: flow} = create_project_and_flow()
      d1 = node_fixture(flow, %{type: "dialogue"})
      d2 = node_fixture(flow, %{type: "dialogue"})

      {:ok, conn} =
        Flows.create_connection_with_attrs(flow, %{
          source_node_id: d1.id,
          target_node_id: d2.id,
          source_pin: "output",
          target_pin: "input"
        })

      assert conn.source_node_id == d1.id
      assert conn.target_node_id == d2.id
    end

    test "works with string keys in attrs" do
      %{flow: flow} = create_project_and_flow()
      entry = get_entry_node(flow)
      dialogue = node_fixture(flow, %{type: "dialogue"})

      {:ok, conn} =
        Flows.create_connection_with_attrs(flow, %{
          "source_node_id" => entry.id,
          "target_node_id" => dialogue.id,
          "source_pin" => "output",
          "target_pin" => "input"
        })

      assert conn.source_node_id == entry.id
    end
  end

  # ===========================================================================
  # update_connection/2
  # ===========================================================================

  describe "update_connection/2" do
    test "updates the label of a connection" do
      %{flow: flow} = create_project_and_flow()
      entry = get_entry_node(flow)
      dialogue = node_fixture(flow, %{type: "dialogue"})
      conn = connection_fixture(flow, entry, dialogue)

      {:ok, updated} = Flows.update_connection(conn, %{label: "Updated Label"})
      assert updated.label == "Updated Label"
    end

    test "can set label to nil" do
      %{flow: flow} = create_project_and_flow()
      entry = get_entry_node(flow)
      dialogue = node_fixture(flow, %{type: "dialogue"})
      conn = connection_fixture(flow, entry, dialogue, %{label: "Some Label"})

      {:ok, updated} = Flows.update_connection(conn, %{label: nil})
      assert updated.label == nil
    end

    test "validates label max length" do
      %{flow: flow} = create_project_and_flow()
      entry = get_entry_node(flow)
      dialogue = node_fixture(flow, %{type: "dialogue"})
      conn = connection_fixture(flow, entry, dialogue)

      {:error, changeset} =
        Flows.update_connection(conn, %{label: String.duplicate("a", 201)})

      assert errors_on(changeset).label
    end
  end

  # ===========================================================================
  # delete_connection/1
  # ===========================================================================

  describe "delete_connection/1" do
    test "deletes a connection" do
      %{flow: flow} = create_project_and_flow()
      entry = get_entry_node(flow)
      dialogue = node_fixture(flow, %{type: "dialogue"})
      conn = connection_fixture(flow, entry, dialogue)

      {:ok, deleted} = Flows.delete_connection(conn)
      assert deleted.id == conn.id

      assert Flows.get_connection(flow.id, conn.id) == nil
    end
  end

  # ===========================================================================
  # delete_connection_by_nodes/3
  # ===========================================================================

  describe "delete_connection_by_nodes/3" do
    test "deletes connection by source and target node IDs" do
      %{flow: flow} = create_project_and_flow()
      entry = get_entry_node(flow)
      dialogue = node_fixture(flow, %{type: "dialogue"})
      _conn = connection_fixture(flow, entry, dialogue)

      {count, _} = Flows.delete_connection_by_nodes(flow.id, entry.id, dialogue.id)
      assert count == 1

      assert Flows.list_connections(flow.id) == []
    end

    test "deletes multiple connections between same node pair" do
      %{flow: flow} = create_project_and_flow()
      d1 = node_fixture(flow, %{type: "dialogue"})
      d2 = node_fixture(flow, %{type: "dialogue"})

      _conn1 =
        connection_fixture(flow, d1, d2, %{source_pin: "response-1", target_pin: "input"})

      _conn2 =
        connection_fixture(flow, d1, d2, %{source_pin: "response-2", target_pin: "input"})

      {count, _} = Flows.delete_connection_by_nodes(flow.id, d1.id, d2.id)
      assert count == 2
    end

    test "returns {0, nil} when no connections match" do
      %{flow: flow} = create_project_and_flow()
      entry = get_entry_node(flow)
      exit_node = get_exit_node(flow)

      {count, _} = Flows.delete_connection_by_nodes(flow.id, entry.id, exit_node.id)
      assert count == 0
    end

    test "does not delete connections in other flows" do
      %{project: project, flow: flow1} = create_project_and_flow()
      flow2 = flow_fixture(project)
      entry1 = get_entry_node(flow1)
      d1 = node_fixture(flow1, %{type: "dialogue"})
      _conn1 = connection_fixture(flow1, entry1, d1)

      entry2 = get_entry_node(flow2)
      d2 = node_fixture(flow2, %{type: "dialogue"})
      _conn2 = connection_fixture(flow2, entry2, d2)

      # Delete from flow1 should not affect flow2
      {1, _} = Flows.delete_connection_by_nodes(flow1.id, entry1.id, d1.id)
      assert length(Flows.list_connections(flow2.id)) == 1
    end
  end

  # ===========================================================================
  # delete_connection_by_pins/5
  # ===========================================================================

  describe "delete_connection_by_pins/5" do
    test "deletes a specific connection by pins" do
      %{flow: flow} = create_project_and_flow()
      d1 = node_fixture(flow, %{type: "dialogue"})
      d2 = node_fixture(flow, %{type: "dialogue"})

      _conn1 =
        connection_fixture(flow, d1, d2, %{source_pin: "response-1", target_pin: "input"})

      _conn2 =
        connection_fixture(flow, d1, d2, %{source_pin: "response-2", target_pin: "input"})

      {count, _} =
        Flows.delete_connection_by_pins(flow.id, d1.id, "response-1", d2.id, "input")

      assert count == 1

      # The other connection should still exist
      connections = Flows.list_connections(flow.id)
      assert length(connections) == 1
      assert hd(connections).source_pin == "response-2"
    end

    test "returns {0, nil} when pins do not match" do
      %{flow: flow} = create_project_and_flow()
      d1 = node_fixture(flow, %{type: "dialogue"})
      d2 = node_fixture(flow, %{type: "dialogue"})
      _conn = connection_fixture(flow, d1, d2, %{source_pin: "output", target_pin: "input"})

      {count, _} =
        Flows.delete_connection_by_pins(flow.id, d1.id, "nonexistent", d2.id, "input")

      assert count == 0
    end
  end

  # ===========================================================================
  # delete_connections_among_nodes/2
  # ===========================================================================

  describe "delete_connections_among_nodes/2" do
    test "deletes connections where both source and target are in the node IDs list" do
      %{flow: flow} = create_project_and_flow()
      d1 = node_fixture(flow, %{type: "dialogue"})
      d2 = node_fixture(flow, %{type: "dialogue"})
      d3 = node_fixture(flow, %{type: "dialogue"})
      entry = get_entry_node(flow)

      _conn1 = connection_fixture(flow, d1, d2)
      _conn2 = connection_fixture(flow, d2, d3)
      _conn3 = connection_fixture(flow, entry, d1)

      # Delete connections among d1, d2, d3 (but not entry)
      {count, _} = Flows.delete_connections_among_nodes(flow.id, [d1.id, d2.id, d3.id])
      assert count == 2

      # The entry -> d1 connection should survive since entry is not in the list
      remaining = Flows.list_connections(flow.id)
      assert length(remaining) == 1
      assert hd(remaining).source_node_id == entry.id
    end

    test "returns {0, nil} for empty node_ids list" do
      %{flow: flow} = create_project_and_flow()
      assert Flows.delete_connections_among_nodes(flow.id, []) == {0, nil}
    end

    test "returns {0, nil} when no connections match" do
      %{flow: flow} = create_project_and_flow()
      d1 = node_fixture(flow, %{type: "dialogue"})

      {count, _} = Flows.delete_connections_among_nodes(flow.id, [d1.id])
      assert count == 0
    end
  end

  # ===========================================================================
  # get_outgoing_connections/1
  # ===========================================================================

  describe "get_outgoing_connections/1" do
    test "returns all outgoing connections from a node" do
      %{flow: flow} = create_project_and_flow()
      entry = get_entry_node(flow)
      d1 = node_fixture(flow, %{type: "dialogue"})
      d2 = node_fixture(flow, %{type: "dialogue"})

      _conn1 = connection_fixture(flow, entry, d1)
      _conn2 = connection_fixture(flow, entry, d2, %{source_pin: "output", target_pin: "input"})

      outgoing = Flows.get_outgoing_connections(entry.id)
      assert length(outgoing) == 2
      assert Enum.all?(outgoing, &(&1.source_node_id == entry.id))
    end

    test "preloads target_node" do
      %{flow: flow} = create_project_and_flow()
      entry = get_entry_node(flow)
      d1 = node_fixture(flow, %{type: "dialogue"})
      _conn = connection_fixture(flow, entry, d1)

      [outgoing] = Flows.get_outgoing_connections(entry.id)
      assert outgoing.target_node.id == d1.id
    end

    test "returns empty list when node has no outgoing connections" do
      %{flow: flow} = create_project_and_flow()
      exit_node = get_exit_node(flow)

      assert Flows.get_outgoing_connections(exit_node.id) == []
    end
  end

  # ===========================================================================
  # get_incoming_connections/1
  # ===========================================================================

  describe "get_incoming_connections/1" do
    test "returns all incoming connections to a node" do
      %{flow: flow} = create_project_and_flow()
      d1 = node_fixture(flow, %{type: "dialogue"})
      d2 = node_fixture(flow, %{type: "dialogue"})
      exit_node = get_exit_node(flow)

      _conn1 = connection_fixture(flow, d1, exit_node)
      _conn2 = connection_fixture(flow, d2, exit_node)

      incoming = Flows.get_incoming_connections(exit_node.id)
      assert length(incoming) == 2
      assert Enum.all?(incoming, &(&1.target_node_id == exit_node.id))
    end

    test "preloads source_node" do
      %{flow: flow} = create_project_and_flow()
      d1 = node_fixture(flow, %{type: "dialogue"})
      exit_node = get_exit_node(flow)
      _conn = connection_fixture(flow, d1, exit_node)

      [incoming] = Flows.get_incoming_connections(exit_node.id)
      assert incoming.source_node.id == d1.id
    end

    test "returns empty list when node has no incoming connections" do
      %{flow: flow} = create_project_and_flow()
      entry = get_entry_node(flow)

      assert Flows.get_incoming_connections(entry.id) == []
    end
  end

  # ===========================================================================
  # change_connection/2
  # ===========================================================================

  describe "change_connection/2" do
    test "returns a changeset for the connection" do
      %{flow: flow} = create_project_and_flow()
      entry = get_entry_node(flow)
      dialogue = node_fixture(flow, %{type: "dialogue"})
      conn = connection_fixture(flow, entry, dialogue)

      changeset = Flows.change_connection(conn, %{label: "New"})
      assert changeset.valid?
      assert Ecto.Changeset.get_change(changeset, :label) == "New"
    end

    test "returns a changeset with no changes when called with empty attrs" do
      %{flow: flow} = create_project_and_flow()
      entry = get_entry_node(flow)
      dialogue = node_fixture(flow, %{type: "dialogue"})
      conn = connection_fixture(flow, entry, dialogue)

      changeset = Flows.change_connection(conn)
      assert changeset.valid?
    end
  end
end
