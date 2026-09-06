defmodule Storyarn.Flows.Editor.Commands.SequenceDelete do
  @moduledoc false

  alias Storyarn.Flows.FlowNode
  alias Storyarn.Flows.NodeDelete
  alias Storyarn.Flows.References
  alias Storyarn.Platform.Collaboration
  alias Storyarn.Repo

  @spec delete_sequence(FlowNode.t()) ::
          {:ok, FlowNode.t()} | {:error, Ecto.Changeset.t()}
  def delete_sequence(%FlowNode{type: "sequence"} = node) do
    fn ->
      with {:ok, %{node: locked_node, project_id: project_id}} <-
             References.lock_active_node_for_write(node),
           :ok <- ensure_sequence(locked_node),
           :ok <- NodeDelete.validate_and_lock_no_active_composition_dependents(locked_node),
           {:ok, deleted_node} <-
             locked_node
             |> FlowNode.soft_delete_changeset()
             |> Repo.update() do
        {deleted_node, project_id}
      else
        {:error, reason} -> Repo.rollback(reason)
      end
    end
    |> Repo.transaction()
    |> broadcast_sequence_result()
  end

  defp ensure_sequence(%FlowNode{type: "sequence", deleted_at: nil}), do: :ok
  defp ensure_sequence(_node), do: {:error, :sequence_not_found}

  defp broadcast_sequence_result({:ok, {sequence, project_id}}) do
    Collaboration.broadcast_dashboard_change(project_id, :flows)
    {:ok, sequence}
  end

  defp broadcast_sequence_result(result), do: result
end
