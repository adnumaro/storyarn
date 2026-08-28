defmodule Storyarn.Flows.AI.FlowNeighborhoodContext do
  @moduledoc false

  alias Storyarn.Flows.ContextQueries

  @spec build(map(), map(), map(), function()) :: {:ok, map()} | {:error, atom()}
  def build(project, subject_ref, policy, entity_builder) do
    with {:ok, neighborhood} <-
           ContextQueries.neighborhood(
             project.id,
             subject_ref.subject_id,
             policy.max_depth,
             policy.max_fan_out,
             policy.max_entities
           ),
         {:ok, flow_entity} <- flow_entity(neighborhood.flow, entity_builder),
         {:ok, node_entities} <- node_entities(neighborhood.nodes, subject_ref.subject_id, entity_builder),
         {:ok, connection_entities} <- connection_entities(neighborhood.connections, entity_builder) do
      warnings =
        []
        |> maybe_warn(neighborhood.depth_limited?, "depth_limit_reached")
        |> maybe_warn(neighborhood.excluded != [], "optional_context_truncated")

      {:ok,
       %{
         entities: [flow_entity] ++ node_entities ++ connection_entities,
         excluded: neighborhood.excluded,
         warnings: warnings
       }}
    end
  end

  defp flow_entity(flow, entity_builder) do
    entity_builder.(
      "flow",
      flow.id,
      %{
        "name" => flow.name,
        "shortcut" => flow.shortcut,
        "description" => flow.description
      },
      required: true,
      priority: 1,
      revision: flow.updated_at
    )
  end

  defp node_entities(nodes, subject_id, entity_builder) do
    nodes
    |> Map.values()
    |> Enum.sort_by(fn {node, depth} -> {depth, node.id} end)
    |> Enum.reduce_while({:ok, []}, fn {node, depth}, {:ok, acc} ->
      required? = node.id == subject_id

      case entity_builder.(
             "flow_node",
             node.id,
             %{
               "type" => node.type,
               "data" => node.data,
               "depth" => depth
             },
             required: required?,
             priority: if(required?, do: 1, else: min(depth + 1, 4)),
             revision: node.updated_at
           ) do
        {:ok, entity} -> {:cont, {:ok, [entity | acc]}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
    |> reverse_result()
  end

  defp connection_entities(connections, entity_builder) do
    connections
    |> Map.values()
    |> Enum.sort_by(fn {connection, depth} -> {depth, connection.id} end)
    |> Enum.reduce_while({:ok, []}, fn {connection, depth}, {:ok, acc} ->
      case entity_builder.(
             "flow_connection",
             connection.id,
             %{
               "source_node_id" => connection.source_node_id,
               "source_pin" => connection.source_pin,
               "target_node_id" => connection.target_node_id,
               "target_pin" => connection.target_pin,
               "label" => connection.label,
               "depth" => depth
             },
             priority: min(depth + 1, 4),
             revision: connection.updated_at
           ) do
        {:ok, entity} -> {:cont, {:ok, [entity | acc]}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
    |> reverse_result()
  end

  defp reverse_result({:ok, entities}), do: {:ok, Enum.reverse(entities)}
  defp reverse_result({:error, reason}), do: {:error, reason}

  defp maybe_warn(warnings, true, warning), do: [warning | warnings]
  defp maybe_warn(warnings, false, _warning), do: warnings
end
