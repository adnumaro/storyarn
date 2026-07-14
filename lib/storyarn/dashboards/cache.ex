defmodule Storyarn.Dashboards.Cache do
  @moduledoc """
  ETS read-through cache for dashboard statistics.

  Caches computed dashboard results per project with a short TTL.
  `fetch/3` and invalidation use direct ETS operations so a change is visible to
  the next dashboard read. The GenServer owns the table and runs cleanup.
  """

  use GenServer

  @table :storyarn_dashboard_cache
  @generation_table :storyarn_dashboard_cache_generations
  @ttl_ms to_timeout(second: 30)
  @cleanup_interval_ms to_timeout(second: 15)

  # ===========================================================================
  # Client API
  # ===========================================================================

  @doc """
  Returns cached value if fresh, otherwise calls `compute_fn`, caches the result,
  and returns it. Direct ETS read — no GenServer call on the hot path.

  ## Examples

      DashboardCache.fetch(project_id, :flow_stats, fn ->
        FlowStats.flow_stats_for_project(project_id)
      end)
  """
  def fetch(project_id, scope, compute_fn) do
    key = {project_id, scope}
    now = System.monotonic_time(:millisecond)
    generation = cache_generation(project_id, scope)

    case :ets.lookup(@table, key) do
      [{^key, result, expires_at, ^generation}] when expires_at > now ->
        if cache_generation(project_id, scope) == generation do
          result
        else
          fetch(project_id, scope, compute_fn)
        end

      _ ->
        compute_and_cache(project_id, scope, key, generation, compute_fn)
    end
  end

  @doc """
  Invalidates all cached entries for a project (all scopes).
  """
  def invalidate(project_id) do
    increment_generation({:project, project_id})
    :ets.match_delete(@table, {{project_id, :_}, :_, :_, :_})
    :ok
  end

  @doc """
  Invalidates a specific scope for a project.
  """
  def invalidate(project_id, scope) do
    increment_generation({:scope, project_id, scope})
    :ets.delete(@table, {project_id, scope})
    :ok
  end

  # ===========================================================================
  # Server
  # ===========================================================================

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    :ets.new(@table, [:named_table, :set, :public, read_concurrency: true])
    :ets.new(@generation_table, [:named_table, :set, :public, read_concurrency: true, write_concurrency: true])
    schedule_cleanup()
    {:ok, %{}}
  end

  @impl true
  def handle_info(:cleanup_expired, state) do
    now = System.monotonic_time(:millisecond)
    :ets.select_delete(@table, [{{:_, :_, :"$1", :_}, [{:<, :"$1", now}], [true]}])
    schedule_cleanup()
    {:noreply, state}
  end

  defp compute_and_cache(project_id, scope, key, generation, compute_fn) do
    result = compute_fn.()
    expires_at = System.monotonic_time(:millisecond) + @ttl_ms
    :ets.insert(@table, {key, result, expires_at, generation})

    if cache_generation(project_id, scope) == generation do
      result
    else
      fetch(project_id, scope, compute_fn)
    end
  end

  defp cache_generation(project_id, scope) do
    {generation_value({:project, project_id}), generation_value({:scope, project_id, scope})}
  end

  defp generation_value(key) do
    case :ets.lookup(@generation_table, key) do
      [{^key, value}] -> value
      [] -> 0
    end
  end

  defp increment_generation(key) do
    :ets.update_counter(@generation_table, key, {2, 1}, {key, 0})
  end

  defp schedule_cleanup do
    Process.send_after(self(), :cleanup_expired, @cleanup_interval_ms)
  end
end
