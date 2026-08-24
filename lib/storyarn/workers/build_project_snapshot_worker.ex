defmodule Storyarn.Workers.BuildProjectSnapshotWorker do
  @moduledoc """
  Executes one durable full-snapshot build outside the LiveView process.
  """

  @max_attempts 3
  use Oban.Worker,
    queue: :snapshot_archives,
    max_attempts: @max_attempts,
    unique: [
      fields: [:worker, :args],
      period: :infinity,
      states: [:available, :scheduled, :executing, :retryable]
    ]

  alias Storyarn.Projects.Versioning

  @impl Oban.Worker
  def backoff(%Oban.Job{} = job) do
    logical_attempt = canonical_attempt(job)
    Oban.Worker.backoff(%{job | attempt: logical_attempt, max_attempts: @max_attempts})
  end

  @doc false
  def canonical_attempt(%Oban.Job{errors: errors}) when is_list(errors) do
    errors
    |> length()
    |> Kernel.+(1)
    |> min(@max_attempts)
  end

  @doc false
  def max_attempts, do: @max_attempts

  @impl Oban.Worker
  def perform(%Oban.Job{id: job_id, args: %{"snapshot_id" => snapshot_id}} = job) do
    heartbeat = Task.async(fn -> heartbeat_loop(snapshot_id, job_id) end)

    try do
      perform_build(job)
    after
      Task.shutdown(heartbeat, :brutal_kill)
    end
  end

  defp perform_build(
         %Oban.Job{id: job_id, args: %{"snapshot_id" => snapshot_id}, attempt: _attempt, max_attempts: _max_attempts} =
           job
       ) do
    attempt = canonical_attempt(job)

    case Versioning.perform_project_snapshot_build(snapshot_id,
           job_id: job_id,
           attempt: attempt,
           max_attempts: @max_attempts
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
