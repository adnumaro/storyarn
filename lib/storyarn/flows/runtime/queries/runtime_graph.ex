defmodule Storyarn.Flows.RuntimeGraph do
  @moduledoc """
  Flow-owned runtime projection of nodes and connections.

  The projection is deliberately independent from sockets and LiveVue. Asset
  URL generation remains a presentation concern, while graph identity,
  ordering and entry selection live here.
  """

  alias Storyarn.Flows.Editor

  @type node_id :: pos_integer()
  @type runtime_node :: map()
  @type connection :: map()
  @type t :: %{nodes: %{optional(node_id()) => runtime_node()}, connections: [connection()]}

  @doc "Loads the graph projection used by the Flow evaluator and debugger."
  @spec load(pos_integer()) :: t()
  def load(flow_id) when is_integer(flow_id) do
    %{
      nodes: flow_id |> Editor.list_runtime_nodes() |> build_nodes_map(),
      connections: flow_id |> Editor.list_connections() |> build_connections()
    }
  end

  @doc "Builds a runtime graph from already-loaded records."
  @spec from_records([map()], [map()]) :: t()
  def from_records(nodes, connections) when is_list(nodes) and is_list(connections) do
    %{nodes: build_nodes_map(nodes), connections: build_connections(connections)}
  end

  @doc "Returns an empty runtime graph."
  @spec empty() :: t()
  def empty, do: %{nodes: %{}, connections: []}

  @doc "Finds the canonical entry node in a runtime node map."
  @spec entry_node_id(map()) :: node_id() | nil
  def entry_node_id(nodes) when is_map(nodes) do
    Enum.find_value(nodes, fn {node_id, node} ->
      if node.type == "entry", do: node_id
    end)
  end

  @doc "Returns the connection represented by the last edge in an execution path."
  @spec active_connection([node_id()], [connection()]) :: map() | nil
  def active_connection([], _connections), do: nil
  def active_connection([_single], _connections), do: nil

  def active_connection(path, connections) when is_list(path) and is_list(connections) do
    source_id = Enum.at(path, -2)
    target_id = Enum.at(path, -1)

    Enum.find_value(connections, fn connection ->
      if connection.source_node_id == source_id and connection.target_node_id == target_id do
        %{
          source_node_id: source_id,
          target_node_id: target_id,
          source_pin: connection.source_pin
        }
      end
    end)
  end

  defp build_nodes_map(nodes) do
    Map.new(nodes, fn node ->
      {node.id,
       %{
         id: node.id,
         type: node.type,
         data: Map.get(node, :data) || %{},
         parent_id: Map.get(node, :parent_id),
         composition_source_id: Map.get(node, :composition_source_id),
         sequence_config: Map.get(node, :sequence_config),
         sequence_visual_layers: Map.get(node, :sequence_visual_layers) || [],
         sequence_tracks: Map.get(node, :sequence_tracks) || []
       }}
    end)
  end

  defp build_connections(connections) do
    Enum.map(connections, fn connection ->
      %{
        source_node_id: connection.source_node_id,
        source_pin: connection.source_pin,
        target_node_id: connection.target_node_id,
        target_pin: connection.target_pin
      }
    end)
  end
end
