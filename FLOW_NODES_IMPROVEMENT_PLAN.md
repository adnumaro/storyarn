# Flow Nodes Improvement Plan

> **Status**: In Progress
> **Date**: February 6, 2026
> **Scope**: Fix and improve all flow nodes that are broken, incomplete, or placeholder

---

## Current State

| Node            | Status                                 | Action             |
|-----------------|----------------------------------------|--------------------|
| **Dialogue**    | Complete (Phases 1-4)                  | No changes needed  |
| **Condition**   | Complete (visual builder, switch mode) | No changes needed  |
| **Entry**       | Functional, rules correct              | Minor improvement  |
| **Exit**        | Functional but minimal                 | Minor improvement  |
| **Hub**         | Functional                             | Done (Phase 1)     |
| **Jump**        | Functional                             | Done (Phase 1)     |
| **Instruction** | Placeholder                            | Full redesign      |

---

## Phase 1: Bug Fixes (Hub + Jump) — COMPLETED

### 1.1 Hub: Apply color on canvas — DONE

Hub nodes now resolve their `color` field to a hex value via `HubColors` module. The color is passed to the canvas through `resolve_node_colors/2` and displayed in the node header.

**Changes made:**
- Created `lib/storyarn/flows/hub_colors.ex` — single source of truth for hub color definitions
- `Flows.resolve_node_colors/2` enriches hub data with `color_hex` for the JS canvas
- `storyarn_node.js` uses `nodeData.color_hex` for hub node header color
- `simple_panels.ex` uses `HubColors.names()` for the color dropdown

---

### 1.2 Hub: Require hub_id — DONE

Hub nodes now auto-generate a unique `hub_id` on creation (e.g., `hub_1`, `hub_2`) and reject empty hub_id on update.

**Changes made:**
- `node_crud.ex` — auto-generates hub_id on creation, validates non-empty + unique on update
- `simple_panels.ex` — shows hub_id as required field with `*` indicator
- `node_helpers.ex` — handles `:hub_id_required` and `:hub_id_not_unique` errors with flash messages

---

### 1.3 Jump: Fix preview/simulator dead-end — DONE

The preview component now follows Jump nodes to their target Hub and continues traversal from there, with cycle detection and depth limiting.

**Changes made:**
- `preview_component.ex` — `skip_to_next_dialogue` resolves Jump → Hub using `Flows.get_hub_by_hub_id/2`
- Added cycle detection via `MapSet` of visited node IDs
- Added `@max_traversal_depth 50` to prevent infinite recursion

---

### 1.4 Jump: Orphan detection on Hub delete — DONE

Deleting a Hub now clears `target_hub_id` on all Jump nodes that targeted it, and shows a warning to the user.

**Changes made:**
- `node_crud.ex` — `clear_orphaned_jumps/2` uses `jsonb_set` to clear target_hub_id on affected jumps
- `node_helpers.ex` — shows ngettext warning with count of affected jump nodes
- `storyarn_node.js` — orphan jumps (no target_hub_id) show a warning triangle indicator
- `node_helpers.ex` — deletion now uses `reload_flow_data/1` so `flow_hubs` stays current

---

### 1.5 Jump: Visual indicator to target Hub — DONE

Jump nodes inherit the color of their target Hub and display the hub's label in the node preview. Orphan jumps show a warning indicator.

**Changes made:**
- `storyarn_node.js` — Jump node color cascades: target hub color > config default
- `node_formatters.js` — Jump preview shows `-> {hub_label}` when target has a label
- `flow_canvas.js` — `rebuildHubsMap()` maintains a `hubsMap` object passed to all nodes
- `setup.js` — passes `hubsMap` to `storyarn-node` component

---

## Phase 1.5: Code Quality Audit Fixes — COMPLETED

A comprehensive audit identified and fixed the following issues:

### Security Fixes

| Fix | Severity | Description |
|-----|----------|-------------|
| HTML sanitization in preview | **High** | `raw/1` now uses Floki-based sanitizer with tag allowlist before rendering TipTap HTML |
| Cycle detection in preview | **Medium** | `skip_to_next_dialogue` uses visited set + max depth to prevent infinite recursion |

### Bug Fixes

| Fix | Severity | Description |
|-----|----------|-------------|
| `flow_hubs` stale after hub delete | **Medium** | `perform_node_deletion` now uses `reload_flow_data/1` in both branches |
| `rebuildDialogueNode` try/finally | **Medium** | `isLoadingFromServer` flag now always resets via try/finally; connection metadata preserved during rebuild |
| `connectionDataMap` consistency | **Medium** | `handleConnectionUpdated` now stores `{id, label, condition}` matching `addConnectionToEditor` |
| `extract_form_data("condition")` | **Medium** | Aligned with `default_data` — extracts `condition`/`switch_mode` instead of stale `expression`/`cases` |
| Hub duplicate generates new hub_id | **Medium** | `duplicate_node` clears `hub_id` for hubs so `create_node` auto-generates a unique one |
| `speaker_page_id` type handling | **Low** | `resolve_speaker` now accepts both string and integer `speaker_page_id` |
| `formatRuleShort` type coercion | **Low** | `String(value)` before `.length` to handle numeric values |
| `hub_color_options` tuple order | **Low** | Fixed to `{translated_label, raw_name}` matching Phoenix `options_for_select` convention |
| Fragile hub_options empty check | **Low** | Changed from exact list comparison to `length(@hub_options) <= 1` |
| `_updateTs` fallback | **Low** | Changed from `Date.now()` to `0` to avoid unnecessary Lit re-renders |

### Code Hygiene

| Fix | Description |
|-----|-------------|
| `to_hex!` renamed | Now `to_hex/2` with explicit default + `default_hex/0` — follows Elixir naming convention |
| Dead code removed | `get_entry_node/1` removed (never called) |
| Visibility corrected | `has_entry_node?/1`, `clear_orphaned_jumps/2` changed to `defp` |
| Inline aliases removed | `alias Storyarn.Pages.ReferenceTracker` moved to module level in `node_crud.ex` |

---

## Phase 1.6: Hub + Jump Bug Fixes — COMPLETED

Follow-up fixes discovered after Phase 1.5 audit.

### Backend fixes

| Fix | Description |
|-----|-------------|
| Atomic hub deletion | `delete_node/1` wrapped in `Repo.transaction` — orphan cleanup + delete are all-or-nothing |
| Cascade hub_id rename | Renaming a hub's `hub_id` cascades to all referencing jump nodes via `cascade_hub_id_rename/3` |
| `updated_at` on bulk updates | `clear_orphaned_jumps` and `cascade_hub_id_rename` now set `updated_at` |
| 3-tuple return from `update_node_data` | Returns `{:ok, node, %{renamed_jumps: count}}` so callers can react to cascades |
| Collaboration broadcast | Hub deletion with orphaned jumps broadcasts `:flow_refresh` (full reload) instead of `:node_deleted` (single remove) |
| Referencing jumps in sidebar | Hub panel shows list of referencing jump nodes with per-jump navigation |
| `navigate_to_node` event | New generic navigation event for zooming + highlighting any node by ID |

### Frontend fixes

| Fix | Description |
|-----|-------------|
| hubsMap not propagating on page reload | Rete LitPlugin's `area.update` only propagates `.data`/`.emit`, not custom props — fixed by setting `.hubsMap` directly on DOM elements via `querySelectorAll` |
| hubsMap rebuild for jump changes | `handleNodeAdded`, `handleNodeUpdated`, `handleNodeRemoved` now rebuild hubsMap for both hub AND jump node types |
| Async `rebuildHubsMap` | Made async with awaited `area.update` calls |
| Double re-render removed | Consolidated initial `rebuildHubsMap` + post-finalize loop into single call after `finalizeSetup` |
| Jump navigation from hub panel | Individual jump buttons use `navigate_to_node` (zoom + highlight jump) instead of `navigate_to_hub` (which navigated back to the hub) |

---

## Phase 2: Minor Improvements (Entry + Exit)

### 2.1 Exit: Auto-create with flow

**Problem:** New flows only get an Entry node. Users must manually add Exit.

**Fix:**

In `flow_crud.ex`, when creating a flow, also create an Exit node at position `{500, 300}` with label `""`.

**Files to modify:**
- `lib/storyarn/flows/flow_crud.ex` - Add Exit node in `create_flow`

---

### 2.2 Exit: Better data structure

**Problem:** Exit only has a `label` field. For export to game engines, more data is useful.

**New data structure:**
```elixir
def default_data("exit") do
  %{
    "label" => "",
    "technical_id" => "",
    "is_success" => true  # true = success ending, false = failure/game over
  }
end
```

**Panel changes:**
- Label text input (existing)
- Technical ID (for export, like dialogue nodes)
- Success/Failure toggle (visual: green check vs red X on canvas)

**Files to modify:**
- `lib/storyarn_web/live/flow_live/node_type_registry.ex` - Update default_data and extract_form_data
- `lib/storyarn_web/live/flow_live/components/panels/simple_panels.ex` - Add fields
- `assets/js/hooks/flow_canvas/components/storyarn_node.js` - Show success/failure indicator
- `assets/js/hooks/flow_canvas/components/node_formatters.js` - Update preview

---

## Phase 3: Instruction Node Redesign

The Instruction node needs the same level of treatment that the Condition node received. It should be the "write" counterpart to Condition's "read".

### 3.1 New data structure

**Current (placeholder):**
```elixir
%{"action" => "", "parameters" => ""}
```

**Proposed:**
```elixir
def default_data("instruction") do
  %{
    "assignments" => [],
    "technical_id" => "",
    "description" => ""
  }
end
```

### Assignment structure:
```elixir
%{
  "id" => "assign_123",
  "page" => "mc.jaime",           # Page shortcut
  "variable" => "health",          # Variable name
  "operator" => "set",             # set, add, subtract, toggle
  "value" => "100"                 # Value to assign
}
```

### 3.2 Operators by variable type

| Block type  | Available operators                            |
|-------------|------------------------------------------------|
| `number`    | `set`, `add`, `subtract`, `multiply`, `divide` |
| `boolean`   | `set_true`, `set_false`, `toggle`              |
| `text`      | `set`, `append`, `clear`                       |
| `select`    | `set` (dropdown with block options)            |

This mirrors the Condition node's operator system. The operators are the "write" side:
- Condition: `health > 50` (read + compare)
- Instruction: `health += 10` (write + modify)

### 3.3 Visual builder (same pattern as Condition)

The Instruction panel should use the same component patterns as the Condition panel:
1. Page dropdown (from `Pages.list_project_variables/1`)
2. Variable dropdown (filtered by selected page)
3. Operator dropdown (filtered by variable type)
4. Value input (type depends on variable: number input, text input, boolean toggle, select dropdown)
5. Add/remove assignments
6. Description field (optional, for documentation)

### 3.4 Canvas rendering

Show assignment previews in the node body:

```
┌─────────────────────────────────┐
│  ⚡ Instruction                  │
├─────────────────────────────────┤
│  mc.jaime.health += 10          │
│  mc.jaime.met_player = true     │
│  inventory.gold -= 50           │
├─────────────────────────────────┤
│────○                       ○────│
└─────────────────────────────────┘
```

If no assignments, show placeholder text: "No assignments"

### 3.5 Implementation plan

**Backend:**

1. Create `lib/storyarn/flows/instruction.ex` module (mirroring `condition.ex`):
   - `add_assignment/2` - Add assignment to instruction data
   - `remove_assignment/2` - Remove assignment by id
   - `update_assignment/3` - Update assignment fields
   - `operators_for_type/1` - Return valid operators for a block type
   - `format_assignment_short/1` - Short text representation

2. Create handler module `lib/storyarn_web/live/flow_live/handlers/instruction_event_handlers.ex`:
   - `handle_event("add_instruction_assignment", ...)`
   - `handle_event("remove_instruction_assignment", ...)`
   - `handle_event("update_instruction_assignment", ...)`

3. Update `node_type_registry.ex`:
   - New `default_data("instruction")`
   - New `extract_form_data("instruction", data)`

**Frontend (panel):**

4. Create `lib/storyarn_web/live/flow_live/components/panels/instruction_panel.ex`:
   - Same component structure as `condition_panel.ex`
   - Assignment list with add/remove
   - Visual builder for each assignment
   - Description field

5. Update `lib/storyarn_web/live/flow_live/components/properties_panels.ex`:
   - Route "instruction" type to new panel instead of simple_panels

**Frontend (canvas):**

6. Update `assets/js/hooks/flow_canvas/components/node_formatters.js`:
   - New `formatInstructionPreview(nodeData)` function
   - Short text for each assignment: `page.variable op value`

7. Update `assets/js/hooks/flow_canvas/components/storyarn_node.js`:
   - Render assignments list in node body (similar to condition rules)

**Files to create:**
- `lib/storyarn/flows/instruction.ex`
- `lib/storyarn_web/live/flow_live/handlers/instruction_event_handlers.ex`
- `lib/storyarn_web/live/flow_live/components/panels/instruction_panel.ex`

**Files to modify:**
- `lib/storyarn_web/live/flow_live/node_type_registry.ex`
- `lib/storyarn_web/live/flow_live/components/properties_panels.ex`
- `lib/storyarn_web/live/flow_live/show.ex` (delegate new events)
- `assets/js/hooks/flow_canvas/components/node_formatters.js`
- `assets/js/hooks/flow_canvas/components/storyarn_node.js`

---

## Phase 4: Connection system hardening

### 4.1 Server-side connection validation

**Problem:** No server-side rules prevent invalid connections (e.g., connecting to Entry's input or from Exit's output). The canvas enforces this visually, but a direct API call could bypass it.

**Fix:**

Add validation in `connection_crud.ex`:
```elixir
defp validate_connection_rules(source_node, target_node, source_pin, target_pin) do
  cond do
    source_node.type == "exit" -> {:error, :exit_has_no_outputs}
    source_node.type == "jump" -> {:error, :jump_has_no_outputs}
    target_node.type == "entry" -> {:error, :entry_has_no_inputs}
    source_node.id == target_node.id -> {:error, :self_connection}
    true -> :ok
  end
end
```

**Files to modify:**
- `lib/storyarn/flows/connection_crud.ex`

---

### 4.2 Fix delete_connection_by_nodes

**Problem:** `delete_connection_by_nodes/3` deletes ALL connections between two nodes. With dialogue responses, there can be multiple valid connections between the same pair (through different response pins).

**Fix:**

Add a more specific function: `delete_connection/4` that includes `source_pin` and `target_pin`.

Keep the existing function for cases where you want to delete all connections between two nodes.

**Files to modify:**
- `lib/storyarn/flows/connection_crud.ex`
- `lib/storyarn/flows.ex` (facade)

---

## Phase 5: Remove connection condition schema (cleanup)

### 5.1 Remove legacy condition field from connections

**Problem:** `flow_connections.condition` exists in the database but is never used anywhere. The research confirmed conditions belong on nodes, not edges.

**Fix:**

Create a migration to remove the `condition` column from `flow_connections`.

**Files to create:**
- New migration: `remove_condition_from_flow_connections.exs`

---

## Implementation Order

| Order   | Phase   | Task                        | Effort  | Status           |
|---------|---------|-----------------------------|---------|------------------|
| 1       | 1.1     | Hub color on canvas         | Small   | **DONE**         |
| 2       | 1.2     | Hub require hub_id          | Small   | **DONE**         |
| 3       | 1.3     | Jump preview resolution     | Small   | **DONE**         |
| 4       | 1.4     | Jump orphan detection       | Small   | **DONE**         |
| 5       | 1.5     | Jump visual indicator       | Small   | **DONE**         |
| 6       | 1.5+    | Code quality audit fixes    | Medium  | **DONE**         |
| 6.5     | 1.6     | Hub + Jump bug fixes        | Medium  | **DONE**         |
| 7       | 2.1     | Exit auto-create            | Trivial | Pending          |
| 8       | 2.2     | Exit better data            | Small   | Pending          |
| 9       | 3.*     | Instruction redesign        | Medium  | Pending          |
| 10      | 4.1     | Connection validation       | Small   | Pending          |
| 11      | 4.2     | Fix connection delete       | Small   | Pending          |
| 12      | 5.1     | Remove connection condition | Trivial | Pending          |

---

## Key Files Reference

### Backend
| File                                                                     | What changes                       |
|--------------------------------------------------------------------------|------------------------------------|
| `lib/storyarn/flows/node_crud.ex`                                        | Hub validation, orphan detection   |
| `lib/storyarn/flows/hub_colors.ex`                                       | Hub color definitions              |
| `lib/storyarn/flows/flow_crud.ex`                                        | Auto-create Exit node              |
| `lib/storyarn/flows/connection_crud.ex`                                  | Validation, specific delete        |
| `lib/storyarn/flows/instruction.ex`                                      | **NEW** - Instruction domain logic |
| `lib/storyarn_web/live/flow_live/node_type_registry.ex`                  | Default data, extract_form_data    |
| `lib/storyarn_web/live/flow_live/components/panels/simple_panels.ex`     | Exit, Hub panel updates            |
| `lib/storyarn_web/live/flow_live/components/panels/instruction_panel.ex` | **NEW** - Visual builder           |
| `lib/storyarn_web/live/flow_live/components/properties_panels.ex`        | Route instruction to new panel     |
| `lib/storyarn_web/live/flow_live/handlers/instruction_event_handlers.ex` | **NEW** - Assignment events        |
| `lib/storyarn_web/live/flow_live/preview_component.ex`                   | Jump resolution, HTML sanitization |
| `lib/storyarn_web/live/flow_live/helpers/node_helpers.ex`                | Hub duplicate fix, deletion fix    |
| `lib/storyarn_web/live/flow_live/show.ex`                                | Delegate instruction events        |

### Frontend
| File                                                              | What changes                                   |
|-------------------------------------------------------------------|-------------------------------------------------|
| `assets/js/hooks/flow_canvas.js`                                  | hubsMap management                             |
| `assets/js/hooks/flow_canvas/components/storyarn_node.js`         | Hub color, Jump indicator, Instruction preview |
| `assets/js/hooks/flow_canvas/components/node_formatters.js`       | Instruction preview, type coercion fix         |
| `assets/js/hooks/flow_canvas/handlers/editor_handlers.js`         | try/finally fix, connection metadata           |
| `assets/js/hooks/flow_canvas/setup.js`                            | hubsMap pass-through, _updateTs fix            |

---

## What this plan does NOT cover

These are out of scope for this plan and belong in separate documents:

- **FlowJump / FlowReturn / Event nodes** - New node types (see PHASE_7_5_FLOWS_ENHANCEMENT.md)
- **Note/Comment node** - Not yet specified
- **`input_condition` / `output_instruction` visual builder** - Dialogue logic fields (separate enhancement)
- **Variable reference syntax (`#shortcut.variable`)** - Depends on Pages enhancement
- **Flow versioning** - Separate feature
- **Screenplay mode** - Separate feature
