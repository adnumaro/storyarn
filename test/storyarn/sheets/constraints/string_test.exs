defmodule Storyarn.Sheets.Constraints.StringTest do
  use ExUnit.Case, async: true

  alias Storyarn.Sheets.Constraints.String, as: StringConstraints

  # =============================================================================
  # extract/1
  # =============================================================================

  describe "extract/1" do
    test "extracts max_length" do
      assert StringConstraints.extract(%{"max_length" => 500}) == %{"max_length" => 500}
    end

    test "parses string max_length" do
      assert StringConstraints.extract(%{"max_length" => "500"}) == %{"max_length" => 500.0}
    end

    test "returns nil when max_length is nil" do
      assert StringConstraints.extract(%{"max_length" => nil}) == nil
    end

    test "returns nil for empty config" do
      assert StringConstraints.extract(%{}) == nil
    end

    test "returns nil for non-map" do
      assert StringConstraints.extract(nil) == nil
    end
  end

  # =============================================================================
  # clamp/2
  # =============================================================================

  describe "clamp/2" do
    test "truncates string exceeding max_length" do
      assert StringConstraints.clamp("hello world", %{"max_length" => 5}) == "hello"
    end

    test "short string passes through" do
      assert StringConstraints.clamp("hi", %{"max_length" => 5}) == "hi"
    end

    test "exact length passes through" do
      assert StringConstraints.clamp("hello", %{"max_length" => 5}) == "hello"
    end

    test "nil config passes through" do
      assert StringConstraints.clamp("hello", nil) == "hello"
    end

    test "nil max_length passes through" do
      assert StringConstraints.clamp("hello", %{"max_length" => nil}) == "hello"
    end

    test "non-string value passes through" do
      assert StringConstraints.clamp(42, %{"max_length" => 5}) == 42
    end

    test "handles unicode correctly" do
      assert StringConstraints.clamp("héllo", %{"max_length" => 3}) == "hél"
    end
  end
end
