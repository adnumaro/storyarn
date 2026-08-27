defmodule Storyarn.Platform.Kernel.IntegerParserTest do
  use ExUnit.Case, async: true

  alias Storyarn.Platform.Kernel.IntegerParser

  test "parses only complete integer representations" do
    assert IntegerParser.parse("42") == 42
    assert IntegerParser.parse("-5") == -5
    assert IntegerParser.parse("0") == 0
    assert IntegerParser.parse(-2) == -2
    assert IntegerParser.parse("42px") == nil
    assert IntegerParser.parse("3.14") == nil
    assert IntegerParser.parse("") == nil
    assert IntegerParser.parse("  ") == nil
    assert IntegerParser.parse(nil) == nil
  end

  test "ensures an integer for pagination state" do
    assert IntegerParser.ensure(2) == 2
    assert IntegerParser.ensure(nil) == 0
    assert IntegerParser.ensure("2") == 0
  end
end
