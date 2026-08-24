defmodule Storyarn.Projects.Imports.Parsers.Yarn.Layout do
  @moduledoc false

  alias Storyarn.Projects.Imports.Parsers.Yarn.Expression

  # Layered left-to-right canvas placement for a compiled Yarn flow.
  #
  # The compiler only ever connects already-created nodes to a newly created
  # one, so a flow's node list in creation order is already a topological order
  # of its graph. That makes the rank pass a single forward sweep instead of a
  # full topological sort, and it is why `assign_positions/3` requires creation
  # order rather than sorting defensively — a caller that reorders the list
  # silently degrades the layout instead of raising.

  # Gaps mirror the editor's ELK options in
  # `assets/app/modules/flows/editor/services/flowAutoLayout.ts`
  # (`nodeNodeBetweenLayers: 120`, `nodeNode: 60`). Sizes deliberately do NOT
  # mirror the 190x130 default box in `lib/flow-node.ts`: that box is only the
  # pre-measure placeholder — the canvas measures the rendered DOM
  # (`syncNodeSize`) and the auto-layout button lays out with those real
  # boxes. Import placement therefore estimates what will render; spacing by
  # the placeholder overlapped every dialogue-heavy column, because a
  # `DialogueNode` renders 280-350px wide and grows with its content.
  @layer_gap 120.0
  @row_gap 60.0
  @pin_height 35.0
  @origin_x 80.0
  @origin_y 80.0
  @annotation_band_gap 140.0

  @default_node_width 280.0
  @node_widths %{
    "dialogue" => 350.0,
    "condition" => 300.0,
    "instruction" => 300.0,
    # AnnotationNode.vue renders a fixed 200x120 box; flowPlacement.ts agrees.
    "annotation" => 200.0,
    "subflow" => 280.0,
    "hub" => 260.0,
    "jump" => 260.0,
    "entry" => 220.0,
    "exit" => 220.0
  }

  @default_node_height 120.0
  @node_heights %{
    "dialogue" => 170.0,
    "condition" => 150.0,
    "instruction" => 140.0,
    "annotation" => 120.0
  }

  @doc """
  Returns `nodes` with `position_x`/`position_y` assigned from graph structure.

  Nodes are ranked by longest path from the entry node, so a rank is a canvas
  column. Column stride follows the widest estimated node in each column, and
  vertical spacing follows each node's estimated height, so real rendered
  boxes do not overlap. Within a column, nodes are ordered by the mean
  vertical centre of their predecessors, which keeps an option's branches next
  to the choice that opened them instead of scattering them by creation index.

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
    {column_xs, after_graph_x} = column_positions(graph_nodes, ranks)
    {positions, bottom} = place_graph_nodes(graph_nodes, ranks, predecessors, index_by_id, column_xs)

    positions =
      place_floating_nodes(floating_nodes, annotation_anchors, ranks, bottom, positions, column_xs, after_graph_x)

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

  # Each column is as wide as its widest estimated node; the next column starts
  # after it plus the layer gap. Returns the x per rank and the x of the first
  # column after the graph, where trailing annotation bands land.
  defp column_positions(graph_nodes, ranks) do
    graph_nodes
    |> Enum.group_by(&Map.fetch!(ranks, &1["id"]))
    |> Enum.sort_by(fn {rank, _nodes} -> rank end)
    |> Enum.reduce({%{}, @origin_x}, fn {rank, rank_nodes}, {xs, x} ->
      width = rank_nodes |> Enum.map(&node_width/1) |> Enum.max()
      {Map.put(xs, rank, x), x + width + @layer_gap}
    end)
  end

  defp place_graph_nodes(graph_nodes, ranks, predecessors, index_by_id, column_xs) do
    graph_nodes
    |> Enum.group_by(&Map.fetch!(ranks, &1["id"]))
    |> Enum.sort_by(fn {rank, _nodes} -> rank end)
    |> Enum.reduce({%{}, %{}, @origin_y}, fn {rank, rank_nodes}, {positions, centres, bottom} ->
      ordered =
        Enum.sort_by(rank_nodes, fn node ->
          {barycentre(node, predecessors, centres), Map.fetch!(index_by_id, node["id"])}
        end)

      x = Map.fetch!(column_xs, rank)

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

  defp place_floating_nodes([], _anchors, _ranks, _bottom, positions, _column_xs, _after_graph_x), do: positions

  defp place_floating_nodes(floating_nodes, annotation_anchors, ranks, bottom, positions, column_xs, after_graph_x) do
    band_top = bottom + @annotation_band_gap

    floating_nodes
    |> Enum.group_by(&anchor_rank(&1, annotation_anchors, ranks))
    |> Enum.reduce(positions, fn {rank, band_nodes}, acc ->
      x = Map.get(column_xs, rank, after_graph_x)

      band_nodes
      |> Enum.reduce({acc, band_top}, fn node, {inner, y} ->
        {Map.put(inner, node["id"], {x, y}), y + node_height(node) + @row_gap}
      end)
      |> elem(0)
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

  @doc false
  @spec node_width(map()) :: float()
  def node_width(%{"type" => type}), do: Map.get(@node_widths, type, @default_node_width)
  def node_width(_node), do: @default_node_width

  # Content-aware estimates: a dialogue grows with its text (~38 chars per
  # rendered line at 350px) and every response row wraps at ~38 chars per row.
  # The numbers are deliberate overestimates — whitespace is recoverable,
  # overlap is not.
  @dialogue_text_chars_per_line 38
  @dialogue_text_line_height 28.0
  @response_label_chars_per_row 38
  @condition_output_height 35.0

  @doc false
  @spec node_height(map()) :: float()
  def node_height(%{"type" => "dialogue", "data" => data} = node) when is_map(data) do
    rendered_text_height = dialogue_text_height(data["text"])
    source_text_height = interpolated_text_height(data["import_yarn_source_text"], :dialogue)
    legacy_preserved_text_height = dialogue_text_height(data["import_yarn_literal_text"])

    base_node_height(node) + Enum.max([rendered_text_height, source_text_height, legacy_preserved_text_height]) +
      dialogue_responses_height(data["responses"])
  end

  def node_height(%{"type" => "condition", "data" => data} = node) when is_map(data) do
    base_node_height(node) + condition_outputs_height(data)
  end

  def node_height(node), do: base_node_height(node)

  # The base height already covers the first rendered text line. Newlines are
  # preserved by the canvas (whitespace-pre-wrap), so every newline-separated
  # segment renders as at least one line of its own.
  defp dialogue_text_height(text) when is_binary(text) and text != "" do
    lines =
      text
      |> String.split("\n")
      |> Enum.reduce(0, fn segment, total ->
        total + max(ceil(String.length(segment) / @dialogue_text_chars_per_line), 1)
      end)

    max(lines - 1, 0) * @dialogue_text_line_height
  end

  defp dialogue_text_height(_no_text), do: 0.0

  defp interpolated_text_height(source_text, mode) when is_binary(source_text) do
    source_text
    |> Expression.interpolate(mode)
    |> dialogue_text_height()
  end

  defp interpolated_text_height(_no_source, _mode), do: 0.0

  # The base height also covers one response pin row; wrapped labels add rows.
  defp dialogue_responses_height(responses) when is_list(responses) and responses != [] do
    total_rows =
      Enum.reduce(responses, 0, fn response, rows ->
        rendered_rows = response_label_rows(response["text"])

        source_rows =
          response["import_yarn_source_text"]
          |> interpolate_response_source()
          |> response_label_rows()

        rows + max(rendered_rows, source_rows)
      end)

    max(total_rows - 1, 0) * @pin_height
  end

  defp dialogue_responses_height(_no_responses), do: 0.0

  defp interpolate_response_source(source_text) when is_binary(source_text),
    do: Expression.interpolate(source_text, :response)

  defp interpolate_response_source(_no_source), do: nil

  defp response_label_rows(label) when is_binary(label) do
    max(ceil(String.length(label) / @response_label_chars_per_row), 1)
  end

  defp response_label_rows(_no_label), do: 1

  # The base estimate covers the input plus the two boolean outputs. A switch
  # renders one row for every rule/block and a final default row, so large
  # elseif chains need to reserve their full socket stack during import layout.
  defp condition_outputs_height(%{"switch_mode" => true, "condition" => condition}) when is_map(condition) do
    output_count = switch_output_count(condition) + 1
    max(output_count - 2, 0) * @condition_output_height
  end

  defp condition_outputs_height(_boolean_or_invalid), do: 0.0

  defp switch_output_count(%{"blocks" => blocks}) when is_list(blocks), do: length(blocks)
  defp switch_output_count(%{"rules" => rules}) when is_list(rules), do: length(rules)
  defp switch_output_count(_condition), do: 0

  defp base_node_height(%{"type" => type}), do: Map.get(@node_heights, type, @default_node_height)
  defp base_node_height(_node), do: @default_node_height
end
