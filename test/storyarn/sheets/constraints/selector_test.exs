defmodule Storyarn.Sheets.Constraints.SelectorTest do
  use ExUnit.Case, async: true

  alias Storyarn.Sheets.Constraints.Selector

  # =============================================================================
  # extract/1
  # =============================================================================

  describe "extract/1" do
    test "extracts max_options" do
      assert Selector.extract(%{"max_options" => 3}) == %{"max_options" => 3}
    end

    test "parses string max_options" do
      assert Selector.extract(%{"max_options" => "3"}) == %{"max_options" => 3.0}
    end

    test "returns nil when max_options is nil" do
      assert Selector.extract(%{"max_options" => nil}) == nil
    end

    test "returns nil for empty config" do
      assert Selector.extract(%{}) == nil
    end

    test "returns nil for non-map" do
      assert Selector.extract(nil) == nil
    end
  end

  # =============================================================================
  # clamp/2
  # =============================================================================

  describe "clamp/2" do
    test "truncates list exceeding max_options" do
      assert Selector.clamp(["a", "b", "c", "d"], %{"max_options" => 2}) == ["a", "b"]
    end

    test "short list passes through" do
      assert Selector.clamp(["a"], %{"max_options" => 2}) == ["a"]
    end

    test "exact count passes through" do
      assert Selector.clamp(["a", "b"], %{"max_options" => 2}) == ["a", "b"]
    end

    test "nil config passes through" do
      assert Selector.clamp(["a", "b"], nil) == ["a", "b"]
    end

    test "nil max_options passes through" do
      assert Selector.clamp(["a", "b", "c"], %{"max_options" => nil}) == ["a", "b", "c"]
    end

    test "non-list value passes through" do
      assert Selector.clamp("single", %{"max_options" => 2}) == "single"
    end

    test "empty list passes through" do
      assert Selector.clamp([], %{"max_options" => 2}) == []
    end
  end
end
