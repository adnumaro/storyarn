defmodule Storyarn.Sheets.FormulaResolver do
  @moduledoc """
  Resolves formula bindings to numeric values and computes formula results for table cells.

  Each formula cell stores its own expression and bindings as a map:
  `%{"expression" => "a - 3", "bindings" => %{"a" => %{"type" => "same_row", "column_slug" => "value"}}}`.

  Handles two types of bindings:
  - `same_row` — references another column in the same table row
  - `variable` — references a variable from any sheet in the project (cross-sheet)

  Called during table data loading to inject computed values into formula cells.
  """

  alias Storyarn.Shared.MapUtils
  alias Storyarn.Sheets
  alias Storyarn.Sheets.FormulaEngine

  @doc """
  Injects `__result` and `__resolved` into every formula cell of a batch of table
  data, as returned by `Sheets.batch_load_table_data/1`.

  `__resolved` is what the health checker evaluates formulas against, so a caller
  that skips this enrichment silently loses `formula_evaluation_failed` — and, on
  rows whose formula cell was never written, reports a phantom
  `invalid_table_structure` the editor does not. Both the editor and the
  project-wide health sweep therefore go through here.

  Cross-sheet variable references are resolved once for the whole batch, so the
  cost is the same for one table as for a project's worth of them.
  """
  @spec enrich_table_data(map(), integer()) :: map()
  def enrich_table_data(table_data, project_id) do
    cross_values = resolve_batch_cross_values(table_data, project_id)

    Map.new(table_data, fn {block_id, data} -> {block_id, enrich_table(data, cross_values)} end)
  end

  defp resolve_batch_cross_values(table_data, project_id) do
    cross_refs =
      table_data
      |> Enum.flat_map(fn {_block_id, %{columns: columns, rows: rows}} ->
        columns
        |> Enum.filter(&(&1.type == "formula"))
        |> MapSet.new(& &1.slug)
        |> collect_cross_sheet_refs(rows)
      end)
      |> Enum.uniq()

    if cross_refs == [], do: %{}, else: Sheets.resolve_variable_values(project_id, cross_refs)
  end

  defp enrich_table(%{columns: columns, rows: rows} = data, cross_values) do
    formula_cols = Enum.filter(columns, &(&1.type == "formula"))

    if formula_cols == [] do
      data
    else
      computed = compute_all_rows(formula_cols, rows, columns, cross_values)
      %{data | rows: Enum.map(rows, &enrich_row(&1, Map.get(computed, &1.id, %{})))}
    end
  end

  defp enrich_row(row, results) do
    cells =
      Enum.reduce(results, row.cells, fn {slug, computed}, cells ->
        Map.put(cells, slug, enrich_cell(Map.get(cells, slug), computed))
      end)

    %{row | cells: cells}
  end

  defp enrich_cell(current, %{result: result, resolved: resolved}) when is_map(current) do
    current |> Map.put("__result", result) |> Map.put("__resolved", resolved)
  end

  defp enrich_cell(_current, %{result: result, resolved: resolved}) do
    %{"__result" => result, "__resolved" => resolved}
  end

  defp compute_all_rows(formula_cols, rows, columns, cross_values) do
    Map.new(rows, fn row ->
      results =
        Map.new(formula_cols, fn col ->
          {col.slug, compute_single(row.cells[col.slug], row.cells, columns, cross_values)}
        end)

      {row.id, results}
    end)
  end

  # ---------------------------------------------------------------------------
  # Private
  # ---------------------------------------------------------------------------

  defp compute_single(cell_value, row_cells, columns, cross_values) do
    expression = if is_map(cell_value), do: cell_value["expression"]
    bindings = if is_map(cell_value), do: cell_value["bindings"] || %{}, else: %{}

    if is_nil(expression) or expression == "" do
      %{result: nil, resolved: %{}}
    else
      values = resolve_bindings(bindings, row_cells, columns, cross_values)

      case FormulaEngine.compute(expression, values) do
        {:ok, result} -> %{result: MapUtils.format_number_result(result), resolved: values}
        {:error, _} -> %{result: nil, resolved: values}
      end
    end
  end

  defp resolve_bindings(bindings, row_cells, _columns, cross_values) when is_map(bindings) do
    Enum.reduce(bindings, %{}, fn
      {symbol, %{"type" => "same_row", "column_slug" => slug}}, values
      when is_binary(symbol) and is_binary(slug) and slug != "" ->
        Map.put(values, symbol, MapUtils.parse_to_number(row_cells[slug]))

      {symbol, %{"type" => "variable", "ref" => ref}}, values
      when is_binary(symbol) and is_binary(ref) and ref != "" ->
        Map.put(values, symbol, MapUtils.parse_to_number(Map.get(cross_values, ref)))

      _invalid_binding, values ->
        values
    end)
  end

  defp resolve_bindings(_bindings, _row_cells, _columns, _cross_values), do: %{}

  defp collect_cross_sheet_refs(formula_slugs, rows) do
    rows
    |> Enum.flat_map(fn row ->
      row.cells
      |> Enum.filter(fn {slug, _} -> MapSet.member?(formula_slugs, slug) end)
      |> Enum.flat_map(fn {_slug, cell} -> extract_variable_refs(cell) end)
    end)
    |> Enum.uniq()
  end

  defp extract_variable_refs(cell_value) when is_map(cell_value) do
    case cell_value["bindings"] do
      bindings when is_map(bindings) ->
        Enum.flat_map(bindings, fn
          {_symbol, %{"type" => "variable", "ref" => ref}} when is_binary(ref) and ref != "" -> [ref]
          _invalid_binding -> []
        end)

      _invalid_bindings ->
        []
    end
  end

  defp extract_variable_refs(_), do: []
end
