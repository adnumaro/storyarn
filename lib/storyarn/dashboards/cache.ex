defmodule Storyarn.Dashboards.Cache do
  @moduledoc """
  ETS read-through cache for dashboard statistics.

  Caches computed dashboard results per project with a short TTL.
  `fetch/3` is a direct ETS read (no GenServer call) for sub-microsecond hits.
  The GenServer owns the table, handles invalidation, and runs periodic cleanup.
  """

  use GenServer

  @table :storyarn_dashboard_cache
  @ttl_ms :timer.seconds(30)
  @cleanup_interval_ms :timer.seconds(15)

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

    case :ets.lookup(@table, key) do
      [{^key, result, expires_at}] when expires_at > now ->
        result

      _ ->
        result = compute_fn.()
        :ets.insert(@table, {key, result, now + @ttl_ms})
        result
    end
  end

  @doc """
  Invalidates all cached entries for a project (all scopes).
  """
  def invalidate(project_id) do
    GenServer.cast(__MODULE__, {:invalidate, project_id})
  end

  @doc """
  Invalidates a specific scope for a project.
  """
  def invalidate(project_id, scope) do
    :ets.delete(@table, {project_id, scope})
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
    schedule_cleanup()
    {:ok, %{}}
  end

  @impl true
  def handle_cast({:invalidate, project_id}, state) do
    :ets.match_delete(@table, {{project_id, :_}, :_, :_})
    {:noreply, state}
  end

  @impl true
  def handle_info(:cleanup_expired, state) do
    now = System.monotonic_time(:millisecond)
    :ets.select_delete(@table, [{{:_, :_, :"$1"}, [{:<, :"$1", now}], [true]}])
    schedule_cleanup()
    {:noreply, state}
  end

  defp schedule_cleanup do
    Process.send_after(self(), :cleanup_expired, @cleanup_interval_ms)
  end
end
