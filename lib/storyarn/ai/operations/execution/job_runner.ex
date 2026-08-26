defmodule Storyarn.AI.Operations.Execution.JobRunner do
  @moduledoc """
  Applies the durable retry and recovery policy for one queued AI operation.

  Oban owns delivery attempts; this module owns what those attempts mean for an
  AI operation and prevents a second external provider attempt after recovery.
  """

  alias Storyarn.AI.Executor
  alias Storyarn.AI.Operations.Commands.Lifecycle

  @spec run(Oban.Job.t()) :: :ok | {:error, atom()} | {:discard, atom()}
  def run(%Oban.Job{} = job) do
    run_with(
      job,
      &Lifecycle.recover_interrupted/1,
      &Executor.run/1,
      &Lifecycle.fail_queued_after_retries/2
    )
  end

  @doc false
  def run_with(
        %Oban.Job{args: %{"operation_id" => operation_id}, attempt: attempt, max_attempts: max_attempts},
        recover,
        execute,
        terminalize
      )
      when is_integer(operation_id) and operation_id > 0 do
    final_attempt? = attempt >= max_attempts

    if attempt > 1 do
      resume_safely(operation_id, final_attempt?, recover, execute, terminalize)
    else
      execute_safely(operation_id, final_attempt?, recover, execute, terminalize)
    end
  end

  def run_with(%Oban.Job{}, _recover, _execute, _terminalize), do: {:discard, :invalid_operation_id}

  defp resume_safely(operation_id, final_attempt?, recover, execute, terminalize) do
    case recover.(operation_id) do
      :ready -> execute_safely(operation_id, final_attempt?, recover, execute, terminalize)
      :ok -> :ok
      {:error, _reason} -> {:error, :ai_operation_recovery_failed}
    end
  end

  defp execute_safely(operation_id, final_attempt?, recover, execute, terminalize) do
    case execute.(operation_id) do
      :ok -> :ok
      {:error, _reason} -> recover_or_retry(operation_id, final_attempt?, recover, terminalize)
    end
  rescue
    _exception -> recover_or_retry(operation_id, final_attempt?, recover, terminalize)
  catch
    _kind, _reason -> recover_or_retry(operation_id, final_attempt?, recover, terminalize)
  end

  defp recover_or_retry(operation_id, final_attempt?, recover, terminalize) do
    case recover.(operation_id) do
      :ready when final_attempt? -> terminalize.(operation_id, :worker_retries_exhausted)
      :ready -> {:error, :ai_execution_interrupted}
      :ok -> :ok
      {:error, _reason} -> {:error, :ai_operation_recovery_failed}
    end
  end
end
