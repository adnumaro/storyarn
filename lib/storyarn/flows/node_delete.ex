defmodule Storyarn.Flows.NodeDelete do
  @moduledoc false

  import Ecto.Query, warn: false

  alias Storyarn.Flows.{FlowNode, VariableReferenceTracker}
  alias Storyarn.Localization
  alias Storyarn.Repo
  alias Storyarn.Sheets

  def delete_node(%FlowNode{type: "entry"}), do: {:error, :cannot_delete_entry_node}

  def delete_node(%FlowNode{type: "exit"} = node) do
    if last_exit_node?(node), do: {:error, :cannot_delete_last_exit}, else: do_delete_node(node)
  end

  def delete_node(%FlowNode{} = node), do: do_delete_node(node)

  @doc """
  Restores a soft-deleted node by clearing its deleted_at timestamp.
  Returns {:ok, :already_active} if the node is not deleted (idempotent for redo safety).
  """
  def restore_node(flow_id, node_id) do
    case Repo.get(FlowNode, node_id) do
      %FlowNode{flow_id: ^flow_id, deleted_at: deleted_at} = node when not is_nil(deleted_at) ->
        node |> FlowNode.restore_changeset() |> Repo.update()

      %FlowNode{flow_id: ^flow_id, deleted_at: nil} ->
        {:ok, :already_active}

      _ ->
        {:error, :not_found}
    end
  end

  defp last_exit_node?(node) do
    from(n in FlowNode,
      where: n.flow_id == ^node.flow_id and n.type == "exit" and is_nil(n.deleted_at)
    )
    |> Repo.aggregate(:count, :id) <= 1
  end

  defp do_delete_node(node) do
    Repo.transaction(fn ->
      orphaned_count = maybe_clear_orphaned_jumps(node)

      Sheets.delete_flow_node_references(node.id)
      VariableReferenceTracker.delete_references(node.id)
      Localization.delete_flow_node_texts(node.id)

      case node |> FlowNode.soft_delete_changeset() |> Repo.update() do
        {:ok, deleted_node} -> {deleted_node, %{orphaned_jumps: orphaned_count}}
        {:error, changeset} -> Repo.rollback(changeset)
      end
    end)
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
