defmodule StoryarnWeb.Live.Shared.NotificationHelpers do
  @moduledoc """
  Builds the small, explicit notification read model consumed by the app shell.

  Notification schemas never cross the LiveVue boundary. This module exposes
  only localized-copy inputs after `Storyarn.NotificationInbox` has filtered by
  current access.
  """

  use StoryarnWeb, :verified_routes

  alias Storyarn.NotificationInbox
  alias Storyarn.Projects
  alias StoryarnWeb.Live.Shared.DecisionNotices

  @type filter :: :all | :unread

  @spec client_state(Storyarn.Accounts.Scope.t(), filter()) :: map()
  def client_state(scope, filter \\ :all) do
    notifications =
      NotificationInbox.list_notifications(scope,
        unread_only: filter == :unread
      )

    comment_ids = for %{entity_type: "comment", entity_id: id} <- notifications, do: id

    decision_projects = decision_destinations(scope, notifications)
    destinations = Map.merge(Projects.comment_destinations(scope, comment_ids), decision_projects)

    cards =
      DecisionNotices.index(
        scope,
        notifications,
        Map.new(decision_projects, fn {{:decision_project, id}, slugs} -> {id, slugs} end)
      )

    %{
      filter: Atom.to_string(filter),
      items: Enum.map(notifications, &serialize(&1, destinations, cards)),
      unreadCount: NotificationInbox.unread_notification_count(scope)
    }
  end

  defp serialize(%{id: _} = notification, destinations, cards) do
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
      href: destination(notification, destinations),
      attachment: DecisionNotices.attachment(notification, cards)
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

      %{surface: "sheet"} = destination ->
        ~p"/workspaces/#{destination.workspace_slug}/projects/#{destination.project_slug}/sheets/#{destination.sheet_id}?#{%{thread: destination.thread_id}}"

      %{surface: "brainstorming"} = destination ->
        ~p"/workspaces/#{destination.workspace_slug}/projects/#{destination.project_slug}/brainstorming/#{destination.session_id}?#{%{thread: destination.thread_id}}"
    end
  end

  defp destination(%{entity_type: "decision", entity_id: id, project_id: project_id}, destinations) do
    case destinations[{:decision_project, project_id}] do
      %{workspace_slug: workspace, project_slug: project} ->
        ~p"/workspaces/#{workspace}/projects/#{project}/brainstorming?#{%{decision: id}}"

      nil ->
        nil
    end
  end

  defp destination(_notification, _scope), do: nil

  # A decision link opens its session through the project's brainstorming route,
  # which rechecks access before naming the session.
  defp decision_destinations(scope, notifications) do
    notifications
    |> Enum.flat_map(fn
      %{entity_type: "decision", project_id: project_id} -> [project_id]
      _other -> []
    end)
    |> Enum.uniq()
    |> Enum.flat_map(fn project_id ->
      case Projects.reload_project(scope, project_id) do
        {:ok, project, _membership} ->
          [{{:decision_project, project_id}, %{workspace_slug: project.workspace.slug, project_slug: project.slug}}]

        {:error, _reason} ->
          []
      end
    end)
    |> Map.new()
  end

  defp actor_name(%{display_name: name}) when is_binary(name) and name != "", do: name
  defp actor_name(_actor), do: nil

  defp project_name(%{name: name}) when is_binary(name), do: name
  defp project_name(_project), do: nil

  defp iso8601(%DateTime{} = datetime), do: DateTime.to_iso8601(datetime)
  defp iso8601(nil), do: nil
end
