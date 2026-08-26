defmodule Storyarn.AI.Operations.Adapters.Jobs.ExecutionQueue do
  @moduledoc "Technical adapter that persists background AI execution jobs in Oban."

  alias Storyarn.Workers.AIExecutionWorker

  @spec enqueue!(pos_integer()) :: Oban.Job.t()
  def enqueue!(operation_id) do
    %{operation_id: operation_id}
    |> AIExecutionWorker.new()
    |> Oban.insert!()
  end
end
