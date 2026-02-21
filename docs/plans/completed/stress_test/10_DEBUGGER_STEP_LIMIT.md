# 10 Debugger Step Limit

> **Gap:** 9 -- Debugger Step Limit
> **Priority:** LOW | **Effort:** Trivial
> **Dependencies:** Debugger engine and handlers (implemented)
> **Previous:** `09_CROSS_FLOW_NAVIGATION.md` | **Next:** None (final document)
> **Last Updated:** February 20, 2026

---

## Context and Current State

### What exists today

The flow debugger is a pure functional state machine that executes flow graphs step by step. It has a built-in step limit to protect against infinite loops.

**Evaluator State:** `/Users/adnumaro/Work/Personal/Code/storyarn/lib/storyarn/flows/evaluator/state.ex`

```elixir
defstruct [
  # ...
  step_count: 0,
  max_steps: 500,     # <-- Current default
  # ...
]
```

- `@type status :: :paused | :waiting_input | :finished`
- `step_count` starts at 0, incremented each step in `Engine.step/3`.
- `max_steps` defaults to 500.

**Engine step limit clause:** `/Users/adnumaro/Work/Personal/Code/storyarn/lib/storyarn/flows/evaluator/engine.ex` (lines 97--103)

```elixir
def step(%State{step_count: count, max_steps: max} = state, _nodes, _connections)
    when count >= max do
  state =
    EngineHelpers.add_console(state, :error, nil, "", "Max steps (#{max}) reached — possible infinite loop")

  {:error, %{state | status: :finished}, :max_steps}
end
```

When the limit is hit:
1. An error-level console message is logged.
2. The state's status is set to `:finished`.
3. The engine returns `{:error, state, :max_steps}`.

The debug session is **permanently stopped** -- the designer must reset and start over. There is no way to continue past the limit.

**Handler side:** `/Users/adnumaro/Work/Personal/Code/storyarn/lib/storyarn_web/live/flow_live/handlers/debug_execution_handlers.ex`

- `apply_step_result/2` (lines 300--304) catches `{:error, state, _reason}` and updates the socket. The `:finished` status causes auto-play to stop and step buttons to be disabled.

**Debug panel UI:** `/Users/adnumaro/Work/Personal/Code/storyarn/lib/storyarn_web/live/flow_live/components/debug_panel.ex`

- Step button disabled when `@debug_state.status in [:finished]` (line 96).
- Status badge shows "Finished" for `:finished` status (line 297).
- No special UI for the max_steps case -- it looks the same as a normal finish.

**Snapshots use Erlang structural sharing** -- snapshots are just Elixir maps pointing to the same variable data. At 1,000 steps, memory overhead is negligible because only changed fields create new allocations. There is no performance concern with raising the limit.

**Existing tests:**

- `/Users/adnumaro/Work/Personal/Code/storyarn/test/storyarn/flows/evaluator/engine_test.exs` (lines 1098--1124) -- "max steps" describe block tests the current behavior where the engine returns `{:error, state, :max_steps}` and status is `:finished`.
- `/Users/adnumaro/Work/Personal/Code/storyarn/test/storyarn_web/live/flow_live/handlers/debug_handlers_test.exs` -- tests auto-play, step, pause, reset, and breakpoints.

### What needs to change

1. **Raise default `max_steps`** from 500 to 1,000.
2. **Instead of hard-stopping**, pause execution and prompt the user to continue for another 1,000 steps. The engine should return a new result type (e.g., `{:step_limit, state}`) instead of `{:error, state, :max_steps}`.
3. **New "continue" action** that increments `max_steps` by 1,000 and resumes execution.
4. **UI prompt** in the debug panel showing "Step limit reached. Continue for another 1,000 steps?" with a button.

### Design

The change is minimal and surgical:
- `State.max_steps` default changes from 500 to 1,000.
- `Engine.step/3` max_steps clause changes from `{:error, ..., :max_steps}` to `{:step_limit, state}` where `state.status` remains `:paused` (not `:finished`).
- A new handler `handle_debug_continue_past_limit/1` bumps `max_steps` by 1,000 and resumes stepping.
- The debug panel shows a "Continue" prompt when the engine hits the step limit (detected by checking if `step_count >= max_steps` and status is `:paused`).

---

## Subtask 1: Change Default -- max_steps: 500 to 1000

### Description

Update the default `max_steps` value in the evaluator state struct from 500 to 1,000.

### Files Affected

| File                                            | Action                                       |
|-------------------------------------------------|----------------------------------------------|
| `lib/storyarn/flows/evaluator/state.ex`         | Change `max_steps: 500` to `max_steps: 1000` |
| `test/storyarn/flows/evaluator/engine_test.exs` | No change (test overrides `max_steps` to 5)  |

### Implementation Steps

1. **Edit `state.ex` line 107:**

```elixir
# Before:
max_steps: 500,

# After:
max_steps: 1000,
```

2. **Verify no test relies on the 500 default.** Checking the existing test at lines 1098--1124: the test overrides `max_steps` to 5 (`state = %{state | max_steps: 5}`), so it does not depend on the default value.

### Test Battery

```elixir
describe "default max_steps" do
  test "state initializes with max_steps 1000" do
    state = Engine.init(%{}, 1)
    assert state.max_steps == 1000
  end
end
```

> Run `mix test` and `mix credo --strict` before proceeding.

---

## Subtask 2: Change Engine Behavior -- Return {:step_limit, state} Instead of {:error, state, :max_steps}

### Description

Modify the `Engine.step/3` clause that fires when `step_count >= max_steps`. Instead of finishing the session with an error, pause the session and return a new `{:step_limit, state}` tuple that signals "limit reached, awaiting user decision."

### Files Affected

| File                                            | Action                   |
|-------------------------------------------------|--------------------------|
| `lib/storyarn/flows/evaluator/engine.ex`        | Change max_steps clause  |
| `test/storyarn/flows/evaluator/engine_test.exs` | Update "max steps" tests |

### Implementation Steps

1. **Edit the max_steps guard clause** in `engine.ex` (lines 97--103):

```elixir
# Before:
def step(%State{step_count: count, max_steps: max} = state, _nodes, _connections)
    when count >= max do
  state =
    EngineHelpers.add_console(state, :error, nil, "", "Max steps (#{max}) reached — possible infinite loop")

  {:error, %{state | status: :finished}, :max_steps}
end

# After:
def step(%State{step_count: count, max_steps: max} = state, _nodes, _connections)
    when count >= max do
  state =
    EngineHelpers.add_console(
      state,
      :warning,
      nil,
      "",
      "Step limit (#{max}) reached — possible infinite loop. Continue or reset."
    )

  {:step_limit, %{state | status: :paused}}
end
```

Key changes:
- Console level changes from `:error` to `:warning` (it is not a terminal error anymore).
- Status stays `:paused` instead of `:finished` (the session is still alive).
- Returns `{:step_limit, state}` instead of `{:error, state, :max_steps}`.

2. **Add a new function `extend_step_limit/1`** to `Engine`:

```elixir
@doc """
Extend the step limit by 1000 steps.
Called when the user chooses to continue past the step limit.
"""
@spec extend_step_limit(State.t()) :: State.t()
def extend_step_limit(%State{} = state) do
  new_max = state.max_steps + 1000

  state
  |> EngineHelpers.add_console(:info, nil, "", "Step limit extended to #{new_max}")
  |> Map.put(:max_steps, new_max)
end
```

3. **Update the `@spec step/3` typespec** to include `{:step_limit, State.t()}`:

```elixir
@spec step(State.t(), map(), list()) ::
        {:ok, State.t()}
        | {:waiting_input, State.t()}
        | {:finished, State.t()}
        | {:flow_jump, State.t(), integer()}
        | {:flow_return, State.t()}
        | {:step_limit, State.t()}
        | {:error, State.t(), atom()}
```

### Test Battery

Update the existing "max steps" describe block in `engine_test.exs`:

```elixir
describe "max steps" do
  test "pauses with :step_limit after max_steps" do
    nodes = %{
      1 => node(1, "hub"),
      2 => node(2, "hub")
    }

    # Circular: 1 -> 2 -> 1
    conns = [conn(1, "default", 2), conn(2, "default", 1)]
    state = Engine.init(%{}, 1)
    state = %{state | max_steps: 5}

    # Step until limit
    {result, state} =
      Enum.reduce_while(1..10, {:ok, state}, fn _i, {_status, s} ->
        case Engine.step(s, nodes, conns) do
          {:ok, new_s} -> {:cont, {:ok, new_s}}
          {:step_limit, new_s} -> {:halt, {:step_limit, new_s}}
          other -> {:halt, other}
        end
      end)

    assert result == :step_limit
    assert state.status == :paused
    assert state.step_count == 5
    assert Enum.any?(state.console, &(&1.message =~ "Step limit"))
    # Crucially, status is NOT :finished
    refute state.status == :finished
  end

  test "extend_step_limit increases max_steps by 1000" do
    state = Engine.init(%{}, 1)
    state = %{state | max_steps: 5, step_count: 5}

    state = Engine.extend_step_limit(state)

    assert state.max_steps == 1005
    assert Enum.any?(state.console, &(&1.message =~ "extended to 1005"))
  end

  test "can continue stepping after extend_step_limit" do
    nodes = %{
      1 => node(1, "hub"),
      2 => node(2, "exit")
    }

    conns = [conn(1, "default", 2)]
    state = Engine.init(%{}, 1)
    state = %{state | max_steps: 1}

    # Hit limit
    {:step_limit, state} = Engine.step(state, nodes, conns)
    assert state.step_count == 1
    assert state.status == :paused

    # Extend and continue
    state = Engine.extend_step_limit(state)
    {:ok, state} = Engine.step(state, nodes, conns)
    assert state.current_node_id == 2
    assert state.step_count == 2
  end
end
```

> Run `mix test` and `mix credo --strict` before proceeding.

---

## Subtask 3: Handler -- Handle the New :step_limit Status

### Description

Update the debug execution handlers to handle the `{:step_limit, state}` result from the engine. When the step limit is hit, the handler should:
1. Assign the new state (status: `:paused`).
2. Set a new assign `debug_step_limit_reached: true` so the UI can show the continue prompt.
3. Stop auto-play if active.

### Files Affected

| File                                                                   | Action                                                  |
|------------------------------------------------------------------------|---------------------------------------------------------|
| `lib/storyarn_web/live/flow_live/handlers/debug_execution_handlers.ex` | Handle `:step_limit` result, reset flag on normal steps |
| `lib/storyarn_web/live/flow_live/show.ex`                              | Add `debug_step_limit_reached` assign                   |
| `test/storyarn_web/live/flow_live/handlers/debug_handlers_test.exs`    | Add tests                                               |

### Implementation Steps

1. **Add `debug_step_limit_reached: false` assign** in `show.ex` `handle_async(:load_flow_data, ...)` (around line 735, alongside other debug assigns):

```elixir
|> assign(:debug_step_limit_reached, false)
```

2. **Add a clause to `apply_step_result/2`** in `debug_execution_handlers.ex` for the new `:step_limit` tuple. Insert it before the catch-all clause (line 300):

```elixir
defp apply_step_result({:step_limit, state}, socket) do
  socket =
    socket
    |> assign(:debug_state, state)
    |> assign(:debug_step_limit_reached, true)
    |> cancel_auto_timer()
    |> assign(:debug_auto_playing, false)

  {:continue, socket}
end
```

3. **Clear the flag on normal step results.** In the existing catch-all clause at line 300:

```elixir
# Before:
defp apply_step_result({_status, state}, socket),
  do: {:continue, assign(socket, :debug_state, state)}

# After:
defp apply_step_result({_status, state}, socket) do
  {:continue,
   socket
   |> assign(:debug_state, state)
   |> assign(:debug_step_limit_reached, false)}
end
```

4. **Also clear the flag in the error catch-all** (line 303):

```elixir
defp apply_step_result({:error, state, _reason}, socket) do
  {:continue,
   socket
   |> assign(:debug_state, state)
   |> assign(:debug_step_limit_reached, false)}
end
```

### Test Battery

Add to `debug_handlers_test.exs`:

```elixir
describe "step limit handling" do
  test "step_limit result sets debug_step_limit_reached flag" do
    # Create a circular flow with max_steps: 1
    nodes = %{
      1 => node(1, "hub"),
      2 => node(2, "hub")
    }
    connections = [conn(1, "default", 2), conn(2, "default", 1)]

    state = Engine.init(%{}, 1)
    state = %{state | max_steps: 1}

    socket = build_socket(%{
      debug_state: state,
      debug_nodes: nodes,
      debug_connections: connections,
      debug_step_limit_reached: false
    })

    {:noreply, result} = DebugHandlers.handle_debug_step(socket)

    assert result.assigns.debug_step_limit_reached == true
    assert result.assigns.debug_state.status == :paused
    # Step button should still work (status is :paused, not :finished)
    refute result.assigns.debug_state.status == :finished
  end

  test "step_limit stops auto-play" do
    nodes = %{
      1 => node(1, "hub"),
      2 => node(2, "hub")
    }
    connections = [conn(1, "default", 2), conn(2, "default", 1)]

    state = Engine.init(%{}, 1)
    state = %{state | max_steps: 1}

    socket = build_socket(%{
      debug_state: state,
      debug_nodes: nodes,
      debug_connections: connections,
      debug_auto_playing: true,
      debug_step_limit_reached: false
    })

    {:noreply, result} = DebugHandlers.handle_debug_auto_step(socket)

    assert result.assigns.debug_auto_playing == false
    assert result.assigns.debug_step_limit_reached == true
  end

  test "normal step clears step_limit_reached flag" do
    nodes = %{
      1 => node(1, "entry"),
      2 => node(2, "hub"),
      3 => node(3, "exit")
    }
    connections = [conn(1, "default", 2), conn(2, "default", 3)]

    state = Engine.init(%{}, 1)

    socket = build_socket(%{
      debug_state: state,
      debug_nodes: nodes,
      debug_connections: connections,
      debug_step_limit_reached: true
    })

    {:noreply, result} = DebugHandlers.handle_debug_step(socket)

    assert result.assigns.debug_step_limit_reached == false
  end
end
```

> Run `mix test` and `mix credo --strict` before proceeding.

---

## Subtask 4: Continue Action -- New "debug_continue_past_limit" Event

### Description

Add a new LiveView event handler that extends the step limit by 1,000 and resumes execution. Wire it up in the facade and session handlers.

### Files Affected

| File                                                                 | Action                                               |
|----------------------------------------------------------------------|------------------------------------------------------|
| `lib/storyarn_web/live/flow_live/handlers/debug_session_handlers.ex` | Add `handle_debug_continue_past_limit/1`             |
| `lib/storyarn_web/live/flow_live/handlers/debug_handlers.ex`         | Add `defdelegate`                                    |
| `lib/storyarn_web/live/flow_live/show.ex`                            | Add `handle_event("debug_continue_past_limit", ...)` |
| `lib/storyarn_web/live/flow_live/components/debug_panel.ex`          | Add continue prompt UI                               |
| `test/storyarn_web/live/flow_live/handlers/debug_handlers_test.exs`  | Add tests                                            |

### Implementation Steps

1. **Add handler in `debug_session_handlers.ex`:**

```elixir
def handle_debug_continue_past_limit(socket) do
  state = socket.assigns.debug_state

  new_state = Engine.extend_step_limit(state)

  {:noreply,
   socket
   |> assign(:debug_state, new_state)
   |> assign(:debug_step_limit_reached, false)}
end
```

2. **Add delegation in `debug_handlers.ex`:**

```elixir
defdelegate handle_debug_continue_past_limit(socket), to: DebugSessionHandlers
```

3. **Add event handler in `show.ex`:**

```elixir
def handle_event("debug_continue_past_limit", _params, socket) do
  DebugHandlers.handle_debug_continue_past_limit(socket)
end
```

4. **Add continue prompt in `debug_panel.ex`.** Insert a banner between the controls bar and the tab content when the step limit is reached:

```elixir
<%!-- Step limit prompt --%>
<div
  :if={@debug_step_limit_reached}
  class="flex items-center gap-3 px-3 py-2 bg-warning/10 border-b border-warning/20 shrink-0"
>
  <.icon name="alert-triangle" class="size-4 text-warning shrink-0" />
  <span class="text-xs text-warning">
    {dgettext("flows", "Step limit (%{count}) reached -- possible infinite loop.",
      count: @debug_state.max_steps)}
  </span>
  <button
    type="button"
    class="btn btn-warning btn-xs"
    phx-click="debug_continue_past_limit"
  >
    {dgettext("flows", "Continue (+1000 steps)")}
  </button>
</div>
```

5. **Add `debug_step_limit_reached` attr to `debug_panel`:**

```elixir
attr :debug_step_limit_reached, :boolean, default: false
```

6. **Pass the assign in `show.ex` render:**

```elixir
<.debug_panel
  ...existing attrs...
  debug_step_limit_reached={@debug_step_limit_reached}
/>
```

### Test Battery

Add to `debug_handlers_test.exs`:

```elixir
describe "handle_debug_continue_past_limit/1" do
  test "extends max_steps by 1000 and clears flag" do
    state = Engine.init(%{}, 1)
    state = %{state | max_steps: 5, step_count: 5}

    socket = build_socket(%{
      debug_state: state,
      debug_step_limit_reached: true
    })

    {:noreply, result} = DebugHandlers.handle_debug_continue_past_limit(socket)

    assert result.assigns.debug_state.max_steps == 1005
    assert result.assigns.debug_step_limit_reached == false
    assert result.assigns.debug_state.status == :paused
  end

  test "stepping works after continuing past limit" do
    nodes = %{
      1 => node(1, "hub"),
      2 => node(2, "exit")
    }
    connections = [conn(1, "default", 2)]

    state = Engine.init(%{}, 1)
    state = %{state | max_steps: 1, step_count: 1}

    socket = build_socket(%{
      debug_state: state,
      debug_nodes: nodes,
      debug_connections: connections,
      debug_step_limit_reached: true
    })

    # Continue past limit
    {:noreply, socket} = DebugHandlers.handle_debug_continue_past_limit(socket)
    assert socket.assigns.debug_state.max_steps == 1001

    # Now step should work
    {:noreply, result} = DebugHandlers.handle_debug_step(socket)
    assert result.assigns.debug_state.step_count >= 2
    assert result.assigns.debug_step_limit_reached == false
  end
end
```

> Run `mix test` and `mix credo --strict` before proceeding.

---

## Subtask 5: Update Existing Tests for New Behavior

### Description

Review and update all existing tests that assert the old `{:error, state, :max_steps}` behavior to use the new `{:step_limit, state}` pattern.

### Files Affected

| File                                                                | Action                                                           |
|---------------------------------------------------------------------|------------------------------------------------------------------|
| `test/storyarn/flows/evaluator/engine_test.exs`                     | Update "max steps" describe block (already handled in Subtask 2) |
| `test/storyarn_web/live/flow_live/handlers/debug_handlers_test.exs` | Verify no test assumes :max_steps error result                   |

### Implementation Steps

1. **Search for `:max_steps` in all test files:**

The only test that directly tests this is in `engine_test.exs` lines 1098--1124, which was already updated in Subtask 2.

2. **Search for `:finished` status assumptions in debug handler tests:** Review `debug_handlers_test.exs` to ensure no test creates a state with `max_steps` where the old error path would be triggered. The existing tests use `%{state | status: :finished}` directly (line 160) and do not trigger the max_steps path through stepping.

3. **Verify `apply_step_result` ordering:** Ensure the new `:step_limit` clause is matched before the existing catch-all in `debug_execution_handlers.ex`. The pattern match `{:step_limit, state}` is a 2-tuple while the catch-all `{_status, state}` also matches 2-tuples. Place the `:step_limit` clause BEFORE the catch-all.

### Test Battery

Run the full test suite to verify nothing is broken:

```bash
mix test
mix credo --strict
```

No new tests needed -- this subtask is a verification pass.

> Run `mix test` and `mix credo --strict` before proceeding.

---

## Summary

| Subtask              | What it delivers                                          | Key files                                     |
|----------------------|-----------------------------------------------------------|-----------------------------------------------|
| 1. Default change    | `max_steps: 1000`                                         | `state.ex`                                    |
| 2. Engine behavior   | `{:step_limit, state}` + `extend_step_limit/1`            | `engine.ex`, `engine_test.exs`                |
| 3. Handler           | `apply_step_result({:step_limit, ...})` + flag management | `debug_execution_handlers.ex`, `show.ex`      |
| 4. Continue action   | `debug_continue_past_limit` event + UI prompt             | `debug_session_handlers.ex`, `debug_panel.ex` |
| 5. Test verification | Ensure all existing tests pass with new behavior          | All test files                                |

**This is the final document in the stress test plan series.**
