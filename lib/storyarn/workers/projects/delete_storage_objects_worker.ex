defmodule Storyarn.Workers.DeleteStorageObjectsWorker do
  @moduledoc """
  Retries deletion of copied asset objects left behind by a rolled-back transaction.

  Content-addressed project blobs are an immutable project-scoped cache and are
  deleted only when their owning project no longer exists. A delayed cleanup
  cannot distinguish an orphan from a deterministic key already adopted by a
  committed project's assets or snapshots, so retention is intentional. Unique
  asset objects and conditional-copy temporaries are still deleted normally.
  """

  use Oban.Worker,
    queue: :storage_cleanup,
    max_attempts: 5,
    unique: [
      fields: [:worker, :queue, :args],
      period: :infinity,
      states: [:available, :scheduled, :executing, :retryable]
    ]

  alias Storyarn.Projects

  require Logger

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"cleanup_request_id" => cleanup_request_id}})
      when is_integer(cleanup_request_id) and cleanup_request_id > 0 do
    process_durable_request(cleanup_request_id)
  end

  # Legacy jobs terminate after creating the durable receipt. Re-processing
  # the same legacy args would create a fresh receipt on every snooze. The
  # recurring reconciler owns delivery by receipt id from this point onward,
  # before any provider mutation is attempted.
  def perform(%Oban.Job{args: %{"storage_keys" => storage_keys}}) when is_list(storage_keys) do
    case Projects.persist_cleanup_request(storage_keys) do
      {:ok, _request} -> :ok
      {:error, reason} -> persist_retry(reason)
    end
  end

  def perform(%Oban.Job{}), do: {:discard, :invalid_storage_cleanup_job}

  defp process_durable_request(cleanup_request_id) do
    case Projects.retry_persisted_cleanup_request_by_id(cleanup_request_id) do
      :ok ->
        :ok

      :blocked ->
        Logger.error("Durable storage cleanup is blocked and requires operator attention")
        :ok

      {:deferred, seconds} ->
        {:snooze, seconds}

      {:error, _reason} ->
        Logger.warning("Durable storage cleanup delivery failed and will retry")
        {:error, :storage_cleanup_failed}
    end
  end

  defp persist_retry(_reason) do
    Logger.error("Storage cleanup could not establish its durable receipt")
    {:snooze, 300}
  end
end
