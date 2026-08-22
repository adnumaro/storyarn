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
end
