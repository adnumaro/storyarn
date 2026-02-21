defmodule Storyarn.Flows.NavigationHistoryStore do
  @moduledoc """
  Temporary in-memory store for navigation history during cross-flow navigation.

  When the designer navigates between flows, `push_navigate` creates a new LiveView
  process — socket assigns are lost. This Agent preserves the navigation history
  across those remounts.

  Keys are `{user_id, project_id}` tuples so each user gets their own slot.

  Entries expire after 10 minutes and are cleaned up lazily on each `put/2` call.
  """

  use Agent

  @ttl_ms :timer.minutes(10)

  def start_link(_opts) do
    Agent.start_link(fn -> %{} end, name: __MODULE__)
  end

  @doc "Store navigation history. Overwrites any existing entry."
  def put(key, history) do
    Agent.update(__MODULE__, fn state ->
      state
      |> sweep_stale()
      |> Map.put(key, {history, System.monotonic_time(:millisecond)})
    end)
  end

  @doc "Retrieve navigation history (non-destructive). Returns `nil` if not found or expired."
  def get(key) do
    Agent.get(__MODULE__, fn state ->
      case Map.get(state, key) do
        nil -> nil
        {history, _ts} -> history
      end
    end)
  end

  @doc "Clear navigation history for the given key (e.g. when leaving the flow editor)."
  def clear(key) do
    Agent.update(__MODULE__, fn state -> Map.delete(state, key) end)
  end

  defp sweep_stale(state) do
    now = System.monotonic_time(:millisecond)

    Map.reject(state, fn
      {_k, {_history, ts}} -> now - ts > @ttl_ms
      _ -> false
    end)
  end
end
