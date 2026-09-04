defmodule StoryarnWeb.Live.Hooks.NotificationsTest do
  use StoryarnWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Storyarn.AccountsFixtures
  import Storyarn.ProjectsFixtures
  import Storyarn.WorkspacesFixtures

  alias Storyarn.Platform.Notifications
  alias Storyarn.Platform.Notifications.Notification
  alias Storyarn.Repo

  setup %{conn: conn} do
    user = user_fixture()

    %{
      conn: log_in_user(conn, user),
      scope: user_scope_fixture(user),
      user: user,
      workspace: workspace_fixture(user)
    }
  end

  test "serves the current notification state on explicit refresh", %{
    conn: conn,
    scope: scope,
    workspace: workspace
  } do
    notification = notification_fixture(scope, "initial-center")

    {:ok, view, _html} = live(conn, ~p"/workspaces/#{workspace.slug}")
    render_hook(view, "refresh_notifications", %{"filter" => "unread"})
    send(view.pid, :notifications_changed)

    notification_id = notification.id

    assert_push_event(view, "notifications_updated", %{
      filter: "unread",
      items: [%{id: ^notification_id, readAt: nil}],
      unreadCount: 1
    })
  end

  test "keeps the unread filter across notification invalidations", %{
    conn: conn,
    scope: scope,
    workspace: workspace
  } do
    read = notification_fixture(scope, "filter-read")
    unread = notification_fixture(scope, "filter-unread")
    assert {:ok, _notification} = Notifications.mark_read(scope, read.id)

    {:ok, view, _html} = live(conn, ~p"/workspaces/#{workspace.slug}")

    render_hook(view, "notification_filter_changed", %{"filter" => "unread"})
    send(view.pid, :notifications_changed)

    unread_id = unread.id

    assert_push_event(view, "notifications_updated", %{
      filter: "unread",
      items: [%{id: ^unread_id, readAt: nil}],
      unreadCount: 1
    })
  end

  test "marks one notification and then all remaining notifications as read", %{
    conn: conn,
    scope: scope,
    workspace: workspace
  } do
    first = notification_fixture(scope, "mark-one")
    second = notification_fixture(scope, "mark-all")

    {:ok, view, _html} = live(conn, ~p"/workspaces/#{workspace.slug}")

    render_hook(view, "mark_notification_read", %{"id" => first.id})

    assert Repo.get!(Notification, first.id).read_at
    assert is_nil(Repo.get!(Notification, second.id).read_at)
    assert Notifications.unread_count(scope) == 1

    render_hook(view, "mark_all_notifications_read", %{})

    assert Repo.get!(Notification, second.id).read_at
    assert Notifications.unread_count(scope) == 0
  end

  test "rejects invalid filter and notification id payloads without changing state", %{
    conn: conn,
    scope: scope,
    workspace: workspace
  } do
    notification = notification_fixture(scope, "invalid-payload")

    {:ok, view, _html} = live(conn, ~p"/workspaces/#{workspace.slug}")

    render_hook(view, "notification_filter_changed", %{"filter" => "archived"})
    render_hook(view, "mark_notification_read", %{"id" => Integer.to_string(notification.id)})

    assert is_nil(Repo.get!(Notification, notification.id).read_at)

    send(view.pid, :notifications_changed)
    notification_id = notification.id

    assert_push_event(view, "notifications_updated", %{
      filter: "all",
      items: [%{id: ^notification_id, readAt: nil}],
      unreadCount: 1
    })
  end

  test "refreshes the authorized inbox when a mark-read target lost access", %{
    conn: conn,
    scope: scope,
    user: user,
    workspace: workspace
  } do
    project_owner = user_fixture()
    project = project_fixture(project_owner)
    membership = membership_fixture(project, user, "viewer")

    assert {:ok, {:created, notification}} =
             Notifications.deliver(scope, nil, project, %{
               kind: "async_operation",
               entity_type: "project_snapshot",
               entity_id: System.unique_integer([:positive]),
               status: "success",
               dedupe_key: "notifications-hook:revoked-access"
             })

    {:ok, view, _html} = live(conn, ~p"/workspaces/#{workspace.slug}")
    render_hook(view, "refresh_notifications", %{"filter" => "unread"})
    assert_reply(view, %{items: [_notification], unreadCount: 1})

    Repo.delete!(membership)
    render_hook(view, "mark_notification_read", %{"id" => notification.id})

    assert_reply(view, %{filter: "unread", items: [], unreadCount: 0})
    assert is_nil(Repo.get!(Notification, notification.id).read_at)
  end

  test "subscribes the LiveView and pushes refreshed state after a PubSub invalidation", %{
    conn: conn,
    scope: scope,
    user: user,
    workspace: workspace
  } do
    {:ok, view, _html} = live(conn, ~p"/workspaces/#{workspace.slug}")
    notification = notification_fixture(scope, "pubsub-refresh")

    :ok =
      Phoenix.PubSub.broadcast(
        Storyarn.PubSub,
        Notifications.user_topic(user.id),
        :notifications_changed
      )

    notification_id = notification.id

    assert_push_event(view, "notifications_updated", %{
      filter: "all",
      items: [%{id: ^notification_id, readAt: nil}],
      unreadCount: 1
    })
  end

  defp notification_fixture(scope, suffix) do
    {:ok, {:created, notification}} =
      Notifications.deliver(scope, nil, %{
        kind: "async_operation",
        entity_type: "template_install",
        entity_id: System.unique_integer([:positive]),
        status: "success",
        dedupe_key: "notifications-hook:#{suffix}:#{System.unique_integer([:positive])}"
      })

    notification
  end
end
