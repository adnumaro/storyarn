defmodule StoryarnWeb.E2E.IdeationRoundsTest do
  use PhoenixTest.Playwright.Case, async: false

  import PhoenixTest.Playwright, only: [press: 3, type: 3]
  import Storyarn.IdeationFixtures
  import StoryarnWeb.E2EHelpers

  alias PhoenixTest.Playwright.Config
  alias Storyarn.Ideation
  alias Storyarn.Repo

  @moduletag :e2e

  test "prepare and start an optional round on the existing canvas without moving earlier notes", %{conn: conn} do
    ctx = ideation_fixture()

    {:ok, existing} =
      Ideation.create_canvas_idea(ctx.facilitator, ctx.project.id, ctx.session.id, %{
        request_key: Ecto.UUID.generate(),
        body: "<p>A question before any round.</p>",
        canvas: %{"x" => -340, "y" => 0, "width" => 280, "color" => "yellow"}
      })

    browser =
      conn
      |> authenticate(ctx.facilitator.user)
      |> visit(board_path(ctx))
      |> assert_has("#canvas-note-#{existing.id}")
      |> click("#brainstorming-rounds-trigger")
      |> type("#brainstorming-round-prompt", "What does the antagonist want?")
      |> click("#brainstorming-round-create:not([disabled])")
      |> assert_has("[id^='brainstorming-round-'][data-status=planned]", text: "What does the antagonist want?")

    assert {:ok, [round]} = Ideation.list_rounds(ctx.facilitator, ctx.project.id, ctx.session.id)

    browser =
      browser
      |> click("#brainstorming-round-start-#{round.id}:not([disabled])")
      |> assert_has("#brainstorming-round-#{round.id}[data-status=active]")
      |> assert_has("#brainstorming-active-round", text: "Round 1")
      |> click("#brainstorming-rounds-trigger")
      |> assert_has("#brainstorming-round-context", text: "What does the antagonist want?")
      |> press("#brainstorming-canvas", "n")
      |> type("[contenteditable=true]", "The antagonist wants to return a stolen memory.")
      |> assert_has("[data-note-id]:not([data-note-id^='-'])", text: "The antagonist wants to return a stolen memory.")
      |> press("[contenteditable=true]", "Escape")
      |> persisted(2)

    assert {:ok, [contribution]} =
             Ideation.list_ideas(ctx.facilitator, ctx.project.id, ctx.session.id, round_id: round.id)

    assert contribution.body == "<p>The antagonist wants to return a stolen memory.</p>"
    refute contribution.late_contribution
    assert {:ok, earlier} = Ideation.get_idea(ctx.facilitator, ctx.project.id, ctx.session.id, existing.id)
    assert earlier.round_id == nil
    assert {:ok, current} = Ideation.get_session(ctx.facilitator, ctx.project.id, ctx.session.id)
    assert current.configuration == ctx.session.configuration

    browser
    |> visit(board_path(ctx))
    |> assert_has("#brainstorming-active-round", text: "Round 1")
    |> assert_has("#canvas-note-#{existing.id}:not([data-round-id])")
    |> assert_has("#canvas-note-#{contribution.id}[data-round-id='#{round.id}']")
    |> assert_has(".canvas-note", count: 2)
  end

  test "correct or cancel a prepared question without starting a round", %{conn: conn} do
    ctx = ideation_fixture()
    {:ok, _} = Ideation.create_round(ctx.facilitator, ctx.project.id, ctx.session.id, 1, %{prompt: "A typo"})
    {:ok, [round]} = Ideation.list_rounds(ctx.facilitator, ctx.project.id, ctx.session.id)
    prompt = "#brainstorming-round-edit-prompt-#{round.id}"

    browser =
      conn
      |> authenticate(ctx.facilitator.user)
      |> visit(board_path(ctx))
      |> assert_has("#brainstorming-canvas")
      |> click("#brainstorming-rounds-trigger")
      |> click("#brainstorming-round-edit-#{round.id}")
      |> press(prompt, "ControlOrMeta+a")
      |> type(prompt, "Which promise changes the story?")
      |> click("#brainstorming-round-save-#{round.id}")
      |> assert_has("#brainstorming-round-#{round.id}", text: "Which promise changes the story?")
      |> click("#brainstorming-round-cancel-#{round.id}:not([disabled])")
      |> assert_has("#brainstorming-round-#{round.id}[data-status=cancelled]")
      |> refute_has("#brainstorming-round-start-#{round.id}")
      |> refute_has("#brainstorming-round-edit-#{round.id}")
      |> refute_has("#brainstorming-active-round")

    assert {:ok, [cancelled]} = Ideation.list_rounds(ctx.viewer, ctx.project.id, ctx.session.id)
    assert cancelled.prompt == "Which promise changes the story?"
    assert cancelled.status == :cancelled
    assert cancelled.started_at == nil
    assert cancelled.closed_at == nil

    browser
    |> click("#brainstorming-rounds-trigger")
    |> assert_has("#brainstorming-canvas")
  end

  test "a round closes in both browsers while private notes remain private and editable", %{conn: conn} = test_context do
    ctx = ideation_fixture()
    assert {:ok, _} = Ideation.set_private_mode(ctx.facilitator, ctx.project.id, ctx.session.id, 1, true)
    assert {:ok, private} = Ideation.get_session(ctx.facilitator, ctx.project.id, ctx.session.id)
    path = board_path(ctx)

    facilitator =
      conn
      |> authenticate(ctx.facilitator.user)
      |> visit(path)
      |> assert_has("#brainstorming-canvas")

    peer_config = test_context |> Map.take(Config.setup_keys()) |> Config.validate!()

    peer =
      peer_config
      |> PhoenixTest.Playwright.Case.new_session(test_context)
      |> authenticate(ctx.peer.user)
      |> visit(path)
      |> assert_has("#brainstorming-canvas")

    facilitator =
      facilitator
      |> click("#brainstorming-rounds-trigger")
      |> type("#brainstorming-round-prompt", "What would make the river forget?")
      |> click("#brainstorming-round-create:not([disabled])")
      |> assert_has("[id^='brainstorming-round-'][data-status=planned]", text: "What would make the river forget?")

    assert {:ok, [round]} = Ideation.list_rounds(ctx.facilitator, ctx.project.id, ctx.session.id)

    facilitator =
      facilitator
      |> click("#brainstorming-round-start-#{round.id}:not([disabled])")
      |> assert_has("#brainstorming-round-#{round.id}[data-status=active]")

    peer =
      peer
      |> assert_has("#brainstorming-active-round", text: "Round 1")
      |> click("#brainstorming-rounds-trigger")
      |> assert_has("#brainstorming-round-#{round.id}[data-status=active]", text: "What would make the river forget?")
      |> refute_has("#brainstorming-round-create")
      |> refute_has("#brainstorming-round-close-#{round.id}")
      |> click("#brainstorming-rounds-trigger")
      |> press("#brainstorming-canvas", "n")
      |> type("[contenteditable=true]", "A secret promise could change the river.")
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
      |> assert_has("button[aria-label='End private mode and reveal to everyone']")

    peer =
      peer
      |> refute_has("#brainstorming-active-round")
      |> click("#brainstorming-rounds-trigger")
      |> assert_has("#brainstorming-round-#{round.id}[data-status=closed]")
      |> click("#brainstorming-rounds-trigger")

    selector = "#canvas-note-#{note.id}"
    {:ok, _} = PlaywrightEx.Frame.click(peer.frame_id, selector: selector, clickCount: 2, timeout: 10_000)

    peer
    |> assert_has("#{selector} [contenteditable=true]")
    |> press("#{selector} [contenteditable=true]", "ControlOrMeta+a")
    |> type("#{selector} [contenteditable=true]", "The river remembers the promise even after this round.")
    |> refute_has("#{selector} footer", text: "Unsaved changes")
    |> refute_has("#{selector} footer", text: "Saving…")
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

  test "viewers can consult the round context without preparing or transitioning rounds", %{conn: conn} do
    ctx = ideation_fixture()

    assert {:ok, prepared} =
             Ideation.create_round(ctx.facilitator, ctx.project.id, ctx.session.id, 1, %{
               prompt: "Which memory changes the story?"
             })

    assert {:ok, [round]} = Ideation.list_rounds(ctx.facilitator, ctx.project.id, ctx.session.id)

    assert {:ok, _} =
             Ideation.start_round(ctx.facilitator, ctx.project.id, ctx.session.id, round.id, prepared.revision)

    conn
    |> authenticate(ctx.viewer.user)
    |> visit(board_path(ctx))
    |> assert_has("#brainstorming-active-round", text: "Round 1")
    |> click("#brainstorming-rounds-trigger")
    |> assert_has("#brainstorming-round-#{round.id}[data-status=active]", text: "Which memory changes the story?")
    |> refute_has("#brainstorming-round-prompt")
    |> refute_has("#brainstorming-round-create")
    |> refute_has("#brainstorming-round-start-#{round.id}")
    |> refute_has("#brainstorming-round-close-#{round.id}")
  end

  defp board_path(ctx) do
    project = Repo.preload(ctx.project, :workspace)
    "/workspaces/#{project.workspace.slug}/projects/#{project.slug}/brainstorming/#{ctx.session.id}"
  end

  defp click(browser, selector) do
    {:ok, _} = PlaywrightEx.Frame.click(browser.frame_id, selector: selector, timeout: 10_000)
    browser
  end

  defp persisted(browser, count) do
    assert_has(browser, "#brainstorming-workspace[aria-busy=false][data-persisted-note-count='#{count}']")
  end
end
