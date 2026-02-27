defmodule StoryarnWeb.E2E.ProjectsTest do
  @moduledoc """
  E2E tests for project-related flows.

  These tests use Playwright to run in a real browser.

  Run with: mix test.e2e
  """

  use PhoenixTest.Playwright.Case, async: true

  import Storyarn.AccountsFixtures
  import Storyarn.ProjectsFixtures

  alias Storyarn.Accounts
  alias Storyarn.Repo

  @moduletag :e2e

  @session_options [
    store: :cookie,
    key: "_storyarn_key",
    signing_salt:
      Application.compile_env!(:storyarn, [StoryarnWeb.Endpoint, :session_signing_salt]),
    encryption_salt:
      Application.compile_env!(:storyarn, [StoryarnWeb.Endpoint, :session_encryption_salt])
  ]

  # Authenticate by injecting a signed session cookie directly.
  # This avoids the phx-trigger-action race condition from the magic link login flow.
  defp authenticate(conn, user) do
    token = Accounts.generate_user_session_token(user)

    add_session_cookie(conn, [value: %{user_token: token}], @session_options)
  end

  describe "unauthenticated access" do
    test "redirects to login when accessing workspaces", %{conn: conn} do
      conn
      |> visit("/workspaces")
      |> assert_path("/users/log-in")
    end

    test "redirects to login when accessing project settings", %{conn: conn} do
      conn
      |> visit("/workspaces/some-workspace/projects/some-project/settings")
      |> assert_path("/users/log-in")
    end
  end

  describe "workspace dashboard (authenticated)" do
    test "shows empty state when user has no projects in workspace", %{conn: conn} do
      user = user_fixture()
      workspace = Storyarn.Workspaces.get_default_workspace(user)

      conn
      |> authenticate(user)
      |> visit("/workspaces/#{workspace.slug}")
      |> assert_has("h1", text: workspace.name)
      |> assert_has("p", text: "No projects yet")
    end

    test "shows project list when user has projects", %{conn: conn} do
      user = user_fixture()
      project = project_fixture(user, %{name: "My Narrative Project"}) |> Repo.preload(:workspace)

      conn
      |> authenticate(user)
      |> visit("/workspaces/#{project.workspace.slug}")
      |> assert_has("h3", text: project.name)
    end

    test "can open new project modal", %{conn: conn} do
      user = user_fixture()
      workspace = Storyarn.Workspaces.get_default_workspace(user)

      conn
      |> authenticate(user)
      |> visit("/workspaces/#{workspace.slug}")
      |> click_link("New Project")
      |> assert_has("h1", text: "New Project")
    end

    test "can create a new project", %{conn: conn} do
      user = user_fixture()
      workspace = Storyarn.Workspaces.get_default_workspace(user)

      conn
      |> authenticate(user)
      |> visit("/workspaces/#{workspace.slug}/projects/new")
      |> assert_has("h1", text: "New Project")
      |> fill_in("Project Name", with: "My New Story")
      |> fill_in("Description", with: "A narrative adventure")
      |> click_button("Create Project")
      |> assert_has("h1", text: "My New Story")
    end
  end

  describe "project show sheet (authenticated)" do
    test "displays project details", %{conn: conn} do
      user = user_fixture()

      project =
        project_fixture(user, %{name: "Epic Tale", description: "An epic story"})
        |> Repo.preload(:workspace)

      conn
      |> authenticate(user)
      |> visit("/workspaces/#{project.workspace.slug}/projects/#{project.slug}")
      |> assert_has("h1", text: "Epic Tale")
    end

    test "shows settings link for owner", %{conn: conn} do
      user = user_fixture()
      project = project_fixture(user) |> Repo.preload(:workspace)

      conn
      |> authenticate(user)
      |> visit("/workspaces/#{project.workspace.slug}/projects/#{project.slug}")
      |> assert_has("a", text: "Settings")
    end
  end

  describe "project settings (authenticated)" do
    test "owner can access settings sheet", %{conn: conn} do
      user = user_fixture()
      project = project_fixture(user, %{name: "Settings Test"}) |> Repo.preload(:workspace)

      conn
      |> authenticate(user)
      |> visit("/workspaces/#{project.workspace.slug}/projects/#{project.slug}/settings")
      |> assert_has("h1", text: "Project Settings")
      |> assert_has("h3", text: "Project Details")
    end

    test "owner can update project name", %{conn: conn} do
      user = user_fixture()
      project = project_fixture(user, %{name: "Old Name"}) |> Repo.preload(:workspace)

      conn
      |> authenticate(user)
      |> visit("/workspaces/#{project.workspace.slug}/projects/#{project.slug}/settings")
      |> assert_has("h1", text: "Project Settings")
      |> fill_in("Project Name", with: "New Name")
      |> click_button("Save Changes")
      |> assert_has("p", text: "Project updated successfully")
    end

    test "shows team members section", %{conn: conn} do
      user = user_fixture()
      project = project_fixture(user) |> Repo.preload(:workspace)

      conn
      |> authenticate(user)
      |> visit("/workspaces/#{project.workspace.slug}/projects/#{project.slug}/settings")
      |> assert_has("h3", text: "Team Members")
    end

    test "shows invite form", %{conn: conn} do
      user = user_fixture()
      project = project_fixture(user) |> Repo.preload(:workspace)

      conn
      |> authenticate(user)
      |> visit("/workspaces/#{project.workspace.slug}/projects/#{project.slug}/settings")
      |> assert_has("h4", text: "Invite a new member")
      |> assert_has("input[type=email]")
    end

    test "non-owner cannot access settings", %{conn: conn} do
      owner = user_fixture()
      viewer = user_fixture()
      project = project_fixture(owner) |> Repo.preload(:workspace)
      membership_fixture(project, viewer, "viewer")

      conn
      |> authenticate(viewer)
      |> visit("/workspaces/#{project.workspace.slug}/projects/#{project.slug}/settings")
      |> assert_path("/workspaces/#{project.workspace.slug}/projects/#{project.slug}")
    end
  end

  describe "project invitation sheet" do
    test "shows invalid invitation message for bad token", %{conn: conn} do
      conn
      |> visit("/projects/invitations/invalid-token-12345")
      |> assert_has("h1", text: "Invalid Invitation")
    end

    test "shows invitation details for valid token", %{conn: conn} do
      owner = user_fixture()
      project = project_fixture(owner, %{name: "Awesome Project"})

      {token, _invitation} =
        create_invitation_with_token(project, owner, "invitee@example.com", "editor")

      conn
      |> visit("/projects/invitations/#{token}")
      |> assert_has("h3", text: "Awesome Project")
      |> assert_has("span", text: "editor")
    end

    test "prompts login for unauthenticated user viewing invitation", %{conn: conn} do
      owner = user_fixture()
      project = project_fixture(owner)

      {token, _invitation} =
        create_invitation_with_token(project, owner, "invitee@example.com")

      conn
      |> visit("/projects/invitations/#{token}")
      |> assert_has("a", text: "Log in to accept")
    end

    test "authenticated user can accept invitation", %{conn: conn} do
      owner = user_fixture()
      invitee = user_fixture(%{email: "invitee@example.com"})

      project =
        project_fixture(owner, %{name: "Collaborative Project"}) |> Repo.preload(:workspace)

      {token, _invitation} =
        create_invitation_with_token(project, owner, "invitee@example.com", "editor")

      conn
      |> authenticate(invitee)
      |> visit("/projects/invitations/#{token}")
      |> assert_has("button", text: "Accept Invitation")
      |> click_button("Accept Invitation")
      |> assert_path("/workspaces/#{project.workspace.slug}/projects/#{project.slug}")
    end

    test "shows email mismatch warning when logged in with different email", %{conn: conn} do
      owner = user_fixture()
      other_user = user_fixture(%{email: "other@example.com"})
      project = project_fixture(owner)

      {token, _invitation} =
        create_invitation_with_token(project, owner, "invitee@example.com")

      conn
      |> authenticate(other_user)
      |> visit("/projects/invitations/#{token}")
      |> assert_has("span", text: "This invitation was sent to")
    end
  end

  describe "home page" do
    test "renders landing page for unauthenticated user", %{conn: conn} do
      conn
      |> visit("/")
      |> assert_has("h1", text: "Phoenix Framework")
    end

    test "authenticated user is redirected to workspace", %{conn: conn} do
      user = user_fixture()
      workspace = Storyarn.Workspaces.get_default_workspace(user)

      conn
      |> authenticate(user)
      |> visit("/")
      |> assert_path("/workspaces/#{workspace.slug}")
    end
  end
end
