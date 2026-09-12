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
    assert has_element?(view, "#brainstorming-panels[data-inject-slot=panels]")
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

  test "viewers can follow and acknowledge group discussions without gaining write permissions", ctx do
    first = idea_fixture(ctx, %{visibility: :shared})
    second = idea_fixture(ctx, %{visibility: :shared}, ctx.peer)

    {:ok, group} =
      Ideation.create_group(ctx.author, ctx.project.id, ctx.session.id, %{
        request_key: Ecto.UUID.generate(),
        title: "Alternatives",
        idea_ids: [first.id, second.id],
        canvas: %{x: 0, y: 0, width: 650, height: 450}
      })

    {:ok, detail} =
      Projects.create_ideation_comment(ctx.author, ctx.project.id, ctx.session.id, {:group, group.id}, %{
        body: "Group discussion",
        client_request_id: Ecto.UUID.generate()
      })

    {:ok, view, _} = live(log_in_user(ctx.conn, ctx.viewer.user), path(ctx))
    render_hook(view, "comments_open", payload(view, ctx, %{group_id: group.id}))
    assert state(view)["groupId"] == group.id
    assert length(state(view)["threads"]) == 1
    render_hook(view, "comments_select_thread", payload(view, ctx, %{thread_id: detail.thread.id}))
    assert state(view)["thread"]["unread"]
    refute state(view)["canComment"]
    assert state(view)["members"] != []
    render_hook(view, "comments_follow", payload(view, ctx, %{thread_id: detail.thread.id, following: true}))
    assert_reply(view, %{ok: true})
    assert state(view)["thread"]["following"]

    render_hook(
      view,
      "comments_read",
      payload(view, ctx, %{thread_id: detail.thread.id, message_id: hd(detail.messages).id})
    )

    assert_reply(view, %{ok: true})
    refute state(view)["thread"]["unread"]
    stale = payload(view, ctx, %{thread_id: detail.thread.id, following: false})
    render_hook(view, "comments_open", payload(view, ctx, %{}))
    render_hook(view, "comments_follow", stale)
    assert_reply(view, %{ok: false})

    assert {:ok, %{thread: %{following: true}}} =
             Projects.get_comment_thread(ctx.viewer, ctx.project.id, detail.thread.id)

    {:ok, reopened, _} = live(log_in_user(ctx.conn, ctx.viewer.user), path(ctx) <> "?thread=#{detail.thread.id}")
    assert state(reopened)["groupId"] == group.id
    assert state(reopened)["thread"]["following"]
    refute state(reopened)["thread"]["unread"]
  end

  test "source invalidation refreshes notification payloads after visibility changes", ctx do
    idea = idea_fixture(ctx, %{visibility: :shared})

    {:ok, _} =
      Projects.create_ideation_comment(ctx.author, ctx.project.id, ctx.session.id, idea.id, %{
        body: "Shared feedback",
        client_request_id: Ecto.UUID.generate(),
        mention_user_ids: [ctx.peer.user.id]
      })

    {:ok, view, _} = live(log_in_user(ctx.conn, ctx.peer.user), path(ctx))
    send(view.pid, :notifications_changed)
    assert_push_event(view, "notifications_updated", %{unreadCount: 1, items: [%{href: href}]})
    assert href =~ "/brainstorming/#{ctx.session.id}?thread="
    {:ok, _} = Ideation.set_private_mode(ctx.facilitator, ctx.project.id, ctx.session.id, ctx.session.revision, true)
    # Flush the coalesced refresh deterministically, using the same handler as its timer.
    send(view.pid, :refresh_comment_notification_sources)
    assert_push_event(view, "notifications_updated", %{unreadCount: 0, items: []})
  end

  test "personal participation synchronizes the actor's other tabs without changing another viewer", ctx do
    {:ok, detail} =
      Projects.create_ideation_comment(ctx.author, ctx.project.id, ctx.session.id, nil, %{
        body: "A discussion in multiple tabs",
        client_request_id: Ecto.UUID.generate()
      })

    url = path(ctx) <> "?thread=#{detail.thread.id}"
    {:ok, first, _} = live(log_in_user(ctx.conn, ctx.viewer.user), url)
    {:ok, second, _} = live(log_in_user(ctx.conn, ctx.viewer.user), url)
    {:ok, other, _} = live(log_in_user(ctx.conn, ctx.peer.user), url)
    refute state(first)["thread"]["following"]
    refute state(second)["thread"]["following"]
    assert state(other)["thread"]["unread"]

    assert {:ok, _} = Projects.set_ideation_comment_following(ctx.viewer, ctx.project.id, detail.thread.id, true)
    assert state(first)["thread"]["following"]
    assert state(second)["thread"]["following"]
    refute state(other)["thread"]["following"]

    assert {:ok, _} =
             Projects.mark_ideation_comment_read(ctx.viewer, ctx.project.id, detail.thread.id, hd(detail.messages).id)

    refute state(first)["thread"]["unread"]
    refute state(second)["thread"]["unread"]
    assert state(other)["thread"]["unread"]
    refute_push_event(first, "notifications_updated", %{}, 250)
    refute_push_event(second, "notifications_updated", %{}, 250)
    refute_push_event(other, "notifications_updated", %{}, 250)
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

  defp state(view), do: LiveVue.Test.get_vue(view, name: "live/ideation/BoardPanels").props["comments"]

  defp payload(view, ctx, attrs) do
    board = LiveVue.Test.get_vue(view, name: "live/ideation/BrainstormingBoard").props["board"]
    Map.merge(attrs, %{epoch: board["epoch"], session_id: ctx.session.id, comment_context: state(view)["context"]})
  end

  defp path(ctx),
    do: ~p"/workspaces/#{ctx.project.workspace.slug}/projects/#{ctx.project.slug}/brainstorming/#{ctx.session.id}"
end
