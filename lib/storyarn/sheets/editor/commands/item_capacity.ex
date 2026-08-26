defmodule Storyarn.Sheets.Editor.Commands.ItemCapacity do
  @moduledoc """
  Enforces the platform item entitlement at the Sheet creation boundary.

  Foreign rows are consumer-local read projections. This command writes only
  Sheet editor data and preserves the shared-table count while bounded contexts
  still use the same database.
  """

  import Ecto.Query, warn: false

  alias Storyarn.Platform
  alias Storyarn.Repo
  alias Storyarn.Sheets.Editor.Data.FlowNodeRecord
  alias Storyarn.Sheets.Editor.Data.FlowRecord
  alias Storyarn.Sheets.Editor.Data.SceneRecord
  alias Storyarn.Sheets.Sheet

  def can_create_item?(project), do: can_create_items?(project, 1)

  def can_create_items?(%{id: project_id, workspace_id: workspace_id}, requested)
      when is_integer(project_id) and project_id > 0 and is_integer(workspace_id) and workspace_id > 0 and
             is_integer(requested) and requested > 0 do
    limit = Platform.entitlement_limit(workspace_id, :items_per_project)
    used = count_project_items(project_id)
    check_capacity(used, limit, requested)
  end

  # The commercial quota counts the same four collections in every tool copy.
  # Changing this set is a product-contract change, not a local refactor.
  defp count_project_items(project_id) do
    count_nodes(project_id) + count_active(Sheet, project_id) +
      count_active(FlowRecord, project_id) + count_active(SceneRecord, project_id)
  end

  defp count_nodes(project_id) do
    Repo.aggregate(
      from(node in FlowNodeRecord,
        join: flow in FlowRecord,
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

  defp check_capacity(used, nil, _requested),
    do: {:error, :limit_reached, %{resource: :items_per_project, used: used, limit: 0}}

  defp check_capacity(used, limit, requested) when used + requested <= limit, do: :ok

  defp check_capacity(used, limit, _requested),
    do: {:error, :limit_reached, %{resource: :items_per_project, used: used, limit: limit}}
end
