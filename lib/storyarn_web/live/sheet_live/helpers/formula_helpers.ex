defmodule StoryarnWeb.SheetLive.Helpers.FormulaHelpers do
  @moduledoc """
  Shared formula helper functions used by both table cell rendering (TableBlocks)
  and the formula sidebar (ContentTab).
  """

  alias Storyarn.Shared.FormulaEngine

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
      {:error, reason} -> "Error: #{reason}"
    end
  end

  def formula_preview_from_cell(_), do: "\u2014"

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
end
