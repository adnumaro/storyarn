# Bug: ETS table is public but mutations go through GenServer — inconsistent read/write path

## Severity: low

## Files:

- `lib/storyarn/collaboration/locks.ex` (lines 68-69, 82-83, 103)

## Description

The ETS table is created with `:public` access and `read_concurrency: true`, which suggests the intent was for reads to bypass the GenServer. However, ALL read operations (`get_lock`, `list_locks`) go through `GenServer.call`, serializing reads through the single GenServer process.

Additionally, `locked_by_other?/3` (line 82-87) is a client-side function that calls `get_lock` via GenServer.call. This is used in hot paths (checking before every node edit in flows). The GenServer becomes a bottleneck under load.

The `locked_by_other?` function could read directly from the public ETS table to avoid GenServer serialization, but doing so introduces a TOCTOU race: the lock could change between the check and the subsequent action.

## Evidence

```elixir
# Table created as public (allows direct ETS reads from any process)
:ets.new(@table_name, [:named_table, :set, :public, read_concurrency: true])

# But reads still go through GenServer
def get_lock(scope, entity_id) do
  GenServer.call(__MODULE__, {:get_lock, scope, entity_id})
end

def locked_by_other?(scope, entity_id, user_id) do
  case get_lock(scope, entity_id) do  # GenServer.call
    {:ok, %{user_id: lock_user_id}} -> lock_user_id != user_id
    {:error, :not_locked} -> false
  end
end
```

## Suggested Fix

Move read-only operations (`get_lock`, `list_locks`, `locked_by_other?`) to read directly from ETS since the table is already `:public`. This eliminates the GenServer bottleneck for reads. The expiry check in `get_lock` can be done client-side (compare `expires_at` with `System.monotonic_time(:millisecond)`), with expired entries cleaned up lazily or by the periodic cleanup timer.

```elixir
def get_lock(scope, entity_id) do
  key = {scope, entity_id}
  now = System.monotonic_time(:millisecond)
  case :ets.lookup(@table_name, key) do
    [{^key, lock_info}] when lock_info.expires_at > now -> {:ok, lock_info}
    _ -> {:error, :not_locked}
  end
end
```
