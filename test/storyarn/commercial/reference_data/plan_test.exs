defmodule Storyarn.Commercial.Billing.PlanTest do
  use ExUnit.Case, async: true

  alias Storyarn.Commercial.Billing.Plan

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

  describe "catalog" do
    @workspace_resources ~w(
      projects_per_workspace members_per_workspace items_per_project storage_bytes_per_workspace
      project_templates_per_workspace project_template_versions_per_template
      named_versions_per_project project_snapshots_per_project
    )a

    test "every plan defines every workspace resource as a number or :unlimited" do
      for {key, %{limits: limits}} <- Plan.all(), resource <- @workspace_resources do
        limit = Map.fetch!(limits, resource)

        assert limit == :unlimited or (is_integer(limit) and limit >= 0),
               "#{key} has #{inspect(limit)} for #{resource}"
      end
    end

    test "every plan keeps deleted items for a finite window" do
      for {key, _plan} <- Plan.all() do
        assert is_integer(Plan.retention_hours(key)) and Plan.retention_hours(key) > 0
      end
    end

    test "the paid plans and the beta are in the catalog" do
      assert %{name: "Beta"} = Plan.get("beta")
      assert %{name: "Pro"} = Plan.get("pro")
      assert %{name: "Studio"} = Plan.get("studio")
    end

    test "the beta caps members where Pro does not" do
      assert Plan.limit("beta", :members_per_workspace) == 10
      assert Plan.limit("pro", :members_per_workspace) == :unlimited
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
