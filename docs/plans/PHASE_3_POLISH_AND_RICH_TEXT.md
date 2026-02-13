# Phase 3 — Polish and Rich Text

## Context

Phases 1-2 delivered a unified TipTap editor where all 16 element types live as nodes in a single ProseMirror document. Text editing, keyboard navigation, slash commands, and interactive NodeViews all work. However, several quality gaps remain:

1. **Rich text marks are silently dropped** — Bold, italic, strike, and hard breaks typed in TipTap are lost on save because the serialization layer only handles plain text + mentions.
2. **No client-side auto-detect** — `AutoDetect` exists server-side but is never called. Typing "INT. OFFICE" doesn't auto-convert to scene heading.
3. **CONT'D only visible in read mode** — The server computes character continuations for read mode, but the edit-mode TipTap editor shows no CONT'D badge.
4. **Transition left-align only in read mode** — Transitions ending in "IN:" (e.g. "FADE IN:") should be left-aligned, but only the read-mode renderer applies this.

---

## Task 1: Rich Text Mark + Hard Break Round-Trip Serialization

**Goal:** Bold, italic, strikethrough, and hard breaks (Shift+Enter) survive the save round-trip. Currently these are silently dropped — this is data loss.

### Problem

TipTap represents marks on text nodes:
```json
{"type": "text", "text": "bold word", "marks": [{"type": "bold"}]}
```
Hard breaks are inline nodes:
```json
{"type": "hardBreak"}
```

Neither the JS serialization (`serialization.js`) nor the Elixir serialization (`tiptap_serialization.ex`) handles these. Plain text content like `"Hello"` stays intact, but `"**Hello**"` becomes `"Hello"` after a round-trip.

### Changes

**`lib/storyarn/screenplays/tiptap_serialization.ex`:**

`inline_content_to_html/1` — extend to handle marks and hard breaks:
- Text nodes with `marks` → wrap in `<strong>`, `<em>`, `<s>` tags (nested, outermost first)
- Hard break nodes → `<br>`
- This triggers on any content that has marks or hardBreak, not just mentions

`html_to_inline_content/1` — extend to parse mark tags and `<br>`:
- Currently only checks for `<span class="mention">`. Extend Floki tree parsing to handle `<strong>`, `<em>`, `<s>`, `<br>`, `<b>`, `<i>` tags
- `<strong>` / `<b>` → bold mark
- `<em>` / `<i>` → italic mark
- `<s>` / `<del>` → strike mark
- `<br>` → hardBreak node
- Nested marks: `<strong><em>text</em></strong>` → `marks: [bold, italic]`

**`assets/js/screenplay/serialization.js`:**

`getNodeText()` — extend to serialize marks and hard breaks:
- Text nodes with `marks` → wrap in `<strong>`, `<em>`, `<s>` tags
- `hardBreak` nodes → `<br>`
- Detection flag: check for marks OR hardBreak (not just mentions)

`htmlToInlineContent()` — extend to parse mark tags and `<br>`:
- Walk DOM tree recursively to accumulate marks from parent elements
- `<strong>` / `<b>` → push bold mark, recurse children
- `<em>` / `<i>` → push italic mark, recurse children
- `<s>` / `<del>` → push strike mark, recurse children
- `<br>` → hardBreak node
- Text nodes → text node with accumulated marks array

### Tests

**`test/storyarn/screenplays/tiptap_serialization_test.exs`:**
- `elements_to_doc` with `<strong>Hello</strong>` content → produces text node with bold mark
- `elements_to_doc` with `<em>Hello</em>` → italic mark
- `elements_to_doc` with `<s>Hello</s>` → strike mark
- `elements_to_doc` with nested `<strong><em>Hello</em></strong>` → both marks
- `elements_to_doc` with `Line one<br>Line two` → text + hardBreak + text
- `doc_to_element_attrs` with marks → produces correct HTML tags
- `doc_to_element_attrs` with hardBreak → produces `<br>`
- Round-trip: bold text → doc → attrs → verify `<strong>` preserved
- Round-trip: mixed bold + mention → verify both survive
- Round-trip: hard break → verify `<br>` preserved

### Files
- Modify: `lib/storyarn/screenplays/tiptap_serialization.ex`
- Modify: `assets/js/screenplay/serialization.js`
- Modify: `test/storyarn/screenplays/tiptap_serialization_test.exs`

### Verification
```bash
mix credo --strict && mix test
```
Manual: type bold text (Cmd+B), save, reload — bold preserved.

---

## Task 2: Auto-Detect InputRules Extension

**Goal:** Typing screenplay patterns instantly converts the block type — no server round-trip. "INT. " at the start of a block converts it to scene heading immediately.

### Problem

`AutoDetect` exists server-side (`auto_detect.ex`) but is never called. The old per-element editing flow used it; the unified TipTap editor does not. Users must manually Tab-cycle or use the slash menu to set block types.

### Approach

Create a TipTap extension with ProseMirror InputRules that fire on specific text patterns. InputRules match regex at the cursor position and transform the document. This gives instant visual feedback as the user types.

### Changes

**New: `assets/js/screenplay/extensions/auto_detect_rules.js`**

InputRules for:
- `^(INT\.|EXT\.|INT\./EXT\.|I/E\.|EST\.)\s` → convert block to `sceneHeading`
  - Only fires when current block is `action` (default type)
  - Keeps the typed text (the prefix is part of the scene heading content)
- `^(CUT TO:|FADE IN:|FADE OUT\.|FADE TO BLACK\.|INTERCUT:|SMASH CUT TO:|MATCH CUT TO:|JUMP CUT TO:)$` or `^[A-Z\s]+TO:$` → convert to `transition`
  - Only when current block is `action`
- `^\(.*\)$` → convert to `parenthetical`
  - Only when current block is `dialogue` (parentheticals appear inside dialogue groups)

Character ALL CAPS detection is intentionally omitted — it's too aggressive as an InputRule (would fire on any caps text). Users use Tab or the slash menu for character blocks.

**`assets/js/hooks/screenplay_editor.js`:**
- Import and register `AutoDetectRules`

### Tests

**`test/storyarn_web/live/screenplay_live/show_test.exs`:**
- Test: sync_editor_content with a scene_heading element containing "INT. OFFICE - DAY" persists correctly (validates server accepts auto-detected types)

**Existing `test/storyarn/screenplays/auto_detect_test.exs`:**
- Already covers the detection patterns — no changes needed

### Files
- Create: `assets/js/screenplay/extensions/auto_detect_rules.js`
- Modify: `assets/js/hooks/screenplay_editor.js`
- Modify: `test/storyarn_web/live/screenplay_live/show_test.exs`

### Verification
```bash
mix credo --strict && mix test
```
Manual: in an empty action block, type "INT. " → block converts to scene heading instantly.

---

## Task 3: CONT'D Decoration Plugin for Edit Mode

**Goal:** Character continuation badges `(CONT'D)` appear in the TipTap editor while writing, not just in read mode.

### Problem

`ElementGrouping.compute_continuations/2` computes which characters should display (CONT'D) by scanning element adjacency. This data is passed to `element_renderer.ex` for read mode. But the TipTap editor (edit mode) shows no CONT'D badge — the user can't see if a character name will get the continuation label.

### Approach

Create a ProseMirror plugin that:
1. On every doc change, traverses the document looking for character nodes
2. Computes which characters repeat after non-scene-breaking elements (same algorithm as `element_grouping.ex`)
3. Adds widget Decorations after matching character nodes that display "(CONT'D)"

This is a read-only visual decoration — not editable text. It uses ProseMirror's `DecorationSet` with widget decorations appended after the character node's content.

### Changes

**New: `assets/js/screenplay/extensions/contd_plugin.js`**
- Export a TipTap Extension wrapping a ProseMirror Plugin
- Plugin state: `DecorationSet` recomputed on `docChanged`
- `computeContdDecorations(doc)`:
  - Iterate doc children, track `lastSpeaker`
  - Scene breakers (sceneHeading, transition, conditional, instruction, response, dualDialogue, hubMarker, jumpMarker) reset `lastSpeaker`
  - Character nodes: extract base name (text content, uppercase, strip extensions like "(V.O.)")
  - If base name matches `lastSpeaker` → add widget decoration after the character node
  - Update `lastSpeaker` for every character node
- Widget decoration: `<span class="sp-contd">(CONT'D)</span>` — uses existing CSS

**`assets/js/hooks/screenplay_editor.js`:**
- Import and register `ContdPlugin`

### Tests

**`test/storyarn_web/live/screenplay_live/show_test.exs`:**
- Existing CONT'D tests cover server-side computation and read-mode rendering — no changes needed
- The client-side plugin replicates the same logic; verification is manual

### Files
- Create: `assets/js/screenplay/extensions/contd_plugin.js`
- Modify: `assets/js/hooks/screenplay_editor.js`

### Verification
```bash
mix credo --strict && mix test
```
Manual: create CHARACTER → DIALOGUE → CHARACTER (same name) → second character shows (CONT'D). Insert a scene heading between them → (CONT'D) disappears.

---

## Task 4: Transition Left-Align in Edit Mode

**Goal:** Transitions ending in "IN:" (e.g. "FADE IN:") are left-aligned in the TipTap editor, matching their read-mode appearance.

### Problem

`.sp-transition` is right-aligned by default. Transitions like "FADE IN:" should be left-aligned (industry convention). The read-mode renderer applies `.sp-transition-left` conditionally, but the TipTap editor always renders transitions right-aligned because the CSS class is static in `renderHTML()`.

### Approach

Create a ProseMirror plugin that adds/removes `.sp-transition-left` as a node decoration on transition blocks based on their text content. This is lighter than a widget — just a class toggle.

### Changes

**New: `assets/js/screenplay/extensions/transition_align_plugin.js`**
- Export a TipTap Extension wrapping a ProseMirror Plugin
- Plugin state: `DecorationSet` recomputed on `docChanged`
- `computeTransitionDecorations(doc)`:
  - For each transition node: check if text content (trimmed, uppercased) ends with "IN:"
  - If yes → add a node decoration with `class: "sp-transition-left"` at that node's position
- The existing `.sp-transition-left { text-align: left }` CSS already handles the visual

**`assets/js/hooks/screenplay_editor.js`:**
- Import and register `TransitionAlignPlugin`

### Tests

**No new Elixir tests needed** — the CSS class and logic are unchanged. Read-mode behavior stays the same.

### Files
- Create: `assets/js/screenplay/extensions/transition_align_plugin.js`
- Modify: `assets/js/hooks/screenplay_editor.js`

### Verification
```bash
mix credo --strict && mix test
```
Manual: type "FADE IN:" in a transition block → aligns left. Change to "CUT TO:" → aligns right.

---

## Dependency Graph

```
Task 1 (Rich text serialization)  ←  independent, highest priority (fixes data loss)
Task 2 (Auto-detect InputRules)   ←  independent
Task 3 (CONT'D decoration)        ←  independent
Task 4 (Transition left-align)    ←  independent
```

All tasks are independent. Recommended order is 1 → 2 → 3 → 4 (priority: data loss fix first, then UX polish).

---

## What's Already Done (no Phase 3 work needed)

| Feature | Status | Notes |
|---------|--------|-------|
| Mention inline serialization | Done | Both JS and Elixir handle `<span class="mention">` |
| Character sheet picker | Done | `#` trigger in character blocks, floating dropdown |
| Read mode toggle | Done | Toolbar button, element hiding, static rendering |
| Placeholder text | Done | Per-type hints via `@tiptap/extension-placeholder` |
| Server-client sync bridge | Done | Debounced push + set_editor_content |
| HTML sanitization | Done | Allowlist-based sanitization in ContentUtils |
