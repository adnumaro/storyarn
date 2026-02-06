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
    if Phoenix.LiveView.connected?(socket) do
      Collaboration.subscribe_presence(flow.id)
      Collaboration.subscribe_cursors(flow.id)
      Collaboration.subscribe_locks(flow.id)
      Collaboration.subscribe_changes(flow.id)
      Collaboration.track_presence(self(), flow.id, user)
    end

    :ok
  end

  @doc """
  Gets the initial collaboration state (online users and node locks).
  """
  @spec get_initial_collab_state(Phoenix.LiveView.Socket.t(), map()) :: {list(), map()}
  def get_initial_collab_state(socket, flow) do
    if Phoenix.LiveView.connected?(socket) do
      {Collaboration.list_online_users(flow.id), Collaboration.list_locks(flow.id)}
    else
      {[], %{}}
    end
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

  def push_remote_change_event(socket, :node_updated, payload) do
    push_event(socket, "node_updated", %{id: payload.node_id, data: payload.node_data})
  end

  def push_remote_change_event(socket, :node_moved, _payload) do
    # Node position is part of flow_data which is already updated
    socket
  end

  def push_remote_change_event(socket, :connection_added, payload) do
    push_event(socket, "connection_added", payload.connection_data)
  end

  def push_remote_change_event(socket, :connection_deleted, payload) do
    push_event(socket, "connection_removed", %{
      source_node_id: payload.source_node_id,
      target_node_id: payload.target_node_id
    })
  end

  def push_remote_change_event(socket, :connection_updated, payload) do
    push_event(socket, "connection_updated", %{
      id: payload.connection_id,
      label: payload.label,
      condition: payload.condition
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

    Collaboration.broadcast_change(socket.assigns.flow.id, action, full_payload)
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

    Collaboration.broadcast_lock_change(socket.assigns.flow.id, action, payload)
  end

  @doc """
  Checks if a node is locked by another user.
  """
  @spec node_locked_by_other?(Phoenix.LiveView.Socket.t(), any()) :: boolean()
  def node_locked_by_other?(socket, node_id) do
    Collaboration.locked_by_other?(
      socket.assigns.flow.id,
      node_id,
      socket.assigns.current_scope.user.id
    )
  end
end
