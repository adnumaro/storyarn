defmodule StoryarnWeb.FlowLive.Handlers.CollaborationEventHandlers do
  @moduledoc """
  Handles collaboration-related events and info messages for the flow editor.

  Responsible for: cursor_moved event, presence join/leave, cursor_update/leave,
  lock_change, remote_change, and clear_collab_toast info messages.
  Returns `{:noreply, socket}`.
  """

  import Phoenix.Component, only: [assign: 3]
  import Phoenix.LiveView, only: [push_event: 3]

  alias Storyarn.Collaboration
  alias Storyarn.Flows
  alias StoryarnWeb.FlowLive.Helpers.CollaborationHelpers

  @spec handle_cursor_moved(map(), Phoenix.LiveView.Socket.t()) ::
          {:noreply, Phoenix.LiveView.Socket.t()}
  def handle_cursor_moved(%{"x" => x, "y" => y}, socket) do
    user = socket.assigns.current_scope.user
    Collaboration.broadcast_cursor({:flow, socket.assigns.flow.id}, user, x, y)
    {:noreply, socket}
  end

  alias StoryarnWeb.Live.Shared.CollaborationHelpers, as: SharedCollab

  @spec handle_presence_event(tuple(), Phoenix.LiveView.Socket.t()) ::
          {:noreply, Phoenix.LiveView.Socket.t()}
  def handle_presence_event({:join, presence}, socket) do
    SharedCollab.handle_presence_join(socket, presence)
  end

  def handle_presence_event({:leave, presence}, socket) do
    SharedCollab.handle_presence_leave(socket, presence)
  end

  @spec handle_cursor_update(map(), Phoenix.LiveView.Socket.t()) ::
          {:noreply, Phoenix.LiveView.Socket.t()}
  def handle_cursor_update(cursor_data, socket) do
    if cursor_data.user_id == socket.assigns.current_scope.user.id do
      {:noreply, socket}
    else
      remote_cursors = Map.put(socket.assigns.remote_cursors, cursor_data.user_id, cursor_data)

      {:noreply,
       socket
       |> assign(:remote_cursors, remote_cursors)
       |> push_event("cursor_update", cursor_data)}
    end
  end

  @spec handle_cursor_leave(String.t(), Phoenix.LiveView.Socket.t()) ::
          {:noreply, Phoenix.LiveView.Socket.t()}
  def handle_cursor_leave(user_id, socket) do
    remote_cursors = Map.delete(socket.assigns.remote_cursors, user_id)

    {:noreply,
     socket
     |> assign(:remote_cursors, remote_cursors)
     |> push_event("cursor_leave", %{user_id: user_id})}
  end

  @spec handle_lock_change(atom(), map(), Phoenix.LiveView.Socket.t()) ::
          {:noreply, Phoenix.LiveView.Socket.t()}
  def handle_lock_change(action, payload, socket) do
    # No echo guard needed — broadcast_from already prevents self-delivery
    node_locks = Collaboration.list_locks({:flow, socket.assigns.flow.id})

    {:noreply,
     socket
     |> assign(:node_locks, node_locks)
     |> push_event("locks_updated", %{locks: node_locks})
     |> CollaborationHelpers.show_collab_toast(action, payload)}
  end

  @spec handle_remote_change(atom(), map(), Phoenix.LiveView.Socket.t()) ::
          {:noreply, Phoenix.LiveView.Socket.t()}
  def handle_remote_change(action, payload, socket) do
    # No echo guard needed — broadcast_from already prevents self-delivery
    flow = Flows.get_flow!(socket.assigns.project.id, socket.assigns.flow.id)
    flow_data = Flows.serialize_for_canvas(flow)

    socket =
      socket
      |> assign(:flow, flow)
      |> assign(:flow_data, flow_data)
      |> CollaborationHelpers.push_remote_change_event(action, payload)
      |> CollaborationHelpers.show_collab_toast(action, payload)

    {:noreply, socket}
  end

  @spec handle_clear_collab_toast(Phoenix.LiveView.Socket.t()) ::
          {:noreply, Phoenix.LiveView.Socket.t()}
  def handle_clear_collab_toast(socket) do
    {:noreply, assign(socket, :collab_toast, nil)}
  end
end
