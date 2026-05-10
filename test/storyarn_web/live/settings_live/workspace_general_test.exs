defmodule StoryarnWeb.SettingsLive.WorkspaceGeneralTest do
  use StoryarnWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Storyarn.AccountsFixtures
  import Storyarn.WorkspacesFixtures

  alias Storyarn.Workspaces

  defp get_general_vue(view) do
    LiveVue.Test.get_vue(view, name: "live/workspace/settings/General")
  end

  describe "mount" do
    test "renders workspace general settings Vue for owner", %{conn: conn} do
      user = user_fixture()
      workspace = workspace_fixture(user, %{name: "Test Workspace"})

      {:ok, view, _html} =
        conn
        |> log_in_user(user)
        |> live(~p"/users/settings/workspaces/#{workspace.slug}/general")

      vue = get_general_vue(view)
      assert vue.component == "live/workspace/settings/General"
      assert vue.props["workspace-name"] == "Test Workspace"
      assert vue.props["is-owner"] == true
    end

    test "renders Vue for admin", %{conn: conn} do
      owner = user_fixture()
      workspace = workspace_fixture(owner, %{name: "Admin Test Workspace"})

      admin = user_fixture()
      workspace_membership_fixture(workspace, admin, "admin")

      {:ok, view, _html} =
        conn
        |> log_in_user(admin)
        |> live(~p"/users/settings/workspaces/#{workspace.slug}/general")

      vue = get_general_vue(view)
      assert vue.props["workspace-name"] == "Admin Test Workspace"
      assert vue.props["is-owner"] == false
    end

    test "is-owner=true only for owner", %{conn: conn} do
      owner = user_fixture()
      workspace = workspace_fixture(owner)

      {:ok, view, _html} =
        conn
        |> log_in_user(owner)
        |> live(~p"/users/settings/workspaces/#{workspace.slug}/general")

      vue = get_general_vue(view)
      assert vue.props["is-owner"] == true
    end

    test "is-owner=false for admin", %{conn: conn} do
      owner = user_fixture()
      workspace = workspace_fixture(owner)

      admin = user_fixture()
      workspace_membership_fixture(workspace, admin, "admin")

      {:ok, view, _html} =
        conn
        |> log_in_user(admin)
        |> live(~p"/users/settings/workspaces/#{workspace.slug}/general")

      vue = get_general_vue(view)
      assert vue.props["is-owner"] == false
    end

    test "redirects member (non-admin) to settings with error", %{conn: conn} do
      owner = user_fixture()
      workspace = workspace_fixture(owner)

      member = user_fixture()
      workspace_membership_fixture(workspace, member, "member")

      logged_in_conn = log_in_user(conn, member)

      assert {:error, {:live_redirect, %{to: "/users/settings", flash: flash}}} =
               live(logged_in_conn, ~p"/users/settings/workspaces/#{workspace.slug}/general")

      assert flash["error"] =~ "You don't have permission to manage this workspace."
    end

    test "redirects viewer to settings with error", %{conn: conn} do
      owner = user_fixture()
      workspace = workspace_fixture(owner)

      viewer = user_fixture()
      workspace_membership_fixture(workspace, viewer, "viewer")

      logged_in_conn = log_in_user(conn, viewer)

      assert {:error, {:live_redirect, %{to: "/users/settings", flash: flash}}} =
               live(logged_in_conn, ~p"/users/settings/workspaces/#{workspace.slug}/general")

      assert flash["error"] =~ "You don't have permission to manage this workspace."
    end

    test "redirects to settings when workspace not found", %{conn: conn} do
      user = user_fixture()
      logged_in_conn = log_in_user(conn, user)

      assert {:error, {:redirect, %{to: "/users/settings", flash: flash}}} =
               live(logged_in_conn, ~p"/users/settings/workspaces/nonexistent-slug/general")

      assert flash["error"] =~ "Workspace not found."
    end

    test "redirects unauthenticated user to login", %{conn: conn} do
      assert {:error, redirect} =
               live(conn, ~p"/users/settings/workspaces/some-slug/general")

      assert {:redirect, %{to: path, flash: flash}} = redirect
      assert path == ~p"/users/log-in"
      assert %{"error" => "You must log in to access this page."} = flash
    end

    test "passes current workspace values to Vue props", %{conn: conn} do
      user = user_fixture()
      workspace = workspace_fixture(user, %{description: "My test description"})

      {:ok, view, _html} =
        conn
        |> log_in_user(user)
        |> live(~p"/users/settings/workspaces/#{workspace.slug}/general")

      vue = get_general_vue(view)
      assert vue.props["workspace-name"] == workspace.name
      assert vue.props["workspace-description"] == "My test description"
      assert vue.props["source-locale"] == workspace.source_locale
      assert is_list(vue.props["language-options"])
    end
  end

  describe "save event" do
    setup %{conn: conn} do
      user = user_fixture()
      workspace = workspace_fixture(user)
      %{conn: log_in_user(conn, user), user: user, workspace: workspace}
    end

    test "updates workspace name successfully", %{conn: conn, workspace: workspace} do
      {:ok, view, _html} = live(conn, ~p"/users/settings/workspaces/#{workspace.slug}/general")

      result =
        render_click(view, "save", %{"workspace" => %{"name" => "New Workspace Name"}})

      assert result =~ "Workspace updated successfully."

      updated = Workspaces.get_workspace!(workspace.id)
      assert updated.name == "New Workspace Name"
    end

    test "updates workspace description", %{conn: conn, workspace: workspace} do
      {:ok, view, _html} = live(conn, ~p"/users/settings/workspaces/#{workspace.slug}/general")

      result =
        render_click(view, "save", %{
          "workspace" => %{"description" => "A brand new description"}
        })

      assert result =~ "Workspace updated successfully."

      updated = Workspaces.get_workspace!(workspace.id)
      assert updated.description == "A brand new description"
    end

    test "updates workspace source locale", %{conn: conn, workspace: workspace} do
      {:ok, view, _html} = live(conn, ~p"/users/settings/workspaces/#{workspace.slug}/general")

      result =
        render_click(view, "save", %{"workspace" => %{"source_locale" => "es"}})

      assert result =~ "Workspace updated successfully."

      updated = Workspaces.get_workspace!(workspace.id)
      assert updated.source_locale == "es"
    end

    test "admin can update workspace", %{conn: conn} do
      owner = user_fixture()
      workspace = workspace_fixture(owner)
      admin = user_fixture()
      workspace_membership_fixture(workspace, admin, "admin")

      {:ok, view, _html} =
        conn
        |> log_in_user(admin)
        |> live(~p"/users/settings/workspaces/#{workspace.slug}/general")

      result =
        render_click(view, "save", %{"workspace" => %{"name" => "Admin Updated Name"}})

      assert result =~ "Workspace updated successfully."
    end
  end

  describe "delete event" do
    test "owner can delete workspace", %{conn: conn} do
      user = user_fixture()
      workspace = workspace_fixture(user)

      {:ok, view, _html} =
        conn
        |> log_in_user(user)
        |> live(~p"/users/settings/workspaces/#{workspace.slug}/general")

      render_click(view, "delete", %{})

      flash = assert_redirect(view, ~p"/users/settings")
      assert flash["info"] =~ "Workspace deleted."
    end

    test "admin cannot delete workspace via event", %{conn: conn} do
      owner = user_fixture()
      workspace = workspace_fixture(owner)
      admin = user_fixture()
      workspace_membership_fixture(workspace, admin, "admin")

      {:ok, view, _html} =
        conn
        |> log_in_user(admin)
        |> live(~p"/users/settings/workspaces/#{workspace.slug}/general")

      result = render_click(view, "delete", %{})
      assert result =~ "Only the workspace owner can delete the workspace."

      # Workspace should still exist
      assert Workspaces.get_workspace!(workspace.id)
    end
  end
end
