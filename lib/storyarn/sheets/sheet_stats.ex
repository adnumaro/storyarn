defmodule Storyarn.Sheets.SheetStats do
  @moduledoc false

  import Ecto.Query, warn: false

  alias Storyarn.Flows.VariableReference
  alias Storyarn.Localization.LocalizableWords
  alias Storyarn.Repo
  alias Storyarn.Sheets.Block
  alias Storyarn.Sheets.HealthChecker
  alias Storyarn.Sheets.HealthSnapshots
  alias Storyarn.Sheets.Sheet
  alias Storyarn.Sheets.TableColumn
  alias Storyarn.Sheets.TableRow

  @variable_types ~w(text rich_text number select multi_select boolean date)

  # ===========================================================================
  # Stats
  # ===========================================================================

  @variable_column_types ~w(number text boolean select multi_select date reference formula)

  @doc """
  Returns per-sheet block and variable counts for all sheets in a project.
  Includes both regular block variables and table cell variables (row × column).
  Returns `%{sheet_id => %{block_count, variable_count}}`.
  """
  def sheet_stats_for_project(project_id) do
    # Regular block counts + non-table variable counts
    base_stats =
      from(s in Sheet,
        left_join: b in Block,
        on: b.sheet_id == s.id and is_nil(b.deleted_at),
        where: s.project_id == ^project_id and is_nil(s.deleted_at),
        group_by: s.id,
        select:
          {s.id,
           %{
             block_count: count(b.id),
             variable_count:
               fragment(
                 "COUNT(CASE WHEN ? = ANY(?) AND ? = false THEN 1 END)",
                 b.type,
                 ^@variable_types,
                 b.is_constant
               )
           }}
      )
      |> Repo.all()
      |> Map.new()

    # Table cell variable counts: rows × variable columns per table block per sheet
    table_var_counts =
      from(tc in TableColumn,
        join: b in Block,
        on: tc.block_id == b.id,
        join: s in Sheet,
        on: b.sheet_id == s.id,
        join: tr in TableRow,
        on: tr.block_id == b.id,
        where:
          s.project_id == ^project_id and is_nil(s.deleted_at) and is_nil(b.deleted_at) and
            b.type == "table" and
            tc.type in ^@variable_column_types and
            (tc.is_constant == false or tc.type == "formula"),
        group_by: s.id,
        select: {s.id, count()}
      )
      |> Repo.all()
      |> Map.new()

    # Merge table variable counts into base stats
    Map.new(base_stats, fn {sheet_id, stats} ->
      table_vars = Map.get(table_var_counts, sheet_id, 0)
      {sheet_id, %{stats | variable_count: stats.variable_count + table_vars}}
    end)
  end

  @doc """
  Returns per-sheet localizable word counts from the runtime export contract:
  - Active sheet names
  - `value.content` for active, exported text/rich_text variables

  Editor-only descriptions, labels, placeholders, options, table metadata, and
  gallery metadata are excluded.

  Returns `%{sheet_id => word_count}`.
  """
  defdelegate sheet_word_counts(project_id), to: LocalizableWords

  @doc """
  Returns a MapSet of block IDs that have at least one variable reference,
  including references stored in table formula bindings.
  """
  def referenced_block_ids_for_project(project_id) do
    tracked_ids =
      from(vr in VariableReference,
        join: b in Block,
        on: vr.block_id == b.id,
        join: s in Sheet,
        on: b.sheet_id == s.id,
        where: s.project_id == ^project_id and is_nil(s.deleted_at) and is_nil(b.deleted_at),
        distinct: vr.block_id,
        select: vr.block_id
      )
      |> Repo.all()
      |> MapSet.new()

    MapSet.union(tracked_ids, formula_referenced_block_ids(project_id))
  end

  # ===========================================================================
  # Dashboard Health Overview
  # ===========================================================================

  @doc """
  Project-wide sheet health findings for the dashboard.

  The sibling of `Flows.list_dashboard_health_findings/1` and
  `Scenes.list_dashboard_health_findings/1`: it runs the SAME `HealthChecker` over
  the SAME snapshot the editor checks, so every one of the 26 codes the popover can
  show can also reach the dashboard. Nothing here re-detects anything.

  This replaced three hand-written aggregate detectors that covered 3 of the 26
  codes and capped unused variables at 10 — on a real 34-sheet project that was 10
  findings reported out of 140. Counts therefore go UP: that is the correction.

  `referenced_ids` is `referenced_block_ids_for_project/1`, which the dashboard
  already caches for its "variables in use" stat; pass it to save the four queries.

  Findings carry the location the caller needs for a label — the sheet name plus
  the block, row, and column names — because resolving those per finding is a query
  per finding.
  """
  def list_dashboard_health_findings(project_id, referenced_ids \\ nil) do
    project_id
    |> HealthSnapshots.load_project(referenced_ids)
    |> Enum.flat_map(fn snapshot ->
      labels = location_labels(snapshot)

      snapshot
      |> HealthChecker.check()
      |> Enum.map(&locate(&1, snapshot.sheet, labels))
    end)
  end

  # ===========================================================================
  # Private
  # ===========================================================================

  defp locate(finding, sheet, labels) do
    details =
      %{sheet_name: sheet.name}
      |> maybe_put(:block_label, Map.get(labels.blocks, finding.block_id))
      |> maybe_put(:row_label, Map.get(labels.rows, finding.row_id))
      |> maybe_put(:column_label, Map.get(labels.columns, finding.column_id))
      |> Map.merge(finding.details)

    %{finding | details: details}
  end

  defp maybe_put(details, _key, nil), do: details
  defp maybe_put(details, key, value), do: Map.put(details, key, value)

  # The dashboard shows one flat list across every sheet, so a finding that only
  # said "Sheet" would be unattributable. Labels come from data already loaded for
  # the snapshot; blank ones are dropped so the caller falls back to an identifier.
  defp location_labels(snapshot) do
    blocks = Map.new(snapshot.blocks, &{&1.id, present(get_in(&1.config || %{}, ["label"]))})

    {rows, columns} =
      Enum.reduce(snapshot.table_data, {%{}, %{}}, fn {_block_id, table}, {rows, columns} ->
        {Map.merge(rows, Map.new(table.rows, &{&1.id, present(&1.name)})),
         Map.merge(columns, Map.new(table.columns, &{&1.id, present(&1.name)}))}
      end)

    %{blocks: blocks, rows: rows, columns: columns}
  end

  defp present(value) when is_binary(value) do
    if String.trim(value) == "", do: nil, else: value
  end

  defp present(_value), do: nil

  defp formula_referenced_block_ids(project_id) do
    reference_pairs =
      project_id
      |> formula_column_slugs_by_block()
      |> formula_reference_pairs()
      |> MapSet.new()

    resolve_reference_pairs(project_id, reference_pairs)
  end

  defp formula_column_slugs_by_block(project_id) do
    from(column in TableColumn,
      join: source_block in Block,
      on: column.block_id == source_block.id,
      join: source_sheet in Sheet,
      on: source_block.sheet_id == source_sheet.id,
      where:
        source_sheet.project_id == ^project_id and is_nil(source_sheet.deleted_at) and
          is_nil(source_block.deleted_at) and column.type == "formula",
      select: {source_block.id, column.slug}
    )
    |> Repo.all()
    |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))
  end

  defp formula_reference_pairs(formula_slugs_by_block) when map_size(formula_slugs_by_block) == 0, do: []

  defp formula_reference_pairs(formula_slugs_by_block) do
    block_ids = Map.keys(formula_slugs_by_block)

    from(row in TableRow,
      where: row.block_id in ^block_ids,
      select: {row.block_id, row.cells}
    )
    |> Repo.all()
    |> Enum.flat_map(fn {block_id, cells} ->
      formula_slugs_by_block
      |> Map.fetch!(block_id)
      |> Enum.flat_map(fn slug ->
        cells
        |> Map.get(slug)
        |> formula_variable_reference_pairs()
      end)
    end)
  end

  defp formula_variable_reference_pairs(%{"bindings" => bindings}) when is_map(bindings) do
    bindings
    |> Map.values()
    |> Enum.flat_map(fn
      %{"type" => "variable", "ref" => reference} when is_binary(reference) ->
        case String.split(reference, ".") do
          [sheet_shortcut, variable_name | _rest]
          when sheet_shortcut != "" and variable_name != "" ->
            [{sheet_shortcut, variable_name}]

          _other ->
            []
        end

      _other ->
        []
    end)
  end

  defp formula_variable_reference_pairs(_cell), do: []

  defp resolve_reference_pairs(project_id, reference_pairs) do
    shortcuts = reference_pairs |> Enum.map(&elem(&1, 0)) |> Enum.uniq()

    from(block in Block,
      join: sheet in Sheet,
      on: block.sheet_id == sheet.id,
      where:
        sheet.project_id == ^project_id and
          fragment("COALESCE(?, CAST(? AS TEXT))", sheet.shortcut, sheet.id) in ^shortcuts and
          is_nil(sheet.deleted_at) and is_nil(block.deleted_at),
      select: {
        coalesce(sheet.shortcut, fragment("CAST(? AS TEXT)", sheet.id)),
        block.variable_name,
        block.id
      }
    )
    |> Repo.all()
    |> Enum.reduce(MapSet.new(), fn {shortcut, variable_name, block_id}, referenced_ids ->
      if MapSet.member?(reference_pairs, {shortcut, variable_name}) do
        MapSet.put(referenced_ids, block_id)
      else
        referenced_ids
      end
    end)
  end
end
