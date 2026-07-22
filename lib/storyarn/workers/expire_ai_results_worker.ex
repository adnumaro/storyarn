defmodule Storyarn.Workers.ExpireAIResultsWorker do
  @moduledoc "Purges expired encrypted AI content and abandons undecided previews."
  use Oban.Worker, queue: :ai, max_attempts: 3

  alias Storyarn.AI.Results
  alias Storyarn.AI.RouteOptions

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    Results.expire()
    RouteOptions.delete_expired()
    :ok
  end
end
