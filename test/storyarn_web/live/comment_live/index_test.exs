defmodule StoryarnWeb.CommentLive.IndexTest do
  use StoryarnWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Storyarn.AccountsFixtures
  import Storyarn.ProjectsFixtures
  import Storyarn.SheetsFixtures

  alias Storyarn.Projects
  alias Storyarn.Repo
  alias Storyarn.Sheets

  setup :register_and_log_in_user

  setup %{user: user} do
    project = user |> project_fixture() |> Repo.preload(:workspace)
    sheet = sheet_fixture(project, %{name: "Character review"})
    %{project: project, sheet: sheet, scope: user_scope_fixture(user)}
  end

  test "the hub uses the workspace shell and lists all accessible conversations without participation", ctx do
    thread = create_comment(ctx)
    reader = user_fixture()
    membership_fixture(ctx.project, reader, "viewer")

    {:ok, view, _} = live(log_in_user(ctx.conn, reader), ~p"/comments")
    assert has_element?(view, "#comments-hub[data-inject=workspace-layout]")
    assert has_element?(view, "#workspace-layout")
    assert state(view)["filters"]["status"] == "all"
    assert [%{"id" => id, "project_name" => name}] = state(view)["threads"]
    assert id == thread.thread.id
    assert name == ctx.project.name
    assert state(view)["counts"] == %{"all" => 1, "open" => 1, "resolved" => 0}
    assert Enum.any?(state(view)["projects"], &(&1["id"] == ctx.project.id))
    assert state(view)["conversation"]["thread"] == nil
  end

  test "filters and selection survive direct links and returning to the list", ctx do
    detail = create_comment(ctx)
    query = %{project_id: ctx.project.id, tool: "sheet", search: "Review", personal: "participated"}
    {:ok, view, _} = live(ctx.conn, ~p"/comments?#{query}")

    render_hook(view, "hub_select", %{thread_id: detail.thread.id, project_id: ctx.project.id})
    selection = Map.merge(query, %{project: ctx.project.id, thread: detail.thread.id})
    assert_comment_patch(view, selection)
    assert state(view)["conversation"]["thread"]["id"] == detail.thread.id
    assert state(view)["contextUrl"] == sheet_path(ctx, detail.thread.id)

    {:ok, reconnected, _} = live(ctx.conn, ~p"/comments?#{selection}")
    assert state(reconnected)["selectedThreadId"] == detail.thread.id
    assert state(reconnected)["filters"]["search"] == "Review"

    render_hook(view, "hub_clear_selection", %{})
    assert_comment_patch(view, query)
    assert state(view)["selectedThreadId"] == nil
    assert state(view)["conversation"]["messages"] == []
  end

  test "filter changes clear selection while retaining authorized search and state counts", ctx do
    open = create_comment(ctx)
    resolved = create_comment(ctx, %{body: "Review the resolved ending"})

    {:ok, _} =
      Projects.set_comment_thread_status(
        ctx.scope,
        ctx.project.id,
        resolved.thread.id,
        "resolved",
        resolved.thread.revision
      )

    {:ok, view, _} = live(ctx.conn, selected_path(ctx, open))

    render_hook(view, "hub_filter", %{project_id: to_string(ctx.project.id), status: "resolved", search: "ending"})
    assert state(view)["selectedThreadId"] == nil
    assert [%{"id" => id}] = state(view)["threads"]
    assert id == resolved.thread.id
    assert state(view)["counts"] == %{"all" => 1, "open" => 0, "resolved" => 1}
  end

  test "reply and resolution reuse the selected conversation and reject cross-thread mutations", ctx do
    detail = create_comment(ctx)
    other = create_comment(ctx, %{body: "Another discussion"})
    {:ok, view, _} = live(ctx.conn, selected_path(ctx, detail))

    render_hook(view, "comments_reply", reply_params(other, "A forged target"))
    assert_reply(view, %{ok: false})
    assert {:ok, %{messages: [_]}} = Projects.get_comment_thread(ctx.scope, ctx.project.id, other.thread.id)

    request = reply_params(detail, "Reply from the comments hub")
    render_hook(view, "comments_reply", request)
    assert_reply(view, %{ok: true})
    render_hook(view, "comments_reply", request)
    assert_reply(view, %{ok: true})
    assert length(state(view)["conversation"]["messages"]) == 2

    revision = state(view)["conversation"]["thread"]["revision"]

    render_hook(view, "comments_set_status", %{
      thread_id: detail.thread.id,
      status: "resolved",
      expected_revision: revision
    })

    assert_reply(view, %{ok: true})
    assert state(view)["conversation"]["thread"]["status"] == "resolved"
    assert state(view)["counts"]["resolved"] == 1

    render_hook(view, "comments_set_status", %{
      thread_id: detail.thread.id,
      status: "open",
      expected_revision: revision
    })

    assert_reply(view, %{ok: false, error: "This conversation changed. Please try again."})
    assert state(view)["conversation"]["thread"]["status"] == "resolved"
  end

  test "viewers can read but cannot reply, resolve or create conversations", ctx do
    detail = create_comment(ctx)
    viewer = user_fixture()
    membership_fixture(ctx.project, viewer, "viewer")
    {:ok, view, _} = live(log_in_user(ctx.conn, viewer), selected_path(ctx, detail))
    refute state(view)["conversation"]["canComment"]

    render_hook(view, "comments_reply", reply_params(detail, "Forged viewer reply"))
    assert_reply(view, %{ok: false})

    render_hook(view, "comments_set_status", %{
      thread_id: detail.thread.id,
      status: "resolved",
      expected_revision: detail.thread.revision
    })

    assert_reply(view, %{ok: false})
    render_hook(view, "comments_create", %{body: "A thread without a source", client_request_id: Ecto.UUID.generate()})
    assert_reply(view, %{ok: false})

    assert {:ok, %{messages: [_], thread: %{status: "open"}}} =
             Projects.get_comment_thread(ctx.scope, ctx.project.id, detail.thread.id)
  end

  test "membership revocation removes messages, rows and project options from an open hub", ctx do
    detail = create_comment(ctx)
    reader = user_fixture()
    membership = membership_fixture(ctx.project, reader, "editor")
    {:ok, view, _} = live(log_in_user(ctx.conn, reader), selected_path(ctx, detail))
    assert state(view)["conversation"]["canComment"]

    assert {:ok, _} = Projects.remove_member(ctx.scope, ctx.project.id, membership.id)

    assert state(view)["threads"] == []
    assert state(view)["selectedThreadId"] == nil
    assert state(view)["conversation"]["messages"] == []
    assert state(view)["contextUrl"] == nil
    refute Enum.any?(state(view)["projects"], &(&1["id"] == ctx.project.id))

    render_hook(view, "comments_reply", reply_params(detail, "Stale composer"))
    assert_reply(view, %{ok: false})
    assert {:ok, %{messages: [_]}} = Projects.get_comment_thread(ctx.scope, ctx.project.id, detail.thread.id)
  end

  test "realtime replies refresh the selected conversation and search results", ctx do
    detail = create_comment(ctx)
    {:ok, view, _} = live(ctx.conn, selected_path(ctx, detail))

    {:ok, _} =
      Projects.reply_to_comment_thread(
        ctx.scope,
        ctx.project.id,
        detail.thread.id,
        reply_params(detail, "Another window")
      )

    assert List.last(state(view)["conversation"]["messages"])["body"] == "Another window"
    assert hd(state(view)["threads"])["message_count"] == 2
  end

  test "deleted surfaces keep readable history and remove the context link and composer", ctx do
    detail = create_comment(ctx)
    {:ok, view, _} = live(ctx.conn, selected_path(ctx, detail))
    assert state(view)["contextUrl"]
    {:ok, _} = Sheets.delete_sheet(ctx.scope, ctx.sheet)
    send(view.pid, :refresh_comment_hub)

    assert state(view)["conversation"]["thread"]["source"]["status"] == "unavailable"
    assert length(state(view)["conversation"]["messages"]) == 1
    assert state(view)["contextUrl"] == nil
    refute state(view)["conversation"]["canComment"]

    render_hook(view, "comments_reply", reply_params(detail, "Source is gone"))
    assert_reply(view, %{ok: false})
  end

  test "malformed and inaccessible direct links reveal no conversation", ctx do
    detail = create_comment(ctx)
    stranger = user_fixture()
    {:ok, denied, _} = live(log_in_user(ctx.conn, stranger), selected_path(ctx, detail))
    assert state(denied)["threads"] == []
    assert state(denied)["conversation"]["messages"] == []
    assert state(denied)["contextUrl"] == nil

    {:ok, view, _} = live(ctx.conn, "/comments?project=999999999999999999999999999999&thread=bad&tool=unknown")
    assert state(view)["selectedThreadId"] == nil
    assert state(view)["filters"]["tool"] == ""
    render_hook(view, "comments_load_messages", %{})
    render_hook(view, "comments_set_status", %{thread_id: "bad", status: "resolved", expected_revision: "bad"})
    assert_reply(view, %{ok: false})
  end

  test "older list pages and selection survive editor return, browser back and fresh access checks", ctx do
    for number <- 1..31, do: create_comment(ctx, %{body: "Review #{number}"})
    reader = user_fixture()
    membership = membership_fixture(ctx.project, reader, "viewer")
    {:ok, view, _} = live(log_in_user(ctx.conn, reader), ~p"/comments")
    assert length(state(view)["threads"]) == 30
    assert state(view)["nextCursor"]
    render_hook(view, "hub_load_more", %{})
    assert_comment_patch(view, %{pages: 2})
    ids = Enum.map(state(view)["threads"], & &1["id"])
    assert length(ids) == 31
    assert length(Enum.uniq(ids)) == 31
    assert state(view)["nextCursor"] == nil

    oldest_id = List.last(ids)
    render_hook(view, "hub_select", %{project_id: ctx.project.id, thread_id: oldest_id})
    return_path = assert_comment_patch(view, %{pages: 2, project: ctx.project.id, thread: oldest_id})

    {:ok, returned, _} = live(log_in_user(ctx.conn, reader), return_path)
    assert Enum.map(state(returned)["threads"], & &1["id"]) == ids
    assert state(returned)["selectedThreadId"] == oldest_id

    render_patch(returned, ~p"/comments")
    assert length(state(returned)["threads"]) == 30
    assert state(returned)["selectedThreadId"] == nil
    render_patch(returned, return_path)
    assert length(state(returned)["threads"]) == 31

    render_patch(returned, "/comments?pages=100000000")
    assert length(state(returned)["threads"]) == 30

    render_hook(view, "hub_filter", %{project_id: to_string(ctx.project.id)})
    assert_comment_patch(view, %{project_id: ctx.project.id})
    assert length(state(view)["threads"]) == 30
    assert state(view)["selectedThreadId"] == nil

    {:ok, _} = Projects.remove_member(ctx.scope, ctx.project.id, membership.id)
    render_hook(view, "hub_refresh", %{})
    assert state(view)["threads"] == []
  end

  test "older history stays chronological across refreshes and replies and disappears on revocation", ctx do
    detail = create_comment(ctx)

    for number <- 1..61 do
      {:ok, _} =
        Projects.reply_to_comment_thread(
          ctx.scope,
          ctx.project.id,
          detail.thread.id,
          reply_params(detail, "Reply #{number}")
        )
    end

    reader = user_fixture()
    membership = membership_fixture(ctx.project, reader, "viewer")
    {:ok, view, _} = live(log_in_user(ctx.conn, reader), selected_path(ctx, detail))
    assert state(view)["conversation"]["messageNextCursor"]
    render_hook(view, "comments_load_messages", %{})
    messages = state(view)["conversation"]["messages"]
    ids = Enum.map(messages, & &1["id"])
    assert length(messages) == 61
    assert ids == Enum.sort(Enum.uniq(ids))
    assert hd(messages)["body"] == "Review this character"
    assert Enum.at(messages, 1)["body"] == "Reply 2"
    assert List.last(messages)["body"] == "Reply 61"
    assert state(view)["conversation"]["messageNextCursor"]

    render_hook(view, "hub_refresh", %{})
    assert Enum.map(state(view)["conversation"]["messages"], & &1["id"]) == ids

    render_hook(view, "comments_load_messages", %{})
    complete_history = state(view)["conversation"]["messages"]
    assert length(complete_history) == 62
    assert Enum.at(complete_history, 1)["body"] == "Reply 1"
    assert state(view)["conversation"]["messageNextCursor"] == nil

    {:ok, _} =
      Projects.reply_to_comment_thread(
        ctx.scope,
        ctx.project.id,
        detail.thread.id,
        reply_params(detail, "Reply 62 from another window")
      )

    refreshed = state(view)["conversation"]["messages"]
    assert length(refreshed) == 63
    assert Enum.take(refreshed, 62) == complete_history
    assert List.last(refreshed)["body"] == "Reply 62 from another window"

    send(view.pid, :refresh_comment_hub)
    assert state(view)["conversation"]["messages"] == refreshed

    {:ok, _} = Projects.remove_member(ctx.scope, ctx.project.id, membership.id)
    assert state(view)["conversation"]["messages"] == []
    assert state(view)["conversation"]["members"] == []
    assert state(view)["selectedThreadId"] == nil
  end

  test "a newly private brainstorming source disappears from an already open hub", ctx do
    ideation = Storyarn.IdeationFixtures.ideation_fixture()
    idea = Storyarn.IdeationFixtures.idea_fixture(ideation, %{visibility: :shared})

    {:ok, detail} =
      Projects.create_ideation_comment(ideation.author, ideation.project.id, ideation.session.id, idea.id, %{
        body: "Discuss a shared idea",
        client_request_id: Ecto.UUID.generate()
      })

    {:ok, view, _} = live(log_in_user(ctx.conn, ideation.peer.user), selected_path(ideation, detail))
    assert state(view)["selectedThreadId"] == detail.thread.id

    {:ok, _} =
      Storyarn.Ideation.set_private_mode(
        ideation.facilitator,
        ideation.project.id,
        ideation.session.id,
        ideation.session.revision,
        true
      )

    assert state(view)["threads"] == []
    assert state(view)["selectedThreadId"] == nil
    assert state(view)["conversation"]["messages"] == []
    assert state(view)["contextUrl"] == nil
    assert state(view)["counts"]["all"] == 0
  end

  defp create_comment(ctx, attrs \\ %{}) do
    attrs =
      Map.merge(
        %{body: "Review this character", position: %{x: 20, y: 300}, client_request_id: Ecto.UUID.generate()},
        attrs
      )

    {:ok, detail} = Projects.create_sheet_canvas_comment(ctx.scope, ctx.project.id, ctx.sheet.id, attrs)
    detail
  end

  defp reply_params(detail, body),
    do: %{
      thread_id: detail.thread.id,
      parent_id: hd(detail.messages).id,
      body: body,
      client_request_id: Ecto.UUID.generate()
    }

  defp selected_path(ctx, detail), do: ~p"/comments?#{%{project: ctx.project.id, thread: detail.thread.id}}"

  defp sheet_path(ctx, thread_id),
    do:
      ~p"/workspaces/#{ctx.project.workspace.slug}/projects/#{ctx.project.slug}/sheets/#{ctx.sheet.id}?#{%{thread: thread_id}}"

  defp state(view) do
    render(view)
    LiveVue.Test.get_vue(view, name: "live/comments/Hub").props["state"]
  end

  defp assert_comment_patch(view, expected_query) do
    path = assert_patch(view)
    uri = URI.parse(path)
    assert uri.path == "/comments"

    assert URI.decode_query(uri.query || "") ==
             Map.new(expected_query, fn {key, value} -> {to_string(key), to_string(value)} end)

    path
  end
end
