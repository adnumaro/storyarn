defmodule Storyarn.Workers.RestoreProjectSnapshotWorker do
  @moduledoc """
  Executes one generation-fenced, durable project-snapshot restore.
  """

  use Oban.Worker,
    queue: :snapshot_restores,
    max_attempts: 5,
    unique: [
      fields: [:worker, :args],
      period: :infinity,
      states: [:available, :scheduled, :executing, :retryable]
    ]

  alias Storyarn.Projects

  @impl Oban.Worker
  def perform(%Oban.Job{
        id: job_id,
        args: %{"restore_id" => restore_id, "generation" => generation},
        attempt: attempt,
        max_attempts: max_attempts
      }) do
    restore_id
    |> Projects.perform_project_snapshot_restore(generation,
      job_id: job_id,
      attempt: attempt,
      max_attempts: max_attempts
    )
    |> handle_result()
  end

  def perform(%Oban.Job{}), do: {:discard, :invalid_project_snapshot_restore_job}

  defp handle_result({:ok, _restore}), do: :ok
  defp handle_result({:retry, reason}), do: {:error, reason}
  defp handle_result({:snooze, seconds}), do: {:snooze, seconds}
  defp handle_result({:discard, reason}), do: {:discard, reason}
end
