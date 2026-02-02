defmodule Storyarn.Collaboration do
  @moduledoc """
  The Collaboration context.

  Provides real-time collaboration features for the Flow Editor:
  - Presence tracking (who's online)
  - Cursor sharing (see other users' cursors)
  - Node locking (prevent simultaneous edits)
  - Change notifications (see remote changes)

  This module serves as a facade, delegating to specialized submodules:
  - `Colors` - Deterministic user color assignment
  - `Presence` - Phoenix.Presence for online users
  - `Locks` - GenServer for node locking
  - `CursorTracker` - PubSub cursor broadcasting
  """

  alias Phoenix.PubSub
  alias Storyarn.Collaboration.{Colors, CursorTracker, Locks, Presence}

  # =============================================================================
  # Colors
  # =============================================================================

  @doc """
  Returns a deterministic color for a user based on their ID.
  Uses a 12-color palette designed for visibility.
  """
  @spec user_color(integer()) :: String.t()
  defdelegate user_color(user_id), to: Colors, as: :for_user

  @doc """
  Returns a lighter version of the user's color.
  """
  @spec user_color_light(integer()) :: String.t()
  defdelegate user_color_light(user_id), to: Colors, as: :for_user_light

  # =============================================================================
  # Presence
  # =============================================================================

  @doc """
  Tracks a user's presence in a flow.
  Should be called when user mounts the flow LiveView.
  """
  @spec track_presence(pid(), integer(), Storyarn.Accounts.User.t()) ::
          {:ok, binary()} | {:error, term()}
  def track_presence(pid, flow_id, user) do
    topic = Presence.flow_topic(flow_id)
    Presence.track_user(pid, topic, user)
  end

  @doc """
  Subscribes to presence updates for a flow.
  """
  @spec subscribe_presence(integer()) :: :ok | {:error, term()}
  def subscribe_presence(flow_id) do
    topic = Presence.flow_topic(flow_id)
    PubSub.subscribe(Storyarn.PubSub, topic)
  end

  @doc """
  Returns a list of users currently in a flow.
  """
  @spec list_online_users(integer()) :: [map()]
  def list_online_users(flow_id) do
    topic = Presence.flow_topic(flow_id)
    Presence.list_users(topic)
  end

  # =============================================================================
  # Cursors
  # =============================================================================

  @doc """
  Broadcasts a cursor position update to all users in a flow.
  """
  @spec broadcast_cursor(integer(), Storyarn.Accounts.User.t(), float(), float()) :: :ok
  defdelegate broadcast_cursor(flow_id, user, x, y), to: CursorTracker

  @doc """
  Broadcasts that a user's cursor has left the flow.
  """
  @spec broadcast_cursor_leave(integer(), integer()) :: :ok
  defdelegate broadcast_cursor_leave(flow_id, user_id), to: CursorTracker

  @doc """
  Subscribes to cursor updates for a flow.
  """
  @spec subscribe_cursors(integer()) :: :ok | {:error, term()}
  defdelegate subscribe_cursors(flow_id), to: CursorTracker, as: :subscribe

  @doc """
  Unsubscribes from cursor updates for a flow.
  """
  @spec unsubscribe_cursors(integer()) :: :ok
  defdelegate unsubscribe_cursors(flow_id), to: CursorTracker, as: :unsubscribe

  # =============================================================================
  # Node Locking
  # =============================================================================

  @doc """
  Attempts to acquire a lock on a node.
  Returns {:ok, lock_info} if successful, {:error, :already_locked, lock_info} if locked by another.
  """
  @spec acquire_lock(integer(), integer(), map()) ::
          {:ok, map()} | {:error, :already_locked, map()}
  defdelegate acquire_lock(flow_id, node_id, user), to: Locks, as: :acquire

  @doc """
  Releases a lock on a node. Only the lock holder can release.
  """
  @spec release_lock(integer(), integer(), integer()) :: :ok | {:error, :not_lock_holder}
  defdelegate release_lock(flow_id, node_id, user_id), to: Locks, as: :release

  @doc """
  Releases all locks held by a user in a flow.
  Called when user disconnects.
  """
  @spec release_all_locks(integer(), integer()) :: :ok
  defdelegate release_all_locks(flow_id, user_id), to: Locks, as: :release_all

  @doc """
  Refreshes a lock's timeout (heartbeat).
  """
  @spec refresh_lock(integer(), integer(), integer()) :: :ok | {:error, :not_lock_holder}
  defdelegate refresh_lock(flow_id, node_id, user_id), to: Locks, as: :refresh

  @doc """
  Gets the current lock holder for a node, if any.
  """
  @spec get_lock(integer(), integer()) :: {:ok, map()} | {:error, :not_locked}
  defdelegate get_lock(flow_id, node_id), to: Locks

  @doc """
  Gets all locks for a flow.
  """
  @spec list_locks(integer()) :: %{integer() => map()}
  defdelegate list_locks(flow_id), to: Locks

  @doc """
  Checks if a node is locked by a different user.
  """
  @spec locked_by_other?(integer(), integer(), integer()) :: boolean()
  defdelegate locked_by_other?(flow_id, node_id, user_id), to: Locks

  # =============================================================================
  # Change Notifications
  # =============================================================================

  @doc """
  Broadcasts a change notification to all users in a flow.
  """
  @spec broadcast_change(integer(), atom(), map()) :: :ok
  def broadcast_change(flow_id, action, payload) do
    PubSub.broadcast(Storyarn.PubSub, changes_topic(flow_id), {:remote_change, action, payload})
  end

  @doc """
  Subscribes to change notifications for a flow.
  """
  @spec subscribe_changes(integer()) :: :ok | {:error, term()}
  def subscribe_changes(flow_id) do
    PubSub.subscribe(Storyarn.PubSub, changes_topic(flow_id))
  end

  @doc """
  Broadcasts a lock state change to all users in a flow.
  """
  @spec broadcast_lock_change(integer(), atom(), map()) :: :ok
  def broadcast_lock_change(flow_id, action, payload) do
    PubSub.broadcast(Storyarn.PubSub, locks_topic(flow_id), {:lock_change, action, payload})
  end

  @doc """
  Subscribes to lock state changes for a flow.
  """
  @spec subscribe_locks(integer()) :: :ok | {:error, term()}
  def subscribe_locks(flow_id) do
    PubSub.subscribe(Storyarn.PubSub, locks_topic(flow_id))
  end

  # =============================================================================
  # Topics
  # =============================================================================

  @doc """
  Returns the topic for a flow's change notifications.
  """
  @spec changes_topic(integer()) :: String.t()
  def changes_topic(flow_id) do
    "flow:#{flow_id}:changes"
  end

  @doc """
  Returns the topic for a flow's lock notifications.
  """
  @spec locks_topic(integer()) :: String.t()
  def locks_topic(flow_id) do
    "flow:#{flow_id}:locks"
  end
end
