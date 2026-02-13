defmodule Storyarn.Screenplays.FlowTraversalTest do
  use ExUnit.Case, async: true

  alias Storyarn.Flows.{FlowConnection, FlowNode}
  alias Storyarn.Screenplays.FlowTraversal

  defp build_node(id, type, data \\ %{}) do
    %FlowNode{id: id, type: type, data: data, position_x: 0.0, position_y: 0.0, source: "manual"}
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

  describe "linearize_tree/2" do
    test "no response branches returns flat result" do
      nodes = [build_node(1, "entry"), build_node(2, "dialogue"), build_node(3, "exit")]
      connections = [build_conn(1, "output", 2), build_conn(2, "output", 3)]

      assert {:ok, result} = FlowTraversal.linearize_tree(nodes, connections)
      assert Enum.map(result.nodes, & &1.id) == [1, 2, 3]
      assert result.branches == []
    end

    test "response branches produce nested structure" do
      nodes = [
        build_node(1, "entry"),
        build_node(2, "dialogue", %{
          "responses" => [
            %{"id" => "c1", "text" => "Go left"},
            %{"id" => "c2", "text" => "Go right"}
          ]
        }),
        build_node(3, "dialogue"),
        build_node(4, "dialogue")
      ]

      connections = [
        build_conn(1, "output", 2),
        build_conn(2, "c1", 3),
        build_conn(2, "c2", 4)
      ]

      assert {:ok, result} = FlowTraversal.linearize_tree(nodes, connections)

      # Main sequence: entry, dialogue (no "output" connection → stops)
      assert Enum.map(result.nodes, & &1.id) == [1, 2]

      # Two branches
      assert length(result.branches) == 2

      [b1, b2] = result.branches
      assert b1.source_node_id == 2
      assert b1.choice_id == "c1"
      assert Enum.map(b1.subtree.nodes, & &1.id) == [3]

      assert b2.source_node_id == 2
      assert b2.choice_id == "c2"
      assert Enum.map(b2.subtree.nodes, & &1.id) == [4]
    end

    test "nested branches produce recursive subtrees" do
      nodes = [
        build_node(1, "entry"),
        build_node(2, "dialogue", %{
          "responses" => [%{"id" => "c1", "text" => "Go"}]
        }),
        build_node(3, "dialogue", %{
          "responses" => [%{"id" => "c2", "text" => "Deeper"}]
        }),
        build_node(4, "dialogue")
      ]

      connections = [
        build_conn(1, "output", 2),
        build_conn(2, "c1", 3),
        build_conn(3, "c2", 4)
      ]

      assert {:ok, result} = FlowTraversal.linearize_tree(nodes, connections)

      assert length(result.branches) == 1
      b1 = hd(result.branches)
      assert b1.choice_id == "c1"
      assert Enum.map(b1.subtree.nodes, & &1.id) == [3]

      # Nested branch
      assert length(b1.subtree.branches) == 1
      b2 = hd(b1.subtree.branches)
      assert b2.choice_id == "c2"
      assert Enum.map(b2.subtree.nodes, & &1.id) == [4]
    end

    test "no entry node returns error" do
      nodes = [build_node(1, "dialogue")]
      assert {:error, :no_entry_node} = FlowTraversal.linearize_tree(nodes, [])
    end
  end
end
