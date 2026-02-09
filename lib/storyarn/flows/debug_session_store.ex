defmodule Storyarn.Flows.DebugSessionStore do
  @moduledoc """
  Temporary in-memory store for debug session state during cross-flow navigation.

  When the debugger enters or returns from a sub-flow, the LiveView must navigate
  to a different flow URL, which triggers a full remount. This Agent preserves the
  debug state across that remount via a one-shot store/take pattern.

  Keys are `{user_id, project_id}` tuples so each user gets their own slot.

  Entries expire after 5 minutes and are cleaned up lazily on each `store/2` call.
  """

  use Agent

  @ttl_ms :timer.minutes(5)

  def start_link(_opts) do
    Agent.start_link(fn -> %{} end, name: __MODULE__)
  end

  @doc "Store debug assigns for later retrieval. Overwrites any existing entry."
  def store(key, assigns) when is_map(assigns) do
    Agent.update(__MODULE__, fn state ->
      state
      |> sweep_stale()
      |> Map.put(key, {assigns, System.monotonic_time(:millisecond)})
    end)
  end

  @doc "Retrieve and remove stored debug assigns. Returns `nil` if not found."
  def take(key) do
    Agent.get_and_update(__MODULE__, fn state ->
      case Map.get(state, key) do
        nil -> {nil, state}
        {assigns, _ts} -> {assigns, Map.delete(state, key)}
      end
    end)
  end

  defp sweep_stale(state) do
    now = System.monotonic_time(:millisecond)

    Map.reject(state, fn
      {_k, {_assigns, ts}} -> now - ts > @ttl_ms
      _ -> false
    end)
  end
end
