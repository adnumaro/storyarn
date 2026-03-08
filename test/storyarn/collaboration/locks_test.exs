defmodule Storyarn.Collaboration.LocksTest do
  use Storyarn.DataCase, async: false

  alias Storyarn.Collaboration.Locks

  @flow_id 1
  @node_id 10

  setup do
    # Ensure the Locks GenServer is running (should be started by the app)
    # Clear all locks before each test
    Locks.clear_all()
    :ok
  end

  defp make_user(id, email \\ nil) do
    %{id: id, email: email || "user#{id}@example.com"}
  end

  describe "acquire/3" do
    test "acquires a lock on an unlocked node" do
      user = make_user(1)

      assert {:ok, lock_info} = Locks.acquire(@flow_id, @node_id, user)
      assert lock_info.user_id == 1
      assert lock_info.user_email == "user1@example.com"
      assert is_binary(lock_info.user_color)
      assert is_integer(lock_info.locked_at)
      assert is_integer(lock_info.expires_at)
      assert lock_info.expires_at > lock_info.locked_at
    end

    test "same user can re-acquire (refresh) their own lock" do
      user = make_user(1)

      {:ok, lock1} = Locks.acquire(@flow_id, @node_id, user)
      {:ok, lock2} = Locks.acquire(@flow_id, @node_id, user)

      assert lock2.user_id == 1
      assert lock2.expires_at >= lock1.expires_at
    end

    test "different user cannot acquire a lock held by another user" do
      user1 = make_user(1)
      user2 = make_user(2)

      {:ok, _lock} = Locks.acquire(@flow_id, @node_id, user1)

      assert {:error, :already_locked, lock_info} = Locks.acquire(@flow_id, @node_id, user2)
      assert lock_info.user_id == 1
    end

    test "can acquire locks on different nodes in the same flow" do
      user = make_user(1)

      assert {:ok, _} = Locks.acquire(@flow_id, 10, user)
      assert {:ok, _} = Locks.acquire(@flow_id, 20, user)
    end

    test "different users can lock different nodes" do
      user1 = make_user(1)
      user2 = make_user(2)

      assert {:ok, _} = Locks.acquire(@flow_id, 10, user1)
      assert {:ok, _} = Locks.acquire(@flow_id, 20, user2)
    end
  end

  describe "release/3" do
    test "lock holder can release their lock" do
      user = make_user(1)
      {:ok, _} = Locks.acquire(@flow_id, @node_id, user)

      assert :ok = Locks.release(@flow_id, @node_id, user.id)
      assert {:error, :not_locked} = Locks.get_lock(@flow_id, @node_id)
    end

    test "non-holder cannot release a lock" do
      user1 = make_user(1)
      _user2 = make_user(2)

      {:ok, _} = Locks.acquire(@flow_id, @node_id, user1)

      assert {:error, :not_lock_holder} = Locks.release(@flow_id, @node_id, 2)
    end

    test "releasing a non-existent lock returns :ok" do
      assert :ok = Locks.release(@flow_id, 999, 1)
    end
  end

  describe "release_all/2" do
    test "releases all locks for a user in a flow" do
      user = make_user(1)

      {:ok, _} = Locks.acquire(@flow_id, 10, user)
      {:ok, _} = Locks.acquire(@flow_id, 20, user)
      {:ok, _} = Locks.acquire(@flow_id, 30, user)

      assert :ok = Locks.release_all(@flow_id, user.id)

      assert {:error, :not_locked} = Locks.get_lock(@flow_id, 10)
      assert {:error, :not_locked} = Locks.get_lock(@flow_id, 20)
      assert {:error, :not_locked} = Locks.get_lock(@flow_id, 30)
    end

    test "does not release locks from other users in the same flow" do
      user1 = make_user(1)
      user2 = make_user(2)

      {:ok, _} = Locks.acquire(@flow_id, 10, user1)
      {:ok, _} = Locks.acquire(@flow_id, 20, user2)

      :ok = Locks.release_all(@flow_id, user1.id)

      assert {:error, :not_locked} = Locks.get_lock(@flow_id, 10)
      assert {:ok, lock} = Locks.get_lock(@flow_id, 20)
      assert lock.user_id == 2
    end

    test "does not release locks in other flows" do
      user = make_user(1)

      {:ok, _} = Locks.acquire(1, @node_id, user)
      {:ok, _} = Locks.acquire(2, @node_id, user)

      :ok = Locks.release_all(1, user.id)

      assert {:error, :not_locked} = Locks.get_lock(1, @node_id)
      assert {:ok, lock} = Locks.get_lock(2, @node_id)
      assert lock.user_id == 1
    end
  end

  describe "refresh/3" do
    test "lock holder can refresh their lock" do
      user = make_user(1)
      {:ok, original} = Locks.acquire(@flow_id, @node_id, user)

      # Small delay to get a different timestamp
      Process.sleep(1)

      assert :ok = Locks.refresh(@flow_id, @node_id, user.id)

      {:ok, refreshed} = Locks.get_lock(@flow_id, @node_id)
      assert refreshed.expires_at >= original.expires_at
    end

    test "non-holder cannot refresh a lock" do
      user1 = make_user(1)
      {:ok, _} = Locks.acquire(@flow_id, @node_id, user1)

      assert {:error, :not_lock_holder} = Locks.refresh(@flow_id, @node_id, 2)
    end

    test "cannot refresh a non-existent lock" do
      assert {:error, :not_lock_holder} = Locks.refresh(@flow_id, 999, 1)
    end
  end

  describe "get_lock/2" do
    test "returns lock info for a locked node" do
      user = make_user(1)
      {:ok, _} = Locks.acquire(@flow_id, @node_id, user)

      assert {:ok, lock_info} = Locks.get_lock(@flow_id, @node_id)
      assert lock_info.user_id == 1
    end

    test "returns not_locked for an unlocked node" do
      assert {:error, :not_locked} = Locks.get_lock(@flow_id, 999)
    end
  end

  describe "list_locks/1" do
    test "lists all locks for a flow" do
      user1 = make_user(1)
      user2 = make_user(2)

      {:ok, _} = Locks.acquire(@flow_id, 10, user1)
      {:ok, _} = Locks.acquire(@flow_id, 20, user2)

      locks = Locks.list_locks(@flow_id)
      assert map_size(locks) == 2
      assert locks[10].user_id == 1
      assert locks[20].user_id == 2
    end

    test "returns empty map when no locks exist" do
      assert Locks.list_locks(999) == %{}
    end

    test "does not include locks from other flows" do
      user = make_user(1)

      {:ok, _} = Locks.acquire(1, @node_id, user)
      {:ok, _} = Locks.acquire(2, @node_id, user)

      locks = Locks.list_locks(1)
      assert map_size(locks) == 1
      assert locks[@node_id].user_id == 1
    end
  end

  describe "locked_by_other?/3" do
    test "returns true when locked by a different user" do
      user1 = make_user(1)
      {:ok, _} = Locks.acquire(@flow_id, @node_id, user1)

      assert Locks.locked_by_other?(@flow_id, @node_id, 2)
    end

    test "returns false when locked by the same user" do
      user = make_user(1)
      {:ok, _} = Locks.acquire(@flow_id, @node_id, user)

      refute Locks.locked_by_other?(@flow_id, @node_id, 1)
    end

    test "returns false when not locked" do
      refute Locks.locked_by_other?(@flow_id, 999, 1)
    end
  end

  describe "cross-scope isolation" do
    test "flow lock does not conflict with sheet lock on same entity_id" do
      user = make_user(1)
      entity_id = 42

      assert {:ok, _} = Locks.acquire({:flow, 1}, entity_id, user)
      assert {:ok, _} = Locks.acquire({:sheet, 1}, entity_id, user)

      flow_locks = Locks.list_locks({:flow, 1})
      sheet_locks = Locks.list_locks({:sheet, 1})

      assert Map.has_key?(flow_locks, entity_id)
      assert Map.has_key?(sheet_locks, entity_id)
    end

    test "different users can lock same entity_id in different scopes" do
      user1 = make_user(1)
      user2 = make_user(2)
      entity_id = 42

      assert {:ok, _} = Locks.acquire({:flow, 1}, entity_id, user1)
      assert {:ok, _} = Locks.acquire({:sheet, 1}, entity_id, user2)

      flow_locks = Locks.list_locks({:flow, 1})
      sheet_locks = Locks.list_locks({:sheet, 1})

      assert flow_locks[entity_id].user_id == 1
      assert sheet_locks[entity_id].user_id == 2
    end

    test "releasing flow lock does not affect sheet lock" do
      user = make_user(1)
      entity_id = 42

      Locks.acquire({:flow, 1}, entity_id, user)
      Locks.acquire({:sheet, 1}, entity_id, user)

      Locks.release({:flow, 1}, entity_id, user.id)

      assert Locks.list_locks({:flow, 1}) == %{}
      assert Map.has_key?(Locks.list_locks({:sheet, 1}), entity_id)
    end

    test "release_all for one scope does not affect other scope" do
      user = make_user(1)

      Locks.acquire({:flow, 1}, 10, user)
      Locks.acquire({:flow, 1}, 20, user)
      Locks.acquire({:sheet, 1}, 10, user)

      Locks.release_all({:flow, 1}, user.id)

      assert Locks.list_locks({:flow, 1}) == %{}
      assert Map.has_key?(Locks.list_locks({:sheet, 1}), 10)
    end
  end

  describe "lock expiration" do
    test "expired lock is treated as not locked by get_lock" do
      user = make_user(1)
      scope = {:flow, 999}
      entity_id = 1

      # Acquire normally first
      {:ok, _} = Locks.acquire(scope, entity_id, user)
      assert {:ok, _} = Locks.get_lock(scope, entity_id)

      # Directly insert an expired entry into ETS to simulate expiration
      # The ETS table is public, so we can manipulate it
      key = {scope, entity_id}
      now = System.monotonic_time(:millisecond)

      expired_lock = %{
        user_id: user.id,
        user_email: user.email,
        user_color: "#ff0000",
        locked_at: now - 60_000,
        expires_at: now - 1_000
      }

      :ets.insert(:storyarn_node_locks, {key, expired_lock})

      # get_lock should return :not_locked for the expired entry
      assert {:error, :not_locked} = Locks.get_lock(scope, entity_id)
    end

    test "expired lock allows new acquisition by different user" do
      user1 = make_user(1)
      user2 = make_user(2)
      scope = {:flow, 998}
      entity_id = 1

      # Insert an expired lock for user1 directly into ETS
      key = {scope, entity_id}
      now = System.monotonic_time(:millisecond)

      expired_lock = %{
        user_id: user1.id,
        user_email: user1.email,
        user_color: "#ff0000",
        locked_at: now - 60_000,
        expires_at: now - 1_000
      }

      :ets.insert(:storyarn_node_locks, {key, expired_lock})

      # user2 should be able to acquire since user1's lock is expired
      assert {:ok, lock_info} = Locks.acquire(scope, entity_id, user2)
      assert lock_info.user_id == 2
    end

    test "expired locks are excluded from list_locks" do
      user = make_user(1)
      scope = {:flow, 997}

      # Acquire a valid lock on entity 10
      {:ok, _} = Locks.acquire(scope, 10, user)

      # Insert an expired lock on entity 20
      key = {scope, 20}
      now = System.monotonic_time(:millisecond)

      expired_lock = %{
        user_id: user.id,
        user_email: user.email,
        user_color: "#ff0000",
        locked_at: now - 60_000,
        expires_at: now - 1_000
      }

      :ets.insert(:storyarn_node_locks, {key, expired_lock})

      locks = Locks.list_locks(scope)
      assert Map.has_key?(locks, 10)
      refute Map.has_key?(locks, 20)
    end
  end

  describe "clear_all/0" do
    test "removes all locks" do
      user = make_user(1)
      {:ok, _} = Locks.acquire(1, 10, user)
      {:ok, _} = Locks.acquire(2, 20, user)

      assert :ok = Locks.clear_all()

      assert {:error, :not_locked} = Locks.get_lock(1, 10)
      assert {:error, :not_locked} = Locks.get_lock(2, 20)
    end
  end
end
