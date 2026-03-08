defmodule Storyarn.Collaboration.CursorTrackerTest do
  use Storyarn.DataCase, async: true

  alias Storyarn.Collaboration.CursorTracker

  describe "cursor_topic/1" do
    test "returns correctly formatted topic for flow scope" do
      assert CursorTracker.cursor_topic({:flow, 42}) == "flow:42:cursors"
    end

    test "returns different topics for different scope IDs" do
      assert CursorTracker.cursor_topic({:flow, 1}) != CursorTracker.cursor_topic({:flow, 2})
    end

    test "returns correctly formatted topic for scene scope" do
      assert CursorTracker.cursor_topic({:scene, 7}) == "scene:7:cursors"
    end
  end

  describe "subscribe/1 and unsubscribe/1" do
    test "subscribes to cursor updates for a flow" do
      assert :ok = CursorTracker.subscribe({:flow, 100})
    end

    test "unsubscribes from cursor updates for a flow" do
      :ok = CursorTracker.subscribe({:flow, 100})
      assert :ok = CursorTracker.unsubscribe({:flow, 100})
    end

    test "subscribes with scene scope tuple" do
      assert :ok = CursorTracker.subscribe({:scene, 100})
    end
  end

  describe "broadcast_cursor/4" do
    test "broadcasts cursor position to subscribers (from another process)" do
      scope = {:flow, 200}
      test_pid = self()
      :ok = CursorTracker.subscribe(scope)

      # Broadcast from a different process so broadcast_from doesn't exclude us
      user = %{id: 1, email: "test@example.com"}

      spawn(fn ->
        CursorTracker.broadcast_cursor(scope, user, 150.5, 200.3)
        send(test_pid, :broadcast_done)
      end)

      assert_receive :broadcast_done
      assert_receive {:cursor_update, payload}
      assert payload.user_id == 1
      assert payload.user_email == "test@example.com"
      assert payload.x == 150.5
      assert payload.y == 200.3
      assert is_binary(payload.user_color)
    end

    test "does not receive messages from unsubscribed flows" do
      test_pid = self()
      :ok = CursorTracker.subscribe({:flow, 300})

      user = %{id: 1, email: "test@example.com"}

      spawn(fn ->
        CursorTracker.broadcast_cursor({:flow, 301}, user, 10.0, 20.0)
        send(test_pid, :done)
      end)

      assert_receive :done
      refute_receive {:cursor_update, _}
    end

    test "user_color is deterministic based on user ID" do
      scope = {:flow, 400}
      test_pid = self()
      :ok = CursorTracker.subscribe(scope)

      user = %{id: 5, email: "test@example.com"}

      spawn(fn ->
        CursorTracker.broadcast_cursor(scope, user, 0.0, 0.0)
        CursorTracker.broadcast_cursor(scope, user, 1.0, 1.0)
        send(test_pid, :done)
      end)

      assert_receive :done
      assert_receive {:cursor_update, payload1}
      assert_receive {:cursor_update, payload2}
      assert payload1.user_color == payload2.user_color
    end

    test "sender does not receive their own cursor (broadcast_from)" do
      scope = {:flow, System.unique_integer([:positive])}
      :ok = CursorTracker.subscribe(scope)

      user = %{id: 1, email: "test@example.com"}
      :ok = CursorTracker.broadcast_cursor(scope, user, 10.0, 20.0)

      refute_receive {:cursor_update, _}
    end
  end

  describe "broadcast_cursor_leave/2" do
    test "broadcasts cursor leave event to subscribers" do
      scope = {:flow, 500}
      test_pid = self()
      :ok = CursorTracker.subscribe(scope)

      spawn(fn ->
        CursorTracker.broadcast_cursor_leave(scope, 42)
        send(test_pid, :done)
      end)

      assert_receive :done
      assert_receive {:cursor_leave, 42}
    end

    test "does not receive leave events from unsubscribed flows" do
      test_pid = self()
      :ok = CursorTracker.subscribe({:flow, 600})

      spawn(fn ->
        CursorTracker.broadcast_cursor_leave({:flow, 601}, 42)
        send(test_pid, :done)
      end)

      assert_receive :done
      refute_receive {:cursor_leave, _}
    end

    test "sender does not receive their own leave (broadcast_from)" do
      scope = {:flow, System.unique_integer([:positive])}
      :ok = CursorTracker.subscribe(scope)

      :ok = CursorTracker.broadcast_cursor_leave(scope, 42)

      refute_receive {:cursor_leave, _}
    end
  end
end
