defmodule Storyarn.Projects.References.VariableReferenceResolutionQueries do
  @moduledoc """
  Persistence-backed resolution of normalized variable-reference specs.

  Extraction remains pure; this query module maps authored namespaces and
  qualified references to active Project-owned Sheet projections.
  """

  import Ecto.Query

  alias Storyarn.Projects.References.Persistence.BlockRecord, as: Block
  alias Storyarn.Projects.References.Persistence.FlowRecord
  alias Storyarn.Projects.References.Persistence.SheetRecord, as: Sheet
  alias Storyarn.Projects.References.Persistence.TableColumnRecord, as: TableColumn
  alias Storyarn.Projects.References.Persistence.TableRowRecord, as: TableRow
  alias Storyarn.Projects.References.VariableCatalog
  alias Storyarn.Projects.References.VariableNamespaceResolver
  alias Storyarn.Projects.References.VariableReference
  alias Storyarn.Repo

  require VariableNamespaceResolver

  @regular_variable_types VariableCatalog.regular_variable_types()
  @table_variable_types VariableCatalog.table_variable_types()
  @constant_table_variable_types VariableCatalog.constant_table_variable_types()

  def resolve_reference_block_ids(project_id, specs) do
    resolution_keys = MapSet.new(specs, & &1.resolution_key)

    regular_keys =
      for {:regular, _sheet, _variable} = key <- resolution_keys,
          do: key

    table_keys =
      for {:table, _sheet, _table, _row, _column} = key <-
            resolution_keys,
          do: key

    qualified_refs =
      for {:qualified, qualified_ref} <- resolution_keys,
          do: qualified_ref

    project_id
    |> resolve_regular_block_ids(regular_keys)
    |> Map.merge(resolve_table_block_ids(project_id, table_keys))
    |> Map.merge(resolve_qualified_reference_definitions(project_id, qualified_refs))
  end

  defp resolve_qualified_reference_definitions(_project_id, []), do: %{}

  defp resolve_qualified_reference_definitions(project_id, qualified_refs) do
    definitions =
      qualified_regular_reference_definitions(project_id, qualified_refs) ++
        qualified_table_reference_definitions(project_id, qualified_refs)

    Map.new(definitions, fn {qualified_ref, source_sheet, source_variable, block_id} ->
      {{:qualified, qualified_ref}, %{block_id: block_id, source_sheet: source_sheet, source_variable: source_variable}}
    end)
  end

  defp qualified_regular_reference_definitions(project_id, qualified_refs) do
    Repo.all(
      from(block in Block,
        join: sheet in Sheet,
        on: sheet.id == block.sheet_id,
        where:
          sheet.project_id == ^project_id and is_nil(sheet.deleted_at) and
            is_nil(block.deleted_at) and
            block.type in ^@regular_variable_types and
            block.is_constant == false and
            not is_nil(block.variable_name) and block.variable_name != "" and
            VariableNamespaceResolver.authoritative_namespace_owner?(sheet) and
            fragment(
              "COALESCE(?, CAST(? AS TEXT)) || '.' || ?",
              sheet.shortcut,
              sheet.id,
              block.variable_name
            ) in ^qualified_refs,
        select: {
          fragment(
            "COALESCE(?, CAST(? AS TEXT)) || '.' || ?",
            sheet.shortcut,
            sheet.id,
            block.variable_name
          ),
          coalesce(sheet.shortcut, fragment("CAST(? AS TEXT)", sheet.id)),
          block.variable_name,
          block.id
        }
      )
    )
  end

  defp qualified_table_reference_definitions(project_id, qualified_refs) do
    from(column in TableColumn, as: :column)
    |> join(:inner, [column: column], block in Block,
      as: :block,
      on: block.id == column.block_id
    )
    |> join(:inner, [block: block], sheet in Sheet,
      as: :sheet,
      on: sheet.id == block.sheet_id
    )
    |> join(:inner, [block: block], row in TableRow,
      as: :row,
      on: row.block_id == block.id
    )
    |> where(
      [column: column, block: block, sheet: sheet, row: row],
      sheet.project_id == ^project_id and is_nil(sheet.deleted_at) and
        is_nil(block.deleted_at) and not is_nil(block.variable_name) and
        block.variable_name != "" and
        VariableNamespaceResolver.authoritative_namespace_owner?(sheet) and
        fragment(
          "COALESCE(?, CAST(? AS TEXT)) || '.' || ? || '.' || ? || '.' || ?",
          sheet.shortcut,
          sheet.id,
          block.variable_name,
          row.slug,
          column.slug
        ) in ^qualified_refs
    )
    |> filter_table_variable_targets()
    |> select([column: column, block: block, sheet: sheet, row: row], {
      fragment(
        "COALESCE(?, CAST(? AS TEXT)) || '.' || ? || '.' || ? || '.' || ?",
        sheet.shortcut,
        sheet.id,
        block.variable_name,
        row.slug,
        column.slug
      ),
      coalesce(sheet.shortcut, fragment("CAST(? AS TEXT)", sheet.id)),
      fragment("? || '.' || ? || '.' || ?", block.variable_name, row.slug, column.slug),
      block.id
    })
    |> Repo.all()
  end

  defp filter_table_variable_targets(query) do
    from([column: column, block: block] in query,
      where:
        block.type == "table" and
          column.type in ^@table_variable_types and
          (column.is_constant == false or
             column.type in ^@constant_table_variable_types)
    )
  end

  defp resolve_regular_block_ids(_project_id, []), do: %{}

  defp resolve_regular_block_ids(project_id, keys) do
    namespaces =
      keys
      |> Enum.map(&elem(&1, 1))
      |> Enum.uniq()

    namespace_ids = VariableNamespaceResolver.resolve_sheet_ids(project_id, namespaces)
    namespace_by_id = Map.new(namespace_ids, fn {namespace, id} -> {id, namespace} end)
    sheet_ids = Map.keys(namespace_by_id)

    variable_names =
      keys
      |> Enum.map(&elem(&1, 2))
      |> Enum.uniq()

    from(block in Block,
      join: sheet in Sheet,
      on: sheet.id == block.sheet_id,
      where:
        sheet.project_id == ^project_id and
          sheet.id in ^sheet_ids and
          block.variable_name in ^variable_names and
          block.type in ^@regular_variable_types and
          block.is_constant == false and
          is_nil(sheet.deleted_at) and
          is_nil(block.deleted_at),
      select: {sheet.id, block.variable_name, block.id}
    )
    |> Repo.all()
    |> Map.new(fn {sheet_id, variable_name, block_id} ->
      {{:regular, Map.fetch!(namespace_by_id, sheet_id), variable_name}, block_id}
    end)
  end

  defp resolve_table_block_ids(_project_id, []), do: %{}

  defp resolve_table_block_ids(project_id, keys) do
    namespaces = keys |> Enum.map(&elem(&1, 1)) |> Enum.uniq()
    namespace_ids = VariableNamespaceResolver.resolve_sheet_ids(project_id, namespaces)
    namespace_by_id = Map.new(namespace_ids, fn {namespace, id} -> {id, namespace} end)
    sheet_ids = Map.keys(namespace_by_id)
    table_names = keys |> Enum.map(&elem(&1, 2)) |> Enum.uniq()
    row_slugs = keys |> Enum.map(&elem(&1, 3)) |> Enum.uniq()
    column_slugs = keys |> Enum.map(&elem(&1, 4)) |> Enum.uniq()

    from(block in Block, as: :block)
    |> join(:inner, [block: block], sheet in Sheet,
      as: :sheet,
      on: sheet.id == block.sheet_id
    )
    |> join(:inner, [block: block], row in TableRow,
      as: :row,
      on: row.block_id == block.id
    )
    |> join(:inner, [block: block], column in TableColumn,
      as: :column,
      on: column.block_id == block.id
    )
    |> where(
      [block: block, sheet: sheet, row: row, column: column],
      sheet.project_id == ^project_id and
        sheet.id in ^sheet_ids and
        block.variable_name in ^table_names and
        row.slug in ^row_slugs and
        column.slug in ^column_slugs and
        is_nil(sheet.deleted_at) and
        is_nil(block.deleted_at)
    )
    |> filter_table_variable_targets()
    |> select([block: block, sheet: sheet, row: row, column: column], {
      sheet.id,
      block.variable_name,
      row.slug,
      column.slug,
      block.id
    })
    |> Repo.all()
    |> Map.new(fn {sheet_id, table_name, row_slug, column_slug, block_id} ->
      namespace = Map.fetch!(namespace_by_id, sheet_id)
      {{:table, namespace, table_name, row_slug, column_slug}, block_id}
    end)
  end

  def actual_flow_node_reference_sets([]), do: %{}

  def actual_flow_node_reference_sets(node_ids) do
    from(reference in VariableReference,
      where:
        reference.source_type == "flow_node" and
          reference.source_id in ^node_ids,
      select: {
        reference.source_id,
        reference.block_id,
        reference.kind,
        reference.source_sheet,
        reference.source_variable,
        reference.flow_node_id
      }
    )
    |> Repo.all()
    |> Enum.reduce(
      %{},
      fn
        {
          source_id,
          block_id,
          kind,
          source_sheet,
          source_variable,
          flow_node_id
        },
        references ->
          reference =
            {
              block_id,
              kind,
              source_sheet,
              source_variable,
              flow_node_id
            }

          Map.update(
            references,
            source_id,
            MapSet.new([reference]),
            &MapSet.put(&1, reference)
          )
      end
    )
  end

  def flow_project_id(flow_id) do
    Repo.one(from(f in FlowRecord, where: f.id == ^flow_id, select: f.project_id))
  end
end
