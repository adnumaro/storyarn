defmodule Storyarn.Flows.Versioning.SnapshotViewer do
  @moduledoc """
  Converts a Flow snapshot into the read-only canvas contract.

  Viewer serialization is owned by Flows so Project/Scene/Sheet snapshot
  tooling cannot change the Flow canvas representation indirectly.
  """

  alias Storyarn.Flows.HubColors

  @spec serialize(map()) :: map()
  def serialize(snapshot) do
    nodes = Map.get(snapshot, "nodes", [])

    id_map =
      nodes
      |> Enum.with_index()
      |> Map.new(fn {_node, index} -> {index, -(index + 1)} end)

    serialized_nodes =
      nodes
      |> Enum.with_index()
      |> Enum.map(&serialize_node(&1, id_map))

    serialized_connections =
      snapshot
      |> Map.get("connections", [])
      |> Enum.with_index()
      |> Enum.map(&serialize_connection(&1, id_map))
      |> Enum.filter(fn connection ->
        not is_nil(connection.source_node_id) and not is_nil(connection.target_node_id)
      end)

    %{
      id: -1,
      name: snapshot["name"],
      nodes: serialized_nodes,
      connections: serialized_connections
    }
  end

  defp serialize_node({node, index}, id_map) do
    %{
      id: Map.fetch!(id_map, index),
      type: node["type"],
      position: %{x: node["position_x"] || 0, y: node["position_y"] || 0},
      data: maybe_add_hub_color(node["data"] || %{})
    }
  end

  defp serialize_connection({connection, index}, id_map) do
    %{
      id: -(index + 1),
      source_node_id: Map.get(id_map, connection["source_node_index"]),
      target_node_id: Map.get(id_map, connection["target_node_index"]),
      source_pin: connection["source_pin"],
      target_pin: connection["target_pin"],
      label: connection["label"]
    }
  end

  defp maybe_add_hub_color(%{"color" => color} = data) when is_binary(color) do
    Map.put(data, "color_hex", HubColors.resolve(color))
  end

  defp maybe_add_hub_color(data), do: data
end
