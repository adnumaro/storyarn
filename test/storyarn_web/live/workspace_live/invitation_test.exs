defmodule StoryarnWeb.WorkspaceLive.InvitationTest do
  use StoryarnWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Storyarn.AccountsFixtures
  import Storyarn.WorkspacesFixtures

  alias Storyarn.Repo
  alias Storyarn.Workspaces
  alias Storyarn.Workspaces.WorkspaceInvitation

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

    test "creates user account and accepts invitation for new email", %{conn: conn} do
      owner = user_fixture()
      workspace = workspace_fixture(owner)

      {encoded_token, _invitation} = create_invitation(workspace, owner, "newuser@example.com")

      assert {:error, {:redirect, %{to: "/users/log-in", flash: flash}}} =
               live(conn, ~p"/workspaces/invitations/#{encoded_token}")

      assert flash["info"] =~ "Invitation accepted"

      # Verify user was created
      assert Storyarn.Accounts.get_user_by_email("newuser@example.com")
    end

    test "shows error for already accepted invitation", %{conn: conn} do
      owner = user_fixture()
      workspace = workspace_fixture(owner)
      invitee = user_fixture()

      {encoded_token, invitation} = create_invitation(workspace, owner, invitee.email)

      # Accept first — token query filters out accepted invitations
      Workspaces.accept_invitation(invitation, invitee)

      {:ok, _view, html} = live(conn, ~p"/workspaces/invitations/#{encoded_token}")

      assert html =~ "Invalid Invitation"
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
  end

  describe "mount with invalid token" do
    test "renders error page for invalid token", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/workspaces/invitations/invalidtoken123")
      assert html =~ "Invalid Invitation"
    end

    test "renders error page for expired invitation", %{conn: conn} do
      owner = user_fixture()
      workspace = workspace_fixture(owner)

      token = :crypto.strong_rand_bytes(32)
      hashed_token = :crypto.hash(:sha256, token)
      encoded_token = Base.url_encode64(token, padding: false)

      expired_at = DateTime.utc_now() |> DateTime.add(-1, :day) |> DateTime.truncate(:second)

      %WorkspaceInvitation{
        workspace_id: workspace.id,
        invited_by_id: owner.id,
        email: "expired@example.com",
        token: hashed_token,
        role: "member",
        expires_at: expired_at
      }
      |> Repo.insert!()

      {:ok, _view, html} = live(conn, ~p"/workspaces/invitations/#{encoded_token}")
      assert html =~ "Invalid Invitation"
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
end
