defmodule StoryarnWeb.E2E.SheetCommentsTest do
  use PhoenixTest.Playwright.Case, async: false

  import Storyarn.AccountsFixtures
  import Storyarn.ProjectsFixtures
  import Storyarn.SheetsFixtures
  import StoryarnWeb.E2EHelpers

  alias PlaywrightEx.Page
  alias Storyarn.Projects
  alias Storyarn.Repo
  alias Storyarn.Sheets

  @moduletag :e2e

  test "a Sheet discussion moves from its header across the canvas and keeps its deep link", %{
    conn: conn
  } do
    user = user_fixture()
    project = user |> project_fixture() |> Repo.preload(:workspace)
    sheet = sheet_fixture(project, %{name: "Character review"})
    block = block_fixture(sheet, %{config: %{"label" => "Motivation", "placeholder" => ""}})
    path = "/workspaces/#{project.workspace.slug}/projects/#{project.slug}/sheets/#{sheet.id}"
    feedback = "Explain how this Sheet changes after the second act."
    surface_selector = "[data-sheet-comment-surface='true']"
    block_selector = "[data-sheet-block-id='#{block.id}']"

    session =
      conn
      |> authenticate(user)
      |> visit(path)
      |> assert_has("h1", text: "Character review", timeout: 20_000)
      |> assert_has(block_selector, timeout: 20_000)
      |> assert_has("[data-testid='sheet-canvas-comments']", timeout: 20_000)
      |> right_click_at(surface_selector, 32, 32)
      |> assert_has("#sheet-comment-context-menu")
      |> click("#sheet-comment-context-add")
      |> assert_has("#sheet-comment-draft-pin")
      |> click("#sheet-comment-magnetism-toggle")
      |> assert_has("#sheet-comment-magnetism-toggle[aria-pressed=false]")
      |> fill_in("#sheet-comment-body", "New thread", with: feedback)
      |> drag_pin("#sheet-comment-draft-pin", 35, 180)
      |> assert_has("#sheet-comment-body", value: feedback)
      |> reload_page()
      |> assert_has("#sheet-comment-draft-pin", timeout: 20_000)
      |> assert_has("#sheet-comment-body", value: feedback)
      |> click("#sheet-comment-send")
      |> assert_has("#sheet-comment-popover", text: feedback)

    scope = user_scope_fixture(user)
    assert {:ok, [thread]} = Projects.list_sheet_comment_pins(scope, project.id, sheet.id)
    assert thread.source.type == "sheet_canvas"
    assert thread.source.sheet_id == sheet.id
    assert thread.source.id == sheet.id
    assert thread.position.x >= 0 and thread.position.x <= 100
    assert thread.position.y >= 0 and thread.position.y <= 10_000_000

    initial_position = thread.position

    session =
      session
      |> reload_page()
      |> refute_has("#sheet-comment-popover")
      |> assert_has("#sheet-comment-pin-#{thread.id}", timeout: 20_000)
      |> click("#sheet-comment-magnetism-toggle")
      |> assert_has("#sheet-comment-magnetism-toggle[aria-pressed=false]")
      |> drag_pin("#sheet-comment-pin-#{thread.id}", 45, 60)
      |> assert_has("#sheet-comment-pin-#{thread.id}[aria-busy=false]")
      |> hover_pin("#sheet-comment-magnetism-toggle")
      |> hover_pin("#sheet-comment-pin-#{thread.id}")
      |> assert_has("#sheet-comment-preview", text: feedback)
      |> click("#sheet-comment-pin-#{thread.id}")
      |> assert_has("#sheet-comment-popover", text: feedback)

    assert {:ok, [moved]} = Projects.list_sheet_comment_pins(scope, project.id, sheet.id)
    assert moved.position.x > initial_position.x
    assert moved.position.y > initial_position.y

    session
    |> visit(path <> "?thread=#{thread.id}")
    |> assert_has("#sheet-comment-popover", text: feedback, timeout: 20_000)
    |> assert_has("#sheet-comment-pin-#{thread.id}[aria-expanded='true']")
  end

  test "a draft moves between cover, header and title without losing its text or Sheet ownership", %{conn: conn} do
    user = user_fixture()
    scope = user_scope_fixture(user)
    project = user |> project_fixture() |> Repo.preload(:workspace)
    sheet = sheet_fixture(project, %{name: "The character's public identity"})
    path = sheet_path(project, sheet)
    feedback = "Does this name fit the identity established by the cover?"
    draft = "#sheet-comment-draft-pin"

    session =
      conn
      |> authenticate(user)
      |> visit(path)
      |> assert_has("[data-sheet-comment-region='title']", timeout: 20_000)
      |> right_click_at("[data-sheet-comment-surface=true]", 32, 32)
      |> click("#sheet-comment-context-add")
      |> assert_has("#{draft}[aria-busy=false]")
      |> assert_has("#sheet-comment-magnetism-toggle[aria-pressed=true]")
      |> fill_in("#sheet-comment-body", "New thread", with: feedback)

    session =
      Enum.reduce(
        [{"cover", "Cover", 0.5, 0.5}, {"header", "Header", 0.04, 0.75}, {"title", "Title", 0.5, 0.5}],
        session,
        fn {region, label, x, y}, session ->
          session = drag_pin_over(session, draft, "[data-sheet-comment-region='#{region}']", x, y)

          # The title is nested inside the previously selected header; cycle to the more specific target.
          session = if region == "title", do: press(session, draft, "]"), else: session

          session
          |> assert_has("#sheet-comment-snap-preview", text: label)
          |> release_pin()
          |> assert_has("#{draft}[aria-busy=false]")
          |> assert_has("#sheet-comment-body", value: feedback)
        end
      )

    session =
      session
      |> reload_page()
      |> assert_has("#{draft}[aria-busy=false]", timeout: 20_000)
      |> assert_has("#sheet-comment-body", value: feedback)
      |> click("#sheet-comment-send")
      |> assert_has("#sheet-comment-popover", text: feedback)
      |> assert_has("#sheet-comment-context", text: "Title")

    assert {:ok, [thread]} = Projects.list_sheet_comment_pins(scope, project.id, sheet.id)
    assert thread.source.type == "sheet_canvas"
    assert thread.source.id == sheet.id
    assert thread.context.type == "sheet_title"
    assert thread.context.id == to_string(sheet.id)
    assert thread.context.status == "available"
    assert thread.message_count == 1

    session
    |> visit(path <> "?thread=#{thread.id}")
    |> assert_has("#sheet-comment-pin-#{thread.id}[aria-expanded=true]", timeout: 20_000)
    |> assert_has("#sheet-comment-context", text: "Title")
    |> assert_has("#sheet-comment-popover", text: feedback)
  end

  test "a pin distinguishes a block from its three-block row and its discussion survives dissolving the row",
       %{conn: conn} do
    user = user_fixture()
    scope = user_scope_fixture(user)
    project = user |> project_fixture() |> Repo.preload(:workspace)
    sheet = sheet_fixture(project, %{name: "Character relationships"})

    blocks =
      for label <- ["Allegiance", "Motivation", "Conflict"] do
        block_fixture(sheet, %{config: %{"label" => label, "placeholder" => ""}})
      end

    [_, middle, _] = blocks
    assert {:ok, group_id} = Sheets.create_column_group(sheet.id, Enum.map(blocks, & &1.id))
    feedback = "These three fields should tell one consistent story."
    created = create_free_comment(scope, project, sheet, feedback)
    thread_id = created.thread.id
    pin = "#sheet-comment-pin-#{thread_id}"
    path = sheet_path(project, sheet)

    session =
      conn
      |> authenticate(user)
      |> visit(path)
      |> assert_has("#{pin}[aria-busy=false]", timeout: 20_000)
      |> assert_has("[data-sheet-comment-row='#{group_id}'] [data-sheet-block-id]", count: 3)
      |> drag_pin_over(pin, "[data-sheet-block-id='#{middle.id}']")
      |> assert_has("#sheet-comment-snap-preview", text: "Motivation")

    assert {:ok, previewing} = Projects.get_comment_thread(scope, project.id, thread_id)
    assert previewing.thread.position == created.thread.position
    assert previewing.thread.revision == created.thread.revision
    assert is_nil(previewing.thread.context)

    session =
      session
      |> release_pin()
      |> assert_has("#{pin}[aria-busy=false]")
      |> click(pin)
      |> assert_has("#sheet-comment-context", text: "Motivation")

    assert {:ok, block_context} = Projects.get_comment_thread(scope, project.id, thread_id)
    assert block_context.thread.context.type == "sheet_block"
    assert block_context.thread.context.id == to_string(middle.id)

    session =
      session
      |> click("#sheet-comment-popover-close")
      |> press(pin, "ArrowRight")
      |> assert_has("#sheet-comment-snap-preview", text: "Motivation")
      |> press(pin, "]")
      |> assert_has("#sheet-comment-snap-preview", text: "Row of 3 blocks")
      |> press(pin, "Enter")
      |> assert_has("#{pin}[aria-busy=false]")
      |> click(pin)
      |> assert_has("#sheet-comment-context", text: "Row of 3 blocks")

    assert {:ok, row_context} = Projects.get_comment_thread(scope, project.id, thread_id)
    assert row_context.thread.context.type == "sheet_column_group"
    assert row_context.thread.context.id == group_id
    assert row_context.thread.revision == block_context.thread.revision + 1
    assert row_context.thread.source == created.thread.source
    assert row_context.thread.root_message_id == created.thread.root_message_id

    session =
      session
      |> visit(path <> "?thread=#{thread_id}")
      |> assert_has("#{pin}[aria-expanded=true]", timeout: 20_000)
      |> assert_has("#sheet-comment-context", text: "Row of 3 blocks")

    assert {:ok, _blocks} =
             Sheets.reorder_blocks_with_columns(
               sheet.id,
               Enum.map(blocks, &%{id: &1.id, column_group_id: nil, column_index: 0})
             )

    reply = "Keep this discussion open while we reorganize the fields."

    session
    |> reload_page()
    |> assert_has("#{pin}[aria-expanded=true]", timeout: 20_000)
    |> refute_has("[data-sheet-comment-row='#{group_id}']")
    |> assert_has("#sheet-comment-context", text: "Row of 3 blocks")
    |> assert_has("#sheet-comment-context", text: "Context unavailable")
    |> fill_in("#sheet-comment-body", "Reply", with: reply)
    |> click("#sheet-comment-send")
    |> assert_has("#sheet-comment-popover", text: reply)

    assert {:ok, retained} = Projects.get_comment_thread(scope, project.id, thread_id)
    assert retained.thread.source.type == "sheet_canvas"
    assert retained.thread.source.status == "available"
    assert retained.thread.context.id == group_id
    assert retained.thread.context.status == "unavailable"
    assert retained.thread.position == row_context.thread.position
    assert retained.thread.message_count == 2
    assert retained.thread.root_message_id == created.thread.root_message_id
  end

  test "a comment on an inherited block belongs only to the child and survives removal of its context", %{conn: conn} do
    user = user_fixture()
    scope = user_scope_fixture(user)
    project = user |> project_fixture() |> Repo.preload(:workspace)
    parent = sheet_fixture(project, %{name: "Character template"})
    source_block = inheritable_block_fixture(parent, label: "Shared motivation")
    child = child_sheet_fixture(project, parent, %{name: "The guard"})
    sibling = child_sheet_fixture(project, parent, %{name: "The courier"})
    inherited = Enum.find(Sheets.list_blocks(child.id), &(&1.inherited_from_block_id == source_block.id))
    assert inherited
    feedback = "This motivation applies specifically to the guard."
    created = create_free_comment(scope, project, child, feedback)
    thread_id = created.thread.id
    pin = "#sheet-comment-pin-#{thread_id}"

    session =
      conn
      |> authenticate(user)
      |> visit(sheet_path(project, child))
      |> assert_has("#{pin}[aria-busy=false]", timeout: 20_000)
      |> drag_pin_over(pin, "[data-sheet-block-id='#{inherited.id}']")
      |> assert_has("#sheet-comment-snap-preview", text: "Shared motivation")
      |> release_pin()
      |> assert_has("#{pin}[aria-busy=false]")
      |> click(pin)
      |> assert_has("#sheet-comment-context", text: "Shared motivation")

    assert {:ok, attached} = Projects.get_comment_thread(scope, project.id, thread_id)
    assert attached.thread.source.id == child.id
    assert attached.thread.context.type == "sheet_block"
    assert attached.thread.context.id == to_string(inherited.id)
    refute attached.thread.context.id == to_string(source_block.id)
    assert {:ok, []} = Projects.list_sheet_comment_pins(scope, project.id, parent.id)
    assert {:ok, []} = Projects.list_sheet_comment_pins(scope, project.id, sibling.id)

    session =
      session
      |> visit(sheet_path(project, parent))
      |> assert_has("[data-sheet-block-id='#{source_block.id}']", timeout: 20_000)
      |> refute_has(pin)
      |> visit(sheet_path(project, sibling))
      |> assert_has("h1", text: "The courier", timeout: 20_000)
      |> refute_has(pin)

    assert {:ok, _deleted} = Sheets.delete_block(source_block)

    session
    |> visit(sheet_path(project, child) <> "?thread=#{thread_id}")
    |> assert_has("#{pin}[aria-expanded=true]", timeout: 20_000)
    |> assert_has("#sheet-comment-context", text: "Shared motivation")
    |> assert_has("#sheet-comment-context", text: "Context unavailable")
    |> assert_has("#sheet-comment-popover", text: feedback)

    assert {:ok, retained} = Projects.get_comment_thread(scope, project.id, thread_id)
    assert retained.thread.source.id == child.id
    assert retained.thread.context.status == "unavailable"
    assert retained.thread.message_count == 1
  end

  test "free movement detaches context and keeps the pin inside the Sheet when dragged onto the surrounding page",
       %{conn: conn} do
    user = user_fixture()
    scope = user_scope_fixture(user)
    project = user |> project_fixture() |> Repo.preload(:workspace)
    sheet = sheet_fixture(project, %{name: "Whole Sheet review"})
    feedback = "This observation concerns the whole Sheet."
    created = create_free_comment(scope, project, sheet, feedback)
    thread_id = created.thread.id
    pin = "#sheet-comment-pin-#{thread_id}"
    path = sheet_path(project, sheet)

    session =
      conn
      |> authenticate(user)
      |> visit(path)
      |> assert_has("#{pin}[aria-busy=false]", timeout: 20_000)
      |> drag_pin_over(pin, "[data-sheet-comment-region=cover]")
      |> assert_has("#sheet-comment-snap-preview", text: "Cover")
      |> release_pin()
      |> assert_has("#{pin}[aria-busy=false]")
      |> click(pin)
      |> assert_has("#sheet-comment-context", text: "Cover")
      |> click("#sheet-comment-popover-close")
      |> click("#sheet-comment-magnetism-toggle")
      |> assert_has("#sheet-comment-magnetism-toggle[aria-pressed=false]")
      |> press(pin, "ArrowRight")
      |> press(pin, "Enter")
      |> assert_has("#{pin}[aria-busy=false]")
      |> click(pin)
      |> refute_has("#sheet-comment-context")
      |> click("#sheet-comment-popover-close")
      |> drag_pin_over(pin, "[data-sheet-comment-surface=true]", -0.2, 0.5)
      |> assert_has("#sheet-comment-snap-preview", text: "Free position")
      |> release_pin()
      |> assert_has("#{pin}[aria-busy=false]")
      |> assert_pin_inside_surface(pin)

    assert {:ok, detached} = Projects.get_comment_thread(scope, project.id, thread_id)
    assert detached.thread.source == created.thread.source
    assert is_nil(detached.thread.context)
    assert detached.thread.position.x > 0
    assert detached.thread.position.x < 10
    assert detached.thread.message_count == 1

    session
    |> visit(path <> "?thread=#{thread_id}")
    |> assert_has("#{pin}[aria-expanded=true]", timeout: 20_000)
    |> assert_has("#sheet-comment-popover", text: feedback)
    |> refute_has("#sheet-comment-context")
    |> assert_pin_inside_surface(pin)
  end

  defp sheet_path(project, sheet) do
    "/workspaces/#{project.workspace.slug}/projects/#{project.slug}/sheets/#{sheet.id}"
  end

  defp create_free_comment(scope, project, sheet, body) do
    assert {:ok, created} =
             Projects.create_sheet_canvas_comment(scope, project.id, sheet.id, %{
               body: body,
               client_request_id: Ecto.UUID.generate(),
               position: %{x: 10, y: 80}
             })

    created
  end

  defp drag_pin_over(session, pin, target, x \\ 0.5, y \\ 0.5) do
    session
    |> hover_pin(pin)
    |> evaluate("document.querySelector(#{Jason.encode!(target)}).getBoundingClientRect().toJSON()", fn box ->
      {:ok, _} = Page.mouse_down(session.page_id, timeout: 10_000)

      {:ok, _} =
        Page.mouse_move(session.page_id,
          x: box["x"] + box["width"] * x,
          y: box["y"] + box["height"] * y,
          steps: 8,
          timeout: 10_000
        )
    end)
  end

  defp release_pin(session) do
    {:ok, _} = Page.mouse_up(session.page_id, timeout: 10_000)
    session
  end

  defp assert_pin_inside_surface(session, pin) do
    evaluate(
      session,
      """
      (() => {
        const surface = document.querySelector('[data-sheet-comment-surface=true]').getBoundingClientRect();
        const pin = document.querySelector(#{Jason.encode!(pin)}).getBoundingClientRect();
        return {
          left: pin.left - surface.left,
          right: surface.right - pin.right,
          top: pin.top - surface.top,
          bottom: surface.bottom - pin.bottom
        };
      })()
      """,
      fn margins ->
        # Hover and focus enlarge the badge slightly; its center still stays one radius inside the surface.
        assert Enum.all?(margins, fn {_edge, pixels} -> pixels >= -2 end)
      end
    )
  end
end
