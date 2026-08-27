defmodule Storyarn.Flows.Versioning.Commands.NamedVersionCapacity do
  @moduledoc """
  Enforces the named-version entitlement for Flow version writes.

  Project scope is read through Versioning's local projection. The entitlement
  remains project-wide, so every named entity-version row consumes the shared
  quota while this capability serializes Flow-owned writes.
  """

  import Ecto.Query, warn: false

  alias Storyarn.Flows.Versioning.EntityVersionRecord
  alias Storyarn.Flows.Versioning.Projections.ProjectRecord
  alias Storyarn.Platform
  alias Storyarn.Repo

  @spec can_create?(pos_integer(), pos_integer()) ::
          :ok | {:error, :project_scope_mismatch | :limit_reached, map()}
  def can_create?(project_id, workspace_id)
      when is_integer(project_id) and project_id > 0 and is_integer(workspace_id) and workspace_id > 0 do
    case Repo.get(ProjectRecord, project_id) do
      %ProjectRecord{workspace_id: ^workspace_id, deleted_at: nil} ->
        check_capacity(project_id, workspace_id)

      _project ->
        {:error, :project_scope_mismatch, %{project_id: project_id, workspace_id: workspace_id}}
    end
  end

  @spec ensure_capacity(pos_integer() | ProjectRecord.t()) ::
          :ok | {:error, :limit_reached | :project_scope_mismatch | :transaction_required, map()}
  def ensure_capacity(project_id) when is_integer(project_id) and project_id > 0 do
    with {:ok, project} <- lock_project(project_id) do
      ensure_capacity(project)
    end
  end

  def ensure_capacity(%ProjectRecord{id: project_id, workspace_id: workspace_id}) do
    check_capacity(project_id, workspace_id)
  end

  @spec lock_project(pos_integer()) ::
          {:ok, ProjectRecord.t()}
          | {:error, :project_scope_mismatch | :transaction_required, map()}
  def lock_project(project_id) when is_integer(project_id) and project_id > 0 do
    if Repo.in_transaction?() do
      case Repo.one(
             from(project in ProjectRecord,
               where: project.id == ^project_id and is_nil(project.deleted_at),
               lock: "FOR UPDATE"
             )
           ) do
        %ProjectRecord{} = project -> {:ok, project}
        nil -> {:error, :project_scope_mismatch, %{project_id: project_id}}
      end
    else
      {:error, :transaction_required, %{resource: :named_versions_per_project}}
    end
  end

  defp check_capacity(project_id, workspace_id) do
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

    check_limit(used, limit)
  end

  defp check_limit(used, nil),
    do: {:error, :limit_reached, %{resource: :named_versions_per_project, used: used, limit: 0}}

  defp check_limit(used, limit) when used < limit, do: :ok

  defp check_limit(used, limit),
    do: {:error, :limit_reached, %{resource: :named_versions_per_project, used: used, limit: limit}}
end
