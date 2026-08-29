defmodule Storyarn.Projects.SnapshotAccounting do
  @moduledoc false

  alias Storyarn.Commercial
  alias Storyarn.Projects.Memberships
  alias Storyarn.Projects.Versioning
  alias Storyarn.Repo

  @type accounting :: %{
          required(:snapshots) => [map()],
          required(:snapshot_reservations) => map(),
          required(:snapshot_slots_used) => non_neg_integer(),
          required(:snapshot_slots_limit) => non_neg_integer() | nil,
          required(:storage_usage) => map(),
          required(:storage_limit) => non_neg_integer() | nil
        }

  @spec read(map(), pos_integer()) :: {:ok, accounting()} | {:error, term()}
  def read(%{user: _} = scope, project_id) when is_integer(project_id) and project_id > 0 do
    Repo.repeatable_read(
      fn ->
        case Memberships.authorize(scope, project_id, :manage_project) do
          {:ok, project, _membership} ->
            snapshots = Versioning.list_project_snapshots(project.id)

            %{
              snapshots: snapshots,
              snapshot_reservations:
                snapshots
                |> Enum.map(& &1.id)
                |> Commercial.active_project_snapshot_reservations(),
              snapshot_slots_used: Commercial.project_snapshot_slot_usage(project.id),
              snapshot_slots_limit: Commercial.entitlement_limit(project.workspace_id, :project_snapshots_per_project),
              storage_usage: Commercial.workspace_storage_usage(project.workspace_id),
              storage_limit: Commercial.entitlement_limit(project.workspace_id, :storage_bytes_per_workspace)
            }

          {:error, reason} ->
            Repo.rollback(reason)
        end
      end,
      timeout: :infinity
    )
  end

  def read(_scope, _project_id), do: {:error, :unauthorized}
end
