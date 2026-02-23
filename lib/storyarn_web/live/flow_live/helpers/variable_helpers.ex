defmodule StoryarnWeb.FlowLive.Helpers.VariableHelpers do
  @moduledoc false

  alias Storyarn.Sheets

  def build_variables(project_id) do
    Sheets.list_project_variables(project_id)
    |> Enum.reduce(%{}, fn var, acc ->
      key = "#{var.sheet_shortcut}.#{var.variable_name}"
      initial = extract_initial_value(var)

      Map.put(acc, key, %{
        value: initial,
        initial_value: initial,
        previous_value: initial,
        source: :initial,
        block_type: var.block_type,
        block_id: var.block_id,
        sheet_shortcut: var.sheet_shortcut,
        variable_name: var.variable_name,
        constraints: var[:constraints]
      })
    end)
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
