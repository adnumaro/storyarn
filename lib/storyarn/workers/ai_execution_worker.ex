defmodule Storyarn.Workers.AIExecutionWorker do
  @moduledoc "Executes one durable AI operation without automatic inference retries."
  use Oban.Worker, queue: :ai, max_attempts: 3

  alias Storyarn.AI.Executor
  alias Storyarn.AI.Operations

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"operation_id" => operation_id}, attempt: attempt})
      when is_integer(operation_id) and operation_id > 0 do
    if attempt > 1 do
      resume_safely(operation_id)
    else
      execute_safely(operation_id)
    end
  end

  def perform(%Oban.Job{}), do: {:discard, :invalid_operation_id}

  defp resume_safely(operation_id) do
    case Operations.recover_interrupted(operation_id) do
      :ready -> execute_safely(operation_id)
      :ok -> :ok
      {:error, _reason} -> {:error, :ai_operation_recovery_failed}
    end
  end

  defp execute_safely(operation_id) do
    case Executor.run(operation_id) do
      :ok -> :ok
      {:error, _reason} -> recover_or_retry(operation_id)
    end
  rescue
    _exception -> recover_or_retry(operation_id)
  catch
    _kind, _reason -> recover_or_retry(operation_id)
  end

  defp recover_or_retry(operation_id) do
    case Operations.recover_interrupted(operation_id) do
      :ready -> {:error, :ai_execution_interrupted}
      :ok -> :ok
      {:error, _reason} -> {:error, :ai_operation_recovery_failed}
    end
  end
end
