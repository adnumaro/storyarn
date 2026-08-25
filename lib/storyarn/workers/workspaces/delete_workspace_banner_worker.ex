defmodule Storyarn.Workers.DeleteWorkspaceBannerWorker do
  @moduledoc """
  Delivers the durable cleanup intent for one obsolete Workspace banner.

  Storage failures snooze the same persisted job instead of exhausting it. The
  object key is unique and deletion is idempotent, so duplicate execution is
  safe.
  """

  use Oban.Worker,
    queue: :workspace_banner_cleanup,
    max_attempts: 20,
    unique: [
      fields: [:worker, :queue, :args],
      period: :infinity,
      states: [:available, :scheduled, :executing, :retryable]
    ]

  alias Storyarn.Workspaces

  require Logger

  @retry_seconds 15 * 60

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"workspace_slug" => workspace_slug, "storage_key" => storage_key}})
      when is_binary(workspace_slug) and is_binary(storage_key) do
    case Workspaces.perform_workspace_banner_cleanup(workspace_slug, storage_key) do
      :ok ->
        :ok

      {:error, :invalid_banner_key} ->
        {:discard, :invalid_banner_key}

      {:error, reason} ->
        Logger.warning(
          "Workspace banner cleanup will retry object=#{inspect(Path.basename(storage_key))} reason=#{inspect(reason)}"
        )

        {:snooze, @retry_seconds}
    end
  end

  def perform(_job), do: {:discard, :invalid_workspace_banner_cleanup_args}
end
