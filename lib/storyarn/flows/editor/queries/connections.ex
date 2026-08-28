defmodule Storyarn.Flows.Editor.Queries.Connections do
  @moduledoc false

  import Ecto.Query, warn: false

  alias Storyarn.Flows.FlowConnection
  alias Storyarn.Flows.FlowNode
  alias Storyarn.Repo

  def list(flow_id) do
    Repo.all(
      from(connection in FlowConnection,
        join: source_node in FlowNode,
        on: connection.source_node_id == source_node.id,
        join: target_node in FlowNode,
        on: connection.target_node_id == target_node.id,
        where:
          connection.flow_id == ^flow_id and is_nil(source_node.deleted_at) and
            is_nil(target_node.deleted_at),
        order_by: [asc: connection.inserted_at],
        preload: [:source_node, :target_node]
      )
    )
  end

  def get(flow_id, connection_id) do
    FlowConnection
    |> where(flow_id: ^flow_id, id: ^connection_id)
    |> preload([:source_node, :target_node])
    |> Repo.one()
  end

  def get!(flow_id, connection_id) do
    FlowConnection
    |> where(flow_id: ^flow_id, id: ^connection_id)
    |> preload([:source_node, :target_node])
    |> Repo.one!()
  end

  def get_by_id!(connection_id), do: Repo.get!(FlowConnection, connection_id)

  def outgoing(node_id) do
    Repo.all(
      from(connection in FlowConnection,
        where: connection.source_node_id == ^node_id,
        preload: [:target_node]
      )
    )
  end

  def incoming(node_id) do
    Repo.all(
      from(connection in FlowConnection,
        where: connection.target_node_id == ^node_id,
        preload: [:source_node]
      )
    )
  end
end
