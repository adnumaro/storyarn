defmodule Storyarn.Projects.Workers.CleanupProjectSnapshotWorker do
  @moduledoc """
  Deletes one bounded batch from a durable snapshot cleanup intent.

  Duplicate delivery is safe: missing objects are successful deletes and the
  intent's remaining inventory can only shrink.
  """

  use Oban.Worker,
    queue: :storage_cleanup,
    max_attempts: 10,
    unique: [
      fields: [:worker, :queue, :args],
      period: :infinity,
      states: [:available, :scheduled, :executing, :retryable]
    ]

  alias Storyarn.Projects.Versioning

  require Logger

  @timeout_ms 2 * 60 * 60 * 1_000

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"intent_id" => intent_id} = args, attempt: attempt, max_attempts: max_attempts}) do
    case Versioning.process_project_snapshot_cleanup_intent(intent_id,
           final_attempt?: attempt >= max_attempts
         ) do
      {:ok, :more} ->
        enqueue_continuation(args, Map.get(args, "continuation", 0) + 1)

      {:ok, {:deferred, seconds}} ->
        {:snooze, seconds}

      {:ok, :terminal} ->
        log_terminal_failure(intent_id)
        :ok

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

  @impl Oban.Worker
  def timeout(_job), do: @timeout_ms

  defp enqueue_continuation(args, continuation) do
    args
    |> Map.take(["intent_id", "replay_token"])
    |> Map.put("continuation", continuation)
    |> new()
    |> Oban.insert()
    |> case do
      {:ok, _job} -> :ok
      {:error, reason} -> {:error, {:snapshot_cleanup_continuation_not_enqueued, reason}}
    end
  end

  defp log_terminal_failure(intent_id) do
    case Versioning.project_snapshot_cleanup_operator_action(intent_id) do
      {:ok, :replay} ->
        Logger.error(
          "Snapshot cleanup exhausted retries intent_id=#{intent_id} " <>
            "operator_replay=Storyarn.Projects.Versioning.replay_terminal_project_snapshot_cleanup(#{intent_id})"
        )

      {:ok, {:manual_repair_required, code}} ->
        Logger.error(
          "Snapshot cleanup integrity failure requires manual repair intent_id=#{intent_id} " <>
            "error_code=#{code} automatic_replay=disabled"
        )

      {:error, reason} ->
        Logger.error(
          "Snapshot cleanup terminal state could not be inspected intent_id=#{intent_id} " <>
            "inspection_error=#{inspect(reason)}"
        )
    end
  end
end
