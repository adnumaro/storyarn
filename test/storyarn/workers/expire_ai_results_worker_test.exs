defmodule Storyarn.Workers.ExpireAIResultsWorkerTest do
  use Storyarn.DataCase, async: false

  alias Storyarn.Workers.ExpireAIResultsWorker
  alias StoryarnWeb.Telemetry

  @event [:storyarn, :ai, :expiration, :stop]

  setup do
    handler_id = "ai-result-expiration-#{System.unique_integer([:positive])}"
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

  test "reports a bounded batch and schedules its continuation" do
    test_pid = self()

    assert :ok =
             ExpireAIResultsWorker.perform_expiration(
               fn -> {:ok, %{expired_count: 100, failure_count: 0, more?: true}} end,
               fn -> send(test_pid, :scheduled_followup) end
             )

    assert_receive :scheduled_followup
    assert_receive {:expiration_stop, @event, measurements, %{status: :ok}}
    assert measurements.expired_count == 100
    assert measurements.failure_count == 0
    assert is_integer(measurements.duration)
  end

  test "reports row failures and asks Oban to retry" do
    assert {:error, :ai_result_expiration_failed} =
             ExpireAIResultsWorker.perform_expiration(
               fn -> {:ok, %{expired_count: 2, failure_count: 1, more?: false}} end,
               fn -> flunk("must not schedule another batch") end
             )

    assert_receive {:expiration_stop, @event, measurements, %{status: :error}}
    assert measurements.expired_count == 2
    assert measurements.failure_count == 1
  end

  test "registers content-free expiration metrics" do
    metrics =
      Enum.filter(Telemetry.metrics(), fn metric ->
        Enum.take(metric.name, 4) == [:storyarn, :ai, :expiration, :stop]
      end)

    assert metrics |> Enum.map(&List.last(&1.name)) |> Enum.sort() ==
             [:duration, :expired_count, :failure_count]

    assert Enum.all?(metrics, fn metric -> metric.tags == [:status] end)
  end
end
