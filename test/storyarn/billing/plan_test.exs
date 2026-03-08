defmodule Storyarn.Billing.PlanTest do
  use ExUnit.Case, async: true

  alias Storyarn.Billing.Plan

  describe "all/0" do
    test "returns a map of plans" do
      plans = Plan.all()
      assert is_map(plans)
      assert Map.has_key?(plans, "free")
    end

    test "free plan has required limit keys" do
      free = Plan.all()["free"]
      assert free[:name] == "Free"
      assert is_integer(free[:limits][:workspaces_per_user])
      assert is_integer(free[:limits][:projects_per_workspace])
      assert is_integer(free[:limits][:items_per_project])
      assert is_integer(free[:limits][:members_per_workspace])
      assert is_integer(free[:limits][:storage_bytes_per_workspace])
    end
  end

  describe "get/1" do
    test "returns plan for valid key" do
      assert %{name: "Free"} = Plan.get("free")
    end

    test "returns nil for unknown key" do
      assert Plan.get("nonexistent") == nil
    end
  end

  describe "limit/2" do
    test "returns limit value for valid plan and resource" do
      assert is_integer(Plan.limit("free", :items_per_project))
    end

    test "returns nil for unknown plan" do
      assert Plan.limit("nonexistent", :items_per_project) == nil
    end

    test "returns nil for unknown resource" do
      assert Plan.limit("free", :nonexistent_resource) == nil
    end
  end

  describe "default_plan/0" do
    test "returns the default plan key" do
      assert Plan.default_plan() == "free"
    end

    test "default plan exists in all plans" do
      assert Map.has_key?(Plan.all(), Plan.default_plan())
    end
  end
end
