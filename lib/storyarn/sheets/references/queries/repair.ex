defmodule Storyarn.Sheets.References.Queries.Repair do
  @moduledoc """
  Read-side for detecting and repairing stale Sheet variable references.

  It owns the SQL comparison between stored reference paths and the current
  Sheet variable vocabulary. Repair writes remain in References commands.
  """

  import Ecto.Query, warn: false

  alias Storyarn.Repo
  alias Storyarn.Sheets.Block
  alias Storyarn.Sheets.Logic
  alias Storyarn.Sheets.References.Data.FlowNodeRecord
  alias Storyarn.Sheets.References.Data.FlowRecord
  alias Storyarn.Sheets.References.Data.VariableReferenceRecord
  alias Storyarn.Sheets.Sheet
  alias Storyarn.Sheets.TableColumn
  alias Storyarn.Sheets.TableRow

  require Logic

  @doc "Returns variable references with current block data for stale repair."
  def list_with_block_info(project_id) do
    Repo.all(
      from(reference in VariableReferenceRecord,
        join: node in FlowNodeRecord,
        on: reference.source_type == "flow_node" and node.id == reference.source_id,
        join: flow in FlowRecord,
        on: flow.id == node.flow_id,
        join: block in Block,
        on: block.id == reference.block_id,
        join: sheet in Sheet,
        on: sheet.id == block.sheet_id,
        where: flow.project_id == ^project_id,
        where: is_nil(flow.deleted_at),
        where: is_nil(sheet.deleted_at),
        where: is_nil(block.deleted_at),
        where: Logic.authoritative_namespace_owner?(sheet),
        select: %{
          node_id: node.id,
          node_type: node.type,
          node_data: node.data,
          kind: reference.kind,
          block_id: reference.block_id,
          current_shortcut: coalesce(sheet.shortcut, fragment("CAST(? AS TEXT)", sheet.id)),
          current_variable: block.variable_name,
          source_sheet: reference.source_sheet,
          source_variable: reference.source_variable
        }
      )
    )
  end

  @doc "Returns stale regular-variable node IDs in one Flow."
  @spec list_stale_regular_node_ids(integer()) :: MapSet.t()
  def list_stale_regular_node_ids(flow_id) do
    [flow_id] |> stale_regular_references() |> node_ids_for_flow(flow_id)
  end

  @doc "Returns stale table-variable node IDs in one Flow."
  @spec list_stale_table_node_ids(integer()) :: MapSet.t()
  def list_stale_table_node_ids(flow_id) do
    [flow_id] |> stale_table_references() |> node_ids_for_flow(flow_id)
  end

  defp stale_regular_references(flow_ids) do
    Repo.all(
      from(reference in VariableReferenceRecord,
        join: node in FlowNodeRecord,
        on: reference.source_type == "flow_node" and node.id == reference.source_id,
        join: block in Block,
        on: block.id == reference.block_id,
        join: sheet in Sheet,
        on: sheet.id == block.sheet_id,
        where: node.flow_id in ^flow_ids,
        where: is_nil(sheet.deleted_at),
        where: is_nil(block.deleted_at),
        where: block.type != "table",
        where:
          not Logic.authoritative_namespace_owner?(sheet) or
            reference.source_sheet != coalesce(sheet.shortcut, fragment("CAST(? AS TEXT)", sheet.id)) or
            reference.source_variable != block.variable_name,
        distinct: true,
        select: {node.flow_id, node.id, reference.source_sheet, reference.source_variable}
      )
    )
  end

  defp stale_table_references(flow_ids) do
    table_cell_exists =
      from(row in TableRow,
        join: column in TableColumn,
        on: column.block_id == row.block_id,
        where:
          parent_as(:reference).source_variable ==
            fragment(
              "? || '.' || ? || '.' || ?",
              parent_as(:block).variable_name,
              row.slug,
              column.slug
            ),
        select: 1
      )

    Repo.all(
      from(reference in VariableReferenceRecord,
        as: :reference,
        join: node in FlowNodeRecord,
        on: reference.source_type == "flow_node" and node.id == reference.source_id,
        join: block in Block,
        as: :block,
        on: block.id == reference.block_id,
        join: sheet in Sheet,
        on: sheet.id == block.sheet_id,
        where: node.flow_id in ^flow_ids,
        where: is_nil(sheet.deleted_at),
        where: is_nil(block.deleted_at),
        where: block.type == "table",
        where:
          not Logic.authoritative_namespace_owner?(sheet) or
            reference.source_sheet != coalesce(sheet.shortcut, fragment("CAST(? AS TEXT)", sheet.id)) or
            not exists(table_cell_exists),
        distinct: true,
        select: {node.flow_id, node.id, reference.source_sheet, reference.source_variable}
      )
    )
  end

  defp node_ids_for_flow(references, flow_id) do
    for {^flow_id, node_id, _source_sheet, _source_variable} <- references,
        into: MapSet.new(),
        do: node_id
  end

  @doc "Resolves a regular variable to its active block ID."
  def resolve_block_id(project_id, sheet_shortcut, variable_name) do
    variable_types = Logic.regular_variable_types()

    case Logic.resolve_sheet_id(project_id, sheet_shortcut) do
      nil ->
        nil

      sheet_id ->
        Repo.one(
          from(block in Block,
            join: sheet in Sheet,
            on: sheet.id == block.sheet_id,
            where: sheet.project_id == ^project_id and sheet.id == ^sheet_id,
            where: block.variable_name == ^variable_name,
            where: block.type in ^variable_types,
            where: block.is_constant == false,
            where: is_nil(sheet.deleted_at),
            where: is_nil(block.deleted_at),
            select: block.id,
            limit: 1
          )
        )
    end
  end

  @doc "Resolves a table-cell variable path to its active table block ID."
  def resolve_table_block_id(project_id, sheet_shortcut, table_name, row_slug, column_slug) do
    variable_types = Logic.table_variable_types()
    constant_variable_types = Logic.constant_table_variable_types()

    case Logic.resolve_sheet_id(project_id, sheet_shortcut) do
      nil ->
        nil

      sheet_id ->
        Repo.one(
          from(block in Block,
            join: sheet in Sheet,
            on: sheet.id == block.sheet_id,
            join: row in TableRow,
            on: row.block_id == block.id,
            join: column in TableColumn,
            on: column.block_id == block.id,
            where: sheet.project_id == ^project_id and sheet.id == ^sheet_id,
            where: block.variable_name == ^table_name,
            where: block.type == "table",
            where: column.type in ^variable_types,
            where: column.is_constant == false or column.type in ^constant_variable_types,
            where: row.slug == ^row_slug,
            where: column.slug == ^column_slug,
            where: is_nil(sheet.deleted_at),
            where: is_nil(block.deleted_at),
            select: block.id,
            limit: 1
          )
        )
    end
  end

  @doc "Lists Sheet IDs addressed by recorded variable references in a project."
  def list_referenced_sheet_ids(project_id) do
    from(reference in VariableReferenceRecord,
      join: block in Block,
      on: reference.block_id == block.id,
      join: sheet in Sheet,
      on: block.sheet_id == sheet.id,
      where: sheet.project_id == ^project_id,
      select: sheet.id
    )
    |> Repo.all()
    |> MapSet.new()
  end
end
