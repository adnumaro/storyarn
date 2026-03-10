defmodule Storyarn.Collaboration do
  @moduledoc """
  The Collaboration context.

  Provides real-time collaboration features for all editors:
  - Presence tracking (who's online)
  - Cursor sharing (see other users' cursors)
  - Entity locking (prevent simultaneous edits)
  - Change notifications (see remote changes)

  All functions accept an `editor_scope` tuple `{type, id}` to identify the
  editor instance. For backward compatibility, bare integers are treated as
  `{:flow, id}`.

  ## Editor scopes

      {:flow, flow_id}
      {:sheet, sheet_id}
      {:scene, scene_id}
      {:screenplay, screenplay_id}

  This module serves as a facade, delegating to specialized submodules:
  - `Colors` - Deterministic user color assignment
  - `Presence` - Phoenix.Presence for online users
  - `Locks` - GenServer for entity locking
  - `CursorTracker` - PubSub cursor broadcasting
  """

  alias Phoenix.PubSub
  alias Storyarn.Collaboration.{Colors, CursorTracker, Locks, Presence}

  @type editor_scope ::
          {:flow, integer()}
          | {:sheet, integer()}
          | {:scene, integer()}
          | {:screenplay, integer()}

  # =============================================================================
  # Scope normalization (backward compat)
  # =============================================================================

  defp normalize_scope({_type, _id} = scope), do: scope
  defp normalize_scope(id) when is_integer(id), do: {:flow, id}

  # =============================================================================
  # Colors
  # =============================================================================

  @doc """
  Returns a deterministic color for a user based on their ID.
  Uses a 12-color palette designed for visibility.
  """
  @spec user_color(integer()) :: String.t()
  defdelegate user_color(user_id), to: Colors, as: :for_user

  # =============================================================================
  # Presence
  # =============================================================================

  @doc """
  Tracks a user's presence in an editor.
  Should be called when user mounts the LiveView.
  """
  def track_presence(pid, scope, user) do
    topic = Presence.topic(normalize_scope(scope))
    Presence.track_user(pid, topic, user)
  end

  @doc """
  Subscribes to presence updates for an editor.
  Subscribes to the proxy topic for efficient join/leave events.
  """
  def subscribe_presence(scope) do
    topic = Presence.topic(normalize_scope(scope))
    PubSub.subscribe(Storyarn.PubSub, "proxy:#{topic}")
  end

  @doc """
  Returns a list of users currently in an editor.
  """
  def list_online_users(scope) do
    topic = Presence.topic(normalize_scope(scope))
    Presence.list_users(topic)
  end

  # =============================================================================
  # Project-level Presence
  # =============================================================================

  @doc """
  Tracks a user's presence at the project level.
  Used to show "User A is editing Sheet 3" in the project sidebar.
  """
  def track_project_presence(pid, project_id, user, meta \\ %{}) do
    topic = project_presence_topic(project_id)
    Presence.track_user(pid, topic, user, meta)
  end

  @doc """
  Updates a user's project-level presence metadata.
  Call when the user navigates to a different entity within the same editor.
  """
  def update_project_presence(project_id, user_id, meta_update) do
    topic = project_presence_topic(project_id)

    Presence.update(self(), topic, user_id, fn metas ->
      Map.merge(metas, meta_update)
    end)
  end

  @doc """
  Subscribes to project-level presence updates.
  """
  def subscribe_project_presence(project_id) do
    topic = project_presence_topic(project_id)
    PubSub.subscribe(Storyarn.PubSub, "proxy:#{topic}")
  end

  @doc """
  Returns a list of users currently in a project.
  """
  def list_project_users(project_id) do
    topic = project_presence_topic(project_id)
    Presence.list_users(topic)
  end

  # =============================================================================
  # Cursors
  # =============================================================================

  @doc """
  Broadcasts a cursor position update to all other users in an editor.
  Uses `broadcast_from` so the sender does not receive their own cursor.
  """
  def broadcast_cursor(scope, user, x, y) do
    CursorTracker.broadcast_cursor(normalize_scope(scope), user, x, y)
  end

  @doc """
  Broadcasts that a user's cursor has left the editor.
  """
  def broadcast_cursor_leave(scope, user_id) do
    CursorTracker.broadcast_cursor_leave(normalize_scope(scope), user_id)
  end

  @doc """
  Subscribes to cursor updates for an editor.
  """
  def subscribe_cursors(scope) do
    CursorTracker.subscribe(normalize_scope(scope))
  end

  @doc """
  Unsubscribes from cursor updates for an editor.
  """
  def unsubscribe_cursors(scope) do
    CursorTracker.unsubscribe(normalize_scope(scope))
  end

  # =============================================================================
  # Entity Locking
  # =============================================================================

  @doc """
  Attempts to acquire a lock on an entity.
  Returns {:ok, lock_info} if successful, {:error, :already_locked, lock_info} if locked by another.
  """
  def acquire_lock(scope, entity_id, user) do
    Locks.acquire(normalize_scope(scope), entity_id, user)
  end

  @doc """
  Releases a lock on an entity. Only the lock holder can release.
  """
  def release_lock(scope, entity_id, user_id) do
    Locks.release(normalize_scope(scope), entity_id, user_id)
  end

  @doc """
  Releases all locks held by a user in an editor scope.
  Called when user disconnects.
  """
  def release_all_locks(scope, user_id) do
    Locks.release_all(normalize_scope(scope), user_id)
  end

  @doc """
  Refreshes a lock's timeout (heartbeat).
  """
  def refresh_lock(scope, entity_id, user_id) do
    Locks.refresh(normalize_scope(scope), entity_id, user_id)
  end

  @doc """
  Gets the current lock holder for an entity, if any.
  """
  def get_lock(scope, entity_id) do
    Locks.get_lock(normalize_scope(scope), entity_id)
  end

  @doc """
  Gets all locks for an editor scope.
  """
  def list_locks(scope) do
    Locks.list_locks(normalize_scope(scope))
  end

  @doc """
  Checks if an entity is locked by a different user.
  """
  def locked_by_other?(scope, entity_id, user_id) do
    Locks.locked_by_other?(normalize_scope(scope), entity_id, user_id)
  end

  # =============================================================================
  # Change Notifications
  # =============================================================================

  @doc """
  Broadcasts a change notification to all subscribers (including sender).
  Prefer `broadcast_change_from/4` in event handlers to avoid echo.
  """
  def broadcast_change(scope, action, payload) do
    PubSub.broadcast(
      Storyarn.PubSub,
      changes_topic(normalize_scope(scope)),
      {:remote_change, action, payload}
    )
  end

  @doc """
  Broadcasts a change notification to all subscribers except the sender.
  Use this in handle_event to avoid receiving your own changes back.
  """
  def broadcast_change_from(pid, scope, action, payload) do
    PubSub.broadcast_from(
      Storyarn.PubSub,
      pid,
      changes_topic(normalize_scope(scope)),
      {:remote_change, action, payload}
    )
  end

  @doc """
  Subscribes to change notifications for an editor.
  """
  def subscribe_changes(scope) do
    PubSub.subscribe(Storyarn.PubSub, changes_topic(normalize_scope(scope)))
  end

  @doc """
  Broadcasts a lock state change to all subscribers (including sender).
  Prefer `broadcast_lock_change_from/4` in event handlers.
  """
  def broadcast_lock_change(scope, action, payload) do
    PubSub.broadcast(
      Storyarn.PubSub,
      locks_topic(normalize_scope(scope)),
      {:lock_change, action, payload}
    )
  end

  @doc """
  Broadcasts a lock state change to all subscribers except the sender.
  """
  def broadcast_lock_change_from(pid, scope, action, payload) do
    PubSub.broadcast_from(
      Storyarn.PubSub,
      pid,
      locks_topic(normalize_scope(scope)),
      {:lock_change, action, payload}
    )
  end

  @doc """
  Subscribes to lock state changes for an editor.
  """
  def subscribe_locks(scope) do
    PubSub.subscribe(Storyarn.PubSub, locks_topic(normalize_scope(scope)))
  end

  # =============================================================================
  # Topics
  # =============================================================================

  @doc false
  def changes_topic({type, id}), do: "#{type}:#{id}:changes"

  @doc false
  def locks_topic({type, id}), do: "#{type}:#{id}:locks"

  @doc false
  def cursors_topic({type, id}), do: "#{type}:#{id}:cursors"

  @doc """
  Returns the topic for project-level presence.
  """
  def project_presence_topic(project_id), do: "project:#{project_id}:presence"

  # =============================================================================
  # Dashboard Invalidation
  # =============================================================================

  @doc """
  Subscribes to dashboard invalidation events for a project.
  """
  def subscribe_dashboard(project_id) do
    PubSub.subscribe(Storyarn.PubSub, dashboard_topic(project_id))
  end

  @doc """
  Broadcasts a dashboard invalidation event for a project.
  Also directly invalidates the ETS cache.

  `scope` is an atom like `:flows`, `:sheets`, or `:scenes`.
  """
  def broadcast_dashboard_change(project_id, scope) do
    Storyarn.Dashboards.Cache.invalidate(project_id)

    PubSub.broadcast(
      Storyarn.PubSub,
      dashboard_topic(project_id),
      {:dashboard_invalidate, scope}
    )
  end

  @doc false
  def dashboard_topic(project_id), do: "project:#{project_id}:dashboard"
end
