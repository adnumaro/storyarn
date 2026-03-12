defmodule Storyarn.Workers.RecoverProjectWorker do
  @moduledoc """
  Oban worker that recovers a deleted project from a snapshot.

  Creates a new project with all entities from the snapshot data,
  with full ID remapping for cross-references.
  """

  use Oban.Worker, queue: :snapshots, max_attempts: 1

  require Logger

  alias Storyarn.Projects
  alias Storyarn.Versioning
  alias Storyarn.Versioning.SnapshotStorage

  @impl Oban.Worker
  def perform(%Oban.Job{
        args:
          %{
            "workspace_id" => workspace_id,
            "snapshot_id" => snapshot_id,
            "user_id" => user_id
          } = args
      }) do
    project_id = args["project_id"]
    snapshot = Versioning.get_project_snapshot(project_id, snapshot_id)

    if snapshot do
      original_name = get_original_project_name(project_id)
      do_recover(workspace_id, snapshot, user_id, original_name)
    else
      broadcast_failure(workspace_id, "Snapshot not found")
      {:error, :snapshot_not_found}
    end
  end

  defp get_original_project_name(project_id) do
    case Storyarn.Repo.get(Projects.Project, project_id) do
      nil -> "Recovered Project"
      project -> "#{project.name} (Recovered)"
    end
  end

  defp do_recover(workspace_id, snapshot, user_id, name) do
    with {:ok, snapshot_data} <- SnapshotStorage.load_snapshot(snapshot.storage_key),
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
