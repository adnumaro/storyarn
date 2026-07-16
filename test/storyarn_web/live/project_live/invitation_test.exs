defmodule StoryarnWeb.ProjectLive.InvitationTest do
  use StoryarnWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Storyarn.AccountsFixtures
  import Storyarn.ProjectsFixtures

  alias Storyarn.Accounts
  alias Storyarn.Accounts.UserToken
  alias Storyarn.Projects.ProjectInvitation
  alias Storyarn.Projects.ProjectMembership
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

    test "redirects a new invitee to password setup before accepting invitation", %{conn: conn} do
      owner = user_fixture()
      project = project_fixture(owner, %{name: "Cool Project"})
      email = "newuser@example.com"

      {token, invitation} =
        create_invitation_with_token(project, owner, email, "editor")

      invitation_path = ~p"/projects/invitations/#{token}"

      assert {:error, {:redirect, %{to: registration_path, flash: flash}}} =
               live(conn, invitation_path)

      assert flash["info"] =~ "Create a password"
      assert {_registration_token, ^invitation_path} = registration_redirect(registration_path)

      user = Accounts.get_user_by_email(email)
      assert user
      assert is_nil(user.hashed_password)
      assert Repo.get_by(UserToken, user_id: user.id, context: "invite")

      invitation = Repo.get!(ProjectInvitation, invitation.id)
      assert is_nil(invitation.accepted_at)

      refute Repo.get_by(ProjectMembership, project_id: project.id, user_id: user.id)
    end

    test "accepts invitation after a new invitee creates a password", %{conn: conn} do
      owner = user_fixture()
      project = project_fixture(owner, %{name: "Cool Project"})
      email = "newuser@example.com"
      password = valid_user_password()

      {token, invitation} =
        create_invitation_with_token(project, owner, email, "editor")

      invitation_path = ~p"/projects/invitations/#{token}"

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

      invitation = Repo.get!(ProjectInvitation, invitation.id)
      assert invitation.accepted_at

      assert Repo.get_by(ProjectMembership, project_id: project.id, user_id: user.id)
    end

    test "shows error for already accepted invitation", %{conn: conn} do
      owner = user_fixture()
      project = project_fixture(owner)
      invitee = user_fixture()

      {token, invitation} =
        create_invitation_with_token(project, owner, invitee.email, "editor")

      # Accept first — token query filters out accepted invitations
      Storyarn.Projects.accept_invitation(invitation, invitee)

      {:ok, view, _html} = live(conn, ~p"/projects/invitations/#{token}")

      vue = LiveVue.Test.get_vue(view, name: "live/project/invitation/ProjectInvitationResponse")
      assert vue.component == "live/project/invitation/ProjectInvitationResponse"
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

    test "explains when a legacy invitation can no longer fit the plan and preserves the locale", %{
      conn: conn
    } do
      owner = user_fixture()
      project = project_fixture(owner)
      invitee = user_fixture()
      existing_member = user_fixture()
      conn = init_test_session(conn, %{locale: "es"})

      {token, invitation} =
        create_invitation_with_token(project, owner, invitee.email, "editor")

      membership_fixture(project, existing_member, "viewer")

      assert {:error, {:redirect, %{to: "/es", flash: flash}}} =
               live(conn, ~p"/projects/invitations/#{token}")

      assert flash["error"] =~ "límite de miembros"
      refute Repo.get_by(ProjectMembership, project_id: project.id, user_id: invitee.id)
      assert is_nil(Repo.get!(ProjectInvitation, invitation.id).accepted_at)
    end
  end

  describe "mount with invalid token" do
    test "renders error page with a locale-aware homepage for invalid token", %{conn: conn} do
      conn = init_test_session(conn, %{locale: "es"})
      {:ok, view, _html} = live(conn, ~p"/projects/invitations/invalid-token")

      vue = LiveVue.Test.get_vue(view, name: "live/project/invitation/ProjectInvitationResponse")
      assert vue.component == "live/project/invitation/ProjectInvitationResponse"
      assert vue.props["homepage-url"] == "/es"
    end

    test "falls back to the public default homepage for an unpublished locale", %{conn: conn} do
      conn = init_test_session(conn, %{locale: "fr"})
      {:ok, view, _html} = live(conn, ~p"/projects/invitations/invalid-token")

      vue = LiveVue.Test.get_vue(view, name: "live/project/invitation/ProjectInvitationResponse")
      assert vue.props["homepage-url"] == "/"
    end

    test "renders error page for expired invitation", %{conn: conn} do
      owner = user_fixture()
      project = project_fixture(owner)

      token = :crypto.strong_rand_bytes(32)
      hashed_token = :crypto.hash(:sha256, token)
      encoded_token = Base.url_encode64(token, padding: false)

      expired_at = DateTime.utc_now() |> DateTime.add(-1, :day) |> DateTime.truncate(:second)

      Repo.insert!(%ProjectInvitation{
        project_id: project.id,
        invited_by_id: owner.id,
        email: "expired@example.com",
        token: hashed_token,
        role: "editor",
        expires_at: expired_at
      })

      {:ok, view, _html} = live(conn, ~p"/projects/invitations/#{encoded_token}")

      vue = LiveVue.Test.get_vue(view, name: "live/project/invitation/ProjectInvitationResponse")
      assert vue.component == "live/project/invitation/ProjectInvitationResponse"
    end
  end

  defp registration_redirect(path) do
    uri = URI.parse(path)
    assert String.starts_with?(uri.path, "/users/register/")

    registration_token = String.replace_prefix(uri.path, "/users/register/", "")
    return_to = uri.query |> URI.decode_query() |> Map.fetch!("return_to")

    {registration_token, return_to}
  end
end
