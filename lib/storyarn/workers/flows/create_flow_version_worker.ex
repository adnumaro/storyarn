defmodule Storyarn.Workers.CreateFlowVersionWorker do
  @moduledoc "Publishes a captured Flow version independently of its editor session."
  use Oban.Worker,
    queue: :flow_versions,
    max_attempts: 3,
    unique: [period: :infinity, fields: [:worker, :args], states: [:available, :scheduled, :executing, :retryable]]

  alias Storyarn.Flows

  @impl Oban.Worker
  def timeout(_job), do: to_timeout(minute: 5)

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"request_id" => id}} = job) do
    case Flows.perform_version_request(id, final_attempt: length(job.errors) + 1 >= 3) do
      {:ok, _request} -> :ok
      {:snooze, seconds} -> {:snooze, seconds}
      {:error, reason} -> {:error, reason}
      {:discard, reason} -> {:discard, reason}
    end
  end
end
