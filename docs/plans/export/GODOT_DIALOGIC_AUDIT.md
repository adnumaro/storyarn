# Godot Export Audit: Dialogic 2 Format Research & Gap Analysis

> **Date:** 2026-02-28
>
> **Scope:** Research Dialogic 2's `.dtl` timeline format, compare with Storyarn's current Godot export, identify all gaps
>
> **Sources:** Dialogic 2 official docs (docs.dialogic.pro), GitHub source (dialogic-godot/dialogic), DeepWiki synthesis

---

## 1. Key Discovery: Dialogic 2 Uses `.dtl` Text Files, NOT JSON

Dialogic 2 timelines are **plain-text `.dtl` files** — a custom line-based DSL. NOT JSON. Each line is one event. TAB characters (not spaces) control nesting for choices and conditions.

Our current `GodotJSON` serializer produces a **generic JSON format** for custom Godot integrations. It is a valid, separate export option — but it is NOT Dialogic-compatible. A true Dialogic export requires a new serializer that emits `.dtl` text.

---

## 2. Complete `.dtl` Event Reference

### 2.1 Text / Dialogue Event

```
CharacterName: Dialogue text here.
CharacterName (portrait): Dialogue with emotion.
"Character With Spaces": Dialogue text.
_: Narrator text (no character shown).
Plain text without speaker.
```

Multi-line continuation with backslash:
```
Alice: This is a long line\
that continues here.
```

Inline variable interpolation: `{Variable.Path}` is replaced at runtime.

### 2.2 Character Event (Join / Leave / Update)

```
join CharacterName
join CharacterName (portrait) center
join CharacterName (portrait) left [animation="Bounce In" length="0.5"]
leave CharacterName [animation="Fade Out"]
leave --All--
update CharacterName (new_portrait) right [move_time="0.3"]
```

**Positions:** `leftmost`, `left`, `center`, `right`, `rightmost` (or custom).

**Shortcode parameters:** `animation`, `length`, `wait`, `repeat`, `repeat_forever`, `z_index`, `mirrored`, `fade`, `fade_length`, `move_time`, `move_ease`, `move_trans`, `extra_data`.

### 2.3 Choice Event

```
- Choice text
- Choice text | [if {Variable} > 10]
- Choice text | [if {Variable} > 10] [else="hide"]
- Choice text | [if {Var} > 5] [else="disable" alt_text="Locked"]
```

Events inside a choice are **TAB-indented** below it:
```
- Accept
	set {Player.Agreed} = true
	Alice: Great!
- Decline
	Alice: Too bad.
```

**`else` values:** `"default"` (show always), `"hide"` (remove when false), `"disable"` (gray out).

### 2.4 Condition Event

```
if {Player.Health} > 50:
	Alice: You look healthy!
elif {Player.Health} > 20:
	Alice: You need rest.
else:
	Alice: You're barely standing!
```

Conditions are GDScript-compatible expressions. Variables in `{curly.braces}`. Supports `==`, `!=`, `<`, `>`, `<=`, `>=`, `and`, `or`, `not`, parentheses.

### 2.5 Variable Set Event

```
set {Variable} = 20
set {Folder.Variable} += 10
set {Folder.Variable} -= 5
set {Folder.Variable} *= 2
set {Folder.Variable} /= 4
set {Player.Name} = "Alice"
set {Player.Alive} = true
set {Player.Score} = {Other.Score}
```

**Operators:** `=`, `+=`, `-=`, `*=`, `/=`

### 2.6 Navigation Events

```
label my_label
label my_label (Display Name)
jump label_name
jump other_timeline/
jump other_timeline/label_name
return
```

- `jump` without args → restart current timeline
- `jump timeline/` → start of another timeline
- `return` → pop from jump stack (or end timeline)

### 2.7 Shortcode Events

```
[background arg="res://bg.png" fade="1.0"]
[wait time="2.0" skippable="true"]
[signal arg="my_event"]
[end_timeline]
```

All shortcode parameter values are **double-quoted strings**.

### 2.8 Audio Event

```
audio music "res://music.ogg" [fade="1.0" volume="-5" loop="true"]
audio "res://sfx.wav"
```

### 2.9 Comment Event

```
# This is a comment
```

### 2.10 Call/Do Event

```
do MyAutoload.my_method()
do Player.take_damage(10)
```

### 2.11 Voice Event

```
[voice path="res://voices/line_001.ogg"]
```

Plays with the next text event.

### 2.12 Text Input Event

```
[text_input var="Player.Name" text="What is your name?" placeholder="Enter name" default="Hero"]
```

---

## 3. Variable System

Variables are defined in Godot project settings under `dialogic/variables`. Structure is a nested dictionary:

```gdscript
{
  "PlayerData": {
    "Health": 100,
    "Name": "Hero",
    "Gold": 0
  },
  "Flags": {
    "MetJaime": false
  }
}
```

**Reference syntax:** `{Folder.Variable}` — curly braces required in conditions, text interpolation, and set events.

**Supported types:** String, Number (int/float), Boolean, Array, Dictionary.

---

## 4. Character Resource Format (`.dch`)

`.dch` files are **Godot Resource files** (binary/text), NOT JSON. Properties:

| Property | Type | Notes |
|----------|------|-------|
| `display_name` | String | Shown in dialogue |
| `color` | Color | RGBA |
| `scale` | float | Default 1.0 |
| `mirror` | bool | Flip portraits |
| `default_portrait` | String | Key in portraits dict |
| `portraits` | Dictionary | name → scene/config |
| `nicknames` | Array | Alternate names |
| `description` | String | Developer notes |
| `custom_info` | Dictionary | Arbitrary metadata |

**Character identification in `.dtl`:** Characters are resolved by `display_name` or nickname. The identifier used in `.dtl` files is typically the filename (without `.dch`).

---

## 5. Storyarn Node → Dialogic Event Mapping

| Storyarn Node | Dialogic `.dtl` | Notes |
|---------------|-----------------|-------|
| `entry` | First line of timeline (implicit) | Or `label` at top |
| `dialogue` | `CharacterName: Text` | Speaker from sheet shortcut → display name |
| `dialogue.responses[]` | `- Choice text` with TAB-indented body | Conditions: `\| [if {condition}]` |
| `dialogue.responses[].instruction_assignments` | `set` lines TAB-indented under choice | Before any dialogue in that branch |
| `condition` | `if {expr}:` / `elif {expr}:` / `else:` | Branches are TAB-indented blocks |
| `instruction` | `set {Var} op value` | One `set` line per assignment |
| `hub` | `label hub_shortcut` | Jump target |
| `jump` | `jump label_name` or `jump timeline/label` | Cross-flow = cross-timeline |
| `subflow` | `jump flow_shortcut/` + `return` at end of target | Dialogic has no native tunnel; use jump + return |
| `scene` | `# location: INT. TAVERN` (comment) or `[background]` | No direct Dialogic equivalent for scene metadata |
| `exit` | `[end_timeline]` or end of file | |
| `stage_directions` | `# [Stage: directions]` (comment) | Informational only |

### Key Challenges

1. **Graph → Linear:** Storyarn flows are directed graphs. Dialogic `.dtl` is linear with branching via TAB indentation. Must use `GraphTraversal.linearize()` to walk the flow, emitting labels and jumps for non-linear paths.

2. **Subflows as tunnels:** Dialogic has no native "tunnel" concept. Best approach: emit `jump flow_shortcut/` and have the target timeline end with `return`.

3. **Multi-branch conditions:** Dialogic supports `if/elif/else` (unlimited elif chains). Storyarn condition nodes with 3+ branches map naturally — better than Ink which only supports if/else.

4. **Choice nesting:** Dialogic choices use TAB indentation for their content. The linearizer already produces `{:choice, resp, idx}` instructions — we need to indent all content belonging to each choice.

---

## 6. Expression Format Differences

### Current: GodotJSON Expression Transpiler

The existing `ExpressionTranspiler.Godot` emits GDScript with underscore variable names:

```
mc_jaime_health > 50 and flags_met_jaime == true
```

### Required: Dialogic Expression Format

Dialogic conditions use the same GDScript operators BUT variables must be in `{curly.braces}` with dot-paths:

```
{mc_jaime.health} > 50 and {flags.met_jaime} == true
```

### Variable Path Convention

| Storyarn | GodotJSON (current) | Dialogic (needed) |
|----------|--------------------|--------------------|
| `mc.jaime.health` | `mc_jaime_health` | `{mc_jaime.health}` |
| `flags.met_jaime` | `flags_met_jaime` | `{flags.met_jaime}` |

**Strategy:** Sheet shortcut (dots → underscores) becomes Dialogic folder. Variable name stays as-is. Wrapped in curly braces.

Example: `mc.jaime` (sheet shortcut) + `health` (variable) → `{mc_jaime.health}`

### Instruction Format Differences

| Storyarn Operator | GodotJSON (current) | Dialogic `.dtl` (needed) |
|-------------------|--------------------|-----------------------------|
| `set` | `var = value` | `set {Var} = value` |
| `add` | `var += value` | `set {Var} += value` |
| `subtract` | `var -= value` | `set {Var} -= value` |
| `set_true` | `var = true` | `set {Var} = true` |
| `set_false` | `var = false` | `set {Var} = false` |
| `toggle` | `var = !var` | `set {Var} = !{Var}` |
| `clear` | `var = ""` | `set {Var} = ""` |
| `set_if_unset` | `if var == null: var = val` | `if {Var} == null:\n\tset {Var} = val` (multi-line) |

**Key difference:** Dialogic prepends `set` keyword and wraps vars in `{}`.

### Condition Operator Compatibility

| Storyarn Operator | GDScript (current) | Dialogic Compatible? |
|-------------------|--------------------|-----------------------|
| `equals` | `==` | Yes |
| `not_equals` | `!=` | Yes |
| `greater_than` | `>` | Yes |
| `less_than` | `<` | Yes |
| `>=`, `<=` | `>=`, `<=` | Yes |
| `is_true` | `== true` | Yes |
| `is_false` | `== false` | Yes |
| `is_nil` | `== null` | Yes — Dialogic supports null |
| `is_empty` | `== ""` | Yes |
| `contains` | `"val" in ref` | **Partial** — GDScript `in` works for arrays/strings |
| `not_contains` | `"val" not in ref` | **Partial** — `not ... in` works in GDScript |
| `starts_with` | `.begins_with()` | **Yes** — GDScript string method |
| `ends_with` | `.ends_with()` | **Yes** — GDScript string method |
| `before` / `after` | `<` / `>` | Yes (string comparison for dates) |

**Note:** Dialogic evaluates conditions via `Dialogic.Expressions.execute_condition()` which executes GDScript expressions. So all valid GDScript works, including method calls like `.begins_with()`.

---

## 7. Current Storyarn Godot Export — State Analysis

### What Exists

| Component | File | Status |
|-----------|------|--------|
| **GodotJSON serializer** | `lib/storyarn/exports/serializers/godot_json.ex` | Complete (209 lines) |
| **Godot expression transpiler** | `lib/storyarn/exports/expression_transpiler/godot.ex` | Complete (71 lines) |
| **GodotJSON tests** | `test/storyarn/exports/serializers/godot_json_test.exs` | 46 tests |
| **Expression transpiler tests** | `test/.../condition_test.exs`, `instruction_test.exs` | Godot cases covered |
| **Format spec** | `docs/plans/export/FORMAT_GODOT.md` | Comprehensive |
| **Registry entry** | `serializer_registry.ex` | `:godot` registered |
| **Export options** | `export_options.ex` | `:godot` and `:godot_dialogic` both valid |

### What's Missing (for Dialogic `.dtl` export)

| Component | Status | Effort |
|-----------|--------|--------|
| **GodotDialogic serializer** | Not implemented | Major — new serializer module |
| **Dialogic expression transpiler** | Not implemented | Medium — new emitter or var_style variant |
| **Dialogic tests** | Not implemented | Major — unit + integration |
| **Registry entry** | `:godot_dialogic` NOT in registry | Trivial |
| **GraphTraversal integration** | Available but not wired | Medium — same pattern as Ink/Yarn |

### Bugs / Gaps in Existing GodotJSON

| # | Issue | Severity | Description |
|---|-------|----------|-------------|
| G1 | Scenes not serialized | Medium | `supported_sections` declares `:scenes` but `serialize/2` never processes `project_data.scenes` |
| G2 | Response `next` always nil | Low | Dialogue responses have `"next" => nil` — the spec shows they should point to connected nodes |
| G3 | No text escaping | Low | Dialogue text is not escaped for JSON special chars (HTML is stripped but no further escaping) |
| G4 | `set_if_unset` no warning | Low | Same as Yarn F3 — emits `if var == null: var = val` but no semantic loss warning (Godot does have null, so less critical) |

---

## 8. Dialogic `.dtl` Serializer — What Needs to Be Built

### 8.1 New Expression Transpiler Variant

The existing `ExpressionTranspiler.Godot` uses `:underscore` var style (`mc_jaime_health`). Dialogic needs a variant with:

- **Variable format:** `{folder.variable}` (curly-brace wrapped, dot-separated, folder = sheet shortcut with dots→underscores)
- **Condition output:** Same GDScript operators
- **Instruction output:** Prefixed with `set ` keyword, e.g., `set {mc_jaime.health} = 100`

**Options:**
1. **New emitter module** `ExpressionTranspiler.Dialogic` with `:dialogic_curly` var style
2. **Extend existing** `ExpressionTranspiler.Godot` with a flag/option for Dialogic mode

Option 1 is cleaner — follows the pattern of separate emitter per format.

### 8.2 Serializer Module

**File:** `lib/storyarn/exports/serializers/godot_dialogic.ex`

**Pattern:** Same as Ink/Yarn serializers — uses `GraphTraversal.linearize()`, renders instructions to `.dtl` text lines.

**Output:** `{:ok, [{filename, content}, ...]}` with:
- One `.dtl` file per flow
- One `metadata.json` sidecar with character/variable mapping

### 8.3 `.dtl` Rendering Rules

1. **Indentation:** TAB characters only. Depth increases for choice bodies and condition branches.
2. **Dialogue:** `SpeakerName: Text` — speaker is the sheet's `name` field (display name). If no speaker, just text.
3. **Choices:** `- Text` at current depth. Choice body is indented +1 TAB.
4. **Conditions:** `if {expr}:` at current depth. Branch body indented +1 TAB. Second branch = `elif` or `else`.
5. **Instructions:** `set {Var} op value` at current depth.
6. **Labels:** `label identifier` at root depth (no indentation).
7. **Jumps:** `jump label` or `jump timeline/label` at current depth.
8. **End:** `[end_timeline]` or implicit at end of file.
9. **Comments:** `# text` for generated headers, stage directions, scene metadata.

### 8.4 Metadata Sidecar

```json
{
  "storyarn_dialogic_metadata": "1.0.0",
  "project": "Project Name",
  "characters": {
    "mc.jaime": {
      "display_name": "Jaime",
      "storyarn_shortcut": "mc.jaime",
      "properties": {
        "health": {"type": "number", "default": 100},
        "class": {"type": "select", "default": "warrior"}
      }
    }
  },
  "variable_folders": {
    "mc_jaime": {
      "health": 100,
      "class": "warrior"
    },
    "flags": {
      "met_jaime": false
    }
  },
  "timeline_mapping": {
    "act1.tavern-intro": "act1_tavern_intro.dtl"
  }
}
```

### 8.5 Example Output

Given a Storyarn flow "Tavern Introduction" with:
- Entry → Dialogue (Jaime: "Hello, traveler!") with 2 responses
- Response 1 → Hub "after_greeting" → Instruction (set met_jaime = true) → Exit
- Response 2 (condition: health > 50) → Dialogue → Exit

Expected `.dtl`:
```
# Generated by Storyarn (https://storyarn.dev)
# Flow: Tavern Introduction

Jaime: Hello, traveler!
- Hello!
	jump after_greeting
- Leave me alone. | [if {mc_jaime.health} > 50]
	Jaime: As you wish.
	[end_timeline]

label after_greeting
set {flags.met_jaime} = true
Jaime: Welcome to the Copper Tankard!
[end_timeline]
```

---

## 9. Feature Matrix: Storyarn Capabilities vs Dialogic Support

| Storyarn Feature | Dialogic Support | Mapping Strategy |
|------------------|-----------------|-------------------|
| Dialogue text | Full | `CharacterName: Text` |
| Speaker assignment | Full | Sheet name → character display name |
| Stage directions | None (comment) | `# [Stage: directions]` |
| Response choices | Full | `- Text` with TAB indent |
| Response conditions | Full | `- Text \| [if {condition}]` |
| Response instructions | Full | `set` lines inside choice block |
| Condition branching (if/elif/else) | Full | Native `if/elif/else:` blocks |
| Condition branching (3+ cases) | Full | `elif` chains (unlike Ink which is limited to if/else) |
| Instruction: set/add/subtract | Full | `set {Var} =`, `+=`, `-=` |
| Instruction: set_true/set_false | Full | `set {Var} = true/false` |
| Instruction: toggle | Full | `set {Var} = !{Var}` |
| Instruction: clear | Full | `set {Var} = ""` |
| Instruction: set_if_unset | Partial | `if {Var} == null:` + `set` (multi-line) — Dialogic supports null |
| Hub nodes | Full | `label` events |
| Jump nodes | Full | `jump label` |
| Subflow nodes | Partial | `jump timeline/` + `return` (no native tunnel) |
| Scene nodes | Partial | `[background]` for images, comment for metadata |
| Variable types: number, boolean, string | Full | Native Dialogic variable types |
| Variable types: select, multi_select | Partial | Stored as string/array — runtime logic needed |
| Variable types: date | Partial | String comparison only |
| Nested conditions (blocks) | Full | Parenthesized expressions |
| Audio references | Partial | `[voice path="..."]` for dialogue audio — but needs `res://` paths |
| Localization IDs | None | Would need separate export (CSV or Dialogic translation keys) |

### Features Dialogic Has That Storyarn Doesn't Map To

| Dialogic Feature | Storyarn Equivalent | Notes |
|-----------------|---------------------|-------|
| Character portraits | None | Storyarn has no portrait system (yet) |
| Character join/leave | None | No stage presence concept in flows |
| Background events | Scene nodes (partial) | Could map scene location to background |
| Audio channels | Audio asset on dialogue | Only per-dialogue, not channel system |
| Wait events | None | No pause concept |
| Signal events | None | Could use as custom events |
| Text BBCode | Rich text in dialogue | Would need to map HTML → BBCode |
| Random text `<A/B/C>` | None | No random text support |
| Do/Call events | None | No autoload call concept |
| Text input events | None | No player input concept |
| Clear events | None | No reset concept |

---

## 10. Implementation Priority Assessment

### Phase 1: Core `.dtl` Export (HIGH priority)

Must-have for a usable Dialogic export:
- [ ] New expression transpiler variant for Dialogic variable syntax
- [ ] `.dtl` serializer with GraphTraversal integration
- [ ] Dialogue rendering (speaker + text)
- [ ] Choice rendering with TAB indentation
- [ ] Condition rendering (if/elif/else)
- [ ] Instruction rendering (set operations)
- [ ] Label/jump for hubs
- [ ] Cross-timeline jump for subflows
- [ ] Exit rendering
- [ ] Metadata sidecar JSON
- [ ] Registry registration
- [ ] Unit tests
- [ ] Stage directions as comments

### Phase 2: Polish (MEDIUM priority)

Nice-to-have improvements:
- [ ] Scene nodes → `[background]` events (if location maps to image)
- [ ] Audio references → `[voice]` events
- [ ] HTML → BBCode conversion for rich text
- [ ] Response `else` behavior mapping (hide/disable)
- [ ] `set_if_unset` → multi-line `if null` + `set`
- [ ] Variable folder nesting documentation/README in export

### Phase 3: Ecosystem (LOW priority, separate tickets)

- [ ] CSV localization export for Godot
- [ ] Fix GodotJSON G1 (scenes not serialized)
- [ ] Fix GodotJSON G2 (response next always nil)

### Not Planned

- `.dch` character file generation (Godot Resource format, too coupled to Godot internals)
- `.tres` resource generation
- Dialogic save data
- `project.godot` variable registration (users must set up variables in Dialogic settings)

---

## 11. Architecture Decision: Expression Transpiler Approach

### Option A: New Emitter Module (Recommended)

Create `ExpressionTranspiler.Dialogic` with a new `:dialogic` var style that wraps refs in `{curly.braces}` with dot paths.

**Pros:**
- Clean separation — each format has its own emitter
- Follows existing pattern (Ink, Yarn, Unity, Godot, Unreal, Articy all have separate modules)
- Can customize instruction output format (prepend `set ` keyword)

**Cons:**
- Some duplication with `ExpressionTranspiler.Godot` (same operator mappings)

### Option B: Flag on Existing Godot Emitter

Add a `dialogic_mode` flag to `ExpressionTranspiler.Godot` that changes variable formatting.

**Pros:**
- No code duplication for operator mappings

**Cons:**
- Breaks the clean 1:1 mapping between format and emitter
- `ExpressionTranspiler.transpile_condition(condition, :godot_dialogic)` vs `:godot` adds complexity to the dispatcher
- Instruction rendering fundamentally differs (needs `set ` prefix) — flag-based branching gets messy

**Decision: Option A** — New emitter module. The instruction format difference alone justifies a separate module. Operator mappings can delegate to shared helpers if needed.

---

## 12. Testing Strategy

### Unit Tests (no external tools)

```
test/storyarn/exports/serializers/godot_dialogic_test.exs
```

- Empty flow produces minimal valid `.dtl`
- Dialogue with speaker renders `CharacterName: Text`
- Dialogue without speaker renders plain text
- Responses render as `- Text` with TAB indentation
- Response conditions render `| [if {condition}]` syntax
- Response instructions render `set` lines inside choice block
- Conditions render `if/elif/else:` blocks
- Instructions render `set {Var} op value`
- Hub nodes render `label`
- Jump nodes render `jump label`
- Subflow nodes render `jump timeline/`
- Exit nodes render `[end_timeline]`
- Stage directions render as comments
- Metadata sidecar has correct structure
- Variable folder mapping is correct
- Timeline filename mapping is correct
- Special characters in text are handled
- Multi-flow export produces multiple `.dtl` files

### Expression Transpiler Tests

Add `:dialogic` test cases alongside existing `:godot` cases in:
- `test/storyarn/exports/expression_transpiler/condition_test.exs`
- `test/storyarn/exports/expression_transpiler/instruction_test.exs`

### No Compiler Validation

Unlike Ink (inklecate) and Yarn (ysc), Dialogic has no standalone compiler. Timeline validation happens at runtime inside Godot. We rely on unit tests and format correctness.

---

## Appendix A: Complete Realistic `.dtl` Example

```dtl
# Generated by Storyarn (https://storyarn.dev)
# Flow: Tavern Introduction

Jaime: Hello, traveler! Welcome to the Copper Tankard.
Jaime: What brings you to these parts?
- I'm looking for work. | [if {mc_jaime.reputation} >= 10]
	set {flags.asked_work} = true
	Jaime: Ah, I might have something for you.
	jump work_offer
- Just passing through.
	Jaime: Well, enjoy your stay.
	jump farewell
- Who are you? | [if {flags.met_jaime} == false]
	set {flags.met_jaime} = true
	Jaime: I'm Jaime, the barkeep. Been running this place for twenty years.
	jump after_intro

label work_offer
if {mc_jaime.reputation} >= 20:
	Jaime: There's a bounty on some bandits outside town. Interested?
	- Accept the bounty
		set {quests.bandit_bounty} = true
		set {mc_jaime.reputation} += 5
		Jaime: Good luck out there!
		[end_timeline]
	- Decline
		jump farewell
else:
	Jaime: Come back when you've made more of a name for yourself.
	jump farewell

label after_intro
Jaime: Now then, what can I do for you?
- I'm looking for work. | [if {mc_jaime.reputation} >= 10]
	jump work_offer
- Just passing through.
	jump farewell

label farewell
Jaime: Safe travels, friend.
[end_timeline]
```

## Appendix B: Text Escaping in `.dtl`

Dialogic text events support these escape sequences:
- `\#` → literal `#` (prevents hashtag parsing)
- `\{` → literal `{` (prevents variable interpolation)
- `\}` → literal `}`
- `\[` → literal `[` (prevents shortcode/markup parsing)
- `\]` → literal `]`
- `\\` → literal `\`

Our serializer must escape these characters in dialogue and choice text.

## Appendix C: Dialogic Variable Operators vs Storyarn

| Dialogic | Storyarn | Notes |
|----------|----------|-------|
| `=` | `set` | Direct assignment |
| `+=` | `add` | Addition |
| `-=` | `subtract` | Subtraction |
| `*=` | (none) | Storyarn has no multiply |
| `/=` | (none) | Storyarn has no divide |
| n/a | `set_true` | Sugar for `= true` |
| n/a | `set_false` | Sugar for `= false` |
| n/a | `toggle` | Sugar for `= !var` |
| n/a | `clear` | Sugar for `= ""` |
| n/a | `set_if_unset` | Conditional set (needs if/set block) |
