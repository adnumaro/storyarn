defmodule Storyarn.Platform.Billing.SubscriptionCrudTest do
  use Storyarn.DataCase, async: true

  import Ecto.Query, warn: false
  import Storyarn.AccountsFixtures
  import Storyarn.WorkspacesFixtures

  alias Storyarn.Accounts.User
  alias Storyarn.Platform.Billing
  alias Storyarn.Platform.Billing.Subscription
  alias Storyarn.Platform.Billing.SubscriptionCrud
  alias Storyarn.Repo
  alias Storyarn.Workspaces.Workspace

  setup do
    user = user_fixture()
    workspace = workspace_fixture(user)
    %{user: user, workspace: workspace}
  end

  describe "create_subscription/1" do
    test "creates free subscription for a workspace without one" do
      # Create a workspace without the auto-subscription by inserting directly
      workspace =
        %Workspace{}
        |> Ecto.Changeset.change(%{
          name: "Bare Workspace",
          slug: "bare-workspace-#{System.unique_integer([:positive])}",
          owner_id:
            (%User{}
             |> Ecto.Changeset.change(%{
               email: "bare#{System.unique_integer([:positive])}@test.com",
               confirmed_at: DateTime.utc_now(:second)
             })
             |> Repo.insert!()).id
        })
        |> Repo.insert!()

      assert {:ok, %Subscription{} = sub} = SubscriptionCrud.create_subscription(workspace)
      assert sub.workspace_id == workspace.id
      assert sub.plan == "free"
      assert sub.status == "active"
    end

    test "returns error for duplicate workspace", %{workspace: workspace} do
      # workspace_fixture already creates a subscription via workspace creation
      assert {:error, changeset} = SubscriptionCrud.create_subscription(workspace)
      assert errors_on(changeset).workspace_id
    end
  end

  describe "plan_for/1" do
    test "returns plan from subscription", %{workspace: workspace} do
      # workspace already has a "free" subscription from creation
      assert SubscriptionCrud.plan_for(workspace) == "free"
    end

    test "returns 'free' when no subscription exists" do
      # Create workspace without subscription
      workspace =
        %Workspace{}
        |> Ecto.Changeset.change(%{
          name: "No Sub Workspace",
          slug: "no-sub-#{System.unique_integer([:positive])}",
          owner_id:
            (%User{}
             |> Ecto.Changeset.change(%{
               email: "nosub#{System.unique_integer([:positive])}@test.com",
               confirmed_at: DateTime.utc_now(:second)
             })
             |> Repo.insert!()).id
        })
        |> Repo.insert!()

      assert SubscriptionCrud.plan_for(workspace) == "free"
    end
  end

  describe "get_subscription/1" do
    test "returns subscription", %{workspace: workspace} do
      # workspace already has a subscription from creation
      assert %Subscription{} = SubscriptionCrud.get_subscription(workspace.id)
    end

    test "returns nil when not found" do
      assert is_nil(SubscriptionCrud.get_subscription(-1))
    end
  end

  describe "plans_for_workspace_ids/1" do
    test "loads several workspace plans in one query and defaults missing subscriptions", %{
      workspace: workspace
    } do
      workspace_without_subscription = workspace_fixture(user_fixture())

      Repo.delete_all(
        from(subscription in Subscription,
          where: subscription.workspace_id == ^workspace_without_subscription.id
        )
      )

      Repo.update_all(
        from(subscription in Subscription, where: subscription.workspace_id == ^workspace.id),
        set: [plan: "legacy-paid"]
      )

      {plans, queries} =
        capture_queries(fn ->
          Billing.plans_for_workspace_ids([
            workspace.id,
            workspace_without_subscription.id,
            workspace.id
          ])
        end)

      assert plans == %{
               workspace.id => "legacy-paid",
               workspace_without_subscription.id => "free"
             }

      assert length(subscription_queries(queries)) == 1
    end

    test "does not query subscriptions for an empty workspace list" do
      {plans, queries} = capture_queries(fn -> Billing.plans_for_workspace_ids([]) end)

      assert plans == %{}
      assert subscription_queries(queries) == []
    end
  end

  describe "update_plan/2" do
    test "updates to a valid plan", %{workspace: workspace} do
      sub = SubscriptionCrud.get_subscription(workspace.id)

      assert {:ok, updated} = SubscriptionCrud.update_plan(sub, "free")
      assert updated.plan == "free"
    end

    test "rejects an invalid plan", %{workspace: workspace} do
      sub = SubscriptionCrud.get_subscription(workspace.id)

      assert {:error, changeset} = SubscriptionCrud.update_plan(sub, "nonexistent")
      assert {"is invalid", _} = changeset.errors[:plan]
    end
  end

  defp capture_queries(fun) when is_function(fun, 0) do
    handler_id = "bulk-plan-query-budget-#{System.unique_integer([:positive])}"
    marker = make_ref()
    test_pid = self()

    :ok =
      :telemetry.attach(
        handler_id,
        [:storyarn, :repo, :query],
        fn _event, _measurements, %{query: query}, {pid, ref} ->
          if self() == pid, do: send(pid, {ref, query})
        end,
        {test_pid, marker}
      )

    try do
      {fun.(), drain_queries(marker)}
    after
      :telemetry.detach(handler_id)
    end
  end

  defp drain_queries(marker, queries \\ []) do
    receive do
      {^marker, query} -> drain_queries(marker, [query | queries])
    after
      0 -> Enum.reverse(queries)
    end
  end

  defp subscription_queries(queries) do
    Enum.filter(queries, &String.contains?(&1, ~s(FROM "subscriptions")))
  end
end
