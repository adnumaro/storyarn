defmodule StoryarnWeb.E2E.IdeationConnectionsTest do
  use PhoenixTest.Playwright.Case, async: false

  import PhoenixTest.Playwright, only: [press: 3, type: 3]
  import Storyarn.IdeationFixtures
  import StoryarnWeb.E2EHelpers

  alias PhoenixTest.Playwright.Config
  alias Storyarn.Ideation
  alias Storyarn.Repo

  @moduletag :e2e

  setup do
    previous = Application.fetch_env!(:live_vue, :enable_props_diff)
    Application.put_env(:live_vue, :enable_props_diff, true)
    on_exit(fn -> Application.put_env(:live_vue, :enable_props_diff, previous) end)
    :ok
  end

  test "connect a selection, undo and redo, and write a connected note in place", %{conn: conn} = context do
    ctx = ideation_fixture()
    first = note(ctx, ctx.author, "The promise", 0)
    second = note(ctx, ctx.peer, "The consequence", 360)
    browser = conn |> authenticate(ctx.author.user) |> visit(path(ctx)) |> assert_has("#brainstorming-canvas")

    viewer_config = context |> Map.take(Config.setup_keys()) |> Config.validate!()

    viewer =
      viewer_config
      |> PhoenixTest.Playwright.Case.new_session(context)
      |> authenticate(ctx.viewer.user)
      |> visit(path(ctx))

    browser = browser |> press("#brainstorming-canvas", "1") |> select_note(first.id) |> select_note(second.id, ["Shift"])
    edge = "[data-connection-source='#{first.id}'][data-connection-target='#{second.id}']"

    browser = press(browser, "#brainstorming-canvas", "l")
    browser = assert_edges(browser, edge)
    assert_edges(viewer, edge)
    browser = browser |> press("#brainstorming-canvas", "ControlOrMeta+z") |> assert_edges(edge, 0)
    browser = browser |> press("#brainstorming-canvas", "ControlOrMeta+Shift+z") |> assert_edges(edge)
    browser = browser |> press("#brainstorming-canvas", "Shift+l") |> assert_edges(edge, 0)
    browser = browser |> press("#brainstorming-canvas", "ControlOrMeta+z") |> assert_edges(edge)

    browser =
      browser |> press("#brainstorming-canvas", "Alt+Shift+ArrowRight") |> assert_has("[contenteditable=true]:focus")

    browser =
      browser
      |> type("[contenteditable=true]", "She breaks the promise to save her rival.")
      |> assert_has("[data-note-id]:not([data-note-id^='-'])", text: "She breaks the promise to save her rival.")

    browser = assert_has(browser, "#brainstorming-workspace[data-persisted-note-count='3']")
    {:ok, notes} = Ideation.list_ideas(ctx.author, ctx.project.id, ctx.session.id)
    created = Enum.find(notes, &(&1.id not in [first.id, second.id]))
    incoming = "[data-connection-target='#{created.id}']"
    browser = browser |> assert_edges(incoming, 2) |> press("[contenteditable=true]", "Escape")
    viewer |> assert_has("#canvas-note-#{created.id}") |> assert_edges(incoming, 2)

    # One undo removes both the new note and its visible connections. The earlier
    # connection remains; redo restores the same identity and only its links.
    # Wait for each persisted projection before navigation can cancel an active
    # refresh reader and invalidate the shared SQL sandbox connection.
    browser =
      browser
      |> press("#brainstorming-canvas", "ControlOrMeta+z")
      |> refute_has("#canvas-note-#{created.id}")
      |> assert_has("#brainstorming-workspace[data-persisted-note-count='2']")
      |> assert_edges(incoming, 0)
      |> assert_edges(edge)
      |> assert_has("#brainstorming-workspace[aria-busy=false][data-persisted-note-count='2']")

    browser =
      browser
      |> press("#brainstorming-canvas", "ControlOrMeta+Shift+z")
      |> assert_has("#canvas-note-#{created.id}")
      |> assert_has("#brainstorming-workspace[data-persisted-note-count='3']")
      |> assert_edges(incoming, 2)
      |> assert_has("#brainstorming-workspace[aria-busy=false][data-persisted-note-count='3']")

    viewer
    |> assert_has("#canvas-note-#{created.id}")
    |> assert_edges(incoming, 2)
    |> assert_has("#brainstorming-workspace[aria-busy=false][data-persisted-note-count='3']")

    browser
    |> assert_has("#brainstorming-workspace[aria-busy=false]")
    |> visit(path(ctx))
    |> assert_edges(incoming, 2)
    |> assert_edges(edge)
  end

  test "contextual creation can be cancelled empty without persisting a note or link", %{conn: conn} do
    ctx = ideation_fixture()
    source = note(ctx, ctx.author, "A reason to return", 0)

    browser =
      conn
      |> authenticate(ctx.author.user)
      |> visit(path(ctx))
      |> assert_has("#brainstorming-canvas")
      |> select_note(source.id)

    browser =
      browser
      |> click("#brainstorming-connection-tools")
      |> assert_has("#add-connected-idea-down")
      |> click("#add-connected-idea-down")
      |> assert_has("[contenteditable=true]:focus")

    browser =
      browser
      |> assert_has("[data-note-id]", count: 2)
      |> press("[contenteditable=true]", "Escape")
      |> assert_has("[data-note-id]", count: 1)

    refute_has(browser, "[data-connection-source]")
    assert {:ok, [remaining]} = Ideation.list_ideas(ctx.author, ctx.project.id, ctx.session.id)
    assert remaining.id == source.id
    assert remaining.canvas["links"] == []
  end

  defp note(ctx, actor, body, x) do
    idea_fixture(
      ctx,
      %{visibility: :shared, body: "<p>#{body}</p>", canvas: %{"x" => x, "y" => 0, "width" => 280, "color" => "yellow"}},
      actor
    )
  end

  defp select_note(browser, id, modifiers \\ []) do
    {:ok, _} =
      PlaywrightEx.Frame.click(browser.frame_id,
        selector: "#canvas-note-#{id} .note-content",
        modifiers: modifiers,
        timeout: 10_000
      )

    assert_has(browser, "#canvas-note-#{id}[aria-selected=true]")
  end

  # A horizontal SVG line has zero bounding-box height. Assert the rendered
  # edge count rather than Playwright's visibility filter for HTML elements.
  defp assert_edges(browser, selector, count \\ 1) do
    {:ok, true} =
      PlaywrightEx.Frame.expect(browser.frame_id,
        expression: "to.have.count",
        selector: selector,
        expected_number: count,
        timeout: 10_000
      )

    browser
  end

  defp click(browser, selector) do
    {:ok, _} = PlaywrightEx.Frame.click(browser.frame_id, selector: selector, timeout: 10_000)
    browser
  end

  defp path(ctx) do
    project = Repo.preload(ctx.project, :workspace)
    "/workspaces/#{project.workspace.slug}/projects/#{project.slug}/brainstorming/#{ctx.session.id}"
  end
end
