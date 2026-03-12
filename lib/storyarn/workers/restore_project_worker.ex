defmodule Storyarn.Workers.RestoreProjectWorker do
  @moduledoc """
  Oban worker that performs a project snapshot restore in the background.

  Acquires an exclusive lock before enqueuing, then:
  1. Runs the restore (transactional, creates pre/post safety snapshots)
  2. Releases the lock (always, even on failure)
  3. Broadcasts completion or failure to all editors
  """

  use Oban.Worker, queue: :snapshots, max_attempts: 1

  require Logger

  alias Storyarn.Collaboration
  alias Storyarn.Projects
  alias Storyarn.Versioning

  @impl Oban.Worker
  def perform(%Oban.Job{
        args: %{"project_id" => project_id, "snapshot_id" => snapshot_id, "user_id" => user_id}
      }) do
    snapshot = Versioning.get_project_snapshot(project_id, snapshot_id)

    if snapshot do
      do_restore(project_id, snapshot, user_id)
    else
      Projects.release_restoration_lock(project_id)
      Collaboration.broadcast_restoration_failed(project_id, %{reason: "Snapshot not found"})
      {:error, :snapshot_not_found}
    end
  end

  defp do_restore(project_id, snapshot, user_id) do
    result = Versioning.restore_project_snapshot(project_id, snapshot, user_id: user_id)

    # ALWAYS release lock
    Projects.release_restoration_lock(project_id)

    case result do
      {:ok, r} ->
        Collaboration.broadcast_restoration_completed(project_id, %{
          restored: r.restored,
          skipped: r.skipped,
          snapshot_title: snapshot.title
        })

        Collaboration.broadcast_dashboard_change(project_id, :all)
        :ok

      {:error, reason} ->
        Logger.error("Project restore failed for project #{project_id}: #{inspect(reason)}")

        Collaboration.broadcast_restoration_failed(project_id, %{reason: :restore_failed})
        {:error, reason}
    end
  end
end
