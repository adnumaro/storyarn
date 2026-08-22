defmodule Storyarn.Shared.SeverityTest do
  @moduledoc """
  `severity_rank/1` was hand-rolled in five places. The copies were split on the
  key type — the Flow analyzer and Project dashboard
  rank atoms, the three dashboard LiveViews rank the strings that cross the
  LiveVue boundary — and split again on the catch-all, which two copies had and
  two did not.

  The shared `rank/1` accepts both key types and is strict on everything else:
  severity is a closed catalog, so an unknown value is a bug in the caller, not
  something to silently sort last.
  """
  use ExUnit.Case, async: true

  alias Storyarn.Shared.Severity

  describe "rank/1 on the atom vocabulary" do
    test "orders error before warning before info" do
      assert Severity.rank(:error) == 0
      assert Severity.rank(:warning) == 1
      assert Severity.rank(:info) == 2
    end
  end

  describe "rank/1 on the string vocabulary" do
    test "orders the LiveVue-facing strings identically" do
      assert Severity.rank("error") == 0
      assert Severity.rank("warning") == 1
      assert Severity.rank("info") == 2
    end

    test "agrees with the atom reading for every catalog value" do
      for severity <- [:error, :warning, :info] do
        assert Severity.rank(severity) == Severity.rank(Atom.to_string(severity)),
               "#{inspect(severity)} must rank the same whichever side of the boundary it is read on"
      end
    end
  end

  describe "rank/1 sorts a mixed list" do
    test "sort_by puts errors first and info last" do
      findings = [
        %{severity: "info"},
        %{severity: "error"},
        %{severity: "warning"},
        %{severity: "error"}
      ]

      assert Enum.map(Enum.sort_by(findings, &Severity.rank(&1.severity)), & &1.severity) ==
               ["error", "error", "warning", "info"]
    end
  end

  describe "rank/1 rejects values outside the catalog" do
    test "raises on an unknown atom" do
      assert_raise ArgumentError, ~r/unknown severity/, fn -> Severity.rank(:critical) end
    end

    test "raises on an unknown string" do
      assert_raise ArgumentError, ~r/unknown severity/, fn -> Severity.rank("Error") end
    end

    test "raises on nil" do
      assert_raise ArgumentError, ~r/unknown severity/, fn -> Severity.rank(nil) end
    end
  end

  describe "catalog/0" do
    test "exposes the three severities in rank order" do
      assert Severity.catalog() == [:error, :warning, :info]
    end
  end
end
