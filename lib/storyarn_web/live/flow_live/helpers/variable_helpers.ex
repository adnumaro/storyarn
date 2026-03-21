defmodule StoryarnWeb.FlowLive.Helpers.VariableHelpers do
  @moduledoc false

  alias Storyarn.Scenes
  alias Storyarn.Shared.FormulaRuntime
  alias Storyarn.Sheets

  @doc """
  Returns the flat list of all variable descriptors (sheets + pins + zones).
  Used by LiveViews that pass variables to condition/instruction builders.
  """
  def list_all_variables(project_id) do
    Sheets.list_project_variables(project_id) ++
      Scenes.list_pin_variables(project_id) ++
      Scenes.list_zone_variables(project_id)
  end

  def build_variables(project_id) do
    variables =
      list_all_variables(project_id)
      |> Enum.reduce(%{}, fn var, acc ->
        key = "#{var.sheet_shortcut}.#{var.variable_name}"
        {initial, formula_meta} = extract_initial_and_formula(var, key)

        entry = %{
          value: initial,
          initial_value: initial,
          previous_value: initial,
          source: :initial,
          block_type: var.block_type,
          block_id: var.block_id,
          sheet_shortcut: var.sheet_shortcut,
          variable_name: var.variable_name,
          constraints: var[:constraints],
          source_type: var[:source_type] || "sheet",
          source_id: var[:source_id]
        }

        entry = if formula_meta, do: Map.put(entry, :formula, formula_meta), else: entry
        Map.put(acc, key, entry)
      end)

    # Recompute all formula values with proper dependency ordering
    FormulaRuntime.recompute_formulas(variables)
  end

  # For formula-type variables, extract expression + bindings and translate same_row refs
  defp extract_initial_and_formula(%{block_type: "formula", cell_value: cell_value} = _var, key)
       when is_map(cell_value) do
    expression = cell_value["expression"]
    raw_bindings = cell_value["bindings"] || %{}

    if is_binary(expression) and expression != "" do
      translated = FormulaRuntime.translate_same_row(key, raw_bindings)
      formula = %{expression: expression, bindings: translated}
      {nil, formula}
    else
      {nil, nil}
    end
  end

  defp extract_initial_and_formula(var, _key) do
    {extract_initial_value(var), nil}
  end

  # Extract the user-defined value from the block/cell, falling back to type default
  defp extract_initial_value(%{cell_value: cell_value} = var) when not is_nil(cell_value) do
    coerce_value(cell_value, var.block_type)
  end

  defp extract_initial_value(%{value: %{"content" => content}} = var)
       when not is_nil(content) do
    coerce_value(content, var.block_type)
  end

  defp extract_initial_value(var), do: type_default(var.block_type)

  defp coerce_value(val, "number") when is_binary(val) do
    case Float.parse(val) do
      {f, ""} -> if f == trunc(f), do: trunc(f), else: f
      _ -> type_default("number")
    end
  end

  defp coerce_value(val, _type), do: val

  defp type_default("number"), do: 0
  defp type_default("boolean"), do: false
  defp type_default("text"), do: ""
  defp type_default("rich_text"), do: ""
  defp type_default("date"), do: nil
  defp type_default(_), do: nil
end
