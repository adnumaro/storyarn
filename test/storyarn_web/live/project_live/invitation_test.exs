defmodule StoryarnWeb.ProjectLive.InvitationTest do
  use StoryarnWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Storyarn.AccountsFixtures
  import Storyarn.ProjectsFixtures

  alias Storyarn.Projects.ProjectInvitation
  alias Storyarn.Repo

  describe "mount with valid token" do
    test "auto-accepts and redirects to login for existing user", %{conn: conn} do
      owner = user_fixture()
      project = project_fixture(owner, %{name: "Cool Project"})
      invitee = user_fixture()

      {token, _invitation} =
        create_invitation_with_token(project, owner, invitee.email, "editor")

      assert {:error, {:redirect, %{to: "/users/log-in", flash: flash}}} =
               live(conn, ~p"/projects/invitations/#{token}")

      assert flash["info"] =~ "Invitation accepted"
      assert flash["info"] =~ invitee.email
    end

    test "creates user account and accepts invitation for new email", %{conn: conn} do
      owner = user_fixture()
      project = project_fixture(owner, %{name: "Cool Project"})

      {token, _invitation} =
        create_invitation_with_token(project, owner, "newuser@example.com", "editor")

      assert {:error, {:redirect, %{to: "/users/log-in", flash: flash}}} =
               live(conn, ~p"/projects/invitations/#{token}")

      assert flash["info"] =~ "Invitation accepted"

      # Verify user was created
      assert Storyarn.Accounts.get_user_by_email("newuser@example.com")
    end

    test "shows error for already accepted invitation", %{conn: conn} do
      owner = user_fixture()
      project = project_fixture(owner)
      invitee = user_fixture()

      {token, invitation} =
        create_invitation_with_token(project, owner, invitee.email, "editor")

      # Accept first — token query filters out accepted invitations
      Storyarn.Projects.accept_invitation(invitation, invitee)

      {:ok, _view, html} = live(conn, ~p"/projects/invitations/#{token}")

      assert html =~ "Invalid Invitation"
    end

    test "handles already member", %{conn: conn} do
      owner = user_fixture()
      project = project_fixture(owner)
      invitee = user_fixture()

      {token, _invitation} =
        create_invitation_with_token(project, owner, invitee.email, "editor")

      # Add as member before accepting
      membership_fixture(project, invitee, "editor")

      assert {:error, {:redirect, %{to: "/users/log-in", flash: flash}}} =
               live(conn, ~p"/projects/invitations/#{token}")

      assert flash["info"] =~ "already a member"
    end
  end

  describe "mount with invalid token" do
    test "renders error page for invalid token", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/projects/invitations/invalid-token")

      assert html =~ "Invalid Invitation"
      assert html =~ "invalid or has expired"
    end

    test "renders error page for expired invitation", %{conn: conn} do
      owner = user_fixture()
      project = project_fixture(owner)

      token = :crypto.strong_rand_bytes(32)
      hashed_token = :crypto.hash(:sha256, token)
      encoded_token = Base.url_encode64(token, padding: false)

      expired_at = DateTime.utc_now() |> DateTime.add(-1, :day) |> DateTime.truncate(:second)

      %ProjectInvitation{
        project_id: project.id,
        invited_by_id: owner.id,
        email: "expired@example.com",
        token: hashed_token,
        role: "editor",
        expires_at: expired_at
      }
      |> Repo.insert!()

      {:ok, _view, html} = live(conn, ~p"/projects/invitations/#{encoded_token}")

      assert html =~ "Invalid Invitation"
    end
  end
end
