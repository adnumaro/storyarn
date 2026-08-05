defmodule Storyarn.Workers.CleanupProjectSnapshotWorker do
  @moduledoc """
  Deletes one bounded batch from a durable snapshot cleanup intent.

  Duplicate delivery is safe: missing objects are successful deletes and the
  intent's remaining inventory can only shrink.
  """

  use Oban.Worker,
    queue: :storage_cleanup,
    max_attempts: 10,
    unique: [fields: [:worker, :args], period: :infinity, states: [:available, :scheduled, :executing, :retryable]]

  alias Storyarn.Versioning

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"intent_id" => intent_id}, attempt: attempt, max_attempts: max_attempts}) do
    case Versioning.process_project_snapshot_cleanup_intent(intent_id,
           final_attempt?: attempt >= max_attempts
         ) do
      {:ok, :more} ->
        {:snooze, 1}

      {:ok, _terminal} ->
        :ok

      {:error, :storage_provider_failure} ->
        {:error, :snapshot_storage_cleanup_failed}

      {:error, reason} when reason in [:snapshot_cleanup_intent_not_found, :invalid_snapshot_cleanup_intent] ->
        {:discard, reason}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @impl Oban.Worker
  def backoff(%Oban.Job{attempt: attempt}) do
    min(300 * Integer.pow(2, max(attempt - 1, 0)), 21_600)
  end
end
