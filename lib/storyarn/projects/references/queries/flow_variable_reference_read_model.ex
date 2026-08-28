defmodule Storyarn.Projects.FlowVariableReferenceReadModel do
  @moduledoc false

  import Ecto.Query

  alias Storyarn.Projects.FlowVariableNamespaceResolver
  alias Storyarn.Projects.Persistence.BlockRecord
  alias Storyarn.Projects.Persistence.FlowNodeRecord
  alias Storyarn.Projects.Persistence.SheetRecord
  alias Storyarn.Projects.Persistence.TableColumnRecord
  alias Storyarn.Projects.Persistence.TableRowRecord
  alias Storyarn.Projects.Persistence.VariableReferenceRecord
  alias Storyarn.Repo

  require FlowVariableNamespaceResolver

  def list_stale_node_ids_by_flow([]), do: %{}

  def list_stale_node_ids_by_flow(flow_ids) when is_list(flow_ids) do
    flow_ids
    |> stale_reference_rows()
    |> Enum.reduce(%{}, fn {flow_id, node_id}, by_flow ->
      Map.update(by_flow, flow_id, MapSet.new([node_id]), &MapSet.put(&1, node_id))
    end)
  end

  defp stale_reference_rows(flow_ids), do: stale_regular_rows(flow_ids) ++ stale_table_rows(flow_ids)

  defp stale_regular_rows(flow_ids) do
    Repo.all(
      from(reference in VariableReferenceRecord,
        join: node in FlowNodeRecord,
        on: reference.source_type == "flow_node" and node.id == reference.source_id,
        join: block in BlockRecord,
        on: block.id == reference.block_id,
        join: sheet in SheetRecord,
        on: sheet.id == block.sheet_id,
        where:
          node.flow_id in ^flow_ids and is_nil(node.deleted_at) and
            is_nil(sheet.deleted_at) and is_nil(block.deleted_at) and block.type != "table",
        where:
          not FlowVariableNamespaceResolver.authoritative_namespace_owner?(sheet) or
            reference.source_sheet != coalesce(sheet.shortcut, fragment("CAST(? AS TEXT)", sheet.id)) or
            reference.source_variable != block.variable_name,
        distinct: true,
        select: {node.flow_id, node.id}
      )
    )
  end

  defp stale_table_rows(flow_ids) do
    table_cell_exists =
      from(row in TableRowRecord,
        join: column in TableColumnRecord,
        on: column.block_id == row.block_id,
        where:
          parent_as(:reference).source_variable ==
            fragment("? || '.' || ? || '.' || ?", parent_as(:block).variable_name, row.slug, column.slug),
        select: 1
      )

    Repo.all(
      from(reference in VariableReferenceRecord,
        as: :reference,
        join: node in FlowNodeRecord,
        on: reference.source_type == "flow_node" and node.id == reference.source_id,
        join: block in BlockRecord,
        as: :block,
        on: block.id == reference.block_id,
        join: sheet in SheetRecord,
        on: sheet.id == block.sheet_id,
        where:
          node.flow_id in ^flow_ids and is_nil(node.deleted_at) and
            is_nil(sheet.deleted_at) and is_nil(block.deleted_at) and block.type == "table",
        where:
          not FlowVariableNamespaceResolver.authoritative_namespace_owner?(sheet) or
            reference.source_sheet != coalesce(sheet.shortcut, fragment("CAST(? AS TEXT)", sheet.id)) or
            not exists(table_cell_exists),
        distinct: true,
        select: {node.flow_id, node.id}
      )
    )
  end

  @doc """
  Stale variable references for MANY flows at once, keyed by flow and node.

  Mirrors the Sheet-owned export query exactly — including its omission of the
  node soft-delete filter — because the export validators pin that behavior.
  `list_stale_node_ids_by_flow/1` above keeps its own (node-filtering) shape.
  """
  @spec list_stale_node_variable_refs_by_flow([integer()]) ::
          %{integer() => %{integer() => MapSet.t(String.t())}}
  def list_stale_node_variable_refs_by_flow([]), do: %{}

  def list_stale_node_variable_refs_by_flow(flow_ids) when is_list(flow_ids) do
    regular = stale_regular_refs(flow_ids)
    table = stale_table_refs(flow_ids)

    Enum.reduce(regular ++ table, %{}, fn
      {flow_id, node_id, source_sheet, source_variable}, refs_by_flow ->
        full_ref = "#{source_sheet}.#{source_variable}"

        Map.update(
          refs_by_flow,
          flow_id,
          %{node_id => MapSet.new([full_ref])},
          &Map.update(&1, node_id, MapSet.new([full_ref]), fn refs ->
            MapSet.put(refs, full_ref)
          end)
        )
    end)
  end

  defp stale_regular_refs(flow_ids) do
    Repo.all(
      from(reference in VariableReferenceRecord,
        join: node in FlowNodeRecord,
        on: reference.source_type == "flow_node" and node.id == reference.source_id,
        join: block in BlockRecord,
        on: block.id == reference.block_id,
        join: sheet in SheetRecord,
        on: sheet.id == block.sheet_id,
        where: node.flow_id in ^flow_ids,
        where: is_nil(sheet.deleted_at),
        where: is_nil(block.deleted_at),
        where: block.type != "table",
        where:
          not FlowVariableNamespaceResolver.authoritative_namespace_owner?(sheet) or
            reference.source_sheet != coalesce(sheet.shortcut, fragment("CAST(? AS TEXT)", sheet.id)) or
            reference.source_variable != block.variable_name,
        distinct: true,
        select: {node.flow_id, node.id, reference.source_sheet, reference.source_variable}
      )
    )
  end

  defp stale_table_refs(flow_ids) do
    table_cell_exists =
      from(row in TableRowRecord,
        join: column in TableColumnRecord,
        on: column.block_id == row.block_id,
        where:
          parent_as(:stale_ref).source_variable ==
            fragment("? || '.' || ? || '.' || ?", parent_as(:stale_block).variable_name, row.slug, column.slug),
        select: 1
      )

    Repo.all(
      from(reference in VariableReferenceRecord,
        as: :stale_ref,
        join: node in FlowNodeRecord,
        on: reference.source_type == "flow_node" and node.id == reference.source_id,
        join: block in BlockRecord,
        as: :stale_block,
        on: block.id == reference.block_id,
        join: sheet in SheetRecord,
        on: sheet.id == block.sheet_id,
        where: node.flow_id in ^flow_ids,
        where: is_nil(sheet.deleted_at),
        where: is_nil(block.deleted_at),
        where: block.type == "table",
        where:
          not FlowVariableNamespaceResolver.authoritative_namespace_owner?(sheet) or
            reference.source_sheet != coalesce(sheet.shortcut, fragment("CAST(? AS TEXT)", sheet.id)) or
            not exists(table_cell_exists),
        distinct: true,
        select: {node.flow_id, node.id, reference.source_sheet, reference.source_variable}
      )
    )
  end
end
