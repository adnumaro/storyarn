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
    ctx.peer.user |> Ecto.Changeset.change(display_name: "Review partner") |> Repo.update!()
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
      |> click_button("Mention people")
      |> click_button("Review partner")
      |> click_button("Mention people")
      |> click("#brainstorming-comment-send")
      |> assert_has("#brainstorming-comments-content", text: "Should the ending stay open?")
      |> fill_in("#brainstorming-comment-body", "Reply", with: "Yes, keep the mystery.")
      |> click("#brainstorming-comment-send")
      |> assert_has("#brainstorming-comments-content", text: "Yes, keep the mystery.")
      |> click("#brainstorming-comment-status")
      |> assert_has("#brainstorming-comment-status", text: "Reopen")

    {:ok, %{threads: [thread]}} = Projects.list_ideation_comment_threads(ctx.author, project.id, ctx.session.id)
    assert [%{kind: "comment_mention"}] = Storyarn.Platform.list_notifications(ctx.peer)

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

  test "group discussion offers persistent explicit follow and read state to a viewer", %{conn: conn} do
    ctx = ideation_fixture()
    first = idea_fixture(ctx, %{visibility: :shared})
    second = idea_fixture(ctx, %{visibility: :shared}, ctx.peer)

    {:ok, group} =
      Ideation.create_group(ctx.author, ctx.project.id, ctx.session.id, %{
        request_key: Ecto.UUID.generate(),
        title: "Alternative endings",
        idea_ids: [first.id, second.id],
        canvas: %{x: 100, y: 100, width: 650, height: 450}
      })

    {:ok, detail} =
      Projects.create_ideation_comment(ctx.author, ctx.project.id, ctx.session.id, {:group, group.id}, %{
        body: "Which ending fits the game?",
        client_request_id: Ecto.UUID.generate(),
        mention_user_ids: [ctx.viewer.user.id]
      })

    project = Repo.preload(ctx.project, :workspace)
    path = "/workspaces/#{project.workspace.slug}/projects/#{project.slug}/brainstorming/#{ctx.session.id}"

    browser =
      conn
      |> authenticate(ctx.viewer.user)
      |> visit(path)
      |> assert_has("#canvas-group-#{group.id}", timeout: 20_000)
      |> click("#canvas-group-#{group.id} header")
      |> click("#brainstorming-group-comments")
      |> assert_has("#brainstorming-comments-content", text: "Which ending fits the game?")
      |> click("#brainstorming-comment-thread-#{detail.thread.id}")
      |> refute_has("#brainstorming-comment-body")
      |> assert_has("#brainstorming-comment-read")
      |> click("#brainstorming-comment-follow")
      |> assert_has("#brainstorming-comment-follow", text: "Unfollow")
      |> click("#brainstorming-comment-read")
      |> refute_has("#brainstorming-comment-read")
      |> visit(path <> "?thread=#{detail.thread.id}")
      |> assert_has("#brainstorming-comment-follow", text: "Unfollow", timeout: 20_000)
      |> refute_has("#brainstorming-comment-read")

    {:ok, _} =
      Projects.reply_to_comment_thread(ctx.author, project.id, detail.thread.id, %{
        body: "A new proposal",
        client_request_id: Ecto.UUID.generate(),
        parent_id: hd(detail.messages).id
      })

    browser
    |> assert_has("#brainstorming-comments-content", text: "A new proposal")
    |> assert_has("#brainstorming-comment-read")
    |> click("#brainstorming-comment-follow")
    |> assert_has("#brainstorming-comment-follow", text: "Follow")
  end
end
