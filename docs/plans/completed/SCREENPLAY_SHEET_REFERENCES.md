# Sheet References in Screenplay Editor

## Context

The screenplay editor stores character names as plain text (`content: "JOHN"`) with no link to sheets. When syncing screenplay -> flow, `speaker_sheet_id` is always `nil`. Inline mentions in dialogue/action text are also impossible because elements use plain `contenteditable` divs instead of TipTap.

**Goal:** Characters reference sheets via `#` autocomplete. Text elements (dialogue, action, scene heading, etc.) support inline `#` mentions to reference any sheet. Navigation icons let users jump to referenced sheets.

## Phase 1: Character Sheet Reference

### 1.1 Data Model (no migration needed)

The `data` JSONB column already exists on `screenplay_elements`. For sheet-referenced characters:

```elixir
%ScreenplayElement{type: "character", content: "DETECTIVE", data: %{"sheet_id" => 42}}
```

Plain text characters keep `data: %{}` or `nil` (backward compatible).

### 1.2 Server — show.ex

**Mount changes:**
- Load `all_sheets = Sheets.list_all_sheets(project.id)` (reuse existing function)
- Build `sheets_map = Map.new(all_sheets, &{&1.id, &1})`
- Assign both to socket

**New event handlers:**
- `search_character_sheets` — calls `Sheets.search_referenceable(project_id, query, ["sheet"])`, pushes `character_sheet_results` event
- `set_character_sheet` — stores `sheet_id` in `element.data`, sets `content` to uppercased sheet name
- `clear_character_sheet` — removes `sheet_id` from `element.data`
- `navigate_to_sheet` — `push_navigate` to the sheet page

**Guard in `build_update_attrs`:** Skip auto-detection for sheet-referenced characters (content comes from sheet, not user typing).

**Files:** `lib/storyarn_web/live/screenplay_live/show.ex`

### 1.3 Element Renderer — character with sheet_id

Add new `render_block` clause matching `%{type: "character", data: %{"sheet_id" => sheet_id}}`:
- Display: `SHEET_NAME` (uppercased) + external-link icon to navigate to sheet + X to clear reference
- Non-editable content (name comes from sheet), but still `phx-hook="ScreenplayElement"` for keyboard events (Enter, Backspace, Tab)
- Add `sheets_map` attr to `element_renderer` component

**Files:** `lib/storyarn_web/components/screenplay/element_renderer.ex`

### 1.4 JS — Character Sheet Picker

**New module:** `assets/js/screenplay/character_sheet_picker.js`
- Creates floating dropdown popup (positioned below element, similar to slash command menu)
- Text input for search query (debounced 300ms)
- Pushes `search_character_sheets` to server, receives `character_sheet_results`
- Arrow key navigation, Enter to select, Escape to dismiss
- On selection: pushes `set_character_sheet` with `{id, sheet_id, name}`

**Modify:** `assets/js/hooks/screenplay_element.js`
- In `handleKeyDown`: when `event.key === "#"` AND `this.elementType === "character"`, prevent default and open the character picker
- Import and delegate to `character_sheet_picker.js`
- Listen for `character_sheet_results` via `handleEvent`

**Reuse existing patterns:** Popup structure from `slash_command.js`, search from `tiptap/mention_extension.js`

### 1.5 CharacterExtension

Add `base_name_from_element(element, sheets_map)`:
- If `element.data["sheet_id"]` exists: lookup name from sheets_map, uppercase it
- Otherwise: delegate to existing `base_name(element.content)`

**Files:** `lib/storyarn/screenplays/character_extension.ex`

### 1.6 ElementGrouping — CONT'D

Change `compute_continuations(elements)` → `compute_continuations(elements, sheets_map \\ %{})`:
- Use `CharacterExtension.base_name_from_element/2` instead of `base_name(content)`
- Update caller in `show.ex` `assign_elements_with_continuations/2` to pass sheets_map

**Files:** `lib/storyarn/screenplays/element_grouping.ex`

### 1.7 Flow Sync — Bidirectional

**Screenplay -> Flow** (`node_mapping.ex`):
- In `map_dialogue_group`: extract `sheet_id` from character element's data, set `"speaker_sheet_id" => sheet_id`

**Flow -> Screenplay** (`reverse_node_mapping.ex`):
- In `build_dialogue_elements`: read `speaker_sheet_id` from node data, store as `%{"sheet_id" => speaker_sheet_id}` in character element's data

**Files:** `lib/storyarn/screenplays/node_mapping.ex`, `lib/storyarn/screenplays/reverse_node_mapping.ex`

### 1.8 CSS

Add to `screenplay.css`:
- `.sp-character-ref` — inline-flex container for referenced character display
- `.sp-character-nav` / `.sp-character-clear` — small icon buttons (reuse `.sp-choice-toggle` pattern)
- `.sp-character-picker` — floating dropdown (reuse `.slash-menu` pattern)

**Files:** `assets/css/screenplay.css`

---

## Phase 2: TipTap for Text Elements (inline mentions)

### 2.1 ContentUtils Module (new)

**New file:** `lib/storyarn/screenplays/content_utils.ex`
- `strip_html(content)` — removes HTML tags, decodes entities -> plain text
- `html?(content)` — detects if content contains HTML
- `plain_to_html(text)` — wraps plain text in `<p>` for TipTap

### 2.2 Auto-Detection + CharacterExtension

- `AutoDetect.detect_type/1`: call `ContentUtils.strip_html` before pattern matching
- `CharacterExtension.parse/1` + `base_name/1`: strip HTML before regex

**Files:** `lib/storyarn/screenplays/auto_detect.ex`, `lib/storyarn/screenplays/character_extension.ex`

### 2.3 New JS Hook: ScreenplayTiptapElement

**New file:** `assets/js/hooks/screenplay_tiptap_element.js`
- Initializes TipTap editor with `StarterKit` (minimal: no headings/lists/code) + `createMentionExtension(this)`
- Reuses existing `assets/js/tiptap/mention_extension.js` (trigger `#`, sheet search popup)
- Keyboard handling via `handleKeyDown` in `editorProps`:
  - `Enter` (no Shift) -> prevent, push `create_next_element`
  - `Backspace` on empty -> prevent, push `delete_element`
  - `Tab` -> prevent, push `change_element_type`
  - `/` on empty -> prevent, push `open_slash_menu`
- Content save: `onUpdate` -> debounced 500ms -> push `update_element_content` with `editor.getHTML()`
- Exposes `el.__storyarnFocus = () => editor.commands.focus('end')` for page-level focus management
- Listens for `mention_suggestions_result` server event

**Register in:** `assets/js/app.js`

### 2.4 Element Renderer — TipTap Types

Define `@tiptap_types ~w(dialogue action scene_heading parenthetical transition note section)`.

**Hook switching** in `element_renderer/1`:
- `type in @tiptap_types` AND editable -> `phx-hook="ScreenplayTiptapElement"`
- `type == "character"` AND editable -> `phx-hook="ScreenplayElement"` (keeps Phase 1 behavior)

**Editable TipTap render_block:** render a `.sp-tiptap-container` div with `data-content`, `data-can-edit`, `data-placeholder`. TipTap hook initializes inside.

**Read-only render_block:** render `{raw(@element.content)}` for HTML content, fallback to plain text.

**Files:** `lib/storyarn_web/components/screenplay/element_renderer.ex`

### 2.5 Server — Mention Suggestions

Add `mention_suggestions` event handler in `show.ex`:
- Calls `Sheets.search_referenceable(project_id, query, ["sheet"])`
- Pushes `mention_suggestions_result` with items list

**Files:** `lib/storyarn_web/live/screenplay_live/show.ex`

### 2.6 ScreenplayEditorPage — Focus with TipTap

Update `focus_element` handler:
- Check for `el.__storyarnFocus` (set by TipTap hook) -> call it
- Fallback to existing contenteditable focus logic

**Files:** `assets/js/hooks/screenplay_editor_page.js`

### 2.7 Flow Sync with HTML Content

**Screenplay -> Flow** (`node_mapping.ex`):
- `dialogue.content` (HTML) -> `"text"` field (the flow editor already uses TipTap for this field)
- `parenthetical.content` -> strip HTML -> `"stage_directions"` (flow stores as plain text)
- `character.content` -> strip HTML -> `"menu_text"` (flow stores as plain text)

**Element splitting** (`element_crud.ex`): Strip HTML before splitting by cursor position.

**Files:** `lib/storyarn/screenplays/node_mapping.ex`, `lib/storyarn/screenplays/element_crud.ex`

### 2.8 CSS — TipTap in Screenplay

Add to `screenplay.css`:
- `.sp-tiptap-container .ProseMirror` — no outline, `white-space: pre-wrap`, margin 0 on `p`
- `.sp-tiptap-container .mention` — inline chip style with primary color bg (reuse existing mention styles)
- `.sp-empty .sp-tiptap-container .ProseMirror::before` — placeholder via CSS

**Files:** `assets/css/screenplay.css`

---

## Implementation Order

### Phase 1 (character sheet reference):
1. `show.ex` — add `all_sheets`/`sheets_map` assigns, new event handlers
2. `character_extension.ex` — add `base_name_from_element/2`
3. `element_grouping.ex` — accept `sheets_map` param
4. `element_renderer.ex` — add `sheets_map` attr, character sheet render clause
5. `screenplay_element.js` — add `#` key detection for character type
6. `character_sheet_picker.js` — new module for search dropdown
7. `node_mapping.ex` — propagate `sheet_id` -> `speaker_sheet_id`
8. `reverse_node_mapping.ex` — propagate `speaker_sheet_id` -> `sheet_id`
9. `screenplay.css` — character reference + picker styles
10. Tests

### Phase 2 (TipTap + inline mentions):
1. `content_utils.ex` — new HTML stripping module
2. `auto_detect.ex` + `character_extension.ex` — strip HTML before matching
3. `screenplay_tiptap_element.js` — new hook
4. `app.js` — register new hook
5. `element_renderer.ex` — switch hook per type, TipTap render clause
6. `show.ex` — add `mention_suggestions` handler, update `build_update_attrs` for HTML
7. `screenplay_editor_page.js` — TipTap focus support
8. `node_mapping.ex` — strip HTML for plain-text sync fields
9. `element_crud.ex` — HTML-safe element splitting
10. `screenplay.css` — TipTap + mention chip styles
11. Tests

## Verification

1. **Phase 1:** Create a character element -> type `#` -> search for a sheet -> select -> verify name displays uppercased with link icon -> click icon navigates to sheet -> sync to flow -> verify `speaker_sheet_id` is set -> sync from flow back -> verify `sheet_id` is preserved
2. **Phase 2:** Create a dialogue element -> type `#` in text -> verify autocomplete popup -> select sheet -> verify mention chip renders -> sync to flow -> verify HTML passes through to `text` field -> press Enter/Backspace/Tab -> verify keyboard events work as before
3. **Backward compat:** Open existing screenplay with plain text elements -> verify they render and edit normally
