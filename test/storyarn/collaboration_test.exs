defmodule Storyarn.CollaborationTest do
  use Storyarn.DataCase

  alias Storyarn.Collaboration
  alias Storyarn.Collaboration.{Colors, Locks}

  # Locks alias used in facade tests below
  import Storyarn.AccountsFixtures

  describe "Colors" do
    test "for_user/1 returns consistent color for same user ID" do
      color1 = Colors.for_user(1)
      color2 = Colors.for_user(1)

      assert color1 == color2
    end

    test "for_user/1 returns different colors for different user IDs" do
      color1 = Colors.for_user(1)
      color2 = Colors.for_user(2)

      assert color1 != color2
    end

    test "for_user/1 cycles through 12-color palette" do
      color_0 = Colors.for_user(0)
      color_12 = Colors.for_user(12)

      assert color_0 == color_12
    end

    test "palette/0 returns 12 colors" do
      assert length(Colors.palette()) == 12
    end

    test "all colors are valid hex codes" do
      for color <- Colors.palette() do
        assert String.match?(color, ~r/^#[0-9a-f]{6}$/i)
      end
    end
  end

  # NOTE: Locks module tests live in collaboration/locks_test.exs (more thorough, 237 lines)

  describe "Collaboration facade" do
    test "user_color/1 delegates to Colors" do
      assert Collaboration.user_color(1) == Colors.for_user(1)
    end

    test "user_color_light/1 delegates to Colors" do
      assert Collaboration.user_color_light(1) == Colors.for_user_light(1)
    end
  end

  # =============================================================================
  # Facade — Topic generation
  # =============================================================================

  describe "changes_topic/1" do
    test "returns correctly formatted topic" do
      assert Collaboration.changes_topic(42) == "flow:42:changes"
    end
  end

  describe "locks_topic/1" do
    test "returns correctly formatted topic" do
      assert Collaboration.locks_topic(42) == "flow:42:locks"
    end
  end

  # =============================================================================
  # Facade — PubSub subscriptions
  # =============================================================================

  describe "subscribe_changes/1" do
    test "subscribes to changes topic" do
      flow_id = System.unique_integer([:positive])
      assert :ok = Collaboration.subscribe_changes(flow_id)
    end
  end

  describe "subscribe_locks/1" do
    test "subscribes to locks topic" do
      flow_id = System.unique_integer([:positive])
      assert :ok = Collaboration.subscribe_locks(flow_id)
    end
  end

  describe "subscribe_presence/1" do
    test "subscribes to presence topic" do
      flow_id = System.unique_integer([:positive])
      assert :ok = Collaboration.subscribe_presence(flow_id)
    end
  end

  describe "subscribe_cursors/1" do
    test "subscribes to cursors topic" do
      flow_id = System.unique_integer([:positive])
      assert :ok = Collaboration.subscribe_cursors(flow_id)
    end
  end

  describe "unsubscribe_cursors/1" do
    test "unsubscribes from cursors topic" do
      flow_id = System.unique_integer([:positive])
      Collaboration.subscribe_cursors(flow_id)
      assert :ok = Collaboration.unsubscribe_cursors(flow_id)
    end
  end

  # =============================================================================
  # Facade — Broadcasting
  # =============================================================================

  describe "broadcast_change/3" do
    test "broadcasts change notification to subscribers" do
      flow_id = System.unique_integer([:positive])
      Collaboration.subscribe_changes(flow_id)

      Collaboration.broadcast_change(flow_id, :node_updated, %{node_id: 1})

      assert_receive {:remote_change, :node_updated, %{node_id: 1}}
    end
  end

  describe "broadcast_lock_change/3" do
    test "broadcasts lock change notification to subscribers" do
      flow_id = System.unique_integer([:positive])
      Collaboration.subscribe_locks(flow_id)

      Collaboration.broadcast_lock_change(flow_id, :lock_acquired, %{node_id: 1, user_id: 42})

      assert_receive {:lock_change, :lock_acquired, %{node_id: 1, user_id: 42}}
    end
  end

  # NOTE: broadcast_cursor/4 and broadcast_cursor_leave/2 tests live in
  # collaboration/cursor_tracker_test.exs (includes deterministic color test)

  # =============================================================================
  # Facade — Lock operations
  # =============================================================================

  describe "facade acquire_lock/3" do
    setup do
      Locks.clear_all()
      user = user_fixture()
      %{user: user, flow_id: System.unique_integer([:positive])}
    end

    test "acquires lock through facade", %{user: user, flow_id: flow_id} do
      assert {:ok, lock_info} = Collaboration.acquire_lock(flow_id, 100, user)
      assert lock_info.user_id == user.id
    end
  end

  describe "facade release_lock/3" do
    setup do
      Locks.clear_all()
      user = user_fixture()
      %{user: user, flow_id: System.unique_integer([:positive])}
    end

    test "releases lock through facade", %{user: user, flow_id: flow_id} do
      {:ok, _} = Collaboration.acquire_lock(flow_id, 100, user)
      assert :ok = Collaboration.release_lock(flow_id, 100, user.id)
    end
  end

  describe "facade release_all_locks/2" do
    setup do
      Locks.clear_all()
      user = user_fixture()
      %{user: user, flow_id: System.unique_integer([:positive])}
    end

    test "releases all locks through facade", %{user: user, flow_id: flow_id} do
      {:ok, _} = Collaboration.acquire_lock(flow_id, 100, user)
      {:ok, _} = Collaboration.acquire_lock(flow_id, 101, user)

      assert :ok = Collaboration.release_all_locks(flow_id, user.id)
      assert Collaboration.list_locks(flow_id) == %{}
    end
  end

  describe "facade get_lock/2" do
    setup do
      Locks.clear_all()
      user = user_fixture()
      %{user: user, flow_id: System.unique_integer([:positive])}
    end

    test "returns lock info through facade", %{user: user, flow_id: flow_id} do
      {:ok, _} = Collaboration.acquire_lock(flow_id, 100, user)
      assert {:ok, lock_info} = Collaboration.get_lock(flow_id, 100)
      assert lock_info.user_id == user.id
    end

    test "returns error when not locked", %{flow_id: flow_id} do
      assert {:error, :not_locked} = Collaboration.get_lock(flow_id, 999)
    end
  end

  describe "facade locked_by_other?/3" do
    setup do
      Locks.clear_all()
      user = user_fixture()
      %{user: user, flow_id: System.unique_integer([:positive])}
    end

    test "returns correct values through facade", %{user: user, flow_id: flow_id} do
      {:ok, _} = Collaboration.acquire_lock(flow_id, 100, user)

      refute Collaboration.locked_by_other?(flow_id, 100, user.id)
      assert Collaboration.locked_by_other?(flow_id, 100, user.id + 1)
      refute Collaboration.locked_by_other?(flow_id, 999, user.id)
    end
  end

  describe "facade list_locks/1" do
    setup do
      Locks.clear_all()
      user = user_fixture()
      %{user: user, flow_id: System.unique_integer([:positive])}
    end

    test "returns all locks through facade", %{user: user, flow_id: flow_id} do
      {:ok, _} = Collaboration.acquire_lock(flow_id, 100, user)
      locks = Collaboration.list_locks(flow_id)
      assert map_size(locks) == 1
    end

    test "returns empty map when no locks", %{flow_id: flow_id} do
      assert Collaboration.list_locks(flow_id) == %{}
    end
  end

  describe "facade refresh_lock/3" do
    setup do
      Locks.clear_all()
      user = user_fixture()
      %{user: user, flow_id: System.unique_integer([:positive])}
    end

    test "refreshes lock through facade", %{user: user, flow_id: flow_id} do
      {:ok, _} = Collaboration.acquire_lock(flow_id, 100, user)
      assert :ok = Collaboration.refresh_lock(flow_id, 100, user.id)
    end

    test "fails for non-holder", %{user: user, flow_id: flow_id} do
      {:ok, _} = Collaboration.acquire_lock(flow_id, 100, user)
      assert {:error, :not_lock_holder} = Collaboration.refresh_lock(flow_id, 100, user.id + 1)
    end
  end

  describe "list_online_users/1" do
    test "returns empty list when no users" do
      flow_id = System.unique_integer([:positive])
      assert Collaboration.list_online_users(flow_id) == []
    end
  end
end
