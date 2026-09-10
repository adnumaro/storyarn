defmodule StoryarnWeb.E2E.BrainstormingShapesTest do
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

  test "a diamond keeps rich text readable, editable and undoable, and duplicates persist its shape", %{conn: conn} do
    ctx = ideation_fixture()

    source =
      note(
        ctx,
        ctx.author,
        """
        <p><strong>A difficult promise</strong></p>
        <p>She protects the city<br>but cannot trust its ruler.</p>
        <ul><li><p>Keep her sister safe.</p></li><li><p><em>Discover who broke the oath.</em></p></li></ul>
        <p></p>
        """,
        0,
        0
      )

    selector = "#canvas-note-#{source.id}"

    browser =
      conn
      |> authenticate(ctx.author.user)
      |> visit(path(ctx))
      |> assert_has(selector, text: "A difficult promise")
      |> press("#brainstorming-canvas", "1")
      |> select_note(source.id)
      |> change_shape("Diamond")
      |> assert_has("#{selector}[data-note-shape=diamond]")
      |> assert_has("#{selector} strong", text: "A difficult promise")
      |> assert_has("#{selector} em", text: "Discover who broke the oath.")

    assert_text_inside_diamond(browser, source.id)

    {:ok, _} =
      PlaywrightEx.Frame.click(browser.frame_id,
        selector: "#{selector} .note-content",
        clickCount: 2,
        timeout: 10_000
      )

    editor = "#{selector} [contenteditable=true]"

    browser =
      browser
      |> assert_has("#{editor}:focus")
      |> type(editor, " A new clue.")
      |> assert_has(selector, text: "A new clue.")
      |> press(editor, "ControlOrMeta+z")
      |> refute_has(selector, text: "A new clue.")
      |> assert_has("#{selector}[data-note-shape=diamond]")
      |> assert_has("#{selector} strong", text: "A difficult promise")

    browser =
      browser
      |> press(editor, "Escape")
      |> press("#brainstorming-canvas", "ControlOrMeta+z")
      |> assert_has("#{selector}[data-note-shape=rectangle]")
      |> press("#brainstorming-canvas", "ControlOrMeta+Shift+z")
      |> assert_has("#{selector}[data-note-shape=diamond]")
      |> assert_has("button[aria-label='Note shape']:not([disabled])")
      |> press("#brainstorming-canvas", "ControlOrMeta+d")
      |> assert_has("#brainstorming-workspace[aria-busy=false][data-persisted-note-count='2']")

    assert {:ok, ideas} = Ideation.list_ideas(ctx.author, ctx.project.id, ctx.session.id)
    assert length(ideas) == 2
    copy = Enum.find(ideas, &(&1.id != source.id))
    assert Enum.all?(ideas, &(&1.canvas["shape"] == "diamond"))

    browser
    |> visit(path(ctx))
    |> assert_has("#{selector}[data-note-shape=diamond]", text: "A difficult promise")
    |> assert_has("#canvas-note-#{copy.id}[data-note-shape=diamond]", text: "Discover who broke the oath.")
    |> assert_has("#canvas-note-#{copy.id} strong", text: "A difficult promise")
  end

  test "one shape change and one undo affect the selection, collaboration and connection boundaries",
       %{conn: conn} = context do
    ctx = ideation_fixture()
    first = note(ctx, ctx.author, "<p>A promise to keep.</p>", 0, 0)
    second = note(ctx, ctx.peer, "<p>A reason to break it.</p>", 850, 550)
    {:ok, _} = Ideation.connect_ideas(ctx.author, ctx.project.id, ctx.session.id, first.id, second.id, true)
    edge = "[data-connection-source='#{first.id}'][data-connection-target='#{second.id}']"

    browser = conn |> authenticate(ctx.author.user) |> visit(path(ctx)) |> assert_has("#brainstorming-canvas")
    viewer_config = context |> Map.take(Config.setup_keys()) |> Config.validate!()

    viewer =
      viewer_config
      |> PhoenixTest.Playwright.Case.new_session(context)
      |> authenticate(ctx.viewer.user)
      |> visit(path(ctx))
      |> assert_has("#canvas-note-#{first.id}")

    browser =
      browser
      |> press("#brainstorming-canvas", "1")
      |> select_note(first.id)
      |> select_note(second.id, ["Shift"])

    before = connection_geometry(browser, edge, first.id, second.id)

    browser =
      browser
      |> change_shape("Ellipse")
      |> assert_has(".canvas-note[data-note-shape=ellipse]", count: 2)

    viewer = assert_has(viewer, ".canvas-note[data-note-shape=ellipse]", count: 2)
    after_shape = connection_geometry(browser, edge, first.id, second.id)
    refute before["points"] == after_shape["points"]

    for boundary <- [after_shape["source"], after_shape["target"]] do
      assert boundary >= 0.99
      assert boundary <= 1.2
    end

    browser =
      browser
      |> press("#brainstorming-canvas", "ControlOrMeta+z")
      |> assert_has(".canvas-note[data-note-shape=rectangle]", count: 2)

    viewer = assert_has(viewer, ".canvas-note[data-note-shape=rectangle]", count: 2)

    browser =
      browser
      |> press("#brainstorming-canvas", "ControlOrMeta+Shift+z")
      |> assert_has(".canvas-note[data-note-shape=ellipse]", count: 2)

    assert_has(viewer, ".canvas-note[data-note-shape=ellipse]", count: 2)
    refute_has(viewer, "button[aria-label='Note shape']")
    browser |> visit(path(ctx)) |> assert_has(".canvas-note[data-note-shape=ellipse]", count: 2)
  end

  test "a blank draft keeps its editor focused when its shape changes and saves that shape", %{conn: conn} do
    ctx = ideation_fixture()
    editor = ".canvas-note[data-note-shape=diamond] [contenteditable=true]"

    browser =
      conn
      |> authenticate(ctx.author.user)
      |> visit(path(ctx))
      |> assert_has("#brainstorming-canvas")
      |> press("#brainstorming-canvas", "n")
      |> assert_has(".canvas-note [contenteditable=true]:focus")
      |> change_shape("Diamond")
      |> assert_has(".canvas-note", count: 1)
      |> assert_has("#{editor}:focus")
      |> type(editor, "A choice with consequences.")
      |> press(editor, "Escape")
      |> assert_has("#brainstorming-workspace[aria-busy=false][data-persisted-note-count='1']")

    assert {:ok, [saved]} = Ideation.list_ideas(ctx.author, ctx.project.id, ctx.session.id)
    assert saved.canvas["shape"] == "diamond"

    browser
    |> visit(path(ctx))
    |> assert_has("#canvas-note-#{saved.id}[data-note-shape=diamond]", text: "A choice with consequences.")
  end

  defp assert_text_inside_diamond(browser, id) do
    {:ok, metrics} =
      PlaywrightEx.Frame.evaluate(browser.frame_id,
        expression: """
        (async () => {
          await document.fonts.ready;
          await new Promise(requestAnimationFrame);
          await new Promise(requestAnimationFrame);
          const note = document.querySelector('#canvas-note-#{id}');
          const bounds = note.getBoundingClientRect();
          const canvas = document.querySelector('#brainstorming-canvas').getBoundingClientRect();
          const dock = document.querySelector('#new-brainstorming-idea').closest('[data-canvas-chrome]').getBoundingClientRect();
          const outline = getComputedStyle(note.querySelector('.note-outline'));
          const center = { x: bounds.x + bounds.width / 2, y: bounds.y + bounds.height / 2 };
          const walker = document.createTreeWalker(note.querySelector('.note-text'), NodeFilter.SHOW_TEXT);
          const corners = [];
          let text;
          while ((text = walker.nextNode())) {
            if (!text.textContent.trim()) continue;
            const range = document.createRange();
            range.selectNodeContents(text);
            for (const rect of range.getClientRects()) {
              if (!rect.width || !rect.height) continue;
              for (const x of [rect.left, rect.right]) for (const y of [rect.top, rect.bottom]) {
                corners.push(Math.abs(x - center.x) / (bounds.width / 2) + Math.abs(y - center.y) / (bounds.height / 2));
              }
            }
          }
          return {
            corners, width: bounds.width, height: bounds.height,
            outlineColor: outline.backgroundColor,
            outlineOpacity: Number(outline.opacity),
            margins: [bounds.left - canvas.left, canvas.right - bounds.right, bounds.top - canvas.top, canvas.bottom - bounds.bottom],
            dockClearance: dock.top - bounds.bottom,
          };
        })()
        """,
        timeout: 10_000
      )

    assert metrics["width"] > 0
    assert metrics["height"] > 0
    assert metrics["corners"] != []
    assert Enum.all?(metrics["corners"], &(&1 <= 1.02)), "Text extends outside the diamond: #{inspect(metrics)}"
    refute metrics["outlineColor"] in ["", "transparent", "rgba(0, 0, 0, 0)"]
    assert metrics["outlineOpacity"] > 0
    assert Enum.all?(metrics["margins"], &(&1 >= 6)), "The shape is clipped by the canvas: #{inspect(metrics)}"
    assert metrics["dockClearance"] >= 6, "The dock overlaps the diamond: #{inspect(metrics)}"
  end

  defp connection_geometry(browser, edge, source_id, target_id) do
    {:ok, geometry} =
      PlaywrightEx.Frame.evaluate(browser.frame_id,
        expression: """
        (async () => {
          await new Promise(requestAnimationFrame);
          await new Promise(requestAnimationFrame);
          const line = document.querySelector(#{Jason.encode!(edge)});
          const matrix = line.getScreenCTM();
          const points = ['x1', 'y1', 'x2', 'y2'].map(name => Number(line.getAttribute(name)));
          function boundary(id, x, y) {
            const box = document.querySelector('#canvas-note-' + id).getBoundingClientRect();
            const point = new DOMPoint(x, y).matrixTransform(matrix);
            const dx = (point.x - box.x - box.width / 2) / (box.width / 2);
            const dy = (point.y - box.y - box.height / 2) / (box.height / 2);
            return dx * dx + dy * dy;
          }
          return { points, source: boundary(#{source_id}, points[0], points[1]), target: boundary(#{target_id}, points[2], points[3]) };
        })()
        """,
        timeout: 10_000
      )

    geometry
  end

  defp change_shape(browser, label) do
    browser
    |> click("button[aria-label='Note shape']")
    |> click("button:text-is(#{Jason.encode!(label)})")
    |> refute_has("#note-shape-rectangle")
  end

  defp select_note(browser, id, modifiers \\ []) do
    {:ok, _} =
      PlaywrightEx.Frame.click(browser.frame_id,
        selector: "#canvas-note-#{id} footer",
        modifiers: modifiers,
        timeout: 10_000
      )

    assert_has(browser, "#canvas-note-#{id}[aria-selected=true]")
  end

  defp click(browser, selector) do
    {:ok, _} = PlaywrightEx.Frame.click(browser.frame_id, selector: selector, timeout: 10_000)
    browser
  end

  defp note(ctx, actor, body, x, y) do
    idea_fixture(
      ctx,
      %{visibility: :shared, body: body, canvas: %{"x" => x, "y" => y, "width" => 280, "color" => "yellow"}},
      actor
    )
  end

  defp path(ctx) do
    project = Repo.preload(ctx.project, :workspace)
    "/workspaces/#{project.workspace.slug}/projects/#{project.slug}/brainstorming/#{ctx.session.id}"
  end
end
