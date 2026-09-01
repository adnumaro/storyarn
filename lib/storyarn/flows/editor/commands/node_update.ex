defmodule Storyarn.Flows.NodeUpdate do
  @moduledoc false

  import Ecto.Query, warn: false

  alias Storyarn.Flows.Editor.Adapters.Postgres.NodePositionStore
  alias Storyarn.Flows.Flow
  alias Storyarn.Flows.FlowConnection
  alias Storyarn.Flows.FlowNode
  alias Storyarn.Flows.Localization
  alias Storyarn.Flows.NodeConnectionRules
  alias Storyarn.Flows.NodeCrud
  alias Storyarn.Flows.NodeEditor
  alias Storyarn.Flows.References
  alias Storyarn.Platform.Collaboration
  alias Storyarn.Platform.Shared.TimeHelpers
  alias Storyarn.Repo

  # This is a write-path certification, not a hash of the derivative rows.
  # Increment it whenever the canonical derivative contract changes. A nil or
  # mismatched value forces FlowSync through the full reconciliation path.
  @derivatives_fingerprint_version 1
  @data_source_locked_event [:storyarn, :flows, :node_update, :source_locked]

  def update_node(%FlowNode{} = node, attrs) do
    result = update_node_without_dashboard_broadcast(node, attrs)

    maybe_broadcast_dashboard(result, node)
    result
  end

  @doc false
  def update_node_without_dashboard_broadcast(%FlowNode{} = node, attrs) do
    Repo.transaction(fn -> update_node_transaction(node, attrs) end)
  end

  defp update_node_transaction(node, attrs) do
    with {:ok, %{project_id: project_id, flow: flow, node: locked_node}} <-
           References.lock_active_node_for_write(node, :key_share),
         changeset = FlowNode.update_changeset(locked_node, attrs),
         type = Ecto.Changeset.get_field(changeset, :type),
         data = Ecto.Changeset.get_field(changeset, :data) || %{},
         parent_id = Ecto.Changeset.get_field(changeset, :parent_id),
         :ok <- validate_node_type_transition(locked_node, type),
         {:ok, parent_id} <-
           References.lock_node_parent(flow.id, parent_id, locked_node.id),
         {:ok, data} <-
           References.lock_and_normalize_node_references(
             project_id,
             flow.id,
             type,
             data
           ),
         :ok <- validate_hub_id(locked_node, type, data) do
      updated_node =
        changeset
        |> Ecto.Changeset.put_change(:parent_id, parent_id)
        |> Ecto.Changeset.put_change(:data, data)
        |> Ecto.Changeset.put_change(
          :word_count,
          Localization.node_word_count(type, data)
        )
        |> Ecto.Changeset.put_change(
          :derivatives_fingerprint,
          derivatives_fingerprint(type, data)
        )
        |> Repo.update()
        |> handle_persisted_node_data(project_id)

      _renamed_count =
        maybe_cascade_hub_id_rename(
          locked_node,
          type,
          data,
          project_id
        )

      _connections_changed? =
        Enum.any?([
          reconcile_outgoing_connection_pins(project_id, locked_node, updated_node),
          reconcile_incoming_connection_pins(updated_node)
        ])

      updated_node
    else
      {:error, reason} -> Repo.rollback(reason)
    end
  end

  defp validate_node_type_transition(%FlowNode{type: type}, type), do: :ok

  defp validate_node_type_transition(%FlowNode{type: "entry"}, _new_type), do: {:error, :cannot_change_entry_node}

  defp validate_node_type_transition(%FlowNode{type: old_type}, new_type)
       when old_type == "sequence" or new_type == "sequence", do: {:error, :cannot_change_sequence_type}

  defp validate_node_type_transition(%FlowNode{} = node, "entry") do
    if active_node_of_type_exists?(node.flow_id, "entry", node.id),
      do: {:error, :entry_node_exists},
      else: :ok
  end

  defp validate_node_type_transition(%FlowNode{type: "exit"} = node, _new_type) do
    if active_node_of_type_exists?(node.flow_id, "exit", node.id),
      do: :ok,
      else: {:error, :cannot_change_last_exit}
  end

  defp validate_node_type_transition(%FlowNode{}, _new_type), do: :ok

  defp active_node_of_type_exists?(flow_id, type, excluded_id) do
    Repo.exists?(
      from(other in FlowNode,
        where:
          other.flow_id == ^flow_id and other.id != ^excluded_id and
            other.type == ^type and is_nil(other.deleted_at)
      )
    )
  end

  def update_node_position(%FlowNode{} = node, attrs) do
    Repo.transaction(fn ->
      with {:ok, %{node: locked_node}} <-
             References.lock_active_node_for_write(node, :key_share),
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
             References.lock_active_node_for_write(node, :key_share),
           {:ok, parent_id} <-
             References.lock_node_parent(flow.id, parent_id, locked_node.id) do
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
  def batch_update_positions(flow_id, positions) when is_list(positions) do
    now = TimeHelpers.now()

    Repo.transaction(fn ->
      with {:ok, %{flow: flow}} <-
             References.lock_active_flow_for_write(flow_id, :key_share),
           {:ok, {ids, xs, ys}} <- normalize_position_batch(positions),
           {:ok, _nodes} <- lock_position_nodes(flow.id, ids) do
        NodePositionStore.update!(ids, xs, ys, now, flow.id)

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
    result = update_node_data_without_dashboard_broadcast(node, data)

    maybe_broadcast_dashboard(result, node)
    result
  end

  @doc """
  Applies a closed authoring operation to the latest locked node state.

  Unlike the legacy read-transform-write adapter, the transition is derived
  only after the node row has been locked. Concurrent edits to different
  fields therefore compose instead of overwriting one another with stale JSON.
  """
  @spec edit_node(pos_integer(), pos_integer(), NodeEditor.operation(), map()) ::
          {:ok,
           %{
             node: FlowNode.t(),
             previous_data: map(),
             current_data: map(),
             changed?: boolean(),
             graph_changed?: boolean(),
             renamed_jumps: non_neg_integer(),
             connections_changed?: boolean()
           }}
          | {:error, term()}
  def edit_node(flow_id, node_id, operation, payload)
      when is_integer(flow_id) and flow_id > 0 and is_integer(node_id) and node_id > 0 and is_atom(operation) and
             is_map(payload) do
    identity = %FlowNode{id: node_id, flow_id: flow_id}

    case Repo.transaction(fn -> edit_node_transaction(identity, operation, payload) end) do
      {:ok, %{changed?: true, node: node} = result} ->
        broadcast_dashboard(node)
        {:ok, result}

      {:ok, result} ->
        {:ok, result}

      {:error, reason} ->
        {:error, reason}
    end
  end

  def edit_node(flow_id, node_id, operation, payload)
      when is_integer(flow_id) and flow_id > 0 and is_binary(node_id) and is_atom(operation) and is_map(payload) do
    case Integer.parse(node_id) do
      {parsed_node_id, ""} when parsed_node_id > 0 ->
        edit_node(flow_id, parsed_node_id, operation, payload)

      _invalid ->
        {:error, :node_not_found}
    end
  end

  def edit_node(_flow_id, _node_id, _operation, _payload), do: {:error, :node_not_found}

  @doc false
  def update_node_data_without_dashboard_broadcast(%FlowNode{} = node, data) do
    case Repo.transaction(fn -> update_node_data_transaction(node, data) end) do
      {:ok, {updated_node, meta}} -> {:ok, updated_node, meta}
      {:error, reason} -> {:error, reason}
    end
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

  @doc false
  def reconcile_persisted_node(%FlowNode{} = node, project_id) do
    node
    |> then(&handle_persisted_node_data({:ok, &1}, project_id))
    |> persist_derivatives_fingerprint()
  end

  @doc false
  @spec data_and_derivatives_current?(FlowNode.t(), map(), integer()) :: boolean()
  def data_and_derivatives_current?(%FlowNode{} = node, desired_data, project_id)
      when is_map(desired_data) and is_integer(project_id) do
    node.id in data_and_derivatives_current_ids([{node, desired_data}], project_id)
  end

  @doc false
  @spec data_and_derivatives_current_ids([{FlowNode.t(), map()}], integer()) ::
          MapSet.t(integer())
  def data_and_derivatives_current_ids(node_data_pairs, project_id)
      when is_list(node_data_pairs) and is_integer(project_id) do
    candidate_pairs =
      node_data_pairs
      |> Enum.group_by(fn {node, _desired_data} -> node.id end)
      |> Enum.reduce([], fn
        {_node_id, [{%FlowNode{} = node, desired_data}]}, candidates
        when is_map(desired_data) ->
          case node_data_candidate(node, desired_data) do
            {:ok, normalized_input} -> [{node, normalized_input} | candidates]
            :not_current -> candidates
          end

        {_node_id, _ambiguous_or_invalid_pairs}, candidates ->
          candidates
      end)

    normalized_by_node_id = normalize_candidate_references(candidate_pairs, project_id)
    hub_owners = lock_batch_hub_owners(candidate_pairs)

    candidates =
      candidate_pairs
      |> Enum.reduce([], fn {%FlowNode{type: type} = node, _normalized_input}, current ->
        with {:ok, normalized_data} <- Map.fetch(normalized_by_node_id, node.id),
             true <- normalized_data == node.data,
             :ok <- validate_batch_hub_id(node, type, normalized_data, hub_owners) do
          [node | current]
        else
          _not_current_or_invalid -> current
        end
      end)
      |> keep_active_project_nodes(project_id)

    localized_text_ids = Localization.flow_node_texts_current_ids(candidates, project_id)
    entity_reference_ids = References.entity_references_current_ids(candidates)

    variable_reference_ids =
      References.flow_node_references_current_ids(
        candidates,
        project_id
      )

    localized_text_ids
    |> MapSet.intersection(entity_reference_ids)
    |> MapSet.intersection(variable_reference_ids)
  end

  defp keep_active_project_nodes([], _project_id), do: []

  defp keep_active_project_nodes(nodes, project_id) do
    node_ids = Enum.map(nodes, & &1.id)

    flow_ids_by_node =
      from(node in FlowNode,
        join: flow in Flow,
        on: flow.id == node.flow_id,
        where:
          node.id in ^node_ids and
            flow.project_id == ^project_id and
            is_nil(node.deleted_at) and
            is_nil(flow.deleted_at),
        select: {node.id, node.flow_id}
      )
      |> Repo.all()
      |> Map.new()

    Enum.filter(nodes, fn node ->
      Map.get(flow_ids_by_node, node.id) == node.flow_id
    end)
  end

  defp node_data_candidate(%FlowNode{} = node, desired_data) do
    changeset = FlowNode.data_changeset(node, %{data: desired_data})
    normalized_input = Ecto.Changeset.get_field(changeset, :data)

    if changeset.valid? and
         node.derivatives_fingerprint == derivatives_fingerprint(node) and
         node.word_count == Localization.node_word_count(node.type, node.data) do
      {:ok, normalized_input}
    else
      :not_current
    end
  end

  defp normalize_candidate_references([], _project_id), do: %{}

  defp normalize_candidate_references(candidate_pairs, project_id) do
    reference_candidates =
      Enum.map(candidate_pairs, fn {node, normalized_input} ->
        {node.id, node.flow_id, node.type, normalized_input}
      end)

    case References.lock_and_normalize_node_reference_batch(
           project_id,
           reference_candidates
         ) do
      {:ok, normalized_by_node_id} -> normalized_by_node_id
      {:error, _reason} -> %{}
    end
  end

  defp lock_batch_hub_owners(candidate_pairs) do
    hub_candidates =
      Enum.flat_map(candidate_pairs, fn
        {%FlowNode{flow_id: flow_id, type: "hub"}, %{"hub_id" => hub_id}}
        when is_binary(hub_id) ->
          if String.trim(hub_id) == "", do: [], else: [{flow_id, hub_id}]

        _candidate ->
          []
      end)

    flow_ids =
      hub_candidates
      |> Enum.map(&elem(&1, 0))
      |> Enum.uniq()
      |> Enum.sort()

    hub_ids =
      hub_candidates
      |> Enum.map(&elem(&1, 1))
      |> Enum.uniq()
      |> Enum.sort()

    if hub_candidates == [] do
      %{}
    else
      from(node in FlowNode,
        where:
          node.flow_id in ^flow_ids and node.type == "hub" and
            is_nil(node.deleted_at) and
            fragment("?->>'hub_id'", node.data) in ^hub_ids,
        order_by: [asc: node.id],
        select: {node.flow_id, fragment("?->>'hub_id'", node.data), node.id}
      )
      |> Repo.all()
      |> Enum.group_by(
        fn {flow_id, hub_id, _node_id} -> {flow_id, hub_id} end,
        fn {_flow_id, _hub_id, node_id} -> node_id end
      )
    end
  end

  defp validate_batch_hub_id(%FlowNode{} = node, "hub", data, hub_owners) do
    hub_id = data["hub_id"]

    cond do
      not is_binary(hub_id) or String.trim(hub_id) == "" ->
        {:error, :hub_id_required}

      Enum.any?(Map.get(hub_owners, {node.flow_id, hub_id}, []), &(&1 != node.id)) ->
        {:error, :hub_id_not_unique}

      true ->
        :ok
    end
  end

  defp validate_batch_hub_id(_node, _type, _data, _hub_owners), do: :ok

  defp update_node_data_transaction(node, data) do
    with {:ok, %{project_id: project_id, flow: flow, node: locked_node}} <-
           References.lock_active_node_for_write(node, :key_share),
         :ok <- emit_data_source_locked(locked_node, project_id),
         {:ok, _parent_id} <-
           References.lock_node_parent(
             flow.id,
             locked_node.parent_id,
             locked_node.id
           ),
         {:ok, normalized_data} <-
           References.lock_and_normalize_node_references(
             project_id,
             flow.id,
             locked_node.type,
             data
           ),
         :ok <- validate_hub_id(locked_node, locked_node.type, normalized_data) do
      {updated_node, connections_changed?} =
        persist_node_data(normalized_data, locked_node, project_id)

      renamed_count =
        maybe_cascade_hub_id_rename(
          locked_node,
          locked_node.type,
          normalized_data,
          project_id
        )

      {updated_node,
       %{
         renamed_jumps: renamed_count,
         connections_changed?: connections_changed?
       }}
    else
      {:error, reason} -> Repo.rollback(reason)
    end
  end

  defp emit_data_source_locked(node, project_id) do
    :telemetry.execute(@data_source_locked_event, %{count: 1}, %{
      node_id: node.id,
      flow_id: node.flow_id,
      project_id: project_id
    })

    :ok
  end

  defp edit_node_transaction(identity, operation, payload) do
    with {:ok, %{project_id: project_id, flow: flow, node: locked_node}} <-
           References.lock_active_node_for_write(identity, :key_share),
         {:ok, authored_data} <-
           NodeEditor.apply_operation(locked_node, flow, project_id, operation, payload),
         {:ok, _parent_id} <-
           References.lock_node_parent(
             flow.id,
             locked_node.parent_id,
             locked_node.id
           ),
         {:ok, normalized_data} <-
           References.lock_and_normalize_node_references(
             project_id,
             flow.id,
             locked_node.type,
             authored_data
           ),
         :ok <- validate_hub_id(locked_node, locked_node.type, normalized_data) do
      persist_authored_node_data(locked_node, normalized_data, project_id)
    else
      {:error, reason} -> Repo.rollback(reason)
    end
  end

  defp persist_authored_node_data(%FlowNode{data: data} = node, data, _project_id) do
    edit_result(node, node, data, false, 0, false)
  end

  defp persist_authored_node_data(%FlowNode{} = locked_node, normalized_data, project_id) do
    {updated_node, connections_changed?} =
      persist_node_data(normalized_data, locked_node, project_id)

    renamed_count =
      maybe_cascade_hub_id_rename(
        locked_node,
        locked_node.type,
        normalized_data,
        project_id
      )

    edit_result(
      locked_node,
      updated_node,
      normalized_data,
      true,
      renamed_count,
      connections_changed?
    )
  end

  defp edit_result(previous_node, current_node, current_data, changed?, renamed_jumps, connections_changed?) do
    %{
      node: current_node,
      previous_data: previous_node.data || %{},
      current_data: current_data,
      changed?: changed?,
      graph_changed?: renamed_jumps > 0 or connections_changed?,
      renamed_jumps: renamed_jumps,
      connections_changed?: connections_changed?
    }
  end

  defp validate_hub_id(%FlowNode{} = node, "hub", data) do
    hub_id = data["hub_id"]

    cond do
      not is_binary(hub_id) or String.trim(hub_id) == "" -> {:error, :hub_id_required}
      NodeCrud.hub_id_exists?(node.flow_id, hub_id, node.id) -> {:error, :hub_id_not_unique}
      true -> :ok
    end
  end

  defp validate_hub_id(_node, _type, _data), do: :ok

  defp maybe_cascade_hub_id_rename(%FlowNode{type: "hub"} = node, updated_type, data, project_id) do
    old_hub_id = node.data["hub_id"]
    new_hub_id = if updated_type == "hub", do: data["hub_id"], else: ""

    if old_hub_id == new_hub_id,
      do: 0,
      else:
        cascade_hub_id_rename(
          project_id,
          node.flow_id,
          old_hub_id,
          new_hub_id
        )
  end

  defp maybe_cascade_hub_id_rename(_node, _type, _data, _project_id), do: 0

  defp persist_node_data(data, node, project_id) do
    word_count = Localization.node_word_count(node.type, data)

    case node
         |> FlowNode.data_changeset(%{data: data})
         |> Ecto.Changeset.put_change(:word_count, word_count)
         |> Ecto.Changeset.put_change(
           :derivatives_fingerprint,
           derivatives_fingerprint(node.type, data)
         )
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
    with :ok <-
           normalize_reference_write_result(
             References.update_entity_references(
               updated_node,
               project_id: project_id
             )
           ),
         :ok <-
           normalize_reference_write_result(References.update_variable_references(updated_node)),
         :ok <- Localization.extract_flow_node(updated_node) do
      updated_node
    else
      {:error, reason} -> Repo.rollback(reason)
    end
  end

  defp handle_persisted_node_data({:error, changeset}, _project_id), do: Repo.rollback(changeset)

  defp normalize_reference_write_result(:ok), do: :ok
  defp normalize_reference_write_result({:error, reason}), do: {:error, reason}

  defp normalize_reference_write_result(result) do
    {:error, {:unexpected_reference_write_result, result}}
  end

  defp persist_derivatives_fingerprint(%FlowNode{} = node) do
    fingerprint = derivatives_fingerprint(node)

    if node.derivatives_fingerprint == fingerprint do
      node
    else
      case node
           |> Ecto.Changeset.change(derivatives_fingerprint: fingerprint)
           |> Repo.update() do
        {:ok, updated_node} -> updated_node
        {:error, changeset} -> Repo.rollback(changeset)
      end
    end
  end

  defp derivatives_fingerprint(%FlowNode{} = node) do
    derivatives_fingerprint(node.type, node.data)
  end

  @doc false
  def derivatives_fingerprint(type, data) do
    {@derivatives_fingerprint_version, type, data}
    |> :erlang.term_to_binary([:deterministic])
    |> then(&:crypto.hash(:sha256, &1))
    |> Base.encode16(case: :lower)
  end

  defp reconcile_outgoing_connection_pins(project_id, %FlowNode{} = previous_node, %FlowNode{} = updated_node) do
    connections = lock_outgoing_connections(updated_node.id)

    previous_pins =
      case References.lock_effective_output_pins(
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
      case References.lock_effective_output_pins(
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

  defp reconcile_incoming_connection_pins(%FlowNode{} = updated_node) do
    updated_node.id
    |> lock_incoming_connections()
    |> Enum.reduce(false, &reconcile_incoming_connection(&1, updated_node.type, &2))
  end

  defp reconcile_incoming_connection(connection, node_type, changed?) do
    if NodeConnectionRules.valid_input_pin?(node_type, connection.target_pin),
      do: changed?,
      else: delete_invalid_incoming_connection(connection)
  end

  defp delete_invalid_incoming_connection(connection) do
    case Repo.delete(connection) do
      {:ok, _deleted_connection} -> true
      {:error, reason} -> Repo.rollback(reason)
    end
  end

  defp lock_incoming_connections(node_id) do
    Repo.all(
      from(connection in FlowConnection,
        where: connection.target_node_id == ^node_id,
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

  defp cascade_hub_id_rename(project_id, flow_id, old_hub_id, new_hub_id)
       when is_binary(old_hub_id) and old_hub_id != "" do
    active_jumps =
      Repo.all(
        from(n in FlowNode,
          where: n.flow_id == ^flow_id and n.type == "jump",
          where: is_nil(n.deleted_at),
          where: fragment("?->>'target_hub_id' = ?", n.data, ^old_hub_id),
          order_by: [asc: n.id],
          lock: "FOR UPDATE"
        )
      )

    Enum.each(active_jumps, fn jump ->
      updated_data = Map.put(jump.data, "target_hub_id", new_hub_id)
      {_updated_jump, _connections_changed?} = persist_node_data(updated_data, jump, project_id)
    end)

    cascade_deleted_hub_id_rename(flow_id, old_hub_id, new_hub_id)

    length(active_jumps)
  end

  defp cascade_hub_id_rename(_, _, _, _), do: 0

  defp cascade_deleted_hub_id_rename(flow_id, old_hub_id, new_hub_id) do
    now = TimeHelpers.now()

    Repo.update_all(
      from(n in FlowNode,
        where: n.flow_id == ^flow_id and n.type == "jump",
        where: not is_nil(n.deleted_at),
        where: fragment("?->>'target_hub_id' = ?", n.data, ^old_hub_id),
        update: [
          set: [
            data:
              fragment(
                "jsonb_set(?, '{target_hub_id}', to_jsonb(?::text))",
                n.data,
                ^new_hub_id
              ),
            derivatives_fingerprint: nil,
            updated_at: ^now
          ]
        ]
      ),
      []
    )
  end
end
