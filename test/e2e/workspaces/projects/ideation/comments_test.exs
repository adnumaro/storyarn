defmodule StoryarnWeb.E2E.IdeationCommentsTest do
  use PhoenixTest.Playwright.Case, async: false

  import Storyarn.IdeationFixtures
  import StoryarnWeb.E2EHelpers

  alias Storyarn.Ideation
  alias Storyarn.Projects
  alias Storyarn.Repo

  @moduletag :e2e

  test "session discussion supports replies, resolution and a durable link", %{conn: conn} do
    ctx = ideation_fixture()
    project = Repo.preload(ctx.project, :workspace)
    path = "/workspaces/#{project.workspace.slug}/projects/#{project.slug}/brainstorming/#{ctx.session.id}"

    session =
      conn
      |> authenticate(ctx.author.user)
      |> visit(path)
      |> assert_has("#brainstorming-canvas", timeout: 20_000)
      |> assert_has("#brainstorming-session-comments", timeout: 20_000)
      |> click("#brainstorming-session-comments")
      |> fill_in("#brainstorming-comment-body", "New thread", with: "Should the ending stay open?")
      |> click("#brainstorming-comment-send")
      |> assert_has("#brainstorming-comments-content", text: "Should the ending stay open?")
      |> fill_in("#brainstorming-comment-body", "Reply", with: "Yes, keep the mystery.")
      |> click("#brainstorming-comment-send")
      |> assert_has("#brainstorming-comments-content", text: "Yes, keep the mystery.")
      |> click("#brainstorming-comment-status")
      |> assert_has("#brainstorming-comment-status", text: "Reopen")

    {:ok, %{threads: [thread]}} = Projects.list_ideation_comment_threads(ctx.author, project.id, ctx.session.id)

    session
    |> visit(path <> "?thread=#{thread.id}")
    |> assert_has("#brainstorming-comments-content", text: "Yes, keep the mystery.", timeout: 20_000)
    |> click("#brainstorming-comment-status")
    |> assert_has("#brainstorming-comment-status", text: "Resolve")
  end

  test "shared idea discussion disappears when the session switches to private mode", %{conn: conn} do
    ctx = ideation_fixture()
    idea = ctx |> idea_fixture(%{body: "<p>Shared alternative</p>"}) |> then(&publish_idea(ctx, &1))
    project = Repo.preload(ctx.project, :workspace)
    path = "/workspaces/#{project.workspace.slug}/projects/#{project.slug}/brainstorming/#{ctx.session.id}"

    browser =
      conn
      |> authenticate(ctx.peer.user)
      |> visit(path)
      |> assert_has("#canvas-note-#{idea.id}", timeout: 20_000)
      |> click("#canvas-note-#{idea.id} .note-content")
      |> click("#brainstorming-idea-comments")
      |> fill_in("#brainstorming-comment-body", "New thread", with: "A shared suggestion")
      |> click("#brainstorming-comment-send")
      |> assert_has("#brainstorming-comments-content", text: "A shared suggestion")

    assert {:ok, %{threads: [_]}} =
             Projects.list_ideation_comment_threads(ctx.peer, project.id, ctx.session.id, idea.id)

    {:ok, _} = Ideation.set_private_mode(ctx.facilitator, project.id, ctx.session.id, ctx.session.revision, true)

    browser
    |> refute_has("#brainstorming-comments-content")
    |> refute_has("#brainstorming-idea-comments")
  end
end
