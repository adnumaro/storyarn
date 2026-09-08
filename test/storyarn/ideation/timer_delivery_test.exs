defmodule Storyarn.Ideation.TimerDeliveryTest do
  use Storyarn.DataCase, async: true

  alias Storyarn.Ideation.Sessions.Execution.TimerDelivery

  test "an Oban job rejection returns a scheduling error instead of form validation" do
    invalid_schedule = %{status: :running, id: 1, version: 1, deadline_at: "invalid"}

    assert {:error, :timer_scheduling_failed} =
             Repo.transact(fn -> TimerDelivery.schedule(invalid_schedule) end)

    assert Repo.aggregate(Oban.Job, :count) == 0
  end
end
