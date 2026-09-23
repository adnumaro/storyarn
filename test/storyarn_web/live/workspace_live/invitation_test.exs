defmodule StoryarnWeb.WorkspaceLive.InvitationTest do
  use StoryarnWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Storyarn.AccountsFixtures
  import Storyarn.WorkspacesFixtures

  alias Storyarn.Accounts
  alias Storyarn.Accounts.UserToken
  alias Storyarn.Repo
  alias Storyarn.Workspaces
  alias Storyarn.Workspaces.WorkspaceInvitation
  alias Storyarn.Workspaces.WorkspaceMembership

  describe "mount with valid token" do
    test "auto-accepts and redirects to login for existing user", %{conn: conn} do
      owner = user_fixture()
      workspace = workspace_fixture(owner)
      invitee = user_fixture()

      {encoded_token, _invitation} =
        workspace_invitation_fixture(workspace, owner, invitee.email)

      assert {:error, {:redirect, %{to: "/users/log-in", flash: flash}}} =
               live(conn, ~p"/workspaces/invitations/#{encoded_token}")

      assert flash["info"] =~ "Invitation accepted"
      assert flash["info"] =~ invitee.email
    end

    test "redirects a new invitee to password setup before accepting invitation", %{conn: conn} do
      owner = user_fixture()
      workspace = workspace_fixture(owner)
      email = "newuser@example.com"

      {encoded_token, invitation} = workspace_invitation_fixture(workspace, owner, email)
      invitation_path = ~p"/workspaces/invitations/#{encoded_token}"

      assert {:error, {:redirect, %{to: registration_path, flash: flash}}} =
               live(conn, ~p"/workspaces/invitations/#{encoded_token}")

      assert flash["info"] =~ "Create a password"
      assert {_registration_token, ^invitation_path} = registration_redirect(registration_path)

      user = Accounts.get_user_by_email(email)
      assert user
      assert is_nil(user.hashed_password)
      assert Repo.get_by(UserToken, user_id: user.id, context: "invite")

      invitation = Repo.get!(WorkspaceInvitation, invitation.id)
      assert is_nil(invitation.accepted_at)

      refute Repo.get_by(WorkspaceMembership, workspace_id: workspace.id, user_id: user.id)
    end

    test "accepts invitation after a new invitee creates a password", %{conn: conn} do
      owner = user_fixture()
      workspace = workspace_fixture(owner)
      email = "newuser@example.com"
      password = valid_user_password()

      {encoded_token, invitation} = workspace_invitation_fixture(workspace, owner, email)
      invitation_path = ~p"/workspaces/invitations/#{encoded_token}"

      assert {:error, {:redirect, %{to: registration_path}}} =
               live(conn, invitation_path)

      {_registration, conn} =
        register_through_session_handoff(conn, registration_path, %{"password" => password})

      assert get_session(conn, :user_token)
      assert redirected_to(conn) == invitation_path

      workspace_path = ~p"/workspaces/#{workspace.slug}"

      assert {:error, {:redirect, %{to: ^workspace_path, flash: flash}}} =
               live(recycle(conn), invitation_path)

      assert flash["info"] == "Invitation accepted! Welcome to #{workspace.name}."

      user = Accounts.get_user_by_email(email)
      assert Accounts.get_user_by_email_and_password(email, password)
      refute Repo.get_by(UserToken, user_id: user.id, context: "invite")

      invitation = Repo.get!(WorkspaceInvitation, invitation.id)
      assert invitation.accepted_at

      assert Repo.get_by(WorkspaceMembership, workspace_id: workspace.id, user_id: user.id)
    end

    test "sends an invitee who is signed in as someone else to log in", %{conn: conn} do
      owner = user_fixture()
      workspace = workspace_fixture(owner)
      invitee = user_fixture()
      other_user = user_fixture()

      {encoded_token, _invitation} =
        workspace_invitation_fixture(workspace, owner, invitee.email)

      assert {:error, {:redirect, %{to: "/users/log-in", flash: flash}}} =
               conn
               |> log_in_user(other_user)
               |> live(~p"/workspaces/invitations/#{encoded_token}")

      assert flash["info"] =~ invitee.email
    end

    test "shows error for already accepted invitation", %{conn: conn} do
      owner = user_fixture()
      workspace = workspace_fixture(owner)
      invitee = user_fixture()

      {encoded_token, invitation} =
        workspace_invitation_fixture(workspace, owner, invitee.email)

      # Accept first — token query filters out accepted invitations
      Workspaces.accept_invitation(invitation, invitee)

      {:ok, view, _html} = live(conn, ~p"/workspaces/invitations/#{encoded_token}")

      vue = LiveVue.Test.get_vue(view, name: "live/workspace/invitation/WorkspaceInvitationResponse")
      assert vue.component == "live/workspace/invitation/WorkspaceInvitationResponse"
    end

    test "handles already member", %{conn: conn} do
      owner = user_fixture()
      workspace = workspace_fixture(owner)
      invitee = user_fixture()

      {encoded_token, _invitation} =
        workspace_invitation_fixture(workspace, owner, invitee.email)

      # Add as member before accepting
      workspace_membership_fixture(workspace, invitee, "member")

      assert {:error, {:redirect, %{to: "/users/log-in", flash: flash}}} =
               live(conn, ~p"/workspaces/invitations/#{encoded_token}")

      assert flash["info"] =~ "already a member"
    end

    test "explains when a legacy invitation can no longer fit the plan and preserves the locale", %{
      conn: conn
    } do
      owner = user_fixture()
      workspace = workspace_fixture(owner)
      invitee = user_fixture()
      existing_member = user_fixture()
      conn = init_test_session(conn, %{locale: "es"})

      {encoded_token, invitation} =
        workspace_invitation_fixture(workspace, owner, invitee.email)

      workspace_membership_fixture(workspace, existing_member, "viewer")

      assert {:error, {:redirect, %{to: "/es", flash: flash}}} =
               live(conn, ~p"/workspaces/invitations/#{encoded_token}")

      assert flash["error"] =~ "límite de miembros"
      refute Repo.get_by(WorkspaceMembership, workspace_id: workspace.id, user_id: invitee.id)
      assert is_nil(Repo.get!(WorkspaceInvitation, invitation.id).accepted_at)
    end
  end

  describe "mount with invalid token" do
    test "renders error page with a locale-aware homepage for invalid token", %{conn: conn} do
      conn = init_test_session(conn, %{locale: "es"})
      {:ok, view, _html} = live(conn, ~p"/workspaces/invitations/invalidtoken123")

      vue = LiveVue.Test.get_vue(view, name: "live/workspace/invitation/WorkspaceInvitationResponse")
      assert vue.component == "live/workspace/invitation/WorkspaceInvitationResponse"
      assert vue.props["homepage-url"] == "/es"
    end

    test "falls back to the public default homepage for an unpublished locale", %{conn: conn} do
      conn = init_test_session(conn, %{locale: "fr"})
      {:ok, view, _html} = live(conn, ~p"/workspaces/invitations/invalidtoken123")

      vue = LiveVue.Test.get_vue(view, name: "live/workspace/invitation/WorkspaceInvitationResponse")
      assert vue.props["homepage-url"] == "/"
    end

    test "renders error page for expired invitation", %{conn: conn} do
      owner = user_fixture()
      workspace = workspace_fixture(owner)

      token = :crypto.strong_rand_bytes(32)
      hashed_token = :crypto.hash(:sha256, token)
      encoded_token = Base.url_encode64(token, padding: false)

      expired_at = DateTime.utc_now() |> DateTime.shift(day: -1) |> DateTime.truncate(:second)

      Repo.insert!(%WorkspaceInvitation{
        workspace_id: workspace.id,
        invited_by_id: owner.id,
        email: "expired@example.com",
        token: hashed_token,
        role: "member",
        expires_at: expired_at
      })

      {:ok, view, _html} = live(conn, ~p"/workspaces/invitations/#{encoded_token}")

      vue = LiveVue.Test.get_vue(view, name: "live/workspace/invitation/WorkspaceInvitationResponse")
      assert vue.component == "live/workspace/invitation/WorkspaceInvitationResponse"
    end
  end

  # =============================================================================
  # Helpers
  # =============================================================================

  defp registration_redirect(path) do
    uri = URI.parse(path)
    assert String.starts_with?(uri.path, "/users/register/")

    registration_token = String.replace_prefix(uri.path, "/users/register/", "")
    return_to = uri.query |> URI.decode_query() |> Map.fetch!("return_to")

    {registration_token, return_to}
  end
end
