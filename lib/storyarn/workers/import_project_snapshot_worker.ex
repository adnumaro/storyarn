defmodule Storyarn.Workers.ImportProjectSnapshotWorker do
  @moduledoc "Executes one durable workspace project-snapshot import."

  @max_attempts 3
  use Oban.Worker,
    queue: :snapshot_imports,
    max_attempts: @max_attempts,
    unique: [
      fields: [:worker, :args],
      period: :infinity,
      states: [:available, :scheduled, :executing, :retryable]
    ]

  alias Storyarn.Projects.Versioning

  @impl Oban.Worker
  def perform(%Oban.Job{id: job_id, args: %{"import_id" => import_id}, attempt: attempt, max_attempts: max_attempts}) do
    import_id
    |> Versioning.perform_workspace_snapshot_import(
      job_id: job_id,
      attempt: attempt,
      max_attempts: max_attempts
    )
    |> handle_result()
  end

  def perform(%Oban.Job{}), do: {:discard, :invalid_workspace_snapshot_import_job}

  @doc false
  def max_attempts, do: @max_attempts

  defp handle_result({:ok, _import}), do: :ok
  defp handle_result({:retry, reason}), do: {:error, reason}
  defp handle_result({:snooze, seconds}), do: {:snooze, seconds}
  defp handle_result({:discard, reason}), do: {:discard, reason}
end
