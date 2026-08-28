defmodule Storyarn.Projects.Overview.FormulaNumberTest do
  use ExUnit.Case, async: true

  alias Storyarn.Projects.Overview.FormulaNumber

  test "preserves the established permissive formula coercion" do
    assert FormulaNumber.parse(nil) == 0.0
    assert FormulaNumber.parse(3) == 3.0
    assert FormulaNumber.parse(2.5) == 2.5
    assert FormulaNumber.parse("7.25 trailing") == 7.25
    assert FormulaNumber.parse("not-a-number") == 0.0
  end

  test "compacts safe whole floats without changing fractional or huge values" do
    assert FormulaNumber.format_result(10.0) == 10
    assert FormulaNumber.format_result(3.14) == 3.14
    assert FormulaNumber.format_result(1.1e16) == 1.1e16
    assert FormulaNumber.format_result(:unknown) == :unknown
  end
end
