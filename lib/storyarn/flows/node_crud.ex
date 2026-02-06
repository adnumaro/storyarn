defmodule Storyarn.Flows.NodeCrud do
  @moduledoc false

  import Ecto.Query, warn: false

  alias Storyarn.Flows.{Flow, FlowNode}
  alias Storyarn.Pages.ReferenceTracker
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

    case attrs["type"] do
      "entry" ->
        if has_entry_node?(flow.id) do
          {:error, :entry_node_exists}
        else
          insert_node(flow, attrs)
        end

      "hub" ->
        hub_id = get_in(attrs, ["data", "hub_id"])
        hub_id = if hub_id == nil || hub_id == "", do: generate_hub_id(flow.id), else: hub_id

        if hub_id_exists?(flow.id, hub_id, nil) do
          {:error, :hub_id_not_unique}
        else
          updated_data = Map.put(attrs["data"] || %{}, "hub_id", hub_id)
          insert_node(flow, Map.put(attrs, "data", updated_data))
        end

      _ ->
        insert_node(flow, attrs)
    end
  end

  defp insert_node(%Flow{} = flow, attrs) do
    %FlowNode{flow_id: flow.id}
    |> FlowNode.create_changeset(attrs)
    |> Repo.insert()
  end

  defp has_entry_node?(flow_id) do
    from(n in FlowNode,
      where: n.flow_id == ^flow_id and n.type == "entry"
    )
    |> Repo.exists?()
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
      select: %{
        id: n.id,
        hub_id: fragment("?->>'hub_id'", n.data),
        label: fragment("?->>'label'", n.data)
      },
      order_by: [asc: fragment("?->>'hub_id'", n.data)]
    )
    |> Repo.all()
  end

  @doc """
  Finds a hub node in a flow by its hub_id.
  Returns nil if not found.
  """
  def get_hub_by_hub_id(flow_id, hub_id) do
    from(n in FlowNode,
      where: n.flow_id == ^flow_id and n.type == "hub",
      where: fragment("?->>'hub_id' = ?", n.data, ^hub_id)
    )
    |> Repo.one()
  end

  defp generate_hub_id(flow_id) do
    max_suffix =
      from(n in FlowNode,
        where: n.flow_id == ^flow_id and n.type == "hub",
        where: fragment("?->>'hub_id' ~ '^hub_[0-9]+$'", n.data),
        select:
          fragment("max(cast(substring(?->>'hub_id' from 'hub_([0-9]+)') as integer))", n.data)
      )
      |> Repo.one()

    "hub_#{(max_suffix || 0) + 1}"
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

      cond do
        hub_id == nil || hub_id == "" ->
          {:error, :hub_id_required}

        hub_id_exists?(node.flow_id, hub_id, node.id) ->
          {:error, :hub_id_not_unique}

        true ->
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
      # Clean up orphaned jump nodes when deleting a hub
      orphaned_count =
        if node.type == "hub" do
          clear_orphaned_jumps(node.flow_id, node.data["hub_id"])
        else
          0
        end

      ReferenceTracker.delete_flow_node_references(node.id)

      case Repo.delete(node) do
        {:ok, deleted_node} ->
          {:ok, deleted_node, %{orphaned_jumps: orphaned_count}}

        error ->
          error
      end
    end
  end

  defp clear_orphaned_jumps(flow_id, hub_id) when is_binary(hub_id) and hub_id != "" do
    query =
      from(n in FlowNode,
        where: n.flow_id == ^flow_id and n.type == "jump",
        where: fragment("?->>'target_hub_id' = ?", n.data, ^hub_id),
        update: [set: [data: fragment("jsonb_set(?, '{target_hub_id}', '\"\"'::jsonb)", n.data)]]
      )

    {count, _} = Repo.update_all(query, [])

    count
  end

  defp clear_orphaned_jumps(_flow_id, _hub_id), do: 0

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
