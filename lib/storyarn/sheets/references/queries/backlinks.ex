defmodule Storyarn.Sheets.References.Queries.Backlinks do
  @moduledoc """
  Read side of the Sheet-owned entity-reference projection.

  It resolves backlinks and stale targets through References-local records,
  keeping read concerns separate from the transactional replacement commands.
  """

  import Ecto.Query

  alias Storyarn.Repo
  alias Storyarn.Sheets.Block
  alias Storyarn.Sheets.References.Entities.EntityReferenceRecord
  alias Storyarn.Sheets.References.Projections.FlowNodeRecord
  alias Storyarn.Sheets.References.Projections.FlowRecord
  alias Storyarn.Sheets.References.Queries.Scenes
  alias Storyarn.Sheets.References.Rules.RichTextMentions
  alias Storyarn.Sheets.Sheet

  @spec flow_node_references_current?(map()) :: boolean()
  def flow_node_references_current?(%{id: node_id, data: data}) when is_integer(node_id) and is_map(data) do
    node_id in flow_node_references_current_ids([%{id: node_id, data: data}])
  end

  def flow_node_references_current?(_node), do: false

  @spec flow_node_references_current_ids([map()]) :: MapSet.t(integer())
  def flow_node_references_current_ids(nodes) when is_list(nodes) do
    valid_nodes =
      Enum.filter(nodes, fn
        %{id: node_id, data: data} when is_integer(node_id) and is_map(data) -> true
        _node -> false
      end)

    node_ids = Enum.map(valid_nodes, & &1.id)
    actual_by_node = flow_node_reference_sets(node_ids)

    Enum.reduce(valid_nodes, MapSet.new(), fn node, current_ids ->
      expected = expected_flow_node_reference_set(node.data)
      actual = Map.get(actual_by_node, node.id, MapSet.new())

      if expected == actual,
        do: MapSet.put(current_ids, node.id),
        else: current_ids
    end)
  end

  @doc "Returns every reference pointing to a target, newest first."
  @spec get_backlinks(String.t(), any()) :: [EntityReferenceRecord.t()]
  def get_backlinks(target_type, target_id) do
    Repo.all(
      from(reference in EntityReferenceRecord,
        where:
          reference.target_type == ^target_type and
            reference.target_id == ^target_id,
        order_by: [desc: reference.inserted_at]
      )
    )
  end

  @doc "Returns active block ids whose tracked target is stale or outside the project."
  @spec list_stale_block_reference_source_ids(integer(), [integer()]) :: MapSet.t()
  def list_stale_block_reference_source_ids(_project_id, []), do: MapSet.new()

  def list_stale_block_reference_source_ids(project_id, block_ids) do
    project_id
    |> stale_block_reference_query(block_ids)
    |> Repo.all()
    |> MapSet.new()
  end

  @doc "Resolves active Sheet and Flow targets in a fixed number of queries."
  @spec get_reference_targets([{String.t() | nil, integer() | nil}], integer()) :: map()
  def get_reference_targets(references, project_id) when is_list(references) do
    sheet_ids = reference_target_ids(references, "sheet")
    flow_ids = reference_target_ids(references, "flow")

    sheet_targets =
      Repo.all(
        from(sheet in Sheet,
          where:
            sheet.project_id == ^project_id and sheet.id in ^sheet_ids and
              is_nil(sheet.deleted_at),
          select: %{
            type: "sheet",
            id: sheet.id,
            name: sheet.name,
            shortcut: sheet.shortcut
          }
        )
      )

    flow_targets =
      Repo.all(
        from(flow in FlowRecord,
          where:
            flow.project_id == ^project_id and flow.id in ^flow_ids and
              is_nil(flow.deleted_at),
          select: %{
            type: "flow",
            id: flow.id,
            name: flow.name,
            shortcut: flow.shortcut
          }
        )
      )

    Map.new(sheet_targets ++ flow_targets, &{{&1.type, &1.id}, &1})
  end

  @doc "Returns backlinks enriched with their active Sheet, Flow, or Scene source."
  @spec get_backlinks_with_sources(String.t(), any(), integer()) :: [map()]
  def get_backlinks_with_sources(target_type, target_id, project_id) do
    block_backlinks = query_block_backlinks(target_type, target_id, project_id)
    flow_backlinks = query_flow_node_backlinks(target_type, target_id, project_id)
    pin_backlinks = Scenes.pin_backlinks(target_type, target_id, project_id)
    zone_backlinks = Scenes.zone_backlinks(target_type, target_id, project_id)

    Enum.sort_by(
      block_backlinks ++ flow_backlinks ++ pin_backlinks ++ zone_backlinks,
      & &1.inserted_at,
      {:desc, NaiveDateTime}
    )
  end

  @doc "Counts every backlink recorded for a target."
  @spec count_backlinks(String.t(), any()) :: non_neg_integer()
  def count_backlinks(target_type, target_id) do
    Repo.one(
      from(reference in EntityReferenceRecord,
        where:
          reference.target_type == ^target_type and
            reference.target_id == ^target_id,
        select: count(reference.id)
      )
    )
  end

  defp flow_node_reference_sets([]), do: %{}

  defp flow_node_reference_sets(node_ids) do
    from(reference in EntityReferenceRecord,
      where:
        reference.source_type == "flow_node" and
          reference.source_id in ^node_ids,
      select: {
        reference.source_id,
        reference.target_type,
        reference.target_id,
        reference.context
      }
    )
    |> Repo.all()
    |> Enum.reduce(%{}, fn {source_id, target_type, target_id, context}, references ->
      reference = {target_type, target_id, context}
      Map.update(references, source_id, MapSet.new([reference]), &MapSet.put(&1, reference))
    end)
  end

  defp expected_flow_node_reference_set(data) do
    data
    |> extract_flow_node_refs()
    |> Enum.map(fn reference ->
      {reference.type, parse_id(reference.id), reference.context}
    end)
    |> Enum.reject(fn {_type, target_id, _context} -> is_nil(target_id) end)
    |> MapSet.new()
  end

  defp extract_flow_node_refs(data) do
    refs =
      []
      |> maybe_add_sheet_ref(data["speaker_sheet_id"], "speaker")
      |> maybe_add_sheet_ref(data["location_sheet_id"], "location")

    mention_refs =
      data
      |> RichTextMentions.html_candidates()
      |> Enum.flat_map(&extract_mentions_from_html/1)
      |> Enum.map(&Map.put(&1, :context, "dialogue"))

    mention_refs ++ refs
  end

  defp extract_mentions_from_html(content) when is_binary(content) do
    case RichTextMentions.extract_from_html(content) do
      {:ok, mentions} -> Enum.map(mentions, &Map.put(&1, :context, "content"))
      {:error, _reason} -> []
    end
  end

  defp extract_mentions_from_html(_content), do: []

  defp maybe_add_sheet_ref(refs, value, _context) when value in [nil, ""], do: refs

  defp maybe_add_sheet_ref(refs, sheet_id, context) do
    [%{type: "sheet", id: sheet_id, context: context} | refs]
  end

  defp parse_id(id) when is_integer(id), do: id

  defp parse_id(id) when is_binary(id) do
    case Integer.parse(id) do
      {integer, ""} -> integer
      _invalid -> nil
    end
  end

  defp parse_id(_id), do: nil

  defp reference_target_ids(references, target_type) do
    references
    |> Enum.flat_map(fn
      {^target_type, target_id} when is_integer(target_id) and target_id > 0 -> [target_id]
      _reference -> []
    end)
    |> Enum.uniq()
  end

  defp stale_block_reference_query(project_id, block_ids) do
    EntityReferenceRecord
    |> join_block_reference_sources(project_id, block_ids)
    |> join_block_reference_targets(project_id)
    |> filter_stale_block_reference_targets()
    |> distinct(true)
    |> select([source_block: source_block], source_block.id)
  end

  defp join_block_reference_sources(query, project_id, block_ids) do
    from(reference in query,
      as: :reference,
      join: source_block in Block,
      as: :source_block,
      on:
        reference.source_type == "block" and
          reference.source_id == source_block.id,
      join: source_sheet in Sheet,
      as: :source_sheet,
      on: source_sheet.id == source_block.sheet_id,
      where:
        source_block.id in ^block_ids and source_sheet.project_id == ^project_id and
          is_nil(source_block.deleted_at) and is_nil(source_sheet.deleted_at)
    )
  end

  defp join_block_reference_targets(query, project_id) do
    from([reference: reference] in query,
      left_join: target_sheet in Sheet,
      as: :target_sheet,
      on:
        reference.target_type == "sheet" and reference.target_id == target_sheet.id and
          target_sheet.project_id == ^project_id and is_nil(target_sheet.deleted_at),
      left_join: target_flow in FlowRecord,
      as: :target_flow,
      on:
        reference.target_type == "flow" and reference.target_id == target_flow.id and
          target_flow.project_id == ^project_id and is_nil(target_flow.deleted_at)
    )
  end

  defp filter_stale_block_reference_targets(query) do
    from(
      [reference: reference, target_sheet: target_sheet, target_flow: target_flow] in query,
      where:
        (reference.target_type == "sheet" and is_nil(target_sheet.id)) or
          (reference.target_type == "flow" and is_nil(target_flow.id))
    )
  end

  defp query_block_backlinks(target_type, target_id, project_id) do
    from(reference in EntityReferenceRecord,
      join: block in Block,
      on:
        reference.source_type == "block" and
          reference.source_id == block.id,
      join: sheet in Sheet,
      on: block.sheet_id == sheet.id,
      where:
        reference.target_type == ^target_type and reference.target_id == ^target_id and
          sheet.project_id == ^project_id and is_nil(sheet.deleted_at) and
          is_nil(block.deleted_at),
      select: %{
        id: reference.id,
        source_type: reference.source_type,
        source_id: reference.source_id,
        context: reference.context,
        inserted_at: reference.inserted_at,
        block_type: block.type,
        block_label: fragment("?->>'label'", block.config),
        sheet_id: sheet.id,
        sheet_name: sheet.name,
        sheet_shortcut: sheet.shortcut
      },
      order_by: [desc: reference.inserted_at]
    )
    |> Repo.all()
    |> Enum.map(fn reference ->
      %{
        id: reference.id,
        source_type: "block",
        source_id: reference.source_id,
        context: reference.context,
        inserted_at: reference.inserted_at,
        source_info: %{
          type: :sheet,
          sheet_id: reference.sheet_id,
          sheet_name: reference.sheet_name,
          sheet_shortcut: reference.sheet_shortcut,
          block_type: reference.block_type,
          block_label: reference.block_label
        }
      }
    end)
  end

  defp query_flow_node_backlinks(target_type, target_id, project_id) do
    from(reference in EntityReferenceRecord,
      join: node in FlowNodeRecord,
      on:
        reference.source_type == "flow_node" and
          reference.source_id == node.id,
      join: flow in FlowRecord,
      on: node.flow_id == flow.id,
      where:
        reference.target_type == ^target_type and reference.target_id == ^target_id and
          flow.project_id == ^project_id and is_nil(node.deleted_at) and
          is_nil(flow.deleted_at),
      select: %{
        id: reference.id,
        source_type: reference.source_type,
        source_id: reference.source_id,
        context: reference.context,
        inserted_at: reference.inserted_at,
        node_type: node.type,
        flow_id: flow.id,
        flow_name: flow.name,
        flow_shortcut: flow.shortcut
      },
      order_by: [desc: reference.inserted_at]
    )
    |> Repo.all()
    |> Enum.map(fn reference ->
      %{
        id: reference.id,
        source_type: "flow_node",
        source_id: reference.source_id,
        context: reference.context,
        inserted_at: reference.inserted_at,
        source_info: %{
          type: :flow,
          flow_id: reference.flow_id,
          flow_name: reference.flow_name,
          flow_shortcut: reference.flow_shortcut,
          node_type: reference.node_type
        }
      }
    end)
  end
end
