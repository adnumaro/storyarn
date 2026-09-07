defmodule StoryarnWeb.E2E.IdeationCanvasTest do
  use PhoenixTest.Playwright.Case, async: false

  import PhoenixTest.Playwright, only: [press: 3, type: 3]
  import Storyarn.IdeationFixtures
  import StoryarnWeb.E2EHelpers

  alias PhoenixTest.Playwright.Config
  alias Storyarn.Ideation
  alias Storyarn.Repo

  @moduletag :e2e

  test "write on the canvas without a form, save, reload, and receive another author's contribution", %{conn: conn} do
    ctx = configure_session(ideation_fixture(), %{default_visibility: :shared})
    project = Repo.preload(ctx.project, :workspace)
    path = "/workspaces/#{project.workspace.slug}/projects/#{project.slug}/brainstorming/#{ctx.session.id}"
    browser = conn |> authenticate(ctx.author.user) |> visit(path) |> assert_has("#brainstorming-canvas")

    browser =
      browser
      |> press("#brainstorming-canvas", "n")
      |> type("[contenteditable=true]", "The city remembers every broken promise.")

    browser =
      browser
      |> assert_has("[data-note-id]:not([data-note-id^='-'])", text: "The city remembers every broken promise.")
      |> refute_has("[role=dialog]")

    browser =
      browser
      |> press("[contenteditable=true]", "Escape")
      |> assert_has("#brainstorming-workspace[aria-busy=false][data-persisted-note-count='1']")
      |> visit(path)
      |> assert_has(".canvas-note", text: "The city remembers every broken promise.")

    {:ok, _} =
      Ideation.create_idea(
        ctx.peer,
        project.id,
        ctx.session.id,
        idea_attrs(%{
          configuration_version: ctx.session.configuration_version,
          body: "<p>The archivist can erase one memory.</p>",
          visibility: :shared,
          canvas: %{"x" => 400, "y" => 200, "width" => 280, "color" => "blue"}
        })
      )

    browser |> assert_has(".canvas-note", text: "The archivist can erase one memory.") |> refute_has("[role=dialog]")
  end

  test "double-click edits the existing note, Delete removes it, and reload preserves both changes", %{conn: conn} do
    ctx = ideation_fixture()

    original =
      idea_fixture(ctx, %{
        body: "<p>Original idea</p>",
        canvas: %{"x" => 0, "y" => 0, "width" => 280, "color" => "yellow"}
      })

    project = Repo.preload(ctx.project, :workspace)
    path = "/workspaces/#{project.workspace.slug}/projects/#{project.slug}/brainstorming/#{ctx.session.id}"
    selector = "#canvas-note-#{original.id}"
    browser = conn |> authenticate(ctx.author.user) |> visit(path) |> assert_has(selector, text: "Original idea")
    {:ok, _} = PlaywrightEx.Frame.click(browser.frame_id, selector: selector, clickCount: 2, timeout: 10_000)
    browser = browser |> assert_has("#{selector} [contenteditable=true]") |> assert_has(".canvas-note", count: 1)

    browser =
      browser
      |> press("#{selector} [contenteditable=true]", "ControlOrMeta+a")
      |> type("#{selector} [contenteditable=true]", "Edited in the same note")
      |> press("#{selector} [contenteditable=true]", "Escape")

    browser = browser |> assert_has(selector, text: "Edited in the same note") |> assert_has(".canvas-note", count: 1)
    browser = browser |> assert_has("#{selector}[aria-selected=true]") |> refute_has("#{selector} [contenteditable=true]")
    browser = browser |> press(selector, "Delete") |> refute_has(selector)
    assert_deleted(ctx, original.id)
    # Reload only after the server projection has caught up with the optimistic
    # deletion, so navigation cannot kill a reader using the test transaction.
    browser
    |> assert_has("#brainstorming-workspace[aria-busy=false][data-persisted-note-count='0']")
    |> visit(path)
    |> assert_has("#brainstorming-canvas")
    |> refute_has(selector)

    assert {:error, :not_found} = Ideation.get_idea(ctx.author, project.id, ctx.session.id, original.id)
    saved = Repo.get!(Storyarn.Ideation.Ideas.Idea, original.id)
    revision = Repo.get_by!(Storyarn.Ideation.Ideas.Revision, idea_id: saved.id, number: saved.revision)
    assert revision.body =~ "Edited in the same note"
    assert saved.state == :active
    assert saved.deleted_at
    {:ok, all} = Ideation.list_ideas(ctx.author, project.id, ctx.session.id, state: :all)
    assert all == []
  end

  test "the trash action cancels a new unsaved note", %{conn: conn} do
    ctx = ideation_fixture()
    project = Repo.preload(ctx.project, :workspace)
    path = "/workspaces/#{project.workspace.slug}/projects/#{project.slug}/brainstorming/#{ctx.session.id}"

    browser =
      conn
      |> authenticate(ctx.author.user)
      |> visit(path)
      |> assert_has("#brainstorming-canvas")
      |> press("#brainstorming-canvas", "n")
      |> assert_has(".canvas-note", count: 1)

    {:ok, _} = PlaywrightEx.Frame.click(browser.frame_id, selector: "button[aria-label='Delete note']", timeout: 10_000)
    refute_has(browser, ".canvas-note")
    {:ok, []} = Ideation.list_ideas(ctx.author, project.id, ctx.session.id, state: :all)
  end

  test "facilitator changes visibility for two browsers and edits are shared without individual publication",
       %{conn: conn} = test_context do
    ctx = ideation_fixture()
    project = Repo.preload(ctx.project, :workspace)
    path = "/workspaces/#{project.workspace.slug}/projects/#{project.slug}/brainstorming/#{ctx.session.id}"

    {:ok, prompt} =
      Ideation.create_canvas_idea(
        ctx.facilitator,
        project.id,
        ctx.session.id,
        idea_attrs(%{
          body: "<p>What does the city remember?</p>",
          canvas: %{"x" => -350, "y" => 0, "width" => 280, "color" => "yellow"}
        })
      )

    facilitator = conn |> authenticate(ctx.facilitator.user) |> visit(path) |> assert_has("#canvas-note-#{prompt.id}")
    peer_config = test_context |> Map.take(Config.setup_keys()) |> Config.validate!()

    peer =
      peer_config
      |> PhoenixTest.Playwright.Case.new_session(test_context)
      |> authenticate(ctx.peer.user)
      |> visit(path)
      |> assert_has("#canvas-note-#{prompt.id}")

    assert_has(peer, "button[aria-label='Start private mode for everyone'][disabled]")

    {:ok, _} =
      PlaywrightEx.Frame.click(facilitator.frame_id,
        selector: "button[aria-label='Start private mode for everyone']",
        timeout: 10_000
      )

    facilitator = assert_has(facilitator, "button[aria-label='End private mode and reveal to everyone']")

    peer =
      peer
      |> refute_has("#canvas-note-#{prompt.id}")
      |> press("#brainstorming-canvas", "n")
      |> type("[contenteditable=true]", "A forgotten promise changed the river.")
      |> assert_has("[data-note-id]:not([data-note-id^='-'])", text: "A forgotten promise changed the river.")

    refute_has(facilitator, ".canvas-note", text: "A forgotten promise changed the river.")
    {:ok, [own]} = Ideation.list_ideas(ctx.peer, project.id, ctx.session.id)

    {:ok, _} =
      PlaywrightEx.Frame.click(facilitator.frame_id,
        selector: "button[aria-label='End private mode and reveal to everyone']",
        timeout: 10_000
      )

    facilitator = assert_has(facilitator, ".canvas-note", text: "A forgotten promise changed the river.")
    peer = peer |> press("[contenteditable=true]", "Escape") |> assert_has("#canvas-note-#{prompt.id}")
    {:ok, _} = PlaywrightEx.Frame.click(peer.frame_id, selector: "#canvas-note-#{own.id}", clickCount: 2, timeout: 10_000)

    peer
    |> press("[contenteditable=true]", "ControlOrMeta+a")
    |> type("[contenteditable=true]", "The river remembers a broken promise.")

    facilitator
    |> assert_has("#canvas-note-#{own.id}", text: "The river remembers a broken promise.")
    |> assert_has(".canvas-note", count: 2)

    refute_has(peer, "[role=dialog]")
  end

  defp assert_deleted(ctx, id, attempts \\ 100)

  defp assert_deleted(ctx, id, attempts) when attempts > 1 do
    case Ideation.get_idea(ctx.author, ctx.project.id, ctx.session.id, id) do
      {:error, :not_found} ->
        :ok

      _ ->
        Process.sleep(20)
        assert_deleted(ctx, id, attempts - 1)
    end
  end

  defp assert_deleted(ctx, id, 1),
    do: assert({:error, :not_found} = Ideation.get_idea(ctx.author, ctx.project.id, ctx.session.id, id))
end
