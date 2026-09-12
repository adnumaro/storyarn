defmodule StoryarnWeb.E2E.CommentsHubTest do
  use PhoenixTest.Playwright.Case, async: false

  import Storyarn.AccountsFixtures
  import Storyarn.ProjectsFixtures
  import Storyarn.SheetsFixtures
  import StoryarnWeb.E2EHelpers

  alias PlaywrightEx.Frame
  alias PlaywrightEx.Page
  alias Storyarn.Projects
  alias Storyarn.Repo

  @moduletag :e2e
  @moduletag browser_context_opts: [viewport: %{width: 1440, height: 1000}]

  test "project chrome opens the shared hub and replies return to the original Sheet", %{conn: conn} do
    user = user_fixture(%{display_name: "Avery"})
    scope = user_scope_fixture(user)
    project = user |> project_fixture(%{name: "The Glass Harbor"}) |> Repo.preload(:workspace)
    sheet = sheet_fixture(project, %{name: "Mara — Character arc"})
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
      |> assert_has("#comments-hub-link[href='/comments?project_id=#{project.id}']", timeout: 20_000)
      |> click("#comments-hub-link")
      |> assert_has("#comments-hub-content", timeout: 20_000)
      |> assert_has("#comments-hub-thread-#{thread.id}")
      |> refute_has("#comments-hub-thread-#{foreign.id}")
      |> refute_has("#hub-comment-body")
      |> click("#comments-hub-thread-#{thread.id}")
      |> fill_in("#hub-comment-body", "Reply", with: "Her promise to the keeper brings her back.")
      |> click("#comments-hub-thread-#{other.id}")
      |> assert_has("#hub-comment-body", value: "")
      |> click("#comments-hub-thread-#{thread.id}")
      |> assert_has("#hub-comment-body", value: "Her promise to the keeper brings her back.")
      |> PhoenixTest.Playwright.reload_page(timeout: 20_000)
      |> assert_has("#hub-comment-body", value: "Her promise to the keeper brings her back.", timeout: 20_000)
      |> click("#hub-comment-send")
      |> assert_has("#comments-hub-detail", text: "Her promise to the keeper brings her back.")

    capture_review_images(browser)

    browser
    |> click("#comments-hub-context")
    |> assert_has("#sheet-comment-popover", text: "Her promise to the keeper brings her back.", timeout: 20_000)

    assert {:ok, %{thread: %{message_count: 2}}} = Projects.get_comment_thread(scope, project.id, thread.id)
  end

  @tag browser_context_opts: [viewport: %{width: 390, height: 844}]
  test "on a narrow screen the conversation opens with a route back to the list", %{conn: conn} do
    user = user_fixture()
    scope = user_scope_fixture(user)
    project = project_fixture(user, %{name: "The Glass Harbor"})
    sheet = sheet_fixture(project, %{name: "Mara"})
    thread = create_thread(scope, project, sheet, "Could this choice change her relationship with the keeper?")

    browser =
      conn
      |> authenticate(user)
      |> visit("/comments")
      |> assert_has("#comments-hub-content", timeout: 20_000)
      |> click("#comments-hub-thread-#{thread.id}")
      |> assert_has("#hub-comment-body")

    capture_review_images(browser, "mobile")

    browser
    |> click("#comments-hub-back")
    |> assert_has("#comments-hub-thread-#{thread.id}")
    |> refute_has("#hub-comment-body")
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

  defp capture_review_images(browser, surface \\ "desktop") do
    if System.get_env("STORYARN_HUB_REVIEW_IMAGES") == "1" do
      for theme <- ["light", "dark"] do
        {:ok, _} =
          Frame.evaluate(browser.frame_id,
            expression: """
            (async () => {
              document.documentElement.classList.toggle('dark', #{theme == "dark"});
              await new Promise(requestAnimationFrame);
              await new Promise(requestAnimationFrame);
              await Promise.allSettled(document.getAnimations()
                .filter(animation => animation.effect?.getTiming().iterations !== Infinity)
                .map(animation => animation.finished));
            })()
            """,
            timeout: 10_000
          )

        {:ok, encoded} = Page.screenshot(browser.page_id, full_page: false, timeout: 10_000)
        File.write!("/private/tmp/comments-hub-#{surface}-#{theme}.png", Base.decode64!(encoded))
      end
    end
  end
end
