defmodule Storyarn.Workers.ImportProjectWorker do
  @moduledoc """
  Materializes a previously parsed import plan with durable progress.
  """

  use Oban.Worker, queue: :imports, max_attempts: 3

  alias Storyarn.Imports

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"attempt_id" => attempt_id}, attempt: attempt, max_attempts: max_attempts}) do
    case Imports.perform_import(attempt_id, attempt: attempt, max_attempts: max_attempts) do
      {:ok, _attempt} -> :ok
      {:error, _reason} -> {:error, :import_execution_failed}
    end
  end
end
