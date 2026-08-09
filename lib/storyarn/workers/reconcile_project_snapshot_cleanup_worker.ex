defmodule Storyarn.Workers.ReconcileProjectSnapshotCleanupWorker do
  @moduledoc """
  Recovers durable snapshot cleanup intents whose owning Oban job disappeared
  or reached a dead state before completing its inventory.

  Each run captures a high-watermark and advances in bounded keyset pages, so
  concurrent cleanup creation cannot make a recovery run unbounded.
  """

  use Oban.Worker,
    queue: :snapshots_maintenance,
    max_attempts: 5,
    unique: [fields: [:worker, :args], period: 600, states: [:available, :scheduled, :executing, :retryable]]

  alias Storyarn.Versioning

  require Logger

  @batch_size 50
  @timeout_ms 10 * 60 * 1_000

  @impl Oban.Worker
  def perform(%Oban.Job{args: args, attempt: attempt, max_attempts: max_attempts}) do
    Versioning.discard_stale_project_snapshot_maintenance_jobs()
    Versioning.rescue_stale_project_snapshot_cleanup_jobs()

    after_id = Map.get(args, "after_id", 0)
    through_id = Map.get(args, "through_id") || Versioning.project_snapshot_cleanup_recovery_high_watermark()

    intent_ids =
      Versioning.list_project_snapshot_cleanup_recovery_candidates(
        after_id: after_id,
        through_id: through_id,
        limit: @batch_size
      )

    {recovered_count, skipped_count, failure_count} = recover_intents(intent_ids)

    {continuation_count, continuation_failure_count} =
      maybe_enqueue_continuation(intent_ids, after_id, through_id)

    failure_count = failure_count + continuation_failure_count
    emit_stop(recovered_count, skipped_count, failure_count, continuation_count)

    if continuation_count == 0, do: emit_backlog()

    if failure_count == 0 do
      :ok
    else
      log_failure(failure_count, attempt, max_attempts)
      {:error, :snapshot_cleanup_recovery_incomplete}
    end
  end

  @impl Oban.Worker
  def timeout(_job), do: @timeout_ms

  defp recover_intents(intent_ids) do
    Enum.reduce(intent_ids, {0, 0, 0}, fn intent_id, {recovered, skipped, failed} ->
      case Versioning.recover_project_snapshot_cleanup_intent(intent_id) do
        {:ok, :recovered} ->
          {recovered + 1, skipped, failed}

        {:ok, status} when status in [:already_active, :already_completed, :terminal] ->
          {recovered, skipped + 1, failed}

        {:error, _reason} ->
          {recovered, skipped, failed + 1}
      end
    end)
  end

  defp maybe_enqueue_continuation(intent_ids, after_id, through_id) do
    next_after_id = next_after_id(intent_ids, after_id)

    if intent_ids != [] and next_after_id < through_id do
      %{after_id: next_after_id, through_id: through_id}
      |> new()
      |> Oban.insert()
      |> case do
        {:ok, _job} -> {1, 0}
        {:error, _reason} -> {0, 1}
      end
    else
      {0, 0}
    end
  end

  defp next_after_id([], after_id), do: after_id
  defp next_after_id(intent_ids, _after_id), do: List.last(intent_ids)

  defp emit_stop(recovered_count, skipped_count, failure_count, continuation_count) do
    :telemetry.execute(
      [:storyarn, :snapshot, :cleanup, :recovery, :stop],
      %{
        recovered_count: recovered_count,
        skipped_count: skipped_count,
        failure_count: failure_count,
        continuation_count: continuation_count
      },
      %{status: if(failure_count == 0, do: :ok, else: :partial)}
    )
  end

  defp emit_backlog do
    backlog = Versioning.project_snapshot_cleanup_backlog()

    :telemetry.execute(
      [:storyarn, :snapshot, :cleanup, :backlog],
      %{
        backlog_count: backlog.backlog_count,
        backlog_bytes: backlog.backlog_bytes,
        retry_count: backlog.retry_count,
        terminal_failures: backlog.terminal_failures,
        terminal_retry_count: backlog.terminal_retry_count,
        repeated_terminal_failures: backlog.repeated_terminal_failures,
        oldest_age_seconds: backlog.oldest_age_seconds
      },
      %{}
    )
  end

  defp log_failure(failure_count, attempt, max_attempts) when attempt >= max_attempts do
    Logger.error("Snapshot cleanup recovery exhausted retries failure_count=#{failure_count}")
  end

  defp log_failure(failure_count, _attempt, _max_attempts) do
    Logger.warning("Snapshot cleanup recovery will retry failure_count=#{failure_count}")
  end
end
