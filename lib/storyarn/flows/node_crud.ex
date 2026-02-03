defmodule Storyarn.Flows.NodeCrud do
  @moduledoc false

  import Ecto.Query, warn: false

  alias Storyarn.Flows.{Flow, FlowNode}
  alias Storyarn.Repo

  def list_nodes(flow_id) do
    from(n in FlowNode,
      where: n.flow_id == ^flow_id,
      order_by: [asc: n.inserted_at]
    )
    |> Repo.all()
  end

  def get_node(flow_id, node_id) do
    FlowNode
    |> where(flow_id: ^flow_id, id: ^node_id)
    |> preload([:outgoing_connections, :incoming_connections])
    |> Repo.one()
  end

  def get_node!(flow_id, node_id) do
    FlowNode
    |> where(flow_id: ^flow_id, id: ^node_id)
    |> preload([:outgoing_connections, :incoming_connections])
    |> Repo.one!()
  end

  def get_node_by_id!(node_id) do
    Repo.get!(FlowNode, node_id)
  end

  def create_node(%Flow{} = flow, attrs) do
    %FlowNode{flow_id: flow.id}
    |> FlowNode.create_changeset(attrs)
    |> Repo.insert()
  end

  def update_node(%FlowNode{} = node, attrs) do
    node
    |> FlowNode.update_changeset(attrs)
    |> Repo.update()
  end

  def update_node_position(%FlowNode{} = node, attrs) do
    node
    |> FlowNode.position_changeset(attrs)
    |> Repo.update()
  end

  def update_node_data(%FlowNode{} = node, data) do
    result =
      node
      |> FlowNode.data_changeset(%{data: data})
      |> Repo.update()

    case result do
      {:ok, updated_node} ->
        # Track references in node data (dialogue mentions, speaker references)
        alias Storyarn.Pages.ReferenceTracker
        ReferenceTracker.update_flow_node_references(updated_node)
        {:ok, updated_node}

      error ->
        error
    end
  end

  def delete_node(%FlowNode{} = node) do
    # Clean up references before deleting
    alias Storyarn.Pages.ReferenceTracker
    ReferenceTracker.delete_flow_node_references(node.id)
    Repo.delete(node)
  end

  def change_node(%FlowNode{} = node, attrs \\ %{}) do
    FlowNode.update_changeset(node, attrs)
  end

  def count_nodes_by_type(flow_id) do
    from(n in FlowNode,
      where: n.flow_id == ^flow_id,
      group_by: n.type,
      select: {n.type, count(n.id)}
    )
    |> Repo.all()
    |> Map.new()
  end
end
