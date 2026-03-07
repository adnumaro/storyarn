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

  # ===========================================================================
  # parse_to_number/1
  # ===========================================================================

  describe "parse_to_number/1" do
    test "nil → 0.0" do
      assert MapUtils.parse_to_number(nil) == 0.0
    end

    test "integer → float" do
      assert MapUtils.parse_to_number(5) == 5.0
    end

    test "float → float" do
      assert MapUtils.parse_to_number(3.14) == 3.14
    end

    test "numeric string → float" do
      assert MapUtils.parse_to_number("42") == 42.0
    end

    test "non-numeric string → 0.0" do
      assert MapUtils.parse_to_number("hello") == 0.0
    end

    test "other types → 0.0" do
      assert MapUtils.parse_to_number([]) == 0.0
      assert MapUtils.parse_to_number(%{}) == 0.0
      assert MapUtils.parse_to_number(true) == 0.0
    end
  end

  # ===========================================================================
  # format_number_result/1
  # ===========================================================================

  describe "format_number_result/1" do
    test "truncates whole float to integer" do
      assert MapUtils.format_number_result(10.0) == 10
      assert MapUtils.format_number_result(0.0) == 0
      assert MapUtils.format_number_result(1000.0) == 1000
    end

    test "preserves decimal floats" do
      assert MapUtils.format_number_result(3.14) == 3.14
      assert MapUtils.format_number_result(0.5) == 0.5
      assert MapUtils.format_number_result(99.99) == 99.99
    end

    test "truncates negative whole float to integer" do
      assert MapUtils.format_number_result(-5.0) == -5
      assert MapUtils.format_number_result(-100.0) == -100
    end

    test "preserves negative decimal floats" do
      assert MapUtils.format_number_result(-3.14) == -3.14
    end

    test "passes through integers unchanged" do
      assert MapUtils.format_number_result(42) == 42
      assert MapUtils.format_number_result(0) == 0
      assert MapUtils.format_number_result(-7) == -7
    end

    test "passes through non-numeric values" do
      assert MapUtils.format_number_result(nil) == nil
      assert MapUtils.format_number_result("hello") == "hello"
    end

    test "preserves floats outside the safe truncation range" do
      huge = 1.0e16
      assert MapUtils.format_number_result(huge) == huge
      assert is_float(MapUtils.format_number_result(huge))
    end
  end
end
