defmodule Storyarn.Workers.DeleteProjectTemplateArtifactsWorker do
  @moduledoc """
  Deletes storage artifacts for hard-deleted project templates.
  """

  use Oban.Worker, queue: :templates, max_attempts: 5

  alias Storyarn.ProjectTemplates

  require Logger

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"storage_keys" => storage_keys}}) do
    case ProjectTemplates.perform_template_artifact_gc(storage_keys) do
      :ok ->
        :ok

      {:error, reason} ->
        Logger.warning("Project template artifact GC failed reason=#{inspect(reason)}")
        {:error, reason}
    end
  end
end
