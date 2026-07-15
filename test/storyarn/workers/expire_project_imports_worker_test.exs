defmodule Storyarn.Workers.ExpireProjectImportsWorkerTest do
  use ExUnit.Case, async: true

  alias Storyarn.Workers.ExpireProjectImportsWorker
  alias StoryarnWeb.Telemetry

  @event [:storyarn, :import, :expiration, :stop]

  setup do
    handler_id = "project-import-expiration-#{System.unique_integer([:positive])}"
    test_pid = self()

    :ok =
      :telemetry.attach(
        handler_id,
        @event,
        fn event, measurements, metadata, _config ->
          send(test_pid, {:expiration_stop, event, measurements, metadata})
        end,
        nil
      )

    on_exit(fn -> :telemetry.detach(handler_id) end)
    :ok
  end

  test "reports expired plans, failures, and duration without identifying metadata" do
    assert :ok = ExpireProjectImportsWorker.perform_expiration(fn -> {:ok, 7} end)

    assert_receive {:expiration_stop, @event, measurements, metadata}
    assert measurements.expired_count == 7
    assert measurements.failure_count == 0
    assert is_integer(measurements.duration)
    assert measurements.duration >= 0
    assert metadata == %{status: :ok, error_code: "none"}
  end

  test "reports a bounded failure code and asks Oban to retry a failed batch" do
    assert {:error, :project_import_expiration_failed} =
             ExpireProjectImportsWorker.perform_expiration(fn ->
               {:error, {:storage_unavailable, "private storage key"}}
             end)

    assert_receive {:expiration_stop, @event, measurements, metadata}
    assert measurements.expired_count == 0
    assert measurements.failure_count == 1
    assert metadata == %{status: :error, error_code: "storage_unavailable"}
    refute inspect({measurements, metadata}) =~ "private storage key"
  end

  test "registers the three expiration metrics with privacy-safe tags" do
    metrics =
      Enum.filter(Telemetry.metrics(), fn metric ->
        Enum.take(metric.name, 4) == [:storyarn, :import, :expiration, :stop]
      end)

    assert metrics |> Enum.map(&List.last(&1.name)) |> Enum.sort() ==
             [:duration, :expired_count, :failure_count]

    assert Enum.all?(metrics, fn metric -> metric.tags == [:status, :error_code] end)
  end
end
