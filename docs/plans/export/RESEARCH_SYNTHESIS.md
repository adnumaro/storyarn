# Export Research Synthesis

> **Date:** February 24, 2026
>
> **Purpose:** Consolidated findings from 6 parallel research agents covering the full game engine and narrative middleware landscape.

---

## Executive Summary

**Key strategic discovery:** Middleware narrative formats (Ink, Yarn) provide dramatically better coverage-per-effort than engine-specific exports. A single Ink export reaches 13+ engine runtimes (~90% of game developers), while three engine-specific exports (Unity + Godot + Unreal) reach ~84%. Ink has **3x better effort-to-reach ratio**.

**Recommended priority change:** Insert Ink and Yarn Spinner as high-priority formats between Storyarn JSON and engine-specific exports. This gives Storyarn immediate cross-engine value with minimal implementation effort.

**AAA engines are dead ends:** REDengine, CryEngine, Infinity Engine, Frostbite, Divinity Engine — all either legacy, proprietary, or migrating to UE5. Supporting Unreal Engine 5 covers the entire AAA market.

---

## Market Analysis by Engine

### Tier 1: High Priority (Large + Growing)

| Engine     | Market Share                             | Indie Relevance                                   | Narrative Tooling Gap                                                 | Priority   |
|------------|------------------------------------------|---------------------------------------------------|-----------------------------------------------------------------------|------------|
| **Godot**  | 5% of Steam games (2024), 69% YoY growth | Extremely high — free, open source, indie darling | High — articy plugin is Beta, no mature external tool exports         | **1**      |
| **Unity**  | ~43% of game jam submissions             | High — still dominant, but trust damaged          | Medium — DSfU is mature but $75; articy free tier caps at 700 objects | **2**      |
| **Unreal** | Dominant for AA/AAA                      | Medium — growing indie adoption (3.5% royalty)    | High — articy v3 importer entering EOL, no good alternatives          | **3**      |

### Tier 2: Niche but Accessible

| Engine          | Users                       | Ease of Export                                  | Priority                  |
|-----------------|-----------------------------|-------------------------------------------------|---------------------------|
| **Ren'Py**      | 23k+ visual novels on VNDB  | 9/10 — .rpy is plain text, trivial to generate  | **Low** (covered by Ink)  |
| **GameMaker**   | Indie staple (A Short Hike) | Covered by Yarn (Chatterbox plugin)             | **Low** (covered by Yarn) |
| **GDevelop**    | Growing open-source 2D      | Covered by Yarn (bondage.js built-in)           | **Low** (covered by Yarn) |
| **Construct 3** | Browser-based 2D            | No standard format, JSON via AJAX               | **Very low**              |
| **RPG Maker**   | Niche RPG community         | Complex internal format, needs companion plugin | **Very low**              |

### Tier 3: Dead Ends (Do NOT Support)

| Engine                         | Reason                                                                   |
|--------------------------------|--------------------------------------------------------------------------|
| **REDengine** (CD Projekt RED) | Being abandoned. CDPR moving to UE5 for Witcher 4 and all future titles. |
| **CryEngine**                  | Negligible user base. Poor narrative tools. Not worth the effort.        |
| **Infinity Engine**            | Fully legacy (Baldur's Gate era, 20+ years old). Modding only.           |
| **Divinity Engine** (Larian)   | Internal only. Being replaced for future titles.                         |
| **Source 2** (Valve)           | Not used for narrative games.                                            |
| **Frostbite** (EA)             | Proprietary. RPG studios (BioWare) fleeing to UE5.                       |
| **Creation Engine** (Bethesda) | Interesting modding community but extremely complex, niche.              |

**Conclusion:** Supporting UE5 covers the entire AAA market. No other AAA engine is worth targeting.

---

## Narrative Middleware Analysis

### Ink (by Inkle) — Highest ROI Export Target

- **GitHub stars:** 4,600+
- **Runtimes:** 13+ implementations — C#, JavaScript, C++, Rust, Lua, GDScript, Java, Kotlin, GameMaker, Swift, Haxe, Unreal (C++), and more
- **Notable games:** 80 Days, Heaven's Vault, Sable, Citizen Sleeper, A Highland Song
- **Format:** `.ink` text files compile to `.ink.json` runtime format ([well-documented spec](https://github.com/inkle/ink/blob/master/Documentation/ink_JSON_runtime_format.md))
- **Key insight:** Exporting to Ink JSON format means any engine with an Ink runtime can import Storyarn projects. This is ~90% of active game developers.

**Storyarn → Ink mapping complexity:** Medium. Ink's model (knots, stitches, choices, diverts, tunnels) is well-documented but structurally different from Storyarn's graph model. Conditions use `{condition:}` syntax. Variables are global. Hub/Jump map to labels/diverts. The main challenge is flattening graph structure into Ink's linear-with-diverts model.

### Yarn Spinner — Second Highest ROI

- **GitHub stars:** 2,700+
- **Runtimes:** Unity (official), Godot (beta), upcoming Unreal
- **Also works in:** GameMaker (via Chatterbox), GDevelop (via bondage.js)
- **Format:** `.yarn` text files with header metadata + body
- **Localization:** Built-in line tags for string extraction
- **Notable:** Created by the Night in the Woods team

**Storyarn → Yarn mapping complexity:** Low-Medium. Yarn's model (nodes with titles, `<<jump>>`, `<<if>>`, options with `->`) maps fairly directly to Storyarn flows. Variables use `$` prefix. Commands use `<<>>` syntax. Simpler than Ink.

### articy:draft X — Competitor & Interop Target

- **Pricing:** EUR 6.99/month, free tier limited to 700 objects
- **Mac version:** Launched April 2025
- **Unreal importer:** v3 entering end-of-life (won't support UE beyond 5.5) — **opportunity for Storyarn**
- **Godot plugin:** Beta quality, not production-ready
- **Key gap:** articy has NO screenplay editor, NO scene/world builder, NO Ink/Yarn export

### Arcweave — Closest Web Competitor

- **Model:** Browser-based, real-time collaborative
- **Free plugins:** Unity, Unreal, Godot
- **Key gaps:** No screenplay editor, no scene/world builder, no Ink/Yarn export
- **Storyarn advantage:** Full creative suite (flows + sheets + scenes + screenplays + localization)

---

## Per-Engine Deep Dive

### Godot Ecosystem (Detailed)

**Dominant addons:**
1. **Dialogic 2** (~5.2k stars, Alpha, MIT) — Most feature-rich. Uses `.dtl` timeline format (custom text DSL, NOT JSON) and `.dch` character resources.
2. **Dialogue Manager** (~3.3k stars, Stable, MIT) — Lightweight, code-driven. Uses `.dialogue` format. Stateless — references game autoloads for variables.

**Dialogic .dtl format highlights:**
```
Emilio: Hello and welcome!
- Yes
    Emilio: Great!
- No
    Emilio: Oh no...
- Maybe | [if {Stats.Charisma} > 10]
    Emilio: Interesting...
```
- Line-oriented, TAB-indentation for scope
- Variables in `{curly brackets}`, folders with dots: `{Stats.Health}`
- GDScript operators for conditions: `==`, `!=`, `<`, `>`, `and`, `or`
- Labels and jumps: `label MyLabel` / `jump MyLabel`
- Shortcodes for events: `[background path="res://..."]`

**Ink/Yarn on Godot:**
- **GodotInk** (C# runtime) — stable, but requires .NET Godot (many indies avoid C#)
- **InkGD** (pure GDScript) — feature-complete but slower, used in commercial games
- **Yarn Spinner for Godot** — Beta, requires C#

**Localization:** Godot natively supports CSV and Gettext (.po) translation imports.

**Key decisions for Storyarn:**
- Generic JSON is universally parseable (no addon required)
- Dialogic .dtl is the highest-value addon-specific format
- Do NOT generate `.dch` or `.tres` resources (Godot-internal format)
- CSV localization export maps directly to Godot's translation system

### Unity Ecosystem (Detailed)

**Dominant plugin:** Dialogue System for Unity (DSfU) by PixelCrushers — $75, 5-star rating, stable JSON import format.

**DSfU JSON structure:**
- `actors[]` with custom `fields{}`
- `conversations[]` → `dialogueEntries[]` with `conditionsString` (Lua) and `userScript` (Lua)
- `variables[]` with typed initial values
- Variable access: `Variable["mc.jaime.health"]`
- Not-equal: `~=` (Lua-specific)
- Logic: `and` / `or`
- Localization: Separate CSV per language

**Ink/Yarn on Unity:**
- Ink: First-class support (Inkle's own C# runtime)
- Yarn Spinner: Official Unity integration, most popular free alternative to DSfU

### Unreal Ecosystem (Detailed)

**Standard import method:** DataTable CSV mapped to `FTableRowBase` C++ structs.

**Key plugins:**
- **Narrative** (by Reubs) — 2,000+ customers, most popular UE dialogue plugin
- **DlgSystem** — JSON import/export, open-source
- **FlowGraph** (MothCocoon) — Most architecturally similar to Storyarn

**articy:draft on Unreal:** Generates C++ classes from project structure (heavy compilation approach). v3 importer entering EOL — won't support UE beyond 5.5. **This is an opportunity** for Storyarn to offer a lighter runtime-data approach.

**Localization:** StringTable CSV format + PO files for native pipeline.

**Multi-file output required:** ZIP with DialogueLines.csv, Conditions.csv, Instructions.csv, DialogueMetadata.json, Character DataTable, Variable DataTable, StringTable CSVs.

---

## Updated Export Priority (Research-Informed)

### Before Research (Original Plan)

```
1. Storyarn JSON (native round-trip)
2. Unity DSfU JSON
3. Godot Dialogic JSON
4. Unreal DataTable CSV
5. articy:draft XML
```

### After Research (Recommended)

```
Phase A: Foundation (unchanged)
  1. Storyarn JSON (native round-trip) — lossless backup, prerequisite for all

Phase B: Expression Transpiler (unchanged, but add Ink/Yarn emitters)
  2. Structured condition/assignment transpiler
  3. Code-mode parser + per-engine emitters (Ink, Yarn, Lua, GDScript, Unreal, articy)

Phase C: Middleware Formats (NEW — highest ROI)
  4. Ink export (.ink text)        — 1 format → 13+ runtimes → ~90% of devs
  5. Yarn Spinner export (.yarn)   — covers Unity, Godot, GameMaker, GDevelop

Phase D: Engine-Specific Formats (reordered by indie priority)
  6. Unity DSfU JSON               — dominant paid plugin, mature format
  7. Godot Dialogic .dtl           — dominant Godot addon, growing fast
  8. Godot generic JSON            — fallback for non-Dialogic users
  9. Unreal DataTable CSV + JSON   — standard UE import path

Phase E: Interoperability
  10. articy:draft XML export      — for articy users migrating to Storyarn
  11. articy:draft XML import      — parse articy projects into Storyarn

Phase F: Niche Formats (future, trivial effort)
  12. Ren'Py .rpy                  — plain text, trivial generator
  13. Godot Dialogue Manager .dialogue — #2 Godot addon, simple format
  14. CSV localization bundle       — universal, works with any engine

Phase G: Scale + API (unchanged)
  15. Oban background processing
  16. REST API endpoints
```

### Effort-to-Reach Analysis

| Format               | Implementation Effort | Developer Reach                   | Effort-to-Reach Ratio   |
|----------------------|-----------------------|-----------------------------------|-------------------------|
| Storyarn JSON        | Medium (one-time)     | 100% (backup)                     | Prerequisite            |
| **Ink (.ink)**       | **Medium**            | **~90% (13+ runtimes)**           | **Best**                |
| **Yarn (.yarn)**     | **Low-Medium**        | **~40% (Unity, Godot, GM, GDev)** | **Excellent**           |
| Unity DSfU JSON      | Medium                | ~35% (Unity DSfU users)           | Good                    |
| Godot Dialogic .dtl  | Medium                | ~15% (Godot Dialogic users)       | Good                    |
| Unreal DataTable CSV | Medium-High           | ~15% (Unreal users)               | Fair                    |
| articy XML           | High                  | ~5% (articy users)                | Low (but strategic)     |
| Ren'Py .rpy          | Very Low              | ~5% (VN developers)               | Excellent (trivial)     |

---

## Competitive Positioning

### What Storyarn Offers That Nobody Else Does

| Feature                 | Storyarn   | articy:draft   | Arcweave   | Ink/Yarn (standalone)   |
|-------------------------|------------|----------------|------------|-------------------------|
| Visual flow editor      | Yes        | Yes            | Yes        | No (text only)          |
| Sheet/entity system     | Yes        | Yes            | Partial    | No                      |
| Screenplay editor       | Yes        | No             | No         | No                      |
| Scene/world builder     | Yes        | No             | No         | No                      |
| Localization pipeline   | Yes        | Yes            | No         | Partial                 |
| Real-time collaboration | Yes        | No             | Yes        | No                      |
| Ink/Yarn export         | Planned    | No             | No         | Native                  |
| Web-based               | Yes        | Desktop only   | Yes        | N/A                     |
| Free tier               | TBD        | 700 objects    | Limited    | Free (open source)      |

### Market Gap

No existing tool combines visual flow editing + screenplay + world building + localization + export to open standards (Ink/Yarn). articy:draft is the closest competitor but lacks screenplays, scenes, Ink/Yarn export, web access, and real-time collaboration. The articy Unreal importer entering EOL creates a window of opportunity.

---

## Per-Format Implementation Notes

### Ink (.ink) — Key Challenges

1. **Graph → Linear conversion:** Storyarn flows are directed graphs; Ink is linear with diverts. Need to topologically sort nodes and insert diverts for non-linear paths.
2. **Hub/Jump → Labels/Diverts:** Direct mapping. Hubs become `= label_name`, Jumps become `-> label_name`.
3. **Conditions:** `{condition:}` inline or `{- condition: content}` for gathering choices.
4. **Variables:** Global, declared with `VAR name = value`. Storyarn's dot notation needs flattening: `mc.jaime.health` → `mc_jaime_health` (Ink doesn't allow dots in variable names).
5. **Responses with conditions:** `+ {condition} Choice text` for conditional choices.
6. **Subflows:** Ink tunnels (`->->`) or threads (`<- thread_name`).
7. **Localization:** Ink has no built-in localization. Export separate string tables alongside .ink file.

### Yarn (.yarn) — Key Challenges

1. **Format:** Header + body per node. Headers include `title:` and optional metadata.
2. **Branching:** `-> NodeTitle` for jumps, `<<jump NodeTitle>>` for explicit jumps.
3. **Conditions:** `<<if $variable == value>>` / `<<elseif>>` / `<<else>>` / `<<endif>>`
4. **Variables:** `$` prefix, `<<set $variable to value>>`, `<<declare $variable = default_value>>`
5. **Responses:** Lines starting with `->` are options.
6. **Localization:** Built-in line tags `#line:id` for string extraction. Export `.csv` string tables.
7. **Commands:** `<<command>>` for custom game actions.

### Dialogic .dtl — Key Challenges

1. **Text-based DSL:** NOT JSON. Must generate properly indented plain text.
2. **Character references:** Filename-based (character name must match `.dch` filename).
3. **Variable folders:** `{Folder.Variable}` — map Storyarn `sheet.variable` to Dialogic folders.
4. **No `.dch` generation:** Character resources are Godot-internal. Provide JSON sidecar for character data.
5. **Conditions:** GDScript expressions in `[if {condition}:]` blocks.
6. **Labels/Jumps:** `label LabelName` / `jump LabelName` or `jump Timeline/Label`.

### Ren'Py .rpy — Trivial Generator

1. **Format:** Pure Python-like indented text.
2. **Characters:** `define character_name = Character("Display Name")`
3. **Dialogue:** `character_name "Dialogue text here"`
4. **Choices:** `menu:` with indented options
5. **Conditions:** `if condition:` / `elif:` / `else:` (Python syntax)
6. **Variables:** `$ variable = value` (Python assignment)
7. **Jumps:** `jump label_name` / `call label_name`

---

## Recommendations Summary

1. **Add Ink and Yarn as Phase C** (before engine-specific formats) — highest ROI
2. **Keep Phase A and Phase B unchanged** — foundation must come first
3. **Reorder Phase D** to prioritize Godot over Unreal (indie-first strategy)
4. **Drop AAA engine research** — UE5 export covers everything; no need for CryEngine, REDengine, etc.
5. **Add Ren'Py as a future "quick win"** — trivial to implement, captures VN market
6. **Import articy:draft remains strategic** — many potential users are currently on articy
7. **Expression transpiler needs 2 more emitters** — Ink syntax and Yarn syntax (in addition to Lua, GDScript, Unreal, articy)
