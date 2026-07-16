defmodule Storyarn.Workers.ExpireProjectImportsWorker do
  @moduledoc """
  Removes encrypted plans for previews that were never executed.
  """

  use Oban.Worker, queue: :imports, max_attempts: 3

  alias Storyarn.Imports

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    perform_expiration(&Imports.expire_stale_imports/0)
  end

  @doc false
  def perform_expiration(expire_imports) when is_function(expire_imports, 0) do
    started_at = System.monotonic_time()

    try do
      case expire_imports.() do
        {:ok, expired_count} when is_integer(expired_count) and expired_count >= 0 ->
          emit_stop(started_at, expired_count, 0, :ok, "none")
          :ok

        {:error, reason} ->
          emit_stop(started_at, 0, 1, :error, safe_error_code(reason))
          {:error, :project_import_expiration_failed}

        _unexpected ->
          emit_stop(started_at, 0, 1, :error, "unexpected_result")
          {:error, :project_import_expiration_failed}
      end
    rescue
      exception ->
        emit_stop(started_at, 0, 1, :exception, "exception")
        reraise exception, __STACKTRACE__
    catch
      kind, reason ->
        emit_stop(started_at, 0, 1, :exception, "throw")
        :erlang.raise(kind, reason, __STACKTRACE__)
    end
  end

  defp emit_stop(started_at, expired_count, failure_count, status, error_code) do
    :telemetry.execute(
      [:storyarn, :import, :expiration, :stop],
      %{
        expired_count: expired_count,
        failure_count: failure_count,
        duration: System.monotonic_time() - started_at
      },
      %{status: status, error_code: error_code}
    )
  end

  defp safe_error_code(reason) when is_atom(reason), do: to_string(reason)
  defp safe_error_code({reason, _details}) when is_atom(reason), do: to_string(reason)
  defp safe_error_code(_reason), do: "unexpected_error"
end
