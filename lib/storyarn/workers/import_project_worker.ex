defmodule Storyarn.Workers.ImportProjectWorker do
  @moduledoc """
  Materializes a previously parsed import plan with durable progress.
  """

  @max_attempts 3
  use Oban.Worker, queue: :imports, max_attempts: @max_attempts

  alias Storyarn.Projects.Imports

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

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"attempt_id" => attempt_id}} = job) do
    case Imports.perform_import(attempt_id,
           attempt: canonical_attempt(job),
           max_attempts: @max_attempts
         ) do
      {:ok, _attempt} -> :ok
      {:snooze, seconds} -> {:snooze, seconds}
      {:error, _reason} -> {:error, :import_execution_failed}
    end
  end
end
