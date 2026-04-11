# Bug: player_live.ex init_and_step does not handle {:flow_jump, ...} 4-tuple

## Severity: high

## Files
- `lib/storyarn_web/live/flow_live/player_live.ex` (lines 158-174: `init_and_step/4`)

## Description

`PlayerEngine.step_until_interactive/4` can return a 4-tuple `{:flow_jump, state, flow_id, skipped}` when the flow encounters a subflow node during initial stepping. The `init_and_step/4` function in `player_live.ex` only matches 3-tuples:

- `{:error, _state, _skipped}` (3-tuple)
- `{_status, new_state, _skipped}` (3-tuple)

The `{:flow_jump, ...}` 4-tuple does not match either clause, causing a `CaseClauseError` crash when a flow's first interactive path passes through a subflow node.

This crash occurs when a user opens the player for a flow whose initial path contains a subflow before any dialogue.

## Evidence

```elixir
# player_live.ex lines 167-174
case PlayerEngine.step_until_interactive(state, nodes_map, connections) do
  {:error, _state, _skipped} ->
    {:error, dgettext("flows", "Error advancing through flow.")}

  {_status, new_state, _skipped} ->      # 3-tuple - does NOT match flow_jump 4-tuple
    {:ok, new_state}
end
```

`PlayerEngine.step_until_interactive` spec shows the 4-tuple return:
```elixir
@spec step_until_interactive(State.t(), map(), list(), keyword()) ::
        {:ok | :waiting_input | :finished | :error, State.t(), list()}
        | {:flow_jump, State.t(), integer(), list()}   # <-- 4-tuple, unhandled
        | {:flow_return, State.t(), list()}
```

## Suggested Fix

Add a clause for the `flow_jump` 4-tuple, similar to how `exploration_live.ex`'s `init_flow/2` handles it (which sets up context then calls `handle_flow_jump`):

```elixir
case PlayerEngine.step_until_interactive(state, nodes_map, connections) do
  {:error, _state, _skipped} ->
    {:error, dgettext("flows", "Error advancing through flow.")}

  {:flow_jump, new_state, _target_flow_id, _skipped} ->
    {:ok, new_state}  # Caller will handle the flow_jump via build_slide_or_advance

  {_status, new_state, _skipped} ->
    {:ok, new_state}
end
```

Alternatively, propagate the flow_jump info to the caller so it can set up the cross-flow context properly.
