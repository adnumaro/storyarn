# Flow Debugger / Inspector

> **Status:** Planning
> **Priority:** High
> **Depends on:** Flow Editor (complete), Variable System (complete)

## Overview

A Chrome DevTools-style debugging panel for flows. Allows authors to execute flows step-by-step or automatically, evaluate conditions against variable state, execute instructions that mutate variables in real time, and inspect the full execution history — all without leaving the flow editor.

**This is NOT a preview.** It is an inspector: a tool for testing narrative logic, finding broken conditions, and verifying variable mutations across the flow graph.

---

## Competitive Research

### Arcweaver — Play Mode + Debugger

- **Play Mode** runs in a separate browser tab as a choose-your-path experience
- **Quickstart from any element** — right-click → "Quickstart Play Mode from here"
- **Debugger panel** shows two columns per variable: **Before-render** and **After-render** — you see the state before and after each node's code executes
- **Color coding**: orange = changed by code, cyan = changed manually by tester
- **Force-assign** — edit values directly in the "before" column to test edge cases
- **Undo last choice** — step backward without full restart
- **Live sync** — editor changes auto-reflect in Play Mode

### articy:draft — Presentation Mode + Simulation

- **Analysis Mode vs Player Mode** toggle:
  - Analysis: shows ALL branches, failed conditions highlighted in **red**
  - Player: hides branches whose conditions fail (simulates real player experience)
- **3-column variable tracking**: Initial / Previous / Current — both per-step delta and cumulative drift visible at a glance
- **Sub-expression condition debugging** — when a condition fails, articy highlights the **specific rule** that caused the failure, not just "condition failed"
- **Journeys** — saved playthroughs that can be replayed for regression testing
- **Override initial values** per journey — test fixtures for narrative testing
- **Live Property Inspector** — synchronized variable watch panel alongside the presentation
- **Function return prompts** — when encountering functions that can't be evaluated, prompts user for expected return value

### Features adopted for Storyarn

| Feature                        | Origin    | Storyarn adaptation                                                                   |
|--------------------------------|-----------|---------------------------------------------------------------------------------------|
| Before/After + 3-column state  | Both      | **4-column variable view**: Initial / Previous / Current / Source (who changed it)    |
| Analysis vs Player mode        | articy    | **Toggle in debug panel**: show all branches (failed in red) vs only valid ones       |
| Sub-expression highlighting    | articy    | **Per-rule evaluation detail** in console: which specific rule failed and why         |
| Force-assign with color coding | Arcweaver | **Color-coded variables**: blue = user override, orange = changed by instruction node |
| Undo / step backward           | Arcweaver | **Undo step** button: revert to previous state snapshot                               |
| Journeys (saved paths)         | articy    | **Phase 3**: save debug sessions as named test cases for regression                   |

---

## Core Concepts

### Debug Session

An ephemeral, in-memory session (socket assigns) that tracks:

- **Current node** — where execution is right now
- **Variable state** — mutable copy of all project variables with change tracking
- **Variable snapshots** — stack of previous states for undo capability
- **Execution path** — ordered list of visited nodes
- **History log** — timestamped events (variable changes, errors, decisions)
- **Console messages** — errors, warnings, info entries
- **Status** — `:paused | :running | :waiting_input | :finished`
- **View mode** — `:analysis | :player` (show all branches vs only valid)

Sessions are not persisted. Closing the debug panel or navigating away discards all state.

### Execution Model

The debugger traverses the flow graph node by node:

1. **Entry/Hub nodes** — pass through automatically, follow the single output connection
2. **Condition nodes** — evaluate rules against current variable state, follow the matching branch
3. **Instruction nodes** — execute assignments (mutate variable state), follow the single output
4. **Dialogue nodes** — pause execution, present response options to the user in the debug panel
5. **Exit nodes** — end execution
6. **Jump nodes** — Phase 3 (cross-flow), initially treated as exit

### Variable State

- Initialized from block values in the database (the `value` field on each block)
- User can override initial values before starting a debug session
- Instruction nodes mutate this state during execution
- State is displayed in the Variables tab and updated in real time
- **4-column tracking** per variable: Initial / Previous / Current / Source
- **Color coding**: blue = user override, orange = instruction mutation, no color = unchanged

### View Modes (inspired by articy:draft)

- **Analysis mode** (default): Shows ALL branches at condition/dialogue nodes, including those whose conditions fail. Failed branches are visually marked in red on the canvas. Console logs detail why each branch passed or failed.
- **Player mode**: Hides branches whose conditions evaluate to false. Only shows options the player would actually see. Simulates the real game experience.

Toggle between modes at any time during a debug session.

---

## Architecture

### New Domain Modules

```
lib/storyarn/flows/
  evaluator/
    engine.ex              # State machine: step, step_back, auto_run, evaluate_node
    condition_eval.ex      # Evaluate condition map against variable state (per-rule detail)
    instruction_exec.ex    # Execute instruction assignments, return new state + changes
    state.ex               # DebugState struct definition
```

#### `Evaluator.State`

```elixir
defmodule Storyarn.Flows.Evaluator.State do
  defstruct [
    :start_node_id,
    :current_node_id,
    :status,                 # :paused | :running | :waiting_input | :finished
    :view_mode,              # :analysis | :player
    variables: %{},           # "mc.jaime.health" => %{value: 80, source: :instruction, ...}
    initial_variables: %{},   # snapshot for reset (DB values + user overrides)
    previous_variables: %{},  # snapshot from the previous step (for 3-column diff)
    snapshots: [],            # [{node_id, variables_snapshot}] — stack for undo
    history: [],              # [%{ts, node_id, type, details}]
    console: [],              # [%{ts, level, node_id, message, rule_details}]
    execution_path: [],       # [node_id, ...] ordered
    pending_choices: nil,     # nil | %{node_id, responses: [...], all_responses: [...]}
    step_count: 0,            # for infinite loop protection
    max_steps: 500            # configurable limit
  ]
end
```

**Variable entry structure:**

```elixir
# Each variable in the state map
%{
  value: 80,                    # current value
  initial_value: 100,           # value at session start
  previous_value: 100,          # value at previous step
  source: :instruction,         # :initial | :user_override | :instruction
  block_type: "number",         # for operator validation
  block_id: "uuid",             # reference to actual block
  sheet_shortcut: "mc.jaime",   # for display
  variable_name: "health"       # for display
}
```

#### `Evaluator.Engine`

Pure functional module. Receives state + flow graph, returns new state.

```elixir
# Step forward one node
Engine.step(debug_state, flow_nodes, flow_connections)
# Returns:
#   {:ok, new_debug_state}
#   {:waiting_input, new_debug_state, choices}
#   {:finished, new_debug_state}
#   {:error, new_debug_state, reason}

# Step backward (undo last step)
Engine.step_back(debug_state)
# Returns:
#   {:ok, new_debug_state}    — restored from snapshots stack
#   {:error, :no_history}     — already at the start

# User selects a dialogue response
Engine.choose_response(debug_state, response_id, flow_connections)
# Returns {:ok, new_debug_state} with current_node advanced

# Initialize state from project variables
Engine.init(project_id, start_node_id, variable_overrides \\ %{})
# Returns %DebugState{}

# Reset to initial state
Engine.reset(debug_state)
# Returns %DebugState{} with variables restored to initial_variables
```

#### `Evaluator.ConditionEval`

Evaluates a condition map (`%{"logic" => "all", "rules" => [...]}`) against the variable state.
Returns **per-rule evaluation detail** for debugging (inspired by articy's sub-expression highlighting).

```elixir
ConditionEval.evaluate(condition_map, variables)
# Returns: {true | false, rule_results}
# where rule_results = [
#   %{rule_id: "r1", passed: true, variable: "mc.jaime.health",
#     operator: "greater_than", value: "50", actual_value: 80},
#   %{rule_id: "r2", passed: false, variable: "mc.jaime.has_key",
#     operator: "is_true", value: nil, actual_value: false}
# ]

ConditionEval.evaluate_rule(rule, variables)
# Returns: {true | false, rule_detail}
```

**Operator evaluation mapping (mirrors `Storyarn.Flows.Condition` operators):**

| Block type     | Operator              | Evaluation                              |
|----------------|-----------------------|-----------------------------------------|
| number         | equals                | `var == parse_number(value)`            |
| number         | not_equals            | `var != parse_number(value)`            |
| number         | greater_than          | `var > parse_number(value)`             |
| number         | less_than             | `var < parse_number(value)`             |
| number         | greater_than_or_equal | `var >= parse_number(value)`            |
| number         | less_than_or_equal    | `var <= parse_number(value)`            |
| boolean        | is_true               | `var == true`                           |
| boolean        | is_false              | `var == false`                          |
| boolean        | is_nil                | `var == nil`                            |
| text           | equals                | `var == value`                          |
| text           | contains              | `String.contains?(var, value)`          |
| text           | starts_with           | `String.starts_with?(var, value)`       |
| text           | ends_with             | `String.ends_with?(var, value)`         |
| text           | is_empty              | `var in [nil, ""]`                      |
| select         | equals                | `var == value`                          |
| select         | not_equals            | `var != value`                          |
| select         | is_nil                | `var == nil`                            |
| multi_select   | contains              | `value in var`                          |
| multi_select   | not_contains          | `value not in var`                      |
| multi_select   | is_empty              | `var in [nil, []]`                      |
| date           | equals                | `Date.compare(var, value) == :eq`       |
| date           | before                | `Date.compare(var, value) == :lt`       |
| date           | after                 | `Date.compare(var, value) == :gt`       |

**Logic modes:**
- `"all"` (AND) — all rules must be true
- `"any"` (OR) — at least one rule must be true

#### `Evaluator.InstructionExec`

Executes a list of assignments against the variable state, returns the new state.

```elixir
InstructionExec.execute(assignments, variables)
# Returns: {:ok, new_variables, changes}
# where changes = [%{variable: "mc.jaime.health", old: 100, new: 80, operator: "subtract"}]
```

**Operator execution mapping (mirrors `Storyarn.Flows.Instruction` operators):**

| Block type | Operator  | Execution                               |
|------------|-----------|-----------------------------------------|
| number     | set       | `value`                                 |
| number     | add       | `current + parse_number(value)`         |
| number     | subtract  | `current - parse_number(value)`         |
| boolean    | set_true  | `true`                                  |
| boolean    | set_false | `false`                                 |
| boolean    | toggle    | `!current`                              |
| text       | set       | `value`                                 |
| text       | clear     | `nil`                                   |
| select     | set       | `value`                                 |
| date       | set       | `value`                                 |

**Variable references:** When `value_type == "variable_ref"`, resolve the value from another variable in state before applying the operator.

### Node Traversal Logic

For each node type, the engine follows this logic:

```
evaluate_node(node, debug_state, connections) ->

  ENTRY:
    → log "Execution started"
    → push snapshot to undo stack
    → follow single output connection
    → {:ok, next_node_id}

  DIALOGUE:
    → push snapshot to undo stack
    → check input_condition (if present):
        - evaluate against variables with per-rule detail
        - if false:
            log error with rule breakdown (which rule failed, actual vs expected)
            in analysis mode: mark node as error, continue to present choices
            in player mode: skip node, follow output
        - if true: continue
    → execute output_instruction if present (mutate variables before presenting choices)
    → if node has responses:
        - evaluate each response's condition with per-rule detail
        - in analysis mode: present ALL responses, mark failed ones in red
        - in player mode: present only valid responses
        - return {:waiting_input, choices}
    → if no responses:
        - follow single "output" connection
        - {:ok, next_node_id}

  CONDITION (boolean mode):
    → push snapshot to undo stack
    → evaluate condition rules against variables with per-rule detail
    → result = true | false
    → log which branch was taken with full rule breakdown:
        "Branch: true — mc.jaime.health (80) > 50 ✓, mc.jaime.has_key (false) is_true ✗"
    → in analysis mode: mark the non-taken branch in red on canvas
    → follow connection from matching output pin ("true" or "false")
    → {:ok, next_node_id}

  CONDITION (switch mode):
    → push snapshot to undo stack
    → evaluate each rule independently with per-rule detail
    → first matching rule determines the output pin
    → if none match, follow "default" pin
    → log which case matched and why others didn't
    → in analysis mode: mark non-matching cases in red
    → {:ok, next_node_id}

  INSTRUCTION:
    → push snapshot to undo stack
    → execute all assignments
    → log each variable change: "mc.jaime.health: 100 → 80 (subtract 20)"
    → update variable source to :instruction
    → follow single output connection
    → {:ok, next_node_id}

  HUB:
    → push snapshot to undo stack
    → pass through, follow single output
    → {:ok, next_node_id}

  JUMP:
    → Phase 1: log "Jump to flow X" as info, end execution
    → Phase 3: push call stack, load target flow, continue
    → {:finished} (Phase 1) or {:ok, target_node_id} (Phase 3)

  EXIT:
    → log "Execution finished"
    → {:finished}

  NO CONNECTION FOUND:
    → log error "No outgoing connection from pin X"
    → {:finished}
```

### LiveView Integration

#### New Socket Assigns

```elixir
# In flow_live/show.ex
assign(socket,
  debug_state: nil,             # %DebugState{} | nil (nil = debug mode off)
  debug_panel_open: false,      # panel visibility
  debug_active_tab: "console",  # "console" | "variables" | "history" | "path"
  debug_view_mode: :analysis    # :analysis | :player
)
```

#### New Handler Module

```
lib/storyarn_web/live/flow_live/
  handlers/
    debug_handlers.ex    # All debug-related event handlers
```

**Events from the UI:**

| Event                      | Action                                               |
|----------------------------|------------------------------------------------------|
| `debug_start`              | Init debug state, open panel, highlight node         |
| `debug_start_from_node`    | Init debug state starting from specific node         |
| `debug_step`               | Call Engine.step, update state, push to canvas       |
| `debug_step_back`          | Call Engine.step_back, restore snapshot              |
| `debug_play`               | Set status to :running, start auto-step timer        |
| `debug_pause`              | Set status to :paused, cancel timer                  |
| `debug_stop`               | Clear debug state, close panel, reset canvas         |
| `debug_restart`            | Reset state to initial, restart from start node      |
| `debug_choose_response`    | Call Engine.choose_response, continue                |
| `debug_set_variable`       | Manually update a variable (source = :user_override) |
| `debug_set_speed`          | Update auto-play interval                            |
| `debug_switch_tab`         | Change active tab in panel                           |
| `debug_set_initial_state`  | Override variable values before starting             |
| `debug_toggle_view_mode`   | Switch between :analysis and :player mode            |

**Auto-play mechanism:**

```elixir
# On debug_play
Process.send_after(self(), :debug_auto_step, speed_ms)

# handle_info(:debug_auto_step, socket)
# → Engine.step(...)
# → if :running and not :waiting_input, schedule next step
# → if :waiting_input or :finished, stop auto-play
```

#### New Component Module

```
lib/storyarn_web/live/flow_live/
  components/
    debug_panel.ex    # Bottom panel: controls + tabs
```

### JavaScript / Canvas Integration

#### Debug Overlay Events (LiveView → JS)

| Push event                  | Payload                                    | Canvas action                                   |
|-----------------------------|--------------------------------------------|-------------------------------------------------|
| `debug_highlight_node`      | `{node_id, type}`                          | Add pulsing border to current node              |
| `debug_mark_visited`        | `{node_id}`                                | Add green tint / checkmark                      |
| `debug_mark_error`          | `{node_id}`                                | Add red tint                                    |
| `debug_mark_branch_failed`  | `{node_id, pin, reason}`                   | Red tint on specific output pin (analysis mode) |
| `debug_animate_edge`        | `{source_id, target_id, source_pin}`       | Animate dash flow on connection                 |
| `debug_dim_edges`           | `{except: [connection_ids]}`               | Reduce opacity on non-taken paths               |
| `debug_clear`               | `{}`                                       | Remove all debug overlays                       |
| `debug_scroll_to_node`      | `{node_id}`                                | Pan canvas to center on node                    |
| `debug_clear_last_step`     | `{node_id, edges}`                         | Remove highlights from undone step              |

#### CSS Animations

```css
/* Current node — pulsing glow */
.debug-current {
  animation: debug-pulse 1.5s ease-in-out infinite;
  box-shadow: 0 0 0 3px var(--debug-active-color);
}

/* Visited node — subtle green tint */
.debug-visited {
  outline: 2px solid oklch(0.72 0.15 155);
  outline-offset: 2px;
}

/* Error node — red tint */
.debug-error {
  outline: 2px solid oklch(0.65 0.2 25);
  outline-offset: 2px;
}

/* Failed branch indicator (analysis mode) — red on specific pin */
.debug-branch-failed {
  outline: 2px dashed oklch(0.65 0.2 25);
  opacity: 0.5;
}

/* Connection animation — flowing dashes */
.debug-edge-active {
  stroke-dasharray: 8 4;
  animation: debug-flow 0.6s linear infinite;
}

@keyframes debug-flow {
  to { stroke-dashoffset: -12; }
}

/* Dimmed connections */
.debug-edge-dim {
  opacity: 0.2;
}

/* Variable change source indicators */
.debug-var-instruction { color: oklch(0.75 0.15 55); }  /* orange — changed by instruction */
.debug-var-user        { color: oklch(0.72 0.15 230); }  /* blue — changed by user */
.debug-var-unchanged   { color: oklch(0.6 0 0); }        /* gray — no change */
```

---

## UI Design

### Panel Layout

The debug panel appears at the bottom of the flow editor, resizable vertically. The canvas area shrinks to accommodate it.

```
┌──────────────────────────────────────────────────────────────┐
│                                                              │
│                    Flow Canvas                               │
│                 (shrinks vertically)                          │
│                                                              │
├──────────────────────────────────────────────────────────────┤
│ ▶ ⏭ ⏮ ⏸ ⏹ ↺  Speed: [━━━●━━━]  [Analysis|Player]  Paused │
├───────────┬────────────┬──────────┬──────────────────────────┤
│  Console  │  Variables │  History │  Path                    │
├───────────┴────────────┴──────────┴──────────────────────────┤
│                                                              │
│  (active tab content)                                        │
│                                                              │
└──────────────────────────────────────────────────────────────┘
```

### Controls Bar

| Control     | Icon   | Action                                           |
|-------------|--------|--------------------------------------------------|
| Play        | `▶`    | Start/resume auto-play                           |
| Step        | `⏭`    | Advance one node                                 |
| Step Back   | `⏮`    | Undo last step (restore previous snapshot)       |
| Pause       | `⏸`    | Pause auto-play                                  |
| Stop        | `⏹`    | End debug session                                |
| Restart     | `↺`    | Reset to initial state and start node            |
| Speed       | slider | 200ms to 3000ms delay between auto-steps         |
| View Mode   | toggle | Analysis (show all) / Player (valid only)        |

### Console Tab

Scrollable log of debug events with **per-rule detail** for condition evaluations. Each entry has:
- **Timestamp** (relative to session start)
- **Level icon**: `✓` info, `⚠` warning, `✗` error
- **Node reference** (clickable — scrolls canvas to node)
- **Message** with expandable rule breakdown

Example entries:
```
00:00.0  ✓  [Entry]           Execution started
00:00.2  ✓  [Jaime greets]    Dialogue — waiting for response (2 of 3 responses valid)
00:01.5  ✓  [Jaime greets]    User selected: "Tell me more"
00:01.7  ✓  [Apply damage]    mc.jaime.health: 100 → 80 (subtract 20)
00:01.9  ⚠  [Check health]    Condition → false (1 of 2 rules failed)
                                 ✓ Rule 1: mc.jaime.health (80) > 50
                                 ✗ Rule 2: mc.jaime.has_key (false) is_true
00:02.1  ✗  [Branch]          No outgoing connection from pin "false"
00:02.1  ✓  [Exit]            Execution finished
```

The rule breakdown is **expandable/collapsible** — collapsed by default, click to expand. This mirrors articy's sub-expression highlighting but adapted to our rule-based condition system.

### Variables Tab

**4-column table** with change tracking and source color coding.

```
┌─────────────────────────┬──────────┬──────────┬──────────┬─────────┐
│ Variable                │ Type     │ Initial  │ Previous │ Current │
├─────────────────────────┼──────────┼──────────┼──────────┼─────────┤
│ mc.jaime.health         │ number   │ 100      │ 100      │ 80  ◆   │ ← orange (instruction)
│ mc.jaime.class          │ select   │ warrior  │ warrior  │ warrior │ ← gray (unchanged)
│ mc.jaime.is_alive       │ boolean  │ true     │ true     │ true    │
│ world.quest_started     │ boolean  │ false    │ false    │ true  ◆ │ ← blue (user override)
└─────────────────────────┴──────────┴──────────┴──────────┴─────────┘

◆ = value changed    Color: orange = instruction, blue = user override
```

- **Initial** — value at session start (DB value or user override from config modal)
- **Previous** — value at the previous step (like articy's 3-column)
- **Current** — value right now. Clickable for inline editing
- **Source color**: orange = changed by instruction node, blue = manually overridden by user, gray = unchanged
- **Editable in runtime**: clicking the "Current" cell opens an inline editor. Edited values turn blue.
- **Diff highlighting**: values that differ from initial are bold
- **Filter/search**: text input to filter variables by name
- **Filter buttons**: "Changed only" / "All" to toggle visibility

### History Tab

Timeline of variable mutations only, showing what changed, where, and the delta.

```
┌──────────┬─────────────────────┬───────────────────────────────┬────────┐
│ Time     │ Node                │ Change                        │ Source │
├──────────┼─────────────────────┼───────────────────────────────┼────────┤
│ 00:01.7  │ Apply damage        │ mc.jaime.health: 100 → 80    │ instr  │
│ 00:02.3  │ Start quest         │ world.quest_started: F → T   │ instr  │
│ 00:02.5  │ (user override)     │ mc.jaime.health: 80 → 120    │ user   │
│ 00:03.1  │ Heal                │ mc.jaime.health: 120 → 135   │ instr  │
└──────────┴─────────────────────┴───────────────────────────────┴────────┘
```

- Node names are clickable (scroll canvas to that node)
- User overrides are logged separately so the full mutation chain is traceable

### Path Tab

Ordered list of all visited nodes with their type and outcome.

```
1. [Entry]  →  started
2. [Dialogue] Jaime greets  →  response: "Tell me more"
3. [Instruction] Apply damage  →  1 variable changed
4. [Condition] Check health  →  branch: false
5. [Exit]  →  finished
```

Each entry is clickable to scroll the canvas to that node.

### Entry Points

1. **Toolbar button**: "Debug" button in the flow editor toolbar — starts from entry node
2. **Context menu**: Right-click any node → "Start debug here"
3. **Keyboard shortcut**: `Ctrl+D` / `Cmd+D` to toggle debug mode

### Initial State Modal

Before starting a debug session (triggered by any entry point), a modal appears:

```
┌─────────────────────────────────────────────────────┐
│  Configure Debug Session                            │
│                                                     │
│  Start from: [Entry node ▼]                        │
│  View mode:  (●) Analysis  ( ) Player              │
│                                                     │
│  Variables:                             [Filter...] │
│  ┌──────────────────────────┬──────────┬──────────┐ │
│  │ Variable                 │ DB Value │ Override │ │
│  ├──────────────────────────┼──────────┼──────────┤ │
│  │ mc.jaime.health          │ 100      │ [    ]   │ │
│  │ mc.jaime.class           │ warrior  │ [    ]   │ │
│  │ world.quest_started      │ false    │ [    ]   │ │
│  └──────────────────────────┴──────────┴──────────┘ │
│                                                     │
│  [Use DB values]  [Reset overrides]    [Start ▶]   │
└─────────────────────────────────────────────────────┘
```

- Pre-populated with current DB values
- User can override any variable — overridden values shown in blue
- "Use DB values" clears all overrides
- "Start from" dropdown lists all nodes in the flow (entry node preselected)
- View mode selector sets the initial analysis/player toggle

---

## Phases

### Phase 1 — Core Engine + Basic Panel

**Goal:** Step-by-step debugging within a single flow with variable inspection and per-rule condition detail.

**Scope exclusions for Phase 1:**
- No auto-play (step-by-step only)
- No connection animations
- No variable editing in runtime
- No History or Path tabs
- No initial state modal (uses DB values directly)
- No analysis/player toggle (analysis mode only)

#### Task 1: `Evaluator.State` + `Evaluator.ConditionEval` + tests ✅

- [x] `Evaluator.State` struct definition (all fields for debug session)
- [x] `Evaluator.ConditionEval.evaluate/2` — evaluate condition map against variable state
- [x] `Evaluator.ConditionEval.evaluate_rule/2` — evaluate single rule, return detail
- [x] `Evaluator.ConditionEval.evaluate_string/2` — parse JSON string conditions (dialogue fields)
- [x] All condition operators: number, boolean, text, select, multi_select, date
- [x] Logic modes: `"all"` (AND) and `"any"` (OR)
- [x] Edge cases: missing variables → nil, empty rules → true, legacy conditions → skip
- [x] Unit tests for `condition_eval` (60 tests)

**Files:** `lib/storyarn/flows/evaluator/state.ex`, `lib/storyarn/flows/evaluator/condition_eval.ex`, `test/storyarn/flows/evaluator/condition_eval_test.exs`

#### Task 2: `Evaluator.InstructionExec` + tests ✅

- [x] `Evaluator.InstructionExec.execute/2` — execute assignments list, return `{:ok, new_variables, changes, errors}`
- [x] `Evaluator.InstructionExec.execute_string/2` — parse JSON string instructions (dialogue output_instruction)
- [x] All instruction operators: set, add, subtract, set_true, set_false, toggle, clear
- [x] `variable_ref` support (resolve value from another variable in state)
- [x] Edge cases: missing variable → error + skip, incomplete assignment → skip, chained ops
- [x] Unit tests for `instruction_exec` (31 tests)

**Files:** `lib/storyarn/flows/evaluator/instruction_exec.ex`, `test/storyarn/flows/evaluator/instruction_exec_test.exs`

#### Task 3: `Evaluator.Engine` + tests ✅

- [x] `Engine.init/2` — initialize state from pre-loaded variables + start node
- [x] `Engine.step/3` — advance one node (entry, exit, dialogue, condition, instruction, hub, jump, scene, subflow)
- [x] `Engine.step_back/1` — undo last step via snapshots stack
- [x] `Engine.choose_response/3` — user selects a dialogue response, execute response instruction, advance
- [x] `Engine.reset/1` — reset to initial state
- [x] Dialogue: input_condition evaluation, output_instruction execution, response condition evaluation
- [x] Condition: boolean mode + switch mode with per-rule detail logging
- [x] Console logging for each node type (per-rule detail for conditions)
- [x] Execution path tracking, snapshot stack for undo
- [x] Infinite loop protection (max_steps)
- [x] Unit tests with simulated flow graphs (37 tests)

**Files:** `lib/storyarn/flows/evaluator/engine.ex`, `test/storyarn/flows/evaluator/engine_test.exs`

#### Task 4: Debug handlers + panel + first working integration ✅

- [x] `debug_handlers.ex` — events: `debug_start`, `debug_step`, `debug_step_back`, `debug_stop`, `debug_choose_response`, `debug_reset`, `debug_tab_change`
- [x] Socket assigns in `show.ex`: `debug_state`, `debug_panel_open`, `debug_active_tab`, `debug_nodes`, `debug_connections`
- [x] `debug_panel.ex` component — controls bar (step, step back, reset, stop) + status badge + console tab + response choices
- [x] "Debug" toggle button in flow editor toolbar (start/stop)
- [x] Wire up: click Debug → load variables + graph → init engine → panel opens → step through flow → see console log → choose responses → reset/stop
- [x] Variables converted from `Sheets.list_project_variables/1` with type-based defaults (number→0, boolean→false, text→"")
- [x] All 791 tests passing, zero warnings

**Files:** `lib/storyarn_web/live/flow_live/handlers/debug_handlers.ex` (new), `lib/storyarn_web/live/flow_live/components/debug_panel.ex` (new), `lib/storyarn_web/live/flow_live/show.ex` (modified)

#### Task 5: Canvas visual feedback ✅

- [x] Push events from LiveView: `debug_highlight_node` (node_id, status, execution_path), `debug_clear_highlights`
- [x] `debug_handler.js` — `handleHighlightNode` and `handleClearHighlights` methods following navigation_handler.js pattern
- [x] CSS classes in `storyarn_node_styles.js`: `.debug-current` (pulsing primary), `.debug-visited` (success border), `.debug-waiting` (pulsing warning), `.debug-error` (error border)
- [x] `@keyframes debug-pulse` and `debug-pulse-warning` animations using OKLch + daisyUI variables
- [x] Auto-scroll canvas to current node on each step via `AreaExtensions.zoomAt`
- [x] `debug_clear_highlights` removes all debug overlays on stop
- [x] Handler registered in `handlers/index.js`, wired in `event_bindings.js`, lifecycle in `flow_canvas.js`
- [x] All 791 tests passing

**Files:** `assets/js/flow_canvas/handlers/debug_handler.js` (new), `assets/js/flow_canvas/components/storyarn_node_styles.js` (modified), `assets/js/flow_canvas/event_bindings.js` (modified), `assets/js/hooks/flow_canvas.js` (modified), `assets/js/flow_canvas/handlers/index.js` (modified)

#### Task 6: Variables tab ✅

- [x] 5-column table: Variable / Type / Initial / Previous / Current (sorted alphabetically)
- [x] Source color coding: `text-warning` (orange) = instruction, `text-info` (blue) = user override, `text-base-content/50` (gray) = unchanged
- [x] Diff highlighting: bold values + ◆ diamond indicator when current differs from initial
- [x] Read-only (inline editing is Phase 2)
- [x] Tab switch in debug panel (`debug_active_tab`) — "Variables" tab button added
- [x] Empty state message when no project variables exist
- [x] Type badge per variable, sheet shortcut dimmed for readability
- [x] All 791 tests passing

**Files:** `lib/storyarn_web/live/flow_live/components/debug_panel.ex` (modified)

### Phase 2 — Interactivity + Visual Polish

**Goal:** Auto-play, runtime variable editing, full visual feedback, all panel tabs, keyboard shortcuts.

**Scope exclusions for Phase 2:**
- No analysis/player toggle (deferred to Phase 3 — requires significant engine changes for branch visibility)
- No failed branch indicators (depends on analysis/player mode)

#### Task 7: Path tab ✅

- [x] Add "Path" tab button in debug panel tabs bar
- [x] `path_tab/1` component showing ordered list of visited nodes
- [x] Each entry: step number, node type icon (`<.icon>`), node label, outcome message (from console)
- [x] Current node highlighted with `text-primary font-bold`
- [x] Empty state: "No steps yet"
- [x] Pass `debug_nodes` to `debug_panel/1` (add attr + wire from `show.ex`)
- [x] `build_path_entries/3` public (`@doc false`) for testability — consume-first-match algorithm handles repeated node visits
- [x] Unit tests: 15 tests covering all scenarios (empty, step numbers, types, labels, outcomes, repeated visits, missing nodes)
- [x] All 806 tests passing, zero warnings

**Data source:** `state.execution_path` (node IDs) + `state.console` (outcome messages) + `debug_nodes` (type/data lookup).

**Files:** `debug_panel.ex` (add tab + component), `show.ex` (pass `debug_nodes` to panel), `test/storyarn_web/live/flow_live/components/debug_panel_test.exs` (new)

#### Task 8: History tab ✅

- [x] Populate `state.history` in Engine on variable mutations (instruction nodes, dialogue output_instruction, response instructions)
- [x] Add `history` to snapshot struct for correct step_back behavior
- [x] Add "History" tab button in debug panel
- [x] `history_tab/1` component — table: Time | Node | Change | Source
- [x] Source badge: "instr" (warning) / "user" (info)
- [x] Empty state: "No variable changes yet"
- [x] Updated `history_entry` type in State to structured format (variable_ref, old_value, new_value, source)
- [x] `add_history_entries/5` helper in Engine for all 3 mutation sites
- [x] Unit tests: 7 new history tests in engine_test (instruction, multiple assignments, output_instruction, response instruction, step_back restore, reset clear, no-mutation nodes)
- [x] All 813 tests passing, zero warnings

**Engine changes:** In `evaluate_instruction/3`, `execute_output_instruction/4`, and `execute_response_instruction/3` — append history entries after `InstructionExec.execute/2` returns changes. In `push_snapshot/1` — include `history`. In `step_back/1` — restore `history`.

**Files:** `state.ex` (updated types), `engine.ex` (populate history + snapshot), `debug_panel.ex` (add tab + component), `engine_test.exs` (7 new tests)

#### Task 9: Auto-play ✅

Implemented auto-play with Play/Pause toggle, speed slider (200-3000ms), and timer-based stepping.

- `debug_handlers.ex`: `handle_debug_play/1`, `handle_debug_pause/1`, `handle_debug_set_speed/2`, `handle_debug_auto_step/1`
- `debug_panel.ex`: Play/Pause toggle button (fast-forward/pause icons), speed slider with label, buttons disabled during auto-play
- `show.ex`: New assigns (`debug_speed`, `debug_auto_playing`), event delegations, `handle_info(:debug_auto_step)`
- Auto-play stays active during `:waiting_input` (user picks response, flow continues). Stops only on `:finished`/error
- Single-response dialogues auto-select (engine change in `engine.ex`)
- 17 tests in `debug_handlers_test.exs`

#### Task 10: Keyboard shortcuts ✅

Implemented debug keyboard shortcuts in `keyboard_handler.js`:

- F10 = step, F9 = step back, F5 = toggle play/pause, F6 = reset
- Ctrl+Shift+D / Cmd+Shift+D = toggle debug mode (works even without debug panel open)
- All shortcuts `preventDefault` to block browser defaults (F5=refresh)
- Debug shortcuts guarded by `[data-debug-active]` attribute on debug panel root div
- F5 play/pause detects auto-play state by querying for the pause button in DOM

#### Task 11: Variables tab — inline editing ✅

Implemented inline variable editing in the debug panel.

- `engine.ex`: `Engine.set_variable/3` — updates value, sets `:user_override` source, adds console + history entries
- `debug_handlers.ex`: `handle_debug_edit_variable/2`, `handle_debug_cancel_edit/1`, `handle_debug_set_variable/2` with `parse_variable_value/2` (number/boolean/text)
- `debug_panel.ex`: Current column cells clickable → inline `<input>` or `<select>` by block_type (number→number input, boolean→select, text→text input). Submit on Enter/blur, cancel on Escape. `var_edit_input/1` component with pattern matching on block_type
- `show.ex`: New assign `debug_editing_var`, event delegations, attr passed to panel
- 5 engine tests + 6 handler tests

#### Task 12: Variables tab — search/filter ✅

- [x] New assigns: `debug_var_filter: ""`, `debug_var_changed_only: false`
- [x] Filter bar above variables table: text input + "Changed only" toggle button + count label
- [x] Text filter: case-insensitive `String.contains?(key, filter)`
- [x] Changed only: keep vars where `value != initial_value`
- [x] `handle_debug_var_filter/2` + `handle_debug_var_toggle_changed/1` handlers
- [x] Counter: "3 of 15 variables"

**Files:** `debug_panel.ex` (filter bar + logic), `debug_handlers.ex` (filter handlers), `show.ex` (assigns + events + pass attrs)

#### Task 13: Connection visual feedback ✅

- [x] Extend `push_debug_canvas/2` to send `debug_highlight_connections` push event with active connection info (source_node_id → target_node_id)
- [x] `handleHighlightConnections(data)` in `debug_handler.js` — find `<storyarn-connection>` elements, add `debug-edge-active` class to the active connection's `path.visible` via Shadow DOM (`el.shadowRoot.querySelector`)
- [x] CSS in `storyarn_connection.js` `static styles`: `path.visible.debug-edge-active` — stroke primary color, `stroke-dasharray: 8 4`, `animation: debug-flow 0.6s linear infinite`
- [x] `@keyframes debug-flow { to { stroke-dashoffset: -12; } }`
- [x] Extend `handleClearHighlights()` to also remove connection debug classes
- [x] Register `debug_highlight_connections` in `event_bindings.js`

**Shadow DOM note:** `<storyarn-connection>` is a LitElement. CSS must go in `static styles` (not external). DOM access via `el.shadowRoot.querySelector("path.visible")`.

**Files:** `debug_handlers.ex` (push event), `debug_handler.js` (handle + cleanup), `storyarn_connection.js` (CSS), `event_bindings.js` (register event)

#### Task 14: Start node selector in debug panel ✅

Original plan was a config modal, but reverted in favor of a lightweight inline approach:
- Variable overrides already covered by Task 11 (inline editing in Variables tab)
- A modal adds friction and goes against the "enter and start" philosophy

**Implemented instead:** inline start node dropdown in the controls bar status area.

- [x] Click Debug → session starts immediately from entry node (no modal)
- [x] `start_node_select/1` component in debug panel controls bar (after step count)
- [x] Dropdown lists all nodes (entry nodes sorted first), shows type + name excerpt
- [x] Changing start node auto-resets session from the new node
- [x] `handle_debug_change_start_node/2` — validates node exists, resets with `Engine.reset/1`
- [x] Disabled during auto-play
- [x] 3 handler tests (reset from new node, ignore non-existent, ignore invalid string)
- [x] All 849 tests passing, zero warnings

**Files:** `debug_handlers.ex` (change_start_node handler), `debug_panel.ex` (start_node_select component), `show.ex` (event delegation)

#### Task 15: Panel resize ✅

- [x] Drag handle (4px bar, `cursor: row-resize`) at top of debug panel
- [x] JS hook `DebugPanelResize` — mousedown/mousemove/mouseup tracking
- [x] Clamp height: 150px–500px
- [x] Persist to `localStorage("storyarn-debug-panel-height")`
- [x] Load saved height on mount, default 280px
- [x] Replace fixed `style="height: 280px;"` with dynamic height

**Files:** `debug_panel.ex` (drag handle + dynamic height), new `assets/js/hooks/debug_panel_resize.js` (hook), hook registration

#### Suggested execution order

Tasks 7-15, in this order. Each delivers standalone value:
1. Task 7 (Path tab) — simple, pure UI
2. Task 8 (History tab) — small engine change + UI
3. Task 9 (Auto-play) — timer + controls
4. Task 10 (Keyboard shortcuts) — JS only
5. Task 11 (Variables inline editing) — engine + handlers + UI
6. Task 12 (Variables search/filter) — pure UI state
7. Task 13 (Connection visual feedback) — backend + JS + CSS
8. Task 14 (Initial state modal) — most complex
9. Task 15 (Panel resize) — independent

### Phase 3 — Advanced (Tasks 16-26)

**Goal:** Cross-flow debugging, breakpoints, saved test sessions.

**Key findings from codebase exploration:**
- **Jump node bug:** Engine reads `data["hub_id"]` but jump nodes store `data["target_hub_id"]`. Hub nodes store `data["hub_id"]`. These are string identifiers, not DB node IDs.
- **`evaluate_node` doesn't receive nodes map** — only the current node, state, and connections. Task 16 refactors the signature to add `nodes` as 4th param.
- **Exit node `exit_mode`:** `"terminal"` | `"flow_reference"` | `"caller_return"`. `referenced_flow_id` stores the target flow DB ID. Already fully implemented in the editor, just not in the debugger.
- **Subflow node:** Stores `referenced_flow_id`. Currently finishes execution in debugger.
- **Engine is pure functional** — returns status tuples, handler does all DB/socket work. New status tuples (`{:flow_jump, state, flow_id}`, `{:flow_return, state}`) let the handler decide what to do.
- **Canvas navigation via `push_navigate` remounts LiveView** — debug state needs to survive navigation. Requires a temporary store (ETS/Agent).
- **Existing APIs:** `Flows.list_nodes/1`, `Flows.list_connections/1`, `Flows.get_flow_brief/2`, `Flows.list_hubs/1` all available.

---

#### Task 16: Jump node → target hub (same flow)

**Goal:** Jump nodes currently end execution. Make them navigate to the target hub within the same flow.

**Files:** `engine.ex`

**Implementation:**
1. Refactor ALL `evaluate_node` clauses to accept 4th param `nodes` (private function, safe change). Called from `step/3` which has `nodes`. Every clause gets `_nodes` except jump.
2. Replace jump evaluator: read `data["target_hub_id"]`, scan `nodes` map for a hub where `node.data["hub_id"]` matches, call `advance_to(state, hub_node_id)`.
3. Add `find_hub_by_hub_id(nodes, target_hub_id)` private helper — `Enum.find_value` over nodes.
4. Error cases: missing `target_hub_id` → error + finish; hub not found → error + finish.

**Tests:** 3 tests — jump to valid hub advances; missing target_hub_id finishes with error; non-existent hub_id finishes with error. Use existing test helpers (`node/3`, `conn/4`). Build a nodes map with `entry(1) → jump(2, target_hub_id: "h1") + hub(3, hub_id: "h1") → exit(4)`.

- [x] Refactor evaluate_node signature to accept `nodes` as 4th param
- [x] Implement jump → hub navigation within same flow
- [x] Handle error cases (missing target_hub_id, hub not found)
- [x] Write 3 tests

---

#### Task 17: Breakpoints — engine support

**Goal:** Add breakpoint data to state and expose toggle/check functions.

**Files:** `state.ex`, `engine.ex`

**Implementation:**
1. `state.ex`: Add `breakpoints: MapSet.t(integer())` to type and `breakpoints: MapSet.new()` to defstruct.
2. `engine.ex`: Add 3 public functions:
   - `toggle_breakpoint(state, node_id)` → adds/removes from MapSet
   - `has_breakpoint?(state, node_id)` → boolean
   - `at_breakpoint?(state)` → checks `current_node_id` membership
3. `reset/1`: Preserve breakpoints → `%{new_state | breakpoints: state.breakpoints}`
4. Add `add_breakpoint_hit(state, node_id)` public function (wraps `add_console` with `:warning` level, message "Paused at breakpoint") — needed by handler in Task 18.

**Tests:** 5 tests — toggle adds, toggle removes, has_breakpoint true/false, at_breakpoint checks current node, reset preserves breakpoints.

- [x] Add `breakpoints` field to State struct
- [x] Add toggle_breakpoint, has_breakpoint?, at_breakpoint? functions
- [x] Preserve breakpoints on reset
- [x] Add add_breakpoint_hit public function
- [x] Write 5 tests

---

#### Task 18: Breakpoints — handler + panel UI

**Goal:** Users toggle breakpoints from Path tab. Auto-play pauses at breakpoint nodes.

**Files:** `debug_handlers.ex`, `debug_panel.ex`, `show.ex`, `debug_handlers_test.exs`

**Implementation:**
1. `debug_handlers.ex`:
   - Add `handle_debug_toggle_breakpoint(%{"node_id" => id_str}, socket)` — parse int, call `Engine.toggle_breakpoint`, push `debug_update_breakpoints` event with `%{breakpoint_ids: MapSet.to_list(state.breakpoints)}`.
   - Modify `handle_debug_auto_step/1`: after `Engine.step` returns, before scheduling next step, check `Engine.at_breakpoint?(new_state)`. If true: call `Engine.add_breakpoint_hit`, set `debug_auto_playing: false`, push canvas.
2. `debug_panel.ex`:
   - Add `breakpoints` attr to `path_tab` (pass `@debug_state.breakpoints` from main component).
   - In each path entry row, prepend a small clickable circle: red filled if node_id in breakpoints, empty border otherwise. `phx-click="debug_toggle_breakpoint" phx-value-node_id={entry.node_id}`.
3. `show.ex`: Add event delegation for `"debug_toggle_breakpoint"`.

**Tests:** 3 tests — toggle adds breakpoint, auto_step pauses at breakpoint, toggle removes breakpoint.

- [x] Add toggle_breakpoint handler + push breakpoints event
- [x] Modify auto_step to pause at breakpoints
- [x] Add breakpoint indicators in Path tab UI
- [x] Wire event delegation in show.ex
- [x] Write 3 tests

---

#### Task 19: Breakpoints — canvas visual indicators

**Goal:** Show red dot on canvas nodes that have breakpoints.

**Files:** `assets/js/flow_canvas/event_bindings.js`, `assets/js/flow_canvas/handlers/debug_handler.js`, CSS

**Implementation:**
1. `event_bindings.js`: Register `debug_update_breakpoints` event → `hook.debugHandler.handleUpdateBreakpoints(data)`.
2. `debug_handler.js`:
   - Add `let breakpointEls = new Set()` to closure state.
   - Add `handleUpdateBreakpoints({ breakpoint_ids })`: clear old `.debug-breakpoint` classes, find elements for each breakpoint_id via `hook.nodeMap.get(dbId)` + `findNodeElement`, add class.
   - Clear breakpointEls in `handleClearHighlights`.
3. CSS: Add `.debug-breakpoint` pseudo-element — red dot (8px circle, `oklch(var(--er))`) at top-right corner of `storyarn-node`.

**Tests:** No automated tests (JS visual). Manual verification: toggle breakpoint, see red dot.

- [ ] Register `debug_update_breakpoints` event in event_bindings.js
- [ ] Add `handleUpdateBreakpoints` to debug_handler.js
- [ ] Add `.debug-breakpoint` CSS class with red dot pseudo-element
- [ ] Clear breakpoint visuals in handleClearHighlights

---

#### Task 20: Cross-flow — engine call stack + exit/subflow transitions

**Goal:** Add call stack to state. Exit nodes with `flow_reference` and subflow nodes return `{:flow_jump, state, target_flow_id}`. Exit with `caller_return` returns `{:flow_return, state}`.

**Files:** `state.ex`, `engine.ex`

**Implementation:**
1. `state.ex`: Add types and fields:
   - `flow_frame` type: `%{flow_id: integer(), return_node_id: integer(), nodes: map(), connections: list(), execution_path: [integer()]}`
   - Add to struct: `call_stack: []`, `current_flow_id: nil`
2. `engine.ex`:
   - Add `push_flow_context(state, flow_id, nodes, connections)` — builds frame from current state, prepends to `call_stack`.
   - Add `pop_flow_context(state)` → `{:ok, frame, updated_state}` | `{:error, :empty_stack}`.
   - Modify exit node evaluator: check `exit_mode`. `"flow_reference"` with `referenced_flow_id` → `{:flow_jump, state, target_flow_id}`. `"caller_return"` with non-empty stack → `{:flow_return, state}`. `"caller_return"` with empty stack → `{:finished, state}`. `"terminal"` → `{:finished, state}` (unchanged).
   - Modify subflow evaluator: if `referenced_flow_id` → `{:flow_jump, state, target_flow_id}`, else → error + finish.
   - Update `step/3` return type spec to include `{:flow_jump, State.t(), integer()}` and `{:flow_return, State.t()}`.
   - `reset/1`: Clear `call_stack`, preserve `breakpoints` and `current_flow_id`.

**Tests:** 7 tests — exit with flow_reference returns flow_jump; exit with caller_return + stack returns flow_return; exit with caller_return + empty stack finishes; exit terminal finishes; subflow with ref returns flow_jump; subflow without ref finishes; push/pop context roundtrip.

- [ ] Add `flow_frame` type, `call_stack`, `current_flow_id` to State
- [ ] Add push_flow_context / pop_flow_context functions
- [ ] Modify exit node evaluator for exit_mode variants
- [ ] Modify subflow evaluator for referenced_flow_id
- [ ] Update step/3 return type spec
- [ ] Update reset/1 to clear call_stack, preserve breakpoints
- [ ] Write 7 tests

---

#### Task 21: Cross-flow — handler data loading + breadcrumb

**Goal:** Handler catches `{:flow_jump, ...}` and `{:flow_return, ...}`, loads target flow data, updates socket assigns. Debug panel shows breadcrumb when in sub-flow.

**Files:** `debug_handlers.ex`, `debug_panel.ex`, `show.ex`

**Implementation:**
1. `debug_handlers.ex`:
   - Extract `handle_step_result/2` private helper that pattern-matches on all step results.
   - `{:flow_jump, state, target_flow_id}`: call `Engine.push_flow_context` with current assigns, `build_nodes_map(target_flow_id)`, `build_connections(target_flow_id)`, find entry node, assign new state with `current_node_id: entry_id`, `current_flow_id: target_flow_id`, assign new `debug_nodes`/`debug_connections`, push canvas events. **No navigation** — canvas stays on original flow (Task 22 handles navigation).
   - `{:flow_return, state}`: call `Engine.pop_flow_context`, restore `debug_nodes`/`debug_connections` from frame, set `current_flow_id: frame.flow_id`, follow output connection from `frame.return_node_id` in restored connections to find next node.
   - Refactor `handle_debug_step/1` and `handle_debug_auto_step/1` to use `handle_step_result/2`.
   - In `start_debug_session/1`: set `current_flow_id: flow.id` on state after init.
2. `debug_panel.ex`: Add breadcrumb bar between drag handle and controls bar:
   ```
   <div :if={@debug_state.call_stack != []} class="...">
     <.icon name="layers" /> In sub-flow (N level(s) deep)
   </div>
   ```
3. `show.ex`: No new assigns needed — `call_stack` and `current_flow_id` live in `debug_state`.

**Tests:** 4 tests — step into flow_reference updates assigns; step into caller_return restores assigns; nested jumps (A→B) push multiple frames; return from nested restores correct context.

- [ ] Extract handle_step_result/2 helper
- [ ] Handle {:flow_jump, ...} — load target flow, push context
- [ ] Handle {:flow_return, ...} — pop context, restore assigns
- [ ] Refactor step/auto_step handlers to use handle_step_result
- [ ] Set current_flow_id on session start
- [ ] Add breadcrumb bar in debug_panel
- [ ] Write 4 tests

---

#### Task 22: Cross-flow — canvas navigation

**Goal:** When debugger enters a sub-flow, navigate the editor to that flow so canvas highlighting works. Debug state survives the LiveView remount.

**Files:** New `lib/storyarn/flows/debug_session_store.ex`, `debug_handlers.ex`, `show.ex`, `application.ex`

**Implementation:**
1. Create `DebugSessionStore` — simple Agent storing `%{{user_id, project_id} => debug_assigns_map}`:
   - `store(key, assigns_map)` — saves all debug-related assigns
   - `take(key)` — returns and removes the stored assigns (one-shot)
2. Add to supervision tree in `application.ex`.
3. In `debug_handlers.ex`, after loading target flow data (flow_jump/flow_return):
   - Call `DebugSessionStore.store({user_id, project_id}, debug_assigns)` before navigate.
   - Call `push_navigate(socket, to: ~p"/projects/#{project_id}/flows/#{target_flow_id}")`.
4. In `show.ex` `mount/3`: After loading flow, check `DebugSessionStore.take({user_id, project_id})`. If found, restore all debug assigns and push canvas events.
5. In `debug_panel.ex`: Enhance breadcrumb with flow names (store `flow_name` in call stack frames). Add click-to-return button.

**Tests:** Agent tests for store/take. Handler tests verify DebugSessionStore.store is called (mock or check Agent state).

- [ ] Create DebugSessionStore Agent module
- [ ] Add to supervision tree
- [ ] Store debug assigns before push_navigate
- [ ] Restore debug assigns on mount
- [ ] Enhance breadcrumb with flow names and return button
- [ ] Write tests

---

#### Task 23: Cross-flow — Path tab call stack display

**Goal:** Show flow transitions in Path tab with visual separators and indentation.

**Files:** `debug_panel.ex`

**Implementation:**
1. Add a `depth` field to each path entry. The depth equals the call_stack length when that node was visited. Store this alongside execution_path in state (e.g., `execution_path_with_depth: [{node_id, depth}, ...]`).
2. In `build_path_entries`, cross-reference `console` entries for flow transition messages. When found, insert a separator entry:
   ```elixir
   %{type: :flow_separator, flow_name: "Quest Flow", depth: 1}
   ```
3. Render separators with distinct styling (info background, layers icon).
4. Indent sub-flow entries based on depth.

**Tests:** Unit test `build_path_entries` with mock data including flow transitions.

- [ ] Add depth tracking to execution path
- [ ] Insert flow separator entries in path tab
- [ ] Render separators with distinct styling
- [ ] Indent sub-flow entries by depth
- [ ] Write tests

---

#### Task 24: Saved test sessions — schema + context

**Goal:** Persist debug configurations to DB for re-use.

**Files:** New migration, new `lib/storyarn/flows/debug_session.ex`, `lib/storyarn/flows.ex` (or new submodule)

**Implementation:**
1. Migration `create_debug_sessions`:
   - `name` (string, required), `start_node_id` (integer), `variable_overrides` (map, default `%{}`), `breakpoints` (array of integers, default `[]`), `flow_id` (references flows, on_delete: delete_all).
   - Index on `flow_id`.
2. Schema with changeset: validate required `name` + `flow_id`, max length 100 for name.
3. Context functions in `Flows` (or `Flows.DebugSessionCrud`):
   - `list_debug_sessions(flow_id)` — ordered by inserted_at desc
   - `get_debug_session!(id)`
   - `create_debug_session(attrs)`
   - `delete_debug_session(id)`

**Tests:** Standard CRUD tests — create with valid attrs, create fails without name, list returns sessions for flow, delete removes session.

- [ ] Create migration
- [ ] Create DebugSession schema + changeset
- [ ] Add CRUD context functions
- [ ] Write CRUD tests

---

#### Task 25: Saved test sessions — panel UI

**Goal:** Save/load/delete debug sessions from the panel.

**Files:** `debug_handlers.ex`, `debug_panel.ex`, `show.ex`

**Implementation:**
1. `debug_handlers.ex`:
   - `handle_debug_save_session(%{"name" => name}, socket)` — extract start_node_id, variable overrides (non-initial values), breakpoints from state. Call `Flows.create_debug_session/1`. Refresh `debug_sessions` assign.
   - `handle_debug_load_session(%{"id" => id}, socket)` — load session, rebuild variables with overrides applied, re-init engine with session's start_node_id, set breakpoints.
   - `handle_debug_delete_session(%{"id" => id}, socket)` — delete and refresh list.
2. `debug_panel.ex`: Add dropdown or small section near controls:
   - Save button → inline text input for name → submit → `phx-submit="debug_save_session"`.
   - Load dropdown → list of saved sessions → `phx-click="debug_load_session" phx-value-id={s.id}`.
   - Delete icon per session → `phx-click="debug_delete_session" phx-value-id={s.id}`.
3. `show.ex`:
   - Add `debug_sessions` assign (loaded in `start_debug_session` via `Flows.list_debug_sessions(flow.id)`).
   - Event delegations for save/load/delete.

**Tests:** Handler tests — save creates session, load restores state, delete removes session.

- [ ] Add save/load/delete handlers
- [ ] Add sessions UI section in debug panel
- [ ] Wire event delegations in show.ex
- [ ] Load debug_sessions on session start
- [ ] Write handler tests

---

#### Task 26: Conditional breakpoints

**Goal:** Breakpoints can optionally have a condition. Only pause when condition evaluates to true.

**Files:** `state.ex`, `engine.ex`, `debug_handlers.ex`, `debug_panel.ex`

**Implementation:**
1. Change `breakpoints` from `MapSet.t(integer())` to `%{integer() => nil | String.t()}`. Key = node_id. Value = `nil` (unconditional) or condition JSON string.
2. Update `toggle_breakpoint/2` to add with `nil` condition by default.
3. Add `set_breakpoint_condition(state, node_id, condition)` — updates condition for existing breakpoint.
4. Update `at_breakpoint?/1`: if value is `nil` → true. If string → evaluate with `ConditionEval.evaluate_string/2`, return result.
5. Update handler: `handle_debug_set_breakpoint_condition(%{"node_id" => id, "condition" => json}, socket)`.
6. UI: In Path tab, when breakpoint is set, show expandable condition input (simple textarea for condition JSON, or integrate the condition builder component).
7. Update Task 18/19 code to work with map instead of MapSet.

**Tests:** Conditional breakpoint only pauses when condition is met. Unconditional still works. Empty condition treated as unconditional.

- [ ] Change breakpoints from MapSet to map (node_id => nil | condition)
- [ ] Add set_breakpoint_condition function
- [ ] Update at_breakpoint? to evaluate conditions
- [ ] Add handler for setting breakpoint conditions
- [ ] Add condition input UI in Path tab
- [ ] Update breakpoint event push for map format
- [ ] Write tests

---

#### Suggested execution order

Tasks 16-26, in this order. Each delivers standalone value:
1. Task 16 (Jump → hub) — immediate fix, jump nodes work
2. Task 17 (Breakpoints engine) — data foundation
3. Task 18 (Breakpoints UI) — usable breakpoints
4. Task 19 (Breakpoints canvas) — visual feedback
5. Task 20 (Cross-flow engine) — call stack + return tuples
6. Task 21 (Cross-flow handler) — flow transitions work in panel
7. Task 22 (Cross-flow canvas) — full visual debugging across flows
8. Task 23 (Path tab stack) — enriched path display
9. Task 24 (Sessions schema) — DB foundation
10. Task 25 (Sessions UI) — save/load sessions
11. Task 26 (Conditional breakpoints) — advanced breakpoints

---

## File Inventory

### New files

```
lib/storyarn/flows/evaluator/
  state.ex
  engine.ex
  condition_eval.ex
  instruction_exec.ex

lib/storyarn_web/live/flow_live/
  handlers/debug_handlers.ex
  components/debug_panel.ex

test/storyarn/flows/evaluator/
  engine_test.exs
  condition_eval_test.exs
  instruction_exec_test.exs
```

### Modified files

```
lib/storyarn_web/live/flow_live/show.ex                     # Add debug assigns, mount debug_state: nil
lib/storyarn_web/live/flow_live/show.html.heex              # Add debug panel component
assets/js/hooks/flow_canvas.js                               # Handle debug push events
assets/js/flow_canvas/components/storyarn_node.js            # Debug CSS classes
assets/js/flow_canvas/components/storyarn_connection.js      # Debug CSS classes + animations
assets/css/app.css                                           # Debug animations + variable colors
```

---

## Edge Cases

| Scenario                                     | Behavior                                                                                   |
|----------------------------------------------|--------------------------------------------------------------------------------------------|
| Node has no outgoing connections             | Log error, end execution                                                                   |
| Condition evaluates but no matching pin      | Log error with rule detail, end execution                                                  |
| Variable referenced in condition is missing  | Treat as nil, log warning with variable name                                               |
| Instruction references non-existent variable | Log error, skip assignment, continue with remaining                                        |
| Dialogue has 0 valid responses after filter  | Analysis: show all as failed; Player: log warning, follow "output" pin if exists, else end |
| Circular path (infinite loop)                | Auto-play stops after max_steps (default: 500), log error                                  |
| Node data is malformed / unparseable         | Log error, skip node, try to follow output                                                 |
| Start from node with no input connections    | Valid — just start there                                                                   |
| User edits variable during auto-play         | Pause auto-play, apply change, user can resume                                             |
| Multiple connections from same pin           | Follow first one found, log warning (should not happen)                                    |
| Stale variable references                    | Use current sheet_shortcut.variable_name, log warning                                      |
| Step back at first node                      | No-op, log info "Already at the start"                                                     |
| Step back after choosing response            | Restore snapshot, return to dialogue with choices re-presented                             |
| Toggle analysis↔player mid-session           | Immediate: re-evaluate current node's visible branches                                     |
| Variable override during condition node      | If current node is condition, re-evaluate and update console                               |
