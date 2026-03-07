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

  alias Storyarn.Shared.{FormulaEngine, MapUtils}
  alias Storyarn.Sheets

  @doc """
  Compute formula results for ALL formula columns in a table, for ALL rows.

  Each formula cell stores its own expression+bindings in `row.cells[col.slug]`.
  Returns `%{row_id => %{column_slug => result}}` where result is `number | nil`.
  Returns an empty map if there are no formula columns.
  """
  @spec compute_all(list(), list(), binary()) :: map()
  def compute_all(columns, rows, project_id) do
    formula_cols = Enum.filter(columns, &(&1.type == "formula"))

    if formula_cols == [] do
      %{}
    else
      cross_values = resolve_cross_values(formula_cols, rows, project_id)
      compute_all_rows(formula_cols, rows, columns, cross_values)
    end
  end

  defp resolve_cross_values(formula_cols, rows, project_id) do
    formula_slugs = MapSet.new(formula_cols, & &1.slug)
    cross_refs = collect_cross_sheet_refs(formula_slugs, rows)

    if cross_refs == [], do: %{}, else: Sheets.resolve_variable_values(project_id, cross_refs)
  end

  defp compute_all_rows(formula_cols, rows, columns, cross_values) do
    Map.new(rows, fn row ->
      results = Map.new(formula_cols, fn col ->
        {col.slug, compute_single(row.cells[col.slug], row.cells, columns, cross_values)}
      end)

      {row.id, results}
    end)
  end

  # ---------------------------------------------------------------------------
  # Private
  # ---------------------------------------------------------------------------

  defp compute_single(cell_value, row_cells, columns, cross_values) do
    expression = if is_map(cell_value), do: cell_value["expression"], else: nil
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

  defp resolve_bindings(bindings, row_cells, _columns, cross_values) do
    Map.new(bindings, fn {symbol, binding} ->
      value =
        case binding do
          %{"type" => "same_row", "column_slug" => slug} ->
            MapUtils.parse_to_number(row_cells[slug])

          %{"type" => "variable", "ref" => ref} ->
            MapUtils.parse_to_number(Map.get(cross_values, ref))

          _ ->
            0.0
        end

      {symbol, value}
    end)
  end

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
    (cell_value["bindings"] || %{})
    |> Map.values()
    |> Enum.filter(&(is_map(&1) and &1["type"] == "variable"))
    |> Enum.map(& &1["ref"])
  end

  defp extract_variable_refs(_), do: []

end
