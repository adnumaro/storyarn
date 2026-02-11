defmodule Storyarn.Screenplays.PageTreeBuilder do
  @moduledoc """
  Builds a recursive page tree from screenplay elements and flattens it
  into a list of node attributes + connection specifications.

  Pure-function module — no DB calls. Receives preloaded data.
  Used by `FlowSync.sync_to_flow/1` for multi-page screenplay sync.
  """

  alias Storyarn.Screenplays.{ElementGrouping, NodeMapping}

  @doc """
  Builds a page tree from preloaded screenplay data.

  Input shape:
      %{
        screenplay_id: integer(),
        elements: [ScreenplayElement.t()],
        children: [page_data()]  # same shape, recursive
      }

  Returns a page tree:
      %{
        screenplay_id: integer(),
        node_attrs_list: [map()],
        branches: [%{choice_id: String.t(), source_node_index: integer(), child: page_tree()}]
      }
  """
  def build(page_data, opts \\ [])

  def build(%{screenplay_id: screenplay_id, elements: elements, children: children}, opts) do
    child_page = Keyword.get(opts, :child_page, false)
    groups = ElementGrouping.group_elements(elements)
    node_attrs_list = NodeMapping.groups_to_node_attrs(groups, child_page: child_page)
    children_by_id = Map.new(children, fn c -> {c.screenplay_id, c} end)
    branches = find_branches(node_attrs_list, children_by_id)

    %{
      screenplay_id: screenplay_id,
      node_attrs_list: node_attrs_list,
      branches: branches
    }
  end

  @doc """
  Flattens a page tree into a flat list of node attrs, connection specs,
  and screenplay IDs involved.

  Returns:
      %{
        all_node_attrs: [map()],
        connections: [%{source_index, target_index, source_pin, target_pin}],
        screenplay_ids: [integer()]
      }
  """
  def flatten(page_tree) do
    {all_attrs, connections, screenplay_ids, _offset} = flatten_tree(page_tree, 0)

    %{
      all_node_attrs: all_attrs,
      connections: connections,
      screenplay_ids: screenplay_ids
    }
  end

  # ---------------------------------------------------------------------------
  # Private — Build
  # ---------------------------------------------------------------------------

  defp find_branches(node_attrs_list, children_by_id) do
    node_attrs_list
    |> Enum.with_index()
    |> Enum.flat_map(fn {attrs, index} ->
      if attrs.type == "dialogue" do
        find_dialogue_branches(attrs, index, children_by_id)
      else
        []
      end
    end)
  end

  defp find_dialogue_branches(attrs, index, children_by_id) do
    responses = (attrs.data || %{})["responses"] || []

    Enum.flat_map(responses, fn response ->
      response_to_branch(response, index, children_by_id)
    end)
  end

  defp response_to_branch(response, index, children_by_id) do
    child_id = response["linked_screenplay_id"]

    case child_id && Map.get(children_by_id, child_id) do
      nil ->
        []

      child_data ->
        child_tree = build(child_data, child_page: true)

        if child_tree.node_attrs_list == [] do
          []
        else
          [%{choice_id: response["id"], source_node_index: index, child: child_tree}]
        end
    end
  end

  # ---------------------------------------------------------------------------
  # Private — Flatten
  # ---------------------------------------------------------------------------

  defp flatten_tree(tree, offset) do
    attrs = tree.node_attrs_list
    count = length(attrs)
    branching_indices = MapSet.new(tree.branches, & &1.source_node_index)
    sequential = build_sequential_connections(attrs, offset, branching_indices)

    {child_attrs, branch_conns, child_ids, final_offset} =
      Enum.reduce(tree.branches, {[], [], [], offset + count}, fn branch, {ca, bc, ci, cur} ->
        {child_all, child_conns, child_screenplay_ids, child_end} =
          flatten_tree(branch.child, cur)

        branch_conn =
          if child_all != [] do
            [%{
              source_index: offset + branch.source_node_index,
              target_index: cur,
              source_pin: branch.choice_id,
              target_pin: "input"
            }]
          else
            []
          end

        {ca ++ child_all, bc ++ branch_conn ++ child_conns, ci ++ child_screenplay_ids, child_end}
      end)

    {
      attrs ++ child_attrs,
      sequential ++ branch_conns,
      [tree.screenplay_id | child_ids],
      final_offset
    }
  end

  defp build_sequential_connections(attrs, offset, branching_indices) do
    attrs
    |> Enum.with_index()
    |> Enum.chunk_every(2, 1, :discard)
    |> Enum.flat_map(fn [{source, src_idx}, {_target, tgt_idx}] ->
      cond do
        source.type in ["exit", "jump"] ->
          []

        source.type == "condition" ->
          [
            %{source_index: offset + src_idx, target_index: offset + tgt_idx, source_pin: "true", target_pin: "input"},
            %{source_index: offset + src_idx, target_index: offset + tgt_idx, source_pin: "false", target_pin: "input"}
          ]

        MapSet.member?(branching_indices, src_idx) ->
          []

        true ->
          [%{source_index: offset + src_idx, target_index: offset + tgt_idx, source_pin: "output", target_pin: "input"}]
      end
    end)
  end
end
