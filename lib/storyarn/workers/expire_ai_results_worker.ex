defmodule Storyarn.Workers.ExpireAIResultsWorker do
  @moduledoc "Purges expired encrypted AI content and abandons undecided previews."
  use Oban.Worker, queue: :ai, max_attempts: 3

  alias Storyarn.AI.Results
  alias Storyarn.AI.RouteOptions

  require Logger

  @event [:storyarn, :ai, :expiration, :stop]

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    perform_expiration(&Results.expire/0, &schedule_followup/0)
  end

  @doc false
  def perform_expiration(expire_results, schedule_followup)
      when is_function(expire_results, 0) and is_function(schedule_followup, 0) do
    started_at = System.monotonic_time()

    try do
      handle_expiration_result(expire_results.(), schedule_followup, started_at)
    rescue
      exception ->
        emit_stop(started_at, 0, 1, :exception)
        reraise exception, __STACKTRACE__
    end
  end

  defp handle_expiration_result(
         {:ok, %{expired_count: expired_count, failure_count: failure_count, more?: more?}},
         schedule_followup,
         started_at
       )
       when is_integer(expired_count) and expired_count >= 0 and is_integer(failure_count) and failure_count >= 0 and
              is_boolean(more?) do
    RouteOptions.delete_expired()
    maybe_schedule_followup(more?, schedule_followup)
    finish_batch(started_at, expired_count, failure_count)
  end

  defp handle_expiration_result(_unexpected, _schedule_followup, started_at) do
    emit_stop(started_at, 0, 1, :error)
    Logger.warning("AI result expiration returned an unexpected result")
    {:error, :ai_result_expiration_failed}
  end

  defp maybe_schedule_followup(true, schedule_followup), do: schedule_followup.()
  defp maybe_schedule_followup(false, _schedule_followup), do: :ok

  defp finish_batch(started_at, expired_count, 0) do
    emit_stop(started_at, expired_count, 0, :ok)
    :ok
  end

  defp finish_batch(started_at, expired_count, failure_count) do
    emit_stop(started_at, expired_count, failure_count, :error)
    Logger.warning("AI result expiration batch had #{failure_count} failed rows")
    {:error, :ai_result_expiration_failed}
  end

  defp schedule_followup do
    %{}
    |> new(schedule_in: 1)
    |> Oban.insert()
  end

  defp emit_stop(started_at, expired_count, failure_count, status) do
    :telemetry.execute(
      @event,
      %{
        expired_count: expired_count,
        failure_count: failure_count,
        duration: System.monotonic_time() - started_at
      },
      %{status: status}
    )
  end
end
