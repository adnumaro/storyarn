defmodule StoryarnWeb.Helpers.UndoRedoStackTest do
  use ExUnit.Case, async: true

  alias StoryarnWeb.Helpers.UndoRedoStack

  # Build a minimal socket-like struct with assigns
  # __changed__ is required by Phoenix.Component.assign
  defp socket(assigns \\ %{}) do
    %Phoenix.LiveView.Socket{
      assigns: Map.merge(%{__changed__: %{}, undo_stack: [], redo_stack: []}, assigns)
    }
  end

  describe "init/1" do
    test "initializes empty stacks" do
      s = UndoRedoStack.init(%Phoenix.LiveView.Socket{assigns: %{__changed__: %{}}})
      assert s.assigns.undo_stack == []
      assert s.assigns.redo_stack == []
    end
  end

  describe "push_undo/2" do
    test "adds action to undo stack and clears redo" do
      s = socket(%{redo_stack: [:old_redo]})
      s = UndoRedoStack.push_undo(s, :action_a)
      assert s.assigns.undo_stack == [:action_a]
      assert s.assigns.redo_stack == []
    end

    test "prepends to existing undo stack" do
      s = socket(%{undo_stack: [:action_a]})
      s = UndoRedoStack.push_undo(s, :action_b)
      assert s.assigns.undo_stack == [:action_b, :action_a]
    end

    test "caps at max size" do
      actions = Enum.map(1..60, &{:action, &1})
      s = socket(%{undo_stack: actions})
      s = UndoRedoStack.push_undo(s, {:action, 0})
      assert length(s.assigns.undo_stack) == 50
      assert hd(s.assigns.undo_stack) == {:action, 0}
    end

    test "respects custom max size" do
      s = socket()
      s = Enum.reduce(1..10, s, fn i, acc -> UndoRedoStack.push_undo(acc, {:action, i}, 5) end)
      assert length(s.assigns.undo_stack) == 5
    end
  end

  describe "push_undo_no_clear/2" do
    test "pushes without clearing redo stack" do
      s = socket(%{redo_stack: [:redo_action]})
      s = UndoRedoStack.push_undo_no_clear(s, :new_undo)
      assert s.assigns.undo_stack == [:new_undo]
      assert s.assigns.redo_stack == [:redo_action]
    end
  end

  describe "push_redo/2" do
    test "adds action to redo stack" do
      s = socket()
      s = UndoRedoStack.push_redo(s, :redo_action)
      assert s.assigns.redo_stack == [:redo_action]
    end

    test "caps at max size" do
      actions = Enum.map(1..60, &{:redo, &1})
      s = socket(%{redo_stack: actions})
      s = UndoRedoStack.push_redo(s, {:redo, 0})
      assert length(s.assigns.redo_stack) == 50
    end
  end

  describe "push_coalesced/4" do
    test "merges when top matches" do
      s = socket(%{undo_stack: [{:update_name, "original", "mid"}]})

      s =
        UndoRedoStack.push_coalesced(
          s,
          {:update_name, "mid", "final"},
          fn
            {:update_name, _, _} -> true
            _ -> false
          end,
          fn {:update_name, original_prev, _} -> {:update_name, original_prev, "final"} end
        )

      assert s.assigns.undo_stack == [{:update_name, "original", "final"}]
      assert s.assigns.redo_stack == []
    end

    test "pushes new when top doesn't match" do
      s = socket(%{undo_stack: [{:update_color, "red", "blue"}]})

      s =
        UndoRedoStack.push_coalesced(
          s,
          {:update_name, "old", "new"},
          fn
            {:update_name, _, _} -> true
            _ -> false
          end,
          fn {:update_name, prev, _} -> {:update_name, prev, "new"} end
        )

      assert length(s.assigns.undo_stack) == 2
      assert hd(s.assigns.undo_stack) == {:update_name, "old", "new"}
    end

    test "pushes new on empty stack" do
      s = socket()

      s =
        UndoRedoStack.push_coalesced(
          s,
          {:update_name, "old", "new"},
          fn _ -> true end,
          fn x -> x end
        )

      assert s.assigns.undo_stack == [{:update_name, "old", "new"}]
    end
  end

  describe "pop_undo/1" do
    test "returns action and updated socket" do
      s = socket(%{undo_stack: [:a, :b, :c]})
      {action, s} = UndoRedoStack.pop_undo(s)
      assert action == :a
      assert s.assigns.undo_stack == [:b, :c]
    end

    test "returns :empty on empty stack" do
      assert UndoRedoStack.pop_undo(socket()) == :empty
    end
  end

  describe "pop_redo/1" do
    test "returns action and updated socket" do
      s = socket(%{redo_stack: [:x, :y]})
      {action, s} = UndoRedoStack.pop_redo(s)
      assert action == :x
      assert s.assigns.redo_stack == [:y]
    end

    test "returns :empty on empty stack" do
      assert UndoRedoStack.pop_redo(socket()) == :empty
    end
  end

  describe "clear/1" do
    test "clears both stacks" do
      s = socket(%{undo_stack: [:a], redo_stack: [:b]})
      s = UndoRedoStack.clear(s)
      assert s.assigns.undo_stack == []
      assert s.assigns.redo_stack == []
    end
  end

  describe "can_undo?/1 and can_redo?/1" do
    test "returns false for empty stacks" do
      s = socket()
      refute UndoRedoStack.can_undo?(s)
      refute UndoRedoStack.can_redo?(s)
    end

    test "returns true for non-empty stacks" do
      s = socket(%{undo_stack: [:a], redo_stack: [:b]})
      assert UndoRedoStack.can_undo?(s)
      assert UndoRedoStack.can_redo?(s)
    end
  end

  describe "full undo/redo cycle" do
    test "push → pop_undo → push_redo → pop_redo → push_undo_no_clear" do
      s = socket()

      # User performs action
      s = UndoRedoStack.push_undo(s, {:create, :block_1})
      assert length(s.assigns.undo_stack) == 1

      # User undoes
      {action, s} = UndoRedoStack.pop_undo(s)
      assert action == {:create, :block_1}
      s = UndoRedoStack.push_redo(s, action)

      assert s.assigns.undo_stack == []
      assert s.assigns.redo_stack == [{:create, :block_1}]

      # User redoes
      {action, s} = UndoRedoStack.pop_redo(s)
      assert action == {:create, :block_1}
      s = UndoRedoStack.push_undo_no_clear(s, action)

      assert s.assigns.undo_stack == [{:create, :block_1}]
      assert s.assigns.redo_stack == []
    end

    test "new action clears redo stack" do
      s = socket(%{redo_stack: [:redo_1, :redo_2]})
      s = UndoRedoStack.push_undo(s, :new_action)
      assert s.assigns.redo_stack == []
    end
  end
end
