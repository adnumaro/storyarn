defmodule Storyarn.Workers.BuildProjectSnapshotWorker do
  @moduledoc """
  Executes one durable full-snapshot build outside the LiveView process.
  """

  use Oban.Worker,
    queue: :snapshots,
    max_attempts: 5,
    unique: [
      fields: [:worker, :args],
      period: :infinity,
      states: [:available, :scheduled, :executing, :retryable]
    ]

  alias Storyarn.Versioning

  @impl Oban.Worker
  def perform(%Oban.Job{id: job_id, args: %{"snapshot_id" => snapshot_id}, attempt: attempt, max_attempts: max_attempts}) do
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
end
