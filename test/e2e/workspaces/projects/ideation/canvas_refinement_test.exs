defmodule StoryarnWeb.E2E.BrainstormingCanvasRefinementTest do
  use PhoenixTest.Playwright.Case, async: false

  import PhoenixTest.Playwright, only: [press: 3]
  import Storyarn.IdeationFixtures
  import StoryarnWeb.E2EHelpers

  alias PlaywrightEx.Frame
  alias PlaywrightEx.Page
  alias Storyarn.Ideation
  alias Storyarn.Repo

  @moduletag :e2e
  @moduletag browser_context_opts: [viewport: %{width: 1600, height: 1000}]

  setup do
    previous = Application.fetch_env!(:live_vue, :enable_props_diff)
    Application.put_env(:live_vue, :enable_props_diff, true)
    on_exit(fn -> Application.put_env(:live_vue, :enable_props_diff, previous) end)
    :ok
  end

  test "a narrative board stays compact and changing an outline preserves its position and zoom", %{conn: conn} do
    ctx = ideation_fixture()
    notes = narrative_board(ctx)
    short = Enum.at(notes, 2)

    browser =
      conn
      |> authenticate(ctx.author.user)
      |> visit(path(ctx))
      |> assert_has(".canvas-note", count: 14)
      |> press("#brainstorming-canvas", "1")

    metrics = board_geometry(browser, short.id)
    assert metrics["shortWidth"] < 240
    assert metrics["shortHeight"] < 95
    assert metrics["overlaps"] == [], "Notes overlap: #{inspect(metrics["overlaps"])}"
    assert metrics["shapeCounts"] == %{"plain" => 7, "rectangle" => 4, "ellipse" => 2, "diamond" => 1}

    browser = click(browser, "#canvas-note-#{short.id} .note-content")
    browser = assert_has(browser, "#canvas-note-#{short.id}[aria-selected=true]")
    before = board_geometry(browser, short.id)

    browser =
      browser
      |> click("#brainstorming-shape-picker")
      |> click("#note-shape-ellipse")
      |> assert_has("#canvas-note-#{short.id}[data-note-shape=ellipse]")
      |> refute_has("#note-shape-ellipse")

    after_shape = board_geometry(browser, short.id)
    assert before["transform"] == after_shape["transform"]
    assert before["position"] == after_shape["position"]
    assert after_shape["metadataPosition"] == "absolute"
    assert after_shape["metadataTop"] >= after_shape["noteBottom"] - 1
    assert after_shape["metadataOpacity"] == 1

    browser =
      browser
      |> press("#brainstorming-canvas", "ControlOrMeta+z")
      |> assert_has("#canvas-note-#{short.id}[data-note-shape=plain]")
      |> press("#brainstorming-canvas", "Escape")

    capture_review_images(browser)
  end

  test "dropping a note on another creates a plain connection that can be directed, deleted and undone", %{conn: conn} do
    ctx = ideation_fixture()
    source = note(ctx, "<p>The secret she keeps</p>", "plain", 0, 0, 240, "mint")
    target = note(ctx, "<p>The person who discovers it</p>", "rectangle", 350, 100, 240, "blue")
    edge = "[data-connection-source='#{source.id}'][data-connection-target='#{target.id}']"
    hit = "#canvas-connection-#{source.id}-#{target.id}"

    browser =
      conn
      |> authenticate(ctx.author.user)
      |> visit(path(ctx))
      |> assert_has(".canvas-note", count: 2)
      |> press("#brainstorming-canvas", "1")

    before = board_geometry(browser, source.id)
    browser = drag_onto_note(browser, source.id, target.id)
    browser = assert_edges(browser, edge <> ":not([marker-start]):not([marker-end])")
    after_drop = board_geometry(browser, source.id)
    assert before["position"] == after_drop["position"]

    assert {:ok, persisted} = Ideation.get_idea(ctx.author, ctx.project.id, ctx.session.id, source.id)
    assert persisted.canvas["x"] == source.canvas["x"]
    assert persisted.canvas["y"] == source.canvas["y"]

    browser =
      browser
      |> press("#brainstorming-canvas", "ControlOrMeta+a")
      |> click("#create-idea-group")
      |> assert_has("[data-group-id][aria-busy=false]", count: 1)
      |> click(hit)
      |> assert_has("#brainstorming-connection-toolbar")
      |> assert_has("#connection-direction-none[aria-pressed=true]")
      |> click("#connection-direction-forward")
      |> assert_edges(edge <> "[marker-end]:not([marker-start])")
      |> assert_has("#connection-direction-forward[aria-pressed=true]")
      |> click("#connection-direction-both")
      |> assert_edges(edge <> "[marker-start][marker-end]")
      |> assert_has("#connection-direction-both[aria-pressed=true]")
      |> press("#brainstorming-canvas", "Delete")
      |> assert_edges(edge, 0)
      |> press("#brainstorming-canvas", "ControlOrMeta+z")
      |> assert_edges(edge <> "[marker-start][marker-end]")
      |> press("#brainstorming-canvas", "ControlOrMeta+Shift+z")
      |> assert_edges(edge, 0)
      |> press("#brainstorming-canvas", "ControlOrMeta+z")
      |> assert_edges(edge <> "[marker-start][marker-end]")

    # The mutation acknowledgement can precede its queued board projection.
    # Let both finish before navigation cancels LiveView's database-reading task.
    browser
    |> assert_has("[data-group-id][aria-busy=false]", count: 1)
    |> assert_has("#brainstorming-workspace[aria-busy=false]")
    |> visit(path(ctx))
    |> assert_has(".canvas-note", count: 2)
    |> assert_edges(edge <> "[marker-start][marker-end]")
  end

  defp narrative_board(ctx) do
    specs = [
      {"<p><strong>What will Mara sacrifice?</strong></p>", "plain", 350, 250, 245, "mint"},
      {"<p>Mara keeps the city safe.<br>Its ruler keeps her brother captive.</p>", "rectangle", 20, 40, 230, "blue"},
      {"<p>The promise</p>", "plain", 325, 35, 190, "yellow"},
      {"<p>Find her brother</p>", "ellipse", 625, 30, 195, "coral"},
      {"<p>An unreliable map</p>", "plain", 935, 65, 220, "violet"},
      {"<p>Old tunnels beneath the city.<br>Who else knows the way?</p>", "rectangle", 20, 235, 240, "paper"},
      {"<p>Trust the envoy?</p>", "diamond", 650, 225, 235, "coral"},
      {"<p>The envoy knows<br>more than he admits.</p>", "plain", 935, 255, 205, "violet"},
      {"<p>City at dawn</p>", "ellipse", 20, 455, 225, "blue"},
      {"<p>Her friend guards the gate.<br><em>Duty or loyalty?</em></p>", "plain", 340, 455, 240, "mint"},
      {"<p><strong>The cost of silence</strong></p><p>A city survives.<br>A friendship ends.</p>", "rectangle", 650,
       450, 240, "yellow"},
      {"<p>Two endings</p>", "plain", 955, 455, 205, "coral"},
      {"<p>Save the city.<br>Lose a friend.</p>", "plain", 355, 645, 235, "mint"},
      {"<p>Let the truth escape.<br>What remains worth protecting?</p>", "rectangle", 865, 645, 250, "paper"}
    ]

    notes = Enum.map(specs, fn {body, shape, x, y, width, color} -> note(ctx, body, shape, x, y, width, color) end)

    relationships = [
      {1, 2, "none"},
      {2, 3, "forward"},
      {3, 4, "none"},
      {1, 5, "none"},
      {0, 2, "none"},
      {0, 6, "both"},
      {6, 7, "forward"},
      {5, 8, "none"},
      {0, 9, "none"},
      {9, 12, "forward"},
      {6, 10, "none"},
      {10, 11, "both"},
      {11, 13, "forward"}
    ]

    changes =
      Enum.map(relationships, fn {from, to, direction} ->
        %{source_id: Enum.at(notes, from).id, target_id: Enum.at(notes, to).id, connected: true, direction: direction}
      end)

    versions = changes |> Enum.map(& &1.source_id) |> Enum.uniq() |> Enum.map(&%{id: &1, version: 0})

    assert {:ok, _} =
             Ideation.update_idea_connections(ctx.author, ctx.project.id, ctx.session.id, %{
               request_key: Ecto.UUID.generate(),
               changes: changes,
               versions: versions
             })

    notes
  end

  defp note(ctx, body, shape, x, y, width, color) do
    idea_fixture(ctx, %{
      visibility: :shared,
      body: body,
      canvas: %{"x" => x, "y" => y, "width" => width, "color" => color, "shape" => shape}
    })
  end

  defp board_geometry(browser, id) do
    {:ok, geometry} =
      Frame.evaluate(browser.frame_id,
        expression: """
        (async () => {
          await document.fonts.ready;
          await new Promise(requestAnimationFrame);
          await new Promise(requestAnimationFrame);
          const note = document.querySelector('#canvas-note-#{id}');
          const wrapper = note.closest('[data-note-id]');
          const metadata = note.querySelector('.note-metadata');
          const world = document.querySelector('#brainstorming-canvas > .origin-top-left');
          const nodes = [...document.querySelectorAll('.canvas-note')];
          const shapes = {};
          const overlaps = [];
          for (let i = 0; i < nodes.length; i++) {
            shapes[nodes[i].dataset.noteShape] = (shapes[nodes[i].dataset.noteShape] || 0) + 1;
            const a = nodes[i].getBoundingClientRect();
            for (let j = i + 1; j < nodes.length; j++) {
              const b = nodes[j].getBoundingClientRect();
              if (a.left < b.right && b.left < a.right && a.top < b.bottom && b.top < a.bottom)
                overlaps.push([nodes[i].id, nodes[j].id]);
            }
          }
          return {
            shortWidth: note.offsetWidth, shortHeight: note.offsetHeight, overlaps, shapeCounts: shapes,
            transform: world.style.transform,
            position: wrapper.style.transform,
            metadataPosition: getComputedStyle(metadata).position,
            metadataOpacity: Number(getComputedStyle(metadata).opacity),
            metadataTop: metadata.getBoundingClientRect().top,
            noteBottom: note.getBoundingClientRect().bottom,
          };
        })()
        """,
        timeout: 10_000
      )

    geometry
  end

  defp drag_onto_note(browser, source_id, target_id) do
    {:ok, [source, target]} =
      Frame.evaluate(browser.frame_id,
        expression: """
        [#{source_id}, #{target_id}].map(id => {
          const box = document.querySelector('#canvas-note-' + id).getBoundingClientRect();
          return { x: box.left + box.width / 2, y: box.top + box.height / 2 };
        })
        """,
        timeout: 10_000
      )

    {:ok, _} = Page.mouse_move(browser.page_id, x: source["x"], y: source["y"], timeout: 10_000)
    {:ok, _} = Page.mouse_down(browser.page_id, timeout: 10_000)
    {:ok, _} = Page.mouse_move(browser.page_id, x: target["x"], y: target["y"], steps: 6, timeout: 10_000)
    browser = assert_has(browser, "#connection-target-#{target_id}")
    browser = assert_has(browser, "#brainstorming-connection-preview")
    {:ok, _} = Page.mouse_up(browser.page_id, timeout: 10_000)
    refute_has(browser, "#brainstorming-connection-preview")
  end

  defp capture_review_images(browser) do
    if System.get_env("STORYARN_CANVAS_REVIEW_IMAGES") == "1" do
      for theme <- ["light", "dark"] do
        {:ok, _} =
          Frame.evaluate(browser.frame_id,
            expression: """
            (async () => {
              document.documentElement.classList.toggle('dark', #{theme == "dark"});
              await new Promise(requestAnimationFrame);
              await new Promise(requestAnimationFrame);
            })()
            """,
            timeout: 10_000
          )

        {:ok, encoded} = Page.screenshot(browser.page_id, full_page: false, timeout: 10_000)
        File.write!("/private/tmp/canvas-refined-#{theme}.png", Base.decode64!(encoded))
      end
    end
  end

  defp assert_edges(browser, selector, count \\ 1) do
    {:ok, true} =
      Frame.expect(browser.frame_id,
        expression: "to.have.count",
        selector: selector,
        expected_number: count,
        timeout: 10_000
      )

    browser
  end

  defp click(browser, selector) do
    {:ok, _} = Frame.click(browser.frame_id, selector: selector, timeout: 10_000)
    browser
  end

  defp path(ctx) do
    project = Repo.preload(ctx.project, :workspace)
    "/workspaces/#{project.workspace.slug}/projects/#{project.slug}/brainstorming/#{ctx.session.id}"
  end
end
