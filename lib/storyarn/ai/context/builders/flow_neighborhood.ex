defmodule Storyarn.AI.Context.Builders.FlowNeighborhood do
  @moduledoc false

  alias Storyarn.AI.Context.Entity
  alias Storyarn.AI.Context.Policy
  alias Storyarn.AI.Context.SubjectRef
  alias Storyarn.Flows

  @spec build(map(), SubjectRef.t(), Policy.t()) :: {:ok, map()} | {:error, atom()}
  def build(project, %SubjectRef{} = subject_ref, %Policy{} = policy) do
    with {:ok, neighborhood} <-
           Flows.get_context_neighborhood(
             project.id,
             subject_ref.subject_id,
             policy.max_depth,
             policy.max_fan_out,
             policy.max_entities
           ),
         {:ok, flow_entity} <- flow_entity(neighborhood.flow),
         {:ok, node_entities} <- node_entities(neighborhood.nodes, subject_ref.subject_id),
         {:ok, connection_entities} <- connection_entities(neighborhood.connections) do
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

  defp flow_entity(flow) do
    Entity.new(
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

  defp node_entities(nodes, subject_id) do
    nodes
    |> Map.values()
    |> Enum.sort_by(fn {node, depth} -> {depth, node.id} end)
    |> Enum.reduce_while({:ok, []}, fn {node, depth}, {:ok, acc} ->
      required? = node.id == subject_id

      case Entity.new(
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

  defp connection_entities(connections) do
    connections
    |> Map.values()
    |> Enum.sort_by(fn {connection, depth} -> {depth, connection.id} end)
    |> Enum.reduce_while({:ok, []}, fn {connection, depth}, {:ok, acc} ->
      case Entity.new(
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
