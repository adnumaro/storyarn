defmodule StoryarnWeb.FlowLive.Helpers.NavigationHistoryTest do
  use ExUnit.Case, async: true

  alias StoryarnWeb.FlowLive.Helpers.NavigationHistory

  describe "new/2" do
    test "creates history with single entry" do
      history = NavigationHistory.new(1, "Flow A")
      assert history.index == 0
      assert length(history.entries) == 1
      assert NavigationHistory.current(history).flow_id == 1
      assert NavigationHistory.current(history).flow_name == "Flow A"
    end
  end

  describe "push/3" do
    test "appends new entry" do
      history = NavigationHistory.new(1, "Flow A")
      history = NavigationHistory.push(history, 2, "Flow B")

      assert history.index == 1
      assert length(history.entries) == 2
      assert NavigationHistory.current(history).flow_id == 2
    end

    test "does not duplicate current flow" do
      history = NavigationHistory.new(1, "Flow A")
      history = NavigationHistory.push(history, 1, "Flow A")

      assert history.index == 0
      assert length(history.entries) == 1
    end

    test "discards forward entries when pushing after back" do
      history = NavigationHistory.new(1, "A")
      history = NavigationHistory.push(history, 2, "B")
      history = NavigationHistory.push(history, 3, "C")

      {:ok, _entry, history} = NavigationHistory.back(history)
      # Now at B, push D -- C should be discarded
      history = NavigationHistory.push(history, 4, "D")

      assert length(history.entries) == 3
      ids = Enum.map(history.entries, & &1.flow_id)
      assert ids == [1, 2, 4]
      assert history.index == 2
    end

    test "truncates to 20 entries" do
      history = NavigationHistory.new(0, "F0")

      history =
        Enum.reduce(1..25, history, fn i, h ->
          NavigationHistory.push(h, i, "F#{i}")
        end)

      assert length(history.entries) == 20
      assert history.index == 19
      # Oldest entries should have been dropped
      assert hd(history.entries).flow_id == 6
    end
  end

  describe "back/1" do
    test "moves cursor back" do
      history = NavigationHistory.new(1, "A")
      history = NavigationHistory.push(history, 2, "B")

      {:ok, entry, history} = NavigationHistory.back(history)

      assert entry.flow_id == 1
      assert history.index == 0
    end

    test "returns :at_start when already at beginning" do
      history = NavigationHistory.new(1, "A")
      assert :at_start = NavigationHistory.back(history)
    end
  end

  describe "forward/1" do
    test "moves cursor forward" do
      history = NavigationHistory.new(1, "A")
      history = NavigationHistory.push(history, 2, "B")
      {:ok, _entry, history} = NavigationHistory.back(history)

      {:ok, entry, history} = NavigationHistory.forward(history)

      assert entry.flow_id == 2
      assert history.index == 1
    end

    test "returns :at_end when already at end" do
      history = NavigationHistory.new(1, "A")
      assert :at_end = NavigationHistory.forward(history)
    end
  end

  describe "can_go_back?/1 and can_go_forward?/1" do
    test "reports availability correctly" do
      history = NavigationHistory.new(1, "A")
      refute NavigationHistory.can_go_back?(history)
      refute NavigationHistory.can_go_forward?(history)

      history = NavigationHistory.push(history, 2, "B")
      assert NavigationHistory.can_go_back?(history)
      refute NavigationHistory.can_go_forward?(history)

      {:ok, _entry, history} = NavigationHistory.back(history)
      refute NavigationHistory.can_go_back?(history)
      assert NavigationHistory.can_go_forward?(history)
    end
  end

  describe "peek_back/1 and peek_forward/1" do
    test "returns nil when no previous/next" do
      history = NavigationHistory.new(1, "A")
      assert NavigationHistory.peek_back(history) == nil
      assert NavigationHistory.peek_forward(history) == nil
    end

    test "returns entries without moving cursor" do
      history = NavigationHistory.new(1, "A")
      history = NavigationHistory.push(history, 2, "B")
      history = NavigationHistory.push(history, 3, "C")

      {:ok, _entry, history} = NavigationHistory.back(history)
      # At B: back=A, forward=C
      assert NavigationHistory.peek_back(history).flow_name == "A"
      assert NavigationHistory.peek_forward(history).flow_name == "C"
      # Cursor didn't move
      assert history.index == 1
    end
  end

  describe "full navigation cycle" do
    test "A -> B -> C -> back -> back -> forward -> forward" do
      history = NavigationHistory.new(1, "A")
      history = NavigationHistory.push(history, 2, "B")
      history = NavigationHistory.push(history, 3, "C")

      assert NavigationHistory.current(history).flow_id == 3

      {:ok, entry, history} = NavigationHistory.back(history)
      assert entry.flow_id == 2

      {:ok, entry, history} = NavigationHistory.back(history)
      assert entry.flow_id == 1

      assert :at_start = NavigationHistory.back(history)

      {:ok, entry, history} = NavigationHistory.forward(history)
      assert entry.flow_id == 2

      {:ok, entry, _history} = NavigationHistory.forward(history)
      assert entry.flow_id == 3
    end

    test "A -> B -> C -> back to B -> navigate to D discards C" do
      history = NavigationHistory.new(1, "A")
      history = NavigationHistory.push(history, 2, "B")
      history = NavigationHistory.push(history, 3, "C")

      {:ok, _entry, history} = NavigationHistory.back(history)
      history = NavigationHistory.push(history, 4, "D")

      assert length(history.entries) == 3
      ids = Enum.map(history.entries, & &1.flow_id)
      assert ids == [1, 2, 4]
      assert :at_end = NavigationHistory.forward(history)
    end
  end
end
