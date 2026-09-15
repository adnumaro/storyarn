defmodule StoryarnWeb.CommentLive.OverlayTest do
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

  test "the overlay lists accessible conversations without participation", ctx do
    thread = create_comment(ctx)
    reader = user_fixture()
    membership_fixture(ctx.project, reader, "viewer")

    {:ok, view, _} = open_hub(log_in_user(ctx.conn, reader), %{})
    assert has_element?(view, "#comments-overlay-island")
    assert state(view)["filters"]["status"] == "all"
    assert [%{"id" => id, "project_name" => name}] = state(view)["threads"]
    assert id == thread.thread.id
    assert name == ctx.project.name
    assert %{"all" => 1, "open" => 1, "resolved" => 0, "tools" => %{"sheet" => 1}} = state(view)["counts"]
    assert Enum.any?(state(view)["projects"], &(&1["id"] == ctx.project.id))
    assert state(view)["conversation"]["thread"] == nil
  end

  test "filters and selection survive closing and reopening without navigation", ctx do
    detail = create_comment(ctx)
    query = %{project_id: ctx.project.id, tool: "sheet", search: "Review", personal: "participated"}
    {:ok, view, _} = open_hub(ctx.conn, query)

    render_hook(view, "hub_select", %{thread_id: detail.thread.id, project_id: ctx.project.id})
    refute_redirected(view)
    render_hook(view, "hub_close", %{})
    refute socket_assigns(view).open
    render_hook(view, "hub_open", %{})
    assert state(view)["conversation"]["thread"]["id"] == detail.thread.id
    assert state(view)["contextUrl"] == sheet_path(ctx, detail.thread.id)

    assert state(view)["selectedThreadId"] == detail.thread.id
    assert state(view)["filters"]["search"] == "Review"

    render_hook(view, "hub_clear_selection", %{})
    refute_redirected(view)
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

    {:ok, view, _} = open_hub(ctx.conn, selected_params(ctx, open))

    render_hook(view, "hub_filter", %{project_id: to_string(ctx.project.id), status: "resolved", search: "ending"})
    assert state(view)["selectedThreadId"] == nil
    assert [%{"id" => id}] = state(view)["threads"]
    assert id == resolved.thread.id
    assert %{"all" => 1, "open" => 0, "resolved" => 1} = state(view)["counts"]
  end

  test "reply and resolution reuse the selected conversation and reject cross-thread mutations", ctx do
    detail = create_comment(ctx)
    other = create_comment(ctx, %{body: "Another discussion"})
    {:ok, view, _} = open_hub(ctx.conn, selected_params(ctx, detail))

    render_hook(view, "comments_reply", reply_params(other, "A forged target"))
    assert_reply(view, %{ok: false})
    assert {:ok, %{messages: [_]}} = Projects.get_comment_thread(ctx.scope, ctx.project.id, other.thread.id)

    request = reply_params(detail, "Reply from the comments hub")
    render_hook(view, "comments_reply", request)
    assert_reply(view, %{ok: true})
    render_hook(view, "comments_reply", request)
    assert_reply(view, %{ok: true})
    flush_refresh(view)
    assert length(state(view)["conversation"]["messages"]) == 2

    revision = state(view)["conversation"]["thread"]["revision"]

    render_hook(view, "comments_set_status", %{
      thread_id: detail.thread.id,
      status: "resolved",
      expected_revision: revision
    })

    assert_reply(view, %{ok: true})
    flush_refresh(view)
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
    {:ok, view, _} = open_hub(log_in_user(ctx.conn, viewer), selected_params(ctx, detail))
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
    {:ok, view, _} = open_hub(log_in_user(ctx.conn, reader), selected_params(ctx, detail))
    assert state(view)["conversation"]["canComment"]
    before_topics = MapSet.new(Registry.keys(Storyarn.PubSub, view.pid))
    send(view.pid, {:comment_conversations_changed, ctx.project.id})
    render(view)
    pending = socket_assigns(view).comment_refresh

    assert {:ok, _} = Projects.remove_member(ctx.scope, ctx.project.id, membership.id)

    assert state(view)["threads"] == []
    assert state(view)["selectedThreadId"] == nil
    assert state(view)["conversation"]["messages"] == []
    assert state(view)["contextUrl"] == nil
    refute Enum.any?(state(view)["projects"], &(&1["id"] == ctx.project.id))
    after_topics = MapSet.new(Registry.keys(Storyarn.PubSub, view.pid))
    assert MapSet.size(MapSet.difference(before_topics, after_topics)) == 5
    refute MapSet.member?(socket_assigns(view).subscribed_projects, ctx.project.id)
    refute MapSet.member?(socket_assigns(view).subscribed_workspaces, ctx.project.workspace_id)

    assert capture_queries(view, fn ->
             send(view.pid, {:refresh_comment_hub, :comment_refresh, pending.token})

             Phoenix.PubSub.broadcast(
               Storyarn.PubSub,
               Storyarn.Platform.Collaboration.dashboard_topic(ctx.project.id),
               {:dashboard_invalidate, :sheets}
             )

             render(view)
             flush_refresh(view)
           end) == []

    render_hook(view, "comments_reply", reply_params(detail, "Stale composer"))
    assert_reply(view, %{ok: false})
    assert {:ok, %{messages: [_]}} = Projects.get_comment_thread(ctx.scope, ctx.project.id, detail.thread.id)
  end

  test "realtime replies refresh the selected conversation and search results", ctx do
    detail = create_comment(ctx)
    {:ok, view, _} = open_hub(ctx.conn, selected_params(ctx, detail))

    {:ok, _} =
      Projects.reply_to_comment_thread(
        ctx.scope,
        ctx.project.id,
        detail.thread.id,
        reply_params(detail, "Another window")
      )

    flush_refresh(view)
    assert List.last(state(view)["conversation"]["messages"])["body"] == "Another window"
    assert hd(state(view)["threads"])["message_count"] == 2
  end

  test "deleted surfaces keep readable history and remove the context link and composer", ctx do
    detail = create_comment(ctx)
    {:ok, view, _} = open_hub(ctx.conn, selected_params(ctx, detail))
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

  test "malformed and inaccessible selections reveal no conversation", ctx do
    detail = create_comment(ctx)
    stranger = user_fixture()
    {:ok, denied, _} = open_hub(log_in_user(ctx.conn, stranger), selected_params(ctx, detail))
    assert state(denied)["threads"] == []
    assert state(denied)["conversation"]["messages"] == []
    assert state(denied)["contextUrl"] == nil

    {:ok, view, _} = open_hub(ctx.conn, %{project: "999999999999999999999999999999", thread: "bad", tool: "unknown"})
    assert state(view)["selectedThreadId"] == nil
    assert state(view)["filters"]["tool"] == ""
    render_hook(view, "comments_load_messages", %{})
    render_hook(view, "comments_set_status", %{thread_id: "bad", status: "resolved", expected_revision: "bad"})
    assert_reply(view, %{ok: false})
  end

  test "loaded pages and selection survive closing and reauthorize when reopened", ctx do
    for number <- 1..31, do: create_comment(ctx, %{body: "Review #{number}"})
    reader = user_fixture()
    membership = membership_fixture(ctx.project, reader, "viewer")
    {:ok, view, _} = open_hub(log_in_user(ctx.conn, reader), %{})
    assert length(state(view)["threads"]) == 30
    more_queries = capture_queries(view, fn -> render_hook(view, "hub_load_more", %{}) end)
    assert Enum.count(more_queries, &count_query?/1) == 1
    ids = Enum.map(state(view)["threads"], & &1["id"])
    assert length(Enum.uniq(ids)) == 31
    assert state(view)["nextCursor"] == nil
    oldest_id = List.last(ids)
    render_hook(view, "hub_select", %{project_id: ctx.project.id, thread_id: oldest_id})
    render_hook(view, "hub_close", %{})
    render_hook(view, "hub_open", %{})
    assert Enum.map(state(view)["threads"], & &1["id"]) == ids
    assert state(view)["selectedThreadId"] == oldest_id
    refute_redirected(view)

    render_hook(view, "hub_filter", %{project_id: to_string(ctx.project.id)})
    assert length(state(view)["threads"]) == 30
    assert state(view)["selectedThreadId"] == nil
    render_hook(view, "hub_close", %{})
    {:ok, _} = Projects.remove_member(ctx.scope, ctx.project.id, membership.id)
    render_hook(view, "hub_open", %{})
    assert state(view)["threads"] == []
  end

  test "closing unsubscribes and stops both refreshes and forged mutations", ctx do
    detail = create_comment(ctx)
    {:ok, view, _} = open_hub(ctx.conn, selected_params(ctx, detail))
    send(view.pid, {:comment_conversations_changed, ctx.project.id})
    render(view)
    pending = socket_assigns(view).comment_refresh
    render_hook(view, "hub_close", %{})
    assert Registry.keys(Storyarn.PubSub, view.pid) == []
    assert socket_assigns(view).refresh_timer == nil
    assert socket_assigns(view).comment_refresh == nil
    assert state(view)["conversation"]["messages"] == []

    assert capture_queries(view, fn ->
             send(view.pid, :refresh_comment_hub)
             send(view.pid, {:refresh_comment_hub, :comment_refresh, pending.token})
             send(view.pid, {:dashboard_invalidate, :sheets})
             render_hook(view, "hub_refresh", %{})
             render_hook(view, "comments_reply", reply_params(detail, "Closed composer"))
             render(view)
           end) == []

    assert {:ok, %{messages: [_]}} = Projects.get_comment_thread(ctx.scope, ctx.project.id, detail.thread.id)
  end

  test "opening follows the host project or workspace and keeps its LiveView alive", ctx do
    create_comment(ctx)

    for {path, project_id} <- [
          {sheet_path(ctx, nil), to_string(ctx.project.id)},
          {~p"/workspaces/#{ctx.project.workspace.slug}", ""},
          {~p"/workspaces/#{ctx.project.workspace.slug}/projects/#{ctx.project.slug}/settings",
           to_string(ctx.project.id)},
          {~p"/users/settings/workspaces/#{ctx.project.workspace.slug}/general", ""}
        ] do
      {:ok, parent, _} = live(ctx.conn, path)
      view = find_live_child(parent, "comments-overlay")
      refute socket_assigns(view).open
      assert Registry.keys(Storyarn.PubSub, view.pid) == []
      assert state(view)["threads"] == []
      render_hook(view, "hub_open", %{project_id: "999999"})
      assert state(view)["filters"]["project_id"] == project_id
      assert state(view)["filters"]["workspace_id"] == to_string(ctx.project.workspace_id)
      render_hook(view, "hub_close", %{})
      assert Process.alive?(parent.pid)
      refute_redirected(parent)
    end
  end

  test "there is no standalone comments route" do
    assert Phoenix.Router.route_info(StoryarnWeb.Router, "GET", "/comments", "localhost") == :error
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
    {:ok, view, _} = open_hub(log_in_user(ctx.conn, reader), selected_params(ctx, detail))
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

    flush_refresh(view)
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

    {:ok, view, _} = open_hub(log_in_user(ctx.conn, ideation.peer.user), selected_params(ideation, detail))
    assert state(view)["selectedThreadId"] == detail.thread.id

    {:ok, _} =
      Storyarn.IdeationFixtures.set_private_mode(
        ideation.facilitator,
        ideation.project.id,
        ideation.session.id,
        ideation.session.revision,
        true
      )

    flush_refresh(view)
    assert state(view)["threads"] == []
    assert state(view)["selectedThreadId"] == nil
    assert state(view)["conversation"]["messages"] == []
    assert state(view)["contextUrl"] == nil
    assert state(view)["counts"]["all"] == 0
  end

  test "selecting a thread reads its message page once without querying the list or workspace options", ctx do
    detail = create_comment(ctx)
    {:ok, view, _} = open_hub(ctx.conn, %{})

    queries =
      capture_queries(view, fn ->
        render_hook(view, "hub_select", %{project_id: ctx.project.id, thread_id: detail.thread.id})
      end)

    assert Enum.count(queries, &message_page_query?/1) == 1
    refute Enum.any?(queries, &count_query?/1)
    refute Enum.any?(queries, &project_options_query?/1)
    assert state(view)["selectedThreadId"] == detail.thread.id
    assert state(view)["contextUrl"] == sheet_path(ctx, detail.thread.id)
  end

  test "comment bursts share one refresh and a reply absorbs its own PubSub echo", ctx do
    detail = create_comment(ctx)
    {:ok, view, _} = open_hub(ctx.conn, selected_params(ctx, detail))

    burst_queries =
      capture_queries(view, fn ->
        for _ <- 1..20, do: send(view.pid, {:comment_conversations_changed, ctx.project.id})
        flush_refresh(view)
      end)

    assert Enum.count(burst_queries, &count_query?/1) == 1
    assert Enum.count(burst_queries, &message_page_query?/1) == 1
    refute Enum.any?(burst_queries, &project_options_query?/1)

    reply_queries =
      capture_queries(view, fn ->
        render_hook(view, "comments_reply", reply_params(detail, "One refresh after replying"))
        assert_reply(view, %{ok: true})
        flush_refresh(view)
      end)

    assert Enum.count(reply_queries, &count_query?/1) == 1
    refute Enum.any?(reply_queries, &project_options_query?/1)
    assert List.last(state(view)["conversation"]["messages"])["body"] == "One refresh after replying"
    assert socket_assigns(view).comment_refresh == nil
  end

  test "dashboard editing uses trailing debounce and a comment refresh cancels the superseded work", ctx do
    detail = create_comment(ctx)
    {:ok, view, _} = open_hub(ctx.conn, selected_params(ctx, detail))

    initial_queries =
      capture_queries(view, fn ->
        send(view.pid, {:dashboard_invalidate, :sheets})
        render(view)
      end)

    assert initial_queries == []
    first = socket_assigns(view).source_refresh

    send(view.pid, {:dashboard_invalidate, :sheets})
    render(view)
    second = socket_assigns(view).source_refresh
    refute first.token == second.token

    assert capture_queries(view, fn ->
             send(view.pid, {:refresh_comment_hub, :source_refresh, first.token})
             render(view)
           end) == []

    comment_queries =
      capture_queries(view, fn ->
        send(view.pid, {:comment_conversations_changed, ctx.project.id})
        flush_refresh(view)
        send(view.pid, {:refresh_comment_hub, :source_refresh, second.token})
        render(view)
      end)

    assert Enum.count(comment_queries, &count_query?/1) == 1
    assert socket_assigns(view).source_refresh == nil

    send(view.pid, {:dashboard_invalidate, :sheets})
    render(view)
    assert socket_assigns(view).source_refresh

    fallback_queries =
      capture_queries(view, fn ->
        send(view.pid, :refresh_comment_hub)
        render(view)
        flush_refresh(view)
      end)

    assert Enum.count(fallback_queries, &count_query?/1) == 1
    assert Enum.any?(fallback_queries, &project_options_query?/1)
    assert socket_assigns(view).source_refresh == nil
  end

  test "a project filter skips unrelated activity but still refreshes a selected thread outside the filter", ctx do
    create_comment(ctx)
    other_project = project_fixture(ctx.user, %{workspace: ctx.project.workspace})
    other_sheet = sheet_fixture(other_project)
    other = create_comment(%{ctx | project: other_project, sheet: other_sheet})
    {:ok, view, _} = open_hub(ctx.conn, %{project_id: ctx.project.id})

    assert capture_queries(view, fn ->
             send(view.pid, {:comment_conversations_changed, other_project.id})
             flush_refresh(view)
           end) == []

    render_hook(view, "hub_select", %{project_id: other_project.id, thread_id: other.thread.id})

    selected_queries =
      capture_queries(view, fn ->
        send(view.pid, {:comment_conversations_changed, other_project.id})
        flush_refresh(view)
      end)

    assert Enum.count(selected_queries, &count_query?/1) == 1
    assert state(view)["selectedThreadId"] == other.thread.id
    assert Enum.all?(state(view)["threads"], &(&1["project_id"] == ctx.project.id))
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

  defp selected_params(ctx, detail), do: %{project: ctx.project.id, thread: detail.thread.id}

  defp sheet_path(ctx, thread_id),
    do:
      ~p"/workspaces/#{ctx.project.workspace.slug}/projects/#{ctx.project.slug}/sheets/#{ctx.sheet.id}?#{%{thread: thread_id}}"

  defp state(view) do
    render(view)
    LiveVue.Test.get_vue(view, name: "live/comments/Overlay").props["state"]
  end

  defp socket_assigns(view), do: :sys.get_state(view.pid).socket.assigns

  defp flush_refresh(view) do
    render(view)

    for kind <- [:comment_refresh, :source_refresh] do
      case socket_assigns(view)[kind] do
        %{token: token} -> send(view.pid, {:refresh_comment_hub, kind, token})
        _ -> :ok
      end
    end

    render(view)
  end

  defp capture_queries(view, fun) do
    marker = make_ref()
    :ok = :telemetry.attach(marker, [:storyarn, :repo, :query], &record_query/4, {self(), view.pid, marker})

    try do
      fun.()
      drain_queries(marker, [])
    after
      :telemetry.detach(marker)
    end
  end

  defp record_query(_event, _measurements, metadata, {recipient, live_view, marker}) do
    if self() == live_view, do: send(recipient, {marker, metadata})
  end

  defp drain_queries(marker, queries) do
    receive do
      {^marker, metadata} -> drain_queries(marker, [metadata | queries])
    after
      0 -> Enum.reverse(queries)
    end
  end

  defp count_query?(query), do: query.source == "comment_threads" and String.contains?(query.query, "GROUP BY")

  # The batched "latest message per row" read of the list is not a message page.
  defp message_page_query?(query),
    do:
      query.source == "comment_messages" and String.contains?(query.query, "ORDER BY") and
        not String.contains?(query.query, "DISTINCT ON")

  defp project_options_query?(query),
    do: query.source == "projects" and String.contains?(query.query, ~s(LEFT OUTER JOIN "workspace_memberships"))

  defp open_hub(conn, params) do
    {:ok, parent, html} = live(conn, ~p"/users/settings/preferences")
    view = find_live_child(parent, "comments-overlay")
    render_hook(view, "hub_open", %{})
    if map_size(params) > 0, do: render_hook(view, "hub_filter", params)

    if params[:thread] do
      render_hook(view, "hub_select", %{project_id: params[:project], thread_id: params[:thread]})
    end

    {:ok, view, html}
  end
end
