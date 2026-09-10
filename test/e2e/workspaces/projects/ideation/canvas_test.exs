defmodule StoryarnWeb.E2E.IdeationCanvasTest do
  use PhoenixTest.Playwright.Case, async: false

  import PhoenixTest.Playwright, only: [press: 3, type: 3, evaluate: 2, evaluate: 4]
  import Storyarn.IdeationFixtures
  import StoryarnWeb.E2EHelpers

  alias PhoenixTest.Playwright.Config
  alias Storyarn.Ideation
  alias Storyarn.Repo

  @moduletag :e2e

  test "creating consecutive sessions from the sticky sidebar keeps its controls usable", %{conn: conn} do
    ctx = ideation_fixture()
    project = Repo.preload(ctx.project, :workspace)
    base = "/workspaces/#{project.workspace.slug}/projects/#{project.slug}/brainstorming"

    browser =
      conn
      |> authenticate(ctx.author.user)
      |> visit("#{base}/#{ctx.session.id}")
      |> assert_has("#brainstorming-canvas")

    {:ok, _} = PlaywrightEx.Frame.click(browser.frame_id, selector: "#new-brainstorming-session", timeout: 10_000)

    browser =
      browser
      |> assert_has("a[aria-current=page]", text: "Untitled session")
      |> assert_has("#new-brainstorming-session:not([disabled])")

    {:ok, sessions} = Ideation.list_sessions(ctx.author, ctx.project.id)
    assert length(sessions) == 2
    created = Enum.find(sessions, &(&1.id != ctx.session.id))

    browser = assert_path(browser, "#{base}/#{created.id}")
    {:ok, _} = PlaywrightEx.Frame.click(browser.frame_id, selector: "#new-brainstorming-session", timeout: 10_000)

    browser
    |> refute_has("a[href='#{base}/#{created.id}'][aria-current=page]")
    |> assert_has("a[aria-current=page]", text: "Untitled session")
    |> assert_has("#new-brainstorming-session:not([disabled])")
    |> assert_has("#brainstorming-canvas")

    assert {:ok, sessions} = Ideation.list_sessions(ctx.author, ctx.project.id)
    assert length(sessions) == 3
  end

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

  test "text undo survives the first autosave without replacing or duplicating its note", %{conn: conn} do
    ctx = ideation_fixture()
    browser = conn |> open_board(ctx) |> press("#brainstorming-canvas", "n")
    browser = evaluate(browser, "window.firstNoteEditor = document.querySelector('[contenteditable=true]')")

    browser =
      browser
      |> type("[contenteditable=true]", "One promise changes the city.")
      |> persisted(1)

    {:ok, [note]} = Ideation.list_ideas(ctx.author, ctx.project.id, ctx.session.id)
    assert note.body == "<p>One promise changes the city.</p>"
    selector = "#canvas-note-#{note.id}"

    browser
    |> assert_has("#{selector} [contenteditable=true]", text: "One promise changes the city.")
    |> press("#{selector} [contenteditable=true]", "ControlOrMeta+z")
    |> assert_has("#{selector} [contenteditable=true] p.is-editor-empty")
    |> assert_has(".canvas-note", count: 1)
    |> evaluate(
      "document.querySelector('[contenteditable=true]') === window.firstNoteEditor",
      [],
      &assert(&1 == true)
    )
    |> press("#{selector} [contenteditable=true]", "ControlOrMeta+Shift+z")
    |> assert_has("#{selector} [contenteditable=true]", text: "One promise changes the city.")
    |> assert_has(".canvas-note", count: 1)
  end

  test "duplicate persists without provenance and delete can undo and redo the same note", %{conn: conn} do
    ctx = ideation_fixture()
    original = canvas_note(ctx, "A door remembers its last visitor.", 0)
    browser = conn |> open_board(ctx) |> select_note(original.id)
    browser = browser |> press("#brainstorming-canvas", "ControlOrMeta+d") |> persisted(2)
    {:ok, notes} = Ideation.list_ideas(ctx.author, ctx.project.id, ctx.session.id)
    copy = Enum.find(notes, &(&1.id != original.id))
    assert copy.body == original.body
    assert copy.source_idea_id == nil
    assert copy.source_revision == nil
    browser = browser |> visit(board_path(ctx)) |> assert_has(".canvas-note", count: 2) |> select_note(copy.id)
    selector = "#canvas-note-#{copy.id}"

    browser =
      browser
      |> press("#brainstorming-canvas", "Delete")
      |> refute_has(selector)
      |> persisted(1)
      |> press("#brainstorming-canvas", "ControlOrMeta+z")
      |> assert_has(selector, text: "A door remembers its last visitor.")
      |> persisted(2)
      |> press("#brainstorming-canvas", "ControlOrMeta+Shift+z")
      |> refute_has(selector)
      |> persisted(1)

    assert_deleted(ctx, copy.id)
    browser |> visit(board_path(ctx)) |> assert_has("#canvas-note-#{original.id}") |> refute_has(selector)
  end

  test "native copy cut and paste operate on selected notes and external text becomes a note", %{conn: conn} do
    ctx = ideation_fixture()
    original = canvas_note(ctx, "A map drawn from memories.", 0)
    browser = conn |> open_board(ctx) |> select_note(original.id)

    browser =
      browser
      |> press("#brainstorming-canvas", "ControlOrMeta+c")
      |> press("#brainstorming-canvas", "ControlOrMeta+v")
      |> persisted(2)
      |> assert_has(".canvas-note", count: 2)

    {:ok, notes} = Ideation.list_ideas(ctx.author, ctx.project.id, ctx.session.id)
    copy = Enum.find(notes, &(&1.id != original.id))
    assert copy.source_idea_id == nil

    browser =
      browser
      |> press("#brainstorming-canvas", "ControlOrMeta+x")
      |> refute_has("#canvas-note-#{copy.id}")
      |> persisted(1)
      |> press("#brainstorming-canvas", "ControlOrMeta+v")
      |> persisted(2)
      |> assert_has(".canvas-note", count: 2)
      |> paste_external("The bridge forgets every name.")
      |> persisted(3)
      |> assert_has(".canvas-note", text: "The bridge forgets every name.")

    assert_deleted(ctx, copy.id)
    browser |> visit(board_path(ctx)) |> assert_has(".canvas-note", count: 3)
  end

  test "select all selects the canvas notes and Delete removes only the current author's notes", %{conn: conn} do
    ctx = ideation_fixture()
    first = canvas_note(ctx, "First own idea", -340)
    second = canvas_note(ctx, "Second own idea", 0)
    peer = canvas_note(ctx, "Another author's idea", 340, ctx.peer)

    browser =
      conn
      |> open_board(ctx)
      |> assert_has(".canvas-note", count: 3)
      |> press("#brainstorming-canvas", "ControlOrMeta+a")
      |> assert_has(".canvas-note[aria-selected=true]", count: 3)
      |> press("#brainstorming-canvas", "Delete")
      |> persisted(1)
      |> assert_has(".canvas-note", count: 1)
      |> assert_has("#canvas-note-#{peer.id}")

    assert_deleted(ctx, first.id)
    assert_deleted(ctx, second.id)
    browser |> visit(board_path(ctx)) |> assert_has(".canvas-note", count: 1) |> assert_has("#canvas-note-#{peer.id}")
  end

  test "select all clipboard and Delete inside the editor affect text without changing the cards", %{conn: conn} do
    ctx = ideation_fixture()
    own = canvas_note(ctx, "Keep this text inside its note.", 0)
    peer = canvas_note(ctx, "The other note stays unchanged.", 340, ctx.peer)
    browser = open_board(conn, ctx)
    selector = "#canvas-note-#{own.id}"
    {:ok, _} = PlaywrightEx.Frame.click(browser.frame_id, selector: selector, clickCount: 2, timeout: 10_000)
    editor = "#{selector} [contenteditable=true]"

    browser =
      browser
      |> assert_has(editor)
      |> press(editor, "ControlOrMeta+a")
      |> press(editor, "ControlOrMeta+c")
      |> press(editor, "Delete")
      |> assert_has("#{editor} p.is-editor-empty")
      |> assert_has(".canvas-note", count: 2)
      |> press(editor, "ControlOrMeta+v")
      |> assert_has(editor, text: "Keep this text inside its note.")
      |> press(editor, "ControlOrMeta+a")
      |> press(editor, "ControlOrMeta+x")
      |> assert_has("#{editor} p.is-editor-empty")
      |> assert_has(".canvas-note", count: 2)
      |> press(editor, "ControlOrMeta+v")
      |> assert_has(editor, text: "Keep this text inside its note.")
      |> assert_has("#canvas-note-#{peer.id}", text: "The other note stays unchanged.")
      |> assert_has(".canvas-note[aria-selected=true]", count: 1)
      |> press(editor, "Escape")
      |> persisted(2)

    browser
    |> assert_has(selector, text: "Keep this text inside its note.")
    |> assert_has(".canvas-note", count: 2)
  end

  defp board_path(ctx) do
    project = Repo.preload(ctx.project, :workspace)
    "/workspaces/#{project.workspace.slug}/projects/#{project.slug}/brainstorming/#{ctx.session.id}"
  end

  defp open_board(conn, ctx) do
    conn |> authenticate(ctx.author.user) |> visit(board_path(ctx)) |> assert_has("#brainstorming-canvas")
  end

  defp canvas_note(ctx, body, x, actor \\ nil) do
    {:ok, note} =
      Ideation.create_canvas_idea(
        actor || ctx.author,
        ctx.project.id,
        ctx.session.id,
        idea_attrs(%{body: "<p>#{body}</p>", canvas: %{"x" => x, "y" => 0, "width" => 280, "color" => "yellow"}})
      )

    note
  end

  defp select_note(browser, id) do
    # A single click selects the note without opening the inline editor.
    {:ok, _} = PlaywrightEx.Frame.click(browser.frame_id, selector: "#canvas-note-#{id} .note-content", timeout: 10_000)
    assert_has(browser, "#canvas-note-#{id}[aria-selected=true]")
  end

  defp persisted(browser, count) do
    assert_has(browser, "#brainstorming-workspace[aria-busy=false][data-persisted-note-count='#{count}']")
  end

  defp paste_external(browser, text) do
    evaluate(
      browser,
      """
      text => {
        const data = new DataTransfer();
        data.setData("text/plain", text);
        document.querySelector("#brainstorming-canvas").dispatchEvent(
          new ClipboardEvent("paste", { clipboardData: data, bubbles: true, cancelable: true })
        );
      }
      """,
      [is_function: true, arg: text],
      fn _ -> :ok end
    )
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
