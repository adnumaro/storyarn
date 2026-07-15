defmodule Storyarn.Imports.ErrorDeduplicator do
  @moduledoc """
  Bounded, process-owned cache for low-cardinality import error fingerprints.

  The private ETS table never receives uploaded names, content, user IDs, or
  project IDs. A `true` result means this fingerprint was not seen during the
  configured window and may be forwarded to an external error sink.
  """

  use GenServer

  @default_ttl_ms to_timeout(minute: 5)
  @max_entries 10_000

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @spec record(map()) :: boolean()
  def record(metadata) when is_map(metadata) do
    GenServer.call(__MODULE__, {:record, fingerprint(metadata)})
  end

  @impl true
  def init(opts) do
    table = :ets.new(__MODULE__, [:set, :private])
    {:ok, %{table: table, ttl_ms: Keyword.get(opts, :ttl_ms, @default_ttl_ms)}}
  end

  @impl true
  def handle_call({:record, fingerprint}, _from, state) do
    now = System.monotonic_time(:millisecond)
    purge_expired(state.table, now)

    fresh? =
      case :ets.lookup(state.table, fingerprint) do
        [{^fingerprint, expires_at}] when expires_at > now -> false
        _other -> true
      end

    if fresh? do
      maybe_bound(state.table)
      :ets.insert(state.table, {fingerprint, now + state.ttl_ms})
    end

    {:reply, fresh?, state}
  end

  defp fingerprint(metadata) do
    metadata
    |> Map.take([:format, :parser_version, :phase, :error_code, :exception_module])
    |> :erlang.term_to_binary()
    |> then(&:crypto.hash(:sha256, &1))
  end

  defp purge_expired(table, now) do
    :ets.select_delete(table, [{{:"$1", :"$2"}, [{:"=<", :"$2", now}], [true]}])
  end

  defp maybe_bound(table) do
    if :ets.info(table, :size) >= @max_entries, do: :ets.delete_all_objects(table)
  end
end
