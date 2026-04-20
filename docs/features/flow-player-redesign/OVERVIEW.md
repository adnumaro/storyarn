# Flow Player Redesign — Vision & Audit

**Status:** vision doc, 2026-04-20. Captures the audit findings, competitive verification, design principle, and phased rollout for rethinking the Flow Player. Not committed to a timeline.

## Why we're rethinking it

The Flow Player is visually broken (symptom: CSS orphaned; root cause: design drifted from a clear model). The user's framing quote:

> **"Arcweaver brilla aquí porque es un sistema bastante simple. Nosotros tenemos un sistema complejo. Pero hay que tratar de brillar igual por simplicidad."**

Goal: keep Storyarn's richer model (scenes, slug_line, tables, screenplays) while the authoring/preview surface feels as clean as Arcweave's Play Mode.

## Immediate bug (independent of redesign)

`assets/css/player.css` exists with complete styles for `.player-layout`, `.player-toolbar`, `.player-choices`, etc. **It is never imported.**
- Not in `assets/css/app.css` (Tailwind + tw-animate-css + katex only).
- Not in `vite.config.mjs` inputs.

Fix: add `@import "player.css";` to `assets/css/app.css`. One line. Unblocks the visual layer regardless of what else we change.

## What's actually structural (not cosmetic)

Three real architectural issues live in the player surface. All are rooted in the code (file paths cited).

### 1. Scene ↔ Flow dual ownership

`Flow` has a direct `scene_id` FK (`lib/storyarn/flows/flow.ex:65`). `Flows.resolve_scene_id/1` walks flow → caller → parent (`lib/storyarn/flows/flows.ex:198-199`). In parallel, **`SceneAmbientFlow` links flows to scene zones** and `ExplorationLive` loads scenes to find their flows independently. Two mental models for the same pairing: "Is the flow attached to the scene, or is the scene providing context to the flow?"

### 2. `slug_line` has a data model that the player ignores

`lib/storyarn_web/live/flow_live/nodes/slug_line/node.ex` carries `location_sheet_id`. The player treats it as flavor text ("INT. CAFÉ — MORNING") and auto-advances (`PlayerLive.show_continue?/1`, `Slide.build/1`). **The backdrop never changes when a slug_line is hit.** The `location_sheet_id` data is collected but unused at runtime. Three possible semantics:
- (a) Flavor only → remove `location_sheet_id`, simplify.
- (b) **Location context setter → sync backdrop from location_sheet → scene** (*recommended*).
- (c) Exploration trigger → navigate to scene. Likely confusing; blurs with scenes.

### 3. FlowPlayer and ExplorationPlayer are parallel code paths

Both reuse `PlayerEngine.step_until_interactive` and `Slide.build` (good). But `PlayerLive` and `ExplorationLive` each own their own state, events (`continue`, `choose_response` duplicated), and render paths. Bug fixes in one don't necessarily propagate. Vue side is over-split: FlowPlayer + PlayerSlide + PlayerChoices + PlayerOutcome + PlayerToolbar for what is conceptually **one screen**.

## Competitive verification (April 2026)

Validated via live web search (not training data) on arcweave.com, articy.com, inkle/ink, docs.yarnspinner.dev, motoslave.net/sugarcube, docs.dialogic.pro, naninovel.com. Full citations in the session memory `project_flow_player_redesign_vision.md`.

### Arcweave's three wins (the simplicity benchmark)

1. **Role-gated chrome, not mode-gated.** Viewers see only cover / text / buttons. Editors see the same plus a bug icon top-right that opens an additive debug panel. No "switch to Debug view" modal.
2. **Single centered column.** No sidebars, no mini-map, no node IDs. Attention budget spent on the story, not the tool.
3. **Blinking-arrow fallback for single-exit nodes.** When there's one way forward, render a pulsing arrow; the whole screen is clickable. Removes visual weight from ~70% of nodes in a typical linear-with-branches flow.

### Anti-patterns to avoid (observed in the competition)

- **"Play" vs "Test" two-button modes** (Twine) → users pick the wrong one and "variables don't work".
- **Debug UI in the reading column** (SugarCube default debug bar; Articy red-highlighted failed conditions on the slide itself) → writers-in-review get distracted; editors stop noticing.
- **Modal variable inspectors** (SugarCube `<<checkvars>>`) → blocks flow, can't stay open while playing.
- **No jump-to-source from the player** (Yarn preview, Dialogic play) → when a branch is wrong, author needs a click back to the node.
- **State loss on recompile** (most engine-embedded previews) → Inky's fast-forward-to-last-node solves this; copy it.
- **"PowerPoint slide" feel** (Articy Presentation View) → authors subconsciously slow down; reading should feel like a game, not a deck.

## Design principle (one rule)

**The reading column never changes shape between dialogue and exploration. The stage swaps content; the chrome stays identical.**

This is how we unify dialogue-only flows and scene/exploration flows without falling into Articy's multi-panel console.

## Target layout

```
┌────────────────────────────────────────┐
│ [←] flow name              [🐛] [⚙]  │  editor-only chrome (role-gated)
├────────────────────────────────────────┤
│                                        │
│         [   STAGE   ]                  │  polymorphic by node type:
│                                        │  • dialogue → speaker + line + portrait
│                                        │  • slug_line → location/time card
│                                        │  • scene context → Konva canvas inline
│                                        │    (pins clickable, zones = regions)
│                                        │  • outcome → end card
│                                        │  • condition/instruction → invisible
│                                        │    to viewer; ghost card for editor
│                                        │
├────────────────────────────────────────┤
│   [ option 1 ]                         │  unified action row:
│   [ option 2 ]                         │  • dialogue responses
│   [ option 3 ]                         │  • pin labels
│                                        │  • hub exits
│   or: ↓ (blinking arrow)               │  single-exit → Arcweave-style arrow
└────────────────────────────────────────┘
```

**Debug panel**: slides in from the right, editor-only, closed by default.
- Variables tab: `initial / previous / current` columns + force-assign (reuse the debug panel's variables tab — already shipped).
- Trace tab: visited-node list, click to rewind, `↗` icon for jump-to-source.

**No "Play" vs "Test"**: one Play button; debug is a toggle on the player, not a separate mode.

## Proposed phases

| Phase | Scope | Size |
|---|---|---|
| **P-1** | Import `player.css` in `app.css`. Unblocks visual regardless of redesign. | 5 min |
| **P-2** | Rewrite `FlowPlayer.vue` to single-column layout. Flatten Vue tree: inline `PlayerSlide` / `PlayerChoices` / `PlayerOutcome` as v-if branches. Keep `PlayerToolbar.vue` (reused in exploration). | 2-3 h |
| **P-3** | Decide slug_line semantics (recommend: location context setter). Sync backdrop from `location_sheet_id` → scene. Document the decision in CLAUDE.md conventions. | 4 h |
| **P-4** | Blinking-arrow for single-exit nodes. Force-assign in debug panel. Jump-to-source from trace. | 1 day |
| **P-5** | Unify scene↔flow resolver (pick canonical ownership). Unify FlowPlayer + ExplorationPlayer Vue into one component with pluggable stage. | 2 days |

## Pending decisions the user must confirm before P-3+

1. **slug_line semantics**: flavor-only / backdrop-setter (recommended) / exploration-trigger.
2. **scene↔flow canonical ownership**: `flow.scene_id` primary with `ambient_flows` as exploration-only overlay (recommended), or flip.
3. **Debug panel reuse**: share the Variables tab implementation already built for the flow debug panel, or build a player-specific leaner version.

## Non-goals

- Don't turn the player into a three-panel IDE (Articy trap).
- Don't split "Play" and "Test" into different buttons (Twine anti-pattern).
- Don't dock debug UI inside the reading column.
- Don't forget state on recompile — if we can't implement Inky-style fast-forward cheaply, at least persist the debug session per-user the way the flow debug panel already does.

## Primary competitive sources (verified 2026-04-20)

- Arcweave: docs.arcweave.com/project-tools/play-mode/overview, /using-play-mode; blog.arcweave.com/write-your-interactive-story-with-arcweave.
- Articy: articy.com/help/adx/Presentation_Journeys.html, /Presentation_Simulation.html.
- Ink/Inky: github.com/inkle/inky README; github.com/inkle/ink-unity-integration InkPlayerWindow.md.
- Yarn Spinner: yarnspinner.dev/features.
- Twine/SugarCube: catn.decontextualize.com/twine, motoslave.net/sugarcube/2/docs.
- Dialogic 2: docs.dialogic.pro/getting-started.
- Naninovel: naninovel.com/guide/editor.
