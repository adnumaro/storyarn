defmodule Storyarn.Flows.DialoguePreviewTest do
  use ExUnit.Case, async: true

  alias Storyarn.Flows.DialoguePreview

  test "returns a dialogue and derives whether its output can continue" do
    dialogue = node(1, "dialogue", %{"responses" => []})
    next_node = node(2, "exit")
    graph = graph([dialogue, next_node], [connection(1, "output", 2)])

    assert {:ok, %{node: ^dialogue, has_next?: true}} =
             DialoguePreview.resolve(graph, 1)
  end

  test "a dialogue with authored responses does not expose generic continue" do
    dialogue = node(1, "dialogue", %{"responses" => [%{"id" => "yes"}]})
    graph = graph([dialogue, node(2, "exit")], [connection(1, "output", 2)])

    assert {:ok, %{has_next?: false}} = DialoguePreview.resolve(graph, 1)
  end

  test "traverses pass-through nodes to the next dialogue" do
    dialogue = node(3, "dialogue", %{"responses" => []})

    graph =
      graph(
        [node(1, "entry"), node(2, "hub", %{"hub_id" => "start"}), dialogue],
        [connection(1, "output", 2), connection(2, "output", 3)]
      )

    assert {:ok, %{node: ^dialogue}} = DialoguePreview.resolve(graph, "1")
  end

  test "resolves jump targets by Flow hub identity" do
    dialogue = node(3, "dialogue", %{"responses" => []})

    graph =
      graph(
        [
          node(1, "jump", %{"target_hub_id" => "arrival"}),
          node(2, "hub", %{"hub_id" => "arrival"}),
          dialogue
        ],
        [connection(2, "output", 3)]
      )

    assert {:ok, %{node: ^dialogue}} = DialoguePreview.resolve(graph, 1)
  end

  test "fails closed for missing nodes, missing jump targets and cycles" do
    cyclic_graph =
      graph(
        [node(1, "hub"), node(2, "hub")],
        [connection(1, "output", 2), connection(2, "output", 1)]
      )

    assert :not_found = DialoguePreview.resolve(cyclic_graph, 99)
    assert :empty = DialoguePreview.resolve(cyclic_graph, 1)
    assert :empty = DialoguePreview.resolve(graph([node(1, "jump")], []), 1)
  end

  test "stops traversal at the domain depth limit" do
    nodes = Enum.map(1..52, &node(&1, "hub"))
    connections = Enum.map(1..51, &connection(&1, "output", &1 + 1))

    assert :empty = DialoguePreview.resolve(graph(nodes, connections), 1)
  end

  test "preserves a dialogue reached by the final allowed traversal edge" do
    dialogue = node(51, "dialogue")
    nodes = Enum.map(1..50, &node(&1, "hub")) ++ [dialogue]
    connections = Enum.map(1..50, &connection(&1, "output", &1 + 1))

    assert {:ok, %{node: ^dialogue}} =
             DialoguePreview.resolve(graph(nodes, connections), 1)
  end

  defp graph(nodes, connections) do
    %{nodes: Map.new(nodes, &{&1.id, &1}), connections: connections}
  end

  defp node(id, type, data \\ %{}) do
    %{id: id, type: type, data: data}
  end

  defp connection(source_node_id, source_pin, target_node_id) do
    %{
      source_node_id: source_node_id,
      source_pin: source_pin,
      target_node_id: target_node_id,
      target_pin: "input"
    }
  end
end
