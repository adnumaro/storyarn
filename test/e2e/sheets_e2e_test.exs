defmodule StoryarnWeb.E2E.SheetsTest do
  @moduledoc """
  E2E tests for sheet-related functionality.

  These tests use Playwright to run in a real browser.

  Run with: mix test.e2e
  """

  use PhoenixTest.Playwright.Case, async: true

  import Storyarn.AccountsFixtures
  import Storyarn.SheetsFixtures
  import Storyarn.ProjectsFixtures

  alias PlaywrightEx.Frame
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

  describe "sheets list (authenticated)" do
    test "shows empty state when project has no sheets", %{conn: conn} do
      user = user_fixture()
      project = project_fixture(user, %{name: "My Project"}) |> Repo.preload(:workspace)

      conn
      |> authenticate(user)
      |> visit("/workspaces/#{project.workspace.slug}/projects/#{project.slug}/sheets")
      |> assert_has("h1", text: "Sheets")
      |> assert_has("p", text: "No sheets yet")
    end

    test "shows sheet list when project has sheets", %{conn: conn} do
      user = user_fixture()
      project = project_fixture(user) |> Repo.preload(:workspace)
      sheet_fixture(project, %{name: "Character Sheet"})

      conn
      |> authenticate(user)
      |> visit("/workspaces/#{project.workspace.slug}/projects/#{project.slug}/sheets")
      |> assert_has("h3", text: "Character Sheet")
    end

    test "can create a new sheet via sidebar button", %{conn: conn} do
      user = user_fixture()
      project = project_fixture(user) |> Repo.preload(:workspace)

      conn
      |> authenticate(user)
      |> visit("/workspaces/#{project.workspace.slug}/projects/#{project.slug}/sheets")
      |> click_button("New Sheet")
      # push_navigate triggers LiveView client-side navigation; wait for the
      # detail page to mount by polling for the sheet title element.
      |> unwrap(fn %{frame_id: frame_id} ->
        Frame.wait_for_selector(frame_id, selector: "#sheet-title", timeout: 10_000)
      end)
      |> assert_has("#sheet-title")
    end

    test "shows subsheet count on parent sheets", %{conn: conn} do
      user = user_fixture()
      project = project_fixture(user) |> Repo.preload(:workspace)
      parent = sheet_fixture(project, %{name: "Characters"})
      sheet_fixture(project, %{name: "Hero", parent_id: parent.id})
      sheet_fixture(project, %{name: "Villain", parent_id: parent.id})

      conn
      |> authenticate(user)
      |> visit("/workspaces/#{project.workspace.slug}/projects/#{project.slug}/sheets")
      |> assert_has("h3", text: "Characters")
      |> assert_has("p", text: "2 subsheets")
    end
  end

  describe "sheet detail (authenticated)" do
    test "displays sheet with its name", %{conn: conn} do
      user = user_fixture()
      project = project_fixture(user) |> Repo.preload(:workspace)
      sheet = sheet_fixture(project, %{name: "World Settings"})

      conn
      |> authenticate(user)
      |> visit(
        "/workspaces/#{project.workspace.slug}/projects/#{project.slug}/sheets/#{sheet.id}"
      )
      |> assert_has("h1", text: "World Settings")
    end

    test "shows add block hint for editor", %{conn: conn} do
      user = user_fixture()
      project = project_fixture(user) |> Repo.preload(:workspace)
      sheet = sheet_fixture(project)

      conn
      |> authenticate(user)
      |> visit(
        "/workspaces/#{project.workspace.slug}/projects/#{project.slug}/sheets/#{sheet.id}"
      )
      |> assert_has("span", text: "Type / to add a block")
    end

    test "shows breadcrumb navigation to parent", %{conn: conn} do
      user = user_fixture()
      project = project_fixture(user) |> Repo.preload(:workspace)
      parent = sheet_fixture(project, %{name: "Characters"})
      child = sheet_fixture(project, %{name: "Main Hero", parent_id: parent.id})

      conn
      |> authenticate(user)
      |> visit(
        "/workspaces/#{project.workspace.slug}/projects/#{project.slug}/sheets/#{child.id}"
      )
      |> assert_has("a", text: "Characters")
      |> assert_has("h1", text: "Main Hero")
    end
  end

  describe "sheet access control" do
    test "viewer can see sheets but not add blocks", %{conn: conn} do
      owner = user_fixture()
      viewer = user_fixture()
      project = project_fixture(owner) |> Repo.preload(:workspace)
      sheet = sheet_fixture(project, %{name: "Shared Sheet"})
      membership_fixture(project, viewer, "viewer")

      conn
      |> authenticate(viewer)
      |> visit(
        "/workspaces/#{project.workspace.slug}/projects/#{project.slug}/sheets/#{sheet.id}"
      )
      |> assert_has("h1", text: "Shared Sheet")
      |> refute_has("span", text: "Type / to add a block")
    end

    test "editor can see and add blocks", %{conn: conn} do
      owner = user_fixture()
      editor = user_fixture()
      project = project_fixture(owner) |> Repo.preload(:workspace)
      sheet = sheet_fixture(project)
      membership_fixture(project, editor, "editor")

      conn
      |> authenticate(editor)
      |> visit(
        "/workspaces/#{project.workspace.slug}/projects/#{project.slug}/sheets/#{sheet.id}"
      )
      |> assert_has("span", text: "Type / to add a block")
    end
  end

  describe "sheet with blocks" do
    test "displays text block content", %{conn: conn} do
      user = user_fixture()
      project = project_fixture(user) |> Repo.preload(:workspace)
      sheet = sheet_fixture(project, %{name: "Sheet with Content"})

      block_fixture(sheet, %{
        type: "text",
        config: %{"label" => "Description"},
        value: %{"content" => "This is the character description."}
      })

      conn
      |> authenticate(user)
      |> visit(
        "/workspaces/#{project.workspace.slug}/projects/#{project.slug}/sheets/#{sheet.id}"
      )
      |> assert_has("label", text: "Description")
    end
  end
end
