defmodule Storyarn.Platform.Dashboards.CacheTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureLog

  alias Phoenix.PubSub
  alias Storyarn.Platform.Dashboards.Cache

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

    test "coalesces concurrent misses for the same project and scope", %{project_id: project_id} do
      parent = self()
      compute_count = :atomics.new(1, [])

      tasks =
        for _ <- 1..20 do
          Task.async(fn ->
            send(parent, {:fetch_ready, self()})

            receive do
              :fetch -> :ok
            end

            Cache.fetch(project_id, :singleflight_scope, fn ->
              invocation = :atomics.add_get(compute_count, 1, 1)

              if invocation == 1 do
                send(parent, {:compute_started, self()})

                receive do
                  :finish_compute -> :ok
                end
              end

              :computed
            end)
          end)
        end

      callers =
        for _ <- tasks do
          assert_receive {:fetch_ready, pid}
          pid
        end

      Enum.each(callers, &send(&1, :fetch))
      assert_receive {:compute_started, compute_pid}
      Process.sleep(25)
      send(compute_pid, :finish_compute)

      assert Enum.map(tasks, &Task.await(&1)) == List.duplicate(:computed, length(tasks))
      assert :atomics.get(compute_count, 1) == 1
    end

    test "does not serialize misses for different keys", %{project_id: project_id} do
      parent = self()

      task_a =
        Task.async(fn ->
          Cache.fetch(project_id, :scope_a, fn ->
            send(parent, {:compute_started, :scope_a, self()})
            receive do: (:finish_compute -> :scope_a)
          end)
        end)

      assert_receive {:compute_started, :scope_a, task_a_pid}

      task_b =
        Task.async(fn ->
          Cache.fetch(project_id, :scope_b, fn ->
            send(parent, {:compute_started, :scope_b, self()})
            receive do: (:finish_compute -> :scope_b)
          end)
        end)

      assert_receive {:compute_started, :scope_b, task_b_pid}
      send(task_a_pid, :finish_compute)
      send(task_b_pid, :finish_compute)

      assert Task.await(task_a) == :scope_a
      assert Task.await(task_b) == :scope_b
    end

    test "cross-key nested computations cannot deadlock each other", %{
      project_id: project_id
    } do
      parent = self()
      barrier = make_ref()

      task_a =
        nested_fetch_task(
          parent,
          barrier,
          project_id,
          :nested_scope_a,
          :nested_scope_b
        )

      task_b =
        nested_fetch_task(
          parent,
          barrier,
          project_id,
          :nested_scope_b,
          :nested_scope_a
        )

      assert_receive {^barrier, :nested_scope_a, task_a_pid}
      assert_receive {^barrier, :nested_scope_b, task_b_pid}

      send(task_a_pid, {barrier, :continue})
      send(task_b_pid, {barrier, :continue})

      assert_task_result(task_a, {:computed, :nested_scope_a})
      assert_task_result(task_b, {:computed, :nested_scope_b})
    end

    test "releases the singleflight lock when computation raises", %{project_id: project_id} do
      assert_raise RuntimeError, "compute failed", fn ->
        Cache.fetch(project_id, :failing_scope, fn -> raise "compute failed" end)
      end

      assert Cache.fetch(project_id, :failing_scope, fn -> :recovered end) == :recovered
    end

    test "returns without retrying forever when every computation invalidates its generation", %{
      project_id: project_id
    } do
      compute_count = :atomics.new(1, [])

      result =
        Cache.fetch(project_id, :continuously_invalidated_scope, fn ->
          :atomics.add(compute_count, 1, 1)
          Cache.invalidate(project_id)
          :snapshot
        end)

      assert result == :snapshot
      assert :atomics.get(compute_count, 1) == 1

      assert Cache.fetch(project_id, :continuously_invalidated_scope, fn -> :fresh end) ==
               :fresh
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
      assert :ok = Cache.cleanup()
      send(task_pid, {:computed_value, :stale})

      assert Task.await(task) == :stale
      assert Cache.fetch(project_id, :scope, fn -> :fresh end) == :fresh
      assert Cache.fetch(project_id, :scope, fn -> :unexpected end) == :fresh
    end

    test "cleanup removes generations after a project has no cache or computation", %{
      project_id: project_id
    } do
      assert :ok = Cache.invalidate(project_id)

      assert [{{:project, ^project_id}, first_generation}] =
               :ets.lookup(:storyarn_dashboard_cache_generations, {:project, project_id})

      assert :ok = Cache.cleanup()

      assert :ets.lookup(:storyarn_dashboard_cache_generations, {:project, project_id}) == []

      assert :ok = Cache.invalidate(project_id)

      assert [{{:project, ^project_id}, second_generation}] =
               :ets.lookup(:storyarn_dashboard_cache_generations, {:project, project_id})

      refute second_generation == first_generation
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
      origin_node = node()
      Cache.fetch(project_id, :scope, fn -> :stale end)
      :ok = Cache.subscribe_dashboard(project_id)
      :ok = PubSub.subscribe(Storyarn.PubSub, Cache.invalidation_topic())

      :ok = Cache.broadcast_dashboard_change(project_id, :scenes)

      assert_receive {:dashboard_invalidate, :scenes}
      assert_receive {:dashboard_cache_invalidate, ^origin_node, ^project_id, :scenes}
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
      :ok = Cache.subscribe_dashboard(project_id)

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
      :ok = Cache.subscribe_dashboard(project_id)

      send(
        Cache,
        {:dashboard_cache_invalidate, node(), project_id, :flows}
      )

      # A synchronous call is a mailbox barrier for the preceding message.
      :sys.get_state(Cache)

      refute_receive {:dashboard_invalidate, :flows}, 10
      assert Cache.fetch(project_id, :scope, fn -> :unexpected end) == :cached
    end

    test "unexpected invalidation messages do not restart the cache", %{project_id: project_id} do
      cache_pid = Process.whereis(Cache)
      Cache.fetch(project_id, :scope, fn -> :cached end)

      PubSub.broadcast(
        Storyarn.PubSub,
        Cache.invalidation_topic(),
        {:dashboard_cache_invalidate, :remote@cluster, %{invalid: project_id}, :flows}
      )

      :sys.get_state(Cache)

      assert Process.whereis(Cache) == cache_pid
      assert Cache.fetch(project_id, :scope, fn -> :unexpected end) == :cached
    end

    test "unsupported invalidation scopes are observable", %{project_id: project_id} do
      log =
        capture_log(fn ->
          send(
            Cache,
            {:dashboard_cache_invalidate, :remote@cluster, project_id, :unsupported}
          )

          :sys.get_state(Cache)
        end)

      assert log =~ "unsupported dashboard cache invalidation scope"
      assert log =~ ":unsupported"
    end
  end

  describe "cache lifecycle" do
    test "manual cleanup is not limited by the default GenServer call timeout" do
      source_path =
        Path.expand(
          "../../../../lib/storyarn/platform/discovery/dashboard_cache.ex",
          __DIR__
        )

      source = File.read!(source_path)

      assert source =~
               ~r/def cleanup,\s+do: GenServer\.call\(__MODULE__, :cleanup, :infinity\)/
    end

    test "cleanup preserves an in-flight computation and its eventual cache entry", %{
      project_id: project_id
    } do
      parent = self()

      task =
        Task.async(fn ->
          Cache.fetch(project_id, :slow_scope, fn ->
            send(parent, {:slow_compute_started, self()})

            receive do
              :finish_slow_compute -> :computed_before_cleanup
            end
          end)
        end)

      assert_receive {:slow_compute_started, task_pid}
      assert :ok = Cache.cleanup()
      send(task_pid, :finish_slow_compute)

      assert Task.await(task) == :computed_before_cleanup

      assert Cache.fetch(project_id, :slow_scope, fn -> :unexpected_recompute end) ==
               :computed_before_cleanup
    end

    test "cleanup does not copy the full value table into the cache process" do
      source_path =
        Path.expand(
          "../../../../lib/storyarn/platform/discovery/dashboard_cache.ex",
          __DIR__
        )

      source = File.read!(source_path)

      refute source =~
               ~r/@table\s*\|>\s*:ets\.tab2list\(\)/
    end

    test "reads and invalidations degrade safely while the ETS owner is restarting", %{
      project_id: project_id
    } do
      assert :ok = Cache.subscribe_resets()
      Cache.fetch(project_id, :scope, fn -> :stale end)

      assert :ok = Supervisor.terminate_child(Storyarn.Supervisor, Cache)
      on_exit(&ensure_cache_started/0)

      assert :ok = Cache.invalidate(project_id)
      assert :ok = Cache.invalidate(project_id, :scope)

      assert Cache.fetch(project_id, :scope, fn -> :computed_without_cache end) ==
               :computed_without_cache

      ensure_cache_started()
      :sys.get_state(Cache)

      assert_receive :dashboard_cache_reset
      assert Cache.fetch(project_id, :scope, fn -> :fresh end) == :fresh
    end

    test "cleanup removes expired entries so the next read recomputes", %{
      project_id: project_id
    } do
      assert Cache.fetch(project_id, :expiring_scope, fn -> :cached end) == :cached

      key = {project_id, :expiring_scope}
      [{^key, :cached, _expires_at, generation}] = :ets.lookup(:storyarn_dashboard_cache, key)

      true =
        :ets.insert(
          :storyarn_dashboard_cache,
          {key, :cached, System.monotonic_time(:millisecond) - 1, generation}
        )

      assert :ok = Cache.cleanup()
      assert Cache.fetch(project_id, :expiring_scope, fn -> :fresh end) == :fresh
    end
  end

  defp ensure_cache_started do
    case Process.whereis(Cache) do
      nil ->
        case Supervisor.restart_child(Storyarn.Supervisor, Cache) do
          {:ok, _pid} -> :ok
          {:ok, _pid, _info} -> :ok
          {:error, :running} -> :ok
        end

      _pid ->
        :ok
    end
  end

  defp nested_fetch_task(parent, barrier, project_id, outer_scope, inner_scope) do
    Task.async(fn -> perform_nested_fetch(parent, barrier, project_id, outer_scope, inner_scope) end)
  end

  defp perform_nested_fetch(parent, barrier, project_id, outer_scope, inner_scope) do
    Cache.fetch(project_id, outer_scope, fn ->
      send(parent, {barrier, outer_scope, self()})

      receive do
        {^barrier, :continue} -> :ok
      end

      Cache.fetch(project_id, inner_scope, fn -> {:nested, inner_scope} end)
      {:computed, outer_scope}
    end)
  end

  defp assert_task_result(task, expected) do
    case Task.yield(task, 1_000) do
      {:ok, result} ->
        assert result == expected

      nil ->
        Task.shutdown(task, :brutal_kill)
        flunk("cache computation deadlocked")
    end
  end
end
