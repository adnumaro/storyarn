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

      {encoded_token, _invitation} = create_invitation(workspace, owner, invitee.email)

      assert {:error, {:redirect, %{to: "/users/log-in", flash: flash}}} =
               live(conn, ~p"/workspaces/invitations/#{encoded_token}")

      assert flash["info"] =~ "Invitation accepted"
      assert flash["info"] =~ invitee.email
    end

    test "redirects a new invitee to password setup before accepting invitation", %{conn: conn} do
      owner = user_fixture()
      workspace = workspace_fixture(owner)
      email = "newuser@example.com"

      {encoded_token, invitation} = create_invitation(workspace, owner, email)
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

      {encoded_token, invitation} = create_invitation(workspace, owner, email)
      invitation_path = ~p"/workspaces/invitations/#{encoded_token}"

      assert {:error, {:redirect, %{to: registration_path}}} =
               live(conn, invitation_path)

      {:ok, view, _html} = live(conn, registration_path)

      assert {:error, {:live_redirect, %{to: ^invitation_path}}} =
               render_click(view, "save", %{"user" => %{"password" => password}})

      assert {:error, {:redirect, %{to: "/users/log-in", flash: flash}}} =
               live(conn, invitation_path)

      assert flash["info"] =~ "Invitation accepted"

      user = Accounts.get_user_by_email(email)
      assert Accounts.get_user_by_email_and_password(email, password)
      refute Repo.get_by(UserToken, user_id: user.id, context: "invite")

      invitation = Repo.get!(WorkspaceInvitation, invitation.id)
      assert invitation.accepted_at

      assert Repo.get_by(WorkspaceMembership, workspace_id: workspace.id, user_id: user.id)
    end

    test "shows error for already accepted invitation", %{conn: conn} do
      owner = user_fixture()
      workspace = workspace_fixture(owner)
      invitee = user_fixture()

      {encoded_token, invitation} = create_invitation(workspace, owner, invitee.email)

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

      {encoded_token, _invitation} = create_invitation(workspace, owner, invitee.email)

      # Add as member before accepting
      workspace_membership_fixture(workspace, invitee, "member")

      assert {:error, {:redirect, %{to: "/users/log-in", flash: flash}}} =
               live(conn, ~p"/workspaces/invitations/#{encoded_token}")

      assert flash["info"] =~ "already a member"
    end

    test "explains when a legacy invitation can no longer fit the plan", %{conn: conn} do
      owner = user_fixture()
      workspace = workspace_fixture(owner)
      invitee = user_fixture()
      existing_member = user_fixture()

      {encoded_token, invitation} = create_invitation(workspace, owner, invitee.email)
      workspace_membership_fixture(workspace, existing_member, "viewer")

      assert {:error, {:redirect, %{to: "/", flash: flash}}} =
               live(conn, ~p"/workspaces/invitations/#{encoded_token}")

      assert flash["error"] =~ "at its member limit"
      refute Repo.get_by(WorkspaceMembership, workspace_id: workspace.id, user_id: invitee.id)
      assert is_nil(Repo.get!(WorkspaceInvitation, invitation.id).accepted_at)
    end
  end

  describe "mount with invalid token" do
    test "renders error page for invalid token", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/workspaces/invitations/invalidtoken123")

      vue = LiveVue.Test.get_vue(view, name: "live/workspace/invitation/WorkspaceInvitationResponse")
      assert vue.component == "live/workspace/invitation/WorkspaceInvitationResponse"
    end

    test "renders error page for expired invitation", %{conn: conn} do
      owner = user_fixture()
      workspace = workspace_fixture(owner)

      token = :crypto.strong_rand_bytes(32)
      hashed_token = :crypto.hash(:sha256, token)
      encoded_token = Base.url_encode64(token, padding: false)

      expired_at = DateTime.utc_now() |> DateTime.add(-1, :day) |> DateTime.truncate(:second)

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

  defp create_invitation(workspace, owner, email, role \\ "member") do
    {encoded_token, invitation_struct} =
      WorkspaceInvitation.build_invitation(workspace, owner, email, role)

    {:ok, invitation} = Repo.insert(invitation_struct)
    {encoded_token, invitation}
  end

  defp registration_redirect(path) do
    uri = URI.parse(path)
    assert String.starts_with?(uri.path, "/users/register/")

    registration_token = String.replace_prefix(uri.path, "/users/register/", "")
    return_to = uri.query |> URI.decode_query() |> Map.fetch!("return_to")

    {registration_token, return_to}
  end
end
