defmodule Storyarn.Flows.FormulaRuntime do
  @moduledoc """
  Recomputes the formula variables used by the Flow player.

  This implementation belongs to Flows even though it currently shares the
  SQL representation of Sheet-defined variables. Changes to Sheet formula
  behavior must therefore be adopted explicitly instead of changing Flow
  runtime semantics through a shared business module.
  """

  alias Storyarn.Flows.FormulaEngine
  alias Storyarn.Platform.Shared.MapUtils

  @spec recompute_formulas(map()) :: map()
  def recompute_formulas(variables) when map_size(variables) == 0, do: variables

  def recompute_formulas(variables) do
    formula_entries =
      variables
      |> Enum.filter(fn {_key, variable} -> is_map(variable[:formula]) end)
      |> Map.new()

    if map_size(formula_entries) == 0 do
      variables
    else
      recompute(variables, formula_entries)
    end
  end

  @doc "Translates a Sheet same-row binding into the variable key consumed by Flows."
  @spec translate_same_row(String.t(), map()) :: map()
  def translate_same_row(formula_ref, raw_bindings) when is_map(raw_bindings) do
    row_prefix =
      case String.split(formula_ref, ".") do
        [sheet, table, row | _rest] -> "#{sheet}.#{table}.#{row}"
        _parts -> nil
      end

    Map.new(raw_bindings, fn {symbol, binding} ->
      {symbol, translate_binding(binding, row_prefix)}
    end)
  end

  def translate_same_row(_formula_ref, _raw_bindings), do: %{}

  defp translate_binding(%{"type" => "same_row", "column_slug" => column_slug}, row_prefix) when is_binary(row_prefix) do
    "#{row_prefix}.#{column_slug}"
  end

  defp translate_binding(%{"type" => "variable", "ref" => reference}, _row_prefix), do: reference

  defp translate_binding(_binding, _row_prefix), do: nil

  defp recompute(variables, formula_entries) do
    graph = dependency_graph(formula_entries)
    order = topological_order(graph, Map.keys(formula_entries))

    Enum.reduce(order, variables, fn key, current_variables ->
      case Map.get(formula_entries, key) do
        nil ->
          current_variables

        entry ->
          result = evaluate(entry.formula, current_variables)
          variable = Map.fetch!(current_variables, key)
          Map.put(current_variables, key, %{variable | value: result})
      end
    end)
  end

  defp dependency_graph(formula_entries) do
    Map.new(formula_entries, fn {key, entry} ->
      dependencies =
        entry.formula
        |> Map.get(:bindings, %{})
        |> Map.values()
        |> Enum.reject(&is_nil/1)

      {key, dependencies}
    end)
  end

  defp topological_order(graph, all_keys) do
    in_degree =
      Map.new(all_keys, fn key ->
        formula_dependencies =
          graph
          |> Map.get(key, [])
          |> Enum.count(&Map.has_key?(graph, &1))

        {key, formula_dependencies}
      end)

    queue = for {key, 0} <- in_degree, do: key
    sort_topologically(queue, graph, in_degree, all_keys, [])
  end

  defp sort_topologically([], _graph, _in_degree, all_keys, sorted) do
    sorted_set = MapSet.new(sorted)
    remaining = Enum.reject(all_keys, &MapSet.member?(sorted_set, &1))
    sorted ++ remaining
  end

  defp sort_topologically([key | rest], graph, in_degree, all_keys, sorted) do
    dependents =
      Enum.filter(all_keys, fn other_key ->
        other_key != key and key in Map.get(graph, other_key, [])
      end)

    {new_queue_entries, new_in_degree} =
      Enum.reduce(dependents, {[], in_degree}, fn dependent, {queue_entries, degrees} ->
        new_degree = Map.get(degrees, dependent, 0) - 1
        degrees = Map.put(degrees, dependent, new_degree)

        if new_degree == 0 do
          {[dependent | queue_entries], degrees}
        else
          {queue_entries, degrees}
        end
      end)

    sort_topologically(rest ++ new_queue_entries, graph, new_in_degree, all_keys, sorted ++ [key])
  end

  defp evaluate(%{expression: expression, bindings: bindings}, variables)
       when is_binary(expression) and expression != "" do
    values =
      Map.new(bindings, fn {symbol, reference} ->
        {symbol, resolve_number(variables, reference)}
      end)

    case FormulaEngine.compute(expression, values) do
      {:ok, result} -> MapUtils.format_number_result(result)
      {:error, _reason} -> nil
    end
  end

  defp evaluate(_formula, _variables), do: nil

  defp resolve_number(variables, reference) when is_binary(reference) do
    case Map.get(variables, reference) do
      %{value: value} -> MapUtils.parse_to_number(value)
      _missing -> 0.0
    end
  end

  defp resolve_number(_variables, _reference), do: 0.0
end
