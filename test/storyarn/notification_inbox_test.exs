defmodule Storyarn.NotificationInboxTest do
  use Storyarn.DataCase, async: true

  import Storyarn.IdeationFixtures
  import Storyarn.SheetsFixtures

  alias Storyarn.Ideation
  alias Storyarn.NotificationInbox
  alias Storyarn.Platform
  alias Storyarn.Platform.Notifications.Notification
  alias Storyarn.Projects

  setup do
    ideation_fixture()
  end

  test "Platform fails closed for comments without an owner visibility predicate", ctx do
    canonical = canonical_comment(ctx)
    idea = idea_fixture(ctx, %{visibility: :shared})
    shared = ideation_comment(ctx, idea.id)
    notifications = NotificationInbox.list_notifications(ctx.peer)

    assert Enum.sort(Enum.map(notifications, & &1.entity_id)) ==
             Enum.sort([hd(canonical.messages).id, hd(shared.messages).id])

    assert Platform.list_notifications(ctx.peer) == []
    assert Platform.unread_notification_count(ctx.peer) == 0

    for notification <- notifications do
      assert {:error, :not_found} = Platform.mark_notification_read(ctx.peer, notification.id)
    end

    assert {:ok, 0} = Platform.mark_all_notifications_read(ctx.peer)
    assert NotificationInbox.unread_notification_count(ctx.peer) == 2
    assert Enum.all?(Repo.all(Notification), &is_nil(&1.read_at))
  end

  test "visibility precedes the limit and hidden notifications retain their unread state", ctx do
    canonical = canonical_comment(ctx)
    session = ideation_comment(ctx, nil)
    idea = idea_fixture(ctx, %{visibility: :shared})
    hidden = ideation_comment(ctx, idea.id)
    hidden_message_id = hd(hidden.messages).id
    hidden_notification = Repo.get_by!(Notification, recipient_id: ctx.peer.user.id, entity_id: hidden_message_id)

    # Equal timestamps make the id tiebreaker explicit: the hidden item is newest.
    Repo.update_all(Notification, set: [inserted_at: ~U[2026-09-12 10:00:00Z]])
    set_private_mode(ctx, true)

    assert [%{entity_id: listed_id}] = NotificationInbox.list_notifications(ctx.peer, limit: 1)
    assert listed_id == hd(session.messages).id
    assert NotificationInbox.unread_notification_count(ctx.peer) == 2

    assert Enum.any?(
             NotificationInbox.list_notifications(ctx.peer),
             &(&1.entity_id == hd(canonical.messages).id)
           )

    assert {:error, :not_found} = NotificationInbox.mark_notification_read(ctx.peer, hidden_notification.id)
    assert {:ok, 2} = NotificationInbox.mark_all_notifications_read(ctx.peer)
    assert NotificationInbox.unread_notification_count(ctx.peer) == 0
    assert is_nil(Repo.get!(Notification, hidden_notification.id).read_at)

    set_private_mode(ctx, false)

    assert NotificationInbox.unread_notification_count(ctx.peer) == 1

    assert [%{id: unread_id}] = NotificationInbox.list_notifications(ctx.peer, unread_only: true)
    assert unread_id == hidden_notification.id
    assert {:ok, %{read_at: read_at}} = NotificationInbox.mark_notification_read(ctx.peer, hidden_notification.id)
    assert read_at
    assert NotificationInbox.unread_notification_count(ctx.peer) == 0
  end

  test "caller options cannot replace the owner's visibility predicate", ctx do
    idea = idea_fixture(ctx, %{visibility: :shared})
    ideation_comment(ctx, idea.id)
    set_private_mode(ctx, true)

    assert NotificationInbox.list_notifications(ctx.peer, comment_visibility: dynamic(true)) == []
  end

  test "missing authenticated users have an empty inbox and cannot acknowledge notifications", ctx do
    ideation_comment(ctx, nil)
    [notification] = NotificationInbox.list_notifications(ctx.peer)

    for scope <- [nil, %{}, %{user: nil}] do
      assert NotificationInbox.list_notifications(scope) == []
      assert NotificationInbox.unread_notification_count(scope) == 0
      assert {:error, :not_found} = NotificationInbox.mark_notification_read(scope, notification.id)
      assert {:ok, 0} = NotificationInbox.mark_all_notifications_read(scope)

      assert Platform.list_notifications(scope) == []
      assert Platform.unread_notification_count(scope) == 0
      assert {:error, :not_found} = Platform.mark_notification_read(scope, notification.id)
      assert {:ok, 0} = Platform.mark_all_notifications_read(scope)
    end

    assert is_nil(Repo.get!(Notification, notification.id).read_at)
  end

  test "inbox SQL correlates both visibility checks with the outer notification message", ctx do
    ideation_comment(ctx, nil)

    {count, queries} = capture_queries(fn -> NotificationInbox.unread_notification_count(ctx.peer) end)
    assert count == 1
    [query] = Enum.filter(queries, &String.contains?(&1, ~s(FROM "notifications")))

    assert length(Regex.scan(~r/coalesce\(\(SELECT/i, query)) == 2
    assert length(Regex.scan(~r/\."id"\s*=\s*[a-z][a-z0-9]*\."entity_id"/i, query)) == 2
    refute String.contains?(query, "NOT IN (SELECT")
  end

  test "Hub search SQL correlates message matching with the current thread", ctx do
    detail = ideation_comment(ctx, nil)

    {result, queries} =
      capture_queries(fn -> Projects.list_ideation_conversations(ctx.peer, search: "Review this source") end)

    assert {:ok, %{threads: [%{id: thread_id}]}} = result
    assert thread_id == detail.thread.id
    [query] = Enum.filter(queries, &String.contains?(&1, "strpos"))
    assert Regex.match?(~r/exists\s*\(/i, query)
    assert Regex.match?(~r/\."thread_id"\s*=\s*[a-z][a-z0-9]*\."id"/i, query)
  end

  defp canonical_comment(ctx) do
    sheet = sheet_fixture(ctx.project)

    assert {:ok, detail} =
             Projects.create_sheet_canvas_comment(
               ctx.author,
               ctx.project.id,
               sheet.id,
               Map.put(comment_attrs(ctx), :position, %{x: 20, y: 50})
             )

    detail
  end

  defp ideation_comment(ctx, anchor) do
    assert {:ok, detail} =
             Projects.create_ideation_comment(ctx.author, ctx.project.id, ctx.session.id, anchor, comment_attrs(ctx))

    detail
  end

  defp comment_attrs(ctx) do
    %{
      body: "Review this source",
      client_request_id: Ecto.UUID.generate(),
      mention_user_ids: [ctx.peer.user.id]
    }
  end

  defp set_private_mode(ctx, private?) do
    assert {:ok, session} = Ideation.get_session(ctx.facilitator, ctx.project.id, ctx.session.id)
    assert {:ok, _} = Ideation.set_private_mode(ctx.facilitator, ctx.project.id, session.id, session.revision, private?)
  end

  defp capture_queries(callback) do
    marker = make_ref()
    Process.put(marker, [])
    :ok = :telemetry.attach(marker, [:storyarn, :repo, :query], &capture_query/4, {self(), marker})

    try do
      {callback.(), Enum.reverse(Process.get(marker))}
    after
      :telemetry.detach(marker)
      Process.delete(marker)
    end
  end

  defp capture_query(_event, _measurements, %{query: query}, {pid, marker}) do
    if self() == pid, do: Process.put(marker, [query | Process.get(marker)])
  end
end
