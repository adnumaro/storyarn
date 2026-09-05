defmodule StoryarnWeb.Live.Shared.NotificationHelpers do
  @moduledoc """
  Builds the small, explicit notification read model consumed by the app shell.

  Notification schemas never cross the LiveVue boundary. This module exposes
  only localized-copy inputs after `Storyarn.Platform` has filtered by
  current access.
  """

  use StoryarnWeb, :verified_routes

  alias Storyarn.Platform
  alias Storyarn.Projects

  @type filter :: :all | :unread

  @spec client_state(Storyarn.Accounts.Scope.t(), filter()) :: map()
  def client_state(scope, filter \\ :all) do
    notifications =
      Platform.list_notifications(scope,
        unread_only: filter == :unread
      )

    comment_ids = for %{entity_type: "comment", entity_id: id} <- notifications, do: id
    destinations = Projects.comment_destinations(scope, comment_ids)

    %{
      filter: Atom.to_string(filter),
      items: Enum.map(notifications, &serialize(&1, destinations)),
      unreadCount: Platform.unread_notification_count(scope)
    }
  end

  defp serialize(%{id: _} = notification, destinations) do
    %{
      id: notification.id,
      kind: notification.kind,
      entityType: notification.entity_type,
      entityName: notification.entity_name,
      status: notification.status,
      createdAt: DateTime.to_iso8601(notification.inserted_at),
      readAt: iso8601(notification.read_at),
      actorName: actor_name(notification.actor),
      projectName: project_name(notification.project),
      href: destination(notification, destinations)
    }
  end

  defp destination(%{entity_type: "comment", entity_id: comment_id, project_id: project_id}, destinations) do
    case destinations[{project_id, comment_id}] do
      nil ->
        nil

      %{surface: "flow"} = destination ->
        ~p"/workspaces/#{destination.workspace_slug}/projects/#{destination.project_slug}/flows/#{destination.flow_id}?#{%{thread: destination.thread_id}}"

      %{surface: "scene"} = destination ->
        ~p"/workspaces/#{destination.workspace_slug}/projects/#{destination.project_slug}/scenes/#{destination.scene_id}?#{%{thread: destination.thread_id}}"
    end
  end

  defp destination(_notification, _scope), do: nil

  defp actor_name(%{display_name: name}) when is_binary(name) and name != "", do: name
  defp actor_name(_actor), do: nil

  defp project_name(%{name: name}) when is_binary(name), do: name
  defp project_name(_project), do: nil

  defp iso8601(%DateTime{} = datetime), do: DateTime.to_iso8601(datetime)
  defp iso8601(nil), do: nil
end
