defmodule StoryarnWeb.FlowLive.Helpers.CollaborationHelpers do
  @moduledoc """
  Collaboration helpers for the flow editor - handles presence, cursors, locks, and real-time changes.
  """

  import Phoenix.Component, only: [assign: 3]
  import Phoenix.LiveView, only: [push_event: 3]

  alias Storyarn.Collaboration

  @collab_toast_duration 3000

  @doc """
  Sets up collaboration subscriptions for a flow.
  """
  @spec setup_collaboration(Phoenix.LiveView.Socket.t(), map(), map()) :: :ok
  def setup_collaboration(socket, flow, user) do
    alias StoryarnWeb.Live.Shared.CollaborationHelpers, as: SharedCollab
    SharedCollab.setup(socket, {:flow, flow.id}, user, cursors: true, locks: true, changes: true)
  end

  @doc """
  Tears down collaboration subscriptions for a flow.
  Called before switching to a different flow via patch navigation.
  """
  @spec teardown_collaboration(integer(), integer()) :: :ok
  def teardown_collaboration(flow_id, user_id) do
    alias StoryarnWeb.Live.Shared.CollaborationHelpers, as: SharedCollab
    SharedCollab.teardown({:flow, flow_id}, user_id)
  end

  @doc """
  Gets the initial collaboration state (online users and node locks).
  """
  @spec get_initial_collab_state(Phoenix.LiveView.Socket.t(), map()) :: {list(), map()}
  def get_initial_collab_state(socket, flow) do
    alias StoryarnWeb.Live.Shared.CollaborationHelpers, as: SharedCollab
    SharedCollab.get_initial_state(socket, {:flow, flow.id})
  end

  @doc """
  Shows a collaboration toast notification.
  """
  @spec show_collab_toast(Phoenix.LiveView.Socket.t(), atom(), map()) ::
          Phoenix.LiveView.Socket.t()
  def show_collab_toast(socket, action, payload) do
    toast = %{
      action: action,
      user_email: payload[:user_email] || "Unknown",
      user_color: payload[:user_color] || "#666"
    }

    Process.send_after(self(), :clear_collab_toast, @collab_toast_duration)
    assign(socket, :collab_toast, toast)
  end

  @doc """
  Pushes a remote change event to the client.
  """
  @spec push_remote_change_event(Phoenix.LiveView.Socket.t(), atom(), map()) ::
          Phoenix.LiveView.Socket.t()
  def push_remote_change_event(socket, :node_added, payload) do
    push_event(socket, "node_added", payload.node_data)
  end

  def push_remote_change_event(socket, :flow_refresh, _payload) do
    push_event(socket, "flow_updated", socket.assigns.flow_data)
  end

  def push_remote_change_event(socket, :node_deleted, payload) do
    push_event(socket, "node_removed", %{id: payload.node_id})
  end

  def push_remote_change_event(socket, :node_restored, payload) do
    push_event(socket, "node_restored", %{
      node: payload.node_data,
      connections: payload.connections
    })
  end

  def push_remote_change_event(socket, :node_moved, payload) do
    push_event(socket, "node_moved", %{
      node_id: payload.node_id,
      x: payload.x,
      y: payload.y
    })
  end

  def push_remote_change_event(socket, :connection_added, payload) do
    push_event(socket, "connection_added", payload.connection_data)
  end

  def push_remote_change_event(socket, :node_updated, %{node_data: node_data} = payload) do
    push_event(socket, "node_updated", %{
      id: payload.node_id,
      data: node_data
    })
  end

  def push_remote_change_event(socket, :connection_deleted, payload) do
    push_event(socket, "connection_removed", %{
      source_node_id: payload.source_node_id,
      target_node_id: payload.target_node_id
    })
  end

  def push_remote_change_event(socket, _action, _payload), do: socket

  @doc """
  Broadcasts a change to other users in the flow.
  """
  @spec broadcast_change(Phoenix.LiveView.Socket.t(), atom(), map()) ::
          Phoenix.LiveView.Socket.t()
  def broadcast_change(socket, action, payload) do
    user = socket.assigns.current_scope.user

    full_payload =
      Map.merge(payload, %{
        user_id: user.id,
        user_email: user.email,
        user_color: Collaboration.user_color(user.id)
      })

    Collaboration.broadcast_change_from(
      self(),
      {:flow, socket.assigns.flow.id},
      action,
      full_payload
    )

    socket
  end

  @doc """
  Broadcasts a lock change (node locked/unlocked) to other users.
  """
  @spec broadcast_lock_change(Phoenix.LiveView.Socket.t(), atom(), any()) :: :ok
  def broadcast_lock_change(socket, action, node_id) do
    user = socket.assigns.current_scope.user

    payload = %{
      node_id: node_id,
      user_id: user.id,
      user_email: user.email,
      user_color: Collaboration.user_color(user.id)
    }

    Collaboration.broadcast_lock_change_from(
      self(),
      {:flow, socket.assigns.flow.id},
      action,
      payload
    )
  end

  @doc """
  Checks if a node is locked by another user.
  """
  @spec node_locked_by_other?(Phoenix.LiveView.Socket.t(), any()) :: boolean()
  def node_locked_by_other?(socket, node_id) do
    Collaboration.locked_by_other?(
      {:flow, socket.assigns.flow.id},
      node_id,
      socket.assigns.current_scope.user.id
    )
  end
end
