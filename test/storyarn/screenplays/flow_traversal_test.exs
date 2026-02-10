defmodule Storyarn.Screenplays.FlowTraversalTest do
  use ExUnit.Case, async: true

  alias Storyarn.Flows.{FlowConnection, FlowNode}
  alias Storyarn.Screenplays.FlowTraversal

  defp build_node(id, type) do
    %FlowNode{id: id, type: type, data: %{}, position_x: 0.0, position_y: 0.0, source: "manual"}
  end

  defp build_conn(source_id, source_pin, target_id) do
    %FlowConnection{
      id: source_id * 1000 + target_id,
      source_node_id: source_id,
      source_pin: source_pin,
      target_node_id: target_id,
      target_pin: "input"
    }
  end

  describe "linearize/2" do
    test "linear chain: entry → dialogue → exit produces correct order" do
      nodes = [build_node(1, "entry"), build_node(2, "dialogue"), build_node(3, "exit")]

      connections = [
        build_conn(1, "output", 2),
        build_conn(2, "output", 3)
      ]

      assert {:ok, ordered} = FlowTraversal.linearize(nodes, connections)
      assert Enum.map(ordered, & &1.id) == [1, 2, 3]
    end

    test "condition node follows true pin, skips false branch" do
      nodes = [
        build_node(1, "entry"),
        build_node(2, "condition"),
        build_node(3, "dialogue"),
        build_node(4, "dialogue")
      ]

      connections = [
        build_conn(1, "output", 2),
        build_conn(2, "true", 3),
        build_conn(2, "false", 4)
      ]

      assert {:ok, ordered} = FlowTraversal.linearize(nodes, connections)
      ids = Enum.map(ordered, & &1.id)

      assert ids == [1, 2, 3]
      refute 4 in ids
    end

    test "exit node is terminal — no further traversal" do
      nodes = [build_node(1, "entry"), build_node(2, "exit")]
      connections = [build_conn(1, "output", 2)]

      assert {:ok, ordered} = FlowTraversal.linearize(nodes, connections)
      assert Enum.map(ordered, & &1.id) == [1, 2]
    end

    test "jump node is terminal — no further traversal" do
      nodes = [build_node(1, "entry"), build_node(2, "jump")]
      connections = [build_conn(1, "output", 2)]

      assert {:ok, ordered} = FlowTraversal.linearize(nodes, connections)
      assert Enum.map(ordered, & &1.id) == [1, 2]
    end

    test "cycle: visited set prevents infinite loop" do
      nodes = [build_node(1, "entry"), build_node(2, "hub"), build_node(3, "dialogue")]

      connections = [
        build_conn(1, "output", 2),
        build_conn(2, "output", 3),
        build_conn(3, "output", 2)
      ]

      assert {:ok, ordered} = FlowTraversal.linearize(nodes, connections)
      assert Enum.map(ordered, & &1.id) == [1, 2, 3]
    end

    test "hub node continues traversal via output pin" do
      nodes = [
        build_node(1, "entry"),
        build_node(2, "hub"),
        build_node(3, "dialogue"),
        build_node(4, "exit")
      ]

      connections = [
        build_conn(1, "output", 2),
        build_conn(2, "output", 3),
        build_conn(3, "output", 4)
      ]

      assert {:ok, ordered} = FlowTraversal.linearize(nodes, connections)
      assert Enum.map(ordered, & &1.id) == [1, 2, 3, 4]
    end

    test "multiple entry nodes: both traversed in id order" do
      nodes = [
        build_node(1, "entry"),
        build_node(2, "dialogue"),
        build_node(3, "entry"),
        build_node(4, "dialogue")
      ]

      connections = [
        build_conn(1, "output", 2),
        build_conn(3, "output", 4)
      ]

      assert {:ok, ordered} = FlowTraversal.linearize(nodes, connections)
      assert Enum.map(ordered, & &1.id) == [1, 2, 3, 4]
    end

    test "no entry node returns error" do
      nodes = [build_node(1, "dialogue"), build_node(2, "exit")]
      connections = [build_conn(1, "output", 2)]

      assert {:error, :no_entry_node} = FlowTraversal.linearize(nodes, connections)
    end

    test "disconnected node after entry: only reachable nodes returned" do
      nodes = [
        build_node(1, "entry"),
        build_node(2, "dialogue"),
        build_node(3, "dialogue")
      ]

      connections = [build_conn(1, "output", 2)]

      assert {:ok, ordered} = FlowTraversal.linearize(nodes, connections)
      ids = Enum.map(ordered, & &1.id)

      assert ids == [1, 2]
      refute 3 in ids
    end

    test "complex path: entry → dialogue → condition → instruction → exit" do
      nodes = [
        build_node(1, "entry"),
        build_node(2, "dialogue"),
        build_node(3, "condition"),
        build_node(4, "instruction"),
        build_node(5, "exit")
      ]

      connections = [
        build_conn(1, "output", 2),
        build_conn(2, "output", 3),
        build_conn(3, "true", 4),
        build_conn(3, "false", 5),
        build_conn(4, "output", 5)
      ]

      assert {:ok, ordered} = FlowTraversal.linearize(nodes, connections)
      assert Enum.map(ordered, & &1.id) == [1, 2, 3, 4, 5]
    end
  end
end
