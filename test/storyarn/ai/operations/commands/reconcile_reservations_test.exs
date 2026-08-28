defmodule Storyarn.AI.Operations.Commands.ReconcileReservationsTest do
  use ExUnit.Case, async: true

  alias Storyarn.AI.Operations.Commands.ReconcileReservations

  test "accepts an immediate zero-second staleness cutoff" do
    assert %{
             allowance_batch: %{more?: false},
             stale_batch: %{more?: false}
           } =
             ReconcileReservations.run(
               %{"allowance_done" => true, "stale_operations_done" => true},
               DateTime.from_unix!(0),
               1,
               0
             )
  end
end
