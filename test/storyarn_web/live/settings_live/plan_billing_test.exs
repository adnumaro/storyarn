defmodule StoryarnWeb.SettingsLive.PlanBillingTest do
  use StoryarnWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Storyarn.AccountsFixtures
  import Storyarn.WorkspacesFixtures

  alias Storyarn.Commercial.Billing.Subscription
  alias Storyarn.Repo

  defp set_plan!(user, plan) do
    Subscription
    |> Repo.get_by!(user_id: user.id)
    |> Subscription.update_changeset(%{plan: plan, status: "active"})
    |> Repo.update!()
  end

  defp get_plan_vue(view) do
    LiveVue.Test.get_vue(view, name: "live/account/settings/AccountSettingsPlanBilling")
  end

  test "shows the account's plan, editor seats and owned workspaces", %{conn: conn} do
    owner = user_fixture()
    workspace = workspace_fixture(owner)
    workspace_membership_fixture(workspace, user_fixture(), "member")
    workspace_membership_fixture(workspace, user_fixture(), "viewer")

    {:ok, view, _html} = conn |> log_in_user(owner) |> live(~p"/users/settings/plan")

    vue = get_plan_vue(view)

    assert vue.props["account"] == %{
             "plan" => %{"key" => "free", "name" => "Free"},
             "seats" => %{"used" => 2, "limit" => 2},
             "workspaces" => %{"used" => 1, "limit" => 1}
           }

    assert vue.props["contact-path"] == "/contact"
  end

  test "paid plans report seats per paid seat", %{conn: conn} do
    owner = user_fixture()
    set_plan!(owner, "studio")

    {:ok, view, _html} = conn |> log_in_user(owner) |> live(~p"/users/settings/plan")

    assert %{"plan" => %{"key" => "studio"}, "seats" => %{"limit" => "paid_seats"}, "workspaces" => %{"limit" => 10}} =
             get_plan_vue(view).props["account"]
  end

  test "an editor in someone else's workspace sees only their own account", %{conn: conn} do
    other_owner = user_fixture()
    set_plan!(other_owner, "beta")
    editor = user_fixture()
    workspace_membership_fixture(workspace_fixture(other_owner), editor, "admin")

    {:ok, view, _html} = conn |> log_in_user(editor) |> live(~p"/users/settings/plan")

    assert get_plan_vue(view).props["account"] == %{
             "plan" => %{"key" => "free", "name" => "Free"},
             "seats" => %{"used" => 1, "limit" => 2},
             "workspaces" => %{"used" => 1, "limit" => 1}
           }
  end
end
