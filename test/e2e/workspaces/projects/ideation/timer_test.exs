defmodule StoryarnWeb.E2E.IdeationTimerTest do
  use PhoenixTest.Playwright.Case, async: false

  import PhoenixTest.Playwright, only: [press: 3, type: 3]
  import Storyarn.IdeationFixtures
  import StoryarnWeb.E2EHelpers

  alias PhoenixTest.Playwright.Config
  alias Storyarn.Ideation
  alias Storyarn.Repo

  @moduletag :e2e

  test "the facilitator controls a shared countdown while a viewer can only consult it", %{conn: conn} = test_context do
    ctx = ideation_fixture()
    path = board_path(ctx)
    manager = conn |> authenticate(ctx.facilitator.user) |> visit(path) |> assert_has("#brainstorming-canvas")
    viewer_config = test_context |> Map.take(Config.setup_keys()) |> Config.validate!()

    viewer =
      viewer_config
      |> PhoenixTest.Playwright.Case.new_session(test_context)
      |> authenticate(ctx.viewer.user)
      |> visit(path)
      |> assert_has("#brainstorming-canvas")

    manager =
      manager
      |> click("#brainstorming-timer-trigger")
      |> press("#brainstorming-timer-duration", "ControlOrMeta+a")
      |> type("#brainstorming-timer-duration", "600")
      |> click("#brainstorming-timer-start:not([disabled])")
      |> assert_has("#brainstorming-timer-pause:not([disabled])")
      |> click("#brainstorming-timer-pause:not([disabled])")
      |> assert_has("#brainstorming-timer-resume:not([disabled])")
      |> assert_has("#brainstorming-canvas")

    assert {:ok, paused} = Ideation.get_timer(ctx.facilitator, ctx.project.id, ctx.session.id)
    assert paused.status == :paused
    assert paused.duration_seconds == 600
    refute paused.reveal_on_expiry
    refute paused.close_contributions_on_expiry

    viewer =
      viewer
      |> assert_has("#brainstorming-timer-countdown", text: format_seconds(paused.remaining_seconds))
      |> click("#brainstorming-timer-trigger")
      |> assert_has("[data-slot=popover-content]", text: "Paused")
      |> refute_has("#brainstorming-timer-start")
      |> refute_has("#brainstorming-timer-resume")
      |> refute_has("#brainstorming-timer-extend")
      |> refute_has("#brainstorming-timer-cancel")
      |> refute_has("#brainstorming-contributions-toggle")

    manager =
      manager
      |> click("#brainstorming-timer-extend:not([disabled])")
      |> assert_has("#brainstorming-timer-countdown", text: format_seconds(paused.remaining_seconds + 60))

    viewer = assert_has(viewer, "#brainstorming-timer-countdown", text: format_seconds(paused.remaining_seconds + 60))
    assert {:ok, extended} = Ideation.get_timer(ctx.viewer, ctx.project.id, ctx.session.id)
    assert extended.status == :paused
    assert extended.remaining_seconds == paused.remaining_seconds + 60
    assert extended.duration_seconds == 660

    manager
    |> click("#brainstorming-timer-resume:not([disabled])")
    |> assert_has("#brainstorming-timer-pause:not([disabled])")
    |> click("#brainstorming-timer-cancel:not([disabled])")
    |> assert_has("#brainstorming-timer-start:not([disabled])")
    |> click("#brainstorming-timer-trigger")
    |> assert_has("#brainstorming-canvas")

    assert_has(viewer, "#brainstorming-timer-countdown", text: "Timer")
    assert {:ok, cancelled} = Ideation.get_timer(ctx.viewer, ctx.project.id, ctx.session.id)
    assert cancelled.status == :cancelled
    assert {:ok, session} = Ideation.get_session(ctx.viewer, ctx.project.id, ctx.session.id)
    assert session.configuration == ctx.session.configuration
    assert session.contributions_open
    assert session.status == :open
  end

  test "closing contributions preserves existing editing and reopening restores creation", %{conn: conn} do
    ctx = ideation_fixture()

    assert {:ok, existing} =
             Ideation.create_canvas_idea(ctx.facilitator, ctx.project.id, ctx.session.id, %{
               request_key: Ecto.UUID.generate(),
               body: "<p>The original promise.</p>",
               canvas: %{"x" => 0, "y" => 0, "width" => 280, "color" => "yellow"}
             })

    selector = "#canvas-note-#{existing.id}"

    browser =
      conn
      |> authenticate(ctx.facilitator.user)
      |> visit(board_path(ctx))
      |> assert_has(selector)
      |> click("#brainstorming-timer-trigger")
      |> click("#brainstorming-contributions-toggle:not([disabled])")
      |> assert_has("#brainstorming-contributions-toggle", text: "Reopen contributions")
      |> assert_has("#brainstorming-contributions-closed")
      |> click("#brainstorming-timer-trigger")
      |> refute_has("#new-brainstorming-idea")
      |> press("#brainstorming-canvas", "n")
      |> refute_has("[contenteditable=true]")

    {:ok, _} = PlaywrightEx.Frame.click(browser.frame_id, selector: selector, clickCount: 2, timeout: 10_000)

    browser =
      browser
      |> assert_has("#{selector} [contenteditable=true]")
      |> press("#{selector} [contenteditable=true]", "ControlOrMeta+a")
      |> type("#{selector} [contenteditable=true]", "The promise can still change.")
      |> refute_has("#{selector} footer", text: "Unsaved changes")
      |> refute_has("#{selector} footer", text: "Saving…")
      |> press("#{selector} [contenteditable=true]", "Escape")
      |> assert_has(selector, text: "The promise can still change.")
      |> click("#brainstorming-timer-trigger")
      |> click("#brainstorming-contributions-toggle:not([disabled])")
      |> refute_has("#brainstorming-contributions-closed")
      |> click("#brainstorming-timer-trigger")
      |> assert_has("#new-brainstorming-idea")
      |> press("#brainstorming-canvas", "n")
      |> type("[contenteditable=true]", "A contribution after reopening.")
      |> assert_has("[data-note-id]:not([data-note-id^='-'])", text: "A contribution after reopening.")
      |> press("[contenteditable=true]", "Escape")
      |> assert_has("#brainstorming-workspace[aria-busy=false][data-persisted-note-count='2']")

    assert {:ok, saved} = Ideation.get_idea(ctx.facilitator, ctx.project.id, ctx.session.id, existing.id)
    assert saved.body == "<p>The promise can still change.</p>"
    assert {:ok, nil} = Ideation.get_timer(ctx.facilitator, ctx.project.id, ctx.session.id)
    browser |> visit(board_path(ctx)) |> assert_has(".canvas-note", count: 2)
  end

  defp format_seconds(seconds),
    do: "#{div(seconds, 60)}:#{seconds |> rem(60) |> Integer.to_string() |> String.pad_leading(2, "0")}"

  defp board_path(ctx) do
    project = Repo.preload(ctx.project, :workspace)
    "/workspaces/#{project.workspace.slug}/projects/#{project.slug}/brainstorming/#{ctx.session.id}"
  end

  defp click(browser, selector) do
    {:ok, _} = PlaywrightEx.Frame.click(browser.frame_id, selector: selector, timeout: 10_000)
    browser
  end
end
