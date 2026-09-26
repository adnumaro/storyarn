defmodule Storyarn.Commercial.Billing.AccountLimitsTest do
  use Storyarn.DataCase, async: true

  import Ecto.Query, warn: false
  import Storyarn.AccountsFixtures
  import Storyarn.ProjectsFixtures
  import Storyarn.WorkspacesFixtures

  alias Storyarn.Commercial
  alias Storyarn.Commercial.Billing
  alias Storyarn.Commercial.Billing.PlanPeriod
  alias Storyarn.Commercial.Billing.Subscription
  alias Storyarn.Commercial.Billing.SubscriptionCrud
  alias Storyarn.Repo
  alias Storyarn.Workspaces

  setup do
    owner = user_fixture()
    %{owner: owner, workspace: workspace_fixture(owner)}
  end

  describe "a lower plan" do
    test "makes an account over its workspace and editor caps read-only", %{owner: owner, workspace: workspace} do
      change_plan!(owner, "beta")
      {:ok, _second} = Workspaces.create_workspace_with_owner(owner, %{name: "Second saga", slug: unique_slug()})

      for _ <- 1..2, do: workspace_membership_fixture(workspace, user_fixture(), "member")

      change_plan!(owner, "free")

      assert subscription(owner).read_only_reasons == ["workspaces_per_user", "editors_per_account"]
      assert %DateTime{} = subscription(owner).read_only_since
      assert Commercial.workspace_read_only_reasons(workspace.id) == ["workspaces_per_user", "editors_per_account"]
      assert Commercial.account_read_only_reasons(owner.id) == ["workspaces_per_user", "editors_per_account"]
    end

    test "counts projects per workspace", %{owner: owner, workspace: workspace} do
      change_plan!(owner, "beta")
      for _ <- 1..4, do: project_fixture(owner, %{workspace: workspace})

      change_plan!(owner, "free")

      assert subscription(owner).read_only_reasons == ["projects_per_workspace"]
    end

    test "counts items per project", %{owner: owner, workspace: workspace} do
      change_plan!(owner, "beta")
      project = project_fixture(owner, %{workspace: workspace})
      insert_flow_nodes!(project, 701)

      change_plan!(owner, "free")

      assert "items_per_project" in subscription(owner).read_only_reasons
    end

    test "counts storage per workspace", %{owner: owner, workspace: workspace} do
      change_plan!(owner, "beta")
      project = project_fixture(owner, %{workspace: workspace})
      for _ <- 1..11, do: Storyarn.AssetsFixtures.asset_fixture(project, owner, %{size: 52_428_800})

      change_plan!(owner, "free")

      assert subscription(owner).read_only_reasons == ["storage_bytes_per_workspace"]
    end

    test "never locks for count limits: backups, named versions and templates", %{owner: owner, workspace: workspace} do
      change_plan!(owner, "beta")
      project = project_fixture(owner, %{workspace: workspace})
      for _ <- 1..3, do: full_project_snapshot_fixture(project)

      change_plan!(owner, "free")

      assert subscription(owner).read_only_reasons == []
      assert Commercial.workspace_read_only_reasons(workspace.id) == []
    end

    test "leaves an account within its new limits writable", %{owner: owner, workspace: workspace} do
      change_plan!(owner, "studio")
      change_plan!(owner, "free")

      assert subscription(owner).read_only_reasons == []
      assert is_nil(subscription(owner).read_only_since)
      assert Commercial.workspace_read_only_reasons(workspace.id) == []
    end
  end

  describe "unlocking" do
    test "happens as soon as deletions bring the account back within limits", %{owner: owner, workspace: workspace} do
      change_plan!(owner, "beta")
      {:ok, second} = Workspaces.create_workspace_with_owner(owner, %{name: "Second saga", slug: unique_slug()})
      change_plan!(owner, "free")
      assert Commercial.workspace_read_only_reasons(workspace.id) == ["workspaces_per_user"]

      Repo.delete!(second)

      assert Commercial.workspace_read_only_reasons(workspace.id) == []
      assert subscription(owner).read_only_reasons == []
      assert is_nil(subscription(owner).read_only_since)
    end

    test "happens when the plan covers the usage again", %{owner: owner, workspace: workspace} do
      change_plan!(owner, "beta")
      {:ok, _second} = Workspaces.create_workspace_with_owner(owner, %{name: "Second saga", slug: unique_slug()})
      change_plan!(owner, "free")
      assert Commercial.workspace_read_only_reasons(workspace.id) == ["workspaces_per_user"]

      change_plan!(owner, "pro")

      assert Commercial.workspace_read_only_reasons(workspace.id) == []
    end

    test "checking a writable workspace costs one query", %{workspace: workspace} do
      {reasons, queries} = capture_queries(fn -> Commercial.workspace_read_only_reasons(workspace.id) end)

      assert reasons == []
      assert length(queries) == 1
    end
  end

  describe "plan periods" do
    test "every account starts with a period on its plan", %{owner: owner} do
      assert [%PlanPeriod{plan: "free"}] = periods(owner)
    end

    test "a new period starts only when the effective plan changes", %{owner: owner} do
      # Periods start on the second; move the first one back so the change
      # below starts its own.
      Repo.update_all(from(period in PlanPeriod, where: period.user_id == ^owner.id),
        set: [started_at: DateTime.shift(DateTime.utc_now(:second), hour: -1)]
      )

      change_plan!(owner, "studio")
      subscription = subscription(owner)

      subscription
      |> Subscription.update_changeset(%{status: "past_due"})
      |> Repo.update!()

      {:ok, _reasons} = Billing.refresh_account_limits(owner.id)

      assert Enum.map(periods(owner), & &1.plan) == ["free", "studio"]
    end
  end

  defp change_plan!(user, plan) do
    {:ok, _subscription} = user.id |> SubscriptionCrud.get_subscription() |> SubscriptionCrud.update_plan(plan)
    :ok
  end

  defp subscription(user), do: SubscriptionCrud.get_subscription(user.id)

  defp periods(user) do
    Repo.all(from(period in PlanPeriod, where: period.user_id == ^user.id, order_by: [asc: period.id]))
  end

  defp unique_slug, do: "saga-#{System.unique_integer([:positive])}"

  defp insert_flow_nodes!(project, count) do
    {:ok, flow} = Storyarn.Flows.create_flow(project, %{name: "Big"})
    now = DateTime.utc_now(:second)

    Repo.insert_all(
      "flow_nodes",
      for i <- 1..count do
        %{
          flow_id: flow.id,
          type: "dialogue",
          position_x: i * 1.0,
          position_y: 0.0,
          data: %{},
          inserted_at: now,
          updated_at: now
        }
      end
    )
  end

  defp capture_queries(fun) do
    handler_id = "account-limits-queries-#{System.unique_integer([:positive])}"
    test_pid = self()
    ref = make_ref()

    :ok =
      :telemetry.attach(
        handler_id,
        [:storyarn, :repo, :query],
        fn _event, _measurements, %{query: query}, {pid, marker} ->
          if self() == pid, do: send(pid, {marker, query})
        end,
        {test_pid, ref}
      )

    try do
      result = fun.()
      {result, drain(ref, [])}
    after
      :telemetry.detach(handler_id)
    end
  end

  defp drain(ref, queries) do
    receive do
      {^ref, query} -> drain(ref, [query | queries])
    after
      0 -> Enum.reverse(queries)
    end
  end
end
