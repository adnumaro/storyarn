defmodule Storyarn.Workers.RestoreProjectWorker do
  @moduledoc """
  Oban worker that performs a project snapshot restore in the background.

  Acquires an exclusive lock before enqueuing, then:
  1. Runs the restore (transactional, creates pre/post safety snapshots)
  2. Releases the lock (always, even on failure)
  3. Broadcasts completion or failure to all editors
  """

  use Oban.Worker, queue: :snapshots, max_attempts: 1

  alias Storyarn.Collaboration
  alias Storyarn.Projects
  alias Storyarn.Versioning

  require Logger

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"project_id" => project_id, "snapshot_id" => snapshot_id, "user_id" => user_id}}) do
    case Versioning.ensure_restore_enabled(:project_snapshot_restore) do
      :ok ->
        restore_snapshot(project_id, snapshot_id, user_id)

      {:error, :restore_temporarily_disabled} = error ->
        Projects.release_restoration_lock(project_id)
        Collaboration.broadcast_restoration_failed(project_id, %{reason: :restore_temporarily_disabled})
        error
    end
  end

  defp restore_snapshot(project_id, snapshot_id, user_id) do
    case Versioning.get_project_snapshot(project_id, snapshot_id) do
      nil ->
        Projects.release_restoration_lock(project_id)
        Collaboration.broadcast_restoration_failed(project_id, %{reason: "Snapshot not found"})
        {:error, :snapshot_not_found}

      snapshot ->
        do_restore(project_id, snapshot, user_id)
    end
  end

  defp do_restore(project_id, snapshot, user_id) do
    result =
      try do
        Versioning.restore_project_snapshot(project_id, snapshot, user_id: user_id)
      rescue
        exception ->
          Logger.error("Project restore raised for project #{project_id}: #{Exception.message(exception)}")

          {:error, :restore_exception}
      after
        Projects.release_restoration_lock(project_id)
      end

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
