defmodule Storyarn.Projects.SheetHealthReadModel do
  @moduledoc """
  Project-owned Sheet health sweep for the project dashboard.

  Runs the exact snapshot assembly and checker the Sheet editor uses — copied
  field for field over Project-owned records — so every finding code the
  editor popover can show also reaches the dashboard, with identical counts.
  """

  import Ecto.Query, warn: false

  alias Storyarn.Platform.Shared.MapUtils
  alias Storyarn.Projects.FlowFormulaEngine, as: FormulaEngine
  alias Storyarn.Projects.FlowVariableNamespaceResolver, as: VariableNamespaceResolver
  alias Storyarn.Projects.Persistence.BlockGalleryImageRecord, as: BlockGalleryImage
  alias Storyarn.Projects.Persistence.BlockRecord, as: Block
  alias Storyarn.Projects.Persistence.EntityReferenceRecord, as: EntityReference
  alias Storyarn.Projects.Persistence.FlowRecord
  alias Storyarn.Projects.Persistence.SheetRecord, as: Sheet
  alias Storyarn.Projects.Persistence.TableColumnRecord, as: TableColumn
  alias Storyarn.Projects.Persistence.TableRowRecord, as: TableRow
  alias Storyarn.Projects.Persistence.VariableReferenceRecord
  alias Storyarn.Projects.References
  alias Storyarn.Projects.SheetFormulaResolver
  alias Storyarn.Projects.SheetHealthChecker
  alias Storyarn.Projects.SheetInheritanceAudit
  alias Storyarn.Repo

  require VariableNamespaceResolver

  # ===========================================================================
  # Dashboard entry points (mirror of the Sheet tool's stats surface)
  # ===========================================================================

  @doc """
  Project-wide sheet health findings for the dashboard.

  Runs the SAME checker over the SAME snapshot the editor checks; findings
  carry the sheet/block/row/column labels the dashboard needs.
  """
  def list_dashboard_health_findings(project_id, referenced_ids \\ nil) do
    project_id
    |> load_project(referenced_ids)
    |> Enum.flat_map(fn snapshot ->
      labels = location_labels(snapshot)

      snapshot
      |> SheetHealthChecker.check()
      |> Enum.map(&locate(&1, snapshot.sheet, labels))
    end)
  end

  @doc """
  Block IDs with at least one variable reference, including references stored
  in table formula bindings.
  """
  def referenced_block_ids_for_project(project_id) do
    tracked_ids =
      from(reference in VariableReferenceRecord,
        join: block in Block,
        on: reference.block_id == block.id,
        join: sheet in Sheet,
        on: block.sheet_id == sheet.id,
        where: sheet.project_id == ^project_id and is_nil(sheet.deleted_at) and is_nil(block.deleted_at),
        distinct: reference.block_id,
        select: reference.block_id
      )
      |> Repo.all()
      |> MapSet.new()

    MapSet.union(tracked_ids, formula_referenced_block_ids(project_id))
  end

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

  # ===========================================================================
  # Project snapshot loading (mirror of the Sheet tool's health snapshots)
  # ===========================================================================

  defp load_project(project_id, referenced_ids) do
    sheets = list_sheets_unpreloaded(project_id)

    if sheets == [] do
      []
    else
      build_snapshots(project_id, sheets, referenced_ids)
    end
  end

  defp list_sheets_unpreloaded(project_id) do
    Repo.all(
      from(sheet in Sheet,
        where: sheet.project_id == ^project_id and is_nil(sheet.deleted_at),
        order_by: [asc: sheet.position, asc: sheet.name]
      )
    )
  end

  defp build_snapshots(project_id, sheets, referenced_ids) do
    blocks_by_sheet =
      sheets
      |> list_project_blocks_grouped()
      |> Map.new(fn {sheet_id, grouped} -> {sheet_id, visible_blocks(grouped)} end)

    all_blocks = blocks_by_sheet |> Map.values() |> List.flatten()

    enrichment = enrichment(project_id, sheets, all_blocks, referenced_ids)

    Enum.map(sheets, fn sheet ->
      sliced_snapshot(sheet, Map.get(blocks_by_sheet, sheet.id, []), enrichment)
    end)
  end

  # Same assembly the editor does: inherited blocks first, grouped by source
  # sheet, then the sheet's own. Block order decides which block of a column
  # group carries an `invalid_block_layout` finding, so it is part of the
  # contract.
  defp visible_blocks({inherited_groups, own_blocks}) do
    Enum.flat_map(inherited_groups, & &1.blocks) ++ own_blocks
  end

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
    referenced_block_ids = referenced_ids || referenced_block_ids_for_project(project_id)
    block_ids = Enum.map(all_blocks, & &1.id)
    raw_table_data = table_data(all_blocks)

    inheritance_issues = list_project_health_issues(sheets, raw_table_data)

    table_data = SheetFormulaResolver.enrich_table_data(raw_table_data, project_id)

    %{
      table_data: table_data,
      gallery_data: gallery_data(all_blocks),
      parent_sheet_ids: sheets |> Enum.map(& &1.parent_id) |> Enum.reject(&is_nil/1) |> MapSet.new(),
      inheritance_issues: inheritance_issues,
      referenced_block_ids: referenced_block_ids,
      stale_variable_reference_counts: stale_variable_reference_counts(all_blocks, referenced_block_ids, project_id),
      stale_entity_reference_block_ids: list_stale_block_reference_source_ids(project_id, block_ids),
      reference_targets: reference_targets(all_blocks, project_id),
      project_variable_types: variable_types(project_id)
    }
  end

  defp table_data(all_blocks) do
    case block_ids_of_type(all_blocks, "table") do
      [] -> %{}
      table_ids -> batch_load_table_data(table_ids)
    end
  end

  defp gallery_data(all_blocks) do
    case block_ids_of_type(all_blocks, "gallery") do
      [] -> %{}
      gallery_ids -> batch_load_gallery_data(gallery_ids)
    end
  end

  defp block_ids_of_type(blocks, type) do
    blocks |> Enum.filter(&(&1.type == type)) |> Enum.map(& &1.id)
  end

  defp stale_variable_reference_counts(blocks, referenced_block_ids, project_id) do
    blocks
    |> Enum.filter(&(MapSet.member?(referenced_block_ids, &1.id) and variable_block?(&1)))
    |> Enum.map(& &1.id)
    |> References.count_stale_variable_references(project_id)
  end

  @non_variable_types ~w(reference gallery)

  defp variable_block?(%{type: type, is_constant: is_constant}) do
    is_constant == false and type not in @non_variable_types
  end

  defp reference_targets(blocks, project_id) do
    references =
      blocks
      |> Enum.filter(&(&1.type == "reference"))
      |> Enum.map(&reference_target_key/1)

    targets =
      references
      |> Enum.map(fn {_block_id, target_type, target_id} -> {target_type, target_id} end)
      |> get_reference_targets(project_id)

    Map.new(references, fn {block_id, target_type, target_id} ->
      {block_id, Map.get(targets, {target_type, target_id})}
    end)
  end

  defp reference_target_key(%{id: id, value: value}) when is_map(value) do
    {id, Map.get(value, "target_type"), Map.get(value, "target_id")}
  end

  defp reference_target_key(%{id: id, value: nil}), do: {id, nil, nil}

  # ===========================================================================
  # Block grouping (mirror of the Sheet tool's editor slicing)
  # ===========================================================================

  defp list_project_blocks_grouped([]), do: %{}

  defp list_project_blocks_grouped(sheets) do
    sheet_ids = Enum.map(sheets, & &1.id)
    source_sheets_by_id = Map.new(sheets, &{&1.id, &1})

    blocks_by_sheet =
      from(block in Block,
        where: block.sheet_id in ^sheet_ids and is_nil(block.deleted_at),
        order_by: [asc: block.sheet_id, asc: block.position, asc: block.id],
        preload: [:inherited_from_block]
      )
      |> Repo.all()
      |> Enum.group_by(& &1.sheet_id)

    Map.new(sheet_ids, fn sheet_id ->
      {sheet_id, group_blocks(Map.get(blocks_by_sheet, sheet_id, []), source_sheets_by_id)}
    end)
  end

  defp group_blocks(blocks, source_sheets_by_id) do
    {inherited, own} = Enum.split_with(blocks, &inherited_block?/1)

    inherited_groups =
      inherited
      |> Enum.group_by(&inherited_source_sheet_id/1)
      |> Enum.reject(fn {source_sheet_id, _blocks} -> is_nil(source_sheet_id) end)
      |> Enum.map(fn {source_sheet_id, blocks} ->
        %{source_sheet: Map.get(source_sheets_by_id, source_sheet_id), blocks: blocks}
      end)
      |> Enum.reject(fn group -> is_nil(group.source_sheet) end)

    {inherited_groups, own}
  end

  defp inherited_block?(%Block{inherited_from_block_id: nil}), do: false
  defp inherited_block?(%Block{detached: true}), do: false
  defp inherited_block?(%Block{}), do: true

  defp inherited_source_sheet_id(%Block{inherited_from_block: %Block{sheet_id: sheet_id}}), do: sheet_id
  defp inherited_source_sheet_id(_block), do: nil

  # ===========================================================================
  # Inheritance issues (mirror of the Sheet tool's project audit)
  # ===========================================================================

  defp list_project_health_issues([], _table_data), do: %{}

  defp list_project_health_issues(sheets, table_data) do
    sheets_by_id = Map.new(sheets, &{&1.id, &1})
    ancestors_by_sheet = Map.new(sheets, &{&1.id, ancestor_chain(&1, sheets_by_id)})

    sources_by_sheet =
      sheets
      |> Enum.map(& &1.id)
      |> load_children_scope_blocks_for_sheets()
      |> Enum.group_by(& &1.sheet_id)

    instances_by_sheet =
      sheets
      |> Enum.map(& &1.id)
      |> active_inherited_instances_for_sheets()
      |> Enum.group_by(& &1.sheet_id)

    resolved =
      Map.new(sheets, fn sheet ->
        ancestors = Map.get(ancestors_by_sheet, sheet.id, [])
        hidden_source_ids = MapSet.new(collect_hidden_block_ids([sheet | ancestors]))

        sources =
          ancestors
          |> Enum.flat_map(&Map.get(sources_by_sheet, &1.id, []))
          |> Enum.reject(&MapSet.member?(hidden_source_ids, &1.id))

        instances =
          instances_by_sheet
          |> Map.get(sheet.id, [])
          |> Enum.reject(&MapSet.member?(hidden_source_ids, &1.inherited_from_block_id))

        {sheet.id, {sources, instances}}
      end)

    structures = project_table_structures(resolved, table_data)

    Map.new(resolved, fn {sheet_id, {sources, instances}} ->
      {sheet_id, SheetInheritanceAudit.issues(sources, instances, structures)}
    end)
  end

  defp project_table_structures(resolved, nil) do
    resolved
    |> Enum.flat_map(fn {_sheet_id, {sources, instances}} -> sources ++ instances end)
    |> Enum.uniq_by(& &1.id)
    |> SheetInheritanceAudit.table_structures()
  end

  defp project_table_structures(_resolved, table_data) when is_map(table_data) do
    SheetInheritanceAudit.table_structures_from_data(table_data)
  end

  defp ancestor_chain(sheet, sheets_by_id, seen \\ [])

  defp ancestor_chain(%Sheet{parent_id: nil}, _sheets_by_id, _seen), do: []

  defp ancestor_chain(%Sheet{} = sheet, sheets_by_id, seen) do
    case Map.get(sheets_by_id, sheet.parent_id) do
      nil ->
        []

      parent ->
        if parent.id in seen do
          []
        else
          [parent | ancestor_chain(parent, sheets_by_id, [parent.id | seen])]
        end
    end
  end

  defp collect_hidden_block_ids(sheets) do
    sheets
    |> Enum.flat_map(fn sheet ->
      sheet.hidden_inherited_block_ids || []
    end)
    |> Enum.uniq()
  end

  defp load_children_scope_blocks_for_sheets([]), do: []

  defp load_children_scope_blocks_for_sheets(sheet_ids) do
    Repo.all(
      from(block in Block,
        where: block.sheet_id in ^sheet_ids and block.scope == "children" and is_nil(block.deleted_at),
        order_by: [asc: block.position]
      )
    )
  end

  defp active_inherited_instances_for_sheets(sheet_ids) do
    Repo.all(
      from(block in Block,
        where:
          block.sheet_id in ^sheet_ids and
            not is_nil(block.inherited_from_block_id) and
            block.detached == false and is_nil(block.deleted_at),
        order_by: [asc: block.id]
      )
    )
  end

  # ===========================================================================
  # Table and gallery batch loads (mirror of the Sheet tool's loaders)
  # ===========================================================================

  defp batch_load_table_data(block_ids) do
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

    columns_by_block = Enum.group_by(columns, & &1.block_id)
    rows_by_block = Enum.group_by(rows, & &1.block_id)

    Map.new(block_ids, fn block_id ->
      {block_id,
       %{
         columns: Map.get(columns_by_block, block_id, []),
         rows: Map.get(rows_by_block, block_id, [])
       }}
    end)
  end

  defp batch_load_gallery_data(block_ids) do
    from(image in BlockGalleryImage,
      where: image.block_id in ^block_ids,
      order_by: [asc: image.block_id, asc: image.position],
      preload: [:asset]
    )
    |> Repo.all()
    |> Enum.group_by(& &1.block_id)
  end

  # ===========================================================================
  # Variable vocabulary (mirror of the Sheet tool's catalog types)
  # ===========================================================================

  # `%{"sheet_shortcut.variable_name" => block_type}` with the tool's exact
  # filters — table cells fold row and column slugs into the name, and
  # reference columns remap to select/multi_select as the catalog does.
  defp variable_types(project_id) do
    project_id
    |> variable_type_rows()
    |> Map.new(fn {shortcut, variable_name, block_type} ->
      {"#{shortcut}.#{variable_name}", block_type}
    end)
  end

  defp variable_type_rows(project_id) do
    block_variable_types(project_id) ++ table_variable_types(project_id)
  end

  defp block_variable_types(project_id) do
    variable_types = ~w(text rich_text number select multi_select boolean date)

    Repo.all(
      from(block in Block,
        join: sheet in Sheet,
        on: block.sheet_id == sheet.id,
        where:
          sheet.project_id == ^project_id and
            is_nil(sheet.deleted_at) and
            is_nil(block.deleted_at) and
            block.type in ^variable_types and
            block.is_constant == false and
            not is_nil(block.variable_name) and
            block.variable_name != "" and
            VariableNamespaceResolver.authoritative_namespace_owner?(sheet),
        select: {coalesce(sheet.shortcut, fragment("CAST(? AS TEXT)", sheet.id)), block.variable_name, block.type}
      )
    )
  end

  defp table_variable_types(project_id) do
    variable_column_types = ~w(number text boolean select multi_select date reference formula)

    from(column in TableColumn,
      join: block in Block,
      on: column.block_id == block.id,
      join: sheet in Sheet,
      on: block.sheet_id == sheet.id,
      join: row in TableRow,
      on: row.block_id == block.id,
      where: sheet.project_id == ^project_id,
      where: is_nil(sheet.deleted_at) and is_nil(block.deleted_at),
      where: block.type == "table",
      where: column.type in ^variable_column_types,
      where: column.is_constant == false or column.type == "formula",
      where: VariableNamespaceResolver.authoritative_namespace_owner?(sheet),
      select:
        {coalesce(sheet.shortcut, fragment("CAST(? AS TEXT)", sheet.id)),
         fragment("? || '.' || ? || '.' || ?", block.variable_name, row.slug, column.slug), column.type, column.config}
    )
    |> Repo.all()
    |> Enum.map(fn {shortcut, variable_name, type, config} ->
      {shortcut, variable_name, remap_reference_type(type, config)}
    end)
  end

  defp remap_reference_type("reference", config) do
    multiple? = (config || %{})["multiple"]
    if multiple?, do: "multi_select", else: "select"
  end

  defp remap_reference_type(type, _config), do: type

  # ===========================================================================
  # Variable value resolution (mirror of the Sheet tool's formula inputs)
  # ===========================================================================

  @doc false
  def resolve_variable_values(project_id, refs) when is_list(refs) do
    {simple_refs, table_refs} = classify_refs(refs)

    simple_values = resolve_simple_values(project_id, simple_refs)
    table_values = resolve_table_values(project_id, table_refs)

    Map.merge(simple_values, table_values)
  end

  defp classify_refs(refs) do
    Enum.split_with(refs, fn ref ->
      ref |> String.split(".") |> length() == 2
    end)
  end

  defp resolve_simple_values(_project_id, []), do: %{}

  defp resolve_simple_values(project_id, refs) do
    pairs = parse_simple_refs(refs)
    do_resolve_simple(project_id, pairs)
  end

  defp parse_simple_refs(refs) do
    refs
    |> Enum.map(&parse_simple_ref/1)
    |> Enum.reject(&is_nil/1)
  end

  defp parse_simple_ref(ref) do
    case String.split(ref, ".", parts: 2) do
      [shortcut, var_name] -> {shortcut, var_name}
      _ -> nil
    end
  end

  defp do_resolve_simple(_project_id, []), do: %{}

  defp do_resolve_simple(project_id, pairs) do
    namespaces = pairs |> Enum.map(&elem(&1, 0)) |> Enum.uniq()
    namespace_ids = VariableNamespaceResolver.resolve_sheet_ids(project_id, namespaces)
    namespace_by_id = Map.new(namespace_ids, fn {namespace, id} -> {id, namespace} end)
    pair_set = MapSet.new(pairs)

    project_id
    |> query_simple_blocks(Map.keys(namespace_by_id))
    |> Repo.all()
    |> build_simple_results(pair_set, namespace_by_id)
  end

  defp query_simple_blocks(project_id, sheet_ids) do
    from(block in Block,
      join: sheet in Sheet,
      on: block.sheet_id == sheet.id,
      where:
        sheet.project_id == ^project_id and
          is_nil(sheet.deleted_at) and
          is_nil(block.deleted_at) and
          not is_nil(block.variable_name) and
          block.variable_name != "" and
          sheet.id in ^sheet_ids,
      select: %{
        sheet_id: sheet.id,
        variable_name: block.variable_name,
        value: block.value
      }
    )
  end

  defp build_simple_results(rows, pair_set, namespace_by_id) do
    Enum.reduce(rows, %{}, fn row, acc ->
      namespace = Map.fetch!(namespace_by_id, row.sheet_id)

      if MapSet.member?(pair_set, {namespace, row.variable_name}) do
        Map.put(acc, "#{namespace}.#{row.variable_name}", extract_block_value(row.value))
      else
        acc
      end
    end)
  end

  defp resolve_table_values(_project_id, []), do: %{}

  defp resolve_table_values(project_id, refs) do
    parsed = parse_table_refs(refs)
    do_resolve_table(project_id, parsed)
  end

  defp parse_table_refs(refs) do
    refs
    |> Enum.map(&parse_table_ref/1)
    |> Enum.reject(&is_nil/1)
  end

  defp parse_table_ref(ref) do
    case String.split(ref, ".") do
      [shortcut, table_name, row_slug, col_slug] ->
        %{
          shortcut: shortcut,
          table_name: table_name,
          row_slug: row_slug,
          col_slug: col_slug,
          ref: ref
        }

      _ ->
        nil
    end
  end

  defp do_resolve_table(_project_id, []), do: %{}

  defp do_resolve_table(project_id, parsed) do
    namespaces = parsed |> Enum.map(& &1.shortcut) |> Enum.uniq()
    namespace_ids = VariableNamespaceResolver.resolve_sheet_ids(project_id, namespaces)
    namespace_by_id = Map.new(namespace_ids, fn {namespace, id} -> {id, namespace} end)
    rows = project_id |> query_table_rows(Map.keys(namespace_by_id)) |> Repo.all()

    Enum.reduce(parsed, %{}, fn entry, acc ->
      match_table_row(rows, entry, acc, namespace_by_id)
    end)
  end

  defp query_table_rows(project_id, sheet_ids) do
    from(row in TableRow,
      join: block in Block,
      on: row.block_id == block.id,
      join: sheet in Sheet,
      on: block.sheet_id == sheet.id,
      where:
        sheet.project_id == ^project_id and
          is_nil(sheet.deleted_at) and
          is_nil(block.deleted_at) and
          block.type == "table" and
          sheet.id in ^sheet_ids,
      select: %{
        sheet_id: sheet.id,
        table_name: block.variable_name,
        row_slug: row.slug,
        cells: row.cells
      }
    )
  end

  defp match_table_row(rows, entry, acc, namespace_by_id) do
    case find_matching_row(rows, entry, namespace_by_id) do
      nil -> acc
      row -> Map.put(acc, entry.ref, resolve_cell_value(row.cells, entry.col_slug))
    end
  end

  defp find_matching_row(rows, entry, namespace_by_id) do
    Enum.find(rows, fn row ->
      Map.fetch!(namespace_by_id, row.sheet_id) == entry.shortcut and row.table_name == entry.table_name and
        row.row_slug == entry.row_slug
    end)
  end

  defp resolve_cell_value(cells, col_slug) do
    case cells[col_slug] do
      %{"expression" => expr, "bindings" => bindings} when is_binary(expr) and expr != "" ->
        compute_formula_cell(expr, bindings, cells)

      other ->
        other
    end
  end

  defp compute_formula_cell(expression, bindings, row_cells) do
    values =
      Map.new(bindings || %{}, fn {symbol, binding} ->
        value =
          case binding do
            %{"type" => "same_row", "column_slug" => slug} ->
              MapUtils.parse_to_number(row_cells[slug])

            %{"type" => "variable", "ref" => _ref} ->
              # Cross-table variable refs in nested formulas fall back to 0
              # (the outer formula resolver handles cross-table resolution)
              0.0

            _ ->
              0.0
          end

        {symbol, value}
      end)

    case FormulaEngine.compute(expression, values) do
      {:ok, result} -> MapUtils.format_number_result(result)
      {:error, _} -> nil
    end
  end

  defp extract_block_value(%{"content" => content}), do: content
  defp extract_block_value(_), do: nil

  # ===========================================================================
  # Formula-referenced blocks (mirror of the Sheet tool's stats)
  # ===========================================================================

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
    namespaces = reference_pairs |> Enum.map(&elem(&1, 0)) |> Enum.uniq()
    namespace_ids = VariableNamespaceResolver.resolve_sheet_ids(project_id, namespaces)
    namespace_by_id = Map.new(namespace_ids, fn {namespace, id} -> {id, namespace} end)
    sheet_ids = Map.keys(namespace_by_id)

    from(block in Block,
      join: sheet in Sheet,
      on: block.sheet_id == sheet.id,
      where:
        sheet.project_id == ^project_id and
          sheet.id in ^sheet_ids and
          is_nil(sheet.deleted_at) and is_nil(block.deleted_at),
      select: {sheet.id, block.variable_name, block.id}
    )
    |> Repo.all()
    |> Enum.reduce(MapSet.new(), fn {sheet_id, variable_name, block_id}, referenced_ids ->
      namespace = Map.fetch!(namespace_by_id, sheet_id)

      if MapSet.member?(reference_pairs, {namespace, variable_name}) do
        MapSet.put(referenced_ids, block_id)
      else
        referenced_ids
      end
    end)
  end

  # ===========================================================================
  # Stale and live entity-reference reads (mirror of the Sheet tool's tracker)
  # ===========================================================================

  defp list_stale_block_reference_source_ids(_project_id, []), do: MapSet.new()

  defp list_stale_block_reference_source_ids(project_id, block_ids) do
    project_id
    |> stale_block_reference_query(block_ids)
    |> Repo.all()
    |> MapSet.new()
  end

  defp stale_block_reference_query(project_id, block_ids) do
    EntityReference
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
      on: reference.source_type == "block" and reference.source_id == source_block.id,
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

  defp get_reference_targets(references, project_id) do
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

  defp reference_target_ids(references, target_type) do
    references
    |> Enum.flat_map(fn
      {^target_type, target_id} when is_integer(target_id) and target_id > 0 -> [target_id]
      _reference -> []
    end)
    |> Enum.uniq()
  end
end
