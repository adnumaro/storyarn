defmodule Storyarn.Flows.RuntimeVariables do
  @moduledoc """
  Builds the variable state consumed by Flow execution.

  The source descriptors are a Flow-owned read model over the shared tables.
  This module owns Flow defaults, coercion and formula initialization so a
  presentation adapter cannot accidentally redefine runtime behavior.
  """

  alias Storyarn.Flows.FormulaRuntime
  alias Storyarn.Flows.VariableCatalog

  @type descriptor :: map()
  @type variable_key :: String.t()
  @type variables :: %{optional(variable_key()) => map()}

  @doc "Builds the initial Flow runtime variables for a project."
  @spec build(pos_integer()) :: variables()
  def build(project_id) when is_integer(project_id) do
    project_id
    |> VariableCatalog.list_referenceable()
    |> from_descriptors()
  end

  @doc "Builds runtime state from already-loaded Flow variable descriptors."
  @spec from_descriptors([descriptor()]) :: variables()
  def from_descriptors(descriptors) when is_list(descriptors) do
    descriptors
    |> Enum.reduce(%{}, fn descriptor, variables ->
      key = "#{descriptor.sheet_shortcut}.#{descriptor.variable_name}"
      {initial_value, formula} = initial_value_and_formula(descriptor, key)

      variable = %{
        value: initial_value,
        initial_value: initial_value,
        previous_value: initial_value,
        source: :initial,
        block_type: descriptor.block_type,
        block_id: descriptor.block_id,
        sheet_shortcut: descriptor.sheet_shortcut,
        variable_name: descriptor.variable_name,
        constraints: descriptor[:constraints],
        options: descriptor[:options],
        source_type: descriptor[:source_type] || "sheet",
        source_id: descriptor[:source_id]
      }

      variable = if formula, do: Map.put(variable, :formula, formula), else: variable
      Map.put(variables, key, variable)
    end)
    |> FormulaRuntime.recompute_formulas()
  end

  @doc "Coerces a user-provided debugger override according to Flow runtime rules."
  @spec coerce_override(term(), String.t() | nil) ::
          {:ok, term()} | {:warning, term(), :invalid_number}
  def coerce_override(raw_value, "number") when is_binary(raw_value) do
    case Float.parse(raw_value) do
      {number, _remainder} -> {:ok, number}
      :error when raw_value == "" -> {:ok, 0}
      :error -> {:warning, 0, :invalid_number}
    end
  end

  def coerce_override(raw_value, "number") when is_number(raw_value), do: {:ok, raw_value}

  def coerce_override("true", "boolean"), do: {:ok, true}
  def coerce_override("false", "boolean"), do: {:ok, false}
  def coerce_override("nil", "boolean"), do: {:ok, nil}
  def coerce_override(nil, "boolean"), do: {:ok, nil}
  def coerce_override(true, "boolean"), do: {:ok, true}
  def coerce_override(false, "boolean"), do: {:ok, false}
  def coerce_override(_raw_value, "boolean"), do: {:ok, false}

  def coerce_override(values, "multi_select") when is_list(values), do: {:ok, values}
  def coerce_override("", "multi_select"), do: {:ok, []}

  def coerce_override(raw_value, "multi_select") when is_binary(raw_value) do
    values =
      raw_value
      |> String.split(",")
      |> Enum.map(&String.trim/1)
      |> Enum.reject(&(&1 == ""))

    {:ok, values}
  end

  def coerce_override(raw_value, _block_type), do: {:ok, raw_value}

  defp initial_value_and_formula(%{block_type: "formula", cell_value: cell_value}, key) when is_map(cell_value) do
    expression = cell_value["expression"]
    raw_bindings = cell_value["bindings"] || %{}

    if is_binary(expression) and expression != "" do
      formula = %{
        expression: expression,
        bindings: FormulaRuntime.translate_same_row(key, raw_bindings)
      }

      {nil, formula}
    else
      {nil, nil}
    end
  end

  defp initial_value_and_formula(descriptor, _key) do
    {initial_value(descriptor), nil}
  end

  defp initial_value(%{cell_value: cell_value} = descriptor) when not is_nil(cell_value) do
    coerce_initial(cell_value, descriptor.block_type)
  end

  defp initial_value(%{value: %{"content" => content}} = descriptor) when not is_nil(content) do
    coerce_initial(content, descriptor.block_type)
  end

  defp initial_value(descriptor), do: type_default(descriptor.block_type)

  defp coerce_initial(value, "number") when is_binary(value) do
    case Float.parse(value) do
      {number, ""} -> if number == trunc(number), do: trunc(number), else: number
      _invalid -> type_default("number")
    end
  end

  defp coerce_initial(value, _block_type), do: value

  defp type_default("number"), do: 0
  defp type_default("boolean"), do: false
  defp type_default("text"), do: ""
  defp type_default("rich_text"), do: ""
  defp type_default("date"), do: nil
  defp type_default(_block_type), do: nil
end
