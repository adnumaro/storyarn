defmodule StoryarnWeb.SettingsLive.WorkspaceMembersTest do
  use StoryarnWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Storyarn.AccountsFixtures
  import Storyarn.WorkspacesFixtures

  alias Storyarn.Workspaces

  describe "mount" do
    test "renders workspace members page for owner", %{conn: conn} do
      user = user_fixture()
      workspace = workspace_fixture(user)

      {:ok, _view, html} =
        conn
        |> log_in_user(user)
        |> live(~p"/users/settings/workspaces/#{workspace.slug}/members")

      assert html =~ "Members"
      assert html =~ "Team Members"
      assert html =~ "Request member invitation"
      assert html =~ "Request Invitation"
    end

    test "renders workspace members page for admin", %{conn: conn} do
      owner = user_fixture()
      workspace = workspace_fixture(owner)

      admin = user_fixture()
      workspace_membership_fixture(workspace, admin, "admin")

      {:ok, _view, html} =
        conn
        |> log_in_user(admin)
        |> live(~p"/users/settings/workspaces/#{workspace.slug}/members")

      assert html =~ "Members"
      assert html =~ "Team Members"
    end

    test "shows existing members in the list", %{conn: conn} do
      owner = user_fixture()
      workspace = workspace_fixture(owner)

      member = user_fixture()
      workspace_membership_fixture(workspace, member, "member")

      {:ok, _view, html} =
        conn
        |> log_in_user(owner)
        |> live(~p"/users/settings/workspaces/#{workspace.slug}/members")

      assert html =~ owner.email
      assert html =~ member.email
    end

    test "redirects member (non-admin) to settings with error", %{conn: conn} do
      owner = user_fixture()
      workspace = workspace_fixture(owner)

      member = user_fixture()
      workspace_membership_fixture(workspace, member, "member")

      logged_in_conn = log_in_user(conn, member)

      assert {:error, {:live_redirect, %{to: "/users/settings", flash: flash}}} =
               live(logged_in_conn, ~p"/users/settings/workspaces/#{workspace.slug}/members")

      assert flash["error"] =~ "You don't have permission to manage this workspace."
    end

    test "redirects viewer to settings with error", %{conn: conn} do
      owner = user_fixture()
      workspace = workspace_fixture(owner)

      viewer = user_fixture()
      workspace_membership_fixture(workspace, viewer, "viewer")

      logged_in_conn = log_in_user(conn, viewer)

      assert {:error, {:live_redirect, %{to: "/users/settings", flash: flash}}} =
               live(logged_in_conn, ~p"/users/settings/workspaces/#{workspace.slug}/members")

      assert flash["error"] =~ "You don't have permission to manage this workspace."
    end

    test "redirects to settings when workspace not found", %{conn: conn} do
      user = user_fixture()
      logged_in_conn = log_in_user(conn, user)

      assert {:error, {:live_redirect, %{to: "/users/settings", flash: flash}}} =
               live(logged_in_conn, ~p"/users/settings/workspaces/nonexistent-slug/members")

      assert flash["error"] =~ "Workspace not found."
    end

    test "redirects unauthenticated user to login", %{conn: conn} do
      assert {:error, redirect} =
               live(conn, ~p"/users/settings/workspaces/some-slug/members")

      assert {:redirect, %{to: path, flash: flash}} = redirect
      assert path == ~p"/users/log-in"
      assert %{"error" => "You must log in to access this page."} = flash
    end

    test "shows invite form with email and role fields", %{conn: conn} do
      user = user_fixture()
      workspace = workspace_fixture(user)

      {:ok, view, _html} =
        conn
        |> log_in_user(user)
        |> live(~p"/users/settings/workspaces/#{workspace.slug}/members")

      assert has_element?(view, "#invite-form")
      assert has_element?(view, "input[name='invite[email]']")
      assert has_element?(view, "select[name='invite[role]']")
    end
  end

  describe "send_invitation event" do
    setup %{conn: conn} do
      user = user_fixture()
      workspace = workspace_fixture(user)
      %{conn: log_in_user(conn, user), user: user, workspace: workspace}
    end

    test "sends invitation request to admin", %{conn: conn, workspace: workspace} do
      {:ok, view, _html} = live(conn, ~p"/users/settings/workspaces/#{workspace.slug}/members")

      result =
        view
        |> form("#invite-form", %{
          "invite" => %{"email" => "newmember@example.com", "role" => "member"}
        })
        |> render_submit()

      assert result =~ "Invitation request sent"
    end

    test "sends invitation request with different roles", %{conn: conn, workspace: workspace} do
      {:ok, view, _html} = live(conn, ~p"/users/settings/workspaces/#{workspace.slug}/members")

      for {email, role} <- [
            {"admin@example.com", "admin"},
            {"viewer@example.com", "viewer"}
          ] do
        result =
          view
          |> form("#invite-form", %{
            "invite" => %{"email" => email, "role" => role}
          })
          |> render_submit()

        assert result =~ "Invitation request sent"
      end
    end
  end

  describe "change_role event" do
    setup %{conn: conn} do
      owner = user_fixture()
      workspace = workspace_fixture(owner)

      member = user_fixture()
      membership = workspace_membership_fixture(workspace, member, "member")

      %{
        conn: log_in_user(conn, owner),
        owner: owner,
        workspace: workspace,
        member: member,
        membership: membership
      }
    end

    test "owner can change member role", %{
      conn: conn,
      workspace: workspace,
      membership: membership
    } do
      {:ok, view, _html} = live(conn, ~p"/users/settings/workspaces/#{workspace.slug}/members")

      result =
        render_click(view, "change_role", %{
          "role" => "admin",
          "member-id" => to_string(membership.id)
        })

      assert result =~ "Role updated successfully."
    end

    test "admin cannot change roles", %{conn: conn, workspace: workspace, membership: membership} do
      admin = user_fixture()
      workspace_membership_fixture(workspace, admin, "admin")

      {:ok, view, _html} =
        conn
        |> log_in_user(admin)
        |> live(~p"/users/settings/workspaces/#{workspace.slug}/members")

      result =
        render_click(view, "change_role", %{
          "role" => "viewer",
          "member-id" => to_string(membership.id)
        })

      assert result =~ "Only the workspace owner can change member roles."
    end

    test "shows error for non-existent member", %{conn: conn, workspace: workspace} do
      {:ok, view, _html} = live(conn, ~p"/users/settings/workspaces/#{workspace.slug}/members")

      result =
        render_click(view, "change_role", %{
          "role" => "admin",
          "member-id" => "999999"
        })

      assert result =~ "Member not found."
    end
  end

  describe "remove_member event" do
    setup %{conn: conn} do
      owner = user_fixture()
      workspace = workspace_fixture(owner)

      member = user_fixture()
      membership = workspace_membership_fixture(workspace, member, "member")

      %{
        conn: log_in_user(conn, owner),
        owner: owner,
        workspace: workspace,
        member: member,
        membership: membership
      }
    end

    test "owner can remove a member", %{
      conn: conn,
      workspace: workspace,
      member: member,
      membership: membership
    } do
      {:ok, view, _html} = live(conn, ~p"/users/settings/workspaces/#{workspace.slug}/members")

      result = render_click(view, "remove_member", %{"id" => to_string(membership.id)})
      assert result =~ "Member removed."

      # Member should no longer be listed
      members = Workspaces.list_workspace_members(workspace.id)
      refute Enum.any?(members, fn m -> m.user_id == member.id end)
    end

    test "admin cannot remove members", %{
      conn: conn,
      workspace: workspace,
      membership: membership
    } do
      admin = user_fixture()
      workspace_membership_fixture(workspace, admin, "admin")

      {:ok, view, _html} =
        conn
        |> log_in_user(admin)
        |> live(~p"/users/settings/workspaces/#{workspace.slug}/members")

      result = render_click(view, "remove_member", %{"id" => to_string(membership.id)})
      assert result =~ "Only the workspace owner can remove members."
    end

    test "shows error for non-existent member on remove", %{conn: conn, workspace: workspace} do
      {:ok, view, _html} = live(conn, ~p"/users/settings/workspaces/#{workspace.slug}/members")

      result = render_click(view, "remove_member", %{"id" => "999999"})
      assert result =~ "Member not found."
    end

    test "cannot remove the workspace owner", %{conn: conn, workspace: workspace, owner: owner} do
      # Find the owner membership
      owner_membership = Workspaces.get_membership(workspace, owner)

      {:ok, view, _html} = live(conn, ~p"/users/settings/workspaces/#{workspace.slug}/members")

      result = render_click(view, "remove_member", %{"id" => to_string(owner_membership.id)})
      assert result =~ "Member not found."
    end
  end
end
