defmodule StoryarnWeb.SettingsLive.WorkspacePlanTest do
  use StoryarnWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Storyarn.AccountsFixtures
  import Storyarn.ProjectsFixtures
  import Storyarn.WorkspacesFixtures

  defp get_plan_vue(view) do
    LiveVue.Test.get_vue(view, name: "live/workspace/settings/WorkspaceSettingsPlan")
  end

  describe "mount" do
    test "shows the plan and the workspace-wide meters to the owner", %{conn: conn} do
      owner = user_fixture()
      workspace = workspace_fixture(owner)
      project_fixture(owner, %{workspace: workspace})
      admin = user_fixture()
      workspace_membership_fixture(workspace, admin, "admin")

      {:ok, view, _html} =
        conn
        |> log_in_user(owner)
        |> live(~p"/users/settings/workspaces/#{workspace.slug}/plan")

      usage = get_plan_vue(view).props["usage"]
      assert usage["plan"]["key"] == "free"
      assert usage["projects"]["used"] == 1
      assert is_integer(usage["projects"]["limit"]) or is_nil(usage["projects"]["limit"])
      assert usage["members"]["used"] == 2
      assert is_binary(usage["storageBytes"]["used"])
      assert usage["storage"]["limitKind"] in ["limited", "unlimited", "unknown"]
      assert get_plan_vue(view).props["contact-path"] == "/contact"
    end

    test "renders for an admin", %{conn: conn} do
      owner = user_fixture()
      workspace = workspace_fixture(owner)
      admin = user_fixture()
      workspace_membership_fixture(workspace, admin, "admin")

      {:ok, view, _html} =
        conn
        |> log_in_user(admin)
        |> live(~p"/users/settings/workspaces/#{workspace.slug}/plan")

      assert get_plan_vue(view).props["usage"]["plan"]["key"] == "free"
    end

    test "redirects members and viewers to their own settings", %{conn: conn} do
      owner = user_fixture()
      workspace = workspace_fixture(owner)

      for role <- ["member", "viewer"] do
        user = user_fixture()
        workspace_membership_fixture(workspace, user, role)

        assert {:error, {:live_redirect, %{to: "/users/settings"}}} =
                 conn
                 |> recycle()
                 |> log_in_user(user)
                 |> live(~p"/users/settings/workspaces/#{workspace.slug}/plan")
      end
    end
  end
end
