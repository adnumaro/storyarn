defmodule Storyarn.CollaborationTest do
  use Storyarn.DataCase

  alias Storyarn.Collaboration
  alias Storyarn.Collaboration.{Colors, Locks}

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

  describe "Locks" do
    setup do
      # Clear all locks before each test
      Locks.clear_all()

      user = user_fixture()
      user2 = user_fixture()
      flow_id = 1
      node_id = 100

      %{user: user, user2: user2, flow_id: flow_id, node_id: node_id}
    end

    test "acquire/3 acquires lock on unlocked node", %{
      user: user,
      flow_id: flow_id,
      node_id: node_id
    } do
      {:ok, lock_info} = Locks.acquire(flow_id, node_id, user)

      assert lock_info.user_id == user.id
      assert lock_info.user_email == user.email
    end

    test "acquire/3 allows same user to refresh lock", %{
      user: user,
      flow_id: flow_id,
      node_id: node_id
    } do
      {:ok, _} = Locks.acquire(flow_id, node_id, user)
      {:ok, lock_info} = Locks.acquire(flow_id, node_id, user)

      assert lock_info.user_id == user.id
    end

    test "acquire/3 fails when locked by another user", %{
      user: user,
      user2: user2,
      flow_id: flow_id,
      node_id: node_id
    } do
      {:ok, _} = Locks.acquire(flow_id, node_id, user)

      {:error, :already_locked, lock_info} = Locks.acquire(flow_id, node_id, user2)

      assert lock_info.user_id == user.id
    end

    test "release/3 releases lock held by user", %{
      user: user,
      flow_id: flow_id,
      node_id: node_id
    } do
      {:ok, _} = Locks.acquire(flow_id, node_id, user)
      :ok = Locks.release(flow_id, node_id, user.id)

      assert {:error, :not_locked} = Locks.get_lock(flow_id, node_id)
    end

    test "release/3 fails when not lock holder", %{
      user: user,
      user2: user2,
      flow_id: flow_id,
      node_id: node_id
    } do
      {:ok, _} = Locks.acquire(flow_id, node_id, user)

      assert {:error, :not_lock_holder} = Locks.release(flow_id, node_id, user2.id)
    end

    test "release_all/2 releases all locks for user in flow", %{
      user: user,
      flow_id: flow_id
    } do
      {:ok, _} = Locks.acquire(flow_id, 1, user)
      {:ok, _} = Locks.acquire(flow_id, 2, user)
      {:ok, _} = Locks.acquire(flow_id, 3, user)

      :ok = Locks.release_all(flow_id, user.id)

      assert Locks.list_locks(flow_id) == %{}
    end

    test "get_lock/2 returns lock info when locked", %{
      user: user,
      flow_id: flow_id,
      node_id: node_id
    } do
      {:ok, _} = Locks.acquire(flow_id, node_id, user)

      {:ok, lock_info} = Locks.get_lock(flow_id, node_id)

      assert lock_info.user_id == user.id
    end

    test "get_lock/2 returns error when not locked", %{flow_id: flow_id, node_id: node_id} do
      assert {:error, :not_locked} = Locks.get_lock(flow_id, node_id)
    end

    test "list_locks/1 returns all locks for flow", %{user: user, flow_id: flow_id} do
      {:ok, _} = Locks.acquire(flow_id, 1, user)
      {:ok, _} = Locks.acquire(flow_id, 2, user)

      locks = Locks.list_locks(flow_id)

      assert Map.has_key?(locks, 1)
      assert Map.has_key?(locks, 2)
    end

    test "locked_by_other?/3 returns true when locked by different user", %{
      user: user,
      user2: user2,
      flow_id: flow_id,
      node_id: node_id
    } do
      {:ok, _} = Locks.acquire(flow_id, node_id, user)

      assert Locks.locked_by_other?(flow_id, node_id, user2.id) == true
    end

    test "locked_by_other?/3 returns false when locked by same user", %{
      user: user,
      flow_id: flow_id,
      node_id: node_id
    } do
      {:ok, _} = Locks.acquire(flow_id, node_id, user)

      assert Locks.locked_by_other?(flow_id, node_id, user.id) == false
    end

    test "locked_by_other?/3 returns false when not locked", %{
      user: user,
      flow_id: flow_id,
      node_id: node_id
    } do
      assert Locks.locked_by_other?(flow_id, node_id, user.id) == false
    end
  end

  describe "Collaboration facade" do
    test "user_color/1 delegates to Colors" do
      assert Collaboration.user_color(1) == Colors.for_user(1)
    end

    test "user_color_light/1 delegates to Colors" do
      assert Collaboration.user_color_light(1) == Colors.for_user_light(1)
    end
  end
end
