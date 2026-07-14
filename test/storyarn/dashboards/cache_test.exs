defmodule Storyarn.Dashboards.CacheTest do
  use ExUnit.Case, async: true

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
end
