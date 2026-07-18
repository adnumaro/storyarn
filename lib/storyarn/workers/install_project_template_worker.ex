defmodule Storyarn.Workers.InstallProjectTemplateWorker do
  @moduledoc """
  Materializes project templates asynchronously with durable progress and retries.
  """

  use Oban.Worker, queue: :template_installs, max_attempts: 3

  alias Storyarn.ProjectTemplates

  require Logger

  @lock_snooze_seconds 30

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"installation_id" => installation_id}, attempt: attempt, max_attempts: max_attempts}) do
    result =
      ProjectTemplates.perform_template_installation(installation_id,
        attempt: attempt,
        max_attempts: max_attempts
      )

    handle_perform_result(result, installation_id)
  rescue
    DBConnection.ConnectionError ->
      Logger.warning(
        "Project template installation database connection unavailable; snoozing installation_id=#{installation_id}"
      )

      {:snooze, @lock_snooze_seconds}
  end

  @doc false
  def handle_perform_result({:ok, _installation}, _installation_id), do: :ok

  def handle_perform_result({:error, :session_lock_timeout}, installation_id) do
    Logger.warning("Project template installation lock unavailable; snoozing installation_id=#{installation_id}")

    {:snooze, @lock_snooze_seconds}
  end

  def handle_perform_result({:error, reason}, installation_id) do
    Logger.warning(
      "Project template installation job failed installation_id=#{installation_id} error=#{safe_error(reason)}"
    )

    {:error, reason}
  end

  defp safe_error(reason) when is_atom(reason), do: reason
  defp safe_error({reason, _details}) when is_atom(reason), do: reason
  defp safe_error(_reason), do: :unexpected_error
end
