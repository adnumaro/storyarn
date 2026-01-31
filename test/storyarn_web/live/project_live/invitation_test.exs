defmodule StoryarnWeb.ProjectLive.InvitationTest do
  use StoryarnWeb.ConnCase

  import Phoenix.LiveViewTest
  import Storyarn.AccountsFixtures
  import Storyarn.ProjectsFixtures

  alias Storyarn.Repo

  describe "Invitation" do
    test "renders invitation page for unauthenticated user", %{conn: conn} do
      owner = user_fixture()
      project = project_fixture(owner, %{name: "Cool Project"})

      {token, _invitation} =
        create_invitation_with_token(project, owner, "invitee@example.com", "editor")

      {:ok, _view, html} = live(conn, ~p"/projects/invitations/#{token}")

      assert html =~ "invited"
      assert html =~ "Cool Project"
      assert html =~ "Log in to accept"
    end

    test "renders invitation for authenticated user with matching email", %{conn: conn} do
      owner = user_fixture()
      project = project_fixture(owner, %{name: "Cool Project"})
      invitee = user_fixture()

      {token, _invitation} = create_invitation_with_token(project, owner, invitee.email, "editor")

      conn = log_in_user(conn, invitee)
      {:ok, _view, html} = live(conn, ~p"/projects/invitations/#{token}")

      assert html =~ "Cool Project"
      assert html =~ "Accept Invitation"
    end

    test "shows warning for authenticated user with non-matching email", %{conn: conn} do
      owner = user_fixture()
      project = project_fixture(owner, %{name: "Cool Project"})
      wrong_user = user_fixture()

      {token, _invitation} =
        create_invitation_with_token(project, owner, "other@example.com", "editor")

      conn = log_in_user(conn, wrong_user)
      {:ok, _view, html} = live(conn, ~p"/projects/invitations/#{token}")

      assert html =~ "other@example.com"
      assert html =~ wrong_user.email
      refute html =~ "Accept Invitation"
    end

    test "accepts invitation", %{conn: conn} do
      owner = user_fixture()
      project = project_fixture(owner, %{name: "Cool Project"}) |> Repo.preload(:workspace)
      invitee = user_fixture()

      {token, _invitation} = create_invitation_with_token(project, owner, invitee.email, "editor")

      conn = log_in_user(conn, invitee)
      {:ok, view, _html} = live(conn, ~p"/projects/invitations/#{token}")

      view
      |> element("button", "Accept Invitation")
      |> render_click()

      {path, flash} = assert_redirect(view)
      assert path == "/workspaces/#{project.workspace.slug}/projects/#{project.slug}"
      assert flash["info"] =~ "Welcome"
    end

    test "shows error for invalid token", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/projects/invitations/invalid-token")

      assert html =~ "Invalid Invitation"
      assert html =~ "invalid or has expired"
    end

    test "shows error for expired invitation", %{conn: conn} do
      owner = user_fixture()
      project = project_fixture(owner)

      # Create an expired invitation by manipulating the database directly
      token = :crypto.strong_rand_bytes(32)
      hashed_token = :crypto.hash(:sha256, token)
      encoded_token = Base.url_encode64(token, padding: false)

      expired_at = DateTime.utc_now() |> DateTime.add(-1, :day) |> DateTime.truncate(:second)

      %Storyarn.Projects.ProjectInvitation{
        project_id: project.id,
        invited_by_id: owner.id,
        email: "expired@example.com",
        token: hashed_token,
        role: "editor",
        expires_at: expired_at
      }
      |> Storyarn.Repo.insert!()

      {:ok, _view, html} = live(conn, ~p"/projects/invitations/#{encoded_token}")

      assert html =~ "Invalid Invitation"
    end
  end
end
