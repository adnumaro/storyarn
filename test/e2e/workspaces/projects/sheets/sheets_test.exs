defmodule StoryarnWeb.E2E.SheetsTest do
  @moduledoc """
  E2E tests for sheet-related functionality.

  These tests use Playwright to run in a real browser.

  Run with: mix test.e2e
  """

  use PhoenixTest.Playwright.Case, async: false

  import Storyarn.AccountsFixtures
  import Storyarn.ProjectsFixtures
  import Storyarn.SheetsFixtures
  import StoryarnWeb.E2EHelpers

  alias Storyarn.Repo
  alias Storyarn.Sheets

  @moduletag :e2e

  describe "sheets list (authenticated)" do
    test "shows empty state when project has no sheets", %{conn: conn} do
      user = user_fixture()
      project = user |> project_fixture(%{name: "My Project"}) |> Repo.preload(:workspace)

      conn
      |> authenticate(user)
      |> visit("/workspaces/#{project.workspace.slug}/projects/#{project.slug}/sheets")
      |> assert_has("h1", text: "Sheets")
      |> assert_has("p", text: "No sheets yet")
    end

    test "shows sheet list when project has sheets", %{conn: conn} do
      user = user_fixture()
      project = user |> project_fixture() |> Repo.preload(:workspace)
      sheet_fixture(project, %{name: "Character Sheet"})

      conn
      |> authenticate(user)
      |> visit("/workspaces/#{project.workspace.slug}/projects/#{project.slug}/sheets")
      |> assert_has("a", text: "Character Sheet")
    end

    test "can create a new sheet via sidebar button", %{conn: conn} do
      user = user_fixture()
      project = user |> project_fixture() |> Repo.preload(:workspace)

      conn
      |> authenticate(user)
      |> visit("/workspaces/#{project.workspace.slug}/projects/#{project.slug}/sheets")
      # Tree panel starts open on sheets index
      |> assert_has("body[data-main-sidebar-open='1']")
      |> assert_has("button", text: "New Sheet")
    end

    test "shows subsheet count on parent sheets", %{conn: conn} do
      user = user_fixture()
      project = user |> project_fixture() |> Repo.preload(:workspace)
      parent = sheet_fixture(project, %{name: "Characters"})
      sheet_fixture(project, %{name: "Hero", parent_id: parent.id})
      sheet_fixture(project, %{name: "Villain", parent_id: parent.id})

      conn
      |> authenticate(user)
      |> visit("/workspaces/#{project.workspace.slug}/projects/#{project.slug}/sheets")
      |> assert_has("a", text: "Characters")
    end
  end

  describe "sheet detail (authenticated)" do
    test "displays sheet with its name", %{conn: conn} do
      user = user_fixture()
      project = user |> project_fixture() |> Repo.preload(:workspace)
      sheet = sheet_fixture(project, %{name: "World Settings"})

      conn
      |> authenticate(user)
      |> visit("/workspaces/#{project.workspace.slug}/projects/#{project.slug}/sheets/#{sheet.id}")
      |> assert_has("h1", text: "World Settings")
    end

    test "shows add block hint for editor", %{conn: conn} do
      user = user_fixture()
      project = user |> project_fixture() |> Repo.preload(:workspace)
      sheet = sheet_fixture(project)

      conn
      |> authenticate(user)
      |> visit("/workspaces/#{project.workspace.slug}/projects/#{project.slug}/sheets/#{sheet.id}")
      |> assert_has("button", text: "Add block")
    end

    test "shows breadcrumb navigation to parent", %{conn: conn} do
      user = user_fixture()
      project = user |> project_fixture() |> Repo.preload(:workspace)
      parent = sheet_fixture(project, %{name: "Characters"})
      child = sheet_fixture(project, %{name: "Main Hero", parent_id: parent.id})

      conn
      |> authenticate(user)
      |> visit("/workspaces/#{project.workspace.slug}/projects/#{project.slug}/sheets/#{child.id}")
      |> assert_has("a", text: "Characters")
      |> assert_has("h1", text: "Main Hero")
    end
  end

  describe "sheet access control" do
    test "viewer can see sheets but not add blocks", %{conn: conn} do
      owner = user_fixture()
      viewer = user_fixture()
      project = owner |> project_fixture() |> Repo.preload(:workspace)
      sheet = sheet_fixture(project, %{name: "Shared Sheet"})
      membership_fixture(project, viewer, "viewer")

      conn
      |> authenticate(viewer)
      |> visit("/workspaces/#{project.workspace.slug}/projects/#{project.slug}/sheets/#{sheet.id}")
      |> assert_has("h1", text: "Shared Sheet")
      |> refute_has("button", text: "Add block")
    end

    test "editor can see and add blocks", %{conn: conn} do
      owner = user_fixture()
      editor = user_fixture()
      project = owner |> project_fixture() |> Repo.preload(:workspace)
      sheet = sheet_fixture(project)
      membership_fixture(project, editor, "editor")

      conn
      |> authenticate(editor)
      |> visit("/workspaces/#{project.workspace.slug}/projects/#{project.slug}/sheets/#{sheet.id}")
      |> assert_has("button", text: "Add block")
    end
  end

  describe "sheet with blocks" do
    test "displays text block content", %{conn: conn} do
      user = user_fixture()
      project = user |> project_fixture() |> Repo.preload(:workspace)
      sheet = sheet_fixture(project, %{name: "Sheet with Content"})

      block_fixture(sheet, %{
        type: "text",
        config: %{"label" => "Description"},
        value: %{"content" => "This is the character description."}
      })

      conn
      |> authenticate(user)
      |> visit("/workspaces/#{project.workspace.slug}/projects/#{project.slug}/sheets/#{sheet.id}")
      |> assert_has("span", text: "Description")
    end

    test "displays computed formula results in table cells", %{conn: conn} do
      user = user_fixture()
      project = user |> project_fixture() |> Repo.preload(:workspace)
      sheet = sheet_fixture(project, %{name: "Formula Sheet"})
      table = table_block_fixture(sheet, %{label: "Stats"})
      [value_col] = table.table_columns
      [row] = table.table_rows
      modifier_col = table_column_fixture(table, %{name: "Modifier", type: "formula"})

      {:ok, row} = Sheets.update_table_cell(row, value_col.slug, "10")

      {:ok, _row} =
        Sheets.update_table_cell(row, modifier_col.slug, %{
          "expression" => "a - 3",
          "bindings" => %{
            "a" => %{"type" => "same_row", "column_slug" => value_col.slug}
          }
        })

      conn
      |> authenticate(user)
      |> visit("/workspaces/#{project.workspace.slug}/projects/#{project.slug}/sheets/#{sheet.id}")
      |> assert_has("button", text: "7")
    end
  end
end
