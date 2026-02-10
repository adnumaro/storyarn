defmodule Storyarn.Screenplays.FlowTraversal do
  @moduledoc """
  Pure functions that linearize a flow graph into screenplay order via DFS.

  Builds an adjacency list from connections, then depth-first traverses from
  entry nodes following the primary path ("output" pin for standard nodes,
  "true" pin for condition nodes).

  No side effects — all functions are deterministic and database-free.
  """

  alias Storyarn.Flows.{FlowConnection, FlowNode}

  @doc """
  Linearizes a flow graph into screenplay order via DFS.

  Follows primary path: "output" pin for standard nodes, "true" pin for conditions.
  Multiple entry nodes are traversed in id order with a shared visited set.

  Returns `{:ok, ordered_nodes}` or `{:error, :no_entry_node}`.
  """
  @spec linearize([FlowNode.t()], [FlowConnection.t()]) ::
          {:ok, [FlowNode.t()]} | {:error, :no_entry_node}
  def linearize(nodes, connections) do
    entry_nodes =
      nodes
      |> Enum.filter(&(&1.type == "entry"))
      |> Enum.sort_by(& &1.id)

    case entry_nodes do
      [] ->
        {:error, :no_entry_node}

      entries ->
        adjacency = build_adjacency(connections)
        nodes_by_id = Map.new(nodes, &{&1.id, &1})

        {ordered, _visited} =
          Enum.reduce(entries, {[], MapSet.new()}, fn entry, {acc, visited} ->
            {path, visited} = traverse(entry, adjacency, nodes_by_id, visited)
            {acc ++ path, visited}
          end)

        {:ok, ordered}
    end
  end

  # ---------------------------------------------------------------------------
  # Adjacency list: %{source_node_id => %{source_pin => target_node_id}}
  # First connection per pin wins (deterministic).
  # ---------------------------------------------------------------------------

  defp build_adjacency(connections) do
    Enum.reduce(connections, %{}, fn conn, acc ->
      pin_map = Map.get(acc, conn.source_node_id, %{})

      if Map.has_key?(pin_map, conn.source_pin),
        do: acc,
        else: Map.put(acc, conn.source_node_id, Map.put(pin_map, conn.source_pin, conn.target_node_id))
    end)
  end

  # ---------------------------------------------------------------------------
  # DFS traversal — follows primary pin per node type.
  # ---------------------------------------------------------------------------

  defp traverse(node, adjacency, nodes_by_id, visited) do
    if MapSet.member?(visited, node.id) do
      {[], visited}
    else
      visited = MapSet.put(visited, node.id)
      pin = primary_pin(node.type)
      next_id = get_in(adjacency, [node.id, pin])
      next_node = if next_id, do: Map.get(nodes_by_id, next_id)

      case next_node do
        nil ->
          {[node], visited}

        next ->
          {rest, visited} = traverse(next, adjacency, nodes_by_id, visited)
          {[node | rest], visited}
      end
    end
  end

  defp primary_pin("condition"), do: "true"
  defp primary_pin(_type), do: "output"
end
