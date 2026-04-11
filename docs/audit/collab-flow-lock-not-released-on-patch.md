# Bug: Flow node lock not released when navigating to a different flow via patch

## Severity: high

## Files:
- `lib/storyarn_web/live/flow_live/show.ex` (lines ~1400-1465, 1619-1633)

## Description

When a user has a node locked (is editing it) and navigates to a different flow via patch navigation (clicking another flow in the sidebar), the old flow's node lock is NOT explicitly released before setting up the new flow's collaboration.

The `handle_params` code path calls a function to load the new flow, which sets up new collaboration state. But it does not release the previously held node lock first. The `locked_node_id` assign gets overwritten with `nil` implicitly (since the new flow starts fresh), but the lock entry persists in the Locks GenServer ETS table until the 30-second timeout expires.

During those 30 seconds, other users cannot edit that node — they'll see it as locked by a user who has already navigated away.

## Evidence

Looking at the flow show.ex, `teardown` is only called in `terminate/2`. During patch navigation (same LiveView, different flow_id), `terminate` is NOT called. The flow loading function should teardown the old collaboration before setting up the new one.

```elixir
# In terminate — properly tears down
def terminate(_reason, socket) do
  if socket.assigns[:flow] do
    if ref = socket.assigns[:lock_heartbeat_ref] do
      Process.cancel_timer(ref)
    end
    if scope = socket.assigns[:collab_scope] do
      user_id = socket.assigns.current_scope.user.id
      Collab.teardown(scope, user_id)
    end
  end
end

# But in the flow loading function — no teardown of the PREVIOUS flow's locks
# The old locked_node_id is lost without releasing the lock
```

Note: The sheet and scene editors DO handle this correctly — they call `teardown_sheet_collab(socket)` / `teardown_scene_collab(socket)` at the start of their load functions before setting up the new entity.

## Suggested Fix

Add a teardown step at the beginning of the flow loading function, similar to how sheets and scenes do it:

```elixir
defp load_flow(socket, flow_id) do
  # Teardown previous flow collaboration BEFORE loading new one
  if scope = socket.assigns[:collab_scope] do
    if ref = socket.assigns[:lock_heartbeat_ref], do: Process.cancel_timer(ref)
    user_id = socket.assigns.current_scope.user.id
    Collab.teardown(scope, user_id)
  end

  # ... rest of flow loading ...
end
```
