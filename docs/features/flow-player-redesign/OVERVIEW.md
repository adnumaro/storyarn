# Flow Player Redesign — Vision & Audit

**Status:** vision doc, 2026-04-20. Captures the audit findings, competitive verification, corrected design principle, and phased rollout. Not committed to a timeline.

---

## 📖 Terminology (read first — prevents conflation)

Two distinct entities that must not be confused:

|                   | **Scene** (exploration tool, existing)                            | **Sequence** (flow tool, new)                         |
| ----------------- | ----------------------------------------------------------------- | ----------------------------------------------------- |
| Module            | `Storyarn.Scenes.Scene`                                           | `Storyarn.Flows.Sequence` (new)                       |
| What it is        | 2D walkable canvas with zones/pins                                | Grouping of flow nodes with shared atmosphere         |
| Fields            | width, height, zones, pins, connections, layers, background_asset | tracks (multi-track timeline), flow_id, start_node_id |
| Consumed by       | ExplorationPlayer                                                 | FlowPlayer                                            |
| User-facing label | "Scenes" (existing Scenes tool)                                   | "Sequences" (new, inside Flow editor)                 |

Adobe Premiere uses "Sequence" as the native term for multi-track timeline compositions — that's why this label fits the flow player feature.

**Earlier drafts (before 2026-04-20) proposed unifying them into a single `Storyarn.Scenes.Scene` entity. That was wrong and got explicitly rejected** — the two entities have different shapes and different consumers. Keep them separate.

---

## ⚠️ HANDOFF FOR NEXT SESSION (read first)

### Where we are (state as of handoff)

- ✅ P-1 shipped — `player.css` imported in `app.css` (commit `2a732b88`). Visual layer unblocked.
- ⏳ **Next: P-2 → P-3 → Premiere v1 → P-4.** Core design decisions are locked. Small judgment calls may surface mid-implementation — ask and re-align, don't barrel through.

### All design decisions locked (do NOT re-debate these)

1. **FlowPlayer ≠ ExplorationPlayer** — they're different products. Don't propose unifying them.
2. **Target audience = videogame teams first.** Articy/Yarn/Ink/Pixel Crushers are the competitors. Arcweave is a simplicity touchstone for the preview surface, NOT for the editor. Don't propose novelist-style simplifications.
3. **Sequence is a first-class entity inside a flow** (`Storyarn.Flows.Sequence`, new). NOT unified with `Storyarn.Scenes.Scene` — see the Terminology section above. The only shared concept is "coherent atmosphere"; the data shapes are different.
4. **Multi-track timeline inside a Sequence** — 3 fixed tracks: `background` (image asset), `music` (audio asset), `ambient` (audio asset). No video, no overlays, no SFX, no effects track in v1. No dynamic track management in v1. Rows are fixed; **clips within them are 100% editable** (drag, resize, delete, re-parent across rows). The 3 tracks map to the user's original ask: "una imagen que actuase de background (...) ambient + bg de fondo" plus a split between music and ambient audio.
5. **Timeline x-axis = node sequence** within the Sequence (not absolute seconds). Clips span `start_node_id → end_node_id`.
6. **Path-agnostic clips**: a clip on nodes 1-5 plays on ALL branches within that range. The Sequence's music is the Sequence's state, not the path's.
7. **Sequence membership via `sequence_directive` pointer on node data.** Node with directive = Sequence entry point. Nodes without directive inherit from upstream-most node with one along the actual execution path. Branching resolves at runtime, no static group-membership conflicts.
8. **Right-click "Create sequence from here"** = create Sequence entity, add directive to node, open Sequence editor. Canvas colors all downstream inheriting nodes as a visual region (badges 🎬 + colored border).
9. **Multi-sequence per flow** from v1. Branches from a Choice can go to different Sequences — shown as "🚪 Sequence: X [Open →]" markers at the edge of the source Sequence's timeline.
10. **Only static images + audio in v1.** Video on nodes is deferred future feature.
11. **Transitions in v1**: `cut` (default), `fade_black`, `fade_white`, `crossfade`. Duration configurable, default 500ms image / 1s audio.
12. **Delete `slug_line` node type entirely** (2026-04-20 decision, supersedes the earlier "drop `location_sheet_id`" plan). Its role (establishing location / time context) is fully covered by the Sequence entity + its tracks. User: _"slug_line ya no tiene valor. Probablemente hay que eliminarlo."_
13. **Drop `flow.scene_id` routing through FlowPlayer.** That field stays for ExplorationPlayer context only (pointing at a `Storyarn.Scenes.Scene`, not a Sequence).
14. ~~**Flatten Vue tree**: inline `PlayerSlide.vue` / `PlayerChoices.vue` / `PlayerOutcome.vue` as v-if branches inside `FlowPlayer.vue`.~~ **REJECTED 2026-04-20.** Flattening produced a ~260-line god component with 3 unrelated responsibilities (slide rendering / choices / outcome) — worse than the split. Keep `PlayerSlide.vue`, `PlayerChoices.vue`, `PlayerOutcome.vue` as separate files. Only `PlayerToolbar.vue` remains untouched as originally planned.

### Deferred — do NOT build unless explicitly requested

- **Project Templates** (`docs/features/project-templates/OVERVIEW.md`) — future-expansion lever when broadening beyond videogames.
- **Flags / Events system** (`docs/features/events-flags-system/OVERVIEW.md`) — can wait until there's a demonstrated need beyond variables + conditions.
- **Tables Tier 2** (`docs/features/tables-rule-engine/OVERVIEW.md`) — dynamic lookup, if/else, dice functions; big differentiator but not blocker.
- **Effects track** (flash, shake, zoom) — add in v2 when/if demand shows.
- **Dynamic tracks** (add/remove tracks) — v2.
- **Keyframes within clip** (volume ramp, opacity curves) — v2.
- **Screenplay feature** — gated to super-admin only for now; don't touch.

### Time estimates (Claude-cadence, calibrated)

Per `feedback_time_estimates_claude_cadence.md`: do NOT inflate. Realistic numbers:

| Step                                                                                                                                                                                            | Time            |
| ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | --------------- |
| **P-2** — single-column layout polish (flatten rejected, see point 14)                                                                                                                          | 0.5-1 h         |
| **P-3** — delete `slug_line` entirely + new `Storyarn.Flows.Sequence` entity + `sequence_directive` on executable nodes + "Create sequence from here" right-click with bottom-docked stub panel | 4-5 h           |
| **Premiere v1** — Sequence editor with 3 fixed tracks, drag/resize clips, transitions, Web Audio mix, CSS fades, canvas badges                                                                  | 4-6 h           |
| **P-4** — blinking arrow, force-assign vars in debug panel, jump-to-source                                                                                                                      | 2-3 h           |
| **Total**                                                                                                                                                                                       | **~1-1.5 days** |

### Files likely touched (quick orient)

**Frontend:**

- `assets/app/modules/flows/player/FlowPlayer.vue` (single-column layout polish — children stay as-is)
- `assets/app/modules/flows/player/Player{Slide,Choices,Outcome}.vue` (keep separate, flatten rejected)
- `assets/app/modules/flows/player/PlayerToolbar.vue` (keep as-is)
- New: `assets/app/modules/flows/sequences/SequenceTimelineEditor.vue` and track/clip subcomponents
- Probably extract: `composables/useWebAudioMix.ts` for audio track mixing
- `FlowDebugPanel.vue` for P-4 polish additions

**Backend:**

- `lib/storyarn/flows/sequence.ex` — **new** schema, fields: `name`, `flow_id`, `start_node_id`, `tracks` (map), timestamps
- Migration to create `flow_sequences` table
- `lib/storyarn_web/live/flow_live/nodes/{entry,dialogue,condition,instruction,hub,jump,subflow,exit}/node.ex` — add optional `sequence_directive` to node data defaults for all executable node types (not annotation).
- `lib/storyarn_web/live/flow_live/nodes/slug_line/` — **deleted** (the whole directory).
- `lib/storyarn_web/live/flow_live/player_live.ex` — resolve active Sequence via path walk
- `lib/storyarn_web/live/flow_live/player/slide.ex` — sequence directive resolution (slug_line build clause gone)

**Not touched:**

- `lib/storyarn/scenes/scene.ex` — exploration Scene is unchanged by this feature.

### How a fresh session should start

1. Read the Terminology callout + this handoff section.
2. Read the rest of this doc for full context.
3. Read the 4 related memory files: `project_flow_player_redesign_vision.md`, `project_target_audience_videogames_first.md`, `feedback_time_estimates_claude_cadence.md`, `feedback_creative_wide_competitive_scan.md`.
4. Start P-2. Surface any judgment-call uncertainty before coding — don't assume the doc has every answer.

---

## Why we're rethinking it

The Flow Player was visually broken (CSS orphaned — now fixed in commit `2a732b88`) and the underlying design had drifted from a clear model. User framing (translated from Spanish):

> **"Arcweave shines here because it's a simple system. Ours is complex. But we have to try to shine just as much through simplicity."**

## Critical distinction: FlowPlayer ≠ ExplorationPlayer

Earlier drafts of this doc proposed unifying the two players. That was wrong and the user corrected it explicitly (translated from Spanish):

> **"The FlowPlayer is about quick flow review (Arcweave, Articy:draft, the whole competition). This is what everyone else has. For testing decision trees or flows."**
>
> **"The ExplorationPlayer is something completely different. It's for prototyping videogames, interactive maps — Articy:draft's `scene` concept, essentially. Nobody else has this because it's like a mini 2D game engine."**

|                    | **FlowPlayer**            | **ExplorationPlayer** |
| ------------------ | ------------------------- | --------------------- |
| What it prototypes | A story: film, book, play | An interactive game   |
| Player character?  | No — static advancement   | Yes — walks around    |
| Triggers scenes?   | Never                     | Yes, by location/zone |
| Ambient flows      | Irrelevant                | Core mechanic         |
| Composition unit   | **Sequence** (new)        | **Scene** (existing)  |
| Competitors        | All have this             | **No one** has this   |
| Storyarn role      | Parity with market        | Unique moat           |

> **"You should be able to prototype a film, a book, or a stage play here. No players, no game prototyping — but yes to story prototyping."**

**Consequence:** `flow.scene_id`, `ambient_flows`, and exploration machinery stay on the ExplorationPlayer side. The FlowPlayer never uses them. The FlowPlayer uses its own `Sequence` entity, which is separate from the exploration `Scene`.

## Target audience (fundamental context)

Target = **videogame design teams**. Not novelists. Not screenwriters. User's framing (translated from Spanish):

> **"This platform is initially aimed at videogames, and that's how we'll market it. Later I want to expand the target as much as possible — videogames alone is too niche."**

This changes the reference set. Direct competitors = **Articy:draft X, Yarn Spinner, Ink, Pixel Crushers Dialogue System**. Arcweave is a simplicity touchstone but not a feature benchmark — it targets interactive fiction authors, not game teams. Target users expect richer chrome: timeline editors, multi-track audio, keyboard shortcuts, Unity-familiar patterns.

Consequence: progressive disclosure / Project Templates is **demoted to "future expansion lever"** — not a blocker for shipping complexity. Target users want advanced features visible.

## Design principle for FlowPlayer

> **"My idea is the Arcweave one. In Arcweave you can even put videos on nodes (I don't want that yet, but it could be a future feature)."**

The preview surface stays minimalist (single reading column) — players see a clean story. The **editor** surface is where richer authoring tools live (multi-track timeline, asset pickers, transitions).

Separation: **preview = Arcweave-clean for readers; editor = game-dev-pro for authors.** Matches Unity (Scene view clean, Timeline window dense).

### Target layout

```
┌──────────────────────────────────────┐
│ [←]  flow name           [🐛] [⚙]  │  editor-only chrome (role-gated)
├──────────────────────────────────────┤
│                                      │
│        ╔════════════════╗            │
│        ║     image      ║            │  ← Sequence's `background` track clip
│        ╚════════════════╝            │     (optional, centered, rounded)
│                                      │
│   Current beat text                  │  ← dialogue text / slug heading
│                                      │
│   [ choice 1 ]                       │
│   [ choice 2 ]                       │  ← choices (Arcweave style)
│                                      │
│   or: ↓  (blinking arrow)            │  ← single-exit auto-advance
└──────────────────────────────────────┘
```

If no Sequence is active (or the active Sequence has no `background` clip at this node), the image block is simply omitted. Minimal flow → minimal player.

## Node types visible in the player

Verified in `lib/storyarn_web/live/flow_live/player/slide.ex`:

- **`dialogue`** → `:dialogue` slide (speaker + text).
- **`exit`** → `:outcome` card (end screen with stats, restart).

All other node types (`condition`, `instruction`, `hub`, `jump`, `subflow`, `entry`, `annotation`) are pass-through — the engine steps past them and the viewer never sees them. (`slug_line` was deleted entirely in 2026-04-20 — see HANDOFF point 12.)

## Sequence model (the core design decision)

After several iterations, the model that survived:

**Sequence is a first-class entity inside a flow.** It has a multi-track timeline for media and effects composition. A node can carry an optional `sequence_directive: sequence_id` — when execution reaches that node, the Sequence's composition becomes active and stays active until a different Sequence directive is hit downstream.

### Multi-track timeline inside a Sequence

Inspired by Adobe Premiere (user showed a screenshot to align vocabulary — and "Sequence" is literally Premiere's native term for a timeline composition). Key insight: it's not "one image + one audio" per node. It's **parallel layered tracks**. v1 deliberately ships just 3 to cover the stated requirement ("imagen de fondo + ambient"):

- `background` (image asset — the static scene the player sees)
- `music` (audio asset — score / theme, typically changes between Sequences)
- `ambient` (audio asset — wind, hall tone, rain; persists longer)

**Deferred to v2 or later** (only when demand shows):

- Video overlay (fog, light effects, UI overlays)
- SFX (one-shot sounds: door open, impact)
- Effects (fade_in, shake, flash — one-shot, attached to a node)
- Video on clips (static images only in v1)

Each clip on each track covers a range of nodes (not seconds). Clips on different tracks overlap — that's the layering.

### Timeline "time" = node sequence

The x-axis is the flow's node path within the Sequence, not absolute seconds. A clip that spans `start_node_id = 3, end_node_id = 7` plays continuously while the player visits any node between 3 and 7 in the execution path.

### Branching is solved by "path-agnostic clips"

Clips apply to **all paths** within the Sequence. The music in "Castle Throne" Sequence sounds the same whether the player goes down branch A or branch B — it's the Sequence's state, not the path's state. If a clip is on a node that only appears in branch B, that clip only activates when the player takes B.

### Sequence membership via directive inheritance

Each node has an optional `sequence_directive` that points to a Sequence. Nodes without a directive inherit from the upstream-most node with one on the actual execution path. This:

- Handles branching without multi-parent conflicts (runtime resolves by path, not by static membership)
- Requires no "group" entity that breaks when edges change
- Lets the canvas show colored regions per Sequence (computed from directive placement)

### Schema

```elixir
# Sequence entity (new — lives in lib/storyarn/flows/sequence.ex)
schema "flow_sequences" do
  field :name, :string
  field :tracks, :map  # nested: %{"background" => [clips], "music" => [clips], "ambient" => [clips]}
  belongs_to :flow, Storyarn.Flows.Flow
  belongs_to :start_node, Storyarn.Flows.FlowNode  # the node the author right-clicked to create this
  timestamps(type: :utc_datetime)
end

# Clip shape (stored inside the tracks map — no separate table)
%{
  asset_id: id | nil,
  start_node_id: id,
  end_node_id: id | nil,  # nil = until Sequence end
  volume: 1.0,            # opacity for video
  transition_in: "cut" | "fade_black" | "fade_white" | "crossfade",
  effect_params: %{}
}

# Node data (JSONB) gains an optional pointer
"sequence_directive" => sequence_id | nil
```

### Author UX

1. Right-click a node in the flow canvas → **"Create sequence from here"**.
2. Sequence entity is created; node gains a `sequence_directive` pointing to it.
3. Sequence editor opens — multi-track timeline editor (Premiere-style, game-dev-dense feel).
4. Author adds clips, effects, transitions.
5. Back in the canvas, all forward-reachable nodes inheriting this directive are colored as a region. Clear visual groupings without `group` as an entity.

### Sidebar scene selector (inside a Sequence editor)

Inside a Sequence editor, a sidebar lists all Sequences of the flow so the author can hop between them without leaving the editor:

```
┌─ Sequences in "Main Flow" ─┐
│ ● Castle Throne Room       │ ← you are here
│ ○ Outside Courtyard        │
│ ○ Dungeon Cell             │
│ + New sequence             │
└────────────────────────────┘
```

### Cross-Sequence branches — "doors"

When a branch from the current Sequence exits to a different Sequence, it appears as a marker at the edge of the timeline next to the branching node: **"🚪 Sequence: X [Open →]"**. Click → navigates to that Sequence's editor.

## MVP scope

Per user agreement (2026-04-20): go for the full path, not the minimal one. Realistic estimate is ~1.5-2 days, not weeks.

- **P-2** (~0.5-1 h): single-column layout polish. Subcomponents (`PlayerSlide`/`PlayerChoices`/`PlayerOutcome`) stay separate — flatten was tried and rejected.
- **P-3** (~4-5 h): delete `slug_line` node type entirely. New `Storyarn.Flows.Sequence` entity + `sequence_directive` on all executable node types (entry, dialogue, condition, instruction, hub, jump, subflow, exit — not annotation) + multi-track schema (2 video + 3 audio tracks fixed). UI to create Sequence from node (menu item + handler + bottom-docked stub panel, NOT a redirect to a new page).
- **Premiere v1** (~4-6 h): multi-track Sequence editor (drag clips, resize, transitions). Player processes parallel cues. Basic transitions (cut, fade_black, fade_white, crossfade).
- **P-4** (~2-3 h): polish — blinking arrow for single-exit, force-assign vars in debug panel, jump-to-source, canvas badges 🎬 + colored regions.

**Out of v1:**

- Effects track (flash, shake, zoom) — v2 if demand
- Dynamic track management — v2
- Keyframes within clips (e.g. volume fading across a clip) — v2
- Video on clips — future (user flagged)

## Data model cleanup included in redesign

- **Delete `slug_line` node type entirely.** Its role (establishing location / time context) is fully covered by the Sequence entity + its tracks. Data migration removes any existing slug_line nodes; flow_connections cascade via `ON DELETE CASCADE`.
- **Stop routing `flow.scene_id` through the FlowPlayer.** `scene_id` stays as the ExplorationPlayer's context field unambiguously. FlowPlayer uses the new Sequence entity, which lives inside a flow.
- ~~**Flatten the Vue component tree.** Inline `PlayerSlide.vue`, `PlayerChoices.vue`, `PlayerOutcome.vue` as v-if branches inside `FlowPlayer.vue`.~~ **REJECTED 2026-04-20** — inlining produced a ~260-line god component. Keep the split. `PlayerToolbar.vue` also stays as-is.

## Competitive verification (April 2026, live web search)

### Arcweave's three wins (the simplicity benchmark)

1. **Role-gated chrome, not mode-gated.** Viewers see only cover/text/buttons. Editors see the same + a bug icon top-right that opens an additive debug panel. No "switch to Debug view" modal.
2. **Single centered column.** No sidebars, no mini-map, no node IDs. Attention budget on the story.
3. **Blinking-arrow fallback for single-exit nodes.** When there's one way forward, render a pulsing arrow; whole screen clickable. Removes visual weight from ~70% of nodes in a typical linear-with-branches flow.

### Anti-patterns to avoid

- **"Play" vs "Test" two-button modes** (Twine) → users pick wrong, "variables don't work".
- **Debug UI in the reading column** (SugarCube default debug bar; Articy red-highlighted failed conditions on the slide) → distracts viewers, editors stop noticing.
- **Modal variable inspectors** (SugarCube `<<checkvars>>`) → blocks flow; can't stay open while playing.
- **No jump-to-source from the player** (Yarn preview, Dialogic play) → authors need one click back to the node.
- **State loss on recompile** (most engine-embedded previews) → Inky's fast-forward solves it; copy it.
- **"PowerPoint slide" feel** (Articy Presentation View) → authors subconsciously slow down; reading should feel like a game, not a deck.

## Phased rollout

| Phase           | Scope                                                                                                                                                                                                                                                                                                       | Size    | Status        |
| --------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------- | ------------- |
| **P-1**         | Import `player.css` in `app.css`.                                                                                                                                                                                                                                                                           | 5 min   | ✅ `2a732b88` |
| **P-2**         | Single-column layout polish on `FlowPlayer.vue`. Subcomponents stay separate (flatten rejected — see point 14 in HANDOFF).                                                                                                                                                                                  | 0.5-1 h | pending       |
| **P-3**         | Delete `slug_line` entirely. New `Storyarn.Flows.Sequence` entity + `sequence_directive` on all executable node types (entry, dialogue, condition, instruction, hub, jump, subflow, exit). Minimum UI: right-click "Create sequence from here" + bottom-docked stub panel (same pattern as FlowDebugPanel). | 4-5 h   | pending       |
| **Premiere v1** | Sequence editor: 3 fixed tracks (`background`, `music`, `ambient`), drag/resize clips, transitions, Web Audio mix, CSS fades. Player runtime processes parallel cues.                                                                                                                                       | 4-6 h   | pending       |
| **P-4**         | Blinking-arrow for single-exit, force-assign vars in debug panel, jump-to-source, canvas 🎬 badges + colored regions.                                                                                                                                                                                       | 2-3 h   | pending       |

## Non-goals

- Don't turn the player into a three-panel IDE (Articy trap).
- Don't split "Play" and "Test" into different buttons (Twine anti-pattern).
- Don't dock debug UI inside the reading column.
- Don't unify FlowPlayer and ExplorationPlayer. They solve different problems.
- Don't unify `Storyarn.Scenes.Scene` (exploration) with `Storyarn.Flows.Sequence` (flow composition). Different shapes, different consumers.
- Don't use `flow.scene_id` or exploration Scenes as a backdrop for FlowPlayer. Sequences are the mechanism.

## Primary competitive sources (verified 2026-04-20)

- Arcweave: docs.arcweave.com/project-tools/play-mode/overview, /using-play-mode; blog.arcweave.com/write-your-interactive-story-with-arcweave.
- Articy: articy.com/help/adx/Presentation_Journeys.html, /Presentation_Simulation.html.
- Ink/Inky: github.com/inkle/inky; github.com/inkle/ink-unity-integration/blob/master/Documentation/InkPlayerWindow.md.
- Yarn Spinner: yarnspinner.dev/features.
- Twine/SugarCube: catn.decontextualize.com/twine; motoslave.net/sugarcube/2/docs.
- Dialogic 2: docs.dialogic.pro/getting-started.
- Naninovel: naninovel.com/guide/editor.
