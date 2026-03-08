defmodule Storyarn.Billing.SubscriptionCrudTest do
  use Storyarn.DataCase, async: true

  alias Storyarn.Billing.{Subscription, SubscriptionCrud}

  import Storyarn.AccountsFixtures
  import Storyarn.WorkspacesFixtures

  setup do
    user = user_fixture()
    workspace = workspace_fixture(user)
    %{user: user, workspace: workspace}
  end

  describe "create_subscription/1" do
    test "creates free subscription for a workspace without one" do
      # Create a workspace without the auto-subscription by inserting directly
      workspace =
        %Storyarn.Workspaces.Workspace{}
        |> Ecto.Changeset.change(%{
          name: "Bare Workspace",
          slug: "bare-workspace-#{System.unique_integer([:positive])}",
          owner_id:
            (%Storyarn.Accounts.User{}
             |> Ecto.Changeset.change(%{
               email: "bare#{System.unique_integer([:positive])}@test.com",
               confirmed_at: DateTime.utc_now(:second)
             })
             |> Storyarn.Repo.insert!()).id
        })
        |> Storyarn.Repo.insert!()

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
        %Storyarn.Workspaces.Workspace{}
        |> Ecto.Changeset.change(%{
          name: "No Sub Workspace",
          slug: "no-sub-#{System.unique_integer([:positive])}",
          owner_id:
            (%Storyarn.Accounts.User{}
             |> Ecto.Changeset.change(%{
               email: "nosub#{System.unique_integer([:positive])}@test.com",
               confirmed_at: DateTime.utc_now(:second)
             })
             |> Storyarn.Repo.insert!()).id
        })
        |> Storyarn.Repo.insert!()

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
end
