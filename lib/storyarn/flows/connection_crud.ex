defmodule Storyarn.Flows.ConnectionCrud do
  @moduledoc false

  import Ecto.Query, warn: false

  alias Storyarn.Flows.{Flow, FlowConnection, FlowNode}
  alias Storyarn.Localization
  alias Storyarn.Repo

  def list_connections(flow_id) do
    from(c in FlowConnection,
      join: sn in FlowNode,
      on: c.source_node_id == sn.id,
      join: tn in FlowNode,
      on: c.target_node_id == tn.id,
      where: c.flow_id == ^flow_id and is_nil(sn.deleted_at) and is_nil(tn.deleted_at),
      order_by: [asc: c.inserted_at],
      preload: [:source_node, :target_node]
    )
    |> Repo.all()
  end

  def get_connection(flow_id, connection_id) do
    FlowConnection
    |> where(flow_id: ^flow_id, id: ^connection_id)
    |> preload([:source_node, :target_node])
    |> Repo.one()
  end

  def get_connection!(flow_id, connection_id) do
    FlowConnection
    |> where(flow_id: ^flow_id, id: ^connection_id)
    |> preload([:source_node, :target_node])
    |> Repo.one!()
  end

  def get_connection_by_id!(connection_id) do
    Repo.get!(FlowConnection, connection_id)
  end

  def create_connection(
        %Flow{} = flow,
        %FlowNode{} = source_node,
        %FlowNode{} = target_node,
        attrs
      ) do
    attrs =
      attrs
      |> Map.put(:source_node_id, source_node.id)
      |> Map.put(:target_node_id, target_node.id)

    %FlowConnection{flow_id: flow.id}
    |> FlowConnection.create_changeset(attrs)
    |> Repo.insert()
    |> tap(fn
      {:ok, _connection} -> Localization.extract_flow(flow)
      _ -> :ok
    end)
  end

  def create_connection(%Flow{} = flow, attrs) do
    source_node_id = attrs[:source_node_id] || attrs["source_node_id"]
    target_node_id = attrs[:target_node_id] || attrs["target_node_id"]

    # Scope nodes to this flow to prevent cross-flow connections
    source_node =
      from(n in FlowNode, where: n.id == ^source_node_id and n.flow_id == ^flow.id)
      |> Repo.one()

    target_node =
      from(n in FlowNode, where: n.id == ^target_node_id and n.flow_id == ^flow.id)
      |> Repo.one()

    case validate_connection_rules(source_node, target_node) do
      :ok ->
        %FlowConnection{flow_id: flow.id}
        |> FlowConnection.create_changeset(attrs)
        |> Repo.insert()
        |> tap(fn
          {:ok, _connection} -> Localization.extract_flow(flow)
          _ -> :ok
        end)

      {:error, _reason} = error ->
        error
    end
  end

  def update_connection(%FlowConnection{} = connection, attrs) do
    connection
    |> FlowConnection.update_changeset(attrs)
    |> Repo.update()
    |> tap(fn
      {:ok, _updated_connection} ->
        Repo.get(Flow, connection.flow_id) |> Localization.extract_flow()

      _ ->
        :ok
    end)
  end

  def delete_connection(%FlowConnection{} = connection) do
    Repo.delete(connection)
    |> tap(fn
      {:ok, _deleted_connection} ->
        Repo.get(Flow, connection.flow_id) |> Localization.extract_flow()

      _ ->
        :ok
    end)
  end

  def delete_connection_by_nodes(flow_id, source_node_id, target_node_id) do
    from(c in FlowConnection,
      where:
        c.flow_id == ^flow_id and
          c.source_node_id == ^source_node_id and
          c.target_node_id == ^target_node_id
    )
    |> Repo.delete_all()
    |> tap(fn
      {deleted_count, _} when deleted_count > 0 ->
        Repo.get(Flow, flow_id) |> Localization.extract_flow()

      _ ->
        :ok
    end)
  end

  def delete_connection_by_pins(flow_id, source_node_id, source_pin, target_node_id, target_pin) do
    from(c in FlowConnection,
      where:
        c.flow_id == ^flow_id and
          c.source_node_id == ^source_node_id and
          c.source_pin == ^source_pin and
          c.target_node_id == ^target_node_id and
          c.target_pin == ^target_pin
    )
    |> Repo.delete_all()
    |> tap(fn
      {deleted_count, _} when deleted_count > 0 ->
        Repo.get(Flow, flow_id) |> Localization.extract_flow()

      _ ->
        :ok
    end)
  end

  @doc """
  Deletes all connections within a flow where both source and target are in the given node IDs list.
  Used by FlowSync to clear internal connections before rebuilding them.
  """
  def delete_connections_among_nodes(_flow_id, []), do: {0, nil}

  def delete_connections_among_nodes(flow_id, node_ids) when is_list(node_ids) do
    from(c in FlowConnection,
      where: c.flow_id == ^flow_id,
      where: c.source_node_id in ^node_ids and c.target_node_id in ^node_ids
    )
    |> Repo.delete_all()
  end

  defp validate_connection_rules(nil, _), do: {:error, :source_node_not_found}
  defp validate_connection_rules(_, nil), do: {:error, :target_node_not_found}

  defp validate_connection_rules(source_node, target_node) do
    cond do
      source_node.type == "exit" -> {:error, :exit_has_no_outputs}
      source_node.type == "jump" -> {:error, :jump_has_no_outputs}
      target_node.type == "entry" -> {:error, :entry_has_no_inputs}
      true -> :ok
    end
  end

  def change_connection(%FlowConnection{} = connection, attrs \\ %{}) do
    FlowConnection.update_changeset(connection, attrs)
  end

  def get_outgoing_connections(node_id) do
    from(c in FlowConnection,
      where: c.source_node_id == ^node_id,
      preload: [:target_node]
    )
    |> Repo.all()
  end

  def get_incoming_connections(node_id) do
    from(c in FlowConnection,
      where: c.target_node_id == ^node_id,
      preload: [:source_node]
    )
    |> Repo.all()
  end
end
