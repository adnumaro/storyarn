defmodule Storyarn.Workers.InspectProjectSnapshotsWorker do
  @moduledoc """
  Advances one low-priority, observation-only snapshot reconciliation page.

  Runs are started explicitly by an operator. Continuations carry the durable
  cursor generation, so overlapping or retried jobs cannot regress progress or
  duplicate findings.
  """

  use Oban.Worker,
    queue: :snapshots_maintenance,
    priority: 3,
    max_attempts: 5,
    unique: [
      fields: [:worker, :args],
      period: 86_400,
      states: [:available, :scheduled, :executing, :retryable]
    ]

  alias Storyarn.Versioning

  require Logger

  @contract_version 1
  @timeout_ms 10 * 60 * 1_000
  @recovery_margin_ms 5 * 60 * 1_000

  @impl Oban.Worker
  def perform(%Oban.Job{} = job), do: perform_page(job, &Versioning.advance_project_snapshot_reconciliation/2)

  @doc false
  def perform_page(
        %Oban.Job{
          args: %{"contract_version" => @contract_version, "cursor_generation" => cursor_generation, "run_id" => run_id},
          attempt: attempt,
          max_attempts: max_attempts
        },
        advance
      )
      when is_integer(run_id) and run_id > 0 and is_integer(cursor_generation) and cursor_generation > 0 and
             is_function(advance, 2) do
    advance
    |> advance_safely(run_id, cursor_generation)
    |> handle_advance_result(run_id, cursor_generation, attempt >= max_attempts)
  end

  def perform_page(%Oban.Job{}, _advance), do: {:discard, :invalid_snapshot_reconciliation_job}

  defp advance_safely(advance, run_id, cursor_generation) do
    {:returned, advance.(run_id, cursor_generation)}
  catch
    kind, reason -> {:raised, kind, reason, __STACKTRACE__}
  end

  defp handle_advance_result({:returned, {:ok, status}}, _run_id, _cursor_generation, _final_attempt?)
       when status in [:completed, :failed], do: :ok

  defp handle_advance_result({:returned, {:ok, status, _next_generation}}, _run_id, _cursor_generation, _final_attempt?)
       when status in [:continue, :stale], do: :ok

  defp handle_advance_result({:returned, {:error, reason}}, run_id, cursor_generation, true),
    do: terminalize(run_id, cursor_generation, reason)

  defp handle_advance_result({:returned, {:error, _reason}}, _run_id, _cursor_generation, false),
    do: {:error, :snapshot_reconciliation_page_failed}

  defp handle_advance_result({:returned, _unexpected}, run_id, cursor_generation, true),
    do: terminalize(run_id, cursor_generation, :snapshot_reconciliation_invalid_page_result)

  defp handle_advance_result({:returned, _unexpected}, _run_id, _cursor_generation, false),
    do: {:error, :snapshot_reconciliation_page_failed}

  defp handle_advance_result({:raised, _kind, _reason, _stacktrace}, run_id, cursor_generation, true),
    do: terminalize(run_id, cursor_generation, :snapshot_reconciliation_page_exception)

  defp handle_advance_result({:raised, kind, reason, stacktrace}, _run_id, _cursor_generation, false),
    do: :erlang.raise(kind, reason, stacktrace)

  @impl Oban.Worker
  def timeout(_job), do: @timeout_ms

  @doc false
  @spec recovery_after_seconds() :: pos_integer()
  def recovery_after_seconds, do: div(@timeout_ms + @recovery_margin_ms, 1_000)

  defp terminalize(run_id, cursor_generation, reason) do
    case Versioning.fail_project_snapshot_reconciliation(run_id, cursor_generation, reason) do
      {:ok, status} when status in [:failed, :stale, :completed] ->
        :ok

      {:error, _failure_reason} ->
        Logger.error("Snapshot reconciliation could not persist terminal evidence run_id=#{run_id}")
        {:error, :snapshot_reconciliation_terminal_evidence_not_persisted}
    end
  end
end
