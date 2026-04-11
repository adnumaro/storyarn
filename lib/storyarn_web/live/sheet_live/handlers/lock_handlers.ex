defmodule StoryarnWeb.SheetLive.Handlers.LockHandlers do
  @moduledoc """
  Handles block locking events for the sheet editor.
  """

  import Phoenix.Component, only: [assign: 3]
  import Phoenix.LiveView, only: [push_event: 3]

  alias Storyarn.Collaboration
  alias Storyarn.Shared.MapUtils
  alias StoryarnWeb.Live.Shared.CollaborationHelpers, as: Collab

  def handle_acquire(%{"block_id" => block_id}, socket) do
    block_id = MapUtils.parse_int(block_id)
    scope = socket.assigns[:collab_scope]

    if scope do
      user = socket.assigns.current_scope.user

      case Collaboration.acquire_lock(scope, block_id, user) do
        {:ok, _lock_info} ->
          Collab.broadcast_lock_change(socket, scope, :block_locked, block_id)
          block_locks = Collaboration.list_locks(scope)
          {:noreply, assign(socket, :block_locks, block_locks)}

        {:error, :already_locked, lock_info} ->
          {:noreply,
           push_event(socket, "block_lock_denied", %{
             blockId: block_id,
             lockedBy: lock_info.user_email,
             userColor: lock_info.user_color
           })}
      end
    else
      {:noreply, socket}
    end
  end

  def handle_release(%{"block_id" => block_id}, socket) do
    block_id = MapUtils.parse_int(block_id)
    scope = socket.assigns[:collab_scope]

    if scope do
      user_id = socket.assigns.current_scope.user.id
      Collaboration.release_lock(scope, block_id, user_id)
      Collab.broadcast_lock_change(socket, scope, :block_unlocked, block_id)
      block_locks = Collaboration.list_locks(scope)
      {:noreply, assign(socket, :block_locks, block_locks)}
    else
      {:noreply, socket}
    end
  end

  def handle_refresh(%{"block_id" => block_id}, socket) do
    block_id = MapUtils.parse_int(block_id)
    scope = socket.assigns[:collab_scope]

    if scope do
      user_id = socket.assigns.current_scope.user.id
      Collaboration.refresh_lock(scope, block_id, user_id)
    end

    {:noreply, socket}
  end
end
