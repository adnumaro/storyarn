defmodule Storyarn.Sheets.Limits do
  @moduledoc false

  import Ecto.Query, warn: false

  alias Storyarn.Platform
  alias Storyarn.Repo
  alias Storyarn.Sheets.Persistence.FlowNodeRecord
  alias Storyarn.Sheets.Persistence.FlowRecord
  alias Storyarn.Sheets.Persistence.ProjectRecord
  alias Storyarn.Sheets.Persistence.SceneRecord
  alias Storyarn.Sheets.Sheet
  alias Storyarn.Sheets.Versioning.EntityVersionRecord

  def can_create_item?(project), do: can_create_items?(project, 1)

  def can_create_named_version?(project_id, workspace_id)
      when is_integer(project_id) and project_id > 0 and is_integer(workspace_id) and workspace_id > 0 do
    case Repo.get(ProjectRecord, project_id) do
      %ProjectRecord{workspace_id: ^workspace_id, deleted_at: nil} ->
        check_named_version_capacity(project_id, workspace_id)

      _project ->
        {:error, :project_scope_mismatch, %{project_id: project_id, workspace_id: workspace_id}}
    end
  end

  def ensure_named_version_capacity(project_id) when is_integer(project_id) and project_id > 0 do
    with {:ok, project} <- lock_named_version_project(project_id) do
      ensure_named_version_capacity(project)
    end
  end

  def ensure_named_version_capacity(%ProjectRecord{id: project_id, workspace_id: workspace_id}) do
    check_named_version_capacity(project_id, workspace_id)
  end

  def lock_named_version_project(project_id) when is_integer(project_id) and project_id > 0 do
    if Repo.in_transaction?() do
      case Repo.one(
             from project in ProjectRecord,
               where: project.id == ^project_id and is_nil(project.deleted_at),
               lock: "FOR UPDATE"
           ) do
        %ProjectRecord{} = project -> {:ok, project}
        nil -> {:error, :project_scope_mismatch, %{project_id: project_id}}
      end
    else
      {:error, :transaction_required, %{resource: :named_versions_per_project}}
    end
  end

  def can_create_items?(%{id: project_id, workspace_id: workspace_id}, requested)
      when is_integer(project_id) and project_id > 0 and is_integer(workspace_id) and workspace_id > 0 and
             is_integer(requested) and requested > 0 do
    limit = Platform.entitlement_limit(workspace_id, :items_per_project)
    used = count_project_items(project_id)
    check_capacity(used, limit, requested)
  end

  # The commercial item quota counts the same four collections in every tool
  # copy; drifting the counted set here would shift who hits the paywall.
  defp count_project_items(project_id) do
    count_nodes(project_id) + count_active(Sheet, project_id) +
      count_active(FlowRecord, project_id) + count_active(SceneRecord, project_id)
  end

  defp count_nodes(project_id) do
    Repo.aggregate(
      from(node in FlowNodeRecord,
        join: flow in FlowRecord,
        on: node.flow_id == flow.id,
        where: flow.project_id == ^project_id and is_nil(node.deleted_at) and is_nil(flow.deleted_at)
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

  defp check_named_version_capacity(project_id, workspace_id) do
    limit = Platform.entitlement_limit(workspace_id, :named_versions_per_project)

    used =
      Repo.aggregate(
        from(version in EntityVersionRecord,
          where:
            version.project_id == ^project_id and not is_nil(version.title) and
              version.is_auto == false
        ),
        :count
      )

    check_named_capacity(used, limit)
  end

  defp check_named_capacity(used, nil),
    do: {:error, :limit_reached, %{resource: :named_versions_per_project, used: used, limit: 0}}

  defp check_named_capacity(used, limit) when used < limit, do: :ok

  defp check_named_capacity(used, limit),
    do: {:error, :limit_reached, %{resource: :named_versions_per_project, used: used, limit: limit}}

  defp check_capacity(used, nil, _requested),
    do: {:error, :limit_reached, %{resource: :items_per_project, used: used, limit: 0}}

  defp check_capacity(used, limit, requested) when used + requested <= limit, do: :ok

  defp check_capacity(used, limit, _requested),
    do: {:error, :limit_reached, %{resource: :items_per_project, used: used, limit: limit}}
end
