defmodule Storyarn.Workers.AIExecutionWorker do
  @moduledoc "Executes one durable AI operation without automatic inference retries."
  use Oban.Worker, queue: :ai, max_attempts: 3

  alias Storyarn.AI

  @impl Oban.Worker
  def perform(%Oban.Job{} = job), do: AI.run_execution_job(job)

  @doc false
  def perform_operation(%Oban.Job{args: %{"operation_id" => operation_id}} = job, recover, execute, terminalize)
      when is_integer(operation_id) and operation_id > 0 do
    AI.run_execution_job_with(job, recover, execute, terminalize)
  end

  def perform_operation(%Oban.Job{} = job, recover, execute, terminalize),
    do: AI.run_execution_job_with(job, recover, execute, terminalize)
end
