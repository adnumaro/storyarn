defmodule Storyarn.Workers.InstallProjectTemplateWorker do
  @moduledoc """
  Materializes project templates asynchronously with durable progress and retries.
  """

  use Oban.Worker, queue: :template_installs, max_attempts: 3

  alias Storyarn.ProjectTemplates

  require Logger

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"installation_id" => installation_id}, attempt: attempt, max_attempts: max_attempts}) do
    case ProjectTemplates.perform_template_installation(installation_id,
           attempt: attempt,
           max_attempts: max_attempts
         ) do
      {:ok, _installation} ->
        :ok

      {:error, reason} ->
        Logger.warning(
          "Project template installation job failed installation_id=#{installation_id} error=#{safe_error(reason)}"
        )

        {:error, reason}
    end
  end

  defp safe_error(reason) when is_atom(reason), do: reason
  defp safe_error({reason, _details}) when is_atom(reason), do: reason
  defp safe_error(_reason), do: :unexpected_error
end
