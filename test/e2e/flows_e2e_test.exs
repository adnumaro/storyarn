defmodule StoryarnWeb.E2E.FlowsTest do
  @moduledoc """
  E2E tests for flow-related functionality.

  These tests use Playwright to run in a real browser.

  Run with: mix test.e2e
  """

  use PhoenixTest.Playwright.Case, async: false

  import Storyarn.AccountsFixtures
  import Storyarn.FlowsFixtures
  import Storyarn.ProjectsFixtures

  alias Storyarn.Repo
  alias Storyarn.Workspaces

  @moduletag :e2e

  # Helper to authenticate via magic link
  # After login, we verify by checking we can access the workspaces page
  defp authenticate_user(conn, user) do
    {token, _db_token} = generate_user_magic_link_token(user)
    workspace = Workspaces.get_default_workspace(user)

    conn
    |> visit("/users/log-in/#{token}")
    |> click_button("Keep me logged in on this device")
    # Verify login by checking we're redirected to workspace
    |> assert_path("/workspaces/#{workspace.slug}")
  end

  describe "flows list (authenticated)" do
    test "shows empty state when project has no flows", %{conn: conn} do
      user = user_fixture()
      project = project_fixture(user, %{name: "My Project"}) |> Repo.preload(:workspace)

      conn
      |> authenticate_user(user)
      |> visit("/workspaces/#{project.workspace.slug}/projects/#{project.slug}/flows")
      |> assert_has("h1", text: "Flows")
      |> assert_has("p", text: "No flows yet")
    end

    test "shows flow list when project has flows", %{conn: conn} do
      user = user_fixture()
      project = project_fixture(user) |> Repo.preload(:workspace)
      flow_fixture(project, %{name: "Main Story Flow"})

      conn
      |> authenticate_user(user)
      |> visit("/workspaces/#{project.workspace.slug}/projects/#{project.slug}/flows")
      |> assert_has("h3", text: "Main Story Flow")
    end

    test "can open new flow modal", %{conn: conn} do
      user = user_fixture()
      project = project_fixture(user) |> Repo.preload(:workspace)

      conn
      |> authenticate_user(user)
      |> visit("/workspaces/#{project.workspace.slug}/projects/#{project.slug}/flows")
      |> click_link("New Flow")
      |> assert_has("h1", text: "New Flow")
    end

    test "can create a new flow", %{conn: conn} do
      user = user_fixture()
      project = project_fixture(user) |> Repo.preload(:workspace)

      conn
      |> authenticate_user(user)
      |> visit("/workspaces/#{project.workspace.slug}/projects/#{project.slug}/flows/new")
      |> fill_in("Name", with: "My Dialogue Tree")
      |> fill_in("Description", with: "A branching conversation")
      |> click_button("Create Flow")
      # After creation, it navigates to the flow editor
      |> assert_has("h1", text: "My Dialogue Tree")
    end

    test "shows main badge on main flow", %{conn: conn} do
      user = user_fixture()
      project = project_fixture(user) |> Repo.preload(:workspace)
      flow = flow_fixture(project, %{name: "Primary Flow"})
      Storyarn.Flows.set_main_flow(flow)

      conn
      |> authenticate_user(user)
      |> visit("/workspaces/#{project.workspace.slug}/projects/#{project.slug}/flows")
      |> assert_has("span", text: "Main")
    end
  end

  describe "flow editor (authenticated)" do
    test "displays flow editor with canvas", %{conn: conn} do
      user = user_fixture()
      project = project_fixture(user) |> Repo.preload(:workspace)
      flow = flow_fixture(project, %{name: "Story Flow"})

      conn
      |> authenticate_user(user)
      |> visit("/workspaces/#{project.workspace.slug}/projects/#{project.slug}/flows/#{flow.id}")
      |> assert_has("h1", text: "Story Flow")
      |> assert_has("#flow-canvas")
    end

    test "shows back link to flows list", %{conn: conn} do
      user = user_fixture()
      project = project_fixture(user) |> Repo.preload(:workspace)
      flow = flow_fixture(project)

      conn
      |> authenticate_user(user)
      |> visit("/workspaces/#{project.workspace.slug}/projects/#{project.slug}/flows/#{flow.id}")
      |> assert_has("a", text: "Flows")
    end

    test "shows add node button for editor", %{conn: conn} do
      user = user_fixture()
      project = project_fixture(user) |> Repo.preload(:workspace)
      flow = flow_fixture(project)

      conn
      |> authenticate_user(user)
      |> visit("/workspaces/#{project.workspace.slug}/projects/#{project.slug}/flows/#{flow.id}")
      |> assert_has("button", text: "Add Node")
    end
  end

  describe "flow access control" do
    test "viewer can see flows but not add node button", %{conn: conn} do
      owner = user_fixture()
      viewer = user_fixture()
      project = project_fixture(owner) |> Repo.preload(:workspace)
      flow = flow_fixture(project, %{name: "Shared Flow"})
      membership_fixture(project, viewer, "viewer")

      conn
      |> authenticate_user(viewer)
      |> visit("/workspaces/#{project.workspace.slug}/projects/#{project.slug}/flows/#{flow.id}")
      |> assert_has("h1", text: "Shared Flow")
      |> refute_has("button", text: "Add Node")
    end

    test "editor can see and add nodes", %{conn: conn} do
      owner = user_fixture()
      editor = user_fixture()
      project = project_fixture(owner) |> Repo.preload(:workspace)
      flow = flow_fixture(project)
      membership_fixture(project, editor, "editor")

      conn
      |> authenticate_user(editor)
      |> visit("/workspaces/#{project.workspace.slug}/projects/#{project.slug}/flows/#{flow.id}")
      |> assert_has("button", text: "Add Node")
    end
  end
end
