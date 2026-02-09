# Phase 3 — Screenplay Editor (Core Blocks)

> **Parent plan:** [SCREENPLAY_TOOL.md](./SCREENPLAY_TOOL.md)
>
> **Note:** Collaboration (Edge Case H — presence + element locking) is **deferred** from Phase 3 to a dedicated Phase 3.5. The editor includes `data-element-id` attributes on all elements to make locking easy to retrofit.

| Task | Name                                                              | Status  | Tests  |
|------|-------------------------------------------------------------------|---------|--------|
| 3.1  | Hook rename + Show LiveView: load elements + editor layout + CSS  | Done    | 4      |
| 3.2  | Element renderer + per-type block components + CSS                | Done    | 3      |
| 3.3  | Contenteditable + ScreenplayElement hook + debounced save         | Done    | 3      |
| 3.4  | Enter key: create next element + type inference                   | Done    | 4      |
| 3.5  | Backspace (delete empty), Tab (cycle type), Arrow navigation      | Done    | 4      |
| 3.6  | Auto-detection + editor toolbar + screenplay name editing         | Done    | 24     |

---

## Task 3.1 — Hook Rename + Show LiveView: Load Elements + Editor Layout + Base CSS

**Goal:** Rename the existing `ScreenplayEditor` hook (used by dialogue fullscreen editor) to `DialogueScreenplayEditor` to free the name. Then enhance `ScreenplayLive.Show` to load screenplay elements and render the editor page container with base CSS.

**Files:**
- `assets/js/hooks/screenplay_editor.js` → rename to `dialogue_screenplay_editor.js`
- `assets/js/app.js` (update import + hook key)
- `lib/storyarn_web/live/flow_live/components/screenplay_editor.ex` (update `phx-hook` reference)
- `lib/storyarn_web/live/screenplay_live/show.ex` (enhance mount + render)
- `assets/css/screenplay.css` (create — page container + dark mode CSS)
- `assets/css/app.css` (import screenplay.css)
- `test/storyarn_web/live/screenplay_live/show_test.exs` (add tests)

**Details — Hook rename:**
- Rename file: `screenplay_editor.js` → `dialogue_screenplay_editor.js`
- Change export name: `ScreenplayEditor` → `DialogueScreenplayEditor`
- In `app.js`: update import path and hook registration key
- In `flow_live/components/screenplay_editor.ex`: change `phx-hook="ScreenplayEditor"` → `"DialogueScreenplayEditor"`

**Details — Show LiveView mount:**
- Add `elements = Screenplays.list_elements(screenplay.id)` to mount
- Add assigns: `:elements`, `:focused_element_id` (nil)
- Keep existing sidebar event handlers (from Phase 2)

**Details — Show LiveView render:**
- Replace current header-only content with screenplay page container
- `div.screenplay-page` with `id="screenplay-page"` wrapping element list
- Each element: `<div class={"screenplay-element sp-#{element.type}"} id={"sp-el-#{element.id}"}>{element.content}</div>`
- Empty state: `gettext("Start typing or press / for commands")`
- No contenteditable yet (Task 3.3), no hooks on elements yet

**Details — CSS (`assets/css/screenplay.css`):**
- `.screenplay-page` — 816px max-width, monospace font, 12pt, single-spaced, white bg with shadow
- Dark mode inversion via `[data-theme="dark"]`
- Page padding: top/right/bottom 96px, left 144px (industry standard margins)

**Tests:**
1. Mounts and renders screenplay page container
2. Renders element content when elements exist
3. Shows empty state when no elements
4. Elements have correct type CSS class (`sp-scene_heading`, etc.)
5. Hook rename doesn't break existing flow tests

---

## Task 3.2 — Element Renderer + Per-Type Block Components + CSS

**Goal:** Create the `element_renderer` dispatch component and per-type block components with industry-standard screenplay CSS formatting.

**Files:**
- `lib/storyarn_web/components/screenplay/element_renderer.ex` (create)
- `assets/css/screenplay.css` (add per-type CSS)
- `lib/storyarn_web/live/screenplay_live/show.ex` (use element_renderer)
- `test/storyarn_web/live/screenplay_live/show_test.exs` (add tests)

**Details — Element Renderer:**
- `element_renderer/1` function component with attrs: `element`, `focused`, `can_edit`, `all_sheets`, `project_variables`
- Wrapping div: `id="sp-el-#{element.id}"`, `class="screenplay-element sp-#{element.type}"`, `data-element-id`, `data-element-type`, `data-position`
- Case dispatch to per-type block functions based on `element.type`

**Details — Standard block components (in same module):**
Each renders a div with the element's content and correct CSS class + `data-placeholder`:
- `scene_heading_block/1` — placeholder: `"INT. LOCATION - TIME"`
- `action_block/1` — placeholder: `"Describe the action..."`
- `character_block/1` — placeholder: `"CHARACTER NAME"`
- `dialogue_block/1` — placeholder: `"Dialogue text..."`
- `parenthetical_block/1` — placeholder: `"(acting direction)"`
- `transition_block/1` — placeholder: `"CUT TO:"`
- `note_block/1` — sans-serif, yellow bg, left border
- `section_block/1` — outline header
- `page_break_block/1` — dashed line separator

Interactive blocks (`conditional`, `instruction`, `response`, `dual_dialogue`, `hub_marker`, `jump_marker`, `title_page`) render as **stubs** with a type label badge — full implementation in Phase 5.

**Details — Per-type CSS (added to `screenplay.css`):**
- `.sp-scene-heading` — uppercase, bold, margin-top 24px, margin-bottom 12px
- `.sp-action` — full width, margin 12px
- `.sp-character` — uppercase, margin-left 192px
- `.sp-parenthetical` — margin-left 144px, max-width 192px
- `.sp-dialogue` — margin-left 96px, max-width 288px
- `.sp-transition` — right-aligned, uppercase
- `.sp-note` — sans-serif, yellow/amber bg, left border
- `.sp-section` — sans-serif, bold, colored border-bottom
- `.sp-page-break` — dashed border, centered label
- `.sp-focused` — highlight ring for focused element
- `.sp-empty::before` — placeholder via CSS `content: attr(data-placeholder)`, muted color

**Tests:**
1. Element renderer renders correct HTML structure with data attributes
2. Scene heading element has uppercase CSS class
3. Interactive blocks render as stubs with type label
4. Page break renders as visual separator

---

## Task 3.3 — Contenteditable + ScreenplayElement Hook + Debounced Save

**Goal:** Make standard elements editable with a JS hook that debounces content saves to the server.

**Files:**
- `assets/js/hooks/screenplay_element.js` (create)
- `assets/js/app.js` (register hook)
- `lib/storyarn_web/components/screenplay/element_renderer.ex` (add contenteditable + hook)
- `lib/storyarn_web/live/screenplay_live/show.ex` (add `update_element_content` handler + helpers)
- `test/storyarn_web/live/screenplay_live/show_test.exs` (add tests)

**Details — ScreenplayElement hook (`assets/js/hooks/screenplay_element.js`):**
- `mounted()`: read `elementId` and `elementType` from dataset, set up input listener with 500ms debounce, update placeholder
- On input: toggle `sp-empty` class, debounce `pushEvent("update_element_content", { id, content })`
- `updatePlaceholder()`: add/remove `sp-empty` class based on `textContent.trim()`
- `destroyed()`: clear debounce timer

**Details — Element renderer updates:**
- Standard blocks: `contenteditable={to_string(@can_edit)}`, `phx-hook="ScreenplayElement"`, `id="sp-edit-#{element.id}"`, `phx-update="ignore"`
- Interactive/utility blocks: NOT contenteditable (they have their own UI)

**Details — LiveView handler:**
- `handle_event("update_element_content", %{"id" => id, "content" => content}, socket)` — authorize, find element, update via `Screenplays.update_element/2`, update in-memory list
- Private helper: `find_element/2` — finds element by id in `socket.assigns.elements`
- Private helper: `update_element_in_list/2` — replaces element in assigns list by id

**Note:** Need to verify `Screenplays` facade has a `get_element!/2` or add one. `ElementCrud` already has `update_element/2`.

**Tests:**
1. `update_element_content` event persists content change to database
2. Unauthorized user cannot update element content (viewer role)
3. Elements render as contenteditable when user has edit permission

---

## Task 3.4 — Enter Key: Create Next Element + Type Inference

**Goal:** Pressing Enter creates the next logical element type after the current one and focuses it.

**Files:**
- `assets/js/hooks/screenplay_element.js` (add keydown handler for Enter)
- `assets/js/hooks/screenplay_editor.js` (create — page-level orchestrator for focus management)
- `assets/js/app.js` (register `ScreenplayEditor` hook)
- `lib/storyarn_web/live/screenplay_live/show.ex` (add `create_next_element` handler + page hook)
- `test/storyarn_web/live/screenplay_live/show_test.exs` (add tests)

**Details — Type inference (JS, in ScreenplayElement hook):**
```
scene_heading → action
action → action
character → dialogue
parenthetical → dialogue
dialogue → action
transition → scene_heading
default → action
```

**Details — ScreenplayElement keydown (Enter):**
- Enter (no shift): flush pending debounce, then `pushEvent("create_next_element", { after_id, type: inferredType, content: "" })`
- Shift+Enter: default behavior (line break within element)

**Details — ScreenplayEditor hook (new `assets/js/hooks/screenplay_editor.js`):**
- Attached to `.screenplay-page` container
- `handleEvent("focus_element", { id })` → `requestAnimationFrame` → focus `sp-edit-${id}` + place cursor at end

**Details — LiveView handler:**
- `handle_event("create_next_element", params, socket)` — authorize, find element by `after_id`, call `Screenplays.insert_element_at/3` at `position + 1`, reload elements, `push_event("focus_element", %{id: new_id})`

**Tests:**
1. `create_next_element` creates element at correct position (after the specified element)
2. `create_next_element` after scene_heading creates action type
3. `create_next_element` after character creates dialogue type
4. Unauthorized user cannot create elements

---

## Task 3.5 — Backspace (Delete Empty), Tab (Cycle Type), Arrow Navigation

**Goal:** Complete keyboard interaction for fluid screenplay writing.

**Files:**
- `assets/js/hooks/screenplay_element.js` (add Backspace + Tab keydown handlers)
- `assets/js/hooks/screenplay_editor.js` (add ArrowUp/ArrowDown navigation)
- `lib/storyarn_web/live/screenplay_live/show.ex` (add `delete_element` + `change_element_type` handlers)
- `test/storyarn_web/live/screenplay_live/show_test.exs` (add tests)

**Details — Backspace (ScreenplayElement hook):**
- If `textContent === ""` and cursor at position 0: `preventDefault()`, `pushEvent("delete_element", { id })`
- Otherwise: default browser backspace

**Details — Tab (ScreenplayElement hook):**
- Tab: cycle to next standard type in order `["action", "scene_heading", "character", "dialogue", "parenthetical", "transition"]`
- Shift+Tab: cycle to previous type
- `pushEvent("change_element_type", { id, type })`

**Details — Arrow keys (ScreenplayEditor hook):**
- ArrowUp at first line of element: `preventDefault()`, focus previous `[contenteditable]` element
- ArrowDown at last line: `preventDefault()`, focus next `[contenteditable]` element
- Detection via `window.getSelection()` offset checks

**Details — LiveView handlers:**
- `handle_event("delete_element", %{"id" => id}, socket)` — authorize, find element + previous element, `Screenplays.delete_element/1`, reload elements, push focus to previous element (or no-op if last element)
- `handle_event("change_element_type", %{"id" => id, "type" => type}, socket)` — authorize, find element, `Screenplays.update_element(element, %{type: type})`, update in-memory list

**Tests:**
1. `delete_element` removes element and compacts positions
2. `delete_element` of the last remaining element keeps at least one empty element (or handles gracefully)
3. `change_element_type` changes type while preserving content
4. Unauthorized user cannot delete elements

---

## Task 3.6 — Auto-Detection + Editor Toolbar + Screenplay Name Editing

**Goal:** Auto-detect element type from text patterns and add the editor toolbar with editable screenplay name.

**Files:**
- `lib/storyarn/screenplays/auto_detect.ex` (create)
- `lib/storyarn/screenplays.ex` (add delegate)
- `lib/storyarn_web/live/screenplay_live/show.ex` (add toolbar render + `save_name`/`auto_detect` handlers)
- `test/storyarn/screenplays/auto_detect_test.exs` (create — unit tests)
- `test/storyarn_web/live/screenplay_live/show_test.exs` (add tests)

**Details — Auto-detect module (`lib/storyarn/screenplays/auto_detect.ex`):**
```elixir
def detect_type(content) do
  trimmed = String.trim(content)
  cond do
    trimmed =~ ~r/^(INT\.|EXT\.|INT\.\/EXT\.|I\/E\.?)\s/i -> "scene_heading"
    trimmed =~ ~r/^[A-Z\s]+TO:$/ -> "transition"
    trimmed in ["FADE IN:", "FADE OUT.", "FADE TO BLACK."] -> "transition"
    trimmed =~ ~r/^[A-Z][A-Z\s\.']+(\s*\([\w\.]+\))?$/ and String.length(trimmed) < 50 -> "character"
    trimmed =~ ~r/^\(.*\)$/ -> "parenthetical"
    true -> nil  # nil = no auto-detection, keep current type
  end
end
```

**Details — Toolbar (rendered in show.ex):**
- Screenplay name: editable title (uses `EditableTitle` hook pattern from flow editor)
- Element count badge
- Draft status indicator
- Link status placeholder (for Phase 6-7)

**Details — LiveView handlers:**
- `handle_event("save_name", %{"value" => name}, socket)` — authorize, `Screenplays.update_screenplay/2`, reload screenplays_tree
- `handle_event("auto_detect_type", %{"id" => id, "content" => content}, socket)` — call `AutoDetect.detect_type/1`, if non-nil and different from current type, update element type

**Tests (auto_detect_test.exs):**
1. `"INT. LIVING ROOM - DAY"` → `"scene_heading"`
2. `"EXT. PARK - NIGHT"` → `"scene_heading"`
3. `"CUT TO:"` → `"transition"`
4. `"JOHN"` → `"character"`
5. `"(whispering)"` → `"parenthetical"`
6. `"He walks away."` → `nil` (no change)

**Tests (show_test.exs):**
1. Toolbar renders screenplay name
2. `save_name` event updates screenplay name and refreshes tree
3. `auto_detect_type` changes element type when pattern matches
4. `auto_detect_type` does nothing when no pattern matches
