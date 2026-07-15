defmodule Storyarn.Workers.ExpireProjectImportsWorker do
  @moduledoc """
  Removes encrypted plans for previews that were never executed.
  """

  use Oban.Worker, queue: :imports, max_attempts: 3

  alias Storyarn.Imports

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    {:ok, _expired_count} = Imports.expire_stale_imports()
    :ok
  end
end
