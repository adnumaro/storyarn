defmodule StoryarnWeb.E2E.FlowsTest do
  @moduledoc """
  E2E tests for flow-related functionality.

  These tests use Playwright to run in a real browser.

  Run with: mix test.e2e
  """

  use PhoenixTest.Playwright.Case, async: true

  import Storyarn.AccountsFixtures
  import Storyarn.FlowsFixtures
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

  describe "flows list (authenticated)" do
    test "shows empty state when project has no flows", %{conn: conn} do
      user = user_fixture()
      project = project_fixture(user, %{name: "My Project"}) |> Repo.preload(:workspace)

      conn
      |> authenticate(user)
      |> visit("/workspaces/#{project.workspace.slug}/projects/#{project.slug}/flows")
      |> assert_has("h1", text: "Flows")
      |> assert_has("p", text: "No flows yet")
    end

    test "shows flow list when project has flows", %{conn: conn} do
      user = user_fixture()
      project = project_fixture(user) |> Repo.preload(:workspace)
      flow_fixture(project, %{name: "Main Story Flow"})

      conn
      |> authenticate(user)
      |> visit("/workspaces/#{project.workspace.slug}/projects/#{project.slug}/flows")
      |> assert_has("h3", text: "Main Story Flow")
    end

    test "can open new flow modal", %{conn: conn} do
      user = user_fixture()
      project = project_fixture(user) |> Repo.preload(:workspace)

      conn
      |> authenticate(user)
      |> visit("/workspaces/#{project.workspace.slug}/projects/#{project.slug}/flows/new")
      |> assert_has("h1", text: "New Flow")
    end

    test "can create a new flow", %{conn: conn} do
      user = user_fixture()
      project = project_fixture(user) |> Repo.preload(:workspace)

      conn
      |> authenticate(user)
      |> visit("/workspaces/#{project.workspace.slug}/projects/#{project.slug}/flows/new")
      |> assert_has("h1", text: "New Flow")
      |> fill_in("Name", with: "My Dialogue Tree")
      |> fill_in("Description", with: "A branching conversation")
      |> click_button("Create Flow")
      |> assert_has("h1", text: "My Dialogue Tree")
    end

    test "shows main badge on main flow", %{conn: conn} do
      user = user_fixture()
      project = project_fixture(user) |> Repo.preload(:workspace)
      flow = flow_fixture(project, %{name: "Primary Flow"})
      Storyarn.Flows.set_main_flow(flow)

      conn
      |> authenticate(user)
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
      |> authenticate(user)
      |> visit("/workspaces/#{project.workspace.slug}/projects/#{project.slug}/flows/#{flow.id}")
      |> assert_has("h1", text: "Story Flow")
      |> assert_has("#flow-canvas")
    end

    test "shows add node button for editor", %{conn: conn} do
      user = user_fixture()
      project = project_fixture(user) |> Repo.preload(:workspace)
      flow = flow_fixture(project)

      conn
      |> authenticate(user)
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
      |> authenticate(viewer)
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
      |> authenticate(editor)
      |> visit("/workspaces/#{project.workspace.slug}/projects/#{project.slug}/flows/#{flow.id}")
      |> assert_has("button", text: "Add Node")
    end
  end
end
