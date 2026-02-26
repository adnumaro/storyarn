defmodule Storyarn.Collaboration.CursorTrackerTest do
  use Storyarn.DataCase, async: true

  alias Storyarn.Collaboration.CursorTracker

  describe "cursor_topic/1" do
    test "returns correctly formatted topic" do
      assert CursorTracker.cursor_topic(42) == "flow:42:cursors"
    end

    test "returns different topics for different flow IDs" do
      assert CursorTracker.cursor_topic(1) != CursorTracker.cursor_topic(2)
    end
  end

  describe "subscribe/1 and unsubscribe/1" do
    test "subscribes to cursor updates for a flow" do
      assert :ok = CursorTracker.subscribe(100)
    end

    test "unsubscribes from cursor updates for a flow" do
      :ok = CursorTracker.subscribe(100)
      assert :ok = CursorTracker.unsubscribe(100)
    end
  end

  describe "broadcast_cursor/4" do
    test "broadcasts cursor position to subscribers" do
      flow_id = 200
      :ok = CursorTracker.subscribe(flow_id)

      user = %{id: 1, email: "test@example.com"}
      :ok = CursorTracker.broadcast_cursor(flow_id, user, 150.5, 200.3)

      assert_receive {:cursor_update, payload}
      assert payload.user_id == 1
      assert payload.user_email == "test@example.com"
      assert payload.x == 150.5
      assert payload.y == 200.3
      assert is_binary(payload.user_color)
    end

    test "does not receive messages from unsubscribed flows" do
      :ok = CursorTracker.subscribe(300)

      user = %{id: 1, email: "test@example.com"}
      :ok = CursorTracker.broadcast_cursor(301, user, 10.0, 20.0)

      refute_receive {:cursor_update, _}
    end

    test "user_color is deterministic based on user ID" do
      flow_id = 400
      :ok = CursorTracker.subscribe(flow_id)

      user = %{id: 5, email: "test@example.com"}
      :ok = CursorTracker.broadcast_cursor(flow_id, user, 0.0, 0.0)

      assert_receive {:cursor_update, payload1}

      :ok = CursorTracker.broadcast_cursor(flow_id, user, 1.0, 1.0)

      assert_receive {:cursor_update, payload2}
      assert payload1.user_color == payload2.user_color
    end
  end

  describe "broadcast_cursor_leave/2" do
    test "broadcasts cursor leave event to subscribers" do
      flow_id = 500
      :ok = CursorTracker.subscribe(flow_id)

      :ok = CursorTracker.broadcast_cursor_leave(flow_id, 42)

      assert_receive {:cursor_leave, 42}
    end

    test "does not receive leave events from unsubscribed flows" do
      :ok = CursorTracker.subscribe(600)

      :ok = CursorTracker.broadcast_cursor_leave(601, 42)

      refute_receive {:cursor_leave, _}
    end
  end
end
