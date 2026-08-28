defmodule Storyarn.Sheets.Expressions.Rules.NumericValuesTest do
  use ExUnit.Case, async: true

  alias Storyarn.Sheets.Expressions.Rules.NumericValues

  describe "parse/1" do
    test "preserves the formula runtime coercion contract" do
      assert NumericValues.parse(nil) == 0.0
      assert NumericValues.parse(5) == 5.0
      assert NumericValues.parse(-5) == -5.0
      assert NumericValues.parse(3.14) == 3.14
      assert NumericValues.parse("42") == 42.0
      assert NumericValues.parse("-3.5") == -3.5
      assert NumericValues.parse("invalid") == 0.0
      assert NumericValues.parse(%{}) == 0.0
    end
  end

  describe "format/1" do
    test "converts bounded whole floats and preserves all other values" do
      assert NumericValues.format(10.0) == 10
      assert NumericValues.format(-10.0) == -10
      assert NumericValues.format(3.14) == 3.14
      assert NumericValues.format(-3.14) == -3.14
      assert NumericValues.format(1.0e15) == 1_000_000_000_000_000
      assert NumericValues.format(-1.0e15) == -1_000_000_000_000_000
      assert NumericValues.format(1.0e16) == 1.0e16
      assert NumericValues.format(-1.0e16) == -1.0e16
      assert NumericValues.format(42) == 42
      assert NumericValues.format("invalid") == "invalid"
      assert NumericValues.format(nil) == nil
    end
  end
end
