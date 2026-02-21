defmodule Storyarn.Sheets.Constraints.BooleanTest do
  use ExUnit.Case, async: true

  alias Storyarn.Sheets.Constraints.Boolean, as: BooleanConstraints

  # =============================================================================
  # extract/1
  # =============================================================================

  describe "extract/1" do
    test "extracts tri_state mode" do
      assert BooleanConstraints.extract(%{"mode" => "tri_state"}) == %{"mode" => "tri_state"}
    end

    test "returns nil for two_state (default)" do
      assert BooleanConstraints.extract(%{"mode" => "two_state"}) == nil
    end

    test "returns nil when mode is nil" do
      assert BooleanConstraints.extract(%{"mode" => nil}) == nil
    end

    test "returns nil for empty config" do
      assert BooleanConstraints.extract(%{}) == nil
    end

    test "returns nil for non-map" do
      assert BooleanConstraints.extract(nil) == nil
    end
  end

  # =============================================================================
  # clamp/2
  # =============================================================================

  describe "clamp/2" do
    test "nil becomes false in two_state mode" do
      assert BooleanConstraints.clamp(nil, nil) == false
      assert BooleanConstraints.clamp(nil, %{"mode" => "two_state"}) == false
    end

    test "nil stays nil in tri_state mode" do
      assert BooleanConstraints.clamp(nil, %{"mode" => "tri_state"}) == nil
    end

    test "true passes through in any mode" do
      assert BooleanConstraints.clamp(true, nil) == true
      assert BooleanConstraints.clamp(true, %{"mode" => "two_state"}) == true
      assert BooleanConstraints.clamp(true, %{"mode" => "tri_state"}) == true
    end

    test "false passes through in any mode" do
      assert BooleanConstraints.clamp(false, nil) == false
      assert BooleanConstraints.clamp(false, %{"mode" => "two_state"}) == false
      assert BooleanConstraints.clamp(false, %{"mode" => "tri_state"}) == false
    end
  end
end
