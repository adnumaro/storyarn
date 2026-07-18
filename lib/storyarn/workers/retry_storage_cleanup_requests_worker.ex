defmodule Storyarn.Workers.RetryStorageCleanupRequestsWorker do
  @moduledoc """
  Retries durable copied-asset cleanup requests that could not be enqueued directly.
  """

  use Oban.Worker,
    queue: :storage_cleanup,
    max_attempts: 5,
    unique: [period: 120, states: [:available, :scheduled, :executing, :retryable]]

  alias Storyarn.Assets.StorageCompensation

  require Logger

  @impl Oban.Worker
  def perform(%Oban.Job{attempt: attempt, max_attempts: max_attempts}) do
    case StorageCompensation.retry_persisted_cleanup_requests() do
      :ok ->
        :ok

      {:error, failed_count} ->
        log_failure(failed_count, attempt, max_attempts)
        {:error, :storage_cleanup_failed}
    end
  end

  defp log_failure(failed_count, attempt, max_attempts) when attempt >= max_attempts do
    Logger.error("Persisted copied asset cleanup exhausted retries failed_count=#{failed_count}")
  end

  defp log_failure(failed_count, _attempt, _max_attempts) do
    Logger.warning("Persisted copied asset cleanup will retry failed_count=#{failed_count}")
  end
end
