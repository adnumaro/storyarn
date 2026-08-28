defmodule Storyarn.Workers.ExpireProjectImportsWorker do
  @moduledoc """
  Reconciles stale import attempts, enforces the absolute encrypted-plan
  retention deadline, and retries any incomplete cleanup without exposing
  import identifiers in telemetry.
  """

  # Sits on `:imports_maintenance`, not `:imports`: this sweep must not compete
  # for slots with the imports it is expiring. `:imports` runs two at a time, so
  # two concurrent user imports would otherwise block the sweep entirely — and a
  # sweep would occupy a slot a user import needs.
  use Oban.Worker, queue: :imports_maintenance, max_attempts: 3

  alias Storyarn.Projects

  @continuation_delay_seconds 1
  @retry_base_seconds 300
  @retry_max_seconds 3_600

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    perform_expiration(&Projects.expire_stale_imports_batch/0, &schedule_followup/0)
  end

  @impl Oban.Worker
  def backoff(%Oban.Job{attempt: attempt}) do
    exponent = max(attempt - 1, 0)
    min(@retry_base_seconds * Integer.pow(2, exponent), @retry_max_seconds)
  end

  @doc false
  def perform_expiration(expire_imports) when is_function(expire_imports, 0) do
    perform_expiration(expire_imports, fn -> :ok end)
  end

  @doc false
  def perform_expiration(expire_imports, schedule_followup)
      when is_function(expire_imports, 0) and is_function(schedule_followup, 0) do
    started_at = System.monotonic_time()

    try do
      handle_expiration_result(expire_imports.(), schedule_followup, started_at)
    rescue
      _exception ->
        emit_stop(started_at, 0, 1, 0, :exception, "exception")
        {:error, :project_import_expiration_failed}
    catch
      _kind, _reason ->
        emit_stop(started_at, 0, 1, 0, :exception, "throw")
        {:error, :project_import_expiration_failed}
    end
  end

  defp handle_expiration_result(
         {:ok, %{expired_count: expired_count, failure_count: failure_count, more?: more?}},
         schedule_followup,
         started_at
       )
       when is_integer(expired_count) and expired_count >= 0 and is_integer(failure_count) and failure_count >= 0 and
              is_boolean(more?) do
    case maybe_schedule_followup(more?, schedule_followup) do
      {:ok, continuation_count} ->
        finish_batch(started_at, expired_count, failure_count, continuation_count)

      {:error, :followup_schedule_failed} ->
        emit_stop(
          started_at,
          expired_count,
          failure_count + 1,
          0,
          :error,
          "followup_schedule_failed"
        )

        {:error, :project_import_expiration_followup_failed}
    end
  end

  defp handle_expiration_result({:ok, expired_count}, _schedule_followup, started_at)
       when is_integer(expired_count) and expired_count >= 0 do
    emit_stop(started_at, expired_count, 0, 0, :ok, "none")
    :ok
  end

  defp handle_expiration_result({:ok, expired_count, failure_count}, _schedule_followup, started_at)
       when is_integer(expired_count) and expired_count >= 0 and is_integer(failure_count) and failure_count > 0 do
    emit_stop(started_at, expired_count, failure_count, 0, :partial, "row_failure")
    {:error, :project_import_expiration_incomplete}
  end

  defp handle_expiration_result({:error, reason}, _schedule_followup, started_at) do
    emit_stop(started_at, 0, 1, 0, :error, safe_error_code(reason))
    {:error, :project_import_expiration_failed}
  end

  defp handle_expiration_result(_unexpected, _schedule_followup, started_at) do
    emit_stop(started_at, 0, 1, 0, :error, "unexpected_result")
    {:error, :project_import_expiration_failed}
  end

  defp maybe_schedule_followup(false, _schedule_followup), do: {:ok, 0}

  defp maybe_schedule_followup(true, schedule_followup) do
    case safely_schedule_followup(schedule_followup) do
      :ok -> {:ok, 1}
      {:ok, _job} -> {:ok, 1}
      _error -> {:error, :followup_schedule_failed}
    end
  end

  defp safely_schedule_followup(schedule_followup) do
    schedule_followup.()
  rescue
    _exception -> {:error, :followup_schedule_failed}
  catch
    _kind, _reason -> {:error, :followup_schedule_failed}
  end

  defp finish_batch(started_at, expired_count, 0, continuation_count) do
    emit_stop(started_at, expired_count, 0, continuation_count, :ok, "none")
    :ok
  end

  defp finish_batch(started_at, expired_count, failure_count, continuation_count) do
    emit_stop(started_at, expired_count, failure_count, continuation_count, :partial, "row_failure")
    {:error, :project_import_expiration_incomplete}
  end

  defp schedule_followup do
    %{}
    |> new(
      schedule_in: @continuation_delay_seconds,
      unique: [
        fields: [:worker],
        period: 60,
        states: [:available, :scheduled]
      ]
    )
    |> Oban.insert()
  end

  defp emit_stop(started_at, expired_count, failure_count, continuation_count, status, error_code) do
    :telemetry.execute(
      [:storyarn, :import, :expiration, :stop],
      %{
        expired_count: expired_count,
        failure_count: failure_count,
        continuation_count: continuation_count,
        duration: System.monotonic_time() - started_at
      },
      %{status: status, error_code: error_code}
    )
  end

  defp safe_error_code(reason) when is_atom(reason), do: to_string(reason)
  defp safe_error_code({reason, _details}) when is_atom(reason), do: to_string(reason)
  defp safe_error_code(_reason), do: "unexpected_error"
end
