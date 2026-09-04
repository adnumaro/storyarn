defmodule StoryarnWeb.E2E.SceneCommentsTest do
  use PhoenixTest.Playwright.Case, async: false

  import Storyarn.AccountsFixtures
  import Storyarn.ProjectsFixtures
  import Storyarn.ScenesFixtures
  import StoryarnWeb.E2EHelpers

  alias PlaywrightEx.Frame
  alias PlaywrightEx.Page
  alias Storyarn.Projects
  alias Storyarn.Repo

  @moduletag :e2e

  test "a spatial Scene discussion preserves its draft and position across moves and deep links", %{conn: conn} do
    user = user_fixture()
    project = user |> project_fixture() |> Repo.preload(:workspace)
    scene = scene_fixture(project, %{name: "Canvas review"})
    path = "/workspaces/#{project.workspace.slug}/projects/#{project.slug}/scenes/#{scene.id}"
    feedback = "Clarify what the player discovers in this part of the map."

    session =
      conn
      |> authenticate(user)
      |> visit(path)
      |> assert_has("[data-testid='scene-canvas-comments']", timeout: 20_000)
      |> click("#scene-comments-create-mode")
      |> assert_has("#scene-comments-create-mode[aria-pressed='true']")
      |> click_at("#scene-canvas-#{scene.id}", 140, 120)
      |> assert_has("#scene-comment-draft-pin")
      |> fill_in("#scene-comment-body", "New thread", with: feedback)
      |> drag_pin("#scene-comment-draft-pin", 70, 40)
      |> assert_has("#scene-comment-body", value: feedback)
      |> click("#scene-comment-send")
      |> assert_has("#scene-comment-popover", text: feedback)

    scope = user_scope_fixture(user)
    assert {:ok, [thread]} = Projects.list_scene_comment_pins(scope, project.id, scene.id)
    assert thread.source.type == "scene_canvas"
    assert thread.source.scene_id == scene.id

    initial_position = thread.position

    session =
      session
      |> click("#scene-comment-popover-close")
      |> drag_pin("#scene-comment-pin-#{thread.id}", 80, 40)
      |> click("#scene-comment-pin-#{thread.id}")
      |> assert_has("#scene-comment-popover", text: feedback)

    assert {:ok, [moved]} = Projects.list_scene_comment_pins(scope, project.id, scene.id)
    assert moved.position.x > initial_position.x
    assert moved.position.y > initial_position.y

    session
    |> visit(path <> "?thread=#{thread.id}")
    |> assert_has("#scene-comment-popover", text: feedback, timeout: 20_000)
    |> assert_has("#scene-comment-pin-#{thread.id}[aria-expanded='true']")
  end

  defp click_at(session, selector, x, y) do
    {:ok, _} =
      Frame.click(session.frame_id,
        selector: selector,
        position: %{x: x, y: y},
        timeout: 10_000
      )

    session
  end

  defp hover_pin(session, selector) do
    {:ok, _} = Frame.hover(session.frame_id, selector: selector, timeout: 10_000)
    session
  end

  defp drag_pin(session, selector, dx, dy) do
    session
    |> hover_pin(selector)
    |> evaluate("document.querySelector(#{Jason.encode!(selector)}).getBoundingClientRect().toJSON()", fn box ->
      {:ok, _} = Page.mouse_down(session.page_id, timeout: 10_000)

      {:ok, _} =
        Page.mouse_move(session.page_id,
          x: box["x"] + box["width"] / 2 + dx,
          y: box["y"] + box["height"] / 2 + dy,
          steps: 5,
          timeout: 10_000
        )

      {:ok, _} = Page.mouse_up(session.page_id, timeout: 10_000)
    end)
  end
end
