defmodule StoryarnWeb.E2E.CommentsHubTest do
  use PhoenixTest.Playwright.Case, async: false

  import Storyarn.AccountsFixtures
  import Storyarn.ProjectsFixtures
  import Storyarn.SheetsFixtures
  import StoryarnWeb.E2EHelpers

  alias Storyarn.Projects
  alias Storyarn.Repo

  @moduletag :e2e
  @moduletag browser_context_opts: [viewport: %{width: 1440, height: 1000}]

  test "review preserves the editor and URL, restores drafts, and opens the original Sheet", %{conn: conn} do
    user = user_fixture(%{display_name: "Avery"})
    scope = user_scope_fixture(user)
    project = user |> project_fixture(%{name: "The Glass Harbor"}) |> Repo.preload(:workspace)
    sheet = sheet_fixture(project, %{name: "Mara — Character arc"})
    block = block_fixture(sheet, %{config: %{"label" => "Motivation"}, value: %{"content" => "A promise to keep"}})
    other_sheet = sheet_fixture(project, %{name: "The lighthouse keeper"})
    other_project = project_fixture(user, %{name: "Other production"})
    foreign_sheet = sheet_fixture(other_project, %{name: "A separate review"})
    thread = create_thread(scope, project, sheet, "Can we clarify why Mara returns to the harbor?")
    other = create_thread(scope, project, other_sheet, "The keeper's warning could foreshadow the final choice.")
    foreign = create_thread(scope, other_project, foreign_sheet, "This belongs to another project.")
    path = "/workspaces/#{project.workspace.slug}/projects/#{project.slug}/sheets/#{sheet.id}"

    browser =
      conn
      |> authenticate(user)
      |> visit(path)
      |> assert_has("#comments-hub-button", timeout: 20_000)
      |> click_at("#sheet-block-#{block.id} > div.relative > .group", 12, 12)
      |> assert_has("#sheet-block-#{block.id} .border-primary")
      |> evaluate("window.commentsReviewHost = document.querySelector('#project-layout')")
      |> click("#comments-hub-button")
      |> assert_has("#comments-review-dialog[role='dialog'][aria-modal='true']")
      |> assert_path(path)
      |> assert_has("#comments-hub-content", timeout: 20_000)
      |> evaluate(
        "(() => { const box = document.querySelector('#comments-review-dialog').getBoundingClientRect(); return [box.x, box.y, box.right < innerWidth, box.bottom < innerHeight]; })()",
        fn [x, y, right_margin, bottom_margin] ->
          assert x > 0 and y > 0 and right_margin and bottom_margin
        end
      )
      |> assert_has("#comments-hub-thread-#{thread.id}")
      |> refute_has("#comments-hub-thread-#{foreign.id}")
      |> refute_has("#hub-comment-body")
      |> click("#comments-hub-thread-#{thread.id}")
      |> fill_in("#hub-comment-body", "Reply", with: "Her promise to the keeper brings her back.")
      |> click("#comments-hub-thread-#{other.id}")
      |> assert_has("#hub-comment-body", value: "")
      |> click("#comments-hub-thread-#{thread.id}")
      |> assert_has("#hub-comment-body", value: "Her promise to the keeper brings her back.")
      |> press("#hub-comment-body", "Escape")
      |> refute_has("#comments-review-dialog")
      |> assert_path(path)
      |> evaluate("document.querySelector('#project-layout') === window.commentsReviewHost", fn same -> assert same end)
      |> evaluate("document.activeElement.id", fn id -> assert id == "comments-hub-button" end)
      |> assert_has("#sheet-block-#{block.id} .border-primary")
      |> click("#comments-hub-button")
      |> assert_has("#hub-comment-body", value: "Her promise to the keeper brings her back.", timeout: 20_000)
      |> click("#hub-comment-send")
      |> assert_has("#comments-hub-detail", text: "Her promise to the keeper brings her back.")

    browser
    |> click("#comments-hub-context")
    |> assert_has("#sheet-comment-popover", text: "Her promise to the keeper brings her back.", timeout: 20_000)

    assert {:ok, %{thread: %{message_count: 2}}} = Projects.get_comment_thread(scope, project.id, thread.id)
  end

  @tag browser_context_opts: [viewport: %{width: 390, height: 844}]
  test "mobile review fills the screen and returns to the list without navigating", %{conn: conn} do
    user = user_fixture()
    scope = user_scope_fixture(user)
    project = project_fixture(user, %{name: "The Glass Harbor"})
    sheet = sheet_fixture(project, %{name: "Mara"})
    thread = create_thread(scope, project, sheet, "Could this choice change her relationship with the keeper?")

    browser =
      conn
      |> authenticate(user)
      |> visit("/users/settings/preferences")
      |> assert_has("#comments-hub-button", timeout: 20_000)
      |> click("#comments-hub-button")
      |> assert_has("#comments-hub-content", timeout: 20_000)
      |> evaluate(
        "(() => { const box = document.querySelector('#comments-review-dialog').getBoundingClientRect(); return [box.x, box.y, box.width, box.height, innerWidth, innerHeight]; })()",
        fn [x, y, width, height, viewport_width, viewport_height] ->
          assert x == 0 and y == 0
          assert width == viewport_width and height == viewport_height
        end
      )
      |> click("#comments-hub-thread-#{thread.id}")
      |> assert_has("#hub-comment-body")

    browser
    |> click("#comments-hub-back")
    |> assert_has("#comments-hub-thread-#{thread.id}")
    |> refute_has("#hub-comment-body")
    |> assert_path("/users/settings/preferences")
    |> click("#comments-hub-close")
    |> refute_has("#comments-review-dialog")
  end

  defp create_thread(scope, project, sheet, body) do
    {:ok, %{thread: thread}} =
      Projects.create_sheet_canvas_comment(scope, project.id, sheet.id, %{
        body: body,
        client_request_id: Ecto.UUID.generate(),
        position: %{x: 20, y: 110}
      })

    thread
  end
end
