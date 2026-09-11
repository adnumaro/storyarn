defmodule StoryarnWeb.IdeationLive.CommentsTest do
  use StoryarnWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Storyarn.IdeationFixtures

  alias Storyarn.Ideation
  alias Storyarn.Projects
  alias Storyarn.Repo

  setup do
    ctx = ideation_fixture()
    %{ctx | project: Repo.preload(ctx.project, :workspace)}
  end

  test "session threads survive reconnect and deep links; viewer cannot write", ctx do
    {:ok, view, _} = live(log_in_user(ctx.conn, ctx.author.user), path(ctx))
    assert has_element?(view, "#brainstorming-comments[data-inject-slot=panels]")
    render_hook(view, "comments_open", payload(view, ctx, %{}))
    assert state(view)["open"]
    request = payload(view, ctx, %{body: "Discuss the ending", client_request_id: Ecto.UUID.generate()})
    render_hook(view, "comments_create", request)
    assert_reply(view, %{ok: true})
    id = state(view)["thread"]["id"]
    render_hook(view, "comments_create", request)
    assert_reply(view, %{ok: true})
    assert length(state(view)["messages"]) == 1

    {:ok, reader, _} = live(log_in_user(ctx.conn, ctx.viewer.user), path(ctx) <> "?thread=#{id}")
    assert state(reader)["thread"]["id"] == id
    refute state(reader)["canComment"]

    render_hook(
      reader,
      "comments_reply",
      payload(reader, ctx, %{
        thread_id: id,
        parent_id: hd(state(reader)["messages"])["id"],
        body: "Forged write",
        client_request_id: Ecto.UUID.generate()
      })
    )

    assert_reply(reader, %{ok: false})
    assert {:ok, %{messages: [_]}} = Projects.get_comment_thread(ctx.author, ctx.project.id, id)
  end

  test "private mode clears idea discussion props and direct links deny access", ctx do
    idea = ctx |> idea_fixture() |> then(&publish_idea(ctx, &1))

    {:ok, detail} =
      Projects.create_ideation_comment(ctx.author, ctx.project.id, ctx.session.id, idea.id, %{
        body: "Shared feedback",
        client_request_id: Ecto.UUID.generate()
      })

    {:ok, view, _} = live(log_in_user(ctx.conn, ctx.peer.user), path(ctx) <> "?thread=#{detail.thread.id}")
    assert state(view)["open"]
    {:ok, _} = Ideation.set_private_mode(ctx.facilitator, ctx.project.id, ctx.session.id, ctx.session.revision, true)
    # The comment invalidation handler independently rechecks the source, even
    # before the asynchronously refreshed canvas has caught up.
    send(view.pid, {:ideation_comments_changed, ctx.session.id})
    render(view)
    refute state(view)["open"]
    assert state(view)["messages"] == []
    render_patch(view, path(ctx) <> "?thread=#{detail.thread.id}")
    refute state(view)["open"]
  end

  test "stale board and context requests cannot retarget a new discussion", ctx do
    {:ok, view, _} = live(log_in_user(ctx.conn, ctx.author.user), path(ctx))
    render_hook(view, "comments_open", payload(view, ctx, %{}))
    stale = payload(view, ctx, %{body: "Do not retarget", client_request_id: Ecto.UUID.generate()})
    render_hook(view, "comments_open", payload(view, ctx, %{}))
    render_hook(view, "comments_create", stale)
    assert_reply(view, %{ok: false})
    render_hook(view, "comments_create", Map.put(payload(view, ctx, stale), :epoch, "old"))
    assert_reply(view, %{ok: false})
    assert {:ok, %{threads: []}} = Projects.list_ideation_comment_threads(ctx.author, ctx.project.id, ctx.session.id)
  end

  test "selecting another source rejects a pending create for the previous discussion", ctx do
    idea = ctx |> idea_fixture() |> then(&publish_idea(ctx, &1))

    {:ok, detail} =
      Projects.create_ideation_comment(ctx.author, ctx.project.id, ctx.session.id, idea.id, %{
        body: "Idea discussion",
        client_request_id: Ecto.UUID.generate()
      })

    {:ok, view, _} = live(log_in_user(ctx.conn, ctx.author.user), path(ctx))
    render_hook(view, "comments_open", payload(view, ctx, %{}))
    pending = payload(view, ctx, %{body: "Session feedback", client_request_id: Ecto.UUID.generate()})
    render_hook(view, "comments_select_thread", payload(view, ctx, %{thread_id: detail.thread.id}))
    assert state(view)["ideaId"] == idea.id
    render_hook(view, "comments_create", pending)
    assert_reply(view, %{ok: false})
    assert {:ok, %{messages: [_]}} = Projects.get_comment_thread(ctx.author, ctx.project.id, detail.thread.id)
    assert {:ok, %{threads: []}} = Projects.list_ideation_comment_threads(ctx.author, ctx.project.id, ctx.session.id)
  end

  defp state(view), do: LiveVue.Test.get_vue(view, name: "live/ideation/CommentsPanel").props["state"]

  defp payload(view, ctx, attrs) do
    board = LiveVue.Test.get_vue(view, name: "live/ideation/BrainstormingBoard").props["board"]
    Map.merge(attrs, %{epoch: board["epoch"], session_id: ctx.session.id, comment_context: state(view)["context"]})
  end

  defp path(ctx),
    do: ~p"/workspaces/#{ctx.project.workspace.slug}/projects/#{ctx.project.slug}/brainstorming/#{ctx.session.id}"
end
