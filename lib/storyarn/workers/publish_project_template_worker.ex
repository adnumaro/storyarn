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

  @lock_snooze_seconds 30

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"publication_id" => publication_id}, attempt: attempt, max_attempts: max_attempts}) do
    result =
      ProjectTemplates.perform_template_publication(publication_id,
        attempt: attempt,
        max_attempts: max_attempts
      )

    handle_perform_result(result, publication_id)
  rescue
    DBConnection.ConnectionError ->
      Logger.warning(
        "Project template publication database connection unavailable; snoozing publication_id=#{publication_id}"
      )

      {:snooze, @lock_snooze_seconds}
  end

  @doc false
  def handle_perform_result({:ok, _publication}, _publication_id), do: :ok

  def handle_perform_result({:error, :session_lock_timeout}, publication_id) do
    Logger.warning("Project template publication lock unavailable; snoozing publication_id=#{publication_id}")

    {:snooze, @lock_snooze_seconds}
  end

  def handle_perform_result({:error, reason}, publication_id) do
    Logger.warning("Project template publication job failed publication_id=#{publication_id} reason=#{inspect(reason)}")

    {:error, reason}
  end
end
