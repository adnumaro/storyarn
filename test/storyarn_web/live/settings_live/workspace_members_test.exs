defmodule StoryarnWeb.SettingsLive.WorkspaceMembersTest do
  use StoryarnWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Storyarn.AccountsFixtures
  import Storyarn.WorkspacesFixtures

  alias Storyarn.Repo
  alias Storyarn.Workspaces
  alias StoryarnWeb.SettingsLive.WorkspaceMembers, as: WorkspaceMembersLive

  @outside_pg_bigint 9_223_372_036_854_775_808

  defp get_members_vue(view) do
    LiveVue.Test.get_vue(view, name: "live/workspace/settings/WorkspaceSettingsMembers")
  end

  defp get_flash_vue(view) do
    LiveVue.Test.get_vue(view, name: "live/layouts/flash/FlashGroup")
  end

  describe "mount" do
    test "renders workspace members Vue for owner", %{conn: conn} do
      user = user_fixture()
      workspace = workspace_fixture(user)

      {:ok, view, _html} =
        conn
        |> log_in_user(user)
        |> live(~p"/users/settings/workspaces/#{workspace.slug}/members")

      vue = get_members_vue(view)
      assert vue.component == "live/workspace/settings/WorkspaceSettingsMembers"
      assert vue.props["can-invite"] == true
      assert vue.props["can-manage"] == true
      assert vue.props["can-transfer-ownership"] == true
      assert vue.props["current-user-id"] == Integer.to_string(user.id)
      assert vue.props["pending-invitations"] == []
    end

    test "renders Vue for admin with can-manage=false", %{conn: conn} do
      owner = user_fixture()
      workspace = workspace_fixture(owner)

      admin = user_fixture()
      workspace_membership_fixture(workspace, admin, "admin")

      {:ok, view, _html} =
        conn
        |> log_in_user(admin)
        |> live(~p"/users/settings/workspaces/#{workspace.slug}/members")

      vue = get_members_vue(view)
      assert vue.component == "live/workspace/settings/WorkspaceSettingsMembers"
      assert vue.props["can-invite"] == true
      assert vue.props["can-manage"] == false
      assert vue.props["can-transfer-ownership"] == false
    end

    test "refreshes stale owner assigns before loading member data" do
      owner = user_fixture()
      workspace = workspace_fixture(owner)
      stale_membership = Workspaces.get_membership(workspace.id, owner.id)
      receiver = user_fixture()
      receiver_workspace = workspace_fixture(receiver)

      assert {:ok, _deleted_workspace} =
               Workspaces.delete_workspace(user_scope_fixture(receiver), receiver_workspace.id)

      _receiver_membership = workspace_membership_fixture(workspace, receiver, "member")

      assert {:ok, _receipt} =
               Workspaces.transfer_owner(user_scope_fixture(owner), workspace.id, receiver.id)

      socket = %Phoenix.LiveView.Socket{
        assigns: %{
          __changed__: %{},
          flash: %{},
          current_scope: user_scope_fixture(owner),
          workspace: workspace,
          membership: stale_membership
        }
      }

      assert {:ok, refreshed_socket} = WorkspaceMembersLive.mount(%{}, %{}, socket)
      assert refreshed_socket.assigns.workspace.owner_id == receiver.id
      assert refreshed_socket.assigns.membership.role == "admin"
      assert Enum.find(refreshed_socket.assigns.members, &(&1.user_id == receiver.id)).role == "owner"
    end

    test "passes existing members in props", %{conn: conn} do
      owner = user_fixture()
      workspace = workspace_fixture(owner)

      member = user_fixture()
      workspace_membership_fixture(workspace, member, "member")

      {:ok, view, _html} =
        conn
        |> log_in_user(owner)
        |> live(~p"/users/settings/workspaces/#{workspace.slug}/members")

      vue = get_members_vue(view)
      emails = Enum.map(vue.props["members"], & &1["email"])
      assert owner.email in emails
      assert member.email in emails

      assert Enum.find(vue.props["members"], &(&1["email"] == member.email))["user_id"] ==
               Integer.to_string(member.id)
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

      assert {:error, {:redirect, %{to: "/users/settings", flash: flash}}} =
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
  end

  describe "send_invitation event" do
    setup %{conn: conn} do
      user = user_fixture()
      workspace = workspace_fixture(user)
      %{conn: log_in_user(conn, user), user: user, workspace: workspace}
    end

    test "sends invitation directly to the workspace member", %{
      conn: conn,
      user: user,
      workspace: workspace
    } do
      {:ok, view, _html} = live(conn, ~p"/users/settings/workspaces/#{workspace.slug}/members")

      result =
        render_click(view, "send_invitation", %{
          "invite" => %{"email" => "newmember@example.com", "role" => "member"}
        })

      assert result =~ "Invitation queued for delivery"
      assert_push_event(view, "invitation_sent", %{})

      assert [invitation] = Workspaces.list_pending_invitations(workspace.id)
      assert invitation.email == "newmember@example.com"
      assert invitation.invited_by_id == user.id

      vue = get_members_vue(view)

      assert [%{"id" => invitation_id, "email" => "newmember@example.com"}] =
               vue.props["pending-invitations"]

      assert invitation_id == invitation.id
    end

    test "revokes a pending invitation and releases its seat", %{
      conn: conn,
      workspace: workspace
    } do
      {:ok, view, _html} = live(conn, ~p"/users/settings/workspaces/#{workspace.slug}/members")

      render_click(view, "send_invitation", %{
        "invite" => %{"email" => "revoke@example.com", "role" => "member"}
      })

      [invitation] = Workspaces.list_pending_invitations(workspace.id)

      result =
        render_click(view, "revoke_invitation", %{"id" => to_string(invitation.id)})

      assert result =~ "Invitation revoked"
      assert Workspaces.list_pending_invitations(workspace.id) == []
      assert get_members_vue(view).props["pending-invitations"] == []

      assert render_click(view, "send_invitation", %{
               "invite" => %{"email" => "replacement@example.com", "role" => "member"}
             }) =~ "Invitation queued for delivery"
    end

    test "does not revoke an invitation from another workspace", %{
      conn: conn,
      workspace: workspace
    } do
      other_owner = user_fixture()
      other_workspace = workspace_fixture(other_owner)

      assert {:ok, other_invitation} =
               Workspaces.create_invitation(
                 %{user: other_owner},
                 other_workspace.id,
                 "other-workspace@example.com",
                 "member"
               )

      {:ok, view, _html} = live(conn, ~p"/users/settings/workspaces/#{workspace.slug}/members")

      result =
        render_click(view, "revoke_invitation", %{"id" => to_string(other_invitation.id)})

      assert result =~ "Invitation not found"
      assert [%{id: invitation_id}] = Workspaces.list_pending_invitations(other_workspace.id)
      assert invitation_id == other_invitation.id
    end

    test "rejects oversized and structured invitation ids", %{
      conn: conn,
      workspace: workspace
    } do
      {:ok, view, _html} = live(conn, ~p"/users/settings/workspaces/#{workspace.slug}/members")

      assert render_click(view, "revoke_invitation", %{
               "id" => Integer.to_string(@outside_pg_bigint)
             }) =~ "Invitation not found."

      assert render_click(view, "revoke_invitation", %{"id" => %{"unexpected" => true}}) =~
               "Invitation not found."
    end

    test "an admin removed after mount cannot send a direct invitation", %{
      conn: conn,
      workspace: workspace
    } do
      admin = user_fixture()
      admin_membership = workspace_membership_fixture(workspace, admin, "admin")

      {:ok, view, _html} =
        conn
        |> log_in_user(admin)
        |> live(~p"/users/settings/workspaces/#{workspace.slug}/members")

      Repo.delete!(admin_membership)

      render_click(view, "send_invitation", %{
        "invite" => %{"email" => "privilege-recovery@example.com", "role" => "admin"}
      })

      flash = assert_redirect(view, ~p"/users/settings")
      assert flash["error"] =~ "permission to manage this workspace"
      assert Workspaces.list_pending_invitations(workspace.id) == []
    end

    test "an admin downgraded after mount cannot revoke a direct invitation", %{
      conn: conn,
      user: owner,
      workspace: workspace
    } do
      assert {:ok, invitation} =
               Workspaces.create_invitation(
                 %{user: owner},
                 workspace.id,
                 "still-invited@example.com",
                 "member"
               )

      admin = user_fixture()
      admin_membership = workspace_membership_fixture(workspace, admin, "admin")

      {:ok, view, _html} =
        conn
        |> log_in_user(admin)
        |> live(~p"/users/settings/workspaces/#{workspace.slug}/members")

      assert {:ok, _membership} =
               Workspaces.update_member_role(
                 user_scope_fixture(owner),
                 workspace.id,
                 admin_membership.id,
                 "member"
               )

      render_click(view, "revoke_invitation", %{"id" => to_string(invitation.id)})

      flash = assert_redirect(view, ~p"/users/settings")
      assert flash["error"] =~ "permission to manage this workspace"
      assert [%{id: invitation_id}] = Workspaces.list_pending_invitations(workspace.id)
      assert invitation_id == invitation.id
    end

    test "reports inconsistent ownership and does not create an invitation", %{
      conn: conn,
      workspace: workspace
    } do
      {:ok, view, _html} = live(conn, ~p"/users/settings/workspaces/#{workspace.slug}/members")

      conflicting_owner = user_fixture()
      workspace_membership_fixture(workspace, conflicting_owner, "owner")

      render_click(view, "send_invitation", %{
        "invite" => %{"email" => "must-not-send@example.com", "role" => "member"}
      })

      flash = assert_redirect(view, ~p"/users/settings")
      assert flash["error"] =~ "could not verify the current workspace owner"
      assert Workspaces.list_pending_invitations(workspace.id) == []
    end

    test "reports inconsistent ownership and does not revoke an invitation", %{
      conn: conn,
      user: owner,
      workspace: workspace
    } do
      assert {:ok, invitation} =
               Workspaces.create_invitation(
                 %{user: owner},
                 workspace.id,
                 "must-remain@example.com",
                 "member"
               )

      {:ok, view, _html} = live(conn, ~p"/users/settings/workspaces/#{workspace.slug}/members")

      conflicting_owner = user_fixture()
      workspace_membership_fixture(workspace, conflicting_owner, "owner")

      render_click(view, "revoke_invitation", %{"id" => to_string(invitation.id)})

      flash = assert_redirect(view, ~p"/users/settings")
      assert flash["error"] =~ "could not verify the current workspace owner"
      assert [%{id: invitation_id}] = Workspaces.list_pending_invitations(workspace.id)
      assert invitation_id == invitation.id
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

    test "explains ownership drift and preserves the role when the update fails closed", %{
      conn: conn,
      workspace: workspace,
      membership: membership
    } do
      conflicting_owner = user_fixture()
      _conflicting_membership = workspace_membership_fixture(workspace, conflicting_owner, "owner")

      {:ok, view, _html} = live(conn, ~p"/users/settings/workspaces/#{workspace.slug}/members")

      result =
        render_click(view, "change_role", %{
          "role" => "admin",
          "member-id" => to_string(membership.id)
        })

      assert result =~ "could not be updated because workspace ownership is inconsistent"
      assert Repo.reload!(membership).role == "member"
    end

    test "admin cannot change roles", %{conn: conn, workspace: workspace, membership: membership} do
      admin = user_fixture()
      workspace_membership_fixture(workspace, admin, "admin")

      {:ok, view, _html} =
        conn
        |> log_in_user(admin)
        |> live(~p"/users/settings/workspaces/#{workspace.slug}/members")

      render_click(view, "change_role", %{
        "role" => "viewer",
        "member-id" => to_string(membership.id)
      })

      assert get_flash_vue(view).props["flash"]["error"] ==
               "Only the workspace owner can change member roles."
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

    test "rejects oversized and structured member ids", %{conn: conn, workspace: workspace} do
      {:ok, view, _html} = live(conn, ~p"/users/settings/workspaces/#{workspace.slug}/members")

      assert render_click(view, "change_role", %{
               "role" => "admin",
               "member-id" => Integer.to_string(@outside_pg_bigint)
             }) =~ "Member not found."

      assert render_click(view, "change_role", %{
               "role" => "admin",
               "member-id" => []
             }) =~ "Member not found."
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

    test "explains ownership drift and preserves the member when removal fails closed", %{
      conn: conn,
      workspace: workspace,
      membership: membership
    } do
      conflicting_owner = user_fixture()
      _conflicting_membership = workspace_membership_fixture(workspace, conflicting_owner, "owner")

      {:ok, view, _html} = live(conn, ~p"/users/settings/workspaces/#{workspace.slug}/members")

      result = render_click(view, "remove_member", %{"id" => to_string(membership.id)})

      assert result =~ "could not be removed because workspace ownership is inconsistent"
      assert Repo.reload!(membership).role == "member"
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

      render_click(view, "remove_member", %{"id" => to_string(membership.id)})

      assert get_flash_vue(view).props["flash"]["error"] ==
               "Only the workspace owner can remove members."
    end

    test "shows error for non-existent member on remove", %{conn: conn, workspace: workspace} do
      {:ok, view, _html} = live(conn, ~p"/users/settings/workspaces/#{workspace.slug}/members")

      result = render_click(view, "remove_member", %{"id" => "999999"})
      assert result =~ "Member not found."
    end

    test "rejects oversized and structured removal ids", %{conn: conn, workspace: workspace} do
      {:ok, view, _html} = live(conn, ~p"/users/settings/workspaces/#{workspace.slug}/members")

      assert render_click(view, "remove_member", %{
               "id" => Integer.to_string(@outside_pg_bigint)
             }) =~ "Member not found."

      assert render_click(view, "remove_member", %{"id" => %{"unexpected" => true}}) =~
               "Member not found."
    end

    test "cannot remove the workspace owner", %{conn: conn, workspace: workspace, owner: owner} do
      owner_membership = Workspaces.get_membership(workspace, owner)

      {:ok, view, _html} = live(conn, ~p"/users/settings/workspaces/#{workspace.slug}/members")

      render_click(view, "remove_member", %{"id" => to_string(owner_membership.id)})

      assert get_flash_vue(view).props["flash"]["error"] ==
               "Cannot remove the workspace owner."
    end
  end

  describe "transfer_owner event" do
    test "transfers ownership and remounts the former owner as an admin", %{conn: conn} do
      owner = user_fixture()
      workspace = workspace_fixture(owner)
      receiver = user_fixture()
      receiver_workspace = workspace_fixture(receiver)

      assert {:ok, _deleted_workspace} =
               Workspaces.delete_workspace(user_scope_fixture(receiver), receiver_workspace.id)

      receiver_membership = workspace_membership_fixture(workspace, receiver, "member")

      {:ok, view, _html} =
        conn
        |> log_in_user(owner)
        |> live(~p"/users/settings/workspaces/#{workspace.slug}/members")

      render_click(view, "transfer_owner", %{"user-id" => to_string(receiver.id)})

      assert_redirect(view, ~p"/users/settings/workspaces/#{workspace.slug}/members")
      assert Repo.reload!(workspace).owner_id == receiver.id
      assert Workspaces.get_membership(workspace.id, owner.id).role == "admin"
      assert Repo.reload!(receiver_membership).role == "owner"
    end

    test "rejects an ownership target outside PostgreSQL bigint range", %{conn: conn} do
      owner = user_fixture()
      workspace = workspace_fixture(owner)

      {:ok, view, _html} =
        conn
        |> log_in_user(owner)
        |> live(~p"/users/settings/workspaces/#{workspace.slug}/members")

      result =
        render_click(view, "transfer_owner", %{
          "user-id" => Integer.to_string(@outside_pg_bigint)
        })

      assert result =~ "Workspace ownership could not be transferred."

      assert render_click(view, "transfer_owner", %{
               "user-id" => %{"unexpected" => true}
             }) =~ "Workspace ownership could not be transferred."

      assert render_click(view, "transfer_owner", %{}) =~
               "Workspace ownership could not be transferred."

      refute_redirected(view)
      assert Repo.reload!(workspace).owner_id == owner.id
    end

    test "a stale owner tab stays as admin and hides owner controls after a transfer elsewhere", %{
      conn: conn
    } do
      owner = user_fixture()
      workspace = workspace_fixture(owner)
      receiver = user_fixture()
      receiver_workspace = workspace_fixture(receiver)

      assert {:ok, _deleted_workspace} =
               Workspaces.delete_workspace(user_scope_fixture(receiver), receiver_workspace.id)

      receiver_membership = workspace_membership_fixture(workspace, receiver, "member")

      {:ok, view, _html} =
        conn
        |> log_in_user(owner)
        |> live(~p"/users/settings/workspaces/#{workspace.slug}/members")

      assert {:ok, _receipt} =
               Workspaces.transfer_owner(user_scope_fixture(owner), workspace.id, receiver.id)

      refute_redirected(view)

      vue = get_members_vue(view)
      assert vue.props["can-invite"] == true
      assert vue.props["can-manage"] == false
      assert vue.props["can-transfer-ownership"] == false

      owner_id = Integer.to_string(owner.id)
      receiver_id = Integer.to_string(receiver.id)

      assert Enum.find(vue.props["members"], &(&1["user_id"] == owner_id))["role"] == "admin"

      assert Enum.find(vue.props["members"], &(&1["user_id"] == receiver_id))["role"] ==
               "owner"

      assert Repo.reload!(receiver_membership).role == "owner"
    end

    test "synchronizes former and new owner controls across open members tabs", %{conn: conn} do
      owner = user_fixture()
      workspace = workspace_fixture(owner)
      receiver = user_fixture()
      receiver_workspace = workspace_fixture(receiver)

      assert {:ok, _deleted_workspace} =
               Workspaces.delete_workspace(user_scope_fixture(receiver), receiver_workspace.id)

      _receiver_membership = workspace_membership_fixture(workspace, receiver, "admin")

      {:ok, former_owner_view, _html} =
        conn
        |> log_in_user(owner)
        |> live(~p"/users/settings/workspaces/#{workspace.slug}/members")

      {:ok, new_owner_view, _html} =
        build_conn()
        |> log_in_user(receiver)
        |> live(~p"/users/settings/workspaces/#{workspace.slug}/members")

      assert get_members_vue(former_owner_view).props["can-manage"] == true
      assert get_members_vue(new_owner_view).props["can-manage"] == false

      assert {:ok, _receipt} =
               Workspaces.transfer_owner(user_scope_fixture(owner), workspace.id, receiver.id)

      former_owner_vue = get_members_vue(former_owner_view)
      new_owner_vue = get_members_vue(new_owner_view)

      assert former_owner_vue.props["can-manage"] == false
      assert former_owner_vue.props["can-transfer-ownership"] == false
      assert new_owner_vue.props["can-manage"] == true
      assert new_owner_vue.props["can-transfer-ownership"] == true
    end

    test "explains when the receiver has reached their workspace limit", %{conn: conn} do
      owner = user_fixture()
      workspace = workspace_fixture(owner)
      receiver = user_fixture()
      _receiver_workspace = workspace_fixture(receiver)
      _receiver_membership = workspace_membership_fixture(workspace, receiver, "member")

      {:ok, view, _html} =
        conn
        |> log_in_user(owner)
        |> live(~p"/users/settings/workspaces/#{workspace.slug}/members")

      result =
        render_click(view, "transfer_owner", %{"user-id" => to_string(receiver.id)})

      assert result =~ "new owner has reached their workspace limit"
      assert Repo.reload!(workspace).owner_id == owner.id
      assert Workspaces.get_membership(workspace.id, owner.id).role == "owner"
    end
  end
end
