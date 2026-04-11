# Bug: Locks GenServer is a single point of failure — crash loses all locks

## Severity: medium

## Files:
- `lib/storyarn/collaboration/locks.ex` (lines 1-343)

## Description

The Locks GenServer stores all lock state in an ETS table that is owned by the GenServer process. If the GenServer crashes:

1. The ETS table is destroyed (tables are owned by the creating process).
2. ALL locks across ALL editors are lost instantly.
3. The GenServer restarts (via supervisor) with a fresh empty ETS table.
4. Users who had locks will continue sending heartbeat refreshes, which will return `{:error, :not_lock_holder}` — but the heartbeat handler in flow show.ex silently ignores this error, so the user thinks they still have the lock.

This creates a split-brain scenario: the user believes they hold the lock, other users see no locks, and concurrent editing can occur.

## Evidence

```elixir
# locks.ex — ETS created in init, destroyed on crash
def init(_opts) do
  :ets.new(@table_name, [:named_table, :set, :public, read_concurrency: true])
  schedule_cleanup()
  {:ok, %{}}
end

# flow show.ex — heartbeat ignores errors
def handle_info(:refresh_node_lock, socket) do
  if node_id = socket.assigns[:locked_node_id] do
    Collaboration.refresh_lock(
      {:flow, socket.assigns.flow.id},
      node_id,
      socket.assigns.current_scope.user.id
    )
    # ^ return value is ignored — :ok or {:error, :not_lock_holder}
    ref = Process.send_after(self(), :refresh_node_lock, @lock_heartbeat_interval)
    {:noreply, assign(socket, :lock_heartbeat_ref, ref)}
  else
    {:noreply, socket}
  end
end
```

## Suggested Fix

Two changes needed:

1. **Use `heir` option on ETS** to survive GenServer restarts, or use a persistent ETS (`:persistent_term`, `:dets`) as a backup.

2. **Handle refresh failure in the heartbeat**: If `refresh_lock` returns `{:error, :not_lock_holder}`, clear the `locked_node_id` and `lock_heartbeat_ref` assigns and notify the user that their lock was lost.

```elixir
# In flow show.ex heartbeat handler
case Collaboration.refresh_lock(scope, node_id, user_id) do
  :ok ->
    ref = Process.send_after(self(), :refresh_node_lock, @lock_heartbeat_interval)
    {:noreply, assign(socket, :lock_heartbeat_ref, ref)}

  {:error, :not_lock_holder} ->
    {:noreply,
     socket
     |> assign(:locked_node_id, nil)
     |> assign(:lock_heartbeat_ref, nil)
     |> put_flash(:info, "Your lock was lost. Please re-select the node.")}
end
```
