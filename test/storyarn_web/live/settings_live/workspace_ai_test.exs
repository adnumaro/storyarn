defmodule StoryarnWeb.SettingsLive.WorkspaceAITest do
  use StoryarnWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Storyarn.AccountsFixtures
  import Storyarn.WorkspacesFixtures

  alias Storyarn.AI

  defp get_ai_vue(view) do
    LiveVue.Test.get_vue(view, name: "live/workspace/settings/WorkspaceSettingsAI")
  end

  describe "mount" do
    test "renders for admins and members, redirects viewers", %{conn: conn} do
      owner = user_fixture()
      workspace = workspace_fixture(owner)
      member = user_fixture()
      workspace_membership_fixture(workspace, member, "member")
      viewer = user_fixture()
      workspace_membership_fixture(workspace, viewer, "viewer")

      {:ok, view, _html} =
        conn
        |> log_in_user(member)
        |> live(~p"/users/settings/workspaces/#{workspace.slug}/ai")

      assert get_ai_vue(view).props["is-owner"] == false

      assert {:error, {:live_redirect, %{to: "/users/settings"}}} =
               conn
               |> recycle()
               |> log_in_user(viewer)
               |> live(~p"/users/settings/workspaces/#{workspace.slug}/ai")
    end
  end

  describe "Storyarn AI policy" do
    test "flagged owner sees allowance state and can enable managed policy", %{conn: conn} do
      owner = user_fixture()
      workspace = workspace_fixture(owner)
      FunWithFlags.enable(:ai_integrations, for_actor: owner)

      {:ok, view, _html} =
        conn
        |> log_in_user(owner)
        |> live(~p"/users/settings/workspaces/#{workspace.slug}/ai")

      vue = get_ai_vue(view)
      assert vue.props["ai"]["visible"] == true
      assert vue.props["ai"]["managedAllowed"] == false
      assert vue.props["ai"]["personalMembersAllowed"] == false
      assert vue.props["ai"]["allowance"]["status"] == "unavailable"

      render_click(view, "update_managed_ai_policy", %{"enabled" => true})

      assert {:ok, policy} = AI.get_workspace_policy(user_scope_fixture(owner), workspace.id)
      assert policy.allowed_lanes == ["managed"]
      assert get_ai_vue(view).props["ai"]["managedAllowed"] == true
    end

    test "owner can toggle member access to personal keys without changing the managed policy", %{conn: conn} do
      owner = user_fixture()
      workspace = workspace_fixture(owner)
      scope = user_scope_fixture(owner)
      FunWithFlags.enable(:ai_integrations, for_actor: owner)
      assert {:ok, _policy} = AI.update_workspace_policy(scope, workspace.id, ["managed"])

      {:ok, view, _html} =
        conn
        |> log_in_user(owner)
        |> live(~p"/users/settings/workspaces/#{workspace.slug}/ai")

      render_click(view, "update_personal_ai_members_policy", %{"enabled" => true})

      assert {:ok, enabled} = AI.get_workspace_policy(scope, workspace.id)
      assert enabled.allowed_lanes == ["managed", "personal_byok"]
      assert get_ai_vue(view).props["ai"]["managedAllowed"] == true
      assert get_ai_vue(view).props["ai"]["personalMembersAllowed"] == true

      render_click(view, "update_personal_ai_members_policy", %{"enabled" => false})

      assert {:ok, disabled} = AI.get_workspace_policy(scope, workspace.id)
      assert disabled.allowed_lanes == ["managed"]
      assert get_ai_vue(view).props["ai"]["managedAllowed"] == true
      assert get_ai_vue(view).props["ai"]["personalMembersAllowed"] == false
    end

    test "managed policy reports ownership drift explicitly and remains unchanged", %{conn: conn} do
      owner = user_fixture()
      workspace = workspace_fixture(owner)
      FunWithFlags.enable(:ai_integrations, for_actor: owner)

      {:ok, view, _html} =
        conn
        |> log_in_user(owner)
        |> live(~p"/users/settings/workspaces/#{workspace.slug}/ai")

      duplicate_owner = user_fixture()
      workspace_membership_fixture(workspace, duplicate_owner, "owner")

      html = render_click(view, "update_managed_ai_policy", %{"enabled" => true})

      assert html =~
               "Storyarn AI policy could not be updated because workspace ownership is inconsistent. Contact support before retrying."

      assert {:ok, policy} = AI.get_workspace_policy(user_scope_fixture(owner), workspace.id)
      assert policy.allowed_lanes == []
    end

    test "personal policy reports ownership drift explicitly and remains unchanged", %{conn: conn} do
      owner = user_fixture()
      workspace = workspace_fixture(owner)
      FunWithFlags.enable(:ai_integrations, for_actor: owner)

      {:ok, view, _html} =
        conn
        |> log_in_user(owner)
        |> live(~p"/users/settings/workspaces/#{workspace.slug}/ai")

      duplicate_owner = user_fixture()
      workspace_membership_fixture(workspace, duplicate_owner, "owner")

      html = render_click(view, "update_personal_ai_members_policy", %{"enabled" => true})

      assert html =~
               "Personal AI member policy could not be updated because workspace ownership is inconsistent. Contact support before retrying."

      assert {:ok, policy} = AI.get_workspace_policy(user_scope_fixture(owner), workspace.id)
      assert policy.allowed_lanes == []
    end

    test "flagged admin and member can read but cannot change managed policy", %{conn: conn} do
      owner = user_fixture()
      workspace = workspace_fixture(owner)
      owner_scope = user_scope_fixture(owner)
      assert {:ok, _policy} = AI.update_workspace_policy(owner_scope, workspace.id, ["managed"])

      for role <- ["admin", "member"] do
        user = user_fixture()
        workspace_membership_fixture(workspace, user, role)
        FunWithFlags.enable(:ai_integrations, for_actor: user)

        {:ok, view, _html} =
          conn
          |> recycle()
          |> log_in_user(user)
          |> live(~p"/users/settings/workspaces/#{workspace.slug}/ai")

        vue = get_ai_vue(view)
        assert vue.props["ai"]["visible"] == true
        assert vue.props["ai"]["managedAllowed"] == true
        assert vue.props["is-owner"] == false

        html = render_click(view, "update_managed_ai_policy", %{"enabled" => false})
        assert html =~ "Only the workspace owner can change Storyarn AI policy."
      end

      assert {:ok, policy} = AI.get_workspace_policy(owner_scope, workspace.id)
      assert policy.allowed_lanes == ["managed"]
    end

    test "flagged non-owner cannot forge a personal-policy update", %{conn: conn} do
      owner = user_fixture()
      workspace = workspace_fixture(owner)
      admin = user_fixture()
      workspace_membership_fixture(workspace, admin, "admin")
      FunWithFlags.enable(:ai_integrations, for_actor: admin)

      {:ok, view, _html} =
        conn
        |> log_in_user(admin)
        |> live(~p"/users/settings/workspaces/#{workspace.slug}/ai")

      html = render_click(view, "update_personal_ai_members_policy", %{"enabled" => true})
      assert html =~ "Only the workspace owner can change Personal AI member policy."

      assert {:ok, policy} = AI.get_workspace_policy(user_scope_fixture(admin), workspace.id)
      assert policy.allowed_lanes == []
    end

    test "AI settings stay absent when the invite flag is off", %{conn: conn} do
      owner = user_fixture()
      workspace = workspace_fixture(owner)

      {:ok, view, _html} =
        conn
        |> log_in_user(owner)
        |> live(~p"/users/settings/workspaces/#{workspace.slug}/ai")

      assert get_ai_vue(view).props["ai"]["visible"] == false
    end

    test "an unflagged owner cannot forge a managed-policy update", %{conn: conn} do
      owner = user_fixture()
      workspace = workspace_fixture(owner)

      {:ok, view, _html} =
        conn
        |> log_in_user(owner)
        |> live(~p"/users/settings/workspaces/#{workspace.slug}/ai")

      html = render_click(view, "update_managed_ai_policy", %{"enabled" => true})
      assert html =~ "Storyarn AI policy could not be updated."

      assert {:ok, policy} = AI.get_workspace_policy(user_scope_fixture(owner), workspace.id)
      assert policy.allowed_lanes == []
    end
  end
end
