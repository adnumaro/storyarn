defmodule Storyarn.Sheets.InheritanceAudit do
  @moduledoc """
  Non-mutating audit of block inheritance: compares eligible ancestor definitions
  with the instances that materialize them.

  The detection lives here, apart from the loading, because there are two callers
  with very different loading strategies — one sheet at a time for the editor, and
  once for a whole project for the dashboard sweep — and they must not be able to
  reach different verdicts. `PropertyInheritance` owns the resolution (which
  ancestor blocks are eligible for a sheet) and calls in with the result.

  The table signature helpers are public because the inheritance write path
  verifies the same structural equality before mutating.
  """

  import Ecto.Query, warn: false

  alias Storyarn.Repo
  alias Storyarn.Sheets.Block
  alias Storyarn.Sheets.TableColumn
  alias Storyarn.Sheets.TableRow

  @type issue :: %{
          required(:reason) => String.t(),
          required(:block_id) => integer() | nil,
          required(:source_block_id) => integer() | nil
        }

  @doc """
  Reports missing, duplicate, orphaned, stale-definition, and stale-table-structure
  states for one sheet.

  `eligible_sources` are the ancestor definitions that should be present on the
  sheet, `instances` the active non-detached blocks that claim to materialize them,
  and `table_structures` the columns and rows of every table block among both, as
  returned by `table_structures/1`.
  """
  @spec issues([Block.t()], [Block.t()], map()) :: [issue()]
  def issues(eligible_sources, instances, table_structures) do
    sources_by_id = Map.new(eligible_sources, &{&1.id, &1})
    instances_by_source = Enum.group_by(instances, & &1.inherited_from_block_id)

    missing_instance_issues(eligible_sources, instances_by_source) ++
      duplicate_instance_issues(instances_by_source) ++
      instance_issues(instances, sources_by_id, table_structures)
  end

  @doc """
  Loads the columns and rows of every table block in `blocks`, in two queries.

  Returns `%{block_id => {columns, rows}}`.
  """
  @spec table_structures([Block.t()]) :: %{integer() => {[TableColumn.t()], [TableRow.t()]}}
  def table_structures(blocks) do
    block_ids =
      blocks
      |> Enum.filter(&(&1.type == "table"))
      |> Enum.map(& &1.id)

    columns =
      Repo.all(
        from(column in TableColumn,
          where: column.block_id in ^block_ids,
          order_by: [asc: column.block_id, asc: column.position, asc: column.id]
        )
      )

    rows =
      Repo.all(
        from(row in TableRow,
          where: row.block_id in ^block_ids,
          order_by: [asc: row.block_id, asc: row.position, asc: row.id]
        )
      )

    # Grouped ONCE, not re-scanned per block: the per-block helpers below each
    # walk the whole loaded set, so calling them in this loop made the sweep
    # O(blocks x (columns + rows)) on a project's every table. The queries above
    # already order by `block_id, position, id` and `Enum.group_by/2` preserves
    # input order within a group, so the grouped lists are the same lists the
    # helpers' `sort_by` produced.
    columns_by_block = Enum.group_by(columns, & &1.block_id)
    rows_by_block = Enum.group_by(rows, & &1.block_id)

    Map.new(block_ids, fn block_id ->
      {block_id, {Map.get(columns_by_block, block_id, []), Map.get(rows_by_block, block_id, [])}}
    end)
  end

  @doc """
  Reuses table data that a caller has already loaded, without querying or
  decoding the rows and their `cells` maps a second time.

  Accepts the `%{block_id => %{columns: columns, rows: rows}}` shape returned by
  `Storyarn.Sheets.TableCrud.batch_load_table_data/1`. The returned lists share
  the already-loaded structs; only the outer structure map is rebuilt.
  """
  @spec table_structures_from_data(%{
          optional(integer()) => %{required(:columns) => [TableColumn.t()], required(:rows) => [TableRow.t()]}
        }) :: %{integer() => {[TableColumn.t()], [TableRow.t()]}}
  def table_structures_from_data(table_data) when is_map(table_data) do
    Map.new(table_data, fn {block_id, data} ->
      {block_id, {Map.fetch!(data, :columns), Map.fetch!(data, :rows)}}
    end)
  end

  @doc "Filters and orders the columns belonging to one block."
  @spec columns_for_block([TableColumn.t()], integer()) :: [TableColumn.t()]
  def columns_for_block(columns, block_id) do
    columns
    |> Enum.filter(&(&1.block_id == block_id))
    |> Enum.sort_by(&{&1.position, &1.id})
  end

  @doc "Filters and orders the rows belonging to one block."
  @spec rows_for_block([TableRow.t()], integer()) :: [TableRow.t()]
  def rows_for_block(rows, block_id) do
    rows
    |> Enum.filter(&(&1.block_id == block_id))
    |> Enum.sort_by(&{&1.position, &1.id})
  end

  @doc "Structural identity of a table column: everything an instance must copy."
  @spec column_signature(TableColumn.t()) :: tuple()
  def column_signature(column) do
    {
      column.slug,
      column.name,
      column.type,
      column.is_constant,
      column.required,
      column.position,
      column.config
    }
  end

  @doc "Structural identity of a table row."
  @spec row_signature(TableRow.t()) :: tuple()
  def row_signature(row), do: {row.slug, row.name, row.position}

  @doc "True when the instance still mirrors its source definition."
  @spec definition_current?(Block.t(), Block.t()) :: boolean()
  def definition_current?(source, instance) do
    instance.type == source.type and
      instance.config == source.config and
      instance.required == source.required and
      instance.is_constant == source.is_constant and
      instance.scope == "self"
  end

  @doc "True when the instance's table structure still mirrors its source."
  @spec table_structure_current?(Block.t(), Block.t(), map()) :: boolean()
  def table_structure_current?(%Block{type: "table"} = source, instance, structures) do
    {source_columns, source_rows} = Map.get(structures, source.id, {[], []})
    {instance_columns, instance_rows} = Map.get(structures, instance.id, {[], []})

    Enum.map(source_columns, &column_signature/1) == Enum.map(instance_columns, &column_signature/1) and
      Enum.map(source_rows, &row_signature/1) == Enum.map(instance_rows, &row_signature/1) and
      cell_keys_current?(source_columns, instance_rows)
  end

  def table_structure_current?(_source, _instance, _structures), do: true

  @doc "True when every instance row carries exactly the source's cell keys."
  @spec cell_keys_current?([TableColumn.t()], [TableRow.t()]) :: boolean()
  def cell_keys_current?(source_columns, instance_rows) do
    expected_cell_keys = MapSet.new(source_columns, & &1.slug)
    Enum.all?(instance_rows, &(MapSet.new(Map.keys(&1.cells || %{})) == expected_cell_keys))
  end

  # ===========================================================================
  # Private
  # ===========================================================================

  defp missing_instance_issues(eligible_sources, instances_by_source) do
    eligible_sources
    |> Enum.reject(&Map.has_key?(instances_by_source, &1.id))
    |> Enum.map(&issue("missing_instance", nil, &1.id))
  end

  defp duplicate_instance_issues(instances_by_source) do
    Enum.flat_map(instances_by_source, fn {source_id, instances} ->
      if length(instances) > 1 do
        [issue("duplicate_instances", hd(instances).id, source_id, %{instance_ids: Enum.map(instances, & &1.id)})]
      else
        []
      end
    end)
  end

  defp instance_issues(instances, sources_by_id, table_structures) do
    Enum.flat_map(instances, fn instance ->
      source = Map.get(sources_by_id, instance.inherited_from_block_id)

      cond do
        is_nil(source) ->
          [issue("source_not_eligible", instance.id, instance.inherited_from_block_id)]

        not definition_current?(source, instance) ->
          [issue("stale_definition", instance.id, source.id)]

        not table_structure_current?(source, instance, table_structures) ->
          [issue("stale_table_structure", instance.id, source.id)]

        true ->
          []
      end
    end)
  end

  defp issue(reason, block_id, source_block_id, details \\ %{}) do
    Map.merge(details, %{
      reason: reason,
      block_id: block_id,
      source_block_id: source_block_id
    })
  end
end
