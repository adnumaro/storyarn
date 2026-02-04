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
    attrs = stringify_keys(attrs)

    changeset =
      %FlowNode{flow_id: flow.id}
      |> FlowNode.create_changeset(attrs)

    # Validate special node types
    case attrs["type"] do
      "entry" ->
        if has_entry_node?(flow.id) do
          {:error, :entry_node_exists}
        else
          Repo.insert(changeset)
        end

      "hub" ->
        hub_id = get_in(attrs, ["data", "hub_id"])

        if hub_id && hub_id != "" && hub_id_exists?(flow.id, hub_id, nil) do
          {:error, :hub_id_not_unique}
        else
          Repo.insert(changeset)
        end

      _ ->
        Repo.insert(changeset)
    end
  end

  @doc """
  Checks if a flow already has an entry node.
  """
  def has_entry_node?(flow_id) do
    from(n in FlowNode,
      where: n.flow_id == ^flow_id and n.type == "entry"
    )
    |> Repo.exists?()
  end

  @doc """
  Gets the entry node for a flow.
  """
  def get_entry_node(flow_id) do
    from(n in FlowNode,
      where: n.flow_id == ^flow_id and n.type == "entry"
    )
    |> Repo.one()
  end

  @doc """
  Checks if a hub_id already exists in a flow (excluding a specific node).
  """
  def hub_id_exists?(flow_id, hub_id, exclude_node_id) do
    query =
      from(n in FlowNode,
        where: n.flow_id == ^flow_id and n.type == "hub",
        where: fragment("?->>'hub_id' = ?", n.data, ^hub_id)
      )

    query =
      if exclude_node_id do
        where(query, [n], n.id != ^exclude_node_id)
      else
        query
      end

    Repo.exists?(query)
  end

  @doc """
  Lists all hub nodes in a flow with their hub_ids.
  Useful for populating Jump node target dropdown.
  """
  def list_hubs(flow_id) do
    from(n in FlowNode,
      where: n.flow_id == ^flow_id and n.type == "hub",
      select: %{id: n.id, hub_id: fragment("?->>'hub_id'", n.data)},
      order_by: [asc: fragment("?->>'hub_id'", n.data)]
    )
    |> Repo.all()
  end

  defp stringify_keys(map) when is_map(map) do
    Map.new(map, fn
      {k, v} when is_atom(k) -> {Atom.to_string(k), v}
      {k, v} -> {k, v}
    end)
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
    # Validate hub_id uniqueness for hub nodes
    if node.type == "hub" do
      hub_id = data["hub_id"]

      if hub_id && hub_id != "" && hub_id_exists?(node.flow_id, hub_id, node.id) do
        {:error, :hub_id_not_unique}
      else
        do_update_node_data(node, data)
      end
    else
      do_update_node_data(node, data)
    end
  end

  defp do_update_node_data(node, data) do
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
    # Prevent deletion of entry nodes
    if node.type == "entry" do
      {:error, :cannot_delete_entry_node}
    else
      # Clean up references before deleting
      alias Storyarn.Pages.ReferenceTracker
      ReferenceTracker.delete_flow_node_references(node.id)
      Repo.delete(node)
    end
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
