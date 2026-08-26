defmodule Storyarn.Sheets.Health.Queries.Snapshots do
  @moduledoc """
  Builds the enriched snapshots `Sheets.Health` consumes — for the one
  sheet open in the editor, and for every sheet in a project.

  BOTH builders live here on purpose. The checker is a pure function over a
  snapshot, so the dashboard runs the exact same 26 rules the editor runs instead
  of reimplementing a handful of them as aggregate SQL; what decides the verdicts
  is then the snapshot, and two builders in two layers is how the two surfaces
  come to disagree about the same sheet. The editor enters through
  `Sheets.sheet_health_findings/1`, the dashboard through `load_project/2`, and
  the enrichment below is written once for both.

  They differ only in how much they read at a time. Built one sheet at a time the
  snapshot costs ~21 queries (713 for a 34-sheet project, measured), so
  `load_project/2` loads every field ONCE for the whole project and slices it per
  sheet — a fixed query count, whatever the sheet count. Slicing is not the same
  as re-deriving, which is why
  `test/storyarn/sheets/health/integration/dashboard_coverage_test.exs` pins the two against
  each other sheet by sheet.
  """

  alias Storyarn.Sheets.Block
  alias Storyarn.Sheets.Editor
  alias Storyarn.Sheets.Health.Queries.Stats
  alias Storyarn.Sheets.Health.Rules.Checker
  alias Storyarn.Sheets.Logic
  alias Storyarn.Sheets.References

  @doc """
  Checks the sheet open in the editor: build its snapshot, then run the checker.
  """
  @spec findings(map()) :: [Checker.finding()]
  def findings(material), do: material |> snapshot() |> Checker.check()

  @doc """
  One checker-ready snapshot from the material the sheet editor already holds:
  `:sheet`, `:project`, the sheet's own `:blocks`, its `:inherited_groups`, and
  the `:table_data` and `:gallery_data` already loaded to render it. Nothing on
  screen is read a second time.

  What it does fetch is the project-wide enrichment the checker needs beyond that
  material — the same enrichment `load_project/2` fetches once for every sheet.
  Public because the agreement test drives this builder rather than a copy of it.
  """
  @spec snapshot(map()) :: map()
  def snapshot(%{sheet: sheet, project: project, blocks: own_blocks, inherited_groups: inherited_groups} = material) do
    blocks = visible_blocks({inherited_groups, own_blocks})
    block_ids = Enum.map(blocks, & &1.id)

    # Project-wide on purpose: a variable bound by a table formula IS used, and
    # The tracked-reference projection only sees explicit variable references and
    # does not know that, so the editor header used to claim "no internal usages"
    # for a block the dashboard correctly reported as used.
    referenced_block_ids = Stats.referenced_block_ids_for_project(project.id)

    %{
      sheet: sheet,
      blocks: blocks,
      table_data: Map.get(material, :table_data) || %{},
      gallery_data: Map.get(material, :gallery_data) || %{},
      has_children: Editor.has_children?(sheet.id),
      inheritance_issues: Editor.list_inheritance_health_issues(sheet.id),
      referenced_block_ids: referenced_block_ids,
      stale_variable_reference_counts: stale_variable_reference_counts(blocks, referenced_block_ids, project.id),
      stale_entity_reference_block_ids: References.list_stale_block_reference_source_ids(project.id, block_ids),
      reference_targets: reference_targets(blocks, project.id),
      project_variable_types: variable_types(project.id)
    }
  end

  @doc """
  Returns one checker-ready snapshot per active sheet of the project.

  Pass `referenced_ids` when the caller already has
  `Health.referenced_block_ids_for_project/1` cached — the dashboard does, for
  its "variables in use" stat.
  """
  @spec load_project(integer(), MapSet.t() | nil) :: [map()]
  def load_project(project_id, referenced_ids \\ nil) do
    sheets = Editor.list_sheets_unpreloaded(project_id)

    if sheets == [] do
      []
    else
      build_snapshots(project_id, sheets, referenced_ids)
    end
  end

  defp build_snapshots(project_id, sheets, referenced_ids) do
    blocks_by_sheet =
      sheets
      |> Editor.list_project_blocks_grouped()
      |> Map.new(fn {sheet_id, grouped} -> {sheet_id, visible_blocks(grouped)} end)

    all_blocks = blocks_by_sheet |> Map.values() |> List.flatten()

    enrichment = enrichment(project_id, sheets, all_blocks, referenced_ids)

    Enum.map(sheets, fn sheet ->
      sliced_snapshot(sheet, Map.get(blocks_by_sheet, sheet.id, []), enrichment)
    end)
  end

  # Same assembly the editor does: inherited blocks first, grouped by source
  # sheet, then the sheet's own. Block order decides which block of a column group
  # carries an `invalid_block_layout` finding, so it is part of the contract.
  defp visible_blocks({inherited_groups, own_blocks}) do
    Enum.flat_map(inherited_groups, & &1.blocks) ++ own_blocks
  end

  # The project sweep's per-sheet slice of the shared enrichment. Field for field
  # the same map `snapshot/1` builds for the editor — that is the contract.
  defp sliced_snapshot(sheet, blocks, enrichment) do
    block_ids = Enum.map(blocks, & &1.id)

    %{
      sheet: sheet,
      blocks: blocks,
      table_data: Map.take(enrichment.table_data, block_ids),
      gallery_data: Map.take(enrichment.gallery_data, block_ids),
      has_children: MapSet.member?(enrichment.parent_sheet_ids, sheet.id),
      inheritance_issues: Map.get(enrichment.inheritance_issues, sheet.id, []),
      referenced_block_ids: enrichment.referenced_block_ids,
      stale_variable_reference_counts: enrichment.stale_variable_reference_counts,
      stale_entity_reference_block_ids: enrichment.stale_entity_reference_block_ids,
      reference_targets: Map.take(enrichment.reference_targets, block_ids),
      project_variable_types: enrichment.project_variable_types
    }
  end

  defp enrichment(project_id, sheets, all_blocks, referenced_ids) do
    referenced_block_ids = referenced_ids || Stats.referenced_block_ids_for_project(project_id)
    block_ids = Enum.map(all_blocks, & &1.id)
    raw_table_data = table_data(all_blocks)

    inheritance_issues =
      Editor.list_project_inheritance_health_issues(sheets, raw_table_data)

    table_data = Logic.enrich_table_formulas(raw_table_data, project_id)

    %{
      table_data: table_data,
      gallery_data: gallery_data(all_blocks),
      parent_sheet_ids: sheets |> Enum.map(& &1.parent_id) |> Enum.reject(&is_nil/1) |> MapSet.new(),
      inheritance_issues: inheritance_issues,
      referenced_block_ids: referenced_block_ids,
      stale_variable_reference_counts: stale_variable_reference_counts(all_blocks, referenced_block_ids, project_id),
      stale_entity_reference_block_ids: References.list_stale_block_reference_source_ids(project_id, block_ids),
      reference_targets: reference_targets(all_blocks, project_id),
      project_variable_types: variable_types(project_id)
    }
  end

  defp table_data(all_blocks) do
    case block_ids_of_type(all_blocks, "table") do
      [] -> %{}
      table_ids -> Editor.batch_load_table_data(table_ids)
    end
  end

  defp gallery_data(all_blocks) do
    case block_ids_of_type(all_blocks, "gallery") do
      [] -> %{}
      gallery_ids -> Editor.batch_load_gallery_data(gallery_ids)
    end
  end

  defp block_ids_of_type(blocks, type) do
    blocks |> Enum.filter(&(&1.type == type)) |> Enum.map(& &1.id)
  end

  defp stale_variable_reference_counts(blocks, referenced_block_ids, project_id) do
    blocks
    |> Enum.filter(&(MapSet.member?(referenced_block_ids, &1.id) and Block.variable?(&1)))
    |> Enum.map(& &1.id)
    |> References.count_stale_variable_references(project_id)
  end

  defp reference_targets(blocks, project_id) do
    references =
      blocks
      |> Enum.filter(&(&1.type == "reference"))
      |> Enum.map(&reference_target_key/1)

    targets =
      references
      |> Enum.map(fn {_block_id, target_type, target_id} -> {target_type, target_id} end)
      |> References.get_reference_targets(project_id)

    Map.new(references, fn {block_id, target_type, target_id} ->
      {block_id, Map.get(targets, {target_type, target_id})}
    end)
  end

  # `nil` is the ONLY non-map `value` that can reach here — the column is nullable
  # — because `Block` declares `field :value, :map` and Ecto's loader raises on a
  # jsonb scalar (verified for strings, numbers, booleans, arrays and
  # `'null'::jsonb`) long before a row reaches this function. A catch-all for
  # shapes the schema cannot produce would hide a loader change, not survive one.
  defp reference_target_key(%{id: id, value: value}) when is_map(value) do
    {id, Map.get(value, "target_type"), Map.get(value, "target_id")}
  end

  defp reference_target_key(%{id: id, value: nil}), do: {id, nil, nil}

  @doc """
  The vocabulary the health checker type-checks formula bindings against:
  `%{"sheet_shortcut.variable_name" => block_type}`.

  The ONE definition, because the reference format is load-bearing — a binding is
  valid only if its `ref` hits a key here, and table cells fold their row and
  column slugs into `variable_name` (`hero.stats.resolve.base`), so a second copy
  that spelled a ref differently would call every table-cell binding invalid on
  one surface and not the other. Worse, two copies edited the same wrong way keep
  the surfaces equal and both wrong, which the agreement test cannot see. The
  editor reaches this through `Sheets.health_variable_types/1`.
  """
  @spec variable_types(integer()) :: %{String.t() => String.t()}
  def variable_types(project_id) do
    project_id
    |> Logic.list_project_variables()
    |> Map.new(fn variable ->
      {"#{variable.sheet_shortcut}.#{variable.variable_name}", variable.block_type}
    end)
  end
end
