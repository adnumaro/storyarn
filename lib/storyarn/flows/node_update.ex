defmodule Storyarn.Flows.NodeUpdate do
  @moduledoc false

  import Ecto.Query, warn: false

  alias Storyarn.Collaboration
  alias Storyarn.Flows.Flow
  alias Storyarn.Flows.FlowConnection
  alias Storyarn.Flows.FlowNode
  alias Storyarn.Flows.NodeConnectionRules
  alias Storyarn.Flows.NodeCrud
  alias Storyarn.Flows.ReferenceIntegrity
  alias Storyarn.Localization
  alias Storyarn.References
  alias Storyarn.Repo
  alias Storyarn.Shared.TimeHelpers
  alias Storyarn.Shared.WordCount

  def update_node(%FlowNode{} = node, attrs) do
    result = Repo.transaction(fn -> update_node_transaction(node, attrs) end)

    maybe_broadcast_dashboard(result, node)
    result
  end

  defp update_node_transaction(node, attrs) do
    with {:ok, %{project_id: project_id, flow: flow, node: locked_node}} <-
           ReferenceIntegrity.lock_active_node_for_write(node),
         changeset = FlowNode.update_changeset(locked_node, attrs),
         type = Ecto.Changeset.get_field(changeset, :type),
         data = Ecto.Changeset.get_field(changeset, :data) || %{},
         parent_id = Ecto.Changeset.get_field(changeset, :parent_id),
         {:ok, parent_id} <-
           ReferenceIntegrity.lock_node_parent(flow.id, parent_id, locked_node.id),
         {:ok, data} <-
           ReferenceIntegrity.lock_and_normalize_node_references(
             project_id,
             flow.id,
             type,
             data
           ) do
      updated_node =
        changeset
        |> Ecto.Changeset.put_change(:parent_id, parent_id)
        |> Ecto.Changeset.put_change(:data, data)
        |> Ecto.Changeset.put_change(
          :word_count,
          WordCount.for_node_data(type, data)
        )
        |> Repo.update()
        |> handle_persisted_node_data(project_id)

      _connections_changed? =
        reconcile_outgoing_connection_pins(
          project_id,
          locked_node,
          updated_node
        )

      updated_node
    else
      {:error, reason} -> Repo.rollback(reason)
    end
  end

  def update_node_position(%FlowNode{} = node, attrs) do
    Repo.transaction(fn ->
      with {:ok, %{node: locked_node}} <-
             ReferenceIntegrity.lock_active_node_for_write(node),
           {:ok, updated_node} <-
             locked_node
             |> FlowNode.position_changeset(attrs)
             |> Repo.update() do
        updated_node
      else
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end

  @doc """
  Reparents a node to another sequence (or to the flow root). `parent_id`
  is an integer id of an existing sequence-typed flow_node or `nil` for
  root-level. The `trg_flow_nodes_validate_parent_is_sequence` DB trigger
  enforces that the target is a sequence; anything else bubbles up as a
  `Postgrex.Error`.

  Scoped to `parent_id` only — no other fields can sneak in because the
  `reparent_changeset` ignores everything else.
  """
  def update_node_parent(%FlowNode{} = node, parent_id) do
    Repo.transaction(fn ->
      with {:ok, %{flow: flow, node: locked_node}} <-
             ReferenceIntegrity.lock_active_node_for_write(node),
           {:ok, parent_id} <-
             ReferenceIntegrity.lock_node_parent(flow.id, parent_id, locked_node.id) do
        reparent_locked_node(locked_node, parent_id)
      else
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end

  defp reparent_locked_node(node, parent_id) do
    case node
         |> FlowNode.reparent_changeset(%{parent_id: parent_id})
         |> Repo.update() do
      {:ok, updated_node} -> updated_node
      {:error, changeset} -> Repo.rollback(changeset)
    end
  end

  @doc """
  Batch-updates positions for multiple nodes in a single transaction.
  Accepts a flow_id and a list of maps with :id, :position_x, :position_y.
  Returns {:ok, count} with the number of updated nodes.
  """
  @batch_node_positions_sql """
  UPDATE flow_nodes
  SET position_x = data.x, position_y = data.y, updated_at = $4
  FROM unnest($1::bigint[], $2::float8[], $3::float8[]) AS data(id, x, y)
  WHERE flow_nodes.id = data.id AND flow_nodes.flow_id = $5 AND flow_nodes.deleted_at IS NULL
  """

  def batch_update_positions(flow_id, positions) when is_list(positions) do
    now = TimeHelpers.now()

    Repo.transaction(fn ->
      with {:ok, %{flow: flow}} <-
             ReferenceIntegrity.lock_active_flow_for_write(flow_id),
           {:ok, {ids, xs, ys}} <- normalize_position_batch(positions),
           {:ok, _nodes} <- lock_position_nodes(flow.id, ids) do
        Repo.query!(@batch_node_positions_sql, [
          ids,
          xs,
          ys,
          now,
          flow.id
        ])

        length(ids)
      else
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end

  defp normalize_position_batch(positions) do
    positions
    |> Enum.reduce_while({:ok, {[], [], []}}, fn
      %{id: id, position_x: x, position_y: y}, {:ok, {ids, xs, ys}}
      when is_integer(id) and is_number(x) and is_number(y) ->
        {:cont, {:ok, {[id | ids], [x / 1 | xs], [y / 1 | ys]}}}

      invalid, _acc ->
        {:halt, {:error, {:invalid_node_position, invalid}}}
    end)
    |> case do
      {:ok, {ids, xs, ys}} ->
        ids = Enum.reverse(ids)

        if length(ids) == length(Enum.uniq(ids)) do
          {:ok, {ids, Enum.reverse(xs), Enum.reverse(ys)}}
        else
          {:error, :duplicate_node_positions}
        end

      {:error, _reason} = error ->
        error
    end
  end

  defp lock_position_nodes(_flow_id, []), do: {:ok, []}

  defp lock_position_nodes(flow_id, ids) do
    nodes =
      Repo.all(
        from(node in FlowNode,
          where:
            node.id in ^ids and node.flow_id == ^flow_id and
              is_nil(node.deleted_at),
          order_by: [asc: node.id],
          lock: "FOR UPDATE"
        )
      )

    if length(nodes) == length(ids),
      do: {:ok, nodes},
      else: {:error, :nodes_not_found}
  end

  def update_node_data(%FlowNode{} = node, data) do
    result =
      case Repo.transaction(fn -> update_node_data_transaction(node, data) end) do
        {:ok, {updated_node, meta}} -> {:ok, updated_node, meta}
        {:error, reason} -> {:error, reason}
      end

    maybe_broadcast_dashboard(result, node)
    result
  end

  defp maybe_broadcast_dashboard({:ok, _, _}, node) do
    broadcast_dashboard(node)
  end

  defp maybe_broadcast_dashboard({:ok, _}, node) do
    broadcast_dashboard(node)
  end

  defp maybe_broadcast_dashboard(_, _), do: :ok

  defp broadcast_dashboard(node) do
    project_id = Repo.one(from(f in Flow, where: f.id == ^node.flow_id, select: f.project_id))

    if project_id, do: Collaboration.broadcast_dashboard_change(project_id, :flows)
  end

  def change_node(%FlowNode{} = node, attrs \\ %{}) do
    FlowNode.update_changeset(node, attrs)
  end

  defp update_node_data_transaction(node, data) do
    with {:ok, %{project_id: project_id, flow: flow, node: locked_node}} <-
           ReferenceIntegrity.lock_active_node_for_write(node),
         {:ok, _parent_id} <-
           ReferenceIntegrity.lock_node_parent(
             flow.id,
             locked_node.parent_id,
             locked_node.id
           ),
         {:ok, normalized_data} <-
           ReferenceIntegrity.lock_and_normalize_node_references(
             project_id,
             flow.id,
             locked_node.type,
             data
           ),
         :ok <- validate_hub_id(locked_node, normalized_data) do
      {updated_node, connections_changed?} =
        persist_node_data(normalized_data, locked_node, project_id)

      renamed_count = maybe_cascade_hub_id_rename(locked_node, normalized_data)

      {updated_node,
       %{
         renamed_jumps: renamed_count,
         connections_changed?: connections_changed?
       }}
    else
      {:error, reason} -> Repo.rollback(reason)
    end
  end

  defp validate_hub_id(%FlowNode{type: "hub"} = node, data) do
    hub_id = data["hub_id"]

    cond do
      hub_id in [nil, ""] -> {:error, :hub_id_required}
      NodeCrud.hub_id_exists?(node.flow_id, hub_id, node.id) -> {:error, :hub_id_not_unique}
      true -> :ok
    end
  end

  defp validate_hub_id(_node, _data), do: :ok

  defp maybe_cascade_hub_id_rename(%FlowNode{type: "hub"} = node, data) do
    old_hub_id = node.data["hub_id"]
    new_hub_id = data["hub_id"]

    if old_hub_id == new_hub_id,
      do: 0,
      else: cascade_hub_id_rename(node.flow_id, old_hub_id, new_hub_id)
  end

  defp maybe_cascade_hub_id_rename(_node, _data), do: 0

  defp persist_node_data(data, node, project_id) do
    word_count = WordCount.for_node_data(node.type, data)

    case node
         |> FlowNode.data_changeset(%{data: data})
         |> Ecto.Changeset.put_change(:word_count, word_count)
         |> Repo.update() do
      {:ok, updated_node} ->
        connections_changed? =
          reconcile_outgoing_connection_pins(
            project_id,
            node,
            updated_node
          )

        {handle_persisted_node_data({:ok, updated_node}, project_id), connections_changed?}

      {:error, changeset} ->
        Repo.rollback(changeset)
    end
  end

  defp handle_persisted_node_data({:ok, updated_node}, project_id) do
    References.update_flow_node_entity_references(updated_node, project_id: project_id)
    References.update_flow_node_variable_references(updated_node)

    case Localization.extract_flow_node(updated_node) do
      :ok -> updated_node
      {:error, reason} -> Repo.rollback(reason)
    end
  end

  defp handle_persisted_node_data({:error, changeset}, _project_id), do: Repo.rollback(changeset)

  defp reconcile_outgoing_connection_pins(project_id, %FlowNode{} = previous_node, %FlowNode{} = updated_node) do
    connections = lock_outgoing_connections(updated_node.id)

    previous_pins =
      case ReferenceIntegrity.lock_effective_output_pins(
             project_id,
             previous_node
           ) do
        {:ok, pins} ->
          pins

        {:error, _reason} ->
          connections
          |> Enum.map(& &1.source_pin)
          |> Enum.uniq()
      end

    current_pins =
      case ReferenceIntegrity.lock_effective_output_pins(
             project_id,
             updated_node
           ) do
        {:ok, pins} -> pins
        {:error, reason} -> Repo.rollback(reason)
      end

    single_pin_migration =
      case {previous_pins, current_pins} do
        {[from_pin], [to_pin]} when from_pin != to_pin ->
          {from_pin, to_pin}

        _other ->
          nil
      end

    accepted_current_pins = accepted_current_pins(updated_node, current_pins)

    Enum.reduce(connections, false, fn connection, changed? ->
      reconcile_outgoing_connection(
        connection,
        accepted_current_pins,
        single_pin_migration
      ) or changed?
    end)
  end

  defp accepted_current_pins(%FlowNode{type: "dialogue", data: data}, current_pins) do
    Enum.uniq(current_pins ++ NodeConnectionRules.accepted_output_pins("dialogue", data || %{}))
  end

  defp accepted_current_pins(_node, current_pins), do: current_pins

  defp lock_outgoing_connections(node_id) do
    Repo.all(
      from(connection in FlowConnection,
        where: connection.source_node_id == ^node_id,
        order_by: [asc: connection.id],
        lock: "FOR UPDATE"
      )
    )
  end

  defp reconcile_outgoing_connection(
         %FlowConnection{source_pin: source_pin} = connection,
         current_pins,
         single_pin_migration
       ) do
    if source_pin in current_pins do
      false
    else
      reconcile_invalid_outgoing_connection(
        connection,
        single_pin_migration
      )
    end
  end

  defp reconcile_invalid_outgoing_connection(
         %FlowConnection{source_pin: source_pin} = connection,
         {source_pin, target_pin}
       ) do
    case connection
         |> FlowConnection.update_changeset(%{source_pin: target_pin})
         |> Repo.update() do
      {:ok, _updated_connection} -> true
      {:error, reason} -> Repo.rollback(reason)
    end
  end

  defp reconcile_invalid_outgoing_connection(connection, _single_pin_migration) do
    case Repo.delete(connection) do
      {:ok, _deleted_connection} -> true
      {:error, reason} -> Repo.rollback(reason)
    end
  end

  defp cascade_hub_id_rename(flow_id, old_hub_id, new_hub_id) when is_binary(old_hub_id) and old_hub_id != "" do
    now = TimeHelpers.now()

    query =
      from(n in FlowNode,
        where: n.flow_id == ^flow_id and n.type == "jump",
        where: fragment("?->>'target_hub_id' = ?", n.data, ^old_hub_id),
        update: [
          set: [
            data: fragment("jsonb_set(?, '{target_hub_id}', to_jsonb(?::text))", n.data, ^new_hub_id),
            updated_at: ^now
          ]
        ]
      )

    {count, _} = Repo.update_all(query, [])
    count
  end

  defp cascade_hub_id_rename(_, _, _), do: 0
end
