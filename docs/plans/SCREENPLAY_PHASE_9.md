# Phase 9: Dual Dialogue & Advanced Formatting

> **Prerequisite:** Phase 8 (Response Branching & Linked Pages) complete
>
> **Priority:** Important
>
> **Scope:** 4 self-contained tasks, ~47 tests total

---

## Overview

Phase 9 delivers three features:

1. **CONT'D Auto-detection** — Industry-standard `(CONT'D)` markers that appear automatically when the same character speaks in consecutive dialogue groups.
2. **Dual Dialogue** — Side-by-side rendering of two characters speaking simultaneously, with full CRUD and bidirectional flow sync.
3. **Read Mode** — A toggle that hides interactive/utility blocks and shows only screenplay-formatted content, suitable for sharing with non-technical collaborators.

**Design principles:**
- CONT'D is **computed, not stored** (same pattern as dialogue groups — Edge Case F)
- Character extensions (V.O., O.S.) are **typed manually by the writer** — the content field already stores them. No separate parsing layer for storage.
- Dual dialogue maps to **one dialogue node** in the flow (not two) — it's a single narrative beat
- Read mode is a **client-side toggle** in assigns — no database changes

---

## Task 9.1 — CONT'D Auto-detection + Display

**Goal:** Automatically show `(CONT'D)` on character elements when the same character speaks in consecutive dialogue groups, separated only by non-scene-breaking elements (action, notes, sections).

**Value:** Industry-standard screenplay formatting — every professional screenplay editor auto-detects continuations.

### Data model

No schema changes. CONT'D is computed from the element list at runtime.

### New module: `CharacterExtension`

Pure-function module for parsing character names and extracting extensions.

**File:** `lib/storyarn/screenplays/character_extension.ex`

```elixir
defmodule Storyarn.Screenplays.CharacterExtension do
  @moduledoc """
  Pure functions for parsing screenplay character name extensions.

  Standard extensions: (V.O.), (O.S.), (CONT'D), (O.C.), (SUBTITLE).
  Parses "JAIME (V.O.)" → %{base_name: "JAIME", extensions: ["V.O."]}.
  """

  @type parsed :: %{base_name: String.t(), extensions: [String.t()]}

  @doc "Parses a character name string into base name and extensions."
  @spec parse(String.t() | nil) :: parsed()
  def parse(nil), do: %{base_name: "", extensions: []}
  def parse(""), do: %{base_name: "", extensions: []}

  def parse(content) do
    # Extract all parenthetical extensions: "JAIME (V.O.) (CONT'D)" → ["V.O.", "CONT'D"]
    extensions = Regex.scan(~r/\(([^)]+)\)/, content) |> Enum.map(fn [_, ext] -> String.trim(ext) end)
    base_name = Regex.replace(~r/\s*\([^)]+\)/, content, "") |> String.trim()
    %{base_name: base_name, extensions: extensions}
  end

  @doc "Returns the base name without any extensions."
  @spec base_name(String.t() | nil) :: String.t()
  def base_name(content) do
    parse(content).base_name
  end

  @doc "Checks if content already includes a CONT'D extension."
  @spec has_contd?(String.t() | nil) :: boolean()
  def has_contd?(nil), do: false
  def has_contd?(content), do: String.contains?(String.upcase(content), "CONT'D")
end
```

### Update: `ElementGrouping.compute_continuations/1`

New public function in `ElementGrouping` that identifies which character elements should display `(CONT'D)`.

```elixir
@doc """
Computes which character elements should display (CONT'D).

Returns a MapSet of element IDs. A character gets (CONT'D) when:
- The same base name appeared in the most recent preceding dialogue group
- Only non-scene-breaking elements (action, note, section) appear between them
- Scene headings, transitions, and page breaks reset the speaker context

Uses `CharacterExtension.base_name/1` for case-insensitive comparison.
"""
@spec compute_continuations([ScreenplayElement.t()]) :: MapSet.t()
def compute_continuations(elements)
```

**Scene-breaking types** (reset last speaker): `scene_heading`, `transition`, `page_break`, `conditional`, `instruction`, `response`, `dual_dialogue`, `hub_marker`, `jump_marker`

**Pass-through types** (don't reset): `action`, `note`, `section`

**Algorithm:**
1. Walk elements sequentially
2. Track `last_speaker` (base name from most recent character element in a dialogue group)
3. When encountering a `character` element that's part of a dialogue group (followed by dialogue):
   - Compare `base_name(content)` with `last_speaker` (case-insensitive)
   - If match → add element ID to continuations MapSet
   - Update `last_speaker` regardless
4. Scene-breaking element → reset `last_speaker` to `nil`

**Edge case:** If writer already typed `(CONT'D)` in the character name, the base_name comparison still works because `parse/1` strips it. The renderer will show the auto-badge only if the content doesn't already contain `(CONT'D)`.

### Update: `show.ex` — Wire continuations into assigns

- Compute continuations in `mount/3` after loading elements
- Recompute after any element mutation (create, update, delete, reorder)
- Helper: `assign_elements_with_meta(socket, screenplay_id)` that assigns both `:elements` and `:continuations`

```elixir
defp assign_elements_with_meta(socket, screenplay_id) do
  elements = Screenplays.list_elements(screenplay_id)
  continuations = ElementGrouping.compute_continuations(elements)

  socket
  |> assign(:elements, elements)
  |> assign(:continuations, continuations)
end
```

### Update: `element_renderer.ex` — Show CONT'D badge

- Add `continuations` attr (MapSet, default: `MapSet.new()`)
- In the `render_block` clause for character type: if element ID is in continuations AND content doesn't already contain `(CONT'D)`, append a `<span class="sp-contd">(CONT'D)</span>` after the contenteditable div

### Update: `screenplay.css`

```css
.sp-contd {
  font-family: "Courier Prime", "Courier New", monospace;
  font-size: 12pt;
  opacity: 0.5;
  margin-left: 0.5ch;
  user-select: none;
  pointer-events: none;
}
```

### Files

| File                                                         | Action                                                 |
|--------------------------------------------------------------|--------------------------------------------------------|
| `lib/storyarn/screenplays/character_extension.ex`            | Create                                                 |
| `lib/storyarn/screenplays/element_grouping.ex`               | Add `compute_continuations/1`                          |
| `lib/storyarn_web/live/screenplay_live/show.ex`              | Wire continuations, `assign_elements_with_meta` helper |
| `lib/storyarn_web/components/screenplay/element_renderer.ex` | Add continuations attr, show CONT'D badge              |
| `assets/css/screenplay.css`                                  | Add `.sp-contd` style                                  |
| `test/storyarn/screenplays/character_extension_test.exs`     | Create (~8 tests)                                      |
| `test/storyarn/screenplays/element_grouping_test.exs`        | Add continuation tests (~6 tests)                      |
| `test/storyarn_web/live/screenplay_live/show_test.exs`       | Add display tests (~2 tests)                           |

### Tests (~16)

**CharacterExtension (8 tests):**
1. `parse/1` with plain name "JAIME" → base_name "JAIME", extensions []
2. `parse/1` with V.O. "JAIME (V.O.)" → base_name "JAIME", extensions ["V.O."]
3. `parse/1` with O.S. "JAIME (O.S.)" → base_name "JAIME", extensions ["O.S."]
4. `parse/1` with CONT'D "JAIME (CONT'D)" → base_name "JAIME", extensions ["CONT'D"]
5. `parse/1` with multiple "JAIME (V.O.) (CONT'D)" → extensions ["V.O.", "CONT'D"]
6. `parse/1` with nil → base_name "", extensions []
7. `base_name/1` returns stripped name
8. `has_contd?/1` returns true when CONT'D present

**compute_continuations (6 tests):**
1. Same speaker in consecutive groups → character marked
2. Different speakers → no continuation
3. Scene heading between same speaker → resets, no continuation
4. Action between same speaker → continuation preserved
5. Empty list → empty MapSet
6. Single dialogue group → no continuation

**LiveView display (2 tests):**
1. Character element shows (CONT'D) badge when in continuations
2. Character element does NOT show badge when not in continuations

### Acceptance criteria

- [x] `CharacterExtension.parse/1` handles all standard extensions
- [x] `compute_continuations/1` correctly identifies continuations
- [x] CONT'D badge visible in editor for continuing characters
- [x] Badge NOT shown if writer already typed (CONT'D)
- [x] Badge updates dynamically after element mutations
- [x] All tests pass
- [x] Credo --strict clean

---

## Task 9.2 — Dual Dialogue Block (Data + CRUD + Rendering)

**Goal:** Full dual dialogue editing experience: create via slash command, edit left/right speakers with character name, optional parenthetical, and dialogue text, rendered as a 2-column layout.

**Value:** Writers can create simultaneous dialogue — essential for film/game screenplays.

### Data structure

Dual dialogue stores structured data in the `data` field (like conditional, instruction, response):

```elixir
%ScreenplayElement{
  type: "dual_dialogue",
  content: "",  # unused (compound element)
  data: %{
    "left" => %{
      "character" => "ALICE",
      "parenthetical" => "(whispering)",  # or nil
      "dialogue" => "I agree."
    },
    "right" => %{
      "character" => "BOB",
      "parenthetical" => nil,
      "dialogue" => "Let's go."
    }
  }
}
```

**Default data** (on creation):
```elixir
%{
  "left" => %{"character" => "", "parenthetical" => nil, "dialogue" => ""},
  "right" => %{"character" => "", "parenthetical" => nil, "dialogue" => ""}
}
```

### Slash command update

The slash command menu already has `dual_dialogue` (Phase 4). Currently creates a stub. Now it creates the element with the default data structure above.

**Change:** In `show.ex`, the `select_slash_command` handler for `dual_dialogue` type sets the initial data:

```elixir
# In the update attrs for dual_dialogue type:
data = %{
  "left" => %{"character" => "", "parenthetical" => nil, "dialogue" => ""},
  "right" => %{"character" => "", "parenthetical" => nil, "dialogue" => ""}
}
```

### LiveView handler

One handler covers all 6 editable fields:

```elixir
def handle_event("update_dual_dialogue", %{
  "element-id" => element_id,
  "side" => side,        # "left" | "right"
  "field" => field,      # "character" | "parenthetical" | "dialogue"
  "value" => value
}, socket)
```

**Validation:**
- `side` must be `"left"` or `"right"`
- `field` must be `"character"`, `"parenthetical"`, or `"dialogue"`
- Rejects invalid side/field silently (defense-in-depth)

**Toggle parenthetical:**

```elixir
def handle_event("toggle_dual_parenthetical", %{
  "element-id" => element_id,
  "side" => side
}, socket)
```

Toggles parenthetical between `nil` (hidden) and `""` (empty, shown).

### Element renderer

Remove `dual_dialogue` from `@stub_types`. Add new `render_block` clause:

```elixir
defp render_block(%{element: %{type: "dual_dialogue"}} = assigns) do
  data = assigns.element.data || %{}
  assigns =
    assigns
    |> assign(:left, data["left"] || %{})
    |> assign(:right, data["right"] || %{})

  ~H"""
  <div class="sp-dual-dialogue">
    <.dual_column side="left" data={@left} element={@element} can_edit={@can_edit} />
    <.dual_column side="right" data={@right} element={@element} can_edit={@can_edit} />
  </div>
  """
end
```

**`dual_column` sub-component:** renders character input, optional parenthetical, dialogue textarea.

Uses `<input>` for character name, `<input>` for parenthetical, `<textarea>` for dialogue — all with `phx-blur="update_dual_dialogue"`. No custom JS hook needed (follows response block pattern).

### CSS

```css
.sp-dual_dialogue {
  display: grid;
  grid-template-columns: 1fr 1fr;
  gap: 24px;
  padding: 8px 0;
}

.sp-dual-column {
  /* Per-column styling matching standard screenplay character+dialogue */
}

.sp-dual-character {
  text-align: center;
  text-transform: uppercase;
  font-weight: bold;
  /* Courier Prime, 12pt */
}

.sp-dual-parenthetical {
  text-align: center;
  font-style: italic;
}

.sp-dual-dialogue-text {
  /* Matches standard dialogue width and styling */
}

.sp-dual-toggle-paren {
  /* Small toggle button for parenthetical visibility */
}
```

### Files

| File                                                         | Action                                                                                       |
|--------------------------------------------------------------|----------------------------------------------------------------------------------------------|
| `lib/storyarn_web/components/screenplay/element_renderer.ex` | Remove from stubs, add `render_block` + `dual_column`                                        |
| `lib/storyarn_web/live/screenplay_live/show.ex`              | Add `update_dual_dialogue`, `toggle_dual_parenthetical` handlers, init data on slash command |
| `assets/css/screenplay.css`                                  | Add dual dialogue styles                                                                     |
| `test/storyarn_web/live/screenplay_live/show_test.exs`       | Add dual dialogue tests (~10 tests)                                                          |
| `test/storyarn/screenplays/element_grouping_test.exs`        | Verify dual_dialogue doesn't affect grouping (~2 tests)                                      |

### Tests (~15)

**LiveView handlers (10 tests):**
1. Create dual_dialogue via slash command → element with default data
2. Update left character → data updated
3. Update right character → data updated
4. Update left dialogue → data updated
5. Update right dialogue → data updated
6. Update left parenthetical → data updated
7. Toggle left parenthetical on → sets empty string
8. Toggle left parenthetical off → sets nil
9. Delete dual_dialogue element → removed
10. Viewer cannot edit dual_dialogue (permission check)

**ElementGrouping (2 tests):**
1. dual_dialogue element → standalone `:dual_dialogue` group
2. dual_dialogue between two dialogue groups → doesn't break their grouping

**Renderer (3 tests):**
1. Renders 2-column layout with character names
2. Shows parenthetical when not nil
3. Hides parenthetical input when nil

### Acceptance criteria

- [x] Slash command `/dual` creates dual dialogue with empty structure
- [x] All 6 fields editable via `phx-blur`
- [x] Parenthetical toggle shows/hides per side
- [x] 2-column layout renders correctly
- [x] Viewers see read-only dual dialogue
- [x] dual_dialogue doesn't break adjacent dialogue group detection
- [x] All tests pass
- [x] Credo --strict clean

---

## Task 9.3 — Dual Dialogue Flow Sync

**Goal:** Dual dialogue elements participate in bidirectional flow sync. A dual dialogue maps to ONE dialogue node with additional dual data.

**Value:** Dual dialogue survives flow round-trips. Writers can sync screenplays with dual dialogue to flows and back.

### Approach: One node per dual dialogue

A dual dialogue is **one narrative beat** (two speakers at the same time). It maps to ONE dialogue node, not two. The flow node stores the left speaker's data in the standard fields and the right speaker's data in a `"dual_dialogue"` sub-map:

```elixir
# Dialogue node data (forward sync)
%{
  "speaker_sheet_id" => nil,
  "text" => left.dialogue,
  "stage_directions" => left.parenthetical || "",
  "menu_text" => left.character,
  "dual_dialogue" => %{
    "text" => right.dialogue,
    "stage_directions" => right.parenthetical || "",
    "menu_text" => right.character
  },
  ...standard fields...
}
```

**Why one node, not two:**
- Dual dialogue is one moment in time — it's semantically a single beat
- Two nodes would require pairing logic (shared IDs, ordering constraints)
- The flow canvas can show a visual indicator ("DUAL") without needing two separate nodes
- KISS: fewer edge cases in connection logic, layout, and traversal

### NodeMapping update

New clause in `group_to_node_attrs`:

```elixir
def group_to_node_attrs(%{type: :dual_dialogue, elements: [element]}, _index) do
  map_dual_dialogue(element)
end
```

Private `map_dual_dialogue/1`:
```elixir
defp map_dual_dialogue(element) do
  data = element.data || %{}
  left = data["left"] || %{}
  right = data["right"] || %{}

  %{
    type: "dialogue",
    data: %{
      "speaker_sheet_id" => nil,
      "text" => left["dialogue"] || "",
      "stage_directions" => left["parenthetical"] || "",
      "menu_text" => left["character"] || "",
      "audio_asset_id" => nil,
      "technical_id" => "",
      "localization_id" => "",
      "input_condition" => "",
      "output_instruction" => "",
      "responses" => [],
      "dual_dialogue" => %{
        "text" => right["dialogue"] || "",
        "stage_directions" => right["parenthetical"] || "",
        "menu_text" => right["character"] || ""
      }
    },
    element_ids: [element.id],
    source: "screenplay_sync"
  }
end
```

### ReverseNodeMapping update

In `map_dialogue/1`, check for `dual_dialogue` data:

```elixir
defp map_dialogue(%FlowNode{id: id, data: data}) do
  data = data || %{}

  if data["dual_dialogue"] do
    map_dual_dialogue_reverse(id, data)
  else
    # ...existing logic...
  end
end
```

`map_dual_dialogue_reverse/2`:
```elixir
defp map_dual_dialogue_reverse(id, data) do
  dual = data["dual_dialogue"] || %{}

  [%{
    type: "dual_dialogue",
    content: "",
    data: %{
      "left" => %{
        "character" => data["menu_text"] || "",
        "parenthetical" => non_empty_or_nil(data["stage_directions"]),
        "dialogue" => data["text"] || ""
      },
      "right" => %{
        "character" => dual["menu_text"] || "",
        "parenthetical" => non_empty_or_nil(dual["stage_directions"]),
        "dialogue" => dual["text"] || ""
      }
    },
    source_node_id: id
  }]
end

defp non_empty_or_nil(""), do: nil
defp non_empty_or_nil(s), do: s
```

### ElementGrouping — already works

`dual_dialogue` is not in `@dialogue_group_types` or `@non_mappeable_types`, so `classify_element_type("dual_dialogue")` returns `:dual_dialogue` atom. This creates a standalone group `%{type: :dual_dialogue, elements: [el]}`. The existing `group_to_node_attrs` dispatch (updated above) handles it.

No changes needed to `ElementGrouping`.

### Files

| File                                                      | Action                                        |
|-----------------------------------------------------------|-----------------------------------------------|
| `lib/storyarn/screenplays/node_mapping.ex`                | Replace nil clause with `map_dual_dialogue/1` |
| `lib/storyarn/screenplays/reverse_node_mapping.ex`        | Add dual_dialogue detection in `map_dialogue` |
| `test/storyarn/screenplays/node_mapping_test.exs`         | Add dual dialogue mapping tests (~3 tests)    |
| `test/storyarn/screenplays/reverse_node_mapping_test.exs` | Add dual dialogue reverse tests (~3 tests)    |
| `test/storyarn/screenplays/flow_sync_test.exs`            | Add round-trip sync tests (~4 tests)          |

### Tests (~10)

**NodeMapping (3 tests):**
1. dual_dialogue → dialogue node with dual_dialogue data
2. dual_dialogue with parentheticals → stage_directions populated
3. dual_dialogue with empty data → default values

**ReverseNodeMapping (3 tests):**
1. dialogue with dual_dialogue data → dual_dialogue element
2. dialogue without dual_dialogue data → unchanged (character+dialogue, existing behavior)
3. dual_dialogue with parentheticals → parenthetical fields populated

**FlowSync integration (4 tests):**
1. sync_to_flow with dual_dialogue → node created with dual data
2. sync_from_flow with dual dialogue node → dual_dialogue element created
3. Round-trip: dual_dialogue → sync_to_flow → sync_from_flow → dual_dialogue preserved
4. Dual dialogue between standard dialogue groups → connections correct

### Acceptance criteria

- [x] Forward sync: dual_dialogue → 1 dialogue node with dual data
- [x] Reverse sync: dialogue node with `dual_dialogue` key → 1 dual_dialogue element
- [x] Round-trip preserves all data (both speakers, parentheticals)
- [x] Regular dialogue nodes (without dual_dialogue key) → unchanged
- [x] Connections to/from dual dialogue node work correctly
- [x] All tests pass
- [x] Credo --strict clean

---

## Task 9.4 — Read Mode

**Goal:** A toolbar toggle that switches the editor to read-only mode, hiding interactive blocks (conditional, instruction, response), utility blocks (note, section), and all edit affordances. Shows only screenplay-formatted content.

**Value:** Writers can preview the "readable" screenplay as it would appear to a non-technical collaborator or in export. Essential for proofing and sharing.

### Approach

- New boolean assign `:read_mode` (default `false`)
- Toolbar button toggles read mode
- When active:
  - Interactive blocks (conditional, instruction, response) are hidden
  - Utility blocks (note) are hidden
  - Stub blocks (hub_marker, jump_marker, title_page) are hidden
  - Standard blocks render without `contenteditable` and without phx-hooks
  - Dual dialogue renders read-only
  - Section elements render as visual headers (not hidden — they're structural)
  - Page breaks remain visible
  - Slash command menu is disabled
  - CONT'D badges still shown (they're part of formatting)
- CSS class `.screenplay-read-mode` on the container adds read-mode styling

### Hidden types in read mode

```elixir
@read_mode_hidden_types ~w(conditional instruction response note hub_marker jump_marker title_page)
```

### LiveView handler

```elixir
def handle_event("toggle_read_mode", _params, socket) do
  {:noreply, assign(socket, :read_mode, !socket.assigns.read_mode)}
end
```

### Toolbar button

```heex
<button
  type="button"
  class={["sp-toolbar-btn", @read_mode && "sp-toolbar-btn-active"]}
  phx-click="toggle_read_mode"
  title={if @read_mode, do: gettext("Exit read mode"), else: gettext("Read mode")}
>
  <.icon name={if @read_mode, do: "pencil", else: "book-open"} class="size-4" />
</button>
```

### Element filtering

In the template's `for` loop, filter out hidden elements when in read mode:

```elixir
# In the element rendering loop
:for={element <- visible_elements(@elements, @read_mode)}
```

```elixir
defp visible_elements(elements, false), do: elements
defp visible_elements(elements, true) do
  Enum.reject(elements, &(&1.type in @read_mode_hidden_types))
end
```

### Element renderer update

Pass `read_mode` as attr. When `read_mode` is true:
- Standard editable blocks render without `contenteditable`, without `phx-hook`, without placeholder
- Dual dialogue renders all fields as plain text (no inputs/textareas)

### CSS

```css
.screenplay-read-mode .screenplay-element {
  cursor: default;
}

.screenplay-read-mode .sp-empty {
  display: none;  /* Hide empty elements in read mode */
}

.sp-toolbar-btn-active {
  background: oklch(var(--p));
  color: oklch(var(--pc));
}
```

### Files

| File                                                         | Action                                                                        |
|--------------------------------------------------------------|-------------------------------------------------------------------------------|
| `lib/storyarn_web/live/screenplay_live/show.ex`              | Add `:read_mode` assign, toggle handler, `visible_elements/2`, toolbar button |
| `lib/storyarn_web/components/screenplay/element_renderer.ex` | Add `read_mode` attr, conditional rendering                                   |
| `assets/css/screenplay.css`                                  | Add read mode styles                                                          |
| `test/storyarn_web/live/screenplay_live/show_test.exs`       | Add read mode tests (~6 tests)                                                |

### Tests (~6)

1. Toggle read mode on → assign updated
2. Toggle read mode off → assign updated
3. Read mode hides conditional elements
4. Read mode hides instruction elements
5. Read mode hides note elements
6. Read mode shows scene_heading, character, dialogue, action, transition, dual_dialogue

### Acceptance criteria

- [x] Toolbar button toggles read mode
- [x] Interactive blocks hidden in read mode
- [x] Notes hidden in read mode
- [x] Standard blocks render as plain text (no editing)
- [x] CONT'D badges still visible in read mode
- [x] Page breaks and sections still visible
- [x] Dual dialogue renders read-only in read mode
- [x] All tests pass
- [x] Credo --strict clean

---

## Implementation Order

```
Task 9.1 (CONT'D)
  ↓
Task 9.2 (Dual Dialogue Block)  ←  depends on 9.1 for continuations
  ↓
Task 9.3 (Dual Dialogue Sync)   ←  depends on 9.2 for data structure
  ↓
Task 9.4 (Read Mode)            ←  depends on 9.2 for dual_dialogue rendering
```

Tasks must be done in order. Each task is self-contained and testable independently.

---

## Files Summary

| File                                                         | Tasks         |
|--------------------------------------------------------------|---------------|
| `lib/storyarn/screenplays/character_extension.ex`            | 9.1 (create)  |
| `lib/storyarn/screenplays/element_grouping.ex`               | 9.1           |
| `lib/storyarn_web/live/screenplay_live/show.ex`              | 9.1, 9.2, 9.4 |
| `lib/storyarn_web/components/screenplay/element_renderer.ex` | 9.1, 9.2, 9.4 |
| `assets/css/screenplay.css`                                  | 9.1, 9.2, 9.4 |
| `lib/storyarn/screenplays/node_mapping.ex`                   | 9.3           |
| `lib/storyarn/screenplays/reverse_node_mapping.ex`           | 9.3           |
| `test/storyarn/screenplays/character_extension_test.exs`     | 9.1 (create)  |
| `test/storyarn/screenplays/element_grouping_test.exs`        | 9.1, 9.2      |
| `test/storyarn/screenplays/node_mapping_test.exs`            | 9.3           |
| `test/storyarn/screenplays/reverse_node_mapping_test.exs`    | 9.3           |
| `test/storyarn/screenplays/flow_sync_test.exs`               | 9.3           |
| `test/storyarn_web/live/screenplay_live/show_test.exs`       | 9.1, 9.2, 9.4 |

---

## Verification

```bash
# Per task
mix test test/storyarn/screenplays/character_extension_test.exs    # 9.1
mix test test/storyarn/screenplays/element_grouping_test.exs       # 9.1, 9.2
mix test test/storyarn_web/live/screenplay_live/show_test.exs      # 9.1, 9.2, 9.4
mix test test/storyarn/screenplays/node_mapping_test.exs            # 9.3
mix test test/storyarn/screenplays/reverse_node_mapping_test.exs    # 9.3
mix test test/storyarn/screenplays/flow_sync_test.exs               # 9.3

# Full suite
mix credo --strict
mix test
```

---

## Decisions

### D9.1: CONT'D computed, not stored
Following Edge Case F (dialogue groups), CONT'D is computed from element adjacency at runtime. No `is_continuation` field in the schema.

### D9.2: Dual dialogue = one flow node
A dual dialogue is one narrative beat. Mapping it to two flow nodes would require pairing logic, ordering constraints, and special connection handling. One node is simpler and semantically correct.

### D9.3: `<input>`/`<textarea>` for dual dialogue, not contenteditable
Standard blocks use contenteditable + ScreenplayElement hook. Dual dialogue has 6 fields per element, making a single contenteditable impractical. `<input>`/`<textarea>` with `phx-blur` follows the response block pattern and needs no custom JS hook.

### D9.4: Read mode is client-side only
No database field for read mode — it's a toggle in socket assigns. Each session has its own read mode state. This avoids unnecessary schema changes and keeps the feature lightweight.

### D9.5: Character extensions are manual
V.O., O.S., and other extensions are typed by the writer in the character name content field. No auto-detection or structured storage. Only CONT'D is auto-detected since it depends on document context (preceding dialogue groups), not user intent.
