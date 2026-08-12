defmodule StoryarnWeb.Live.Hooks.Notifications do
  @moduledoc """
  Loads and refreshes the notification bell for the authenticated app shell.

  The hook is user-scoped rather than project-scoped, so it works unchanged
  across workspace, project, and settings navigation in the shared LiveView
  session. PostgreSQL remains the source of truth; PubSub only triggers a
  fresh authorized read.
  """

  import Phoenix.Component, only: [assign: 3]

  alias Storyarn.Notifications
  alias StoryarnWeb.Helpers.Authorize
  alias StoryarnWeb.Live.Shared.NotificationHelpers

  @events ~w(
    notification_filter_changed
    mark_notification_read
    mark_all_notifications_read
    refresh_notifications
  )
  @max_pg_bigint 9_223_372_036_854_775_807

  defguardp valid_notification_id(value)
            when is_integer(value) and value > 0 and value <= @max_pg_bigint

  def on_mount(:setup_notifications, _params, _session, socket) do
    scope = socket.assigns.current_scope

    if Phoenix.LiveView.connected?(socket) do
      :ok = Notifications.subscribe(scope)
    end

    socket =
      socket
      |> assign(:notification_filter, :all)
      |> Phoenix.LiveView.attach_hook(
        :notification_events,
        :handle_event,
        &handle_notification_event/3
      )
      |> Phoenix.LiveView.attach_hook(
        :notification_invalidations,
        :handle_info,
        &handle_notification_info/2
      )

    {:cont, socket}
  end

  defp handle_notification_event("notification_filter_changed", %{"filter" => filter}, socket)
       when filter in ~w(all unread) do
    filter = String.to_existing_atom(filter)
    {state, socket} = refresh(socket, filter)

    {:halt, state, socket}
  end

  defp handle_notification_event("refresh_notifications", %{"filter" => filter}, socket) when filter in ~w(all unread) do
    filter = String.to_existing_atom(filter)
    {state, socket} = refresh(socket, filter)

    {:halt, state, socket}
  end

  defp handle_notification_event("mark_notification_read", %{"id" => notification_id}, socket)
       when valid_notification_id(notification_id) do
    with :ok <- Authorize.authorize(socket, :manage_notifications),
         {:ok, _notification} <-
           Notifications.mark_read(socket.assigns.current_scope, notification_id) do
      {state, socket} = refresh(socket)
      {:halt, state, socket}
    else
      _error -> {:halt, %{error: "not_found"}, socket}
    end
  end

  defp handle_notification_event("mark_all_notifications_read", %{}, socket) do
    with :ok <- Authorize.authorize(socket, :manage_notifications),
         {:ok, _count} <- Notifications.mark_all_read(socket.assigns.current_scope) do
      {state, socket} = refresh(socket)
      {:halt, state, socket}
    else
      _error -> {:halt, %{error: "unavailable"}, socket}
    end
  end

  defp handle_notification_event(event, _params, socket) when event in @events do
    {:halt, %{error: "invalid_request"}, socket}
  end

  defp handle_notification_event(_event, _params, socket), do: {:cont, socket}

  defp handle_notification_info(:notifications_changed, socket) do
    {state, socket} = refresh(socket)
    {:halt, Phoenix.LiveView.push_event(socket, "notifications_updated", state)}
  end

  defp handle_notification_info(_message, socket), do: {:cont, socket}

  defp refresh(socket, filter \\ nil) do
    filter = filter || socket.assigns.notification_filter
    state = NotificationHelpers.client_state(socket.assigns.current_scope, filter)

    {state, assign(socket, :notification_filter, filter)}
  end
end
