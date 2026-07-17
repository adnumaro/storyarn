defmodule Storyarn.Workers.DeleteStorageObjectsWorker do
  @moduledoc """
  Retries deletion of copied asset objects left behind by a rolled-back transaction.

  Content-addressed project blobs are an immutable project-scoped cache and are
  deleted only when their owning project no longer exists. A delayed cleanup
  cannot distinguish an orphan from a deterministic key already adopted by a
  committed project's assets or snapshots, so retention is intentional. Unique
  asset objects and conditional-copy temporaries are still deleted normally.
  """

  use Oban.Worker, queue: :storage_cleanup, max_attempts: 5

  alias Storyarn.Assets.StorageCompensation

  require Logger

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"storage_keys" => storage_keys}, attempt: attempt, max_attempts: max_attempts}) do
    case StorageCompensation.delete_storage_keys(storage_keys) do
      :ok ->
        :ok

      {:error, failed_keys} when attempt >= max_attempts ->
        persist_exhausted_cleanup(failed_keys)

      {:error, failed_keys} ->
        log_failure(length(failed_keys), attempt, max_attempts)
        {:error, :storage_cleanup_failed}
    end
  end

  defp persist_exhausted_cleanup(failed_keys) do
    case StorageCompensation.persist_cleanup_request(failed_keys) do
      {:ok, request} ->
        Logger.warning(
          "Copied asset cleanup moved to recurring reconciliation request_id=#{request.id} failed_count=#{length(failed_keys)}"
        )

        :ok

      {:error, reason} ->
        Logger.error(
          "Copied asset cleanup exhausted retries and fallback persistence failed failed_count=#{length(failed_keys)} error=#{inspect(reason)}"
        )

        # A final-attempt error would let Oban discard the only durable record
        # of these objects. Snoozing keeps this same job alive until the
        # fallback outbox can be persisted successfully.
        {:snooze, 300}
    end
  end

  defp log_failure(failed_count, _attempt, _max_attempts) do
    Logger.warning("Copied asset cleanup will retry failed_count=#{failed_count}")
  end
end
