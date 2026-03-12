defmodule Storyarn.Workers.DailySnapshotWorker do
  @moduledoc """
  Oban cron worker that creates daily automatic project snapshots.

  Runs at 3 AM UTC daily. For each project with auto_snapshots_enabled:
  - Skips if a manual snapshot was created within the last 6 hours
  - Skips if no entities changed since the last snapshot
  - Creates an auto snapshot with `is_auto: true`
  - Prunes oldest auto snapshots if over the billing limit
  """

  use Oban.Worker, queue: :snapshots, max_attempts: 3
  use Gettext, backend: StoryarnWeb.Gettext

  require Logger

  alias Storyarn.Billing
  alias Storyarn.Projects
  alias Storyarn.Versioning
  alias Storyarn.Versioning.ChangeDetector

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    Projects.list_projects_with_auto_snapshots()
    |> Enum.each(&process_project/1)

    :ok
  end

  defp process_project(project) do
    cond do
      ChangeDetector.recent_manual_snapshot?(project.id, 6) ->
        Logger.debug("Skipping daily snapshot for project #{project.id}: recent manual snapshot")

      not ChangeDetector.project_changed_since_last_snapshot?(project.id) ->
        Logger.debug("Skipping daily snapshot for project #{project.id}: no changes")

      true ->
        create_daily_snapshot(project)
    end
  rescue
    e ->
      Logger.error("Daily snapshot failed for project #{project.id}: #{Exception.message(e)}")
  end

  defp create_daily_snapshot(project) do
    today = Date.utc_today() |> Calendar.strftime("%Y-%m-%d")

    case Versioning.create_project_snapshot(project.id, nil,
           title: dgettext("projects", "Daily backup — %{date}", date: today),
           is_auto: true
         ) do
      {:ok, _} ->
        Logger.info("Created daily snapshot for project #{project.id}")
        maybe_prune_auto_snapshots(project)

      {:error, reason} ->
        Logger.warning("Failed daily snapshot for project #{project.id}: #{inspect(reason)}")
    end
  end

  defp maybe_prune_auto_snapshots(project) do
    case Billing.can_create_project_snapshot?(project.id, project.workspace_id) do
      :ok ->
        :ok

      {:error, :limit_reached, _} ->
        Versioning.prune_auto_snapshots(project.id)
    end
  end
end
