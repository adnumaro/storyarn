defmodule Storyarn.Workers.SnapshotRetentionWorker do
  @moduledoc """
  Oban cron worker that enforces snapshot retention for soft-deleted projects.

  When explicitly enabled, each soft-deleted project:
  - Looks up the workspace plan's retention period
  - Deletes auto snapshots older than the retention period

  This worker never permanently deletes projects. It is disabled by default
  while deleted-project recovery is being hardened.
  """

  use Oban.Worker, queue: :snapshots, max_attempts: 3

  import Ecto.Query, warn: false

  alias Storyarn.Billing.Plan
  alias Storyarn.Billing.SubscriptionCrud
  alias Storyarn.Projects.Project
  alias Storyarn.Repo
  alias Storyarn.Versioning

  require Logger

  @batch_size 100

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    if enabled?(), do: process_batches(nil)
    :ok
  end

  defp process_batches(after_id) do
    projects = list_deleted_project_ids(after_id)
    Enum.each(projects, &process_project/1)

    case List.last(projects) do
      nil -> :ok
      {project_id, _workspace_id} when length(projects) == @batch_size -> process_batches(project_id)
      _project -> :ok
    end
  end

  defp list_deleted_project_ids(after_id) do
    Project
    |> where([p], not is_nil(p.deleted_at))
    |> maybe_after_id(after_id)
    |> order_by([p], asc: p.id)
    |> limit(^@batch_size)
    |> select([p], {p.id, p.workspace_id})
    |> Repo.all()
  end

  defp maybe_after_id(query, nil), do: query
  defp maybe_after_id(query, after_id), do: where(query, [p], p.id > ^after_id)

  defp process_project({project_id, workspace_id}) do
    retention_days = get_retention_days(workspace_id)
    pruned = Versioning.prune_expired_snapshots(project_id, retention_days)

    if pruned > 0 do
      Logger.info("Pruned #{pruned} expired snapshots for deleted project #{project_id}")
    end
  rescue
    e ->
      Logger.error("Snapshot retention failed for project #{project_id}: #{Exception.message(e)}")
  end

  defp get_retention_days(workspace_id) do
    plan_key = SubscriptionCrud.plan_for_workspace_id(workspace_id)
    Plan.limit(plan_key, :snapshot_retention_days) || 30
  end

  defp enabled? do
    case Application.get_env(:storyarn, __MODULE__, []) do
      config when is_list(config) ->
        Keyword.keyword?(config) and Keyword.get(config, :enabled, false) == true

      _invalid_config ->
        false
    end
  end
end
