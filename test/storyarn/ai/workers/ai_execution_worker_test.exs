defmodule Storyarn.Workers.AIExecutionWorkerTest do
  use ExUnit.Case, async: true

  alias Storyarn.Workers.AIExecutionWorker

  test "terminalizes a queued operation when the final recovery attempt fails" do
    test_pid = self()

    recover = fn operation_id ->
      send(test_pid, {:recovered, operation_id})
      :ready
    end

    execute = fn operation_id ->
      send(test_pid, {:executed, operation_id})
      raise "database unavailable before claim"
    end

    terminalize = fn operation_id, reason ->
      send(test_pid, {:terminalized, operation_id, reason})
      :ok
    end

    job = %Oban.Job{args: %{"operation_id" => 42}, attempt: 3, max_attempts: 3}

    assert :ok = AIExecutionWorker.perform_operation(job, recover, execute, terminalize)
    assert_receive {:recovered, 42}
    assert_receive {:executed, 42}
    assert_receive {:recovered, 42}
    assert_receive {:terminalized, 42, :worker_retries_exhausted}
  end

  test "returns an error while a retry remains and leaves the operation recoverable" do
    test_pid = self()
    recover = fn _operation_id -> :ready end
    execute = fn _operation_id -> {:error, :temporary_database_failure} end

    terminalize = fn operation_id, reason ->
      send(test_pid, {:unexpected_terminalization, operation_id, reason})
      :ok
    end

    job = %Oban.Job{args: %{"operation_id" => 42}, attempt: 2, max_attempts: 3}

    assert {:error, :ai_execution_interrupted} =
             AIExecutionWorker.perform_operation(job, recover, execute, terminalize)

    refute_receive {:unexpected_terminalization, _, _}
  end
end
