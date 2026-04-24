defmodule Storyarn.Workers.TrashRetentionWorker do
  @moduledoc """
  Oban cron worker that hard-deletes soft-deleted flow-domain entities past
  their trash retention window.

  Runs hourly (daily + 24h retention would mean up to 47h effective — hourly
  keeps slack bounded). For each soft-deleted `flow`:
  - Looks up the project's retention hours (per-project override in
    `project.settings["trash_retention_hours"]`, else the workspace plan's
    default).
  - Hard-deletes the entity if `deleted_at` is past the window.

  Sequences are now `flow_nodes` rows with `type='sequence'` (post-Phase 1
  of the flow relational refactor). Soft-deleted flow_nodes are not purged
  by this worker — they only hard-delete via FK cascade when their parent
  flow is hard-deleted.

  `ON DELETE CASCADE` on `flows_entity_trash_refs.target_*_id` drops the
  trash refs pointing at the deleted entity automatically — no separate
  job needed for trash-row cleanup.
  """

  use Oban.Worker, queue: :default, max_attempts: 3

  import Ecto.Query, warn: false

  alias Storyarn.Billing.Plan
  alias Storyarn.Billing.SubscriptionCrud
  alias Storyarn.Flows
  alias Storyarn.Flows.Flow
  alias Storyarn.Projects.Project
  alias Storyarn.Repo
  alias Storyarn.Shared.TimeHelpers

  require Logger

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    now = TimeHelpers.now()
    Enum.each(list_deleted_flows(), &process_flow(&1, now))
    :ok
  end

  defp list_deleted_flows do
    Repo.all(
      from(f in Flow,
        join: p in Project,
        on: p.id == f.project_id,
        where: not is_nil(f.deleted_at),
        select: {f, p}
      )
    )
  end

  defp process_flow({flow, project}, now) do
    if expired?(flow.deleted_at, project, now) do
      case Flows.hard_delete_flow(flow) do
        {:ok, _} ->
          Logger.info("Permanently deleted flow #{flow.id}")

        {:error, reason} ->
          Logger.warning("Failed to permanently delete flow #{flow.id}: #{inspect(reason)}")
      end
    end
  rescue
    e ->
      Logger.error("Trash retention failed for flow #{flow.id}: #{Exception.message(e)}")
  end

  defp expired?(deleted_at, project, now) do
    DateTime.diff(now, deleted_at, :hour) >= retention_hours_for(project)
  end

  defp retention_hours_for(%Project{settings: settings, workspace_id: workspace_id}) do
    case Map.get(settings || %{}, "trash_retention_hours") do
      hours when is_integer(hours) and hours > 0 ->
        hours

      _ ->
        workspace_id |> SubscriptionCrud.plan_for_workspace_id() |> Plan.retention_hours()
    end
  end
end
