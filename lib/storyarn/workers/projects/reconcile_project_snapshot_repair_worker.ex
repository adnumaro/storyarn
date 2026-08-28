defmodule Storyarn.Workers.ReconcileProjectSnapshotRepairWorker do
  @moduledoc """
  Restores bounded delivery for pending snapshot reconciliation repairs.

  Each cron run captures a pending-action high-watermark and advances through
  it in keyset pages. Recovery reuses an exact delivery while it still has an
  attempt budget and never restarts an exhausted delivery chain.
  """

  use Oban.Worker,
    queue: :snapshots_maintenance,
    priority: 3,
    max_attempts: 5,
    unique: [
      fields: [:worker, :args],
      period: 600,
      states: [:available, :scheduled, :executing, :retryable]
    ]

  alias Storyarn.Projects

  @batch_size 50
  @timeout_ms 10 * 60 * 1_000
  @recovery_count_fields [
    :already_active_count,
    :already_terminal_count,
    :failure_count,
    :reenqueued_count,
    :requeued_count,
    :terminalized_count
  ]

  @impl Oban.Worker
  def perform(%Oban.Job{} = job) do
    perform_recovery(
      job,
      &Projects.project_snapshot_reconciliation_repair_recovery_high_watermark/0,
      &Projects.recover_project_snapshot_reconciliation_repair_delivery_page/1,
      &Oban.insert/1
    )
  end

  @doc false
  def perform_recovery(%Oban.Job{args: args}, high_watermark, recover_page, enqueue) when is_map(args) do
    if valid_callbacks?(high_watermark, recover_page, enqueue) do
      run_recovery(args, high_watermark, recover_page, enqueue)
    else
      {:discard, :invalid_snapshot_reconciliation_repair_recovery_job}
    end
  end

  def perform_recovery(%Oban.Job{}, _high_watermark, _recover_page, _enqueue),
    do: {:discard, :invalid_snapshot_reconciliation_repair_recovery_job}

  defp run_recovery(args, high_watermark, recover_page, enqueue) do
    with {:ok, after_id, through_id} <- normalize_args(args, high_watermark),
         {:ok, page} <-
           recover_page.(after_id: after_id, through_id: through_id, limit: @batch_size),
         :ok <- validate_page(page, after_id, through_id) do
      finish_valid_page(page, through_id, enqueue)
    else
      {:discard, _reason} = discard -> discard
      {:error, _reason} -> {:error, :snapshot_reconciliation_repair_recovery_failed}
      _unexpected -> {:error, :snapshot_reconciliation_repair_recovery_failed}
    end
  end

  defp valid_callbacks?(high_watermark, recover_page, enqueue),
    do: is_function(high_watermark, 0) and is_function(recover_page, 1) and is_function(enqueue, 1)

  @impl Oban.Worker
  def timeout(_job), do: @timeout_ms

  defp normalize_args(args, high_watermark) do
    after_id = Map.get(args, "after_id", 0)

    through_id =
      case Map.fetch(args, "through_id") do
        {:ok, value} -> value
        :error -> high_watermark.()
      end

    if map_size(Map.drop(args, ["after_id", "through_id"])) == 0 and is_integer(after_id) and after_id >= 0 and
         is_integer(through_id) and through_id >= after_id do
      {:ok, after_id, through_id}
    else
      {:discard, :invalid_snapshot_reconciliation_repair_recovery_job}
    end
  end

  defp validate_page(%{complete?: complete?, next_after_id: next_after_id} = page, after_id, through_id)
       when is_boolean(complete?) and is_integer(next_after_id) and next_after_id >= after_id and
              next_after_id <= through_id do
    cond do
      not valid_recovery_counts?(page) -> {:error, :invalid_snapshot_reconciliation_repair_recovery_page}
      complete? or next_after_id > after_id -> :ok
      true -> {:error, :snapshot_reconciliation_repair_recovery_cursor_stalled}
    end
  end

  defp validate_page(_page, _after_id, _through_id), do: {:error, :invalid_snapshot_reconciliation_repair_recovery_page}

  defp valid_recovery_counts?(page) do
    Enum.all?(@recovery_count_fields, fn field ->
      count = Map.get(page, field)
      is_integer(count) and count >= 0
    end)
  end

  defp ensure_page_succeeded(%{failure_count: 0}), do: :ok
  defp ensure_page_succeeded(%{failure_count: _positive}), do: {:error, :snapshot_repair_recovery_incomplete}

  defp finish_valid_page(page, through_id, enqueue) do
    {continuation_count, continuation_failure_count} =
      maybe_enqueue_continuation(page, through_id, enqueue)

    page = Map.update!(page, :failure_count, &(&1 + continuation_failure_count))
    emit_stop(page, continuation_count)

    case ensure_page_succeeded(page) do
      :ok -> :ok
      {:error, _reason} -> {:error, :snapshot_reconciliation_repair_recovery_failed}
    end
  end

  defp maybe_enqueue_continuation(%{complete?: true}, _through_id, _enqueue), do: {0, 0}

  defp maybe_enqueue_continuation(%{next_after_id: next_after_id}, through_id, enqueue) do
    %{after_id: next_after_id, through_id: through_id}
    |> new()
    |> enqueue.()
    |> case do
      {:ok, %Oban.Job{}} -> {1, 0}
      _error -> {0, 1}
    end
  end

  defp emit_stop(page, continuation_count) do
    :telemetry.execute(
      [:storyarn, :snapshot, :reconciliation, :repair, :recovery, :stop],
      %{
        requeued_count: page.requeued_count,
        reenqueued_count: page.reenqueued_count,
        already_active_count: page.already_active_count,
        terminalized_count: page.terminalized_count,
        already_terminal_count: page.already_terminal_count,
        failure_count: page.failure_count,
        continuation_count: continuation_count
      },
      %{status: if(page.failure_count == 0, do: :ok, else: :partial)}
    )
  end
end
