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

  alias Storyarn.Projects
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
        {:ok, :already_purged} ->
          :ok

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

  defp expired?(_deleted_at, %{purge_at: %DateTime{} = purge_at}, now), do: DateTime.compare(now, purge_at) in [:eq, :gt]

  defp expired?(_deleted_at, _item, _now), do: false

  defp permanently_delete_item(%{type: "sheet"} = item) do
    Projects.delete_retention_candidate(item, &Sheets.permanently_delete_sheet/1)
  end

  defp permanently_delete_item(%{type: "flow"} = item) do
    Projects.delete_retention_candidate(item, &Projects.permanently_delete_trashed_flow/1)
  end

  defp permanently_delete_item(%{type: "scene"} = item) do
    Projects.delete_retention_candidate(item, &Projects.permanently_delete_trashed_scene/1)
  end

  defp permanently_delete_item(%{type: "asset"} = item) do
    case Projects.purge_asset_trash_candidate(item, nil) do
      {:error, :asset_not_found} -> {:ok, :already_purged}
      result -> result
    end
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
