# Phase 1 — Unified TipTap Editor: Task Breakdown

> **Parent plan:** `docs/plans/SCREENPLAY_UNIFIED_TIPTAP.md`
> **Goal:** Replace all per-element TipTap instances and the contenteditable character hook with a single TipTap editor. Text-based types only. Interactive blocks remain server-rendered for now.
> **Principle:** Each task is self-contained, provides value on its own, includes tests, and follows SOLID/YAGNI/KISS.

---

## Task Overview

| #   | Task                               | Type       | Depends on  | Status  |
|-----|------------------------------------|------------|-------------|---------|
| 1   | Elixir TipTap Serialization module | Backend    | —           | Pending |
| 2   | Custom TipTap Node Extensions      | Frontend   | —           | Pending |
| 3   | ScreenplayKeymap Extension         | Frontend   | Task 2      | Pending |
| 4   | Placeholder Extension + CSS        | Frontend   | Task 2      | Pending |
| 5   | Mention Extension Adaptation       | Frontend   | —           | Pending |
| 6   | SlashCommands Extension + Renderer | Frontend   | Task 2      | Pending |
| 7   | LiveView Bridge + JS Serialization | Frontend   | Task 2      | Pending |
| 8   | ScreenplayEditor Hook Assembly     | Frontend   | Tasks 2-7   | Pending |
| 9   | LiveView Integration (show.ex)     | Full-stack | Tasks 1, 8  | Pending |
| 10  | Test Migration + Old Code Removal  | Full-stack | Task 9      | Pending |

---

## Task 1: Elixir TipTap Serialization Module

### Goal

Create `Storyarn.Screenplays.TiptapSerialization` — a pure Elixir module that converts between `ScreenplayElement` records and TipTap document JSON. This is the server-side foundation for the unified editor.

### Why this provides value on its own

- Centralizes all serialization logic that is currently scattered across `content_utils.ex`, `node_mapping.ex`, and ad-hoc conversions in `show.ex`
- Fully testable without any frontend changes
- Can be used immediately by `show.ex` to render `data-content` JSON for the future editor

### Files to create

- `lib/storyarn/screenplays/tiptap_serialization.ex`
- `test/storyarn/screenplays/tiptap_serialization_test.exs`

### Specification

```elixir
defmodule Storyarn.Screenplays.TiptapSerialization do
  @moduledoc """
  Converts between ScreenplayElement records and TipTap document JSON.

  ## Type mapping

  Server uses snake_case (`scene_heading`), TipTap uses camelCase (`sceneHeading`).
  Atom nodes (page_break, conditional, etc.) have no inline content.
  Text nodes (action, dialogue, etc.) carry HTML content parsed to TipTap inline format.
  """

  # Public API:
  # - elements_to_doc(elements) :: map()
  #     Converts a sorted list of ScreenplayElement structs to a TipTap JSON document.
  #     Returns %{"type" => "doc", "content" => [...]}.
  #     Empty list produces a single empty action node.
  #
  # - doc_to_element_attrs(doc_json) :: [map()]
  #     Converts a TipTap JSON document to a list of attribute maps suitable for
  #     creating/updating ScreenplayElement records.
  #     Each map has: %{type, position, content, data, element_id}.
  #
  # - server_type_to_tiptap(type) :: String.t()
  #     Converts "scene_heading" -> "sceneHeading", etc.
  #
  # - tiptap_type_to_server(type) :: String.t()
  #     Converts "sceneHeading" -> "scene_heading", etc.
end
```

### Type mapping table

| Server type     | TipTap type     | Atom?   |
|-----------------|-----------------|---------|
| `scene_heading` | `sceneHeading`  | No      |
| `action`        | `action`        | No      |
| `character`     | `character`     | No      |
| `dialogue`      | `dialogue`      | No      |
| `parenthetical` | `parenthetical` | No      |
| `transition`    | `transition`    | No      |
| `note`          | `note`          | No      |
| `section`       | `section`       | No      |
| `page_break`    | `pageBreak`     | Yes     |
| `dual_dialogue` | `dualDialogue`  | Yes     |
| `conditional`   | `conditional`   | Yes     |
| `instruction`   | `instruction`   | Yes     |
| `response`      | `response`      | Yes     |
| `hub_marker`    | `hubMarker`     | Yes     |
| `jump_marker`   | `jumpMarker`    | Yes     |
| `title_page`    | `titlePage`     | Yes     |

### Content conversion (Phase 1 — simplified)

**Elements to doc (server -> client):**
- Text nodes: Parse HTML content into TipTap inline content. For Phase 1, use a simple approach:
  - Wrap `<p>...</p>` content as-is (TipTap's `parseHTML` handles it client-side)
  - Store the raw HTML as a text node if no structure is detected
- Atom nodes: No content, only `attrs` with `elementId` and `data`

**Doc to elements (client -> server):**
- Text nodes: Extract text content from TipTap inline nodes. For Phase 1:
  - Concatenate text from `{"type": "text", "text": "..."}` nodes
  - Preserve mention marks as HTML `<span class="mention">` tags
- Atom nodes: Extract `data` from `attrs`

### Tests

```
test "elements_to_doc converts empty list to doc with single action node"
test "elements_to_doc preserves element order by position"
test "elements_to_doc converts each text element type correctly"
test "elements_to_doc converts atom element types correctly"
test "elements_to_doc preserves element ID in attrs"
test "elements_to_doc preserves element data in attrs"
test "elements_to_doc handles nil content gracefully"
test "elements_to_doc handles empty string content"
test "doc_to_element_attrs extracts type, position, content, data, element_id"
test "doc_to_element_attrs handles atom nodes (no content)"
test "doc_to_element_attrs handles empty doc"
test "doc_to_element_attrs preserves position index"
test "round_trip: elements -> doc -> attrs preserves all data"
test "round_trip: mixed text and atom nodes"
test "server_type_to_tiptap converts all known types"
test "tiptap_type_to_server converts all known types"
test "server_type_to_tiptap returns input for unknown types"
test "tiptap_type_to_server returns input for unknown types"
```

### Acceptance criteria

- [x] Module compiles with `--warnings-as-errors`
- [x] All tests pass
- [x] Credo `--strict` clean
- [x] Round-trip conversion preserves all element data
- [x] Unknown types pass through without error

---

## Task 2: Custom TipTap Node Extensions

### Goal

Define all TipTap node extensions needed for the screenplay document schema. These are the building blocks — each extension is a self-contained module that tells TipTap how to parse, render, and serialize a screenplay element type.

### Why this provides value on its own

- Defines the document schema that all other extensions depend on
- Each node is independently testable (can be loaded into a minimal TipTap editor)
- Establishes the naming convention and attribute pattern used throughout

### Files to create

```
assets/js/screenplay/nodes/
├── screenplay_doc.js       # Custom top-level document node
├── scene_heading.js        # Text block
├── action.js               # Text block
├── character.js            # Text block (+ sheet_id attribute)
├── dialogue.js             # Text block
├── parenthetical.js        # Text block
├── transition.js           # Text block
├── note.js                 # Text block
├── section.js              # Text block
├── page_break.js           # Atom node (no editable content)
└── index.js                # Re-export all nodes for easy import
```

### Specification

**ScreenplayDoc** (`screenplay_doc.js`):
- `name: "doc"`, `topNode: true`, `content: "screenplayBlock+"`
- Replaces the default `Document` from StarterKit
- Forces the document to only contain screenplay block nodes

**Text block nodes** (all follow identical pattern):
- `group: "screenplayBlock"`, `content: "inline*"`, `defining: true`
- Attribute: `elementId` (default null) — links to server-side ScreenplayElement ID
- Attribute: `data` (default `{}`) — preserves arbitrary server data
- `parseHTML`: matches `div[data-node-type="<snake_case_type>"]`
- `renderHTML`: outputs `<div data-node-type="<snake_case_type>" class="sp-<snake_case_type>">`

**Character node** (extends text block pattern):
- Additional attribute: `sheetId` (default null) — character sheet reference
- `renderHTML`: adds `data-sheet-id` attribute when `sheetId` is set

**PageBreak** (`page_break.js`):
- `group: "screenplayBlock"`, `atom: true`, `selectable: true`, `draggable: false`
- `parseHTML`: matches `div[data-node-type="page_break"]`
- `renderHTML`: outputs `<div data-node-type="page_break" class="sp-page_break"><div class="sp-page-break-line"></div></div>`
- No content hole (atom node)

**Factory function** — to avoid 8 nearly-identical files, create a helper:

```javascript
// assets/js/screenplay/nodes/create_text_node.js
import { Node, mergeAttributes } from "@tiptap/core";

/**
 * Creates a screenplay text block node with the standard attribute pattern.
 * @param {string} name - TipTap node name (camelCase)
 * @param {string} serverType - Server type (snake_case) used in data-node-type
 * @param {Object} [extraAttrs] - Additional attributes beyond elementId and data
 */
export function createTextNode(name, serverType, extraAttrs = {}) {
  return Node.create({
    name,
    group: "screenplayBlock",
    content: "inline*",
    defining: true,

    addAttributes() {
      return {
        elementId: {
          default: null,
          parseHTML: (el) => el.dataset.elementId || null,
          renderHTML: () => ({}),
        },
        data: {
          default: {},
          parseHTML: () => ({}),
          renderHTML: () => ({}),
        },
        ...extraAttrs,
      };
    },

    parseHTML() {
      return [{ tag: `div[data-node-type="${serverType}"]` }];
    },

    renderHTML({ HTMLAttributes }) {
      return [
        "div",
        mergeAttributes(HTMLAttributes, {
          "data-node-type": serverType,
          class: `sp-${serverType}`,
        }),
        0,
      ];
    },
  });
}
```

Then each text node is a one-liner:
```javascript
// scene_heading.js
import { createTextNode } from "./create_text_node.js";
export const SceneHeading = createTextNode("sceneHeading", "scene_heading");
```

### Tests

JS tests are validated by:
1. **Compilation check**: `npm run build` (esbuild) succeeds with no errors
2. **Manual smoke test** (documented as test steps for the developer):
   - Create a minimal HTML file that loads the editor with all nodes
   - Verify: typing produces the correct DOM structure
   - Verify: `data-node-type` attributes are present
   - Verify: CSS classes (`sp-action`, etc.) are applied
3. **Integration tests** (in Task 10): LiveView tests verify the editor renders correctly

### Acceptance criteria

- [ ] All node files compile via esbuild (no import errors)
- [ ] `index.js` re-exports all nodes cleanly
- [ ] Factory pattern (`createTextNode`) eliminates duplication
- [ ] Character node has extra `sheetId` attribute
- [ ] PageBreak is an atom node with no content hole
- [ ] ScreenplayDoc restricts content to `screenplayBlock+`

---

## Task 3: ScreenplayKeymap Extension

### Goal

Create the `ScreenplayKeymap` TipTap extension that handles all screenplay-specific keyboard behavior: Enter (create next block with correct type), Tab/Shift-Tab (cycle type), Backspace (delete empty blocks), and Escape (blur).

### Why this provides value on its own

- Encapsulates all keyboard logic in one extension (Single Responsibility)
- Replaces the keyboard handling currently split across `screenplay_element.js` (lines 79-196) and `screenplay_tiptap_element.js` (lines 100-149)
- Can be tested independently with a minimal TipTap editor

### Files to create

- `assets/js/screenplay/extensions/screenplay_keymap.js`

### Specification

**Key mappings:**

| Key           | Context                                      | Behavior                                               |
|---------------|----------------------------------------------|--------------------------------------------------------|
| `Enter`       | Empty non-action text block                  | Convert to `action` (instead of splitting)             |
| `Enter`       | Non-empty text block                         | Split block. New block type = `NEXT_TYPE[currentType]` |
| `Enter`       | Atom node selected                           | Insert new `action` block after atom                   |
| `Shift-Enter` | Any text block                               | Hard break (default TipTap behavior — no override)     |
| `Tab`         | Text block in `TYPE_CYCLE`                   | Set node to next type in cycle                         |
| `Shift-Tab`   | Text block in `TYPE_CYCLE`                   | Set node to previous type in cycle                     |
| `Backspace`   | Empty non-action text block, cursor at start | Convert to `action`                                    |
| `Backspace`   | Empty action block, cursor at start          | Default ProseMirror joinBackward                       |
| `Escape`      | Any                                          | Blur editor                                            |

**Constants** (defined within the extension, not imported from shared):

```javascript
const NEXT_TYPE = {
  sceneHeading: "action",
  action: "action",
  character: "dialogue",
  parenthetical: "dialogue",
  dialogue: "action",
  transition: "sceneHeading",
  note: "action",
  section: "action",
};

const TYPE_CYCLE = [
  "action", "sceneHeading", "character", "dialogue",
  "parenthetical", "transition",
];
```

### Design decisions

- **YAGNI**: No `note` or `section` in `TYPE_CYCLE` — they're utility types inserted via slash command, not cycled to. The old `constants.js` also excluded them.
- **KISS**: Enter logic is a simple lookup table, not a state machine.
- **SOLID (SRP)**: Only keyboard behavior. No DOM manipulation, no server events, no styling.

### Tests

Validated by compilation + manual keyboard testing steps:
1. Create an action block, type text, press Enter -> new action block appears
2. Create a character block, type name, press Enter -> dialogue block appears
3. Empty dialogue block, press Enter -> converts to action
4. Press Tab on action -> cycles to sceneHeading
5. Press Shift-Tab on sceneHeading -> cycles to transition
6. Empty character block, press Backspace -> converts to action
7. Empty action block (only one remaining), press Backspace -> block stays (doc can't be empty)

### Acceptance criteria

- [ ] Compiles via esbuild without errors
- [ ] Enter creates correct next type for each source type
- [ ] Empty Enter converts non-action to action
- [ ] Tab/Shift-Tab cycle through TYPE_CYCLE
- [ ] Backspace on empty non-action converts to action before deleting
- [ ] Escape blurs the editor

---

## Task 4: Placeholder Extension + CSS

### Goal

Install `@tiptap/extension-placeholder` and configure per-node-type placeholders. Update CSS so placeholders display correctly within the unified editor.

### Why this provides value on its own

- Users see contextual hints in empty blocks ("INT. LOCATION - TIME" for scene headings, etc.)
- Replaces the current brittle CSS placeholder system (`.sp-empty` + `data-placeholder` + `::before`)
- Uses TipTap's official extension — no custom CSS hacks needed

### Files to create/modify

- **Install**: `@tiptap/extension-placeholder` npm package
- **Create**: `assets/js/screenplay/extensions/screenplay_placeholder.js`
- **Modify**: `assets/css/screenplay.css` — remove old placeholder CSS, add new

### Specification

```javascript
// assets/js/screenplay/extensions/screenplay_placeholder.js
import Placeholder from "@tiptap/extension-placeholder";

const PLACEHOLDERS = {
  sceneHeading: "INT. LOCATION - TIME",
  action: "Describe the action...",
  character: "CHARACTER NAME",
  dialogue: "Dialogue text...",
  parenthetical: "(acting direction)",
  transition: "CUT TO:",
  note: "Note...",
  section: "Section heading",
};

export const ScreenplayPlaceholder = Placeholder.configure({
  showOnlyCurrent: true,
  includeChildren: false,
  placeholder: ({ node }) => PLACEHOLDERS[node.type.name] || "",
});
```

**CSS changes:**

Remove:
```css
/* Old placeholder rules targeting .sp-empty, .sp-block[data-placeholder], .sp-tiptap-prosemirror */
```

Add:
```css
/* TipTap Placeholder extension adds .is-empty + .is-editor-empty classes */
.screenplay-prosemirror .is-empty::before {
  content: attr(data-placeholder);
  color: oklch(0.556 0.02 252.8 / 0.5);
  font-style: italic;
  pointer-events: none;
  float: left;
  height: 0;
}
```

### Tests

1. **Build**: `npm run build` succeeds after installing the package
2. **Visual**: Each empty block type shows its placeholder text
3. **Behavior**: Placeholder disappears as soon as user types
4. **Focus**: `showOnlyCurrent: true` means only the focused empty block shows placeholder

### Acceptance criteria

- [ ] `@tiptap/extension-placeholder` installed in package.json
- [ ] Each of the 8 text node types has a unique placeholder
- [ ] Placeholder only shows on the currently focused empty block
- [ ] Old placeholder CSS removed (no `.sp-empty` placeholder rules)
- [ ] Compiles and builds without errors

---

## Task 5: Mention Extension Adaptation

### Goal

Refactor the existing `mention_extension.js` so it can receive the LiveView hook reference via TipTap extension options instead of being tightly coupled to the hook constructor argument.

### Why this provides value on its own

- Decouples the mention extension from any specific hook implementation
- Follows the Open/Closed principle — the extension works with any hook that has `pushEvent` and `handleEvent`
- Backward-compatible: existing `ScreenplayTiptapElement` can still use it during the transition period

### Files to modify

- `assets/js/tiptap/mention_extension.js`

### Specification

**Current API:**
```javascript
// Called from screenshot_tiptap_element.js
createMentionExtension(this) // `this` = the hook, must have pushEvent/handleEvent
```

**New API (backward-compatible):**
```javascript
// Option 1: legacy (still works)
createMentionExtension(hook)

// Option 2: via TipTap options (new)
createMentionExtension({ liveViewHook: hook })
```

**Changes inside `createMentionExtension`:**
```javascript
export function createMentionExtension(hookOrOptions) {
  // Support both old (hook directly) and new (options object) calling conventions
  const hook = hookOrOptions?.liveViewHook || hookOrOptions;

  // ... rest of the extension unchanged, uses `hook.pushEvent()` and `hook.handleEvent()`
}
```

### Tests

1. **Build**: Compiles without errors
2. **Backward compat**: Existing `ScreenplayTiptapElement` still works (manual test: type `#` in a dialogue element, see suggestions appear)
3. **New usage**: Can be called with `{ liveViewHook: hook }` and functions identically

### Acceptance criteria

- [ ] Both calling conventions work
- [ ] No changes to the mention rendering or behavior
- [ ] No changes to server-side events (`mention_suggestions`, `mention_suggestions_result`)
- [ ] Compiles without errors

---

## Task 6: SlashCommands Extension + Renderer

### Goal

Create a client-side slash command menu using TipTap's Suggestion API. This replaces the current server-rendered `SlashCommandMenu` component and eliminates the server round-trip for menu display/filtering.

### Why this provides value on its own

- Instant slash menu response (no server round-trip for open/filter/close)
- Menu rendered entirely in the browser
- Removes 5 server events: `open_slash_menu`, `close_slash_menu`, `select_slash_command`, `split_and_open_slash_menu`, `filter_slash_commands`

### Files to create

- `assets/js/screenplay/extensions/slash_commands.js` — TipTap extension using Suggestion API
- `assets/js/screenplay/extensions/slash_menu_renderer.js` — Floating menu DOM (vanilla JS)

### Specification

**Slash Commands Extension:**
- Trigger character: `/`
- Only activates when current block is empty (text content is just `/`)
- Uses `@tiptap/suggestion` (already installed)
- Command list matches current server-side list (from `slash_command_menu.ex`)

**Command categories:**

| Category    | Commands                                                              |
|-------------|-----------------------------------------------------------------------|
| Screenplay  | Scene Heading, Action, Character, Dialogue, Parenthetical, Transition |
| Interactive | Condition, Instruction, Responses                                     |
| Utility     | Note, Section, Page Break                                             |

**Command actions:**
- `setNode` mode: Replaces current block type (for text nodes)
- `insertAtom` mode: Inserts an atom node after current position (for page_break, and future interactive blocks)

**Renderer** (`slash_menu_renderer.js`):
- Creates a floating `<div class="slash-menu">` positioned near the cursor
- Each item: `<div class="slash-menu-item"><icon> <label> <description></div>`
- Keyboard: ArrowUp/Down navigate, Enter selects, Escape closes
- Filtering: Items filtered by label match against typed query
- Uses Lucide icons via `createElement()` (following project icon convention)
- Positioning: Uses `tippy.js` or manual positioning below the cursor

**Design decisions:**
- **YAGNI**: No category headers in the menu for now — just a flat filtered list. Categories can be added later if UX testing requires it.
- **KISS**: Icons are created with `lucide.createElement()` (project convention), not SVG strings.
- **SRP**: Renderer is separate from the extension logic.

### CSS

Reuse existing `.slash-menu` CSS classes from `screenplay.css`. No new CSS needed if the class names match.

### Tests

1. **Build**: Compiles without errors
2. **Behavior**: Type `/` in an empty block -> menu appears
3. **Filtering**: Type `/sce` -> only "Scene Heading" shows
4. **Selection**: Press Enter on "Scene Heading" -> block type changes to sceneHeading
5. **Escape**: Press Escape -> menu closes
6. **Non-empty**: Type `/` in a block with text -> menu does NOT appear

### Acceptance criteria

- [ ] Slash menu appears client-side with no server events
- [ ] All screenplay types available as commands
- [ ] Filtering works by label substring
- [ ] Arrow keys navigate, Enter selects, Escape closes
- [ ] Menu positioned near cursor
- [ ] `setNode` mode works for text types
- [ ] `insertAtom` mode works for page_break
- [ ] Compiles without errors

---

## Task 7: LiveView Bridge + JS Serialization

### Goal

Create the bidirectional sync layer between TipTap (client) and LiveView (server). This is the backbone that replaces all per-element `update_element_content`, `create_next_element`, `delete_element` events with a single `sync_editor_content` event.

### Why this provides value on its own

- Establishes the single-sync pattern that eliminates 6+ server events
- Client-side serialization (doc -> elements) is independently useful
- Debounced sync reduces server load vs. current per-keystroke events

### Files to create

- `assets/js/screenplay/extensions/liveview_bridge.js` — TipTap extension
- `assets/js/screenplay/serialization.js` — docToElements / elementsToDoc functions

### Specification

**LiveViewBridge extension:**

```javascript
export const LiveViewBridge = Extension.create({
  name: "liveViewBridge",

  addOptions() {
    return { liveViewHook: null };
  },

  addStorage() {
    return { debounceTimer: null, suppressUpdate: false };
  },

  // On every doc change (debounced 500ms): push elements to server
  onUpdate() { ... },

  // On blur: flush immediately
  onBlur() { ... },

  // On create: listen for server push events
  onCreate() {
    // "set_editor_content" -> replace entire doc (used by flow sync)
  },

  onDestroy() {
    // Clear debounce timer
  },
});
```

**Serialization** (`serialization.js`):

```javascript
// Client-side type mapping (camelCase <-> snake_case)
const NODE_TYPE_MAP = { sceneHeading: "scene_heading", ... };
const REVERSE_MAP = { scene_heading: "sceneHeading", ... };

// TipTap doc JSON -> flat element list for server
export function docToElements(editor) { ... }

// Flat element list -> TipTap doc JSON for client
export function elementsToDoc(elements, schema) { ... }
```

**Key design decisions:**
- **Debounce**: 500ms (matches current per-element debounce)
- **Flush on blur**: Ensures no data loss when user clicks away
- **Suppress flag**: Prevents infinite loops when server pushes content back
- **KISS**: No diffing on client — send full element list. Server does the diff.
- **SOLID (SRP)**: Serialization is a separate module from the extension.

### Tests

1. **Build**: Compiles without errors
2. **Serialization unit tests** (can be tested in Node.js or browser):
   - `docToElements` converts a doc with mixed node types to correct element list
   - `elementsToDoc` converts element list back to valid doc JSON
   - Type mapping is bidirectional and complete
   - Atom nodes have no content field
   - Text nodes have HTML content
3. **Integration** (manual):
   - Edit text -> wait 500ms -> server receives `sync_editor_content`
   - Blur editor -> server receives sync immediately
   - Server pushes `set_editor_content` -> editor updates without triggering re-sync

### Acceptance criteria

- [ ] Extension provides debounced client-to-server sync
- [ ] Extension listens for `set_editor_content` server push
- [ ] Suppress flag prevents infinite sync loops
- [ ] `docToElements` and `elementsToDoc` handle all 16 element types
- [ ] Serialization preserves element IDs and data
- [ ] Compiles without errors

---

## Task 8: ScreenplayEditor Hook Assembly

### Goal

Create the single `ScreenplayEditor` Phoenix LiveView hook that assembles all TipTap extensions into one editor instance. This hook replaces `ScreenplayEditorPage`, `ScreenplayElement`, `ScreenplayTiptapElement`, and `SlashCommand` hooks.

### Why this provides value on its own

- Single entry point for the entire screenplay editor
- Consolidates 4 hooks into 1
- Clean extension composition — each behavior is a separate extension (SRP)

### Files to create

- `assets/js/hooks/screenplay_editor.js`

### Files to modify

- `assets/js/app.js` — Add `ScreenplayEditor` to hooks (keep old hooks during transition)

### Specification

```javascript
export const ScreenplayEditor = {
  mounted() {
    // 1. Parse initial content from data-content attribute (TipTap JSON)
    // 2. Read data-can-edit for editable flag
    // 3. Create TipTap Editor with all extensions:
    //    - ScreenplayDoc (custom doc node)
    //    - StarterKit (only Text, HardBreak, History, Bold, Italic, Strike)
    //    - All text block nodes (SceneHeading, Action, Character, etc.)
    //    - PageBreak atom node
    //    - ScreenplayKeymap
    //    - ScreenplayPlaceholder
    //    - SlashCommands
    //    - LiveViewBridge (configured with this hook)
    //    - MentionExtension (configured with this hook)
    // 4. Listen for server events:
    //    - "focus_editor" -> focus at end
  },

  destroyed() {
    // Destroy editor instance
  },
};
```

**What this hook does NOT do:**
- No keyboard handling (delegated to ScreenplayKeymap)
- No sync logic (delegated to LiveViewBridge)
- No slash menu logic (delegated to SlashCommands)
- No mention logic (delegated to MentionExtension)

### Tests

1. **Build**: Compiles without errors, no import resolution failures
2. **Integration**: Hook can be mounted on a div with `phx-hook="ScreenplayEditor"`
3. **Initialization**: Editor creates with correct extensions based on `data-content` JSON

### Acceptance criteria

- [ ] Hook registered in `app.js`
- [ ] Editor initializes with all extensions
- [ ] Initial content loaded from `data-content` JSON attribute
- [ ] `data-can-edit` controls editable state
- [ ] `focus_editor` server event focuses the editor
- [ ] Editor destroyed cleanly on hook destroy
- [ ] Compiles without errors

---

## Task 9: LiveView Integration (show.ex)

### Goal

Modify `show.ex` to render the single TipTap editor container instead of per-element `<.element_renderer>` components. Add the `sync_editor_content` event handler that replaces per-element CRUD events.

### Why this provides value on its own

- This is the "flip the switch" task — the unified editor becomes live
- Removes the `element_renderer` loop from the template
- Adds the diff-and-persist handler for the new sync model

### Files to modify

- `lib/storyarn_web/live/screenplay_live/show.ex`

### Specification

**Render changes:**

Replace the element loop with a single editor container:

```heex
<div
  id="screenplay-editor"
  class={["screenplay-page", @read_mode && "screenplay-read-mode"]}
  phx-hook="ScreenplayEditor"
  data-content={Jason.encode!(TiptapSerialization.elements_to_doc(@elements))}
  data-can-edit={to_string(@can_edit && !@read_mode)}
/>
```

**New event handler:**

```elixir
def handle_event("sync_editor_content", %{"elements" => elements_json}, socket) do
  with_edit_permission(socket, fn ->
    do_sync_editor_content(socket, elements_json)
  end)
end
```

`do_sync_editor_content/2` logic:
1. Receive flat element list from client
2. Compare with existing `@elements` assigns
3. For each element in the client list:
   - If `element_id` matches an existing element: update content, type, position, data
   - If `element_id` is null: create new element at position
4. For each existing element NOT in the client list: delete it
5. Broadcast changes for collaboration
6. Update assigns

**Events to keep** (interactive blocks still use direct events):
- All condition/instruction/response events
- Character sheet events
- Mention events
- Toolbar/sidebar events

**Events that can be removed** (handled client-side now):
- `create_next_element`, `create_first_element`, `create_element_at_end`
- `delete_element` (for text elements — keep for interactive blocks from sidebar)
- `change_element_type`
- `open_slash_menu`, `close_slash_menu`, `select_slash_command`, `split_and_open_slash_menu`

**Important**: Keep `delete_element` as a fallback for interactive blocks that still use the trash button.

### Tests

**Elixir tests** (update `show_test.exs`):

```
test "renders screenplay editor with data-content JSON"
test "sync_editor_content creates new elements"
test "sync_editor_content updates existing elements"
test "sync_editor_content deletes removed elements"
test "sync_editor_content reorders elements"
test "sync_editor_content requires edit permission"
test "sync_editor_content handles empty element list"
test "sync_editor_content preserves interactive block data"
```

### Acceptance criteria

- [ ] Single editor container rendered with TipTap JSON in `data-content`
- [ ] `sync_editor_content` handler persists changes correctly
- [ ] Old per-element CRUD events removed (except `delete_element` fallback)
- [ ] Slash menu events removed from server
- [ ] All tests pass
- [ ] Credo `--strict` clean
- [ ] Compiles with `--warnings-as-errors`

---

## Task 10: Test Migration + Old Code Removal

### Goal

Update all remaining tests to work with the unified editor. Remove old hooks, components, and dead code that are no longer used.

### Why this provides value on its own

- Clean codebase with no dead code
- Test suite reflects the actual architecture
- Reduced bundle size (fewer JS files)

### Files to delete

- `assets/js/hooks/screenplay_element.js`
- `assets/js/hooks/screenplay_tiptap_element.js`
- `assets/js/hooks/screenplay_editor_page.js`
- `assets/js/hooks/slash_command.js`
- `assets/js/screenplay/constants.js`
- `lib/storyarn_web/components/screenplay/slash_command_menu.ex`

### Files to modify

- `assets/js/app.js` — Remove old hook imports and registrations
- `assets/css/screenplay.css` — Remove dead CSS for old wrapper elements
- `test/storyarn_web/live/screenplay_live/show_test.exs` — Update any remaining tests

### Files to keep (still used)

- `lib/storyarn_web/components/screenplay/element_renderer.ex` — Keep for now (used by interactive blocks in Phase 2). Mark with `@moduledoc` that it will be removed in Phase 2.
- `assets/js/screenplay/character_sheet_picker.js` — Keep until Phase 3 (character sheet integration in TipTap)

### Specification

**app.js cleanup:**
```javascript
// Remove:
import { ScreenplayElement } from "./hooks/screenplay_element";
import { ScreenplayTiptapElement } from "./hooks/screenplay_tiptap_element";
import { ScreenplayEditorPage } from "./hooks/screenplay_editor_page";
import { SlashCommand } from "./hooks/slash_command";

// Keep:
import { ScreenplayEditor } from "./hooks/screenplay_editor";
```

**CSS cleanup:**
- Remove `.screenplay-element` wrapper styles that no longer apply
- Remove `.sp-tiptap-container` styles
- Remove `.sp-block` styles for the old contenteditable approach
- Keep `.sp-<type>` styles (now applied by TipTap nodes directly)
- Keep `.sp-page_break` styles
- Keep `.screenplay-page` container styles

### Tests

1. **Build**: `npm run build` succeeds (no dangling imports)
2. **Elixir**: `mix test` — all tests pass
3. **Credo**: `mix credo --strict` — no issues
4. **Compile**: `mix compile --warnings-as-errors` — no warnings

### Acceptance criteria

- [ ] All deleted files are gone
- [ ] No dangling imports in any JS file
- [ ] No references to old hook names in Elixir templates
- [ ] `npm run build` succeeds
- [ ] `mix compile --warnings-as-errors` succeeds
- [ ] `mix credo --strict` clean
- [ ] `mix test` — all tests pass
- [ ] Bundle size reduced (fewer hooks loaded)

---

## Execution Protocol

For each task:

1. **Implement** the changes described above
2. **Run verification:**
   ```bash
   mix compile --warnings-as-errors
   mix credo --strict
   mix test
   ```
3. **Report results** to the user
4. **Wait for approval** before starting the next task

---

## Post-Phase 1 State

After all 10 tasks are complete, the editor will:

- Use a single TipTap instance for all text-based elements
- Support Enter, Tab, Backspace keyboard shortcuts natively
- Show per-type placeholders in empty blocks
- Have a client-side slash command menu (no server round-trip)
- Sync document state to the server via a single debounced event
- Allow cursor navigation between all text blocks
- Allow keyboard deletion of page breaks
- Maintain all existing interactive block functionality (condition, instruction, response)

**What's NOT yet done** (Phase 2+):
- Interactive blocks as TipTap NodeViews (still server-rendered)
- Auto-detect InputRules
- Character sheet picker within TipTap
- CONT'D decorations
- Read mode within TipTap
- Rich text round-trip serialization (bold, italic, mentions)
