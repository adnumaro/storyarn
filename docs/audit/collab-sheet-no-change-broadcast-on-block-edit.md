# Bug: Sheet editor does not broadcast most block-level changes to collaborators

## Severity: high

## Files:
- `lib/storyarn_web/live/sheet_live/show.ex` (lines ~911-915)

## Description

The sheet editor has a `broadcast_sheet_change` helper that broadcasts changes via PubSub, but it is unclear how many block-level operations actually call it. Looking at the `handle_info({:remote_change, action, payload}, socket)` handler, it delegates to `handle_remote_change`, but without seeing what actions are actually broadcast, the remote change handling may be incomplete.

More critically, the sheet editor subscribes to `lock_change` events but does NOT broadcast lock state changes when blocks are locked/released. The `LockHandlers` module acquires and releases locks but never calls `Collab.broadcast_lock_change`. This means:

- User A locks a block → User B never knows about it (no lock_change broadcast)
- User B's `block_locks` assign is stale — they can't see that User A is editing a block
- User B can try to edit the same block, and the lock acquisition will fail, but they won't see the visual lock indicator beforehand

## Evidence

```elixir
# lock_handlers.ex — acquires lock but does NOT broadcast
def handle_acquire(%{"block_id" => block_id}, socket) do
  case Collaboration.acquire_lock(scope, block_id, user) do
    {:ok, _lock_info} ->
      block_locks = Collaboration.list_locks(scope)
      {:noreply, assign(socket, :block_locks, block_locks)}
      # ^ Only updates LOCAL assign — no broadcast to other users!
    # ...
  end
end

# Compare with flow editor which broadcasts:
# CollaborationHelpers.broadcast_lock_change(socket, :node_locked, node_id)
```

## Suggested Fix

Add lock change broadcasts in `LockHandlers.handle_acquire/2` and `handle_release/2`:

```elixir
def handle_acquire(%{"block_id" => block_id}, socket) do
  # ... existing code ...
  case Collaboration.acquire_lock(scope, block_id, user) do
    {:ok, _lock_info} ->
      block_locks = Collaboration.list_locks(scope)
      # ADD: broadcast to other users
      Collab.broadcast_lock_change(socket, scope, :lock_acquired, block_id)
      {:noreply, assign(socket, :block_locks, block_locks)}
    # ...
  end
end
```

Note: This will double-broadcast due to the GenServer broadcast bug (see `collab-double-lock-broadcast.md`). Fix that bug first, then add these broadcasts.
