defmodule StoryarnWeb.E2E.PagesTest do
  @moduledoc """
  E2E tests for page-related functionality.

  These tests use Playwright to run in a real browser.

  Run with: mix test.e2e
  """

  use PhoenixTest.Playwright.Case, async: false

  import Storyarn.AccountsFixtures
  import Storyarn.PagesFixtures
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

  describe "pages list (authenticated)" do
    test "shows empty state when project has no pages", %{conn: conn} do
      user = user_fixture()
      project = project_fixture(user, %{name: "My Project"}) |> Repo.preload(:workspace)

      conn
      |> authenticate_user(user)
      |> visit("/workspaces/#{project.workspace.slug}/projects/#{project.slug}/pages")
      |> assert_has("h1", text: "Pages")
      |> assert_has("p", text: "No pages yet")
    end

    test "shows page list when project has pages", %{conn: conn} do
      user = user_fixture()
      project = project_fixture(user) |> Repo.preload(:workspace)
      page_fixture(project, %{name: "Character Sheet"})

      conn
      |> authenticate_user(user)
      |> visit("/workspaces/#{project.workspace.slug}/projects/#{project.slug}/pages")
      |> assert_has("h3", text: "Character Sheet")
    end

    test "can open new page modal", %{conn: conn} do
      user = user_fixture()
      project = project_fixture(user) |> Repo.preload(:workspace)

      conn
      |> authenticate_user(user)
      |> visit("/workspaces/#{project.workspace.slug}/projects/#{project.slug}/pages")
      |> click_button("New Page")
      |> assert_has("h1", text: "New Page")
    end

    test "can create a new page", %{conn: conn} do
      user = user_fixture()
      project = project_fixture(user) |> Repo.preload(:workspace)

      conn
      |> authenticate_user(user)
      |> visit("/workspaces/#{project.workspace.slug}/projects/#{project.slug}/pages")
      |> click_button("New Page")
      |> fill_in("Name", with: "Hero Character")
      |> click_button("Create Page")
      # After creation, it navigates to the page detail
      |> assert_has("h1", text: "Hero Character")
    end

    test "shows subpage count on parent pages", %{conn: conn} do
      user = user_fixture()
      project = project_fixture(user) |> Repo.preload(:workspace)
      parent = page_fixture(project, %{name: "Characters"})
      page_fixture(project, %{name: "Hero", parent_id: parent.id})
      page_fixture(project, %{name: "Villain", parent_id: parent.id})

      conn
      |> authenticate_user(user)
      |> visit("/workspaces/#{project.workspace.slug}/projects/#{project.slug}/pages")
      |> assert_has("h3", text: "Characters")
      |> assert_has("p", text: "2 subpages")
    end
  end

  describe "page detail (authenticated)" do
    test "displays page with its name", %{conn: conn} do
      user = user_fixture()
      project = project_fixture(user) |> Repo.preload(:workspace)
      page = page_fixture(project, %{name: "World Settings"})

      conn
      |> authenticate_user(user)
      |> visit("/workspaces/#{project.workspace.slug}/projects/#{project.slug}/pages/#{page.id}")
      |> assert_has("h1", text: "World Settings")
    end

    test "shows add block hint for editor", %{conn: conn} do
      user = user_fixture()
      project = project_fixture(user) |> Repo.preload(:workspace)
      page = page_fixture(project)

      conn
      |> authenticate_user(user)
      |> visit("/workspaces/#{project.workspace.slug}/projects/#{project.slug}/pages/#{page.id}")
      |> assert_has("span", text: "Type / to add a block")
    end

    test "shows breadcrumb navigation to parent", %{conn: conn} do
      user = user_fixture()
      project = project_fixture(user) |> Repo.preload(:workspace)
      parent = page_fixture(project, %{name: "Characters"})
      child = page_fixture(project, %{name: "Main Hero", parent_id: parent.id})

      conn
      |> authenticate_user(user)
      |> visit(
        "/workspaces/#{project.workspace.slug}/projects/#{project.slug}/pages/#{child.id}"
      )
      |> assert_has("a", text: "Characters")
      |> assert_has("h1", text: "Main Hero")
    end
  end

  describe "page access control" do
    test "viewer can see pages but not add blocks", %{conn: conn} do
      owner = user_fixture()
      viewer = user_fixture()
      project = project_fixture(owner) |> Repo.preload(:workspace)
      page = page_fixture(project, %{name: "Shared Page"})
      membership_fixture(project, viewer, "viewer")

      conn
      |> authenticate_user(viewer)
      |> visit("/workspaces/#{project.workspace.slug}/projects/#{project.slug}/pages/#{page.id}")
      |> assert_has("h1", text: "Shared Page")
      |> refute_has("span", text: "Type / to add a block")
    end

    test "editor can see and add blocks", %{conn: conn} do
      owner = user_fixture()
      editor = user_fixture()
      project = project_fixture(owner) |> Repo.preload(:workspace)
      page = page_fixture(project)
      membership_fixture(project, editor, "editor")

      conn
      |> authenticate_user(editor)
      |> visit("/workspaces/#{project.workspace.slug}/projects/#{project.slug}/pages/#{page.id}")
      |> assert_has("span", text: "Type / to add a block")
    end
  end

  describe "page with blocks" do
    test "displays text block content", %{conn: conn} do
      user = user_fixture()
      project = project_fixture(user) |> Repo.preload(:workspace)
      page = page_fixture(project, %{name: "Page with Content"})

      block_fixture(page, %{
        type: "text",
        config: %{"label" => "Description"},
        value: %{"content" => "This is the character description."}
      })

      conn
      |> authenticate_user(user)
      |> visit("/workspaces/#{project.workspace.slug}/projects/#{project.slug}/pages/#{page.id}")
      |> assert_has("label", text: "Description")
    end
  end
end
