defmodule Storyarn.Flows.Localization.ProjectionLockTest do
  use Storyarn.DataCase, async: true

  alias Storyarn.Flows.Localization
  alias Storyarn.Repo

  test "requires an explicit transaction for the localization inventory lock" do
    assert_raise ArgumentError,
                 "localization inventory locks require an explicit database transaction",
                 fn -> Localization.lock_inventory!(1) end
  end

  test "acquires the inventory lock inside the caller-owned transaction" do
    assert {:ok, :ok} =
             Repo.transaction(fn ->
               assert :ok = Localization.lock_inventory!(1)
             end)
  end
end
