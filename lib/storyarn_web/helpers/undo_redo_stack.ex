defmodule StoryarnWeb.Helpers.UndoRedoStack do
  @moduledoc """
  Shared undo/redo stack management for LiveView editors.

  Provides generic stack operations (push, pop, coalesce, cap) that can be
  used by any LiveView that needs undo/redo functionality. Domain-specific
  action dispatch (undo_action/redo_action) remains in each editor's handler.
  """

  import Phoenix.Component, only: [assign: 2, assign: 3]

  @default_max_size 50

  @doc """
  Initializes undo/redo assigns on a socket.
  Call in the LiveView's mount/3 or setup function.
  """
  def init(socket) do
    assign(socket, undo_stack: [], redo_stack: [])
  end

  @doc """
  Pushes an action onto the undo stack and clears the redo stack.
  Used when the user performs a new action (invalidates redo history).
  """
  def push_undo(socket, action, max_size \\ @default_max_size) do
    stack = Enum.take([action | socket.assigns.undo_stack], max_size)
    assign(socket, undo_stack: stack, redo_stack: [])
  end

  @doc """
  Pushes an action onto the undo stack WITHOUT clearing the redo stack.
  Used internally during redo to preserve the remaining redo history.
  """
  def push_undo_no_clear(socket, action, max_size \\ @default_max_size) do
    stack = Enum.take([action | socket.assigns.undo_stack], max_size)
    assign(socket, :undo_stack, stack)
  end

  @doc """
  Pushes an action onto the redo stack.
  """
  def push_redo(socket, action, max_size \\ @default_max_size) do
    stack = Enum.take([action | socket.assigns.redo_stack], max_size)
    assign(socket, :redo_stack, stack)
  end

  @doc """
  Coalesces consecutive actions of the same type and element.
  If the top of the undo stack matches the `match_fn`, replaces it with
  the `merge_fn` result. Otherwise pushes as a normal new action.

  ## Example

      push_coalesced(socket, action,
        fn top -> match?({:update_block_value, ^block_id, _, _}, top) end,
        fn {:update_block_value, id, original_prev, _} ->
          {:update_block_value, id, original_prev, new}
        end
      )
  """
  def push_coalesced(socket, action, match_fn, merge_fn, max_size \\ @default_max_size) do
    case socket.assigns.undo_stack do
      [top | rest] ->
        if match_fn.(top) do
          updated = merge_fn.(top)
          assign(socket, undo_stack: [updated | rest], redo_stack: [])
        else
          push_undo(socket, action, max_size)
        end

      _ ->
        push_undo(socket, action, max_size)
    end
  end

  @doc """
  Pops from the undo stack and returns `{action, updated_socket}` or `:empty`.
  Does NOT execute the action — the caller must dispatch it.
  """
  def pop_undo(socket) do
    case socket.assigns.undo_stack do
      [] -> :empty
      [action | rest] -> {action, assign(socket, :undo_stack, rest)}
    end
  end

  @doc """
  Pops from the redo stack and returns `{action, updated_socket}` or `:empty`.
  """
  def pop_redo(socket) do
    case socket.assigns.redo_stack do
      [] -> :empty
      [action | rest] -> {action, assign(socket, :redo_stack, rest)}
    end
  end

  @doc """
  Clears both stacks (e.g., after a full data refresh that invalidates history).
  """
  def clear(socket) do
    assign(socket, undo_stack: [], redo_stack: [])
  end

  @doc """
  Returns true if undo stack is non-empty.
  """
  def can_undo?(socket), do: socket.assigns.undo_stack != []

  @doc """
  Returns true if redo stack is non-empty.
  """
  def can_redo?(socket), do: socket.assigns.redo_stack != []
end
