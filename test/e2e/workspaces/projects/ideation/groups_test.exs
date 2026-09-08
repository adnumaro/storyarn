defmodule StoryarnWeb.E2E.IdeationGroupsTest do
  use PhoenixTest.Playwright.Case, async: false

  import PhoenixTest.Playwright, only: [press: 3, type: 3, evaluate: 3, drag: 3]
  import Storyarn.IdeationFixtures
  import StoryarnWeb.E2EHelpers

  alias PhoenixTest.Playwright.Config
  alias Storyarn.Ideation
  alias Storyarn.Repo

  @moduletag :e2e

  setup do
    # LiveVue.Test reads full props in server tests; the real browser must also
    # exercise production's partial updates. E2E cases run synchronously.
    previous = Application.fetch_env!(:live_vue, :enable_props_diff)
    Application.put_env(:live_vue, :enable_props_diff, true)
    on_exit(fn -> Application.put_env(:live_vue, :enable_props_diff, previous) end)
    :ok
  end

  test "organize and synthesize shared notes directly on the canvas, with collaboration and undo",
       %{conn: conn} = context do
    ctx = ideation_fixture()
    first = note(ctx, ctx.author, "She protects the city because she once abandoned her sister.", 0, 0, "yellow")
    second = note(ctx, ctx.peer, "Her rival knows the truth about the evacuation.", 340, 0, "blue")

    browser = conn |> authenticate(ctx.author.user) |> visit(path(ctx)) |> assert_has("#brainstorming-canvas")

    browser =
      evaluate(browser, "document.querySelector('#brainstorming-board').dataset.useDiff", fn mode ->
        assert mode == "true"
      end)

    viewer_config = context |> Map.take(Config.setup_keys()) |> Config.validate!()

    viewer =
      viewer_config
      |> PhoenixTest.Playwright.Case.new_session(context)
      |> authenticate(ctx.viewer.user)
      |> visit(path(ctx))

    browser = browser |> assert_has("[data-note-id]", count: 2) |> press("#brainstorming-canvas", "ControlOrMeta+a")

    browser =
      browser
      |> assert_has(".canvas-note[aria-selected=true]", count: 2)
      |> click("#create-idea-group")
      |> assert_has("[data-group-id]", count: 1)

    assert {:ok, [group]} = Ideation.list_groups(ctx.author, ctx.project.id, ctx.session.id)
    selector = "#canvas-group-#{group.id}"
    title = "#group-title-#{group.id}"
    synthesis = "#group-synthesis-#{group.id}"

    browser =
      browser
      |> assert_has("#{selector}[aria-busy=false]")
      |> click("#group-title-edit-#{group.id}")
      |> press(title, "ControlOrMeta+a")
      |> type(title, "Guilt and loyalty")
      |> press(title, "Enter")
      |> assert_has(selector, text: "Guilt and loyalty")
      |> assert_has("#{selector}[aria-busy=false]")
      |> click("#group-synthesis-add-#{group.id}")
      |> type(synthesis, "Her loyalty is an attempt to repair the harm she caused.")
      |> click("#group-synthesis-save-#{group.id}")
      |> assert_has("#{selector}[aria-busy=false]", text: "Her loyalty is an attempt to repair the harm she caused.")
      |> refute_has("[role=dialog]")

    viewer =
      viewer
      |> assert_has(selector, text: "Guilt and loyalty")
      |> assert_has(selector, text: "Her loyalty is an attempt to repair the harm she caused.")

    viewer |> refute_has("#group-title-edit-#{group.id}") |> refute_has("#group-separate-#{group.id}")

    browser = press(browser, "#brainstorming-canvas", "1")

    # Group movement preserves the authored source text and is one undo step.
    browser =
      browser
      |> drag("#{selector} > header",
        to: "#{selector} > header",
        playwright: [source_position: %{x: 20, y: 25}, target_position: %{x: 100, y: 25}]
      )
      |> assert_has("#{selector}[aria-busy=false]")

    assert {:ok, moved} = Ideation.get_idea(ctx.author, ctx.project.id, ctx.session.id, first.id)
    assert moved.canvas["x"] > first.canvas["x"]
    assert moved.body == first.body
    assert {:ok, moved_peer} = Ideation.get_idea(ctx.author, ctx.project.id, ctx.session.id, second.id)
    assert_in_delta moved_peer.canvas["x"] - second.canvas["x"], moved.canvas["x"] - first.canvas["x"], 0.0001

    browser = browser |> press(selector, "ControlOrMeta+z") |> assert_has("#{selector}[aria-busy=false]")
    assert {:ok, undone} = Ideation.get_idea(ctx.author, ctx.project.id, ctx.session.id, first.id)
    assert undone.canvas["x"] == first.canvas["x"]

    browser = browser |> press(selector, "ControlOrMeta+Shift+z") |> assert_has("#{selector}[aria-busy=false]")
    assert {:ok, redone} = Ideation.get_idea(ctx.author, ctx.project.id, ctx.session.id, first.id)
    assert redone.canvas["x"] == moved.canvas["x"]

    browser = browser |> click("#group-separate-#{group.id}") |> assert_has("#{selector}[data-total-members='0']")

    browser
    |> assert_has(selector, text: "Her loyalty is an attempt to repair the harm she caused.")
    |> assert_has("[data-note-id]", count: 2)

    assert {:ok, [separated]} = Ideation.list_groups(ctx.viewer, ctx.project.id, ctx.session.id)
    assert separated.idea_ids == []

    browser =
      browser
      |> press(selector, "ControlOrMeta+z")
      |> assert_has("#{selector}[data-total-members='2'][aria-busy=false]")
      |> click("#group-delete-#{group.id}")
      |> refute_has(selector)
      |> assert_has("[data-note-id]", count: 2)

    viewer |> refute_has(selector) |> assert_has("[data-note-id]", count: 2)

    browser
    |> press("#brainstorming-canvas", "ControlOrMeta+z")
    |> assert_has("#{selector}[data-total-members='2']")
    |> visit(path(ctx))
    |> assert_has(selector, text: "Guilt and loyalty")
    |> assert_has(selector, text: "Her loyalty is an attempt to repair the harm she caused.")
  end

  defp note(ctx, actor, body, x, y, color) do
    idea_fixture(
      ctx,
      %{visibility: :shared, body: "<p>#{body}</p>", canvas: %{"x" => x, "y" => y, "width" => 280, "color" => color}},
      actor
    )
  end

  defp path(ctx) do
    project = Repo.preload(ctx.project, :workspace)
    "/workspaces/#{project.workspace.slug}/projects/#{project.slug}/brainstorming/#{ctx.session.id}"
  end

  defp click(browser, selector) do
    {:ok, _} = PlaywrightEx.Frame.click(browser.frame_id, selector: selector, timeout: 10_000)
    browser
  end
end
