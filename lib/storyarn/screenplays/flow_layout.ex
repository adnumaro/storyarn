defmodule Storyarn.Screenplays.FlowLayout do
  @moduledoc """
  Pure-function module that computes node positions for tree-aware flow layout.

  Positions branches horizontally at response nodes and stacks each branch
  vertically. Used by `FlowSync` to position new nodes after sync.
  """

  @x_center 400.0
  @x_gap 350.0
  @y_start 100.0
  @y_spacing 150.0

  @doc """
  Computes positions for all nodes in a page tree.

  Returns a map of `%{node_id => {x, y}}`.

  The `page_tree` is the recursive structure from `PageTreeBuilder.build/2`.
  The `all_nodes` is the flat list of flow nodes matching `PageTreeBuilder.flatten/1` order.
  """
  @spec compute_positions(map(), [map()]) :: %{integer() => {float(), float()}}
  def compute_positions(page_tree, all_nodes) do
    {positions, _y_end, _offset} = layout_page(page_tree, all_nodes, 0, @x_center, @y_start)
    positions
  end

  # ---------------------------------------------------------------------------
  # Private
  # ---------------------------------------------------------------------------

  defp layout_page(
         %{node_attrs_list: attrs, branches: branches},
         all_nodes,
         offset,
         x_center,
         y_start
       ) do
    branches_by_index = Enum.group_by(branches, & &1.source_node_index)
    initial_child_offset = offset + length(attrs)

    attrs
    |> Enum.with_index()
    |> Enum.reduce({%{}, y_start, initial_child_offset}, fn {_attr, local_idx}, {pos, y, c_off} ->
      node = Enum.at(all_nodes, offset + local_idx)
      layout_node(node, pos, y, c_off, x_center, all_nodes, Map.get(branches_by_index, local_idx))
    end)
  end

  defp layout_node(nil, pos, y, c_off, _x_center, _all_nodes, _idx_branches) do
    {pos, y + @y_spacing, c_off}
  end

  defp layout_node(node, pos, y, c_off, x_center, _all_nodes, nil) do
    {Map.put(pos, node.id, {x_center, y}), y + @y_spacing, c_off}
  end

  defp layout_node(node, pos, y, c_off, x_center, all_nodes, idx_branches) do
    pos = Map.put(pos, node.id, {x_center, y})

    {branch_pos, max_y_end, new_c_off} =
      layout_branches(idx_branches, all_nodes, c_off, x_center, y + @y_spacing)

    {Map.merge(pos, branch_pos), max_y_end, new_c_off}
  end

  defp layout_branches(branches, all_nodes, child_offset, parent_x, branch_y) do
    branch_widths = Enum.map(branches, &subtree_width(&1.child))
    total_width = Enum.sum(branch_widths) + max(length(branches) - 1, 0) * @x_gap
    start_x = parent_x - total_width / 2.0

    {positions, max_y_end, final_offset, _x} =
      branches
      |> Enum.zip(branch_widths)
      |> Enum.reduce({%{}, branch_y, child_offset, start_x}, fn {branch, width},
                                                                {pos, max_y, c_off, x} ->
        center = x + width / 2.0

        {child_pos, child_y_end, new_c_off} =
          layout_page(branch.child, all_nodes, c_off, center, branch_y)

        {Map.merge(pos, child_pos), max(max_y, child_y_end), new_c_off, x + width + @x_gap}
      end)

    {positions, max_y_end, final_offset}
  end

  defp subtree_width(%{branches: []}), do: 0.0

  defp subtree_width(%{branches: branches}) do
    widths = Enum.map(branches, &max(subtree_width(&1.child), 0.0))
    Enum.sum(widths) + max(length(branches) - 1, 0) * @x_gap
  end
end
