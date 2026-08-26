defmodule Storyarn.Localization.Texts.Commands.InventoryLockTest do
  use Storyarn.DataCase, async: true

  alias Storyarn.Localization.Texts

  test "inventory advisory locks reject callers outside an explicit transaction" do
    task =
      Task.async(fn ->
        assert_raise ArgumentError, ~r/require an explicit database transaction/, fn ->
          Texts.lock_inventory!(1)
        end
      end)

    Task.await(task)
  end
end
