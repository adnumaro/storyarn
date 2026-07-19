defmodule Storyarn.Flows.NodeDelete do
  @moduledoc false

  import Ecto.Query, warn: false

  alias Storyarn.Collaboration
  alias Storyarn.Flows.FlowNode
  alias Storyarn.Flows.NodeCrud
  alias Storyarn.Flows.ReferenceIntegrity
  alias Storyarn.Localization
  alias Storyarn.References
  alias Storyarn.Repo

  def delete_node(%FlowNode{} = node_hint) do
    node_hint
    |> do_delete_node()
    |> maybe_broadcast_delete()
  end

  @doc """
  Restores a soft-deleted node by clearing its deleted_at timestamp.
  Returns {:ok, :already_active} if the node is not deleted (idempotent for redo safety).
  """
  def restore_node(flow_id, node_id) when is_integer(flow_id) and is_integer(node_id) do
    fn ->
      with {:ok, %{project_id: project_id}} <-
             ReferenceIntegrity.lock_active_flow_for_write(flow_id),
           %FlowNode{} = node <- lock_node_in_flow(node_id, flow_id) do
        restore_locked_node(node, project_id)
      else
        nil -> Repo.rollback(:not_found)
        {:error, reason} -> Repo.rollback(reason)
      end
    end
    |> Repo.transaction()
    |> unwrap_restore_result()
  end

  def restore_node(_flow_id, _node_id), do: {:error, :not_found}

  defp restore_locked_node(%FlowNode{deleted_at: nil}, project_id), do: {:already_active, project_id}

  defp restore_locked_node(%FlowNode{} = node, project_id) do
    changeset =
      FlowNode.update_changeset(node, %{
        type: node.type,
        data: node.data,
        parent_id: node.parent_id
      })

    type = Ecto.Changeset.get_field(changeset, :type)
    data = Ecto.Changeset.get_field(changeset, :data) || %{}
    parent_id = Ecto.Changeset.get_field(changeset, :parent_id)

    with :ok <- validate_restore_changeset(changeset),
         {:ok, parent_id} <-
           ReferenceIntegrity.lock_node_parent(node.flow_id, parent_id, node.id),
         {:ok, data} <-
           ReferenceIntegrity.lock_and_normalize_node_references(
             project_id,
             node.flow_id,
             type,
             data
           ),
         :ok <- validate_restored_node_identity(node, type, data),
         {:ok, restored_node} <-
           changeset
           |> Ecto.Changeset.put_change(:parent_id, parent_id)
           |> Ecto.Changeset.put_change(:data, data)
           |> Ecto.Changeset.put_change(:deleted_at, nil)
           |> Repo.update(),
         :ok <- rebuild_references(restored_node, project_id),
         :ok <- Localization.extract_flow_node(restored_node) do
      {:restored, restored_node, project_id}
    else
      {:error, reason} -> Repo.rollback(reason)
    end
  end

  defp validate_restore_changeset(%Ecto.Changeset{valid?: true}), do: :ok
  defp validate_restore_changeset(%Ecto.Changeset{} = changeset), do: {:error, changeset}

  defp validate_restored_node_identity(node, "hub", data) do
    hub_id = data["hub_id"]

    cond do
      not is_binary(hub_id) or String.trim(hub_id) == "" ->
        {:error, :hub_id_required}

      NodeCrud.hub_id_exists?(node.flow_id, hub_id, node.id) ->
        {:error, :hub_id_not_unique}

      true ->
        :ok
    end
  end

  defp validate_restored_node_identity(node, "entry", _data) do
    if Repo.exists?(
         from(other in FlowNode,
           where:
             other.flow_id == ^node.flow_id and other.id != ^node.id and
               other.type == "entry" and is_nil(other.deleted_at)
         )
       ) do
      {:error, :entry_node_exists}
    else
      :ok
    end
  end

  defp validate_restored_node_identity(_node, _type, _data), do: :ok

  defp rebuild_references(node, project_id) do
    with :ok <-
           normalize_reference_rebuild_result(
             References.update_flow_node_entity_references(
               node,
               project_id: project_id
             )
           ) do
      normalize_reference_rebuild_result(References.update_flow_node_variable_references(node))
    end
  end

  defp normalize_reference_rebuild_result(:ok), do: :ok
  defp normalize_reference_rebuild_result({:error, _reason} = error), do: error

  defp normalize_reference_rebuild_result(result), do: {:error, {:unexpected_reference_rebuild_result, result}}

  defp validate_deletable_node(%FlowNode{type: "entry"}), do: {:error, :cannot_delete_entry_node}

  defp validate_deletable_node(%FlowNode{type: "exit"} = node) do
    from(n in FlowNode, where: n.flow_id == ^node.flow_id and n.type == "exit" and is_nil(n.deleted_at))
    |> Repo.aggregate(
      :count,
      :id
    )
    |> case do
      count when count <= 1 -> {:error, :cannot_delete_last_exit}
      _count -> :ok
    end
  end

  defp validate_deletable_node(%FlowNode{}), do: :ok

  defp do_delete_node(node_hint) do
    fn ->
      with {:ok, %{node: node, project_id: project_id}} <-
             ReferenceIntegrity.lock_active_node_for_write(node_hint),
           :ok <- validate_deletable_node(node) do
        orphaned_count = maybe_clear_orphaned_jumps(node)

        References.delete_flow_node_entity_references(node.id)
        References.delete_flow_node_variable_references(node.id)
        Localization.delete_flow_node_texts(node.id)

        soft_delete_locked_node(node, orphaned_count, project_id)
      else
        {:error, reason} -> Repo.rollback(reason)
      end
    end
    |> Repo.transaction()
    |> unwrap_delete_result()
  end

  defp soft_delete_locked_node(node, orphaned_count, project_id) do
    case node |> FlowNode.soft_delete_changeset() |> Repo.update() do
      {:ok, deleted_node} ->
        {deleted_node, %{orphaned_jumps: orphaned_count}, project_id}

      {:error, changeset} ->
        Repo.rollback(changeset)
    end
  end

  defp maybe_clear_orphaned_jumps(%{type: "hub"} = node) do
    clear_orphaned_jumps(node.flow_id, node.data["hub_id"])
  end

  defp maybe_clear_orphaned_jumps(_node), do: 0

  defp lock_node_in_flow(node_id, flow_id) do
    Repo.one(
      from(node in FlowNode,
        where: node.id == ^node_id and node.flow_id == ^flow_id,
        lock: "FOR UPDATE"
      )
    )
  end

  defp unwrap_delete_result({:ok, {deleted_node, meta, project_id}}), do: {:ok, deleted_node, meta, project_id}

  defp unwrap_delete_result({:error, reason}), do: {:error, reason}

  defp maybe_broadcast_delete({:ok, deleted_node, meta, project_id}) do
    Collaboration.broadcast_dashboard_change(project_id, :flows)
    {:ok, deleted_node, meta}
  end

  defp maybe_broadcast_delete({:error, _reason} = error), do: error

  defp unwrap_restore_result({:ok, {:already_active, _project_id}}), do: {:ok, :already_active}

  defp unwrap_restore_result({:ok, {:restored, restored_node, project_id}}) do
    Collaboration.broadcast_dashboard_change(project_id, :flows)
    {:ok, restored_node}
  end

  defp unwrap_restore_result({:error, reason}), do: {:error, reason}

  defp clear_orphaned_jumps(flow_id, hub_id) when is_binary(hub_id) and hub_id != "" do
    now = Storyarn.Shared.TimeHelpers.now()

    query =
      from(n in FlowNode,
        where: n.flow_id == ^flow_id and n.type == "jump",
        where: fragment("?->>'target_hub_id' = ?", n.data, ^hub_id),
        update: [
          set: [
            data: fragment("jsonb_set(?, '{target_hub_id}', '\"\"'::jsonb)", n.data),
            updated_at: ^now
          ]
        ]
      )

    {count, _} = Repo.update_all(query, [])

    count
  end

  defp clear_orphaned_jumps(_flow_id, _hub_id), do: 0
end
