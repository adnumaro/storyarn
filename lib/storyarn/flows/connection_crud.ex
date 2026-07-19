defmodule Storyarn.Flows.ConnectionCrud do
  @moduledoc false

  import Ecto.Query, warn: false

  alias Storyarn.Flows.Flow
  alias Storyarn.Flows.FlowConnection
  alias Storyarn.Flows.FlowNode
  alias Storyarn.Flows.NodeConnectionRules
  alias Storyarn.Flows.ReferenceIntegrity
  alias Storyarn.References.ProjectReferenceIntegrity
  alias Storyarn.Repo

  def list_connections(flow_id) do
    Repo.all(
      from(c in FlowConnection,
        join: sn in FlowNode,
        on: c.source_node_id == sn.id,
        join: tn in FlowNode,
        on: c.target_node_id == tn.id,
        where: c.flow_id == ^flow_id and is_nil(sn.deleted_at) and is_nil(tn.deleted_at),
        order_by: [asc: c.inserted_at],
        preload: [:source_node, :target_node]
      )
    )
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

  def create_connection(%Flow{} = flow, %FlowNode{} = source_node, %FlowNode{} = target_node, attrs) do
    attrs =
      attrs
      |> stringify_keys()
      |> Map.put("source_node_id", source_node.id)
      |> Map.put("target_node_id", target_node.id)

    create_connection(flow, attrs)
  end

  def create_connection(%Flow{} = flow, attrs) do
    attrs = stringify_keys(attrs)

    Repo.transaction(fn ->
      with {:ok, %{flow: locked_flow}} <-
             ReferenceIntegrity.lock_active_flow_for_write(flow),
           {:ok, source_node_id} <- normalize_endpoint_id(attrs["source_node_id"], :source),
           {:ok, target_node_id} <- normalize_endpoint_id(attrs["target_node_id"], :target),
           attrs =
             attrs
             |> Map.put("source_node_id", source_node_id)
             |> Map.put("target_node_id", target_node_id),
           changeset =
             FlowConnection.create_changeset(
               %FlowConnection{flow_id: locked_flow.id},
               attrs
             ),
           :ok <- validate_connection_changeset(changeset),
           {:ok, source_node, target_node} <-
             lock_connection_endpoints(
               locked_flow.id,
               source_node_id,
               target_node_id
             ),
           :ok <-
             validate_connection_rules(
               locked_flow.project_id,
               source_node,
               target_node,
               attrs
             ),
           {:ok, connection} <- Repo.insert(changeset) do
        connection
      else
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end

  def update_connection(%FlowConnection{} = connection, attrs) do
    attrs = stringify_keys(attrs)

    Repo.transaction(fn ->
      with {:ok, %{flow: flow}} <-
             ReferenceIntegrity.lock_active_flow_for_write(connection.flow_id),
           {:ok, locked_connection} <-
             lock_connection_for_write(connection.id, flow.id),
           {:ok, source_node, target_node} <-
             lock_connection_endpoints(
               flow.id,
               locked_connection.source_node_id,
               locked_connection.target_node_id
             ),
           effective_attrs =
             attrs
             |> Map.put_new("source_pin", locked_connection.source_pin)
             |> Map.put_new("target_pin", locked_connection.target_pin),
           changeset =
             FlowConnection.update_changeset(
               locked_connection,
               effective_attrs
             ),
           :ok <- validate_connection_changeset(changeset),
           :ok <-
             validate_connection_rules(
               flow.project_id,
               source_node,
               target_node,
               effective_attrs
             ),
           {:ok, updated_connection} <- Repo.update(changeset) do
        updated_connection
      else
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end

  def delete_connection(%FlowConnection{id: connection_id, flow_id: flow_id}) do
    delete_connection_by_id(flow_id, connection_id)
  end

  def delete_connection_by_id(flow_id, connection_id) do
    Repo.transaction(fn ->
      with {:ok, normalized_connection_id} <-
             normalize_connection_id(connection_id),
           {:ok, %{flow: flow}} <-
             ReferenceIntegrity.lock_active_flow_for_write(flow_id),
           {:ok, locked_connection} <-
             lock_connection_for_write(normalized_connection_id, flow.id),
           {:ok, deleted_connection} <- Repo.delete(locked_connection) do
        deleted_connection
      else
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end

  def delete_connection_by_nodes(flow_id, source_node_id, target_node_id) do
    with {:ok, source_node_id} <- normalize_endpoint_id(source_node_id, :source),
         {:ok, target_node_id} <- normalize_endpoint_id(target_node_id, :target) do
      delete_connection_count(flow_id, fn locked_flow_id ->
        Repo.delete_all(
          from(connection in FlowConnection,
            where:
              connection.flow_id == ^locked_flow_id and
                connection.source_node_id == ^source_node_id and
                connection.target_node_id == ^target_node_id
          )
        )
      end)
    else
      {:error, reason} -> {0, reason}
    end
  end

  def delete_connection_by_pins(flow_id, source_node_id, source_pin, target_node_id, target_pin)
      when is_binary(source_pin) and is_binary(target_pin) do
    with {:ok, source_node_id} <- normalize_endpoint_id(source_node_id, :source),
         {:ok, target_node_id} <- normalize_endpoint_id(target_node_id, :target) do
      delete_connection_count(flow_id, fn locked_flow_id ->
        Repo.delete_all(
          from(connection in FlowConnection,
            where:
              connection.flow_id == ^locked_flow_id and
                connection.source_node_id == ^source_node_id and
                connection.source_pin == ^source_pin and
                connection.target_node_id == ^target_node_id and
                connection.target_pin == ^target_pin
          )
        )
      end)
    else
      {:error, reason} -> {0, reason}
    end
  end

  def delete_connection_by_pins(_flow_id, _source_node_id, _source_pin, _target_node_id, _target_pin),
    do: {0, :invalid_connection_pin}

  @doc """
  Deletes all connections within a flow where both source and target are in the given node IDs list.
  Used by FlowSync to clear internal connections before rebuilding them.
  """
  def delete_connections_among_nodes(_flow_id, []), do: {0, nil}

  def delete_connections_among_nodes(flow_id, node_ids) when is_list(node_ids) do
    case normalize_node_ids(node_ids) do
      {:ok, node_ids} ->
        delete_connection_count(flow_id, fn locked_flow_id ->
          Repo.delete_all(
            from(connection in FlowConnection,
              where: connection.flow_id == ^locked_flow_id,
              where:
                connection.source_node_id in ^node_ids and
                  connection.target_node_id in ^node_ids
            )
          )
        end)

      {:error, reason} ->
        {0, reason}
    end
  end

  defp delete_connection_count(flow_id, delete_fn) do
    case Repo.transaction(fn -> delete_connections_in_locked_flow(flow_id, delete_fn) end) do
      {:ok, {count, result}} -> {count, result}
      {:error, reason} -> {0, reason}
    end
  end

  defp delete_connections_in_locked_flow(flow_id, delete_fn) do
    case ReferenceIntegrity.lock_active_flow_for_write(flow_id) do
      {:ok, %{flow: flow}} -> delete_fn.(flow.id)
      {:error, reason} -> Repo.rollback(reason)
    end
  end

  defp validate_connection_rules(project_id, source_node, target_node, attrs) do
    source_pin = attrs["source_pin"]
    target_pin = attrs["target_pin"]

    with {:ok, output_pins} <-
           ReferenceIntegrity.lock_effective_output_pins(project_id, source_node) do
      cond do
        source_node.type == "exit" ->
          {:error, :exit_has_no_outputs}

        source_node.type == "jump" ->
          {:error, :jump_has_no_outputs}

        target_node.type == "entry" ->
          {:error, :entry_has_no_inputs}

        not valid_source_pin?(source_node, source_pin, output_pins) ->
          {:error, :invalid_source_pin}

        not NodeConnectionRules.valid_input_pin?(target_node.type, target_pin) ->
          {:error, :invalid_target_pin}

        true ->
          :ok
      end
    end
  end

  defp valid_source_pin?(%FlowNode{type: "dialogue", data: data}, source_pin, output_pins) do
    source_pin in output_pins or
      NodeConnectionRules.valid_output_pin?("dialogue", data || %{}, source_pin)
  end

  defp valid_source_pin?(_source_node, source_pin, output_pins), do: source_pin in output_pins

  defp validate_connection_changeset(%Ecto.Changeset{valid?: true}), do: :ok
  defp validate_connection_changeset(changeset), do: {:error, changeset}

  defp lock_connection_endpoints(flow_id, source_node_id, target_node_id) do
    nodes =
      Repo.all(
        from(node in FlowNode,
          where:
            node.id in ^[source_node_id, target_node_id] and
              node.flow_id == ^flow_id and is_nil(node.deleted_at),
          order_by: [asc: node.id],
          lock: "FOR SHARE"
        )
      )

    by_id = Map.new(nodes, &{&1.id, &1})

    case {Map.get(by_id, source_node_id), Map.get(by_id, target_node_id)} do
      {nil, _target} -> {:error, :source_node_not_found}
      {_source, nil} -> {:error, :target_node_not_found}
      {source, target} -> {:ok, source, target}
    end
  end

  defp lock_connection_for_write(connection_id, flow_id) do
    case Repo.one(
           from(connection in FlowConnection,
             where:
               connection.id == ^connection_id and
                 connection.flow_id == ^flow_id,
             lock: "FOR UPDATE"
           )
         ) do
      %FlowConnection{} = connection -> {:ok, connection}
      nil -> {:error, :connection_not_found}
    end
  end

  defp normalize_endpoint_id(value, endpoint) do
    case ProjectReferenceIntegrity.normalize_optional_id(value) do
      {:ok, id} when is_integer(id) -> {:ok, id}
      _other -> {:error, :"#{endpoint}_node_not_found"}
    end
  end

  defp normalize_connection_id(value) do
    case ProjectReferenceIntegrity.normalize_optional_id(value) do
      {:ok, id} when is_integer(id) -> {:ok, id}
      _other -> {:error, :connection_not_found}
    end
  end

  defp normalize_node_ids(node_ids) do
    node_ids
    |> Enum.reduce_while({:ok, []}, fn node_id, {:ok, normalized_ids} ->
      case normalize_endpoint_id(node_id, :source) do
        {:ok, normalized_id} ->
          {:cont, {:ok, [normalized_id | normalized_ids]}}

        {:error, _reason} ->
          {:halt, {:error, :node_not_found}}
      end
    end)
    |> case do
      {:ok, normalized_ids} -> {:ok, Enum.reverse(normalized_ids)}
      {:error, _reason} = error -> error
    end
  end

  defp stringify_keys(attrs) do
    Map.new(attrs, fn
      {key, value} when is_atom(key) -> {Atom.to_string(key), value}
      pair -> pair
    end)
  end

  def change_connection(%FlowConnection{} = connection, attrs \\ %{}) do
    FlowConnection.update_changeset(connection, attrs)
  end

  def get_outgoing_connections(node_id) do
    Repo.all(from(c in FlowConnection, where: c.source_node_id == ^node_id, preload: [:target_node]))
  end

  def get_incoming_connections(node_id) do
    Repo.all(from(c in FlowConnection, where: c.target_node_id == ^node_id, preload: [:source_node]))
  end
end
