defmodule StoryarnWeb.E2E.IdeationTimerTest do
  use PhoenixTest.Playwright.Case, async: false

  import PhoenixTest.Playwright, only: [press: 3, type: 3, evaluate: 3]
  import Storyarn.IdeationFixtures
  import StoryarnWeb.E2EHelpers

  alias PhoenixTest.Playwright.Config
  alias Storyarn.Ideation
  alias Storyarn.Repo

  @moduletag :e2e

  test "the facilitator controls a shared countdown while a viewer can only consult it", %{conn: conn} = test_context do
    ctx = ideation_fixture()
    path = board_path(ctx)

    manager =
      conn
      |> authenticate(ctx.facilitator.user)
      |> visit(path)
      |> assert_has("#brainstorming-canvas")
      |> evaluate("document.querySelector('#brainstorming-header').dataset.useDiff", fn mode ->
        assert mode == "true"
      end)

    viewer_config = test_context |> Map.take(Config.setup_keys()) |> Config.validate!()

    viewer =
      viewer_config
      |> PhoenixTest.Playwright.Case.new_session(test_context)
      |> authenticate(ctx.viewer.user)
      |> visit(path)
      |> assert_has("#brainstorming-canvas")

    manager =
      manager
      |> press("#brainstorming-round-timer-minutes", "ControlOrMeta+a")
      |> type("#brainstorming-round-timer-minutes", "10")
      |> click("#brainstorming-round-timer-start:not([disabled])")
      |> assert_has("#brainstorming-round-timer-pause[aria-disabled=false]")
      |> press("#brainstorming-round-timer-pause[aria-disabled=false]", "Enter")
      |> assert_has("#brainstorming-round-timer-resume[aria-disabled=false]")
      |> evaluate("document.activeElement.id", fn id -> assert id == "brainstorming-round-timer-resume" end)
      |> assert_has("#brainstorming-canvas")

    assert {:ok, paused} = Ideation.get_timer(ctx.facilitator, ctx.project.id, ctx.session.id)
    assert paused.status == :paused
    assert paused.duration_seconds == 600
    refute paused.close_contributions_on_expiry

    viewer =
      viewer
      |> assert_has("#brainstorming-round-timer", text: format_seconds(paused.remaining_seconds))
      |> assert_has("[aria-label='Paused']")
      |> refute_has("#brainstorming-round-timer-start")
      |> refute_has("#brainstorming-round-timer-resume")
      |> refute_has("#brainstorming-round-timer-extend")
      |> refute_has("#brainstorming-round-timer-cancel")
      |> click("#brainstorming-session-settings")
      |> assert_has("#brainstorming-session-form")
      |> refute_has("#brainstorming-contributions-toggle")
      |> click("#brainstorming-session-close")
      |> refute_has("#brainstorming-session-form")

    manager =
      manager
      |> click("#brainstorming-round-timer-extend:not([disabled])")
      |> assert_has("#brainstorming-round-timer", text: format_seconds(paused.remaining_seconds + 60))

    viewer = assert_has(viewer, "#brainstorming-round-timer", text: format_seconds(paused.remaining_seconds + 60))
    assert {:ok, extended} = Ideation.get_timer(ctx.viewer, ctx.project.id, ctx.session.id)
    assert extended.status == :paused
    assert extended.remaining_seconds == paused.remaining_seconds + 60
    assert extended.duration_seconds == 660

    manager =
      manager
      |> press("#brainstorming-round-timer-resume[aria-disabled=false]", "Enter")
      |> assert_has("#brainstorming-round-timer-pause[aria-disabled=false]")
      |> evaluate("document.activeElement.id", fn id -> assert id == "brainstorming-round-timer-pause" end)
      |> click("#brainstorming-round-timer-cancel:not([disabled])")
      |> assert_has("#brainstorming-round-timer-start:not([disabled])")

    refute_has(viewer, "#brainstorming-round-timer")
    assert {:ok, cancelled} = Ideation.get_timer(ctx.viewer, ctx.project.id, ctx.session.id)
    assert cancelled.status == :cancelled
    assert {:ok, session} = Ideation.get_session(ctx.viewer, ctx.project.id, ctx.session.id)
    assert session.configuration == ctx.session.configuration
    assert session.contributions_open
    assert session.status == :open

    # Starting a second clock reuses the timer row and patches the same prop object.
    manager
    |> click("#brainstorming-round-timer-start:not([disabled])")
    |> assert_has("#brainstorming-round-timer-pause[aria-disabled=false]")
    |> press("#brainstorming-round-timer-pause[aria-disabled=false]", "Enter")
    |> assert_has("#brainstorming-round-timer-resume[aria-disabled=false]")

    assert {:ok, restarted} = Ideation.get_timer(ctx.viewer, ctx.project.id, ctx.session.id)
    assert restarted.id == cancelled.id
    assert restarted.version > cancelled.version
    assert restarted.remaining_seconds > 0
    assert_has(viewer, "#brainstorming-round-timer", text: format_seconds(restarted.remaining_seconds))
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
      |> click("#brainstorming-session-settings")
      |> click("#brainstorming-contributions-toggle:not([disabled])")
      |> assert_has("#brainstorming-contributions-toggle", text: "Reopen contributions")
      |> assert_has("#brainstorming-contributions-closed")
      |> click("#brainstorming-session-close")
      |> refute_has("#new-brainstorming-idea")
      |> press("#brainstorming-canvas", "n")
      |> refute_has("[contenteditable=true]")

    {:ok, _} = PlaywrightEx.Frame.click(browser.frame_id, selector: selector, clickCount: 2, timeout: 10_000)

    browser =
      browser
      |> assert_has("#{selector} [contenteditable=true]")
      |> press("#{selector} [contenteditable=true]", "ControlOrMeta+a")
      |> type("#{selector} [contenteditable=true]", "The promise can still change.")
      |> refute_has("#{selector} .note-metadata", text: "Unsaved changes")
      |> refute_has("#{selector} .note-metadata", text: "Saving…")
      |> press("#{selector} [contenteditable=true]", "Escape")
      |> assert_has(selector, text: "The promise can still change.")
      |> click("#brainstorming-session-settings")
      |> click("#brainstorming-contributions-toggle:not([disabled])")
      |> refute_has("#brainstorming-contributions-closed")
      |> click("#brainstorming-session-close")
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

  defp format_seconds(seconds), do: "#{pad(div(seconds, 60))}:#{pad(rem(seconds, 60))}"

  defp pad(value), do: value |> Integer.to_string() |> String.pad_leading(2, "0")

  defp board_path(ctx) do
    project = Repo.preload(ctx.project, :workspace)
    "/workspaces/#{project.workspace.slug}/projects/#{project.slug}/brainstorming/#{ctx.session.id}"
  end

  defp click(browser, selector) do
    {:ok, _} = PlaywrightEx.Frame.click(browser.frame_id, selector: selector, timeout: 10_000)
    browser
  end
end
