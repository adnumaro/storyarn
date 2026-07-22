defmodule Storyarn.Workers.AIExecutionWorker do
  @moduledoc "Executes one durable AI operation without automatic inference retries."
  use Oban.Worker, queue: :ai, max_attempts: 1

  alias Storyarn.AI.Executor

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"operation_id" => operation_id}}) when is_integer(operation_id) and operation_id > 0 do
    Executor.run(operation_id)
  end

  def perform(%Oban.Job{}), do: {:discard, :invalid_operation_id}
end
