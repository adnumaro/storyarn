defmodule Storyarn.Workers.RepairProjectSnapshotFindingWorker do
  @moduledoc """
  Applies one explicit, generation-fenced snapshot reconciliation action.

  One finding per job bounds provider work and prevents a large workspace from
  monopolizing the maintenance queue. Exits and throws are left to Oban so it
  retains their original failure class and stacktrace.
  """

  use Oban.Worker,
    queue: :snapshots_maintenance,
    priority: 3,
    max_attempts: 5,
    unique: [
      fields: [:worker, :args],
      period: :infinity,
      states: [:available, :scheduled, :executing, :retryable]
    ]

  alias Storyarn.Projects

  require Logger

  @contract_version 1
  @timeout_ms 10 * 60 * 1_000
  @recovery_margin_ms 5 * 60 * 1_000

  @impl Oban.Worker
  def perform(%Oban.Job{} = job), do: perform_action(job, &Projects.perform_project_snapshot_reconciliation_repair/1)

  @doc false
  def perform_action(
        %Oban.Job{
          args: %{"action_id" => action_id, "contract_version" => @contract_version},
          attempt: attempt,
          max_attempts: max_attempts
        },
        repair
      )
      when is_integer(action_id) and action_id > 0 and is_function(repair, 1) do
    repair
    |> call_safely(action_id)
    |> handle_result(action_id, attempt >= max_attempts)
  end

  def perform_action(%Oban.Job{}, _repair), do: {:discard, :invalid_snapshot_reconciliation_repair_job}

  @impl Oban.Worker
  def timeout(_job), do: @timeout_ms

  @doc false
  @spec recovery_after_seconds() :: pos_integer()
  def recovery_after_seconds, do: div(@timeout_ms + @recovery_margin_ms, 1_000)

  defp call_safely(repair, action_id) do
    {:returned, repair.(action_id)}
  rescue
    exception -> {:raised, exception, __STACKTRACE__}
  end

  defp handle_result({:returned, {:ok, status}}, _action_id, _final_attempt?)
       when status in [:repaired, :resolved, :manual, :failed], do: :ok

  defp handle_result({:returned, {:error, reason}}, action_id, true), do: terminalize(action_id, reason)

  defp handle_result({:returned, {:error, _reason}}, _action_id, false),
    do: {:error, :snapshot_reconciliation_repair_failed}

  defp handle_result({:returned, _invalid}, action_id, true),
    do: terminalize(action_id, :snapshot_reconciliation_invalid_repair_result)

  defp handle_result({:returned, _invalid}, _action_id, false), do: {:error, :snapshot_reconciliation_repair_failed}

  defp handle_result({:raised, exception, _stacktrace}, action_id, true),
    do: terminalize(action_id, {:snapshot_reconciliation_repair_exception, exception.__struct__})

  defp handle_result({:raised, exception, stacktrace}, _action_id, false), do: reraise(exception, stacktrace)

  defp terminalize(action_id, reason) do
    case Projects.fail_project_snapshot_reconciliation_repair(action_id, reason) do
      {:ok, status} when status in [:repaired, :resolved, :manual, :failed] ->
        :ok

      {:error, _failure_reason} ->
        Logger.error("Snapshot reconciliation repair could not persist terminal evidence action_id=#{action_id}")
        {:error, :snapshot_reconciliation_repair_terminal_evidence_not_persisted}
    end
  end
end
