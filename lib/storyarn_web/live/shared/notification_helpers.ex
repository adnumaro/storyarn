defmodule StoryarnWeb.Live.Shared.NotificationHelpers do
  @moduledoc """
  Builds the small, explicit notification read model consumed by the app shell.

  Notification schemas never cross the LiveVue boundary. This module exposes
  only localized-copy inputs after `Storyarn.Platform.Notifications` has filtered by
  current access.
  """

  alias Storyarn.Platform.Notifications

  @type filter :: :all | :unread

  @spec client_state(Storyarn.Accounts.Scope.t(), filter()) :: map()
  def client_state(scope, filter \\ :all) do
    notifications =
      Notifications.list_notifications(scope,
        unread_only: filter == :unread
      )

    %{
      filter: Atom.to_string(filter),
      items: Enum.map(notifications, &serialize/1),
      unreadCount: Notifications.unread_count(scope)
    }
  end

  defp serialize(%{id: _} = notification) do
    %{
      id: notification.id,
      kind: notification.kind,
      entityType: notification.entity_type,
      entityName: notification.entity_name,
      status: notification.status,
      createdAt: DateTime.to_iso8601(notification.inserted_at),
      readAt: iso8601(notification.read_at),
      actorName: actor_name(notification.actor),
      projectName: project_name(notification.project)
    }
  end

  defp actor_name(%{display_name: name}) when is_binary(name) and name != "", do: name
  defp actor_name(_actor), do: nil

  defp project_name(%{name: name}) when is_binary(name), do: name
  defp project_name(_project), do: nil

  defp iso8601(%DateTime{} = datetime), do: DateTime.to_iso8601(datetime)
  defp iso8601(nil), do: nil
end
