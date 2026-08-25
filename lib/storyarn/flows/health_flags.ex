defmodule Storyarn.Flows.HealthFlags do
  @moduledoc false

  alias Storyarn.Flows.Instruction

  @spec add([map()], MapSet.t(), %{String.t() => String.t()}) :: [map()]
  def add(nodes, stale_node_ids, variable_types) do
    Enum.map(nodes, fn node ->
      data =
        node.data
        |> add_stale(node.id, stale_node_ids)
        |> add_type_warning(node.type, variable_types)

      %{node | data: data}
    end)
  end

  @spec add_type_warning(map(), String.t(), %{String.t() => String.t()}) :: map()
  def add_type_warning(data, "instruction", variable_types) do
    assignments = data["assignments"] || []

    if Instruction.has_type_warnings?(assignments, variable_types),
      do: Map.put(data, "has_type_warnings", true),
      else: data
  end

  def add_type_warning(data, "dialogue", variable_types) do
    responses = data["responses"] || []

    updated =
      Enum.map(responses, fn response ->
        assignments = response["instruction_assignments"] || []

        if Instruction.has_type_warnings?(assignments, variable_types),
          do: Map.put(response, "has_type_warnings", true),
          else: response
      end)

    Map.put(data, "responses", updated)
  end

  def add_type_warning(data, _type, _variable_types), do: data

  @spec add_stale(map(), integer(), MapSet.t()) :: map()
  def add_stale(data, node_id, stale_node_ids) do
    if MapSet.member?(stale_node_ids, node_id),
      do: Map.put(data, "has_stale_refs", true),
      else: data
  end
end
