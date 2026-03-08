defmodule StoryarnWeb.Live.Shared.CollaborationHelpers do
  @moduledoc """
  Shared collaboration helpers for all editors.

  Handles presence setup/teardown, change subscriptions, lock subscriptions,
  and broadcasting. Each editor LiveView calls these functions with their
  editor scope tuple.

  ## Usage

      alias StoryarnWeb.Live.Shared.CollaborationHelpers, as: Collab

      # In mount (after loading entity):
      scope = {:sheet, sheet.id}
      Collab.setup(socket, scope, user)
      {online_users, locks} = Collab.get_initial_state(socket, scope)

      # In terminate:
      Collab.teardown(scope, user_id)

  ## Required assigns

  After setup, the socket should have:
  - `:collab_scope` — the editor scope tuple
  - `:online_users` — list of online user presence maps
  """

  import Phoenix.Component, only: [assign: 3]

  alias Storyarn.Collaboration
  alias Storyarn.Collaboration.Presence

  @doc """
  Sets up collaboration subscriptions for an editor.
  Call in mount only when `connected?(socket)` is true.

  ## Options

  - `:cursors` - subscribe to cursor updates (default: false)
  - `:locks` - subscribe to lock changes (default: true)
  - `:changes` - subscribe to change notifications (default: true)
  """
  def setup(socket, scope, user, opts \\ []) do
    if Phoenix.LiveView.connected?(socket) do
      # Presence: subscribe to proxy topic + track
      Collaboration.subscribe_presence(scope)
      Collaboration.track_presence(self(), scope, user)

      if Keyword.get(opts, :changes, true) do
        Collaboration.subscribe_changes(scope)
      end

      if Keyword.get(opts, :locks, true) do
        Collaboration.subscribe_locks(scope)
      end

      if Keyword.get(opts, :cursors, false) do
        Collaboration.subscribe_cursors(scope)
      end
    end

    :ok
  end

  @doc """
  Tears down collaboration subscriptions.
  Call before switching entities (patch navigation) or in terminate/2.
  """
  def teardown(scope, user_id) do
    topic = Presence.topic(scope)

    # Unsubscribe from all topics
    Phoenix.PubSub.unsubscribe(Storyarn.PubSub, "proxy:#{topic}")
    Phoenix.PubSub.unsubscribe(Storyarn.PubSub, Collaboration.changes_topic(scope))
    Phoenix.PubSub.unsubscribe(Storyarn.PubSub, Collaboration.locks_topic(scope))
    Phoenix.PubSub.unsubscribe(Storyarn.PubSub, Collaboration.cursors_topic(scope))

    # Untrack presence (safety — LiveView process death also untracks)
    Presence.untrack(self(), topic, user_id)

    # Release any held locks
    Collaboration.release_all_locks(scope, user_id)

    :ok
  end

  @doc """
  Gets initial collaboration state (online users + locks).
  Returns `{[], %{}}` when not connected (static render).
  """
  def get_initial_state(socket, scope) do
    if Phoenix.LiveView.connected?(socket) do
      {Collaboration.list_online_users(scope), Collaboration.list_locks(scope)}
    else
      {[], %{}}
    end
  end

  @doc """
  Broadcasts a change from the current process (no echo).
  Automatically enriches payload with user info.
  Returns the socket for piping.
  """
  def broadcast_change(socket, scope, action, payload) do
    user = socket.assigns.current_scope.user

    full_payload =
      Map.merge(payload, %{
        user_id: user.id,
        user_email: user.email,
        user_color: Collaboration.user_color(user.id)
      })

    Collaboration.broadcast_change_from(self(), scope, action, full_payload)
    socket
  end

  @doc """
  Broadcasts a lock state change from the current process (no echo).
  Returns the socket for piping.
  """
  def broadcast_lock_change(socket, scope, action, entity_id) do
    user = socket.assigns.current_scope.user

    payload = %{
      entity_id: entity_id,
      user_id: user.id,
      user_email: user.email,
      user_color: Collaboration.user_color(user.id)
    }

    Collaboration.broadcast_lock_change_from(self(), scope, action, payload)
    socket
  end

  # =============================================================================
  # Presence event handlers
  # =============================================================================

  @doc """
  Handles a presence join event. Updates the online_users assign.
  Call from handle_info matching `{Storyarn.Collaboration.Presence, {:join, presence}}`.
  """
  def handle_presence_join(socket, presence) do
    user_meta = presence_to_user_meta(presence)

    online_users =
      socket.assigns.online_users
      |> Enum.reject(&(&1.user_id == user_meta.user_id))
      |> List.insert_at(-1, user_meta)

    {:noreply, assign(socket, :online_users, online_users)}
  end

  @doc """
  Handles a presence leave event. Updates the online_users assign.
  Call from handle_info matching `{Storyarn.Collaboration.Presence, {:leave, presence}}`.
  """
  def handle_presence_leave(socket, %{metas: %{metas: []}} = presence) do
    user_id = presence.id
    online_users = Enum.reject(socket.assigns.online_users, &(&1.user_id == user_id))
    {:noreply, assign(socket, :online_users, online_users)}
  end

  def handle_presence_leave(socket, _presence) do
    # User still connected on another tab — no change
    {:noreply, socket}
  end

  defp presence_to_user_meta(%{user: user}) do
    %{
      user_id: user.id,
      email: user.email,
      display_name: user[:display_name],
      avatar_url: user[:avatar_url],
      color: user[:color]
    }
  end
end
