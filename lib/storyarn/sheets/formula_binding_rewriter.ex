defmodule Storyarn.Sheets.FormulaBindingRewriter do
  @moduledoc """
  Rewrites cross-sheet formula bindings when table rows are copied from a parent
  sheet to a child sheet during property inheritance.

  A formula cell stores bindings like:
    %{"b" => %{"type" => "variable", "ref" => "main.stats.con.modifier"}}

  When the parent sheet "main" propagates to child "seven", and the "stats" block
  was also propagated, the binding becomes:
    %{"b" => %{"type" => "variable", "ref" => "seven.stats.con.modifier"}}

  Only rewrites bindings whose ref starts with the parent shortcut AND whose
  referenced block was actually propagated to the child (exists in var_name_mapping).
  """

  import Ecto.Query, warn: false
  alias Storyarn.Repo
  alias Storyarn.Sheets.Block

  @doc """
  Rewrites cross-sheet variable bindings in a row's cells map.

  Pure function — no DB access. Returns cells unchanged if shortcuts are nil,
  empty, or equal.

  ## Parameters
    - `cells` — row cells map, e.g. `%{"base" => 10, "value" => %{"expression" => ..., "bindings" => ...}}`
    - `parent_shortcut` — source sheet shortcut (e.g. `"main"`)
    - `child_shortcut` — target sheet shortcut (e.g. `"seven"`)
    - `var_name_mapping` — `%{"stats" => "stats", "combat" => "combat_1"}` parent var_name → child var_name
  """
  @spec rewrite_cells(map(), String.t() | nil, String.t() | nil, map()) :: map()
  def rewrite_cells(cells, parent_shortcut, child_shortcut, var_name_mapping)

  def rewrite_cells(cells, nil, _child, _mapping), do: cells
  def rewrite_cells(cells, _parent, nil, _mapping), do: cells
  def rewrite_cells(cells, "", _child, _mapping), do: cells
  def rewrite_cells(cells, _parent, "", _mapping), do: cells
  def rewrite_cells(cells, same, same, _mapping), do: cells
  def rewrite_cells(cells, _parent, _child, mapping) when map_size(mapping) == 0, do: cells

  def rewrite_cells(cells, parent_shortcut, child_shortcut, var_name_mapping) do
    prefix = parent_shortcut <> "."

    Map.new(cells, fn {slug, cell_value} ->
      {slug, rewrite_cell(cell_value, prefix, child_shortcut, var_name_mapping)}
    end)
  end

  defp rewrite_cell(cell_value, prefix, child_shortcut, mapping) when is_map(cell_value) do
    case {cell_value["expression"], cell_value["bindings"]} do
      {expr, bindings} when is_binary(expr) and is_map(bindings) ->
        new_bindings = rewrite_bindings(bindings, prefix, child_shortcut, mapping)
        Map.put(cell_value, "bindings", new_bindings)

      _ ->
        cell_value
    end
  end

  defp rewrite_cell(cell_value, _prefix, _child_shortcut, _mapping), do: cell_value

  defp rewrite_bindings(bindings, prefix, child_shortcut, mapping) do
    Map.new(bindings, fn {symbol, binding} ->
      {symbol, rewrite_binding(binding, prefix, child_shortcut, mapping)}
    end)
  end

  defp rewrite_binding(
         %{"type" => "variable", "ref" => ref} = binding,
         prefix,
         child_shortcut,
         mapping
       ) do
    if String.starts_with?(ref, prefix) do
      ref
      |> String.slice(String.length(prefix)..-1//1)
      |> rewrite_variable_ref(binding, child_shortcut, mapping)
    else
      binding
    end
  end

  defp rewrite_binding(binding, _prefix, _child_shortcut, _mapping), do: binding

  defp rewrite_variable_ref(rest, binding, child_shortcut, mapping) do
    case String.split(rest, ".", parts: 2) do
      [block_var_name | rest_parts] ->
        case Map.get(mapping, block_var_name) do
          nil ->
            binding

          child_var_name ->
            build_rewritten_binding(binding, child_shortcut, child_var_name, rest_parts)
        end

      _ ->
        binding
    end
  end

  defp build_rewritten_binding(binding, child_shortcut, child_var_name, []) do
    Map.put(binding, "ref", child_shortcut <> "." <> child_var_name)
  end

  defp build_rewritten_binding(binding, child_shortcut, child_var_name, [rest_path]) do
    Map.put(binding, "ref", child_shortcut <> "." <> child_var_name <> "." <> rest_path)
  end

  @doc """
  Builds a mapping of parent block variable_name → child block variable_name
  for all inherited blocks between a parent and child sheet.

  Covers the full ancestor chain — a child block's `inherited_from_block_id` may
  point to a grandparent block.
  """
  @spec build_var_name_mapping(integer(), integer()) :: map()
  def build_var_name_mapping(parent_sheet_id, child_sheet_id) do
    from(child_b in Block,
      join: parent_b in Block,
      on: child_b.inherited_from_block_id == parent_b.id,
      where:
        child_b.sheet_id == ^child_sheet_id and
          parent_b.sheet_id == ^parent_sheet_id and
          is_nil(child_b.deleted_at) and
          not is_nil(parent_b.variable_name),
      select: {parent_b.variable_name, child_b.variable_name}
    )
    |> Repo.all()
    |> Map.new()
  end

  @doc """
  Checks whether any cell in a cells map contains a formula binding of type "variable".
  Used as an early-exit guard to avoid unnecessary DB queries.
  """
  @spec has_formula_variable_bindings?(map() | nil) :: boolean()
  def has_formula_variable_bindings?(nil), do: false

  def has_formula_variable_bindings?(cells) when is_map(cells) do
    Enum.any?(cells, fn {_slug, cell_value} ->
      is_map(cell_value) and
        is_binary(cell_value["expression"]) and
        is_map(cell_value["bindings"]) and
        Enum.any?(cell_value["bindings"], fn {_sym, b} ->
          is_map(b) and b["type"] == "variable"
        end)
    end)
  end

  @doc """
  Checks whether any row in a list has formula variable bindings.
  """
  @spec any_rows_have_formula_bindings?(list()) :: boolean()
  def any_rows_have_formula_bindings?(rows) do
    Enum.any?(rows, fn row -> has_formula_variable_bindings?(row.cells) end)
  end
end
