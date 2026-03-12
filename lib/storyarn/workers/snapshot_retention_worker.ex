defmodule Storyarn.Workers.SnapshotRetentionWorker do
  @moduledoc """
  Oban cron worker that enforces snapshot retention for soft-deleted projects.

  Runs daily at 4 AM UTC. For each soft-deleted project:
  - Looks up the workspace plan's retention period
  - Deletes auto snapshots older than the retention period
  - Permanently deletes the project if no snapshots remain
  """

  use Oban.Worker, queue: :snapshots, max_attempts: 3

  require Logger

  import Ecto.Query, warn: false

  alias Storyarn.Billing.{Plan, SubscriptionCrud}
  alias Storyarn.Projects
  alias Storyarn.Projects.Project
  alias Storyarn.Repo
  alias Storyarn.Versioning

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    list_deleted_project_ids()
    |> Enum.each(&process_project/1)

    :ok
  end

  defp list_deleted_project_ids do
    from(p in Project,
      where: not is_nil(p.deleted_at),
      select: {p.id, p.workspace_id}
    )
    |> Repo.all()
  end

  defp process_project({project_id, workspace_id}) do
    retention_days = get_retention_days(workspace_id)
    pruned = Versioning.prune_expired_snapshots(project_id, retention_days)

    if pruned > 0 do
      Logger.info("Pruned #{pruned} expired snapshots for deleted project #{project_id}")
    end

    maybe_permanently_delete(project_id)
  rescue
    e ->
      Logger.error("Snapshot retention failed for project #{project_id}: #{Exception.message(e)}")
  end

  defp get_retention_days(workspace_id) do
    plan_key = SubscriptionCrud.plan_for_workspace_id(workspace_id)
    Plan.limit(plan_key, :snapshot_retention_days) || 30
  end

  defp maybe_permanently_delete(project_id) do
    remaining = Versioning.count_project_snapshots(project_id)
    if remaining > 0, do: :ok, else: do_permanently_delete(project_id)
  end

  defp do_permanently_delete(project_id) do
    case Repo.get(Project, project_id) do
      %Project{deleted_at: deleted_at} = project when not is_nil(deleted_at) ->
        case Projects.permanently_delete_project(project) do
          {:ok, _} ->
            Logger.info("Permanently deleted project #{project_id} (no snapshots remain)")

          {:error, reason} ->
            Logger.warning(
              "Failed to permanently delete project #{project_id}: #{inspect(reason)}"
            )
        end

      _ ->
        :ok
    end
  end
end
