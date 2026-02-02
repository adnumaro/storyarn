# Code Refactoring Plan

## Executive Summary

Audit identified **12 files** exceeding recommended limits (500 lines for Elixir/JS).

| File | Lines | Severity | Priority |
|------|-------|----------|----------|
| `flow_live/show.ex` | 1,330 | Critical | P0 |
| `flow_canvas.js` | 1,151 | Critical | P0 |
| `page_live/show.ex` | 769 | High | P1 |
| `core_components.ex` | 580 | Medium | P2 |
| `accounts_test.exs` | 569 | Low | P3 |
| `layouts.ex` | 471 | Low | P3 |

---

## Phase 1: Flow Editor (Critical - 2,481 lines total)

### 1.1 `flow_live/show.ex` (1,330 lines → ~250 lines main + components)

**Current Structure:**
- Render function (lines 20-213) - 194 lines of HEEx
- Private components (lines 217-413) - `save_indicator`, `node_type_icon`, `node_type_label`, `node_properties_form`
- Mount & setup (lines 415-499) - collaboration setup, initial state
- 20+ `handle_event` callbacks (lines 506-988) - node/connection/response CRUD
- `handle_info` callbacks (lines 990-1074) - collaboration messages
- Helper functions (lines 1076-1330) - form builders, broadcasters

**Proposed Extraction:**

```
lib/storyarn_web/live/flow_live/
├── show.ex                    (~250 lines) - Main LiveView, mount, render shell
├── components/
│   ├── flow_header.ex         (~50 lines)  - Header with breadcrumb, add node
│   ├── node_panel.ex          (~120 lines) - Node properties side panel
│   ├── connection_panel.ex    (~60 lines)  - Connection properties side panel
│   └── node_type_helpers.ex   (~60 lines)  - node_type_icon, node_type_label
├── events/
│   ├── node_events.ex         (~180 lines) - handle_event for node CRUD
│   ├── connection_events.ex   (~100 lines) - handle_event for connections
│   └── response_events.ex     (~100 lines) - handle_event for dialogue responses
└── collaboration/
    ├── collaboration_events.ex (~100 lines) - handle_info for presence/cursors/locks
    └── collaboration_helpers.ex (~80 lines) - broadcast helpers, toast helpers
```

**Pattern:** Use `defdelegate` in main module or `use` macros to compose behavior.

**Implementation Steps:**

1. **Extract Node Type Helpers** (low risk)
   - Create `FlowLive.Components.NodeTypeHelpers`
   - Move `node_type_icon/1`, `node_type_label/1`, `default_node_data/1`
   - Import in `show.ex`

2. **Extract Panel Components** (low risk)
   - Create `FlowLive.Components.NodePanel` as functional component
   - Create `FlowLive.Components.ConnectionPanel` as functional component
   - Move `node_properties_form/1` to NodePanel
   - Import in `show.ex`

3. **Extract Event Handlers** (medium risk)
   - Create behavior modules with `defoverridable` callbacks
   - Use `__using__` macro to inject event handlers
   - Or use simple module + `defdelegate` pattern

4. **Extract Collaboration** (medium risk)
   - Create `FlowLive.Collaboration.Events` module
   - Create `FlowLive.Collaboration.Helpers` module
   - Handle_info callbacks can use pattern matching in main module

---

### 1.2 `flow_canvas.js` (1,151 lines → ~200 lines main + modules)

**Current Structure:**
- Helper functions (lines 11-59) - icon creation, NODE_CONFIGS
- `StoryarnNode` LitElement (lines 62-263) - 200 lines
- `StoryarnSocket` LitElement (lines 266-300) - 35 lines
- `StoryarnConnection` LitElement (lines 303-437) - 135 lines
- `FlowNode` class (lines 440-467) - 28 lines
- `FlowCanvas` hook (lines 469-1111) - 643 lines
  - `initEditor` (50 lines)
  - `loadFlow` (15 lines)
  - `addNodeToEditor` / `addConnectionToEditor` (40 lines)
  - `setupEventHandlers` (100 lines)
  - Mouse/cursor handlers (80 lines)
  - Lock handlers (80 lines)
  - Node CRUD handlers (150 lines)
  - Connection handlers (60 lines)
  - Keyboard handler (40 lines)
  - Cleanup (40 lines)
- Global styles (lines 1114-1151)

**Proposed Extraction:**

```
assets/js/hooks/
├── flow_canvas.js             (~200 lines) - Main hook, init, cleanup
├── flow_canvas/
│   ├── node_config.js         (~60 lines)  - NODE_CONFIGS + createIconSvg
│   ├── flow_node.js           (~40 lines)  - FlowNode class
│   ├── components/
│   │   ├── storyarn_node.js   (~210 lines) - StoryarnNode LitElement
│   │   ├── storyarn_socket.js (~40 lines)  - StoryarnSocket LitElement
│   │   └── storyarn_connection.js (~140 lines) - StoryarnConnection LitElement
│   ├── handlers/
│   │   ├── event_handlers.js  (~100 lines) - setupEventHandlers
│   │   ├── node_handlers.js   (~150 lines) - handleNodeAdded/Removed/Updated
│   │   ├── connection_handlers.js (~80 lines) - handleConnectionAdded/Removed
│   │   └── keyboard_handler.js (~50 lines) - handleKeyboard
│   └── collaboration/
│       ├── cursor_handler.js  (~100 lines) - cursor tracking, remote cursors
│       └── lock_handler.js    (~80 lines)  - lock indicators, isNodeLocked
└── flow_canvas_styles.js      (~40 lines)  - Global CSS injection
```

**Implementation Steps:**

1. **Extract LitElement Components** (low risk)
   - Move `StoryarnNode`, `StoryarnSocket`, `StoryarnConnection` to separate files
   - Export and import in main file
   - Register custom elements after import

2. **Extract Node Config** (low risk)
   - Move `NODE_CONFIGS` and `createIconSvg` to `node_config.js`
   - Move `FlowNode` class to `flow_node.js`

3. **Extract Event Handlers** (medium risk)
   - Create handler classes/functions that receive `this` context
   - Bind handlers in main hook

4. **Extract Collaboration** (medium risk)
   - Create `CursorHandler` class
   - Create `LockHandler` class
   - Instantiate in main hook

---

## Phase 2: Page Editor (High Priority - 769 lines)

### 2.1 `page_live/show.ex` (769 lines → ~200 lines main + modules)

**Current Structure:**
- Render function (lines 15-134) - 120 lines
- `save_indicator` component (lines 137-157)
- Mount (lines 159-212) - 54 lines
- Handle_event callbacks (lines 219-621) - 400+ lines mixed concerns
  - Name editing (30 lines)
  - Block CRUD (100 lines)
  - Multi-select handling (80 lines)
  - Config panel (100 lines)
  - Rich text (20 lines)
  - Page tree operations (80 lines)
- Helper functions (lines 623-769)

**Proposed Extraction:**

```
lib/storyarn_web/live/page_live/
├── show.ex                    (~200 lines) - Main LiveView, mount, render
├── components/
│   └── save_indicator.ex      (~30 lines)  - Shared with flow_live
└── events/
    ├── name_events.ex         (~40 lines)  - edit_name, save_name, cancel_edit_name
    ├── block_events.ex        (~150 lines) - add_block, delete_block, update_block_value
    ├── config_events.ex       (~120 lines) - configure_block, save_block_config, options
    └── page_tree_events.ex    (~80 lines)  - move_page, create_child_page, delete_page
```

**Implementation Steps:**

1. **Extract Save Indicator** (low risk)
   - This component is duplicated - create shared component
   - Put in `lib/storyarn_web/components/save_indicator.ex`
   - Import in both flow_live and page_live

2. **Extract Block Events** (medium risk)
   - Create `PageLive.Events.BlockEvents` module
   - Use `defdelegate` or macro injection

3. **Extract Config Events** (medium risk)
   - Create `PageLive.Events.ConfigEvents` module
   - Handle select options, multi-select, rich text

4. **Extract Page Tree Events** (low risk)
   - Create `PageLive.Events.PageTreeEvents` module
   - Move page navigation and CRUD

---

## Phase 3: Core Components (Medium Priority)

### 3.1 `core_components.ex` (580 lines → ~300 lines + extractions)

**Current Structure:**
- Flash components (50 lines)
- Form components (200 lines) - input, label, error
- Button component (60 lines)
- Icon component (30 lines)
- Badge component (20 lines)
- Table components (80 lines)
- Empty state (30 lines)
- Header/section (60 lines)
- Misc helpers (50 lines)

**Proposed Extraction:**

```
lib/storyarn_web/components/
├── core_components.ex         (~300 lines) - Keep most-used components
├── form_components.ex         (~150 lines) - input, label, error, textarea
└── table_components.ex        (~80 lines)  - table, thead, tbody, tr, td
```

**Note:** This is lower priority as Phoenix generators expect `core_components.ex` to exist. Only extract if it grows further.

---

## Phase 4: Test Files (Low Priority)

Test files over 500 lines are less critical but can benefit from organization:

- `accounts_test.exs` (569 lines) - Consider splitting into `accounts/users_test.exs`, `accounts/sessions_test.exs`, etc.
- `user_auth_test.exs` (392 lines) - Acceptable, no action needed
- `projects_test.exs` (389 lines) - Acceptable, no action needed
- `flows_test.exs` (342 lines) - Acceptable, no action needed

---

## Implementation Order

### Sprint 1: Shared Components & Low-Risk Extractions
- [ ] Create shared `SaveIndicator` component
- [ ] Extract `NodeTypeHelpers` from flow_live
- [ ] Extract JS LitElement components to separate files
- [ ] Extract `NODE_CONFIGS` to separate file

### Sprint 2: Flow Editor Event Handlers
- [ ] Extract flow node event handlers
- [ ] Extract flow connection event handlers
- [ ] Extract flow response event handlers
- [ ] Extract collaboration events and helpers

### Sprint 3: Flow Canvas JS Handlers
- [ ] Extract cursor/collaboration handlers
- [ ] Extract lock handlers
- [ ] Extract keyboard handler
- [ ] Extract node/connection handlers

### Sprint 4: Page Editor
- [ ] Extract page block event handlers
- [ ] Extract page config event handlers
- [ ] Extract page tree event handlers

### Sprint 5: Final Cleanup
- [ ] Consider core_components extraction
- [ ] Consider test file organization
- [ ] Update imports and verify all tests pass

---

## Technical Approach: Event Handler Extraction (Elixir)

Two recommended patterns:

### Pattern A: Module + defdelegate (Simpler)

```elixir
# lib/storyarn_web/live/flow_live/events/node_events.ex
defmodule StoryarnWeb.FlowLive.Events.NodeEvents do
  @moduledoc false

  alias Storyarn.Flows

  def handle_add_node(socket, %{"type" => type}) do
    # ... implementation
  end
end

# lib/storyarn_web/live/flow_live/show.ex
def handle_event("add_node", params, socket) do
  NodeEvents.handle_add_node(socket, params)
end
```

### Pattern B: Use macro for injection (More DRY)

```elixir
# lib/storyarn_web/live/flow_live/events/node_events.ex
defmodule StoryarnWeb.FlowLive.Events.NodeEvents do
  defmacro __using__(_opts) do
    quote do
      def handle_event("add_node", params, socket) do
        # ... implementation
      end

      def handle_event("delete_node", params, socket) do
        # ... implementation
      end
    end
  end
end

# lib/storyarn_web/live/flow_live/show.ex
use StoryarnWeb.FlowLive.Events.NodeEvents
```

**Recommendation:** Start with Pattern A (explicit delegation) for clarity, refactor to Pattern B only if duplication becomes problematic.

---

## Technical Approach: JS Module Extraction

```javascript
// assets/js/hooks/flow_canvas/components/storyarn_node.js
import { LitElement, css, html } from "lit";
import { unsafeSVG } from "lit/directives/unsafe-svg.js";
import { NODE_CONFIGS } from "../node_config.js";

export class StoryarnNode extends LitElement {
  // ... full implementation
}

customElements.define("storyarn-node", StoryarnNode);

// assets/js/hooks/flow_canvas.js
import "./flow_canvas/components/storyarn_node.js";
import "./flow_canvas/components/storyarn_socket.js";
import "./flow_canvas/components/storyarn_connection.js";
import { FlowNode } from "./flow_canvas/flow_node.js";
import { NODE_CONFIGS } from "./flow_canvas/node_config.js";

export const FlowCanvas = {
  // ... reduced to ~200 lines
};
```

---

## Success Metrics

| Metric | Current | Target |
|--------|---------|--------|
| Max Elixir file lines | 1,330 | < 400 |
| Max JS file lines | 1,151 | < 300 |
| Files > 500 lines | 6 | 0 |
| Files > 300 lines | 10 | < 5 |

---

## Risks & Mitigations

| Risk | Impact | Mitigation |
|------|--------|------------|
| Breaking LiveView event routing | High | Comprehensive E2E tests before/after |
| JS module loading order | Medium | Use ES modules, verify in browser |
| Import cycles | Medium | Clear dependency direction (handlers → core) |
| Test coverage gaps | Medium | Run full test suite after each extraction |

---

## Notes

- All extractions should maintain existing public API
- No new features during refactoring
- Each extraction should be a separate commit
- Run `mix precommit` and `npm run check` after each change
