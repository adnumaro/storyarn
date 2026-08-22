defmodule Storyarn.References.FlowNodeRepair do
  @moduledoc """
  Projects-owned repair writer for stale variable names in Flow node data.

  The legacy References namespace is currently part of the Projects boundary.
  This workflow consumes the shared SQL table through local records and
  refreshes the Project-owned derivatives in the same transaction. It supports
  only the narrow data mutation used by stale-reference repair; graph topology
  and editor behavior remain owned by the Flow bounded context.
  """

  import Ecto.Query, warn: false

  alias Storyarn.Projects.FlowLocalizationProjection
  alias Storyarn.Projects.FlowWordCount, as: WordCount
  alias Storyarn.References.EntityTracker
  alias Storyarn.References.Persistence.FlowNodeRecord
  alias Storyarn.References.Persistence.FlowRecord
  alias Storyarn.References.ProjectReferenceIntegrity
  alias Storyarn.References.VariableReferenceTracker
  alias Storyarn.Repo

  @derivatives_fingerprint_version 1

  @spec update_data_without_dashboard_broadcast(FlowNodeRecord.t(), map()) ::
          {:ok, FlowNodeRecord.t(), map()} | {:error, term()}
  def update_data_without_dashboard_broadcast(%FlowNodeRecord{} = node, data) when is_map(data) do
    case Repo.transaction(fn -> repair_node_data(node, data) end) do
      {:ok, {updated_node, meta}} -> {:ok, updated_node, meta}
      {:error, reason} -> {:error, reason}
    end
  end

  def update_data_without_dashboard_broadcast(node, data), do: {:error, {:invalid_flow_node_reference_repair, node, data}}

  defp repair_node_data(node, data) do
    with {:ok, project_id} <- active_project_id(node),
         {:ok, _project} <-
           ProjectReferenceIntegrity.lock_active_project(project_id, :key_share),
         {:ok, flow} <- lock_active_flow(node.flow_id, project_id),
         {:ok, locked_node} <- lock_active_node(node.id, flow.id),
         :ok <- lock_active_parent(locked_node),
         {:ok, updated_node} <- persist_data(locked_node, data),
         :ok <- refresh_derivatives(updated_node, project_id) do
      {updated_node, %{renamed_jumps: 0, connections_changed?: false}}
    else
      {:error, reason} -> Repo.rollback(reason)
    end
  end

  defp active_project_id(%FlowNodeRecord{flow_id: flow_id}) when is_integer(flow_id) do
    case Repo.one(
           from(flow in FlowRecord,
             where: flow.id == ^flow_id and is_nil(flow.deleted_at),
             select: flow.project_id
           )
         ) do
      project_id when is_integer(project_id) -> {:ok, project_id}
      nil -> {:error, :flow_not_found}
    end
  end

  defp active_project_id(_node), do: {:error, :flow_not_found}

  defp lock_active_flow(flow_id, project_id) do
    case Repo.one(
           from(flow in FlowRecord,
             where:
               flow.id == ^flow_id and flow.project_id == ^project_id and
                 is_nil(flow.deleted_at),
             lock: "FOR KEY SHARE"
           )
         ) do
      %FlowRecord{} = flow -> {:ok, flow}
      nil -> {:error, :flow_not_found}
    end
  end

  defp lock_active_node(node_id, flow_id) do
    case Repo.one(
           from(node in FlowNodeRecord,
             where:
               node.id == ^node_id and node.flow_id == ^flow_id and
                 is_nil(node.deleted_at),
             lock: "FOR UPDATE"
           )
         ) do
      %FlowNodeRecord{} = node -> {:ok, node}
      nil -> {:error, :node_not_found}
    end
  end

  defp lock_active_parent(%FlowNodeRecord{parent_id: nil}), do: :ok

  defp lock_active_parent(%FlowNodeRecord{} = node) do
    case Repo.one(
           from(parent in FlowNodeRecord,
             where:
               parent.id == ^node.parent_id and parent.flow_id == ^node.flow_id and
                 parent.type == "sequence" and is_nil(parent.deleted_at),
             lock: "FOR KEY SHARE",
             select: parent.id
           )
         ) do
      parent_id when parent_id == node.parent_id -> :ok
      nil -> {:error, :parent_not_found}
    end
  end

  defp persist_data(node, data) do
    node
    |> Ecto.Changeset.change(%{
      data: data,
      word_count: WordCount.for_node_data(node.type, data),
      derivatives_fingerprint: derivatives_fingerprint(node.type, data)
    })
    |> Repo.update()
  end

  defp refresh_derivatives(node, project_id) do
    with :ok <-
           normalize_projection_result(
             EntityTracker.update_flow_node_entity_references(
               node,
               project_id: project_id
             )
           ),
         :ok <- normalize_projection_result(VariableReferenceTracker.update_references(node)) do
      FlowLocalizationProjection.extract_flow_node(node)
    end
  end

  defp normalize_projection_result(:ok), do: :ok
  defp normalize_projection_result({:error, reason}), do: {:error, reason}

  defp normalize_projection_result(result), do: {:error, {:unexpected_reference_write_result, result}}

  defp derivatives_fingerprint(type, data) do
    {@derivatives_fingerprint_version, type, data}
    |> :erlang.term_to_binary([:deterministic])
    |> then(&:crypto.hash(:sha256, &1))
    |> Base.encode16(case: :lower)
  end
end
