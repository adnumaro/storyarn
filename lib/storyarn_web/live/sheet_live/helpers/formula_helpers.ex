defmodule StoryarnWeb.SheetLive.Helpers.FormulaHelpers do
  @moduledoc """
  Shared formula helper functions used by both table cell rendering (TableBlocks)
  and the formula sidebar (ContentTab).
  """

  import Phoenix.Component, only: [assign: 3]

  alias Storyarn.Shared.FormulaEngine
  alias Storyarn.Sheets

  @doc "Extract symbol names from an expression string."
  def formula_symbols(expression) when is_binary(expression) do
    case FormulaEngine.parse(expression) do
      {:ok, ast} -> FormulaEngine.extract_symbols(ast)
      {:error, _} -> []
    end
  end

  def formula_symbols(_), do: []

  @doc "Extract expression string from a formula cell value map."
  def formula_cell_expression(%{"expression" => expr}) when is_binary(expr), do: expr
  def formula_cell_expression(_), do: ""

  @doc "Extract computed result from a formula cell value (injected by compute_formulas)."
  def formula_cell_result(%{"__result" => result}), do: result
  def formula_cell_result(_), do: nil

  @doc "Get binding value string for a symbol from a formula cell."
  def formula_cell_binding(%{"bindings" => bindings}, symbol) when is_map(bindings) do
    case Map.get(bindings, symbol) do
      %{"type" => "same_row", "column_slug" => slug} -> "same_row:" <> slug
      %{"type" => "variable", "ref" => ref} -> ref
      _ -> ""
    end
  end

  def formula_cell_binding(_, _), do: ""

  @doc "Generate LaTeX preview from a formula cell value."
  def formula_preview_from_cell(%{"expression" => expr}) when is_binary(expr) and expr != "" do
    case FormulaEngine.parse(expr) do
      {:ok, ast} -> FormulaEngine.to_latex(ast)
      {:error, _reason} -> nil
    end
  end

  def formula_preview_from_cell(_), do: nil

  @doc "Generate LaTeX result line: values substituted into expression = result."
  def formula_result_latex(%{"expression" => expr, "__result" => result} = cell)
      when is_binary(expr) and expr != "" and not is_nil(result) do
    resolved = Map.get(cell, "__resolved", %{})

    case FormulaEngine.parse(expr) do
      {:ok, ast} ->
        substituted = FormulaEngine.to_latex_substituted(ast, resolved)
        "#{substituted} = #{format_formula_value(result)}"

      {:error, _} ->
        nil
    end
  end

  def formula_result_latex(_), do: nil

  @doc "Format a numeric formula result for display."
  def format_formula_value(nil), do: nil

  def format_formula_value(value) when is_float(value) do
    if value == Float.floor(value),
      do: value |> trunc() |> to_string(),
      else: :erlang.float_to_binary(value, decimals: 2)
  end

  def format_formula_value(value) when is_integer(value), do: to_string(value)
  def format_formula_value(value), do: to_string(value)

  @doc "Parse a binding value string into the stored binding map format."
  def parse_binding_value(""), do: nil
  def parse_binding_value("same_row:" <> slug), do: %{"type" => "same_row", "column_slug" => slug}
  def parse_binding_value(ref) when is_binary(ref), do: %{"type" => "variable", "ref" => ref}

  @doc "Encode stored binding maps back to string format for event params."
  def encode_bindings(bindings) when is_map(bindings) do
    Map.new(bindings, fn {symbol, binding} ->
      value =
        case binding do
          %{"type" => "same_row", "column_slug" => slug} -> "same_row:" <> slug
          %{"type" => "variable", "ref" => ref} -> ref
          _ -> ""
        end

      {symbol, value}
    end)
  end

  def encode_bindings(_), do: %{}

  @doc "Build combobox options list from same-row columns + cross-sheet variables."
  def build_binding_options(same_row_cols, vars_by_sheet) do
    same_row =
      Enum.map(same_row_cols, fn col ->
        %{value: "same_row:" <> col.slug, label: col.name, group: "Same row"}
      end)

    cross_sheet =
      vars_by_sheet
      |> Enum.sort_by(fn {sheet, _} -> sheet end)
      |> Enum.flat_map(fn {sheet_shortcut, vars} ->
        Enum.map(vars, fn var ->
          full_ref = sheet_shortcut <> "." <> var.variable_name
          %{value: full_ref, label: var.variable_name, group: sheet_shortcut}
        end)
      end)

    same_row ++ cross_sheet
  end

  @doc "Get display text for a binding value (show column name for same-row, ref path for cross-sheet)."
  def formula_binding_display(cell_value, symbol, same_row_cols) do
    binding_value = formula_cell_binding(cell_value, symbol)

    case binding_value do
      "" ->
        ""

      "same_row:" <> slug ->
        col = Enum.find(same_row_cols, &(&1.slug == slug))
        if col, do: col.name, else: slug

      ref ->
        ref
    end
  end

  # ===========================================================================
  # Formula sidebar data helpers
  # ===========================================================================

  @formula_page_size 20

  def refresh_formula_editing(socket) do
    case socket.assigns.formula_editing do
      nil ->
        socket

      %{row_id: row_id, column_slug: slug, block_id: block_id} = fe ->
        table_entry = Map.get(socket.assigns.table_data, block_id, %{columns: [], rows: []})
        enriched_row = Enum.find(table_entry.rows, &(&1.id == row_id))
        row = enriched_row || Sheets.get_table_row!(row_id)
        assign(socket, :formula_editing, %{fe | value: row.cells[slug]})
    end
  end

  def build_formula_editing_for_vue(nil, _search_results, _has_more), do: nil

  def build_formula_editing_for_vue(fe, search_results, has_more) do
    cell_value = fe.value
    expr = formula_cell_expression(cell_value)
    symbols = formula_symbols(expr)

    same_row_options =
      (fe.columns || [])
      |> Enum.filter(fn c -> c.type in ["number", "formula"] and c.slug != fe.column_slug end)
      |> Enum.map(fn c -> %{value: "same_row:" <> c.slug, label: c.name} end)

    symbol_bindings = Map.new(symbols, fn s -> {s, formula_cell_binding(cell_value, s)} end)
    preview_latex = formula_preview_from_cell(cell_value)
    result_latex = formula_result_latex(cell_value)

    parse_error =
      if expr != "" do
        case FormulaEngine.parse(expr) do
          {:ok, _} -> nil
          {:error, reason} -> reason
        end
      end

    %{
      row_id: fe.row_id,
      column_slug: fe.column_slug,
      block_id: fe.block_id,
      table_name: fe.table_name,
      row_name: fe.row_name,
      column_name: fe.column_name,
      expression: expr,
      symbols: symbols,
      symbol_bindings: symbol_bindings,
      same_row_options: same_row_options,
      search_results: search_results,
      has_more: has_more || false,
      preview_latex: preview_latex,
      result_latex: result_latex,
      parse_error: parse_error,
      result: formula_cell_result(cell_value)
    }
  end

  def search_binding_variables(project_id, query, offset) do
    filtered =
      project_id
      |> Sheets.list_project_variables()
      |> Enum.filter(&numeric_formula_variable?/1)
      |> filter_binding_variables(query)

    total = length(filtered)
    page = filtered |> Enum.drop(offset) |> Enum.take(@formula_page_size)
    has_more = offset + @formula_page_size < total

    {group_binding_variables(page), has_more}
  end

  def merge_search_results(existing, new_page) do
    existing_map = Map.new(existing, fn g -> {g.heading, g.items} end)

    new_page
    |> Enum.reduce(existing_map, fn group, acc ->
      existing_items = Map.get(acc, group.heading, [])
      Map.put(acc, group.heading, existing_items ++ group.items)
    end)
    |> Enum.sort_by(fn {heading, _} -> heading end)
    |> Enum.map(fn {heading, items} -> %{heading: heading, items: items} end)
  end

  def formula_page_size, do: @formula_page_size

  @doc """
  Computes formula results for all table blocks and enriches row cells
  with `__result` and `__resolved` keys.
  """
  def compute_formulas(table_data, project_id) do
    Map.new(table_data, &compute_table_formulas(&1, project_id))
  end

  defp numeric_formula_variable?(variable) do
    variable.block_type in ["number", "formula"]
  end

  defp filter_binding_variables(vars, ""), do: vars

  defp filter_binding_variables(vars, query) do
    query = String.downcase(query)
    Enum.filter(vars, &binding_variable_matches?(&1, query))
  end

  defp binding_variable_matches?(variable, query) do
    Enum.any?(
      [
        variable.variable_name,
        variable.sheet_shortcut,
        variable.sheet_shortcut <> "." <> variable.variable_name
      ],
      &(&1 |> String.downcase() |> String.contains?(query))
    )
  end

  defp group_binding_variables(vars) do
    vars
    |> Enum.group_by(fn v -> v.sheet_shortcut end)
    |> Enum.sort_by(fn {sheet, _} -> sheet end)
    |> Enum.map(fn {sheet_shortcut, vars} ->
      %{heading: sheet_shortcut, items: Enum.map(vars, &binding_variable_item(sheet_shortcut, &1))}
    end)
  end

  defp binding_variable_item(sheet_shortcut, variable) do
    %{value: sheet_shortcut <> "." <> variable.variable_name, label: variable.variable_name}
  end

  defp compute_table_formulas({block_id, %{columns: columns} = data}, project_id) do
    formula_columns = Enum.filter(columns, &(&1.type == "formula"))
    {block_id, compute_table_formula_data(data, formula_columns, project_id)}
  end

  defp compute_table_formula_data(data, [], _project_id), do: data

  defp compute_table_formula_data(%{columns: columns, rows: rows} = data, _formula_columns, project_id) do
    computed = compute_formula_results(columns, rows, project_id)
    %{data | rows: Enum.map(rows, &enrich_formula_row(&1, computed))}
  end

  defp compute_formula_results(columns, rows, project_id) do
    Storyarn.Sheets.FormulaResolver.compute_all(columns, rows, project_id)
  rescue
    _ -> %{}
  end

  defp enrich_formula_row(row, computed) do
    formula_results = Map.get(computed, row.id, %{})
    %{row | cells: enrich_formula_cells(row.cells, formula_results)}
  end

  defp enrich_formula_cells(cells, formula_results) do
    Enum.reduce(formula_results, cells, fn {slug, computed_entry}, cells ->
      Map.put(cells, slug, enrich_formula_cell(cells[slug], computed_entry))
    end)
  end

  defp enrich_formula_cell(current, %{result: result} = computed_entry) when is_map(current) do
    resolved = Map.get(computed_entry, :resolved, %{})

    current
    |> Map.put("__result", result)
    |> Map.put("__resolved", resolved)
  end

  defp enrich_formula_cell(_current, %{result: result} = computed_entry) do
    %{"__result" => result, "__resolved" => Map.get(computed_entry, :resolved, %{})}
  end
end
