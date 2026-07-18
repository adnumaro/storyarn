defmodule Storyarn.Flows.NodeUpdate do
  @moduledoc false

  import Ecto.Query, warn: false

  alias Storyarn.Collaboration
  alias Storyarn.Flows.Flow
  alias Storyarn.Flows.FlowNode
  alias Storyarn.Flows.NodeCrud
  alias Storyarn.Localization
  alias Storyarn.References
  alias Storyarn.References.AvatarIntegrity
  alias Storyarn.Repo
  alias Storyarn.Shared.TimeHelpers
  alias Storyarn.Shared.WordCount

  def update_node(%FlowNode{} = node, attrs) do
    result = Repo.transaction(fn -> update_node_transaction(node, attrs) end)

    maybe_broadcast_dashboard(result, node)
    result
  end

  defp update_node_transaction(node, attrs) do
    changeset = FlowNode.update_changeset(node, attrs)
    type = Ecto.Changeset.get_field(changeset, :type)
    data = Ecto.Changeset.get_field(changeset, :data)

    case AvatarIntegrity.lock_and_normalize_node_avatar(
           node.flow_id,
           type,
           data || %{}
         ) do
      {:ok, data} ->
        changeset
        |> Ecto.Changeset.put_change(:data, data)
        |> Ecto.Changeset.put_change(:word_count, WordCount.for_node_data(type, data))
        |> Repo.update()
        |> extract_updated_node_or_rollback()

      {:error, reason} ->
        Repo.rollback(reason)
    end
  end

  defp extract_updated_node_or_rollback({:ok, updated_node}) do
    case Localization.extract_flow_node(updated_node) do
      :ok -> updated_node
      {:error, reason} -> Repo.rollback(reason)
    end
  end

  defp extract_updated_node_or_rollback({:error, changeset}), do: Repo.rollback(changeset)

  def update_node_position(%FlowNode{} = node, attrs) do
    node
    |> FlowNode.position_changeset(attrs)
    |> Repo.update()
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
    node
    |> FlowNode.reparent_changeset(%{parent_id: parent_id})
    |> Repo.update()
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
      {ids, xs, ys} =
        Enum.reduce(positions, {[], [], []}, fn %{id: id, position_x: x, position_y: y}, {ids, xs, ys} ->
          {[id | ids], [x / 1 | xs], [y / 1 | ys]}
        end)

      Repo.query!(@batch_node_positions_sql, [
        Enum.reverse(ids),
        Enum.reverse(xs),
        Enum.reverse(ys),
        now,
        flow_id
      ])

      length(positions)
    end)
  end

  def update_node_data(%FlowNode{type: "hub"} = node, data) do
    result = update_hub_node_data(node, data)
    maybe_broadcast_dashboard(result, node)
    result
  end

  def update_node_data(%FlowNode{} = node, data) do
    result =
      case do_update_node_data(node, data) do
        {:ok, updated_node} -> {:ok, updated_node, %{renamed_jumps: 0}}
        error -> error
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

  defp update_hub_node_data(node, data) do
    hub_id = data["hub_id"]

    if hub_id == nil || hub_id == "" do
      {:error, :hub_id_required}
    else
      update_hub_in_transaction(node, data, hub_id)
    end
  end

  defp update_hub_in_transaction(node, data, hub_id) do
    fn ->
      Repo.one!(from(f in Flow, where: f.id == ^node.flow_id, lock: "FOR UPDATE"))

      if NodeCrud.hub_id_exists?(node.flow_id, hub_id, node.id) do
        Repo.rollback(:hub_id_not_unique)
      else
        apply_hub_update_or_rollback(node, data, hub_id)
      end
    end
    |> Repo.transaction()
    |> case do
      {:ok, {updated_node, meta}} -> {:ok, updated_node, meta}
      {:error, reason} -> {:error, reason}
    end
  end

  defp apply_hub_update_or_rollback(node, data, hub_id) do
    case do_update_hub_data(node, data, hub_id) do
      {:ok, updated_node, meta} -> {updated_node, meta}
      {:error, reason} -> Repo.rollback(reason)
    end
  end

  defp do_update_hub_data(node, data, hub_id) do
    old_hub_id = node.data["hub_id"]

    case do_update_node_data(node, data) do
      {:ok, updated_node} ->
        renamed_count =
          if old_hub_id == hub_id,
            do: 0,
            else: cascade_hub_id_rename(node.flow_id, old_hub_id, hub_id)

        {:ok, updated_node, %{renamed_jumps: renamed_count}}

      error ->
        error
    end
  end

  defp do_update_node_data(node, data) do
    Repo.transaction(fn ->
      node
      |> normalize_node_avatar_or_rollback(data)
      |> persist_node_data(node)
    end)
  end

  defp normalize_node_avatar_or_rollback(node, data) do
    case AvatarIntegrity.lock_and_normalize_node_avatar(node.flow_id, node.type, data) do
      {:ok, normalized_data} -> normalized_data
      {:error, reason} -> Repo.rollback(reason)
    end
  end

  defp persist_node_data(data, node) do
    word_count = WordCount.for_node_data(node.type, data)

    node
    |> FlowNode.data_changeset(%{data: data})
    |> Ecto.Changeset.put_change(:word_count, word_count)
    |> Repo.update()
    |> handle_persisted_node_data()
  end

  defp handle_persisted_node_data({:ok, updated_node}) do
    References.update_flow_node_entity_references(updated_node)
    References.update_flow_node_variable_references(updated_node)
    Localization.extract_flow_node(updated_node)
    updated_node
  end

  defp handle_persisted_node_data({:error, changeset}), do: Repo.rollback(changeset)

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
