defmodule Storyarn.Workers.DeleteStorageObjectsWorker do
  @moduledoc """
  Retries deletion of copied asset objects left behind by a rolled-back transaction.
  """

  use Oban.Worker, queue: :default, max_attempts: 5

  alias Storyarn.Assets.StorageCompensation

  require Logger

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"storage_keys" => storage_keys}, attempt: attempt, max_attempts: max_attempts}) do
    case StorageCompensation.delete_storage_keys(storage_keys) do
      :ok ->
        :ok

      {:error, failed_keys} ->
        log_failure(length(failed_keys), attempt, max_attempts)
        {:error, :storage_cleanup_failed}
    end
  end

  defp log_failure(failed_count, attempt, max_attempts) when attempt >= max_attempts do
    Logger.error("Copied asset cleanup exhausted retries failed_count=#{failed_count}")
  end

  defp log_failure(failed_count, _attempt, _max_attempts) do
    Logger.warning("Copied asset cleanup will retry failed_count=#{failed_count}")
  end
end
