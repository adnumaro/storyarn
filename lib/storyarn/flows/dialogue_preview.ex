defmodule Storyarn.Flows.DialoguePreview do
  @moduledoc """
  Resolves authored Flow graphs to the next dialogue shown by the editor preview.

  Traversal, jump resolution, cycle detection and the depth guard are Flow
  semantics. The caller remains responsible for speaker presentation, text
  sanitization and serialization.
  """

  import Ecto.Query

  alias Storyarn.Flows.FlowConnection
  alias Storyarn.Flows.FlowNode
  alias Storyarn.Repo

  @max_traversal_depth 50

  @type graph :: %{nodes: %{optional(pos_integer()) => map()}, connections: [map()]}
  @type preview :: %{node: map(), has_next?: boolean()}
  @type result :: {:ok, preview()} | :empty | :not_found | :no_transition

  @doc "Starts a preview from a node in a persisted Flow."
  @spec start(pos_integer(), integer() | String.t()) :: result()
  def start(flow_id, node_id) do
    flow_id
    |> load_graph()
    |> resolve(node_id)
  end

  @doc "Follows one authored output pin and resolves to the next dialogue."
  @spec follow(pos_integer(), integer() | String.t(), String.t()) :: result()
  def follow(flow_id, node_id, source_pin) when is_binary(source_pin) do
    graph = load_graph(flow_id)

    with {:ok, normalized_node_id} <- normalize_node_id(node_id),
         true <- Map.has_key?(graph.nodes, normalized_node_id),
         %{target_node_id: target_node_id} <-
           Enum.find(graph.connections, fn connection ->
             connection.source_node_id == normalized_node_id and connection.source_pin == source_pin
           end) do
      resolve(graph, target_node_id)
    else
      _missing -> :no_transition
    end
  end

  @doc "Resolves an already-loaded graph to the next dialogue node."
  @spec resolve(graph(), integer() | String.t()) :: result()
  def resolve(%{nodes: nodes} = graph, node_id) do
    with {:ok, normalized_node_id} <- normalize_node_id(node_id),
         {:ok, node} <- Map.fetch(nodes, normalized_node_id) do
      traverse(graph, node, MapSet.new(), 0)
    else
      _missing -> :not_found
    end
  end

  defp traverse(_graph, nil, _visited, _depth), do: :empty

  defp traverse(graph, %{type: "dialogue"} = node, _visited, _depth) do
    {:ok, %{node: node, has_next?: dialogue_has_next?(graph, node)}}
  end

  defp traverse(_graph, _node, _visited, depth) when depth >= @max_traversal_depth, do: :empty

  defp traverse(graph, node, visited, depth) do
    if MapSet.member?(visited, node.id) do
      :empty
    else
      continue_traversal(graph, node, MapSet.put(visited, node.id), depth)
    end
  end

  defp continue_traversal(graph, %{type: "jump"} = node, visited, depth) do
    target_hub_id = node.data["target_hub_id"]

    if is_binary(target_hub_id) and target_hub_id != "" do
      case find_hub(graph.nodes, target_hub_id) do
        nil -> :empty
        hub -> traverse(graph, hub, visited, depth + 1)
      end
    else
      :empty
    end
  end

  defp continue_traversal(graph, node, visited, depth) do
    case first_outgoing(graph.connections, node.id) do
      nil -> :empty
      connection -> traverse(graph, Map.get(graph.nodes, connection.target_node_id), visited, depth + 1)
    end
  end

  defp dialogue_has_next?(graph, node) do
    responses = node.data["responses"] || []

    responses == [] and
      Enum.any?(graph.connections, fn connection ->
        connection.source_node_id == node.id and connection.source_pin == "output"
      end)
  end

  defp find_hub(nodes, target_hub_id) do
    Enum.find_value(nodes, fn {_node_id, node} ->
      if node.type == "hub" and node.data["hub_id"] == target_hub_id, do: node
    end)
  end

  defp first_outgoing(connections, node_id) do
    Enum.find(connections, &(&1.source_node_id == node_id))
  end

  defp load_graph(flow_id) do
    nodes =
      Repo.all(
        from(node in FlowNode,
          where: node.flow_id == ^flow_id and is_nil(node.deleted_at),
          order_by: [asc: node.inserted_at, asc: node.id],
          select: %{id: node.id, type: node.type, data: node.data}
        )
      )

    connections =
      Repo.all(
        from(connection in FlowConnection,
          join: source in FlowNode,
          on: source.id == connection.source_node_id,
          join: target in FlowNode,
          on: target.id == connection.target_node_id,
          where:
            connection.flow_id == ^flow_id and is_nil(source.deleted_at) and
              is_nil(target.deleted_at),
          order_by: [asc: connection.inserted_at, asc: connection.id],
          select: %{
            source_node_id: connection.source_node_id,
            source_pin: connection.source_pin,
            target_node_id: connection.target_node_id,
            target_pin: connection.target_pin
          }
        )
      )

    %{nodes: Map.new(nodes, &{&1.id, &1}), connections: connections}
  end

  defp normalize_node_id(node_id) when is_integer(node_id), do: {:ok, node_id}

  defp normalize_node_id(node_id) when is_binary(node_id) do
    case Integer.parse(node_id) do
      {parsed, ""} -> {:ok, parsed}
      _invalid -> :error
    end
  end

  defp normalize_node_id(_node_id), do: :error
end
