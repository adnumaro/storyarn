defmodule Storyarn.Imports.Parsers.Yarn.Layout do
  @moduledoc false

  # Layered left-to-right canvas placement for a compiled Yarn flow.
  #
  # The compiler only ever connects already-created nodes to a newly created
  # one, so a flow's node list in creation order is already a topological order
  # of its graph. That makes the rank pass a single forward sweep instead of a
  # full topological sort, and it is why `assign_positions/3` requires creation
  # order rather than sorting defensively — a caller that reorders the list
  # silently degrades the layout instead of raising.

  # Kept in step with the editor's ELK options in
  # `assets/app/modules/flows/editor/services/flowAutoLayout.ts`
  # (`nodeNodeBetweenLayers: 120`, `nodeNode: 60`) over the 190x130 default node
  # box in `lib/flow-node.ts`. Import placement has to agree with what the
  # auto-layout button produces, otherwise pressing it reflows the whole flow.
  @node_width 190.0
  @node_height 130.0
  @layer_gap 120.0
  @row_gap 60.0
  @pin_height 35.0
  @origin_x 80.0
  @origin_y 80.0
  @column_gap @node_width + @layer_gap
  @annotation_band_gap 140.0

  @doc """
  Returns `nodes` with `position_x`/`position_y` assigned from graph structure.

  Nodes are ranked by longest path from the entry node, so a rank is a canvas
  column. Within a column, nodes are ordered by the mean vertical centre of
  their predecessors, which keeps an option's branches next to the choice that
  opened them instead of scattering them by creation index.

  Nodes with no edges at all — annotations retained for unsupported commands —
  are laid out in a band below the graph, in the column after whichever node
  they were emitted next to, so they stay near their context without
  overlapping executable nodes. `annotation_anchors` maps such a node id to the
  source node ids it was emitted after.
  """
  @spec assign_positions([map()], [map()], %{optional(String.t()) => [String.t()]}) :: [map()]
  def assign_positions(nodes, connections, annotation_anchors \\ %{}) do
    index_by_id = nodes |> Enum.with_index() |> Map.new(fn {node, index} -> {node["id"], index} end)
    predecessors = build_predecessors(connections)
    connected = connected_ids(connections)

    {graph_nodes, floating_nodes} = Enum.split_with(nodes, &MapSet.member?(connected, &1["id"]))

    ranks = compute_ranks(graph_nodes, predecessors)
    {positions, bottom} = place_graph_nodes(graph_nodes, ranks, predecessors, index_by_id)
    positions = place_floating_nodes(floating_nodes, annotation_anchors, ranks, bottom, positions)

    Enum.map(nodes, fn node ->
      {x, y} = Map.get(positions, node["id"], {@origin_x, @origin_y})

      node
      |> Map.put("position_x", x)
      |> Map.put("position_y", y)
    end)
  end

  defp build_predecessors(connections) do
    Enum.reduce(connections, %{}, fn connection, acc ->
      Map.update(
        acc,
        connection["target_node_id"],
        [connection["source_node_id"]],
        &[connection["source_node_id"] | &1]
      )
    end)
  end

  defp connected_ids(connections) do
    Enum.reduce(connections, MapSet.new(), fn connection, acc ->
      acc
      |> MapSet.put(connection["source_node_id"])
      |> MapSet.put(connection["target_node_id"])
    end)
  end

  # Longest path from the entry. Safe as a single pass because every edge runs
  # from a lower to a higher creation index, so a node's predecessors are always
  # ranked before it.
  defp compute_ranks(graph_nodes, predecessors) do
    Enum.reduce(graph_nodes, %{}, fn node, ranks ->
      rank =
        predecessors
        |> Map.get(node["id"], [])
        |> Enum.map(&Map.get(ranks, &1))
        |> Enum.reject(&is_nil/1)
        |> case do
          [] -> 0
          ranked -> Enum.max(ranked) + 1
        end

      Map.put(ranks, node["id"], rank)
    end)
  end

  defp place_graph_nodes(graph_nodes, ranks, predecessors, index_by_id) do
    graph_nodes
    |> Enum.group_by(&Map.fetch!(ranks, &1["id"]))
    |> Enum.sort_by(fn {rank, _nodes} -> rank end)
    |> Enum.reduce({%{}, %{}, @origin_y}, fn {rank, rank_nodes}, {positions, centres, bottom} ->
      ordered =
        Enum.sort_by(rank_nodes, fn node ->
          {barycentre(node, predecessors, centres), Map.fetch!(index_by_id, node["id"])}
        end)

      x = @origin_x + rank * @column_gap

      {positions, centres, column_bottom} =
        Enum.reduce(ordered, {positions, centres, @origin_y}, fn node, {pos, cen, y} ->
          height = node_height(node)

          {
            Map.put(pos, node["id"], {x, y}),
            Map.put(cen, node["id"], y + height / 2),
            y + height + @row_gap
          }
        end)

      {positions, centres, max(bottom, column_bottom)}
    end)
    |> then(fn {positions, _centres, bottom} -> {positions, bottom} end)
  end

  # Nodes whose predecessors are all in earlier columns already have centres;
  # an empty list only happens for the entry node, which anchors at the top.
  defp barycentre(node, predecessors, centres) do
    predecessors
    |> Map.get(node["id"], [])
    |> Enum.map(&Map.get(centres, &1))
    |> Enum.reject(&is_nil/1)
    |> case do
      [] -> @origin_y
      values -> Enum.sum(values) / length(values)
    end
  end

  defp place_floating_nodes([], _anchors, _ranks, _bottom, positions), do: positions

  defp place_floating_nodes(floating_nodes, annotation_anchors, ranks, bottom, positions) do
    band_top = bottom + @annotation_band_gap

    floating_nodes
    |> Enum.group_by(&anchor_rank(&1, annotation_anchors, ranks))
    |> Enum.reduce(positions, fn {rank, band_nodes}, acc ->
      x = @origin_x + rank * @column_gap

      band_nodes
      |> Enum.with_index()
      |> Enum.reduce(acc, fn {node, row}, inner ->
        Map.put(inner, node["id"], {x, band_top + row * (@node_height + @row_gap)})
      end)
    end)
  end

  defp anchor_rank(node, annotation_anchors, ranks) do
    annotation_anchors
    |> Map.get(node["id"], [])
    |> Enum.map(&Map.get(ranks, &1))
    |> Enum.reject(&is_nil/1)
    |> case do
      [] -> 0
      anchor_ranks -> Enum.max(anchor_ranks) + 1
    end
  end

  # Mirrors the canvas: a node is 130px tall and grows by one pin row per extra
  # response, so a dialogue with many choices does not overlap its neighbour.
  defp node_height(%{"type" => "dialogue", "data" => data}) when is_map(data) do
    case data["responses"] do
      responses when is_list(responses) ->
        @node_height + max(length(responses) - 1, 0) * @pin_height

      _no_responses ->
        @node_height
    end
  end

  defp node_height(_node), do: @node_height
end
