defmodule Storyarn.Platform.Dashboards.Cache do
  @moduledoc """
  ETS read-through cache for dashboard statistics.

  Caches computed dashboard results per project with a short TTL.
  `fetch/3` and invalidation use direct ETS operations so a change is visible to
  the next dashboard read. Cache hits stay on the direct ETS path, while misses
  use a node-local, per-key singleflight lock. The GenServer owns the tables and
  runs cleanup.
  """

  use GenServer

  alias Phoenix.PubSub

  require Logger

  @table :storyarn_dashboard_cache
  @generation_table :storyarn_dashboard_cache_generations
  @flight_table :storyarn_dashboard_cache_flights
  @invalidation_topic "storyarn:dashboard_cache:invalidations"
  @reset_topic "storyarn:dashboard_cache:resets"
  @ttl_ms to_timeout(second: 30)
  @cleanup_interval_ms to_timeout(second: 15)
  @compute_depth_key {__MODULE__, :compute_depth}

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

    case cached_result(project_id, scope, key) do
      {:ok, result} ->
        result

      :miss ->
        fetch_on_miss(project_id, scope, key, compute_fn)

      :unavailable ->
        compute_fn.()
    end
  end

  @doc """
  Invalidates all cached entries for a project (all scopes).
  """
  def invalidate(project_id) do
    with_cache_tables(fn ->
      advance_generation({:project, project_id})
      :ets.match_delete(@table, {{project_id, :_}, :_, :_, :_})
    end)

    :ok
  end

  @doc """
  Invalidates a specific scope for a project.
  """
  def invalidate(project_id, scope) do
    with_cache_tables(fn ->
      advance_generation({:scope, project_id, scope})
      :ets.delete(@table, {project_id, scope})
    end)

    :ok
  end

  @doc false
  def invalidation_topic, do: @invalidation_topic

  @doc """
  Subscribes to dashboard invalidation events for a project.
  """
  def subscribe_dashboard(project_id) do
    PubSub.subscribe(Storyarn.PubSub, dashboard_topic(project_id))
  end

  @doc """
  Broadcasts a dashboard invalidation event for a project.
  Also directly invalidates the ETS cache.

  `scope` is an atom like `:flows`, `:sheets`, or `:scenes`.
  """
  def broadcast_dashboard_change(project_id, scope) do
    invalidate(project_id)

    # Notify this node only after its cache is synchronously invalidated.
    # Remote cache processes receive the cluster-wide message below, invalidate
    # their own ETS table, and then relay the same dashboard event locally.
    PubSub.local_broadcast(
      Storyarn.PubSub,
      dashboard_topic(project_id),
      {:dashboard_invalidate, scope}
    )

    PubSub.broadcast(
      Storyarn.PubSub,
      invalidation_topic(),
      {:dashboard_cache_invalidate, node(), project_id, scope}
    )
  end

  @doc """
  Broadcasts a dashboard change after a successful operation and returns the
  operation result unchanged.
  """
  def broadcast_dashboard_result({:ok, _value} = result, project_id, scope) do
    broadcast_dashboard_change(project_id, scope)
    result
  end

  def broadcast_dashboard_result(result, _project_id, _scope), do: result

  @doc false
  def dashboard_topic(project_id), do: "project:#{project_id}:dashboard"

  @doc """
  Subscribes the calling process to local cache lifecycle resets.

  A reset means the ETS owner restarted and all previously cached dashboard
  values disappeared. Long-lived dashboard LiveViews use this signal to reload
  even when no domain mutation was published during the restart window.
  """
  def subscribe_resets do
    PubSub.subscribe(Storyarn.PubSub, @reset_topic)
  end

  @doc false
  def cleanup, do: GenServer.call(__MODULE__, :cleanup, :infinity)

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
    :ets.new(@flight_table, [:named_table, :set, :public, read_concurrency: true, write_concurrency: true])
    :ok = PubSub.subscribe(Storyarn.PubSub, @invalidation_topic)
    schedule_cleanup()
    send(self(), :announce_reset)
    {:ok, %{}}
  end

  @impl true
  def handle_call(:cleanup, _from, state) do
    cleanup_expired()
    {:reply, :ok, state}
  end

  @impl true
  def handle_info({:dashboard_cache_invalidate, origin_node, project_id, scope}, state)
      when is_atom(origin_node) and is_integer(project_id) and project_id > 0 and
             scope in [:all, :flows, :scenes, :sheets] do
    # The writer invalidates and notifies its own node synchronously. Every
    # other cache process invalidates first and only then relays the dashboard
    # event locally, so a LiveView can never reload against that node's stale
    # ETS entry. This also covers nodes with no dashboard LiveView at the time.
    if origin_node != node() do
      invalidate(project_id)

      PubSub.local_broadcast(
        Storyarn.PubSub,
        dashboard_topic(project_id),
        {:dashboard_invalidate, scope}
      )
    end

    {:noreply, state}
  end

  def handle_info({:dashboard_cache_invalidate, origin_node, project_id, scope}, state)
      when is_atom(origin_node) and is_integer(project_id) and project_id > 0 do
    Logger.warning(
      "Ignoring unsupported dashboard cache invalidation scope #{inspect(scope)} " <>
        "for project #{project_id} from #{inspect(origin_node)}"
    )

    {:noreply, state}
  end

  @impl true
  def handle_info(:announce_reset, state) do
    PubSub.local_broadcast(Storyarn.PubSub, @reset_topic, :dashboard_cache_reset)
    {:noreply, state}
  end

  @impl true
  def handle_info(:cleanup_expired, state) do
    cleanup_expired()
    schedule_cleanup()
    {:noreply, state}
  end

  def handle_info(_message, state), do: {:noreply, state}

  defp fetch_after_lock(project_id, scope, key, compute_fn) do
    case cached_result(project_id, scope, key) do
      {:ok, result} ->
        result

      :miss ->
        case current_generation(project_id, scope) do
          {:ok, generation} ->
            compute_and_cache(project_id, scope, key, generation, compute_fn)

          :unavailable ->
            compute_fn.()
        end

      :unavailable ->
        compute_fn.()
    end
  end

  defp fetch_on_miss(project_id, scope, key, compute_fn) do
    if cache_compute_active?() do
      # A computation may legitimately read another cached dashboard slice.
      # Waiting for that key's singleflight lock can form A -> B / B -> A
      # cycles across callers, so nested reads compute directly on a miss.
      fetch_after_lock(project_id, scope, key, compute_fn)
    else
      with_key_lock(key, fn ->
        fetch_in_flight(project_id, scope, key, compute_fn)
      end)
    end
  end

  defp fetch_in_flight(project_id, scope, key, compute_fn) do
    with_flight(key, fn ->
      fetch_after_lock(project_id, scope, key, compute_fn)
    end)
  end

  defp compute_and_cache(project_id, scope, key, generation, compute_fn) do
    result = with_compute_guard(compute_fn)

    with_cache_tables(fn ->
      expires_at = System.monotonic_time(:millisecond) + @ttl_ms
      entry = {key, result, expires_at, generation}
      :ets.insert(@table, entry)

      if cache_generation(project_id, scope) != generation do
        # The computation raced an invalidation. Never loop inside the
        # singleflight lock: under sustained writes that would starve every
        # reader of this key. Return this caller's snapshot, but remove it from
        # the cache so the invalidation-triggered reload computes fresh data.
        :ets.delete_object(@table, entry)
      end
    end)

    result
  end

  defp cache_compute_active?, do: Process.get(@compute_depth_key, 0) > 0

  defp with_compute_guard(compute_fn) do
    previous_depth = Process.get(@compute_depth_key, 0)
    Process.put(@compute_depth_key, previous_depth + 1)

    try do
      compute_fn.()
    after
      if previous_depth == 0,
        do: Process.delete(@compute_depth_key),
        else: Process.put(@compute_depth_key, previous_depth)
    end
  end

  defp cached_result(project_id, scope, key) do
    with_cache_tables(fn ->
      now = System.monotonic_time(:millisecond)
      generation = cache_generation(project_id, scope)
      cached_lookup(project_id, scope, key, now, generation)
    end)
  end

  defp cached_lookup(project_id, scope, key, now, generation) do
    case :ets.lookup(@table, key) do
      [{^key, result, expires_at, ^generation}] when expires_at > now ->
        if cache_generation(project_id, scope) == generation, do: {:ok, result}, else: :miss

      _ ->
        :miss
    end
  end

  defp current_generation(project_id, scope) do
    case with_cache_tables(fn -> cache_generation(project_id, scope) end) do
      :unavailable -> :unavailable
      generation -> {:ok, generation}
    end
  end

  defp cache_generation(project_id, scope) do
    {generation_value({:project, project_id}), generation_value({:scope, project_id, scope})}
  end

  defp generation_value(key) do
    case :ets.lookup(@generation_table, key) do
      [{^key, value}] ->
        value

      [] ->
        # A lock-free reader may still hold an entry after invalidation deletes
        # it. Never reuse a default generation after cleanup: a fresh reference
        # prevents that reader from observing an ABA transition and returning
        # its stale value.
        :ets.insert_new(@generation_table, {key, make_ref()})
        generation_value(key)
    end
  end

  defp advance_generation(key), do: :ets.insert(@generation_table, {key, make_ref()})

  defp with_key_lock(key, fun) do
    :global.trans({{__MODULE__, :cache_key, key}, self()}, fun, [node()])
  end

  defp with_flight({_project_id, _scope} = key, fun) do
    registered? = with_cache_tables(fn -> register_flight(key) end)

    try do
      fun.()
    after
      maybe_unregister_flight(key, registered?)
    end
  end

  defp register_flight(key) do
    with_activity_lock(fn -> :ets.insert(@flight_table, {key, self()}) end)
    true
  end

  defp maybe_unregister_flight(key, true) do
    with_cache_tables(fn ->
      with_activity_lock(fn -> :ets.delete_object(@flight_table, {key, self()}) end)
    end)
  end

  defp maybe_unregister_flight(_key, _registered?), do: :ok

  # ETS tables disappear briefly if their owner restarts. Cache availability
  # must never turn a successful domain write or dashboard read into a crash.
  # Keep this boundary around ETS-only work so exceptions from `compute_fn`
  # continue to propagate unchanged.
  defp with_cache_tables(fun) do
    fun.()
  rescue
    ArgumentError -> :unavailable
  end

  defp cleanup_expired do
    # Misses register their flight under this lock before reading a generation.
    # Cleanup can therefore remove an unused generation only when no cached
    # entry or older computation can still publish a value for that project.
    with_activity_lock(fn ->
      now = System.monotonic_time(:millisecond)
      :ets.select_delete(@table, [{{:_, :_, :"$1", :_}, [{:<, :"$1", now}], [true]}])
      purge_unused_generations()
    end)
  end

  defp purge_unused_generations do
    active_flights =
      @flight_table
      |> :ets.tab2list()
      |> Enum.filter(fn {key, pid} ->
        if Process.alive?(pid) do
          true
        else
          :ets.delete_object(@flight_table, {key, pid})
          false
        end
      end)

    cached_projects =
      @table
      |> :ets.select([
        {{{:"$1", :_}, :_, :_, :_}, [], [:"$1"]}
      ])
      |> MapSet.new()

    retained_projects =
      MapSet.union(
        cached_projects,
        MapSet.new(active_flights, fn {{project_id, _scope}, _pid} -> project_id end)
      )

    @generation_table
    |> :ets.tab2list()
    |> Enum.each(fn {generation_key, _generation} ->
      if !MapSet.member?(retained_projects, generation_project_id(generation_key)) do
        :ets.delete(@generation_table, generation_key)
      end
    end)
  end

  defp generation_project_id({:project, project_id}), do: project_id
  defp generation_project_id({:scope, project_id, _scope}), do: project_id

  defp with_activity_lock(fun) do
    :global.trans({{__MODULE__, :activity}, self()}, fun, [node()])
  end

  defp schedule_cleanup do
    Process.send_after(self(), :cleanup_expired, @cleanup_interval_ms)
  end
end
