# Phase 4: Flow Editor V2 — Full Vue Migration

## Goal

Create a complete Vue-based flow editor at `/v2/.../flows/:id` using Rete.js with the official Vue plugin. Node-based visual scripting with all node types, connections, conditions, instructions, collaboration, and debug mode.

## Prerequisites

- [ ] Phase 1 complete (base components, ConditionBuilder, InstructionBuilder)
- [ ] Phase 2 complete (validates canvas + toolbar patterns)
- [ ] Phase 3 complete (validates complex form interactions)

## 4.1 Rete.js Vue Migration

### Current State

- Rete.js 2 with `@retejs/lit-plugin` (Lit/Web Components)
- Custom node rendering via Shadow DOM
- ~490 lines in `flow_canvas.js` hook
- Icons rendered via `createIconHTML`/`createIconSvg` from `node_config.js`

### Target

- Rete.js 2 with `@retejs/vue-plugin` (Vue 3)
- Node rendering as Vue components (reactive, no Shadow DOM)
- All node types as Vue components with proper slots

### Install

```bash
npm install @retejs/vue-plugin
# Remove: @retejs/lit-plugin (after migration)
```

## 4.2 Route & LiveView Shell

### Route

```elixir
live "/v2/workspaces/:workspace_slug/projects/:project_slug/flows/:id",
     FlowLive.ShowV2, :show
```

### LiveView (`flow_live/show_v2.ex`)

```elixir
def render(assigns) do
  ~H"""
  <.vue
    v-component="FlowEditor"
    v-socket={@socket}
    id="flow-editor"
    flow={@flow}
    nodes={@nodes}
    connections={@connections}
    project={@project}
    workspace={@workspace}
    can_edit={@can_edit}
    project_variables={@project_variables}
    project_sheets={@flat_sheets}
    project_flows={@flat_flows}
  />
  """
end
```

## 4.3 Layout

```
┌──────────────────────────────────────────────┐
│ FlowHeader (breadcrumb, title, shortcuts)     │
├────────────┬─────────────────────────────────┤
│            │                                 │
│ TreePanel  │   FlowCanvas (Rete.js)          │
│ (flows     │   ├─ Nodes (Vue components)     │
│  tree)     │   ├─ Connections (SVG paths)    │
│            │   └─ Minimap                    │
│            │                                 │
│            ├─────────────────────────────────┤
│            │ DebugPanel (collapsible bottom)  │
└────────────┴─────────────────────────────────┘
│             ┌───────────────┐                │
│             │ CanvasToolbar │                │
│             │ (add node)    │                │
│             └───────────────┘                │
```

## 4.4 Node Components

### Base Node

| Component        | Purpose                                         |
| ---------------- | ----------------------------------------------- |
| `FlowNode.vue`   | Base node wrapper — header, ports, body, resize |
| `NodePort.vue`   | Input/output connection port                    |
| `NodeHeader.vue` | Icon, title, color strip                        |

### Node Types (one Vue component each)

| Component             | Node Type     | Contents                                       |
| --------------------- | ------------- | ---------------------------------------------- |
| `EntryNode.vue`       | `entry`       | Start marker, no inputs                        |
| `ExitNode.vue`        | `exit`        | End marker, no outputs                         |
| `DialogueNode.vue`    | `dialogue`    | Character select, text content, audio, choices |
| `ConditionNode.vue`   | `condition`   | ConditionBuilder, true/false output ports      |
| `InstructionNode.vue` | `instruction` | InstructionBuilder, assignments list           |
| `HubNode.vue`         | `hub`         | Multiple labeled outputs, color picker         |
| `JumpNode.vue`        | `jump`        | Flow/node target selector                      |
| `SlugLineNode.vue`    | `slug_line`   | Section divider with title                     |
| `SubflowNode.vue`     | `subflow`     | Flow selector, parameter mapping               |
| `AnnotationNode.vue`  | `annotation`  | Free-text note (not connected)                 |

### Node Internals

| Component             | Used In      | Purpose                                    |
| --------------------- | ------------ | ------------------------------------------ |
| `DialogueChoices.vue` | DialogueNode | Choice list with add/remove/reorder        |
| `DialogueContent.vue` | DialogueNode | TipTap editor for dialogue text            |
| `CharacterSelect.vue` | DialogueNode | Sheet picker with avatar preview           |
| `AudioSelect.vue`     | DialogueNode | Audio asset picker with preview            |
| `NodeContextMenu.vue` | All nodes    | Right-click: duplicate, delete, lock, copy |

## 4.5 Canvas Components

| Component            | Purpose                                       |
| -------------------- | --------------------------------------------- |
| `FlowCanvas.vue`     | Rete.js area setup, zoom/pan, background grid |
| `CanvasToolbar.vue`  | Add node buttons (per type)                   |
| `CanvasMinimap.vue`  | Minimap overview                              |
| `ConnectionPath.vue` | Custom SVG connection with animation          |
| `SelectionBox.vue`   | Multi-select rectangle                        |

## 4.6 Screenplay Integration

| Component            | Purpose                                   |
| -------------------- | ----------------------------------------- |
| `ScreenplayView.vue` | Side-by-side screenplay text view         |
| `ScreenplaySync.vue` | Scroll sync between canvas and screenplay |

## 4.7 Debug Mode

| Component                | Purpose                                     |
| ------------------------ | ------------------------------------------- |
| `DebugPanel.vue`         | Collapsible bottom panel for flow debugging |
| `DebugControls.vue`      | Play, step, reset, speed controls           |
| `DebugVariables.vue`     | Variable watch with edit                    |
| `DebugNodeHighlight.vue` | Current node highlight on canvas            |
| `DebugChoicePrompt.vue`  | Choice selection during debug playback      |

## 4.8 Collaboration

Same composables as Phase 2:

- `usePresence(scope)` — online users
- `useLocking(scope)` — node locking
- `useCursorSharing(flowId)` — cursor positions on canvas

Additionally:

- Node lock indicators (badge on locked nodes)
- Remote node movement (animate other users' drag operations)
- Collaboration toast notifications

## 4.9 Event Handlers

All events from current `flow_live/show.ex`:

### Node Events

- `create_node`, `update_node`, `delete_node`, `move_node`
- `resize_node`, `duplicate_node`, `copy_nodes`, `paste_nodes`
- `update_node_content`, `update_node_config`

### Connection Events

- `create_connection`, `delete_connection`
- `update_connection_path`

### Choice Events (Dialogue nodes)

- `add_choice`, `update_choice`, `delete_choice`, `reorder_choices`

### Hub Events

- `add_hub_output`, `update_hub_output`, `delete_hub_output`
- `update_hub_color`

### Canvas Events

- `update_viewport`, `auto_arrange`
- `select_nodes`, `deselect_all`

### Debug Events

- `start_debug`, `stop_debug`, `step_debug`
- `select_debug_choice`, `update_debug_variable`

## Deliverables

- [ ] `/v2/.../flows/:id` route working
- [ ] Rete.js canvas with Vue plugin (no Lit/Shadow DOM)
- [ ] All 10 node types as Vue components
- [ ] Node editing inline (dialogue text, conditions, instructions)
- [ ] Connection creation and deletion
- [ ] Canvas toolbar for adding nodes
- [ ] Minimap
- [ ] Debug mode with variable watch and step execution
- [ ] Collaboration (presence, locking, cursors)
- [ ] Screenplay side-by-side view
- [ ] Auto-arrange layout
- [ ] Undo/redo for all canvas operations
- [ ] Feature parity with current flow editor

## Estimated Scope

~35 Vue components + Rete.js Vue plugin integration + debug system

---

## Post-Migration: Cleanup Phase

After all 4 phases are complete and v2 pages are validated:

1. **Update routes** — v2 routes become the primary routes, old routes redirect
2. **Remove old pages** — delete HEEx LiveViews and their handlers/helpers
3. **Remove old hooks** — delete JS hooks replaced by Vue components
4. **Remove esbuild** — Vite handles everything (move landing.js to Vite entry)
5. **Remove DaisyUI** — NuxtUI is the only component library
6. **Remove SearchableSelect, EntitySelect, PopoverSelect** — Vue Select replaces all
7. **Update tests** — migrate LiveView tests to test the new LiveViews
8. **Performance audit** — verify zero forced reflows across all editors
