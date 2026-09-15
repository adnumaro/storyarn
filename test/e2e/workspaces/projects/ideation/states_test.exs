defmodule StoryarnWeb.E2E.IdeationStatesTest do
  use PhoenixTest.Playwright.Case, async: false

  import Storyarn.IdeationFixtures
  import StoryarnWeb.E2EHelpers

  alias PhoenixTest.Playwright.Config
  alias Storyarn.Ideation
  alias Storyarn.Repo

  @moduletag :e2e

  test "the author parks, discards and brings back a note from its context menu, and the tree counts it",
       %{conn: conn} do
    ctx = ideation_fixture()
    note = idea_fixture(ctx, %{visibility: :shared, canvas: %{"x" => 0, "y" => 60}})
    {ctx, _second} = new_round(ctx, %{prompt: "Second question"})
    selector = "#canvas-note-#{note.id}"

    conn
    |> authenticate(ctx.author.user)
    |> visit(board_path(ctx))
    |> assert_has(selector)
    |> refute_has("#brainstorming-tree-later-#{ctx.session.id}")
    |> right_click("#{selector} .note-content")
    |> click_item("#brainstorming-note-context-park")
    |> assert_has("#{selector}[data-note-state=parked] .note-tab", text: "For later")
    |> assert_has("#brainstorming-tree-later-#{ctx.session.id}", text: "1")
    |> right_click("#{selector} .note-content")
    |> click_item("#brainstorming-note-context-discard")
    |> assert_has("#{selector}[data-note-state=discarded] .note-tab", text: "Discarded")
    |> refute_has("#brainstorming-tree-later-#{ctx.session.id}")
    |> right_click("#{selector} .note-content")
    |> click_item("#brainstorming-note-context-restore")
    |> assert_has("#{selector}[data-note-state=active]")
    |> refute_has("#{selector} .note-tab")
    |> assert_has("#brainstorming-workspace[aria-busy=false]")

    eventually(fn ->
      assert {:ok, %{state: :active}} = Ideation.get_idea(ctx.author, ctx.project.id, ctx.session.id, note.id)
    end)
  end

  test "bringing a note into the active round copies it under the band for everyone and empties For later",
       %{conn: conn} = context do
    ctx = ideation_fixture()

    parked =
      idea_fixture(ctx, %{
        visibility: :shared,
        state: :parked,
        body: "<p>Keep the light</p>",
        canvas: %{"x" => 0, "y" => 60}
      })

    {ctx, second} = new_round(ctx, %{prompt: "Second question"})
    peer_config = context |> Map.take(Config.setup_keys()) |> Config.validate!()

    peer =
      peer_config
      |> PhoenixTest.Playwright.Case.new_session(context)
      |> authenticate(ctx.peer.user)
      |> visit(board_path(ctx))
      |> assert_has("#canvas-note-#{parked.id}")

    author =
      conn
      |> authenticate(ctx.author.user)
      |> visit(board_path(ctx))
      |> assert_has("#brainstorming-tree-later-#{ctx.session.id}", text: "1")
      |> right_click("#canvas-note-#{parked.id} .note-content")
      |> click_item("#brainstorming-note-context-bring")
      |> assert_has(".canvas-note[data-round-id='#{second.id}']", text: "Keep the light")
      |> refute_has("#brainstorming-tree-later-#{ctx.session.id}")
      |> assert_has("#brainstorming-workspace[aria-busy=false]")

    copy =
      eventually(fn ->
        assert {:ok, ideas} = Ideation.list_ideas(ctx.author, ctx.project.id, ctx.session.id, state: :all)
        assert [copy] = Enum.filter(ideas, &(&1.source_idea_id == parked.id))
        assert copy.round_id == second.id
        copy
      end)

    assert_has(peer, "#canvas-note-#{copy.id}", text: "Keep the light")
    assert_has(author, "#canvas-note-#{parked.id}[data-note-state=parked]")
  end

  test "the For later list brings a note into the active round and drops it from the list", %{conn: conn} do
    ctx = ideation_fixture()

    parked =
      idea_fixture(ctx, %{
        visibility: :shared,
        state: :parked,
        body: "<p>Later</p>",
        canvas: %{"x" => 0, "y" => 60}
      })

    {ctx, second} = new_round(ctx, %{prompt: "Second question"})

    conn
    |> authenticate(ctx.author.user)
    |> visit("#{board_path(ctx)}?view=later")
    |> assert_has("#canvas-list-note-#{parked.id}", text: "For later")
    |> click_item("#canvas-list-bring-#{parked.id}")
    |> refute_has("#canvas-list-note-#{parked.id}")
    |> assert_has("#brainstorming-workspace[aria-busy=false]")

    eventually(fn ->
      assert {:ok, ideas} = Ideation.list_ideas(ctx.author, ctx.project.id, ctx.session.id, state: :all)
      assert Enum.any?(ideas, &(&1.source_idea_id == parked.id and &1.round_id == second.id))
    end)
  end

  # A state change or a copy reaches the database a moment after the browser shows it.
  defp eventually(assertion, attempts \\ 200) do
    assertion.()
  rescue
    error in [ExUnit.AssertionError, MatchError] ->
      if attempts > 1 do
        Process.sleep(25)
        eventually(assertion, attempts - 1)
      else
        reraise error, __STACKTRACE__
      end
  end

  # Menu items and list buttons are plain elements, outside the library's click/2 scope.
  defp click_item(browser, selector) do
    {:ok, _} = PlaywrightEx.Frame.click(browser.frame_id, selector: selector, timeout: 10_000)
    browser
  end

  defp board_path(ctx) do
    project = Repo.preload(ctx.project, :workspace)
    "/workspaces/#{project.workspace.slug}/projects/#{project.slug}/brainstorming/#{ctx.session.id}"
  end
end
