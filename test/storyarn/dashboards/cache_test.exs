defmodule Storyarn.Dashboards.CacheTest do
  use ExUnit.Case, async: true

  alias Phoenix.PubSub
  alias Storyarn.Collaboration
  alias Storyarn.Dashboards.Cache

  setup do
    # Use unique project IDs to avoid collisions in the shared ETS table
    project_id = System.unique_integer([:positive])
    %{project_id: project_id}
  end

  describe "fetch/3" do
    test "returns computed value on cache miss", %{project_id: project_id} do
      result = Cache.fetch(project_id, :test_scope, fn -> %{count: 42} end)
      assert result == %{count: 42}
    end

    test "returns cached value on cache hit", %{project_id: project_id} do
      Cache.fetch(project_id, :test_scope, fn -> %{count: 1} end)

      # compute_fn should NOT be called on cache hit
      result = Cache.fetch(project_id, :test_scope, fn -> %{count: 999} end)
      assert result == %{count: 1}
    end
  end

  describe "invalidate/1" do
    test "clears all entries for a project", %{project_id: project_id} do
      Cache.fetch(project_id, :scope_a, fn -> :a end)
      Cache.fetch(project_id, :scope_b, fn -> :b end)

      Cache.invalidate(project_id)

      # Should recompute
      result_a = Cache.fetch(project_id, :scope_a, fn -> :a_new end)
      result_b = Cache.fetch(project_id, :scope_b, fn -> :b_new end)

      assert result_a == :a_new
      assert result_b == :b_new
    end

    test "does not reinsert a value computed before invalidation", %{project_id: project_id} do
      parent = self()

      task =
        Task.async(fn ->
          Cache.fetch(project_id, :scope, fn ->
            send(parent, {:compute_started, self()})

            receive do
              {:computed_value, value} -> value
            end
          end)
        end)

      assert_receive {:compute_started, task_pid}
      assert :ok = Cache.invalidate(project_id)
      send(task_pid, {:computed_value, :stale})

      assert_receive {:compute_started, ^task_pid}
      send(task_pid, {:computed_value, :fresh})

      assert Task.await(task) == :fresh
      assert Cache.fetch(project_id, :scope, fn -> :unexpected end) == :fresh
    end
  end

  describe "invalidate/2" do
    test "clears specific scope for a project", %{project_id: project_id} do
      Cache.fetch(project_id, :scope_a, fn -> :a end)
      Cache.fetch(project_id, :scope_b, fn -> :b end)

      Cache.invalidate(project_id, :scope_a)

      # scope_a should recompute
      result_a = Cache.fetch(project_id, :scope_a, fn -> :a_new end)
      assert result_a == :a_new

      # scope_b should still be cached
      result_b = Cache.fetch(project_id, :scope_b, fn -> :b_new end)
      assert result_b == :b
    end
  end

  describe "cluster invalidation" do
    test "the writer invalidates synchronously and emits exactly one local event", %{
      project_id: project_id
    } do
      Cache.fetch(project_id, :scope, fn -> :stale end)
      :ok = Collaboration.subscribe_dashboard(project_id)

      :ok = Collaboration.broadcast_dashboard_change(project_id, :scenes)

      assert_receive {:dashboard_invalidate, :scenes}
      assert Cache.fetch(project_id, :scope, fn -> :fresh end) == :fresh

      # The global echo was already enqueued by the call above. Processing it
      # must not relay a second local dashboard event.
      :sys.get_state(Cache)
      refute_receive {:dashboard_invalidate, :scenes}, 10
    end

    test "the cache subscribes to remote invalidations and relays only after clearing local ETS", %{
      project_id: project_id
    } do
      Cache.fetch(project_id, :scope, fn -> :stale end)
      :ok = Collaboration.subscribe_dashboard(project_id)

      PubSub.broadcast(
        Storyarn.PubSub,
        Cache.invalidation_topic(),
        {:dashboard_cache_invalidate, :remote@cluster, project_id, :sheets}
      )

      assert_receive {:dashboard_invalidate, :sheets}
      assert Cache.fetch(project_id, :scope, fn -> :fresh end) == :fresh
    end

    test "the origin node ignores the cluster echo after its synchronous invalidation", %{
      project_id: project_id
    } do
      Cache.fetch(project_id, :scope, fn -> :cached end)
      :ok = Collaboration.subscribe_dashboard(project_id)

      send(
        Cache,
        {:dashboard_cache_invalidate, node(), project_id, :flows}
      )

      # A synchronous call is a mailbox barrier for the preceding message.
      :sys.get_state(Cache)

      refute_receive {:dashboard_invalidate, :flows}, 10
      assert Cache.fetch(project_id, :scope, fn -> :unexpected end) == :cached
    end
  end
end
