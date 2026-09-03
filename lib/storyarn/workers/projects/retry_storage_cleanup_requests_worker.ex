defmodule Storyarn.Workers.RetryStorageCleanupRequestsWorker do
  @moduledoc """
  Retries durable copied-asset cleanup requests that could not be enqueued directly.
  """

  # The window must stay strictly below the `*/15` cron interval this is
  # scheduled at. It previously ran at `* * * * *` with a 120s window — double
  # its own schedule — so it deduped every other tick by construction and the
  # declared once-a-minute cadence was fiction. 600s is honest against `*/15`.
  use Oban.Worker,
    queue: :storage_cleanup,
    max_attempts: 5,
    unique: [period: 600, states: [:available, :scheduled, :executing, :retryable]]

  alias Storyarn.Projects

  require Logger

  @impl Oban.Worker
  def perform(%Oban.Job{} = job) do
    perform_with(
      job,
      &Projects.enqueue_due_cleanup_request_jobs/0,
      &Projects.emit_storage_cleanup_request_backlog/0
    )
  end

  @doc false
  def perform_with(%Oban.Job{attempt: attempt, max_attempts: max_attempts}, retry_fun, emit_backlog_fun)
      when is_function(retry_fun, 0) and is_function(emit_backlog_fun, 0) do
    result =
      case call_retry_safely(retry_fun) do
        :ok ->
          :ok

        {:error, failed_count} when is_integer(failed_count) and failed_count >= 0 ->
          log_failure(failed_count, attempt, max_attempts)
          {:error, :storage_cleanup_failed}

        {:error, :retry_call_failed} ->
          {:error, :storage_cleanup_failed}

        _unexpected ->
          Logger.error("Persisted copied asset cleanup returned an invalid result")
          {:error, :storage_cleanup_failed}
      end

    emit_backlog(emit_backlog_fun)
    result
  end

  defp call_retry_safely(retry_fun) do
    retry_fun.()
  rescue
    exception ->
      Logger.error("Persisted copied asset cleanup failed exception_module=#{inspect(exception.__struct__)}")

      {:error, :retry_call_failed}
  catch
    kind, _reason ->
      Logger.error("Persisted copied asset cleanup failed failure_kind=#{inspect(kind)}")
      {:error, :retry_call_failed}
  end

  defp emit_backlog(emit_backlog_fun) do
    emit_backlog_fun.()
  rescue
    exception ->
      Logger.error("Storage cleanup backlog telemetry failed exception_module=#{inspect(exception.__struct__)}")
      :ok
  catch
    kind, _reason ->
      Logger.error("Storage cleanup backlog telemetry failed failure_kind=#{inspect(kind)}")
      :ok
  end

  defp log_failure(failed_count, attempt, max_attempts) when attempt >= max_attempts do
    Logger.error("Persisted copied asset cleanup exhausted retries failed_count=#{failed_count}")
  end

  defp log_failure(failed_count, _attempt, _max_attempts) do
    Logger.warning("Persisted copied asset cleanup will retry failed_count=#{failed_count}")
  end
end
