defmodule Storyarn.Shared.FormulaRuntime do
  @moduledoc """
  Reactive formula recomputation for runtime variable maps.

  Given a variables map where some entries carry a `:formula` key
  (containing `expression` and `bindings`), recomputes all formula
  values in dependency order using topological sort.

  Called after every variable mutation (instructions, user overrides)
  to cascade changes through dependent formulas.
  """

  alias Storyarn.Shared.{FormulaEngine, MapUtils}

  @doc """
  Recompute all formula variables in dependency order.

  Formulas are identified by having a `:formula` key in their variable entry:

      %{
        formula: %{expression: "a - 3", bindings: %{"a" => "sheet.table.row.col"}},
        value: ...,
        ...
      }

  Returns the variables map with all formula values updated.
  """
  @spec recompute_formulas(map()) :: map()
  def recompute_formulas(variables) when map_size(variables) == 0, do: variables

  def recompute_formulas(variables) do
    formula_entries =
      variables
      |> Enum.filter(fn {_key, var} -> is_map(var[:formula]) end)
      |> Map.new()

    if map_size(formula_entries) == 0 do
      variables
    else
      do_recompute(variables, formula_entries)
    end
  end

  @doc """
  Translate same_row bindings to full variable references.

  Given a formula reference like `"seven.stats.con.modifier"` and raw bindings
  like `%{"a" => %{"type" => "same_row", "column_slug" => "value"}}`,
  returns `%{"a" => "seven.stats.con.value"}` by replacing the column slug
  in the reference path.
  """
  @spec translate_same_row(String.t(), map()) :: map()
  def translate_same_row(formula_ref, raw_bindings) when is_map(raw_bindings) do
    # formula_ref is like "sheet.table.row.column" — extract the row prefix
    parts = String.split(formula_ref, ".")

    row_prefix =
      case parts do
        [sheet, table, row | _] -> "#{sheet}.#{table}.#{row}"
        _ -> nil
      end

    Map.new(raw_bindings, fn {symbol, binding} ->
      ref = translate_binding(binding, row_prefix)
      {symbol, ref}
    end)
  end

  def translate_same_row(_formula_ref, _raw_bindings), do: %{}

  # ---------------------------------------------------------------------------
  # Private
  # ---------------------------------------------------------------------------

  defp translate_binding(%{"type" => "same_row", "column_slug" => col_slug}, row_prefix)
       when is_binary(row_prefix) do
    "#{row_prefix}.#{col_slug}"
  end

  defp translate_binding(%{"type" => "variable", "ref" => ref}, _row_prefix) do
    ref
  end

  defp translate_binding(_binding, _row_prefix), do: nil

  defp do_recompute(variables, formula_entries) do
    # Build dependency graph: formula_key => [dependency_keys]
    graph = build_dependency_graph(formula_entries)

    # Topological sort using Kahn's algorithm
    order = topological_sort(graph, Map.keys(formula_entries))

    # Evaluate each formula in topological order
    Enum.reduce(order, variables, fn key, vars ->
      case Map.get(formula_entries, key) do
        nil ->
          vars

        entry ->
          formula = entry.formula
          result = evaluate_formula(formula, vars)

          var = Map.get(vars, key)
          Map.put(vars, key, %{var | value: result})
      end
    end)
  end

  defp build_dependency_graph(formula_entries) do
    Map.new(formula_entries, fn {key, entry} ->
      bindings = entry.formula[:bindings] || %{}
      deps = bindings |> Map.values() |> Enum.reject(&is_nil/1)
      {key, deps}
    end)
  end

  defp topological_sort(graph, all_keys) do
    # Kahn's algorithm
    # in_degree: how many formula dependencies each key has
    in_degree =
      Map.new(all_keys, fn key ->
        deps = Map.get(graph, key, [])
        # Only count deps that are themselves formulas (in the graph)
        formula_deps = Enum.count(deps, &Map.has_key?(graph, &1))
        {key, formula_deps}
      end)

    # Start with nodes that have no formula dependencies
    queue = for {key, 0} <- in_degree, do: key
    do_kahn(queue, graph, in_degree, all_keys, [])
  end

  defp do_kahn([], _graph, _in_degree, all_keys, sorted) do
    sorted_set = MapSet.new(sorted)

    # Any remaining keys are in cycles — append them at the end (they'll get nil)
    remaining = Enum.filter(all_keys, &(not MapSet.member?(sorted_set, &1)))
    sorted ++ remaining
  end

  defp do_kahn([key | rest], graph, in_degree, all_keys, sorted) do
    # Find all formulas that depend on this key
    dependents =
      Enum.filter(all_keys, fn other_key ->
        other_key != key and key in Map.get(graph, other_key, [])
      end)

    # Decrease in_degree for each dependent
    {new_queue_additions, new_in_degree} =
      Enum.reduce(dependents, {[], in_degree}, fn dep, {q_acc, deg_acc} ->
        new_deg = Map.get(deg_acc, dep, 0) - 1
        deg_acc = Map.put(deg_acc, dep, new_deg)

        if new_deg == 0 do
          {[dep | q_acc], deg_acc}
        else
          {q_acc, deg_acc}
        end
      end)

    do_kahn(rest ++ new_queue_additions, graph, new_in_degree, all_keys, sorted ++ [key])
  end

  defp evaluate_formula(%{expression: expression, bindings: bindings}, variables)
       when is_binary(expression) and expression != "" do
    # Resolve binding symbols to current numeric values
    values =
      Map.new(bindings, fn {symbol, ref} ->
        numeric = resolve_to_number(variables, ref)
        {symbol, numeric}
      end)

    case FormulaEngine.compute(expression, values) do
      {:ok, result} -> MapUtils.format_number_result(result)
      {:error, _} -> nil
    end
  end

  defp evaluate_formula(_formula, _variables), do: nil

  defp resolve_to_number(variables, ref) when is_binary(ref) do
    case Map.get(variables, ref) do
      %{value: val} -> MapUtils.parse_to_number(val)
      _ -> 0.0
    end
  end

  defp resolve_to_number(_variables, _ref), do: 0.0
end
