defmodule Storyarn.Flows.Editor.Commands.ItemCapacity do
  @moduledoc false

  import Ecto.Query, warn: false

  alias Storyarn.Commercial
  alias Storyarn.Flows.Editor.Projections.SceneRecord
  alias Storyarn.Flows.Editor.Projections.SheetRecord
  alias Storyarn.Flows.Flow
  alias Storyarn.Flows.FlowNode
  alias Storyarn.Repo

  @spec can_create_item?(map()) :: :ok | {:error, :limit_reached, map()}
  def can_create_item?(project), do: can_create_items?(project, 1)

  @spec can_create_items?(map(), pos_integer()) :: :ok | {:error, :limit_reached, map()}
  def can_create_items?(%{id: project_id, workspace_id: workspace_id}, requested)
      when is_integer(project_id) and project_id > 0 and is_integer(workspace_id) and workspace_id > 0 and
             is_integer(requested) and requested > 0 do
    limit = Commercial.entitlement_limit(workspace_id, :items_per_project)
    used = count_project_items(project_id)

    check_capacity(used, limit, requested)
  end

  defp count_project_items(project_id) do
    count_nodes(project_id) +
      count_active(SheetRecord, project_id) +
      count_active(Flow, project_id) +
      count_active(SceneRecord, project_id)
  end

  defp count_nodes(project_id) do
    Repo.aggregate(
      from(node in FlowNode,
        join: flow in Flow,
        on: node.flow_id == flow.id,
        where:
          flow.project_id == ^project_id and is_nil(node.deleted_at) and
            is_nil(flow.deleted_at)
      ),
      :count
    )
  end

  defp count_active(schema, project_id) do
    Repo.aggregate(
      from(record in schema,
        where: record.project_id == ^project_id and is_nil(record.deleted_at)
      ),
      :count
    )
  end

  defp check_capacity(used, nil, _requested) do
    {:error, :limit_reached, %{resource: :items_per_project, used: used, limit: 0}}
  end

  defp check_capacity(used, limit, requested) when used + requested <= limit, do: :ok

  defp check_capacity(used, limit, _requested) do
    {:error, :limit_reached, %{resource: :items_per_project, used: used, limit: limit}}
  end
end
