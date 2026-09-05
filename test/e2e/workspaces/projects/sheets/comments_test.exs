defmodule StoryarnWeb.E2E.SheetCommentsTest do
  use PhoenixTest.Playwright.Case, async: false

  import Storyarn.AccountsFixtures
  import Storyarn.ProjectsFixtures
  import Storyarn.SheetsFixtures
  import StoryarnWeb.E2EHelpers

  alias Storyarn.Projects
  alias Storyarn.Repo

  @moduletag :e2e

  test "a block discussion can start from the context menu and keeps its anchor across moves and deep links", %{
    conn: conn
  } do
    user = user_fixture()
    project = user |> project_fixture() |> Repo.preload(:workspace)
    sheet = sheet_fixture(project, %{name: "Character review"})
    block = block_fixture(sheet, %{config: %{"label" => "Motivation", "placeholder" => ""}})
    path = "/workspaces/#{project.workspace.slug}/projects/#{project.slug}/sheets/#{sheet.id}"
    feedback = "Explain why this motivation changes after the second act."
    block_selector = "[data-sheet-block-id='#{block.id}']"

    session =
      conn
      |> authenticate(user)
      |> visit(path)
      |> assert_has("h1", text: "Character review", timeout: 20_000)
      |> assert_has(block_selector, timeout: 20_000)
      |> assert_has("[data-testid='sheet-block-comments']", timeout: 20_000)
      |> right_click_at(block_selector, 8, 8)
      |> assert_has("#sheet-comment-context-menu")
      |> click("#sheet-comment-context-add")
      |> assert_has("#sheet-comment-draft-pin")
      |> fill_in("#sheet-comment-body", "New thread", with: feedback)
      |> drag_pin("#sheet-comment-draft-pin", 35, 20)
      |> assert_has("#sheet-comment-body", value: feedback)
      |> click("#sheet-comment-send")
      |> assert_has("#sheet-comment-popover", text: feedback)

    scope = user_scope_fixture(user)
    assert {:ok, [thread]} = Projects.list_sheet_comment_pins(scope, project.id, sheet.id)
    assert thread.source.type == "sheet_block"
    assert thread.source.sheet_id == sheet.id
    assert thread.source.id == block.id
    assert thread.position.x >= 0 and thread.position.x <= 100
    assert thread.position.y >= 0 and thread.position.y <= 100

    initial_position = thread.position

    session =
      session
      |> click("#sheet-comment-popover-close")
      |> drag_pin("#sheet-comment-pin-#{thread.id}", 45, 18)
      |> hover_pin("#sheet-comment-pin-#{thread.id}")
      |> assert_has("#sheet-comment-preview", text: feedback)
      |> click("#sheet-comment-pin-#{thread.id}")
      |> assert_has("#sheet-comment-popover", text: feedback)

    assert {:ok, [moved]} = Projects.list_sheet_comment_pins(scope, project.id, sheet.id)
    assert moved.position.x > initial_position.x
    assert moved.position.y > initial_position.y

    session
    |> visit(path <> "?thread=#{thread.id}")
    |> assert_has("#sheet-comment-popover", text: feedback, timeout: 20_000)
    |> assert_has("#sheet-comment-pin-#{thread.id}[aria-expanded='true']")
  end
end
