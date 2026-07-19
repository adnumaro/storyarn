defmodule Storyarn.Workers.TrashRetentionWorker do
  @moduledoc """
  Oban cron worker that hard-deletes soft-deleted project entities past their
  trash retention window.

  Scheduled hourly, but disabled by default while referential integrity is
  being hardened. When explicitly enabled, each soft-deleted project item:
  - Looks up the project's retention hours (per-project override in
    `project.settings["trash_retention_hours"]`, else the workspace plan's
    default).
  - Hard-deletes the entity if `deleted_at` is past the window.

  Flow sequences are `flow_nodes` rows with `type='sequence'`. Soft-deleted
  flow_nodes are not purged directly by this worker; they hard-delete via FK
  cascade when their parent flow is hard-deleted.

  `ON DELETE CASCADE` on `flows_entity_trash_refs.target_*_id` drops the
  trash refs pointing at the deleted entity automatically — no separate
  job needed for trash-row cleanup.
  """

  use Oban.Worker, queue: :default, max_attempts: 3

  alias Storyarn.Billing.Plan
  alias Storyarn.Billing.SubscriptionCrud
  alias Storyarn.Flows
  alias Storyarn.Projects
  alias Storyarn.Scenes
  alias Storyarn.Screenplays
  alias Storyarn.Shared.TimeHelpers
  alias Storyarn.Sheets

  require Logger

  @batch_size 100

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    if enabled?() do
      now = TimeHelpers.now()

      case Projects.deleted_items_retention_cutoff() do
        nil -> :ok
        cutoff -> process_batches(nil, cutoff, now)
      end
    end

    :ok
  end

  defp process_batches(cursor, cutoff, now) do
    items = Projects.list_deleted_items_for_retention(after: cursor, through: cutoff, limit: @batch_size)
    Enum.each(items, &process_item(&1, now))

    case List.last(items) do
      nil ->
        :ok

      item when length(items) == @batch_size ->
        process_batches({item.deleted_at, item.type, item.id}, cutoff, now)

      _item ->
        :ok
    end
  end

  defp process_item(item, now) do
    if expired?(item.deleted_at, item, now) do
      case permanently_delete_item(item) do
        {:ok, _} ->
          Logger.info("Permanently deleted #{item.type} #{item.id}")

        {:error, reason} ->
          Logger.warning("Failed to permanently delete #{item.type} #{item.id}: #{inspect(reason)}")
      end
    end
  rescue
    e ->
      Logger.error("Trash retention failed for #{item.type} #{item.id}: #{Exception.message(e)}")
  end

  defp expired?(deleted_at, item, now) do
    DateTime.diff(now, deleted_at, :hour) >= retention_hours_for(item)
  end

  defp retention_hours_for(%{project_settings: settings, workspace_id: workspace_id}) do
    case Map.get(settings || %{}, "trash_retention_hours") do
      hours when is_integer(hours) and hours > 0 ->
        hours

      _ ->
        workspace_id |> SubscriptionCrud.plan_for_workspace_id() |> Plan.retention_hours()
    end
  end

  defp permanently_delete_item(%{type: "sheet"} = item) do
    with {:ok, sheet} <- fetch_sheet(item), do: Sheets.permanently_delete_sheet(sheet)
  end

  defp permanently_delete_item(%{type: "flow"} = item) do
    with {:ok, flow} <- fetch_flow(item), do: Flows.hard_delete_flow(flow)
  end

  defp permanently_delete_item(%{type: "scene"} = item) do
    with {:ok, scene} <- fetch_scene(item), do: Scenes.hard_delete_scene(scene)
  end

  defp permanently_delete_item(%{type: "screenplay"} = item) do
    with {:ok, screenplay} <- fetch_screenplay(item), do: Screenplays.hard_delete_screenplay(screenplay)
  end

  defp fetch_sheet(item), do: fetch_deleted(Sheets.get_trashed_sheet(item.project_id, item.id))
  defp fetch_flow(item), do: fetch_deleted(Flows.get_flow_including_deleted(item.project_id, item.id))
  defp fetch_scene(item), do: fetch_deleted(Scenes.get_scene_including_deleted(item.project_id, item.id))

  defp fetch_screenplay(item), do: fetch_deleted(Screenplays.get_screenplay_including_deleted(item.project_id, item.id))

  defp fetch_deleted(%{deleted_at: %DateTime{}} = item), do: {:ok, item}
  defp fetch_deleted(_item), do: {:error, :not_found}

  defp enabled? do
    case Application.get_env(:storyarn, __MODULE__, []) do
      config when is_list(config) ->
        Keyword.keyword?(config) and Keyword.get(config, :enabled, false) == true

      _invalid_config ->
        false
    end
  end
end
