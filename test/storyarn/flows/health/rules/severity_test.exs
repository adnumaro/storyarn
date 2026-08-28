defmodule Storyarn.Flows.SeverityTest do
  use ExUnit.Case, async: true

  alias Storyarn.Flows.Severity

  test "owns the strict Flow health ordering" do
    assert Severity.catalog() == [:error, :warning, :info]

    assert Enum.map(Severity.catalog(), &Severity.rank/1) == [0, 1, 2]

    for severity <- Severity.catalog() do
      assert Severity.rank(severity) == Severity.rank(Atom.to_string(severity))
    end

    assert_raise ArgumentError, ~r/unknown Flow severity/, fn ->
      Severity.rank(:critical)
    end
  end
end
