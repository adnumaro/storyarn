defmodule StoryarnWeb.E2E.IdeationRoundsTest do
  use PhoenixTest.Playwright.Case, async: false

  import PhoenixTest.Playwright, only: [click: 2, press: 3, type: 3]
  import Storyarn.IdeationFixtures
  import StoryarnWeb.E2EHelpers

  alias PhoenixTest.Playwright.Config
  alias Storyarn.Ideation
  alias Storyarn.Repo

  @moduletag :e2e

  test "a session starts quiet and the next round opens a new band below the notes without moving them",
       %{conn: conn} do
    ctx = ideation_fixture()
    first = first_round(ctx)

    {:ok, existing} =
      Ideation.create_canvas_idea(ctx.facilitator, ctx.project.id, ctx.session.id, %{
        request_key: Ecto.UUID.generate(),
        body: "<p>A question before any round.</p>",
        canvas: %{"x" => -340, "y" => 120, "width" => 280, "color" => "yellow"}
      })

    browser =
      conn
      |> authenticate(ctx.facilitator.user)
      |> visit(board_path(ctx))
      |> assert_has("#canvas-note-#{existing.id}")
      |> refute_has("#brainstorming-band-#{first.id}")
      |> right_click("#brainstorming-canvas")
      |> click("#brainstorming-round-context-new")
      |> assert_has("#brainstorming-round-#{first.id}[data-status=closed]", text: "Round 1")
      |> assert_has("[id^='brainstorming-round-'][data-status=active]", text: "Round 2")

    assert {:ok, [second, closed]} = Ideation.list_rounds(ctx.facilitator, ctx.project.id, ctx.session.id)
    assert closed.id == first.id

    browser =
      browser
      |> assert_has("#brainstorming-tree-round-#{second.id}[data-status=active]", text: "Round 2")
      |> press("#brainstorming-canvas", "n")
      |> assert_has("[data-note-id^='-'] [contenteditable=true]")
      |> dump_notes("after n")
      |> type("[data-note-id^='-'] [contenteditable=true]", "The antagonist wants to return a stolen memory.")
      |> dump_notes("after typing")
      |> assert_has("[data-note-id] [contenteditable=true]", text: "The antagonist wants to return a stolen memory.")
      |> assert_has("[data-note-id]:not([data-note-id^='-'])", text: "The antagonist wants to return a stolen memory.")
      |> press("[contenteditable=true]", "Escape")
      |> persisted(2)

    assert {:ok, [contribution]} =
             Ideation.list_ideas(ctx.facilitator, ctx.project.id, ctx.session.id, round_id: second.id)

    assert contribution.body == "<p>The antagonist wants to return a stolen memory.</p>"
    refute contribution.late_contribution
    assert {:ok, earlier} = Ideation.get_idea(ctx.facilitator, ctx.project.id, ctx.session.id, existing.id)
    assert earlier.round_id == first.id
    assert earlier.canvas["y"] == 120

    browser
    |> visit(board_path(ctx))
    |> assert_has("#brainstorming-round-#{second.id}[data-status=active]")
    |> assert_has("#canvas-note-#{existing.id}[data-round-id='#{first.id}']")
    |> assert_has("#canvas-note-#{contribution.id}[data-round-id='#{second.id}']")
    |> assert_has(".canvas-note", count: 2)
  end

  test "a round closes in both browsers while private notes remain private and editable",
       %{conn: conn} = test_context do
    ctx = ideation_fixture()
    assert {:ok, _} = Ideation.set_private_mode(ctx.facilitator, ctx.project.id, ctx.session.id, 1, true)
    assert {:ok, private} = Ideation.get_session(ctx.facilitator, ctx.project.id, ctx.session.id)
    {ctx, round} = new_round(%{ctx | session: private}, %{prompt: "What would make the river forget?"})
    path = board_path(ctx)

    facilitator =
      conn
      |> authenticate(ctx.facilitator.user)
      |> visit(path)
      |> assert_has("#brainstorming-round-#{round.id}[data-status=active]", text: "What would make the river forget?")

    peer_config = test_context |> Map.take(Config.setup_keys()) |> Config.validate!()

    peer =
      peer_config
      |> PhoenixTest.Playwright.Case.new_session(test_context)
      |> authenticate(ctx.peer.user)
      |> visit(path)
      |> assert_has("#brainstorming-round-#{round.id}[data-status=active]", text: "Round 2")
      |> refute_has("#brainstorming-round-close-#{round.id}")
      |> refute_has("#brainstorming-round-next")
      |> press("#brainstorming-canvas", "n")
      |> assert_has("[data-note-id^='-'] [contenteditable=true]")
      |> type("[data-note-id^='-'] [contenteditable=true]", "A secret promise could change the river.")
      |> assert_has("[data-note-id] [contenteditable=true]", text: "A secret promise could change the river.")
      |> assert_has("[data-note-id]:not([data-note-id^='-'])", text: "A secret promise could change the river.")
      |> press("[contenteditable=true]", "Escape")
      |> persisted(1)

    assert {:ok, [note]} = Ideation.list_ideas(ctx.peer, ctx.project.id, ctx.session.id)
    assert note.round_id == round.id
    assert note.visibility == :private
    refute_has(facilitator, "#canvas-note-#{note.id}")

    facilitator =
      facilitator
      |> click("#brainstorming-round-close-#{round.id}:not([disabled])")
      |> assert_has("#brainstorming-round-#{round.id}[data-status=closed]")
      |> assert_has("#brainstorming-round-new-#{round.id}")
      |> assert_has("button[aria-label='End private mode and reveal to everyone']")

    peer = assert_has(peer, "#brainstorming-round-#{round.id}[data-status=closed]")

    selector = "#canvas-note-#{note.id}"
    {:ok, _} = PlaywrightEx.Frame.click(peer.frame_id, selector: selector, clickCount: 2, timeout: 10_000)

    peer
    |> assert_has("#{selector} [contenteditable=true]")
    |> press("#{selector} [contenteditable=true]", "ControlOrMeta+a")
    |> type("#{selector} [contenteditable=true]", "The river remembers the promise even after this round.")
    |> refute_has("#{selector} .note-metadata", text: "Unsaved changes")
    |> refute_has("#{selector} .note-metadata", text: "Saving…")
    |> press("#{selector} [contenteditable=true]", "Escape")
    |> persisted(1)
    |> assert_has(selector, text: "The river remembers the promise even after this round.")
    |> assert_has("#{selector}[data-round-id='#{round.id}']")

    refute_has(facilitator, selector)
    assert {:ok, updated} = Ideation.get_idea(ctx.peer, ctx.project.id, ctx.session.id, note.id)
    assert updated.body == "<p>The river remembers the promise even after this round.</p>"
    assert updated.round_id == round.id
    assert updated.visibility == :private
    refute updated.late_contribution
    assert {:error, :not_found} = Ideation.get_idea(ctx.facilitator, ctx.project.id, ctx.session.id, note.id)
    assert {:ok, current} = Ideation.get_session(ctx.facilitator, ctx.project.id, ctx.session.id)
    assert current.configuration == private.configuration
    assert current.status == :open
  end

  test "the session tree opens a band and the parked list from deep links", %{conn: conn} do
    ctx = ideation_fixture()
    first = first_round(ctx)
    parked = idea_fixture(ctx, %{visibility: :shared, state: :parked, canvas: %{"x" => 0, "y" => 100}})
    {ctx, second} = new_round(ctx, %{prompt: "Second question"})

    conn
    |> authenticate(ctx.author.user)
    |> visit(board_path(ctx))
    |> assert_has("#brainstorming-tree-round-#{first.id}", text: "Round 1")
    |> assert_has("#brainstorming-tree-round-#{second.id}", text: "Round 2")
    |> assert_has("#brainstorming-tree-later-#{ctx.session.id}", text: "1")
    |> click("#brainstorming-tree-round-#{first.id}")
    |> assert_path(board_path(ctx), query_params: %{"round" => Integer.to_string(first.id)})
    |> assert_has("#brainstorming-round-#{first.id}[data-status=closed]")
    |> click("#brainstorming-tree-later-#{ctx.session.id}")
    |> assert_path(board_path(ctx), query_params: %{"view" => "later"})
    |> assert_has("button", text: "Back to canvas")
    |> assert_has("#canvas-list-note-#{parked.id}", text: "Parked")
  end

  test "viewers can consult the round headers without starting or closing rounds", %{conn: conn} do
    ctx = ideation_fixture()
    first = first_round(ctx)
    {ctx, round} = new_round(ctx, %{prompt: "Which memory changes the story?"})

    conn
    |> authenticate(ctx.viewer.user)
    |> visit(board_path(ctx))
    |> assert_has("#brainstorming-round-#{first.id}[data-status=closed]", text: "Round 1")
    |> assert_has("#brainstorming-round-#{round.id}[data-status=active]", text: "Which memory changes the story?")
    |> refute_has("#brainstorming-round-next")
    |> refute_has("#brainstorming-round-new-#{round.id}")
    |> refute_has("#brainstorming-round-close-#{round.id}")
  end

  # Temporary diagnostics for CI: what the canvas holds right after typing.
  defp dump_notes(browser, label) do
    Process.sleep(1_500)

    {:ok, dump} =
      PlaywrightEx.Frame.evaluate(browser.frame_id,
        timeout: 10_000,
        expression: """
        JSON.stringify({
          active: document.activeElement && (document.activeElement.tagName + '#' + document.activeElement.id + '.' + document.activeElement.className),
          notes: [...document.querySelectorAll('[data-note-id]')].map((el) => ({
            id: el.dataset.noteId,
            editable: !!el.querySelector('[contenteditable=true]'),
            text: el.textContent.trim().slice(0, 80)
          })),
          editors: [...document.querySelectorAll('[contenteditable=true]')].map((el) => el.textContent.trim().slice(0, 80)),
          workspace: (document.querySelector('#brainstorming-workspace') || {}).outerHTML?.slice(0, 200)
        })
        """
      )

    IO.puts("[rounds e2e] " <> label <> ": " <> inspect(dump))
    browser
  end

  defp persisted(browser, count) do
    assert_has(browser, "#brainstorming-workspace[aria-busy=false][data-persisted-note-count='#{count}']")
  end

  defp board_path(ctx) do
    project = Repo.preload(ctx.project, :workspace)
    "/workspaces/#{project.workspace.slug}/projects/#{project.slug}/brainstorming/#{ctx.session.id}"
  end
end
