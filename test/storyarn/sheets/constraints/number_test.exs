defmodule Storyarn.Sheets.Constraints.NumberTest do
  use ExUnit.Case, async: true

  alias Storyarn.Sheets.Constraints.Number

  # =============================================================================
  # extract/1
  # =============================================================================

  describe "extract/1" do
    test "extracts numeric constraints" do
      assert Number.extract(%{"min" => 0, "max" => 100, "step" => 1}) ==
               %{"min" => 0, "max" => 100, "step" => 1}
    end

    test "parses string constraints" do
      assert Number.extract(%{"min" => "0", "max" => "100", "step" => "1"}) ==
               %{"min" => 0.0, "max" => 100.0, "step" => 1.0}
    end

    test "returns nil when all values are nil" do
      assert Number.extract(%{"min" => nil, "max" => nil, "step" => nil}) == nil
    end

    test "returns nil for empty config" do
      assert Number.extract(%{}) == nil
    end

    test "returns nil for non-map" do
      assert Number.extract(nil) == nil
    end

    test "partial constraints preserved" do
      assert Number.extract(%{"min" => 0, "max" => nil, "step" => nil}) ==
               %{"min" => 0, "max" => nil, "step" => nil}
    end
  end

  # =============================================================================
  # clamp/2
  # =============================================================================

  describe "clamp/2" do
    test "clamps value above max" do
      assert Number.clamp(150, %{"min" => 0, "max" => 100}) == 100
    end

    test "clamps value below min" do
      assert Number.clamp(-5, %{"min" => 0, "max" => 100}) == 0
    end

    test "value within range unchanged" do
      assert Number.clamp(50, %{"min" => 0, "max" => 100}) == 50
    end

    test "nil min means no lower bound" do
      assert Number.clamp(-999, %{"min" => nil, "max" => 100}) == -999
    end

    test "nil max means no upper bound" do
      assert Number.clamp(999, %{"min" => 0, "max" => nil}) == 999
    end

    test "both nil means no clamping" do
      assert Number.clamp(999, %{"min" => nil, "max" => nil}) == 999
    end

    test "nil config means no clamping" do
      assert Number.clamp(999, nil) == 999
    end

    test "handles string constraint values (from form params)" do
      assert Number.clamp(150, %{"min" => "0", "max" => "100"}) == 100
    end

    test "handles mixed string and number constraints" do
      assert Number.clamp(-5, %{"min" => "0", "max" => 100}) == 0
    end

    test "ignores unparseable string constraints" do
      assert Number.clamp(150, %{"min" => "abc", "max" => "xyz"}) == 150
    end

    test "non-number value passes through" do
      assert Number.clamp("text", %{"min" => 0, "max" => 100}) == "text"
    end

    test "clamps at exact boundary" do
      assert Number.clamp(100, %{"min" => 0, "max" => 100}) == 100
      assert Number.clamp(0, %{"min" => 0, "max" => 100}) == 0
    end

    test "handles float constraints" do
      assert Number.clamp(1.5, %{"min" => 0.5, "max" => 1.0}) == 1.0
    end
  end

  # =============================================================================
  # clamp_and_format/2
  # =============================================================================

  describe "clamp_and_format/2" do
    test "clamps and formats integer result" do
      assert Number.clamp_and_format("150", %{"min" => 0, "max" => 100}) == "100"
    end

    test "clamps and formats float result" do
      assert Number.clamp_and_format("150", %{"min" => 0.5, "max" => 99.5}) == "99.5"
    end

    test "passes through non-numeric string" do
      assert Number.clamp_and_format("abc", %{"min" => 0, "max" => 100}) == "abc"
    end

    test "passes through empty string" do
      assert Number.clamp_and_format("", %{"min" => 0, "max" => 100}) == ""
    end

    test "handles string constraints from config panel" do
      assert Number.clamp_and_format("150", %{"min" => "0", "max" => "100"}) == "100"
    end

    test "no clamping needed returns original value formatted" do
      assert Number.clamp_and_format("50", %{"min" => 0, "max" => 100}) == "50"
    end

    test "nil config passes through" do
      assert Number.clamp_and_format("150", nil) == "150"
    end

    test "non-string value passes through" do
      assert Number.clamp_and_format(42, %{"min" => 0, "max" => 100}) == 42
    end
  end

  # =============================================================================
  # parse_constraint/1
  # =============================================================================

  describe "parse_constraint/1" do
    test "nil returns nil" do
      assert Number.parse_constraint(nil) == nil
    end

    test "empty string returns nil" do
      assert Number.parse_constraint("") == nil
    end

    test "integer passes through" do
      assert Number.parse_constraint(42) == 42
    end

    test "float passes through" do
      assert Number.parse_constraint(3.14) == 3.14
    end

    test "numeric string parsed to float" do
      assert Number.parse_constraint("42") == 42.0
    end

    test "float string parsed" do
      assert Number.parse_constraint("3.14") == 3.14
    end

    test "non-numeric string returns nil" do
      assert Number.parse_constraint("abc") == nil
    end

    test "negative string parsed" do
      assert Number.parse_constraint("-10") == -10.0
    end
  end

  # =============================================================================
  # format_number/1
  # =============================================================================

  describe "format_number/1" do
    test "integer float formatted without decimal" do
      assert Number.format_number(42.0) == "42"
    end

    test "float with decimal preserved" do
      assert Number.format_number(3.14) == "3.14"
    end

    test "integer formatted" do
      assert Number.format_number(42) == "42"
    end

    test "zero formatted" do
      assert Number.format_number(0.0) == "0"
    end

    test "negative integer float" do
      assert Number.format_number(-5.0) == "-5"
    end
  end
end
