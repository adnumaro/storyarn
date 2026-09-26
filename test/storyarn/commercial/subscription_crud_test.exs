defmodule Storyarn.Commercial.Billing.SubscriptionCrudTest do
  use Storyarn.DataCase, async: true

  import Ecto.Query, warn: false
  import Storyarn.AccountsFixtures
  import Storyarn.WorkspacesFixtures

  alias Storyarn.Accounts.User
  alias Storyarn.Commercial
  alias Storyarn.Commercial.Billing
  alias Storyarn.Commercial.Billing.Subscription
  alias Storyarn.Commercial.Billing.SubscriptionCrud
  alias Storyarn.Repo
  alias Storyarn.Workspaces
  alias Storyarn.Workspaces.Workspace

  setup do
    user = user_fixture()
    workspace = workspace_fixture(user)
    %{user: user, workspace: workspace}
  end

  describe "create_account_subscription/1" do
    test "the public facade returns a neutral subscription receipt" do
      user = insert_user_without_subscription!("neutral-receipt")

      assert {:ok,
              %{
                id: subscription_id,
                user_id: user_id,
                plan: "free",
                status: "active"
              } = receipt} = Commercial.create_account_subscription(user)

      assert user_id == user.id
      assert Enum.sort(Map.keys(receipt)) == [:id, :plan, :status, :user_id]
      refute Map.has_key?(receipt, :__struct__)

      assert %Subscription{id: ^subscription_id, user_id: ^user_id} =
               Repo.get(Subscription, subscription_id)
    end

    test "the public facade returns a stable neutral error for an existing subscription", %{
      user: user
    } do
      assert {:error,
              %{
                code: :subscription_already_exists,
                field_errors: %{user_id: [:already_exists]}
              }} = Commercial.create_account_subscription(user)
    end

    test "the public facade returns a stable neutral error for invalid subscription input" do
      assert {:error,
              %{
                code: :invalid_subscription,
                field_errors: %{user_id: [:required]}
              }} = Commercial.create_account_subscription(%{id: nil})
    end

    test "creates a free subscription for an account without one" do
      user = insert_user_without_subscription!("bare")

      assert {:ok, %Subscription{} = sub} = SubscriptionCrud.create_subscription(user)
      assert sub.user_id == user.id
      assert sub.plan == "free"
      assert sub.status == "active"
    end

    test "returns an error for an account that already has one", %{user: user} do
      assert {:error, changeset} = SubscriptionCrud.create_subscription(user)
      assert errors_on(changeset).user_id
    end
  end

  describe "one subscription per account" do
    test "registration creates the account's subscription", %{user: user} do
      assert [%Subscription{plan: "free", status: "active"}] = account_subscriptions(user)
    end

    test "creating another workspace does not create a subscription", %{user: user} do
      set_plan!(user, "beta", "active")

      assert {:ok, _workspace} =
               Workspaces.create_workspace_with_owner(user, %{name: "Second saga", slug: unique_slug("second")})

      assert [%Subscription{plan: "beta"}] = account_subscriptions(user)
    end
  end

  describe "plan_for/1" do
    test "a workspace takes its owner's plan", %{user: user, workspace: workspace} do
      assert SubscriptionCrud.plan_for(workspace) == "free"

      set_plan!(user, "studio", "active")

      assert SubscriptionCrud.plan_for(workspace) == "studio"
    end

    test "every workspace of one owner shares the owner's plan", %{user: user, workspace: workspace} do
      set_plan!(user, "beta", "active")

      {:ok, second} =
        Workspaces.create_workspace_with_owner(user, %{name: "Another saga", slug: unique_slug("another")})

      assert Billing.plans_for_workspace_ids([workspace.id, second.id]) ==
               %{workspace.id => "beta", second.id => "beta"}

      assert Commercial.entitlement_limit(second.id, :projects_per_workspace) == :unlimited
    end

    test "a member's own plan does not change someone else's workspace", %{workspace: workspace} do
      member = user_fixture()
      workspace_membership_fixture(workspace, member, "member")
      set_plan!(member, "studio", "active")

      assert SubscriptionCrud.plan_for(workspace) == "free"
      assert Commercial.entitlement_limit(workspace.id, :projects_per_workspace) == 3
    end

    test "returns 'free' when the owner has no subscription" do
      workspace = insert_workspace!(insert_user_without_subscription!("no-sub"), "no-sub")

      assert SubscriptionCrud.plan_for(workspace) == "free"
    end
  end

  describe "effective plan" do
    test "grants the contracted plan only while the status entitles it", %{user: user, workspace: workspace} do
      entitled = ~w(active trialing past_due)

      for status <- Subscription.statuses() do
        set_plan!(user, "pro", status)
        expected = if status in entitled, do: "pro", else: "free"

        assert SubscriptionCrud.plan_for(workspace) == expected, "status #{status}"
        assert SubscriptionCrud.plan_for_user(user.id) == expected, "status #{status}"
        assert Billing.plans_for_workspace_ids([workspace.id]) == %{workspace.id => expected}

        assert Commercial.entitlement_limit(workspace.id, :projects_per_workspace) ==
                 if(expected == "pro", do: :unlimited, else: 3)
      end
    end

    test "a canceled Pro account reports the Free limits", %{user: user, workspace: workspace} do
      set_plan!(user, "pro", "canceled")

      assert %{plan: "free", projects: %{limit: 3}} = Commercial.workspace_usage(workspace)
    end
  end

  describe "status" do
    test "rejects a status Stripe does not define", %{user: user} do
      subscription = SubscriptionCrud.get_subscription(user.id)

      changeset = Subscription.update_changeset(subscription, %{status: "suspended"})

      refute changeset.valid?
      assert {"is invalid", _} = changeset.errors[:status]
    end

    test "the database rejects an unknown status written around the changeset", %{user: user} do
      assert_raise Postgrex.Error, ~r/subscriptions_status_must_be_known/, fn ->
        Repo.update_all(
          from(subscription in Subscription, where: subscription.user_id == ^user.id),
          set: [status: "suspended"]
        )
      end
    end
  end

  describe "get_subscription/1" do
    test "returns the account's subscription", %{user: user} do
      assert %Subscription{} = SubscriptionCrud.get_subscription(user.id)
    end

    test "returns nil when not found" do
      assert is_nil(SubscriptionCrud.get_subscription(-1))
    end
  end

  describe "plans_for_workspace_ids/1" do
    test "loads several workspace plans in one query and defaults owners without a subscription", %{
      user: user,
      workspace: workspace
    } do
      owner_without_subscription = insert_user_without_subscription!("owner-without")
      workspace_without_subscription = insert_workspace!(owner_without_subscription, "without")

      Repo.update_all(
        from(subscription in Subscription, where: subscription.user_id == ^user.id),
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
    test "updates to a valid plan", %{user: user} do
      sub = SubscriptionCrud.get_subscription(user.id)

      assert {:ok, updated} = SubscriptionCrud.update_plan(sub, "free")
      assert updated.plan == "free"
    end

    test "rejects an invalid plan", %{user: user} do
      sub = SubscriptionCrud.get_subscription(user.id)

      assert {:error, changeset} = SubscriptionCrud.update_plan(sub, "nonexistent")
      assert {"is invalid", _} = changeset.errors[:plan]
    end
  end

  defp set_plan!(user, plan, status) do
    user.id
    |> SubscriptionCrud.get_subscription()
    |> Subscription.update_changeset(%{plan: plan, status: status})
    |> Repo.update!()
  end

  defp account_subscriptions(user) do
    Repo.all(from(subscription in Subscription, where: subscription.user_id == ^user.id))
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
    Enum.filter(queries, &String.contains?(&1, ~s("subscriptions")))
  end

  defp insert_user_without_subscription!(prefix) do
    %User{}
    |> Ecto.Changeset.change(%{
      email: "#{prefix}-#{System.unique_integer([:positive])}@test.com",
      confirmed_at: DateTime.utc_now(:second)
    })
    |> Repo.insert!()
  end

  defp insert_workspace!(owner, prefix) do
    %Workspace{}
    |> Ecto.Changeset.change(%{
      name: "Workspace without subscription",
      slug: unique_slug(prefix),
      owner_id: owner.id
    })
    |> Repo.insert!()
  end

  defp unique_slug(prefix), do: "#{prefix}-#{System.unique_integer([:positive])}"
end
