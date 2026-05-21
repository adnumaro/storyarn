# Events / Flags System — Vision & Phased Design

**Status:** vision doc, 2026-04-20. Deferred until Flow Player MVP ships and real demand emerges. Not committed to a timeline.

## Why this exists

Cross-flow / cross-scene reactivity is hard to author today. Today the only mechanism is "set a variable flag; have subscribers poll it via condition nodes." That works for simple cases but collapses into spaghetti when a project has many reactive behaviors spanning multiple flows and scenes.

A proper pub/sub system solves this with decoupling: emitter doesn't know who reacts; subscriber doesn't know who emitted. It also naturally composes with the reactive formula engine already in place.

This doc captures the design explored in the 2026-04-20 session and the reasons to defer full implementation.

## Two-phase strategy

**v1 — Flags (ship this first, if we ship anything)**

- Stamp-style annotations on existing flow nodes. Not new flow-graph nodes.
- A stamp is either "raise flag X" (emit) or "on flag X" (subscribe).
- **No payload. No filter. No namespacing.** Just a name.
- Inspector panel lists all flags: raisers, listeners, jump-to-source.
- ~80% of the reactivity value. ~30% of the complexity.

**v2 — Events (only if demand emerges after Flags ship)**

- Adds payload (key/value data on the signal).
- Adds filter (subscribers gate on payload content).
- Adds scoping / namespacing (flow-local vs project-wide).
- Event Graph inspector with Sankey-style topology view.
- Full pub/sub semantics.

Refactor from Flags → Events is additive; no breaking changes at runtime.

## UX principle: annotation stamps, not flow nodes

User reframed my first proposal, which had added a discrete `Event` node interrupting flow execution. Correct shape:

> **"The new subscriber node can be the same as the emitter. A node that connects directly to any node without in/out flow connections — like an annotation on the node, with a different connection line from all the others so there's no confusion."** (translated from Spanish)

Visual: a small stamp tethered to a host node via a **dashed line in a distinct color** (e.g. cyan or violet — not reused by flow connections). The stamp does not participate in the flow's execution graph. It's a hook on node events.

```
                         ╭─ 🔔 raise: alice_reveals
                        ╱
  ┌─ Dialogue "Alice tells the secret" ─┐
  │ Alice: "I'm pregnant."               │──→ [flow continues]
  └──────────────────────────────────────┘
                        ╲
                         ╰─ 🔔 listen: mood_changed
                               (turns host into alt entry point
                                when the flag fires)
```

**Emit trigger**: after the host node executes (natural "something happened here" semantic).
**Subscribe effect**: the host node becomes an alternate entry point. When the flag fires, execution jumps to the host and runs the flow forward. A flow can have multiple subscribe stamps → multi-entry state machine.

## How flags/events work inside scenes

**Scenes do not get a separate UI for flags.** They delegate to their ambient flows.

- Zone triggers an ambient flow (existing mechanism).
- That ambient flow carries raise/listen stamps like any other flow.
- Scene editor stays focused on world layout (zones, pins, layers). Zero new concepts there.

This keeps the "scene = interactive world, flow = narrative logic" boundary clean.

## Distinguishing Flag/Event from Instruction / Conditional

|              | Instruction              | Conditional                 | Flag / Event                                        |
| ------------ | ------------------------ | --------------------------- | --------------------------------------------------- |
| What it does | Write a variable         | Read a variable, branch     | Broadcast a named signal                            |
| Scope        | Local to current flow    | Local to current flow       | **Project-wide** (or namespaced)                    |
| Model        | Imperative               | Gate                        | **Pub/Sub**                                         |
| Who reacts   | Nobody — it's a mutation | Nobody — decides next route | **Any subscriber in any flow/scene's ambient flow** |
| Visible in   | The flow where it lives  | The flow where it lives     | Everywhere it's subscribed, via Inspector           |

A Flag is _not_ syntactic sugar over an Instruction. An Instruction writes and moves on; a Flag's semantic is "notify anyone listening." Subscribers wake up automatically — no polling required.

## Four-layer architecture (for reference, not a build plan)

The user brainstormed an architecture where four orthogonal layers cooperate. Each is opt-in. Authors use only what they need.

```
┌─────────────────────────────────────────────────────┐
│ Layer 4 — FLAG/EVENT BUS (reactive world)           │
│   emit → subscribers in other flows/scenes react    │
├─────────────────────────────────────────────────────┤
│ Layer 3 — REACTIVE FORMULAS (the existing moat)     │
│   cue.image_asset_id = castle_day ? sunny : night   │
├─────────────────────────────────────────────────────┤
│ Layer 2 — PREMIERE TIMELINE (authored direction)    │
│   tracks: background / audio / characters / props   │
├─────────────────────────────────────────────────────┤
│ Layer 1 — ENTRY COVER (minimum baseline)            │
│   image + title on the flow's entry node            │
└─────────────────────────────────────────────────────┘
```

Layer 1 ships in the Flow Player MVP (see `flow-player-redesign/OVERVIEW.md`). Layers 2–4 are future work. Layer 4 (this doc) pairs best with Layer 3 — flags cause vars to change, formulas react, visuals update.

## Inspector UX (for v1 Flags — simplified; v2 Events adds payload/filter columns)

Sidebar panel in the project chrome:

```
┌─ Flags                               [search] ┐
├────────────────────────────────────────────────┤
│  🔔 alice_reveals                              │
│     1 raiser  ·  2 listeners                   │
│                                                │
│  🔔 chapter_3_start                            │
│     1 raiser  ·  5 listeners                   │
│                                                │
│  ⚠️ player_fainted                             │
│     2 raisers  ·  0 listeners                  │
│                                                │
│  ⚠️ music_stop                                 │
│     0 raisers  ·  1 listener                   │
└────────────────────────────────────────────────┘
```

Click a flag → detail view with clickable jump-to-source for each raiser and listener. The ⚠️ markers flag orphan raisers and orphan listeners (the typical pub/sub bug pattern).

During debug mode, a new **Flags tab** in the debug panel shows a live log of firings with timestamps and which listeners reacted.

## Hard UX rules for shipping this

1. **Progressive disclosure.** Flags must be invisible to authors who don't need them. No "Flags" menu entry by default. The stamp option appears in the node context menu's advanced submenu, or only when the project template (see `project-templates/OVERVIEW.md`) enables the feature.
2. **Rename safety.** Renaming a flag updates every raiser and listener. No sed-replace.
3. **Ring buffer on debug log.** Cap live events to last ~200 entries to avoid UI saturation. "Pause capture" button for analysis.
4. **Autocomplete everywhere.** Flag names autocomplete from existing project flags + "create new" fallback. Typos are the #1 pub/sub bug in practice.

## Why this is deferred (2026-04-20 decision)

User framing:

> **"What most holds me back about what we're planning is the added complexity we'd be including, and I'm worried the end user won't fully understand it or will reject the whole thing."** (translated from Spanish)

Priority order today: finish Flow Player MVP → move to Scenes → Screenplay is super-admin-only. Flags/Events is a power feature that can wait until:

1. Flow Player MVP is shipped and the baseline is solid.
2. The Project Templates system (see `project-templates/OVERVIEW.md`) is in place — needed for progressive disclosure.
3. Real user feedback requests cross-flow reactivity that variable polling can't satisfy cleanly.

Building Flags before those three is premature optimization.

## Non-goals

- Don't ship v2 (Events with payload/filter) first. Start with Flags.
- Don't build the Sankey graph visualization in v1 — backlinks-list suffices.
- Don't support event hierarchy / wildcards (`combat:*` matches `combat:hit`). Adds complexity, zero demonstrated need.
- Don't support cancellation or priorities ("first this listener, then that"). Deterministic by creation order.
- Don't surface Flags/Events in the UI of projects whose template doesn't enable them. Progressive disclosure is non-negotiable.

## Related docs

- `docs/features/flow-player-redesign/OVERVIEW.md` — Layer 1 is the baseline that must ship first.
- `docs/features/project-templates/OVERVIEW.md` — the gating mechanism that makes this feature palatable.
- `docs/features/tables-rule-engine/OVERVIEW.md` — the reactive formula engine that amplifies Flag value.
