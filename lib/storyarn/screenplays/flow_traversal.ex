defmodule Storyarn.Screenplays.FlowTraversal do
  @moduledoc """
  Pure functions that linearize a flow graph into screenplay order via DFS.

  Builds an adjacency list from connections, then depth-first traverses from
  entry nodes following the primary path ("output" pin for standard nodes,
  "true" pin for condition nodes). Collects response branches at dialogue nodes
  into a recursive tree structure.

  No side effects — all functions are deterministic and database-free.
  """

  alias Storyarn.Flows.{FlowConnection, FlowNode}

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

  @doc """
  Linearizes a flow graph with branch structure via DFS.

  Follows the primary path and collects response branches at dialogue nodes.
  Each branch follows a response-pin connection into a subtree.

  Returns `{:ok, traversal_result}` or `{:error, :no_entry_node}`.

  The `traversal_result` has:
    - `nodes` — ordered node list for the main sequence
    - `branches` — response branches with recursive subtrees
  """
  @spec linearize_tree([FlowNode.t()], [FlowConnection.t()]) ::
          {:ok, map()} | {:error, :no_entry_node}
  def linearize_tree(nodes, connections) do
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

        {result, _visited} =
          Enum.reduce(entries, {%{nodes: [], branches: []}, MapSet.new()}, fn entry, {acc, visited} ->
            {tree, visited} = traverse_tree(entry, adjacency, nodes_by_id, visited)
            {%{nodes: acc.nodes ++ tree.nodes, branches: acc.branches ++ tree.branches}, visited}
          end)

        {:ok, result}
    end
  end

  # ---------------------------------------------------------------------------
  # Private — shared
  # ---------------------------------------------------------------------------

  defp primary_pin("condition"), do: "true"
  defp primary_pin(_type), do: "output"

  # ---------------------------------------------------------------------------
  # Tree traversal — follows primary pin + collects response branches
  # ---------------------------------------------------------------------------

  defp traverse_tree(node, adjacency, nodes_by_id, visited) do
    if MapSet.member?(visited, node.id) do
      {%{nodes: [], branches: []}, visited}
    else
      visited = MapSet.put(visited, node.id)
      {branches, visited} = collect_response_branches(node, adjacency, nodes_by_id, visited)

      pin = primary_pin(node.type)
      next_id = get_in(adjacency, [node.id, pin])
      next_node = if next_id, do: Map.get(nodes_by_id, next_id)

      case next_node do
        nil ->
          {%{nodes: [node], branches: branches}, visited}

        next ->
          {rest, visited} = traverse_tree(next, adjacency, nodes_by_id, visited)
          {%{nodes: [node | rest.nodes], branches: branches ++ rest.branches}, visited}
      end
    end
  end

  defp collect_response_branches(%{type: "dialogue"} = node, adjacency, nodes_by_id, visited) do
    pin_map = Map.get(adjacency, node.id, %{})
    ctx = %{pin_map: pin_map, adjacency: adjacency, nodes_by_id: nodes_by_id}

    node
    |> response_ids()
    |> Enum.reduce({[], visited}, fn resp_id, {acc, vis} ->
      follow_response_pin(node.id, resp_id, ctx, acc, vis)
    end)
  end

  defp collect_response_branches(_node, _adjacency, _nodes_by_id, visited), do: {[], visited}

  defp follow_response_pin(node_id, resp_id, ctx, acc, visited) do
    with target_id when not is_nil(target_id) <- Map.get(ctx.pin_map, resp_id),
         %FlowNode{} = target <- Map.get(ctx.nodes_by_id, target_id) do
      {subtree, visited} = traverse_tree(target, ctx.adjacency, ctx.nodes_by_id, visited)
      {acc ++ [%{source_node_id: node_id, choice_id: resp_id, subtree: subtree}], visited}
    else
      _ -> {acc, visited}
    end
  end

  @doc "Extracts response IDs from a node's data."
  def response_ids(%{data: data}) when is_map(data) do
    (data["responses"] || []) |> Enum.map(& &1["id"]) |> Enum.reject(&is_nil/1)
  end

  def response_ids(_), do: []
end
