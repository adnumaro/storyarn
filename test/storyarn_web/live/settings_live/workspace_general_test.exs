defmodule StoryarnWeb.SettingsLive.WorkspaceGeneralTest do
  use StoryarnWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Storyarn.AccountsFixtures
  import Storyarn.WorkspacesFixtures

  alias Storyarn.Workspaces

  describe "mount" do
    test "renders workspace general settings page for owner", %{conn: conn} do
      user = user_fixture()
      workspace = workspace_fixture(user)

      {:ok, _view, html} =
        conn
        |> log_in_user(user)
        |> live(~p"/users/settings/workspaces/#{workspace.slug}/general")

      assert html =~ "General"
      assert html =~ workspace.name
      assert html =~ "Workspace name"
      assert html =~ "Save Changes"
    end

    test "renders workspace general settings page for admin", %{conn: conn} do
      owner = user_fixture()
      workspace = workspace_fixture(owner)

      admin = user_fixture()
      workspace_membership_fixture(workspace, admin, "admin")

      {:ok, _view, html} =
        conn
        |> log_in_user(admin)
        |> live(~p"/users/settings/workspaces/#{workspace.slug}/general")

      assert html =~ "General"
      assert html =~ workspace.name
    end

    test "shows danger zone only for owner", %{conn: conn} do
      owner = user_fixture()
      workspace = workspace_fixture(owner)

      {:ok, _view, html} =
        conn
        |> log_in_user(owner)
        |> live(~p"/users/settings/workspaces/#{workspace.slug}/general")

      assert html =~ "Danger Zone"
      assert html =~ "Delete Workspace"
    end

    test "hides danger zone for admin", %{conn: conn} do
      owner = user_fixture()
      workspace = workspace_fixture(owner)

      admin = user_fixture()
      workspace_membership_fixture(workspace, admin, "admin")

      {:ok, _view, html} =
        conn
        |> log_in_user(admin)
        |> live(~p"/users/settings/workspaces/#{workspace.slug}/general")

      refute html =~ "Danger Zone"
      refute html =~ "Delete Workspace"
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

      assert {:error, {:live_redirect, %{to: "/users/settings", flash: flash}}} =
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

    test "shows form fields with current workspace values", %{conn: conn} do
      user = user_fixture()
      workspace = workspace_fixture(user, %{description: "My test description"})

      {:ok, view, html} =
        conn
        |> log_in_user(user)
        |> live(~p"/users/settings/workspaces/#{workspace.slug}/general")

      assert html =~ "Workspace name"
      assert html =~ "Description"
      assert html =~ "Banner URL"
      assert html =~ "Source language"
      assert has_element?(view, "input[name='workspace[name]']")
    end
  end

  describe "validate event" do
    setup %{conn: conn} do
      user = user_fixture()
      workspace = workspace_fixture(user)
      %{conn: log_in_user(conn, user), user: user, workspace: workspace}
    end

    test "validates form on change", %{conn: conn, workspace: workspace} do
      {:ok, view, _html} = live(conn, ~p"/users/settings/workspaces/#{workspace.slug}/general")

      result =
        view
        |> form("form[phx-submit='save']", %{"workspace" => %{"name" => "Updated Name"}})
        |> render_change()

      assert result =~ "Updated Name"
    end

    test "shows validation error for empty name", %{conn: conn, workspace: workspace} do
      {:ok, view, _html} = live(conn, ~p"/users/settings/workspaces/#{workspace.slug}/general")

      result =
        view
        |> form("form[phx-submit='save']", %{"workspace" => %{"name" => ""}})
        |> render_change()

      assert result =~ "can&#39;t be blank"
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
        view
        |> form("form[phx-submit='save']", %{"workspace" => %{"name" => "New Workspace Name"}})
        |> render_submit()

      assert result =~ "Workspace updated successfully."

      updated = Workspaces.get_workspace!(workspace.id)
      assert updated.name == "New Workspace Name"
    end

    test "updates workspace description", %{conn: conn, workspace: workspace} do
      {:ok, view, _html} = live(conn, ~p"/users/settings/workspaces/#{workspace.slug}/general")

      result =
        view
        |> form("form[phx-submit='save']", %{
          "workspace" => %{"description" => "A brand new description"}
        })
        |> render_submit()

      assert result =~ "Workspace updated successfully."

      updated = Workspaces.get_workspace!(workspace.id)
      assert updated.description == "A brand new description"
    end

    test "updates workspace source locale", %{conn: conn, workspace: workspace} do
      {:ok, view, _html} = live(conn, ~p"/users/settings/workspaces/#{workspace.slug}/general")

      result =
        view
        |> form("form[phx-submit='save']", %{"workspace" => %{"source_locale" => "es"}})
        |> render_submit()

      assert result =~ "Workspace updated successfully."

      updated = Workspaces.get_workspace!(workspace.id)
      assert updated.source_locale == "es"
    end

    test "shows validation error on invalid submit", %{conn: conn, workspace: workspace} do
      {:ok, view, _html} = live(conn, ~p"/users/settings/workspaces/#{workspace.slug}/general")

      result =
        view
        |> form("form[phx-submit='save']", %{"workspace" => %{"name" => ""}})
        |> render_submit()

      assert result =~ "can&#39;t be blank"
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
        view
        |> form("form[phx-submit='save']", %{
          "workspace" => %{"name" => "Admin Updated Name"}
        })
        |> render_submit()

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

      # Push the delete event directly (modal confirm triggers JS.push("delete"))
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
