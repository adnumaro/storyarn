defmodule StoryarnWeb.E2E.ProjectsTest do
  @moduledoc """
  E2E tests for project-related flows.

  These tests use Playwright to run in a real browser.

  Run with: mix test.e2e
  """

  use PhoenixTest.Playwright.Case, async: false

  import Storyarn.AccountsFixtures
  import Storyarn.ProjectsFixtures
  import StoryarnWeb.E2EHelpers

  alias Storyarn.Accounts
  alias Storyarn.Assets
  alias Storyarn.Projects
  alias Storyarn.Repo

  @moduletag :e2e

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
      |> assert_has("h3", text: "No projects yet")
    end

    test "shows project list when user has projects", %{conn: conn} do
      user = user_fixture()
      project = user |> project_fixture(%{name: "My Narrative Project"}) |> Repo.preload(:workspace)

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
      |> click_button("New Project")
      |> assert_has("[data-slot='dialog-content'] h2", text: "New Project")
    end

    test "can create a new project", %{conn: conn} do
      user = user_fixture()
      workspace = Storyarn.Workspaces.get_default_workspace(user)

      conn
      |> authenticate(user)
      |> visit("/workspaces/#{workspace.slug}")
      |> click_button("New Project")
      |> assert_has("[data-slot='dialog-content'] h2", text: "New Project")
      |> fill_in("Project Name", with: "My New Story")
      |> click("#project-type")
      |> click("[data-slot='select-item']", "Video game")
      |> click("#project-subtype")
      |> click("[data-slot='select-item']", "RPG", exact: true)
      |> fill_in("Description", with: "A narrative adventure")
      |> click_button("Create Project")
      |> assert_has("p", text: "Project created successfully")
    end
  end

  describe "project show (authenticated)" do
    test "displays project dashboard with stat cards", %{conn: conn} do
      user = user_fixture()

      project =
        user
        |> project_fixture(%{name: "Epic Tale", description: "An epic story"})
        |> Repo.preload(:workspace)

      conn
      |> authenticate(user)
      |> visit("/workspaces/#{project.workspace.slug}/projects/#{project.slug}")
      |> assert_has("[data-testid='project-stat-sheets']")
      |> assert_has("[data-testid='project-stat-flows']")
    end

    test "shows project settings in dropdown for owner", %{conn: conn} do
      user = user_fixture()
      project = user |> project_fixture() |> Repo.preload(:workspace)

      conn
      |> authenticate(user)
      |> visit("/workspaces/#{project.workspace.slug}/projects/#{project.slug}")
      |> click("button", project.name)
      |> assert_has("a", "Project settings")
    end
  end

  describe "project assets (authenticated)" do
    test "uploads a real image file through the browser", %{conn: conn} do
      user = user_fixture()
      project = user |> project_fixture(%{name: "Upload Project"}) |> Repo.preload(:workspace)
      filename = "e2e-upload-#{System.unique_integer([:positive])}.png"
      image_path = tiny_png_fixture(filename)

      conn
      |> authenticate(user)
      |> visit("/workspaces/#{project.workspace.slug}/projects/#{project.slug}/assets")
      |> assert_has("[data-testid='asset-upload-button']")
      |> unwrap(fn %{frame_id: frame_id} ->
        {:ok, _} =
          PlaywrightEx.Frame.set_input_files(frame_id,
            selector: "[data-testid='asset-upload-input']",
            local_paths: [image_path],
            timeout: 10_000
          )
      end)
      |> assert_has("p", text: "Asset uploaded successfully.")
      |> assert_has("p", text: filename)

      assert Enum.any?(Assets.list_assets(project.id), &(&1.filename == filename))
    end
  end

  describe "project settings (authenticated)" do
    test "owner can access settings sheet", %{conn: conn} do
      user = user_fixture()
      project = user |> project_fixture(%{name: "Settings Test"}) |> Repo.preload(:workspace)

      conn
      |> authenticate(user)
      |> visit("/workspaces/#{project.workspace.slug}/projects/#{project.slug}/settings")
      |> assert_has("h1", text: "General")
    end

    test "owner can update project name", %{conn: conn} do
      user = user_fixture()
      project = user |> project_fixture(%{name: "Old Name"}) |> Repo.preload(:workspace)

      conn
      |> authenticate(user)
      |> visit("/workspaces/#{project.workspace.slug}/projects/#{project.slug}/settings")
      |> assert_has("h1", text: "General")
      |> fill_in("Project Name", with: "New Name")
      |> click_button("Save Changes")
      |> assert_has("p", text: "Project updated successfully")
    end

    test "shows team members section", %{conn: conn} do
      user = user_fixture()
      project = user |> project_fixture() |> Repo.preload(:workspace)

      conn
      |> authenticate(user)
      |> visit("/workspaces/#{project.workspace.slug}/projects/#{project.slug}/settings/members")
      |> assert_has("h1", text: "Members")
    end

    test "shows invite form", %{conn: conn} do
      user = user_fixture()
      project = user |> project_fixture() |> Repo.preload(:workspace)

      conn
      |> authenticate(user)
      |> visit("/workspaces/#{project.workspace.slug}/projects/#{project.slug}/settings/members")
      |> assert_has("h4", text: "Request member invitation")
      |> assert_has("input[type=email]")
    end

    test "non-owner cannot access settings", %{conn: conn} do
      owner = user_fixture()
      viewer = user_fixture()
      project = owner |> project_fixture() |> Repo.preload(:workspace)
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

    test "valid token redirects new invitee to registration", %{conn: conn} do
      owner = user_fixture()
      project = project_fixture(owner, %{name: "Awesome Project"})

      {token, _invitation} =
        create_invitation_with_token(project, owner, "new-invitee@example.com", "editor")

      conn
      |> visit("/projects/invitations/#{token}")
      |> assert_path("/users/register/*")
      |> assert_has("h1", text: "Complete your account")

      invited_user = Accounts.get_user_by_email("new-invitee@example.com")
      assert invited_user
      refute Projects.get_membership(project.id, invited_user.id)
    end

    test "invited user can accept, authenticate, and open the project", %{conn: conn} do
      owner = user_fixture()
      project = owner |> project_fixture(%{name: "Invitation Flow Project"}) |> Repo.preload(:workspace)
      invited_email = "project-invite-#{System.unique_integer([:positive])}@example.com"

      {token, _invitation} =
        create_invitation_with_token(project, owner, invited_email, "editor")

      conn
      |> visit("/projects/invitations/#{token}")
      |> assert_path("/users/register/*")
      |> fill_in("#register-password", "Password", with: "password12345")
      |> fill_in("#register-password-confirmation", "Confirm Password", with: "password12345")
      |> click_button("Create an account")
      |> assert_path("/users/log-in")

      invited_user = Accounts.get_user_by_email(invited_email)
      assert invited_user

      membership = Projects.get_membership(project.id, invited_user.id)
      assert membership.role == "editor"

      conn
      |> authenticate(invited_user)
      |> visit("/workspaces/#{project.workspace.slug}/projects/#{project.slug}")
      |> assert_has("[data-testid='project-stat-sheets']")
      |> assert_has("[data-testid='project-stat-flows']")
    end

    test "already accepted invitation shows invalid invitation page", %{conn: conn} do
      owner = user_fixture()
      project = project_fixture(owner)

      {token, invitation} =
        create_invitation_with_token(project, owner, "double-accept@example.com")

      # Accept the invitation first
      {:ok, user} = Accounts.find_or_register_confirmed_user("double-accept@example.com")
      {:ok, _} = Projects.accept_invitation(invitation, user)

      # Already-accepted token is filtered out by verify_token_query, shows invalid page
      conn
      |> visit("/projects/invitations/#{token}")
      |> assert_has("h1", text: "Invalid Invitation")
    end
  end

  describe "home page" do
    test "renders landing page for unauthenticated user", %{conn: conn} do
      conn
      |> visit("/")
      |> assert_has("h1", text: "Design interactive narratives without losing control of the world.")
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

  defp tiny_png_fixture(filename) do
    path = Path.join(System.tmp_dir!(), filename)

    File.write!(
      path,
      Base.decode64!("iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==")
    )

    path
  end
end
