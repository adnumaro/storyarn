defmodule Storyarn.Flows.NodeDelete do
  @moduledoc false

  import Ecto.Query, warn: false

  alias Storyarn.Collaboration
  alias Storyarn.Flows.Flow
  alias Storyarn.Flows.FlowNode
  alias Storyarn.Localization
  alias Storyarn.References
  alias Storyarn.Repo

  def delete_node(%FlowNode{type: "entry"}), do: {:error, :cannot_delete_entry_node}

  def delete_node(%FlowNode{type: "exit"} = node) do
    if last_exit_node?(node),
      do: {:error, :cannot_delete_last_exit},
      else: do_delete_and_broadcast(node)
  end

  def delete_node(%FlowNode{} = node), do: do_delete_and_broadcast(node)

  defp do_delete_and_broadcast(node) do
    result = do_delete_node(node)

    case result do
      {:ok, _, _} ->
        project_id = Repo.one(from(f in Flow, where: f.id == ^node.flow_id, select: f.project_id))

        if project_id do
          Collaboration.broadcast_dashboard_change(project_id, :flows)
        end

      _ ->
        :ok
    end

    result
  end

  @doc """
  Restores a soft-deleted node by clearing its deleted_at timestamp.
  Returns {:ok, :already_active} if the node is not deleted (idempotent for redo safety).
  """
  def restore_node(flow_id, node_id) do
    case Repo.get(FlowNode, node_id) do
      %FlowNode{flow_id: ^flow_id, deleted_at: deleted_at} = node when not is_nil(deleted_at) ->
        restore_deleted_node(node, flow_id)

      %FlowNode{flow_id: ^flow_id, deleted_at: nil} ->
        {:ok, :already_active}

      _ ->
        {:error, :not_found}
    end
  end

  defp restore_deleted_node(node, flow_id) do
    result = Repo.transaction(fn -> restore_node_transaction(node) end)
    maybe_broadcast_restore(result, flow_id)
    result
  end

  defp restore_node_transaction(node) do
    with {:ok, restored_node} <- node |> FlowNode.restore_changeset() |> Repo.update(),
         :ok <- Localization.extract_flow_node(restored_node) do
      restored_node
    else
      {:error, reason} -> Repo.rollback(reason)
    end
  end

  defp maybe_broadcast_restore({:ok, _restored_node}, flow_id) do
    project_id = Repo.one(from(f in Flow, where: f.id == ^flow_id, select: f.project_id))
    if project_id, do: Collaboration.broadcast_dashboard_change(project_id, :flows)
  end

  defp maybe_broadcast_restore(_result, _flow_id), do: :ok

  defp last_exit_node?(node) do
    Repo.aggregate(
      from(n in FlowNode, where: n.flow_id == ^node.flow_id and n.type == "exit" and is_nil(n.deleted_at)),
      :count,
      :id
    ) <= 1
  end

  defp do_delete_node(node) do
    fn ->
      orphaned_count = maybe_clear_orphaned_jumps(node)

      References.delete_flow_node_entity_references(node.id)
      References.delete_flow_node_variable_references(node.id)
      Localization.delete_flow_node_texts(node.id)

      case node |> FlowNode.soft_delete_changeset() |> Repo.update() do
        {:ok, deleted_node} -> {deleted_node, %{orphaned_jumps: orphaned_count}}
        {:error, changeset} -> Repo.rollback(changeset)
      end
    end
    |> Repo.transaction()
    |> unwrap_delete_result()
  end

  defp maybe_clear_orphaned_jumps(%{type: "hub"} = node) do
    clear_orphaned_jumps(node.flow_id, node.data["hub_id"])
  end

  defp maybe_clear_orphaned_jumps(_node), do: 0

  defp unwrap_delete_result({:ok, {deleted_node, meta}}), do: {:ok, deleted_node, meta}
  defp unwrap_delete_result({:error, reason}), do: {:error, reason}

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
