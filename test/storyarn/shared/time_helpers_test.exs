defmodule Storyarn.Shared.TimeHelpersTest do
  use ExUnit.Case, async: true

  alias Storyarn.Shared.TimeHelpers

  # ===========================================================================
  # now/0
  # ===========================================================================

  describe "now/0" do
    test "returns a DateTime" do
      result = TimeHelpers.now()
      assert %DateTime{} = result
    end

    test "returns UTC time" do
      result = TimeHelpers.now()
      assert result.time_zone == "Etc/UTC"
    end

    test "returns time truncated to seconds (no microseconds)" do
      result = TimeHelpers.now()
      assert result.microsecond == {0, 0}
    end

    test "returns approximately current time" do
      before = DateTime.utc_now() |> DateTime.truncate(:second)
      result = TimeHelpers.now()
      after_time = DateTime.utc_now() |> DateTime.truncate(:second)

      # Result should be between before and after (within 1 second)
      assert DateTime.compare(result, before) in [:eq, :gt]
      assert DateTime.compare(result, after_time) in [:eq, :lt]
    end

    test "two consecutive calls return close timestamps" do
      t1 = TimeHelpers.now()
      t2 = TimeHelpers.now()

      diff = DateTime.diff(t2, t1, :second)
      assert diff >= 0
      assert diff <= 1
    end
  end
end
