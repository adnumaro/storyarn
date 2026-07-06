defmodule Storyarn.Workers.PublishProjectTemplateWorker do
  @moduledoc """
  Publishes project templates asynchronously.

  The worker delegates business logic to `Storyarn.ProjectTemplates` so the
  context remains the source of truth for permissions, status transitions, and
  version creation.
  """

  use Oban.Worker, queue: :templates, max_attempts: 3

  alias Storyarn.ProjectTemplates

  require Logger

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"publication_id" => publication_id}, attempt: attempt, max_attempts: max_attempts}) do
    case ProjectTemplates.perform_template_publication(publication_id,
           attempt: attempt,
           max_attempts: max_attempts
         ) do
      {:ok, _publication} ->
        :ok

      {:error, reason} ->
        Logger.warning(
          "Project template publication job failed publication_id=#{publication_id} reason=#{inspect(reason)}"
        )

        {:error, reason}
    end
  end
end
