defmodule Storyarn.Shared.MapUtilsTest do
  use ExUnit.Case, async: true

  alias Storyarn.Shared.MapUtils

  # ===========================================================================
  # stringify_keys/1
  # ===========================================================================

  describe "stringify_keys/1" do
    test "converts atom keys to strings" do
      assert MapUtils.stringify_keys(%{name: "test", age: 42}) == %{
               "name" => "test",
               "age" => 42
             }
    end

    test "leaves string keys unchanged" do
      assert MapUtils.stringify_keys(%{"name" => "test"}) == %{"name" => "test"}
    end

    test "handles mixed atom and string keys" do
      input = Map.put(%{name: "test"}, "age", 42)
      result = MapUtils.stringify_keys(input)
      assert result == %{"name" => "test", "age" => 42}
    end

    test "does NOT recursively convert nested maps" do
      result = MapUtils.stringify_keys(%{name: "test", nested: %{key: "val"}})
      assert result == %{"name" => "test", "nested" => %{key: "val"}}
    end

    test "handles empty map" do
      assert MapUtils.stringify_keys(%{}) == %{}
    end

    test "preserves values of all types" do
      result =
        MapUtils.stringify_keys(%{
          string: "hello",
          number: 42,
          float: 3.14,
          bool: true,
          nil_val: nil,
          list: [1, 2, 3],
          nested_map: %{a: 1}
        })

      assert result["string"] == "hello"
      assert result["number"] == 42
      assert result["float"] == 3.14
      assert result["bool"] == true
      assert result["nil_val"] == nil
      assert result["list"] == [1, 2, 3]
      assert result["nested_map"] == %{a: 1}
    end

    test "handles single key map" do
      assert MapUtils.stringify_keys(%{key: "value"}) == %{"key" => "value"}
    end
  end

  # ===========================================================================
  # parse_int/1
  # ===========================================================================

  describe "parse_int/1" do
    test "parses string integer" do
      assert MapUtils.parse_int("42") == 42
    end

    test "parses negative string integer" do
      assert MapUtils.parse_int("-5") == -5
    end

    test "returns nil for empty string" do
      assert MapUtils.parse_int("") == nil
    end

    test "returns nil for nil" do
      assert MapUtils.parse_int(nil) == nil
    end

    test "passes through integer values" do
      assert MapUtils.parse_int(42) == 42
      assert MapUtils.parse_int(0) == 0
      assert MapUtils.parse_int(-1) == -1
    end

    test "returns nil for non-numeric string" do
      assert MapUtils.parse_int("abc") == nil
    end

    test "returns nil for partial numeric string" do
      assert MapUtils.parse_int("42abc") == nil
    end

    test "parses zero" do
      assert MapUtils.parse_int("0") == 0
    end

    test "returns nil for float string" do
      assert MapUtils.parse_int("3.14") == nil
    end

    test "returns nil for whitespace-only string" do
      # Integer.parse handles this case
      assert MapUtils.parse_int("  ") == nil
    end
  end
end
