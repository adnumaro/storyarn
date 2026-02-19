defmodule StoryarnWeb.FlowLive.Helpers.VariableHelpers do
  @moduledoc false

  alias Storyarn.Sheets

  def build_variables(project_id) do
    Sheets.list_project_variables(project_id)
    |> Enum.reduce(%{}, fn var, acc ->
      key = "#{var.sheet_shortcut}.#{var.variable_name}"

      Map.put(acc, key, %{
        value: default_value(var.block_type),
        initial_value: default_value(var.block_type),
        previous_value: default_value(var.block_type),
        source: :initial,
        block_type: var.block_type,
        block_id: var.block_id,
        sheet_shortcut: var.sheet_shortcut,
        variable_name: var.variable_name
      })
    end)
  end

  defp default_value("number"), do: 0
  defp default_value("boolean"), do: false
  defp default_value("text"), do: ""
  defp default_value("rich_text"), do: ""
  defp default_value(_), do: nil
end
