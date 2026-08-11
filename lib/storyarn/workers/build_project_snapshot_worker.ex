defmodule Storyarn.Workers.BuildProjectSnapshotWorker do
  @moduledoc """
  Executes one durable full-snapshot build outside the LiveView process.
  """

  @max_attempts 5
  use Oban.Worker,
    queue: :snapshot_archives,
    max_attempts: @max_attempts,
    unique: [
      fields: [:worker, :args],
      period: :infinity,
      states: [:available, :scheduled, :executing, :retryable]
    ]

  alias Storyarn.Versioning

  @impl Oban.Worker
  def backoff(%Oban.Job{attempt: attempt, max_attempts: max_attempts} = job) do
    logical_attempt =
      @max_attempts
      |> Kernel.-(max_attempts - attempt)
      |> max(1)
      |> min(@max_attempts)

    Oban.Worker.backoff(%{job | attempt: logical_attempt, max_attempts: @max_attempts})
  end

  @impl Oban.Worker
  def perform(%Oban.Job{id: job_id, args: %{"snapshot_id" => snapshot_id}} = job) do
    heartbeat = Task.async(fn -> heartbeat_loop(snapshot_id, job_id) end)

    try do
      perform_build(job)
    after
      Task.shutdown(heartbeat, :brutal_kill)
    end
  end

  defp perform_build(%Oban.Job{
         id: job_id,
         args: %{"snapshot_id" => snapshot_id},
         attempt: attempt,
         max_attempts: max_attempts
       }) do
    case Versioning.perform_project_snapshot_build(snapshot_id,
           job_id: job_id,
           attempt: attempt,
           max_attempts: max_attempts
         ) do
      {:ok, _snapshot} -> :ok
      {:retry, reason} -> {:error, reason}
      {:snooze, seconds} -> {:snooze, seconds}
      {:discard, reason} -> {:discard, reason}
    end
  end

  defp heartbeat_loop(snapshot_id, job_id) do
    receive do
      :stop -> :ok
    after
      Versioning.project_snapshot_build_heartbeat_interval_ms() ->
        case Versioning.heartbeat_project_snapshot_build(snapshot_id, job_id) do
          :ok -> heartbeat_loop(snapshot_id, job_id)
          {:error, reason} -> exit({:snapshot_build_heartbeat_failed, reason})
        end
    end
  end
end
