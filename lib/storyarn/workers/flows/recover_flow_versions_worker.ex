defmodule Storyarn.Workers.RecoverFlowVersionsWorker do
  @moduledoc "Recovers interrupted version writes on the Flow-owned queue."
  use Oban.Worker,
    queue: :flow_versions,
    max_attempts: 3,
    unique: [period: 900, states: [:available, :scheduled, :executing, :retryable]]

  @impl Oban.Worker
  def perform(_job), do: Storyarn.Flows.recover_version_requests()
end
