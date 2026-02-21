defmodule Storyarn.Sheets.Constraints.DateTest do
  use ExUnit.Case, async: true

  alias Storyarn.Sheets.Constraints.Date, as: DateConstraints

  # =============================================================================
  # extract/1
  # =============================================================================

  describe "extract/1" do
    test "extracts date range" do
      assert DateConstraints.extract(%{"min_date" => "2025-01-01", "max_date" => "2025-12-31"}) ==
               %{"min_date" => "2025-01-01", "max_date" => "2025-12-31"}
    end

    test "returns nil when both dates are nil" do
      assert DateConstraints.extract(%{"min_date" => nil, "max_date" => nil}) == nil
    end

    test "returns nil for empty strings" do
      assert DateConstraints.extract(%{"min_date" => "", "max_date" => ""}) == nil
    end

    test "partial range preserved" do
      assert DateConstraints.extract(%{"min_date" => "2025-01-01", "max_date" => nil}) ==
               %{"min_date" => "2025-01-01", "max_date" => nil}
    end

    test "returns nil for empty config" do
      assert DateConstraints.extract(%{}) == nil
    end

    test "returns nil for non-map" do
      assert DateConstraints.extract(nil) == nil
    end
  end

  # =============================================================================
  # clamp/2
  # =============================================================================

  describe "clamp/2" do
    test "clamps date before min" do
      assert DateConstraints.clamp("2024-06-15", %{
               "min_date" => "2025-01-01",
               "max_date" => "2025-12-31"
             }) ==
               "2025-01-01"
    end

    test "clamps date after max" do
      assert DateConstraints.clamp("2026-03-01", %{
               "min_date" => "2025-01-01",
               "max_date" => "2025-12-31"
             }) ==
               "2025-12-31"
    end

    test "date within range unchanged" do
      assert DateConstraints.clamp("2025-06-15", %{
               "min_date" => "2025-01-01",
               "max_date" => "2025-12-31"
             }) ==
               "2025-06-15"
    end

    test "nil min_date means no lower bound" do
      assert DateConstraints.clamp("2020-01-01", %{"min_date" => nil, "max_date" => "2025-12-31"}) ==
               "2020-01-01"
    end

    test "nil max_date means no upper bound" do
      assert DateConstraints.clamp("2030-01-01", %{"min_date" => "2025-01-01", "max_date" => nil}) ==
               "2030-01-01"
    end

    test "nil config passes through" do
      assert DateConstraints.clamp("2025-06-15", nil) == "2025-06-15"
    end

    test "empty string passes through" do
      assert DateConstraints.clamp("", %{"min_date" => "2025-01-01", "max_date" => "2025-12-31"}) ==
               ""
    end

    test "non-string value passes through" do
      assert DateConstraints.clamp(nil, %{"min_date" => "2025-01-01", "max_date" => "2025-12-31"}) ==
               nil
    end

    test "at exact boundary passes through" do
      assert DateConstraints.clamp("2025-01-01", %{
               "min_date" => "2025-01-01",
               "max_date" => "2025-12-31"
             }) ==
               "2025-01-01"

      assert DateConstraints.clamp("2025-12-31", %{
               "min_date" => "2025-01-01",
               "max_date" => "2025-12-31"
             }) ==
               "2025-12-31"
    end
  end
end
