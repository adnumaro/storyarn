defmodule StoryarnWeb.SettingsLive.WorkspaceUsageTest do
  use StoryarnWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Storyarn.AccountsFixtures
  import Storyarn.ProjectsFixtures
  import Storyarn.WorkspacesFixtures

  alias Storyarn.Commercial.Billing.Subscription
  alias Storyarn.Repo

  # The plan belongs to the workspace's owner.
  defp subscribe!(workspace, plan) do
    Subscription
    |> Repo.get_by!(user_id: workspace.owner_id)
    |> Subscription.update_changeset(%{plan: plan, status: "active"})
    |> Repo.update!()
  end

  defp get_usage_vue(view) do
    LiveVue.Test.get_vue(view, name: "live/workspace/settings/WorkspaceSettingsUsage")
  end

  defp usage_path(workspace), do: ~p"/users/settings/workspaces/#{workspace.slug}/usage"

  describe "mount" do
    test "shows the workspace-wide meters and links the owner to Plan & billing", %{conn: conn} do
      owner = user_fixture()
      workspace = workspace_fixture(owner)
      project_fixture(owner, %{workspace: workspace})

      {:ok, view, _html} = conn |> log_in_user(owner) |> live(usage_path(workspace))

      vue = get_usage_vue(view)
      usage = vue.props["usage"]
      assert usage["projects"] == %{"used" => 1, "limit" => 3}
      assert usage["storageBytes"]["limit"] == Integer.to_string(500 * 1024 * 1024)
      assert usage["storage"]["limitKind"] == "limited"
      assert vue.props["plan-path"] == "/users/settings/plan"

      # Seats are an account total: they stay on the owner's Plan & billing page.
      refute Map.has_key?(usage, "members")
      refute Map.has_key?(usage, "plan")
    end

    test "takes its limits from the owner's plan", %{conn: conn} do
      owner = user_fixture()
      workspace = workspace_fixture(owner)
      subscribe!(workspace, "pro")

      {:ok, view, _html} = conn |> log_in_user(owner) |> live(usage_path(workspace))

      assert get_usage_vue(view).props["usage"]["projects"] == %{"used" => 0, "limit" => "unlimited"}
    end

    test "shows the totals to admins and members, without the plan link", %{conn: conn} do
      owner = user_fixture()
      workspace = workspace_fixture(owner)

      for role <- ["admin", "member"] do
        user = user_fixture()
        workspace_membership_fixture(workspace, user, role)

        {:ok, view, _html} = conn |> recycle() |> log_in_user(user) |> live(usage_path(workspace))

        vue = get_usage_vue(view)
        assert vue.props["usage"]["projects"]["limit"] == 3, role
        assert is_nil(vue.props["plan-path"]), role
      end
    end

    test "sends away a member demoted to viewer while the page is open", %{conn: conn} do
      owner = user_fixture()
      workspace = workspace_fixture(owner)
      member = user_fixture()
      membership = workspace_membership_fixture(workspace, member, "member")

      {:ok, view, _html} = conn |> log_in_user(member) |> live(usage_path(workspace))
      assert get_usage_vue(view).props["usage"]["projects"]

      {:ok, _viewer} =
        Storyarn.Workspaces.update_member_role(user_scope_fixture(owner), workspace.id, membership.id, "viewer")

      assert_redirect(view, "/users/settings")
    end

    test "sends away a member removed while the page is open", %{conn: conn} do
      owner = user_fixture()
      workspace = workspace_fixture(owner)
      member = user_fixture()
      membership = workspace_membership_fixture(workspace, member, "admin")

      {:ok, view, _html} = conn |> log_in_user(member) |> live(usage_path(workspace))

      {:ok, _removed} = Storyarn.Workspaces.remove_member(user_scope_fixture(owner), workspace.id, membership.id)

      assert_redirect(view, "/users/settings")
    end

    test "stays open for the members who still see the totals", %{conn: conn} do
      owner = user_fixture()
      workspace = workspace_fixture(owner)
      member = user_fixture()
      workspace_membership_fixture(workspace, member, "member")
      other = workspace_membership_fixture(workspace, user_fixture(), "member")

      {:ok, view, _html} = conn |> log_in_user(member) |> live(usage_path(workspace))

      {:ok, _viewer} =
        Storyarn.Workspaces.update_member_role(user_scope_fixture(owner), workspace.id, other.id, "viewer")

      assert render(view)
      assert get_usage_vue(view).props["usage"]["projects"]["limit"] == 3
    end

    test "redirects viewers, who receive no workspace totals", %{conn: conn} do
      owner = user_fixture()
      workspace = workspace_fixture(owner)
      viewer = user_fixture()
      workspace_membership_fixture(workspace, viewer, "viewer")

      assert {:error, {:live_redirect, %{to: "/users/settings"}}} =
               conn |> log_in_user(viewer) |> live(usage_path(workspace))
    end

    test "redirects someone who is only a member of one of its projects", %{conn: conn} do
      owner = user_fixture()
      workspace = workspace_fixture(owner)
      project = project_fixture(owner, %{workspace: workspace})
      project_editor = user_fixture()
      membership_fixture(project, project_editor, "editor")

      assert {:error, {:live_redirect, %{to: "/users/settings"}}} =
               conn |> log_in_user(project_editor) |> live(usage_path(workspace))
    end
  end
end
