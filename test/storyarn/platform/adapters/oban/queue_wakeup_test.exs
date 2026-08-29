defmodule Storyarn.Platform.Adapters.Oban.QueueWakeupTest do
  use ExUnit.Case, async: true

  alias Storyarn.Platform.Adapters.Oban.QueueWakeup

  test "wakes immediately and for the configured bounded window" do
    test_process = self()

    notifier = fn queue ->
      send(test_process, {:queue_wakeup, queue})
      :ok
    end

    pid =
      start_supervised!({QueueWakeup, queue: :invitation_delivery, interval: 1, repetitions: 2, notifier: notifier})

    monitor = Process.monitor(pid)

    assert_receive {:queue_wakeup, "invitation_delivery"}
    assert_receive {:queue_wakeup, "invitation_delivery"}
    assert_receive {:queue_wakeup, "invitation_delivery"}
    assert_receive {:DOWN, ^monitor, :process, ^pid, reason}
    assert reason in [:normal, :noproc]
    refute_receive {:queue_wakeup, "invitation_delivery"}
  end

  test "a failed signal is best-effort and does not stop later wakeups" do
    test_process = self()

    notifier = fn queue ->
      send(test_process, {:queue_wakeup_attempt, queue})
      {:error, :notifier_unavailable}
    end

    pid =
      start_supervised!({QueueWakeup, queue: "invitation_delivery", interval: 1, repetitions: 1, notifier: notifier})

    monitor = Process.monitor(pid)

    assert_receive {:queue_wakeup_attempt, "invitation_delivery"}
    assert_receive {:queue_wakeup_attempt, "invitation_delivery"}
    assert_receive {:DOWN, ^monitor, :process, ^pid, reason}
    assert reason in [:normal, :noproc]
  end
end
