defmodule Storyarn.Workers.RecoverProjectWorker do
  @moduledoc """
  Oban worker that recovers a deleted project from a snapshot.

  Creates a new project with all entities from the snapshot data,
  with full ID remapping for cross-references.
  """

  use Oban.Worker, queue: :snapshots, max_attempts: 1

  alias Storyarn.Projects
  alias Storyarn.Versioning
  alias Storyarn.Versioning.ProjectSnapshotIntegrity
  alias Storyarn.Versioning.SnapshotStorage
  alias Storyarn.Workspaces

  require Logger

  @impl Oban.Worker
  def perform(%Oban.Job{
        args: %{"workspace_id" => workspace_id, "snapshot_id" => snapshot_id, "user_id" => user_id} = args
      }) do
    project_id = args["project_id"]

    with :ok <- Versioning.ensure_restore_enabled(:deleted_project_recovery),
         %{role: role} when role in ["owner", "admin"] <-
           Workspaces.get_membership(workspace_id, user_id),
         %Projects.Project{} = project <-
           Projects.get_deleted_project(workspace_id, project_id),
         snapshot when not is_nil(snapshot) <-
           Versioning.get_project_snapshot(project.id, snapshot_id) do
      do_recover(workspace_id, snapshot, user_id, "#{project.name} (Recovered)")
    else
      {:error, :restore_temporarily_disabled} = error ->
        broadcast_failure(workspace_id, "Recovery temporarily unavailable")
        error

      _invalid_source ->
        broadcast_failure(workspace_id, "Snapshot not found")
        {:error, :snapshot_not_found}
    end
  end

  defp do_recover(workspace_id, snapshot, user_id, name) do
    with {:ok, snapshot_data, actual_checksum} <-
           SnapshotStorage.load_snapshot_with_checksum(snapshot.storage_key),
         :ok <-
           ProjectSnapshotIntegrity.validate_recovery_blob(
             snapshot_data,
             snapshot.entity_counts,
             snapshot.checksum,
             actual_checksum
           ),
         {:ok, project} <-
           Versioning.recover_project(workspace_id, snapshot_data, user_id, name: name) do
      broadcast_success(workspace_id, project)
      :ok
    else
      {:error, reason} ->
        Logger.error("Project recovery failed for workspace #{workspace_id}: #{inspect(reason)}")
        broadcast_failure(workspace_id, inspect(reason))
        {:error, reason}
    end
  end

  defp broadcast_success(workspace_id, project) do
    Phoenix.PubSub.broadcast(
      Storyarn.PubSub,
      "workspace:#{workspace_id}:recovery",
      {:recovery_completed, %{project_id: project.id, project_name: project.name}}
    )
  end

  defp broadcast_failure(workspace_id, reason) do
    Phoenix.PubSub.broadcast(
      Storyarn.PubSub,
      "workspace:#{workspace_id}:recovery",
      {:recovery_failed, %{reason: reason}}
    )
  end
end
