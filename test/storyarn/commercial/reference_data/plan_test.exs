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
      assert is_integer(free[:limits][:editors_per_account])
      assert is_integer(free[:limits][:storage_bytes_per_workspace])
    end
  end

  describe "catalog" do
    @workspace_resources ~w(
      workspaces_per_user projects_per_workspace items_per_project storage_bytes_per_workspace
      project_templates_per_workspace project_template_versions_per_template
      named_versions_per_project project_snapshots_per_project
    )a

    @mib 1024 * 1024
    @gib 1024 * @mib
    @day 24

    # The catalog approved for ENG-240.
    @catalog %{
      "free" => %{
        workspaces_per_user: 1,
        storage_bytes_per_workspace: 500 * @mib,
        editors_per_account: 2,
        projects_per_workspace: 3,
        items_per_project: 700,
        named_versions_per_project: 10,
        project_snapshots_per_project: 2,
        project_templates_per_workspace: 10,
        project_template_versions_per_template: 20,
        trash_retention_hours: 24
      },
      "beta" => %{
        workspaces_per_user: 3,
        storage_bytes_per_workspace: 10 * @gib,
        editors_per_account: 10,
        projects_per_workspace: :unlimited,
        items_per_project: :unlimited,
        named_versions_per_project: :unlimited,
        project_snapshots_per_project: 20,
        project_templates_per_workspace: 50,
        project_template_versions_per_template: 100,
        trash_retention_hours: 30 * @day
      },
      "pro" => %{
        workspaces_per_user: 3,
        storage_bytes_per_workspace: 10 * @gib,
        editors_per_account: :paid_seats,
        projects_per_workspace: :unlimited,
        items_per_project: :unlimited,
        named_versions_per_project: :unlimited,
        project_snapshots_per_project: 20,
        project_templates_per_workspace: 50,
        project_template_versions_per_template: 100,
        trash_retention_hours: 30 * @day
      },
      "studio" => %{
        workspaces_per_user: 10,
        storage_bytes_per_workspace: 20 * @gib,
        editors_per_account: :paid_seats,
        projects_per_workspace: :unlimited,
        items_per_project: :unlimited,
        named_versions_per_project: :unlimited,
        project_snapshots_per_project: 100,
        project_templates_per_workspace: :unlimited,
        project_template_versions_per_template: :unlimited,
        trash_retention_hours: 90 * @day
      }
    }

    test "every plan carries exactly the approved limits" do
      assert Map.new(Plan.all(), fn {key, %{limits: limits}} -> {key, limits} end) == @catalog
    end

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

    test "Free and Beta cap editors while the paid plans sell seats" do
      assert Plan.limit("free", :editors_per_account) == 2
      assert Plan.limit("beta", :editors_per_account) == 10
      assert Plan.limit("pro", :editors_per_account) == :paid_seats
      assert Plan.limit("studio", :editors_per_account) == :paid_seats
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
