# Refactor: Per-Node-Type Architecture for Flow Editor

## Goal
Reorganize the flow editor from concern-based (handlers/, helpers/, components/panels/) to per-node-type architecture where each node type is self-contained — both Elixir and JavaScript.

## Principle
Code duplication > bad abstractions. Each node type directory should tell you everything that node does.

---

## Target Structure

### Elixir
```
lib/storyarn_web/live/flow_live/
├── show.ex                              # Main LiveView (thin dispatcher)
├── node_type_registry.ex                # Aggregates per-type modules (lookup only)
├── nodes/
│   ├── dialogue/
│   │   ├── node.ex                      # Metadata + handlers (responses, tech_id, double-click→screenplay)
│   │   └── config_sidebar.ex            # Sidebar panel HTML
│   ├── condition/
│   │   ├── node.ex                      # Metadata + handlers (condition builder, switch mode, response condition builder)
│   │   └── config_sidebar.ex
│   ├── instruction/
│   │   ├── node.ex                      # Metadata + handlers (instruction builder)
│   │   └── config_sidebar.ex
│   ├── hub/
│   │   ├── node.ex                      # Metadata + handlers (on_select loads referencing_jumps)
│   │   └── config_sidebar.ex
│   ├── jump/
│   │   ├── node.ex                      # Metadata only
│   │   └── config_sidebar.ex
│   ├── entry/
│   │   ├── node.ex                      # Metadata only
│   │   └── config_sidebar.ex
│   └── exit/
│       ├── node.ex                      # Metadata + handlers (generate_technical_id)
│       └── config_sidebar.ex
├── components/
│   ├── properties_panels.ex             # SIMPLIFIED: shared frame, delegates to per-type sidebar
│   └── screenplay_editor.ex             # Stays (dialogue full-screen editor)
├── handlers/
│   ├── generic_node_handlers.ex         # RENAMED: only generic ops (select, move, delete, duplicate, etc.)
│   ├── editor_info_handlers.ex          # Stays
│   └── collaboration_event_handlers.ex  # Stays
└── helpers/
    ├── node_helpers.ex                  # TRIMMED: persist_node_update + shared utils only
    ├── form_helpers.ex                  # Stays
    ├── connection_helpers.ex            # Stays
    ├── socket_helpers.ex                # Stays
    └── collaboration_helpers.ex         # Stays
```

### JavaScript
```
assets/js/hooks/flow_canvas/
├── nodes/
│   ├── index.js                         # Registry: type → module lookup
│   ├── dialogue.js                      # Config, pins, rendering, formatting, rebuild check
│   ├── condition.js
│   ├── instruction.js
│   ├── hub.js
│   ├── jump.js
│   ├── entry.js
│   └── exit.js
├── flow_node.js                         # Simplified: delegates pin creation to per-type
├── components/
│   ├── storyarn_node.js                 # Simplified: delegates body rendering to per-type
│   └── (others stay)
├── handlers/
│   ├── editor_handlers.js              # Simplified: rebuildNode generic, needsRebuild per-type
│   └── (others stay)
└── (flow_canvas.js, setup.js, event_bindings.js stay)
```

---

## What Each Module Contains

### `node.ex` (per type)
- `type/0`, `icon_name/0`, `label/0` — metadata
- `default_data/0` — default data map for new nodes
- `extract_form_data/1` — converts node data to form data
- `on_select/2` — extra work on selection (hub: load referencing_jumps)
- `on_double_click/2` — editing mode to open (dialogue: `:screenplay`, others: `:sidebar`)
- `duplicate_data_cleanup/1` — transform data when duplicating (clear hub_id, technical_id, etc.)
- Type-specific event handlers (responses for dialogue, condition builder for condition, etc.)

### `config_sidebar.ex` (per type)
- `config_sidebar/1` — Phoenix function component for the sidebar content
- Wraps itself in `<.form>` if needed (dialogue, exit, hub, jump use form; condition/instruction don't)
- Computes its own options (speaker_options in dialogue, hub_options in jump)

### `node_type_registry.ex` (refactored)
- Module lookup map: `node_module("dialogue")` → `Nodes.Dialogue.Node`
- Sidebar lookup: `sidebar_module("dialogue")` → `Nodes.Dialogue.ConfigSidebar`
- Delegates: `icon_name/1`, `label/1`, `default_data/1`, `extract_form_data/2` → per-type module
- `types/0`, `user_addable_types/0`

### JS `nodes/{type}.js`
Each exports an object with:
```javascript
{
  config: { label, color, icon, inputs, outputs, dynamicOutputs },
  createOutputs(data),          // for dynamic outputs
  getPreviewText(data),         // canvas preview text
  getIndicators(data),          // header badges
  renderHeader(node, data, config, pagesMap),  // custom header (speaker avatar)
  getBodyContent(data),         // extra body content (stage directions, nav links)
  formatOutputLabel(key, data), // custom output socket labels
  getOutputBadges(key, data),   // output socket badges ([?] for response conditions)
  needsRebuild(oldData, newData), // whether node_updated needs full rebuild
  nodeColor(data, config, pagesMap, hubsMap), // custom node color
}
```
All keys are optional — only implement what the type needs.

---

## Current Files → New Location

### Elixir Files Deleted/Moved
| Current File | New Location |
|------|--------------|
| `handlers/node_event_handlers.ex` | Split → `handlers/generic_node_handlers.ex` + per-type `node.ex` |
| `handlers/response_event_handlers.ex` | `nodes/dialogue/node.ex` |
| `handlers/condition_event_handlers.ex` | `nodes/condition/node.ex` |
| `handlers/instruction_event_handlers.ex` | `nodes/instruction/node.ex` |
| `helpers/response_helpers.ex` | `nodes/dialogue/node.ex` |
| `components/panels/dialogue_panel.ex` | `nodes/dialogue/config_sidebar.ex` |
| `components/panels/condition_panel.ex` | `nodes/condition/config_sidebar.ex` |
| `components/panels/instruction_panel.ex` | `nodes/instruction/config_sidebar.ex` |
| `components/panels/simple_panels.ex` | Split → `entry/`, `exit/`, `hub/`, `jump/` config_sidebar.ex |
| `components/node_type_helpers.ex` | Split → per-type modules + registry |

### JavaScript Files Deleted/Moved
| Current File | New Location |
|------|--------------|
| `node_config.js` | `nodes/index.js` (aggregates per-type configs) |
| `components/node_formatters.js` | Split → per-type `nodes/{type}.js` |

---

## Implementation Phases

### Phase 1: Scaffold + Registry Refactor
1. Create `nodes/` directory with 14 stub files (7 types x `node.ex` + `config_sidebar.ex`)
2. Move metadata (icon, label, default_data, extract_form_data) from `NodeTypeRegistry` into each `node.ex`
3. Refactor `NodeTypeRegistry` to aggregate via module lookup map
4. Add `node_module/1` and `sidebar_module/1` to registry
5. **All callers still work unchanged** — public API identical
6. `mix test` → commit

### Phase 2: Simple Types (entry, exit, jump)
1. **Entry**: Move panel from `simple_panels.ex` → `entry/config_sidebar.ex`
2. **Exit**: Move panel + `generate_exit_technical_id` logic → `exit/node.ex` + `exit/config_sidebar.ex`
3. **Jump**: Move panel → `jump/config_sidebar.ex`
4. Update `properties_panels.ex` to dispatch to per-type sidebar modules (hybrid: new types use modules, old types still use old code)
5. `mix test` → commit

### Phase 3: Hub Node
1. Move panel from `simple_panels.ex` → `hub/config_sidebar.ex`
2. Move `on_select` logic (load referencing_jumps) from `node_event_handlers.ex` → `hub/node.ex`
3. Move `duplicate_data_cleanup` (clear hub_id) → `hub/node.ex`
4. Update `node_event_handlers.ex` to delegate to `hub/node.ex`
5. `mix test` → commit

### Phase 4: Condition Node
1. Move ALL of `condition_event_handlers.ex` → `condition/node.ex` (condition builder, switch mode, apply_condition_update)
2. Keep `handle_update_response_condition_builder` in `condition/node.ex` (it's condition-building logic, called for dialogue responses too)
3. Move panel from `condition_panel.ex` → `condition/config_sidebar.ex`
4. Update `show.ex` to dispatch condition events to `Condition.Node`
5. Delete `condition_event_handlers.ex`
6. `mix test` → commit

### Phase 5: Instruction Node
1. Move ALL of `instruction_event_handlers.ex` → `instruction/node.ex`
2. Move panel from `instruction_panel.ex` → `instruction/config_sidebar.ex`
3. Update `show.ex` dispatch
4. Delete `instruction_event_handlers.ex`
5. `mix test` → commit

### Phase 6: Dialogue Node (largest)
1. Move response handler functions (add/remove/update_response_*) → `dialogue/node.ex`
2. Move ALL of `response_helpers.ex` (response CRUD, connection migration) → `dialogue/node.ex`
3. Move `handle_generate_technical_id` (dialogue branch) → `dialogue/node.ex`
4. Move `handle_open_screenplay`, `on_double_click` → `dialogue/node.ex`
5. Move private helpers: `get_speaker_name`, `count_speaker_in_flow`, `word_count`, `normalize_for_id` → `dialogue/node.ex`
6. Move panel from `dialogue_panel.ex` → `dialogue/config_sidebar.ex`
7. Update `show.ex` to dispatch dialogue events
8. Delete `response_event_handlers.ex`, `response_helpers.ex`
9. `mix test` → commit

### Phase 7: Clean Up Generic Handlers
1. Rename `node_event_handlers.ex` → `generic_node_handlers.ex` — only generic ops remain
2. Trim `node_helpers.ex`: `duplicate_node` delegates to per-type `duplicate_data_cleanup/1`
3. `node_selected` and `node_double_clicked` dispatch via `on_select/2` and `on_double_click/2` to per-type modules
4. Simplify `properties_panels.ex`: remove all if/else, single dispatch to `sidebar_module`
5. Delete: `simple_panels.ex`, `dialogue_panel.ex`, `condition_panel.ex`, `instruction_panel.ex`, `node_type_helpers.ex`
6. Clean up `show.ex` imports
7. `mix test` + `mix precommit` → commit

### Phase 8: JavaScript Refactoring
1. Create `nodes/` directory with `index.js` + 7 per-type files
2. Extract per-type config, rendering, formatting into each `nodes/{type}.js`
3. Refactor `flow_node.js` to delegate pin creation to per-type `createOutputs`
4. Refactor `storyarn_node.js` to delegate body rendering via per-type functions
5. Refactor `editor_handlers.js`: rename `rebuildDialogueNode` → `rebuildNode`, use `needsRebuild` per-type
6. Simplify `node_config.js` → thin aggregator from `nodes/index.js`
7. Delete `node_formatters.js` (content moved to per-type modules)
8. Manual browser testing of all node types
9. Commit

### Phase 9: Final Cleanup
1. Verify no orphaned files
2. Update `CLAUDE.md` with new file structure
3. `mix precommit` → final commit

---

## Key Decisions

| Decision | Choice | Why |
|----------|--------|-----|
| Dispatch mechanism | Module lookup map in registry, no behaviours | Simple, explicit, no over-abstraction |
| `apply_condition_update` location | `condition/node.ex` (shared for both condition nodes AND dialogue response conditions) | Condition-building logic belongs to condition module |
| Sidebar wrapper | Shared frame in `properties_panels.ex`, delegates content to per-type `config_sidebar.ex` | Frame is identical for all types, no need to duplicate |
| `normalize_form_params` | Moves to dialogue's sidebar (it normalizes dialogue-specific fields) | Type-specific normalization belongs with the type |
| JS `rebuildDialogueNode` | Renamed to `rebuildNode`, driven by per-type `needsRebuild` | Condition nodes also have dynamic outputs |

---

## Verification
After each phase:
- `mix test`
- `mix format`
- `mix credo`
- Manual browser test: create/edit each node type, test screenplay, condition builder, hub/jump navigation

After final phase:
- `mix precommit`
- Verify each node directory is self-contained (reading 2 files tells you everything about that node)
