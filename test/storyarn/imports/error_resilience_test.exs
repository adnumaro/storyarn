defmodule Storyarn.Imports.ErrorResilienceTest do
  use ExUnit.Case, async: false

  alias Storyarn.Imports.Error
  alias Storyarn.Imports.ErrorDeduplicator

  @event [:storyarn, :import, :error]

  setup do
    handler_id = "import-error-resilience-#{System.unique_integer([:positive])}"
    test_pid = self()

    :ok =
      :telemetry.attach(
        handler_id,
        @event,
        fn event, measurements, metadata, _config ->
          send(test_pid, {:import_error, event, measurements, metadata})
        end,
        nil
      )

    on_exit(fn -> :telemetry.detach(handler_id) end)
    :ok
  end

  test "report emits without deduplication while the cache is unavailable" do
    assert :ok = Supervisor.terminate_child(Storyarn.Supervisor, ErrorDeduplicator)
    on_exit(&ensure_deduplicator_started/0)

    assert :ok = Error.report(metadata("cache_unavailable"))

    assert_receive {:import_error, @event, %{count: 1}, reported}
    assert reported.error_code == "cache_unavailable"

    assert reported |> Map.keys() |> Enum.sort() ==
             [:error_code, :exception_module, :format, :parser_version, :phase]

    ensure_deduplicator_started()
  end

  test "report emits and returns ok when the cache call times out" do
    pid = Process.whereis(ErrorDeduplicator)
    :ok = :sys.suspend(pid)
    on_exit(fn -> resume_if_alive(pid) end)

    assert :ok = Error.report(metadata("cache_timeout"))
    assert_receive {:import_error, @event, %{count: 1}, %{error_code: "cache_timeout"}}

    :ok = :sys.resume(pid)
  end

  defp metadata(error_code) do
    %{
      format: "yarn",
      parser_version: "3",
      phase: "parse",
      error_code: error_code,
      exception_module: "none",
      filename: "private-project.yarn",
      user_id: 123,
      project_id: 456
    }
  end

  defp ensure_deduplicator_started do
    case Process.whereis(ErrorDeduplicator) do
      nil ->
        case Supervisor.restart_child(Storyarn.Supervisor, ErrorDeduplicator) do
          {:ok, _pid} -> :ok
          {:ok, _pid, _info} -> :ok
          {:error, :running} -> :ok
        end

      _pid ->
        :ok
    end
  end

  defp resume_if_alive(pid) do
    if Process.alive?(pid) do
      try do
        :sys.resume(pid)
      catch
        :exit, _reason -> :ok
      end
    end
  end
end
