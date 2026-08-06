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

  @impl Oban.Worker
  def perform(%Oban.Job{
        args: %{"contract_version" => @contract_version, "cursor_generation" => cursor_generation, "run_id" => run_id},
        attempt: attempt,
        max_attempts: max_attempts
      })
      when is_integer(run_id) and run_id > 0 and is_integer(cursor_generation) and cursor_generation > 0 do
    case Versioning.advance_project_snapshot_reconciliation(run_id, cursor_generation) do
      {:ok, status} when status in [:completed, :failed] ->
        :ok

      {:ok, status, _next_generation} when status in [:continue, :stale] ->
        :ok

      {:error, reason} when attempt >= max_attempts ->
        terminalize(run_id, cursor_generation, reason)

      {:error, _reason} ->
        {:error, :snapshot_reconciliation_page_failed}
    end
  end

  def perform(%Oban.Job{}), do: {:discard, :invalid_snapshot_reconciliation_job}

  @impl Oban.Worker
  def timeout(_job), do: @timeout_ms

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
