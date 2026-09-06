defmodule Storyarn.Flows.Editor.Commands.SequenceRestore do
  @moduledoc false

  import Ecto.Query

  alias Storyarn.Flows.FlowNode
  alias Storyarn.Flows.NodeDelete
  alias Storyarn.Flows.References
  alias Storyarn.Platform.Collaboration
  alias Storyarn.Repo

  @spec restore_sequence(FlowNode.t()) :: {:ok, FlowNode.t()} | {:error, term()}
  def restore_sequence(%FlowNode{id: node_id, type: "sequence"}) when is_integer(node_id) do
    fn ->
      flow_id =
        Repo.one(
          from(node in FlowNode,
            where: node.id == ^node_id and node.type == "sequence",
            select: node.flow_id
          )
        ) || Repo.rollback(:sequence_not_found)

      with {:ok, %{flow: flow, project_id: project_id}} <-
             References.lock_active_flow_for_write(flow_id),
           %FlowNode{} = locked_node <-
             Repo.one(
               from(node in FlowNode,
                 where:
                   node.id == ^node_id and node.flow_id == ^flow.id and
                     node.type == "sequence" and not is_nil(node.deleted_at),
                 lock: "FOR UPDATE"
               )
             ),
           :ok <- NodeDelete.validate_and_lock_active_composition_source(locked_node),
           :ok <-
             References.lock_active_asset_references_for_restore(project_id,
               flow_node_ids: [locked_node.id]
             ),
           {:ok, restored_node} <-
             locked_node
             |> FlowNode.restore_changeset()
             |> Repo.update() do
        {restored_node, project_id}
      else
        nil -> Repo.rollback(:sequence_not_deleted)
        {:error, reason} -> Repo.rollback(reason)
      end
    end
    |> Repo.transaction()
    |> broadcast_sequence_result()
  end

  defp broadcast_sequence_result({:ok, {sequence, project_id}}) do
    Collaboration.broadcast_dashboard_change(project_id, :flows)
    {:ok, sequence}
  end

  defp broadcast_sequence_result(result), do: result
end
