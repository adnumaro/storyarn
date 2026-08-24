defmodule Storyarn.Projects.Imports.Queue do
  @moduledoc """
  Waking the imports queue and telling the page about an attempt.

  Both signals are best-effort by design. The durable attempt row and the Oban
  job are the source of truth; a lost notification costs latency, never work.
  """

  alias Storyarn.Projects.Imports.Error
  alias Storyarn.Projects.Imports.ProjectImportAttempt

  @doc """
  Signals the imports queue that work is available.

  `Oban.insert/1` runs inside the attempt transaction, and the configured PG
  notifier has no transactional delivery guarantee: its insert signal can arrive
  before the job is visible on another connection. Callers therefore send this
  second signal **after** the outer commit. The job stays durable either way —
  for a lost wake on a fresh import the prompt net is Oban's stager interval,
  and the expiry sweep additionally wakes `available` jobs whose attempts have
  aged past the rolling retention window.
  """
  @spec wake(ProjectImportAttempt.t(), keyword()) :: :ok
  def wake(%ProjectImportAttempt{} = attempt, opts \\ []) do
    notifier =
      Keyword.get(opts, :queue_notifier, fn payload ->
        Oban.Notifier.notify(Oban, :insert, payload)
      end)

    case safely_notify(notifier) do
      :ok ->
        :ok

      :error ->
        Error.report(%{
          format: attempt.format,
          parser_version: attempt.parser_version,
          import_mode: attempt.import_mode,
          phase: "queue_wakeup",
          error_code: "queue_wakeup_failed",
          exception_module: "none"
        })
    end
  end

  defp safely_notify(notifier) when is_function(notifier, 1) do
    case notifier.(%{queue: "imports"}) do
      :ok -> :ok
      _failure -> :error
    end
  rescue
    _exception -> :error
  catch
    _kind, _reason -> :error
  end

  defp safely_notify(_invalid_notifier), do: :error

  @doc "Subscribes the caller to every import transition in a project."
  @spec subscribe(pos_integer()) :: :ok | {:error, term()}
  def subscribe(project_id) do
    Phoenix.PubSub.subscribe(Storyarn.PubSub, topic(project_id))
  end

  @doc "Announces an attempt transition. Delivery is ephemeral; resume is not."
  @spec broadcast(ProjectImportAttempt.t()) :: :ok
  def broadcast(%ProjectImportAttempt{} = attempt) do
    Phoenix.PubSub.broadcast(
      Storyarn.PubSub,
      topic(attempt.project_id),
      {:project_import_updated, attempt}
    )
  end

  @doc false
  @spec topic(pos_integer()) :: String.t()
  def topic(project_id), do: "project_imports:project:#{project_id}"
end
