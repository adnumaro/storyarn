# Flow Scopes Plugin Migration

## Objective

Evaluate and, if validated phase by phase, replace `rete-scopes-plugin` with a Storyarn-owned sequence/scope integration for the flow editor.

The goal is not to redesign the flow editor. The goal is to make sequence behavior explicit in our flow domain while preserving the current user-facing behavior:

- sequences are flow nodes with `nodeType === "sequence"`;
- child nodes stay inside their sequence unless the user explicitly reparents with Cmd/Ctrl + drag;
- sequences can grow when children collide with their bounds;
- nested sequences propagate growth to their parent sequences;
- moving a sequence moves its children as a visual group;
- sequence geometry is persisted through the existing LiveView events.

## Current State

`package.json` currently depends on `rete-scopes-plugin`.

The flow editor mounts `ScopesPlugin` in:

```text
assets/app/modules/flows/editor/services/reteSetup.ts
```

The plugin is already heavily constrained:

- `exclude: () => true` prevents the generic plugin sizing rules from owning our sequence geometry.
- `flowScopesPreset` replaces the classic long-press preset with Cmd/Ctrl gated reparenting.
- sequence sizing, collision growth, manual resize, nested parent growth, and persistence live in `useFlowCanvas.ts`.
- `editorHandlers.ts` contains workarounds for the plugin validator, especially when deleting sequence parents.

This means the dependency is no longer the source of truth for sequence behavior. It mostly provides generic Rete pipe wiring for:

- parent-child translation when a sequence moves;
- node ordering for nested nodes;
- validation around parent/child lifecycle;
- a `ScopesPlugin` instance type used by runtime plumbing.

## Phase 0 Findings

Baseline audit from 2026-05-13:

- Production imports of `rete-scopes-plugin` are limited to:
  - `reteSetup.ts` for plugin creation;
  - `flow-scopes-preset.ts` for preset internals;
  - `editorHandlers.ts` and `flowCanvasRuntime.ts` for `ScopesPlugin` types/runtime plumbing.
- There is no production usage of:
  - `scopes.update`;
  - `scopes.isDependent`;
  - `scopepicked`;
  - `scopereleased`;
  - `getPickedNodes`.
- Current explicit plugin workarounds are:
  - `flowScopesPreset` replaces classic long-press reparenting with Cmd/Ctrl gated reparenting.
  - `exclude: () => true` prevents generic child-driven resizing from owning sequence geometry.
  - `clearSequenceChildParents` exists because the plugin validator blocks removing parent nodes with children.
  - `handleFlowUpdated` clears every `.parent` pointer before wiping nodes for the same validator reason.
- Behavior that must be replicated before removing the dependency:
  - sequence move translates descendants;
  - parent sequence renders behind descendants;
  - connections stay visible and aligned;
  - Cmd/Ctrl reparent preserves current drop-target behavior.
- Behavior that should not be replicated:
  - long-press reparenting;
  - generic plugin auto-fit/compact sizing;
  - generic opacity visual effects;
  - validator constraints that conflict with the server delete/reload model.

## Implementation Status

- Phase 0 audit is complete.
- Phase 1 implementation is complete:
  - sequence geometry has been extracted from `useFlowCanvas.ts` into `flowSequenceGeometry.ts`;
  - `useFlowCanvas.ts` now delegates sequence resize, fitting, parent growth, node-view lookup, and pending geometry flush to that module;
  - behavior should remain unchanged.
- Phase 1 validation:
  - targeted lint passed for `useFlowCanvas.ts` and `flowSequenceGeometry.ts`;
  - formatting check passed for changed TS/MD files;
  - flow Vitest suite passed;
  - architecture verification passed with only the accepted `components/ui` circular warnings;
  - browser smoke check on `/flows/8` rendered nodes, sequences, and connections with no console errors.
- Phase 2 implementation is complete:
  - `flowSequenceGeometry.test.ts` covers fit mode, contain mode, collision growth, resize clamping, nested propagation, and selected-ancestor suppression.
- Phase 2 validation:
  - flow/editor geometry tests passed;
  - targeted lint passed for the new geometry test file;
  - formatting check passed after applying `oxfmt`.
- Phase 3 implementation is complete:
  - Cmd/Ctrl reparenting now lives in `flowSequenceScopes.ts`;
  - `reteSetup.ts` installs the local controller for editable flows;
  - `flow-scopes-preset.ts` has been removed;
- Phase 3 validation:
  - unit tests cover no-modifier drag, Cmd/Ctrl drop into sequence, Cmd/Ctrl drop to root, selected-descendant dedupe, descendant-drop blocking, and pointerup cleanup;
  - targeted lint and formatting checks passed;
  - local TypeScript diagnostics are clean for the new controller. The remaining filtered `reteSetup.ts` errors are the existing Vue SFC module-resolution diagnostics.
- Phase 4 implementation is complete:
  - sequence descendant translation now lives in `flowSequenceScopes.ts`;
  - selected descendant subtrees are skipped so multi-select parent + child does not double-translate;
  - the local controller applies the minimal ordering rules needed after removing `ScopesPlugin`;
  - `ScopesPlugin` is no longer mounted or referenced in the flow editor.
- Phase 4 validation:
  - unit tests cover descendant translation, selected subtree dedupe, and parent-behind-child ordering;
  - targeted lint, formatting, and flow editor tests passed;
  - local TypeScript diagnostics are clean for the new controller. The remaining filtered `reteSetup.ts` errors are the existing Vue SFC module-resolution diagnostics.
- Phase 5 implementation is complete:
  - `normalizeFlowSequenceStacking` centralizes ordering after pick, reparent, and remote reparent events;
  - sequence children and their connections are kept above sequence surfaces;
  - new connections are normalized so they remain visible around sequence surfaces.
- Phase 5 validation:
  - unit tests cover parent-behind-child ordering, connection visibility after picking, remote-style reparent normalization, and new connection stacking;
  - targeted lint and formatting checks passed.
- Phase 6 implementation is complete:
  - sequence parent validation is now explicit in `flowSequenceScopes.ts`;
  - local drag reparent and remote `node_reparented` events share the same invariant checks;
  - flow reload no longer clears every `.parent` pointer before removing nodes;
  - deleted sequence children are detached locally to mirror the existing database trigger behavior.
- Phase 6 validation:
  - unit tests cover valid parent changes, root detach, self-parent rejection, descendant-parent rejection, non-sequence parent rejection, and missing parent rejection;
  - flow editor sequence/autolayout tests passed;
  - targeted lint and formatting checks passed;
  - architecture verification passed with only the accepted `components/ui` circular warnings.

## Why Consider Removing It

### Product Fit

Storyarn sequences are becoming more than generic scopes. Planned sequence behavior includes:

- inline editing of the sequence name directly in the sequence header;
- notes visible inside the sequence;
- inline editing of those sequence notes;
- background/media configuration and player-facing sequence state;
- strict containment and explicit reparent semantics.

Those rules are domain-specific. A generic scope plugin keeps pulling behavior toward "nested nodes" while the product model is closer to "editable sequence surface on the flow canvas".

### Technical Fit

We already own the important behavior:

- geometry and minimum size;
- collision growth;
- nested growth propagation;
- Cmd/Ctrl reparent intent;
- server persistence;
- auto-layout sequence fitting.

Keeping the plugin means keeping its implicit behavior and then overriding pieces of it. That makes sequence bugs harder to reason about because ownership is split between:

- `rete-scopes-plugin`;
- `flow-scopes-preset.ts`;
- `SequenceNode.vue`;
- `useFlowCanvas.ts`;
- `editorHandlers.ts`.

### Dependency Risk

Rete's licensing page classifies `rete-scopes-plugin` as an advanced plugin under `CC-BY-NC-SA-4.0`, with commercial use not permitted without a separate licensing model.

The installed package metadata also declares:

```json
"license": "CC-BY-NC-SA-4.0"
```

That should be treated as a separate product/legal risk, not just a technical one.

## Non-Goals

- Do not rewrite the full Rete integration.
- Do not replace `rete`, `rete-area-plugin`, `rete-connection-plugin`, `rete-history-plugin`, `rete-minimap-plugin`, or `rete-vue-plugin`.
- Do not change the persisted data model in the first migration.
- Do not implement sequence notes or inline sequence header editing as part of the dependency removal unless a phase explicitly calls for a small compatibility hook.
- Do not change the UX contract for reparenting: reparent remains Cmd/Ctrl + drag only.

## Target Shape

Create a local flow-domain integration that owns sequence behavior directly.

Possible file split:

```text
assets/app/modules/flows/editor/services/flowSequenceScopes.ts
assets/app/modules/flows/editor/services/flowSequenceOrdering.ts
assets/app/modules/flows/editor/composables/flowSequenceGeometry.ts
assets/app/modules/flows/editor/lib/flow-reparent-state.ts
```

Expected responsibilities:

- `flowSequenceGeometry.ts`
  - sequence bounds;
  - child bounds;
  - minimum size;
  - collision growth;
  - manual resize clamp;
  - nested sequence propagation;
  - pending geometry persistence.

- `flowSequenceScopes.ts`
  - move children when a sequence moves;
  - resolve Cmd/Ctrl reparent drop target;
  - maintain `.parent` on Rete nodes;
  - emit `node_reparented`;
  - block accidental reparent without modifier.

- `flowSequenceOrdering.ts`
  - keep parent nodes behind their children;
  - keep connections visible/aligned;
  - bring selected/moved sequences and children to a coherent z-order.

The public contract should be small:

```ts
type FlowSequenceScopesController = {
  destroy(): void;
};

function installFlowSequenceScopes(options): FlowSequenceScopesController;
```

## Migration Plan

### Phase 0: Narrow Baseline Audit

Before touching implementation, audit only the concrete dependency surface.

Checklist:

- Find every import of `rete-scopes-plugin`.
- Find every runtime reference to `runtime.scopes`.
- Confirm whether `scopes.update`, `isDependent`, `scopepicked`, `scopereleased`, or `getPickedNodes` are used.
- Record every current workaround caused by the plugin.
- Capture current browser behavior for:
  - move normal node inside sequence;
  - move sequence with children;
  - Cmd/Ctrl reparent into sequence;
  - Cmd/Ctrl reparent out to root;
  - nested sequence parent growth;
  - delete sequence;
  - remote `node_reparented`;
  - auto-layout with sequences.

Exit criteria:

- Written findings in this document or a short implementation note.
- Clear list of plugin behaviors that must be replicated.
- Clear list of plugin behaviors that must not be replicated.

### Phase 1: Extract Sequence Geometry

Move the current sequence geometry logic out of `useFlowCanvas.ts` without changing behavior.

Scope:

- `sequenceGeometry`
- `sequenceChildren`
- `nodeBounds`
- `sequenceMinimumSize`
- `clampSequenceSize`
- `expandGeometryToContainBounds`
- `fitGeometryToChildBounds`
- `applySequenceGeometry`
- `fitSequencesToChildren`
- `expandParentSequenceForNode`
- `expandContainingSequencesForGeometry`
- `pushSequenceGeometry`
- `flushPendingSequenceGeometry`

Keep this as a pure extraction plus dependency injection from the runtime.

Exit criteria:

- `useFlowCanvas.ts` delegates sequence geometry to the new module.
- No behavior change.
- Existing manual resize and collision behavior still work.

Validation:

- `pnpm run lint -- <changed files>`
- `pnpm exec oxfmt --check <changed files>`
- `pnpm run test -- --run assets/app/test/modules/flows`
- browser check on `/flows/:id` for drag, resize, nested growth, and connections.

### Phase 2: Add Geometry Unit Tests

Before replacing the plugin, lock down the rules that previously regressed.

Test cases:

- [x] a new sequence fits at least one child plus padding;
- [x] moving a child inside bounds does not resize the sequence;
- [x] dragging a child against the right edge grows only the right side;
- [x] dragging a child against the bottom edge grows only the bottom side;
- [x] manual resize cannot shrink below child bounds;
- [x] nested sequence growth propagates to parent sequence;
- [x] selected parent plus selected children does not double-apply movement;
- [ ] Cmd/Ctrl state does not trigger collision growth rules incorrectly.

The remaining Cmd/Ctrl assertion belongs with Phase 3 because the current geometry module correctly delegates that state to `flow-reparent-state.ts`, while the next phase owns the reparent controller and drop behavior.

Exit criteria:

- Sequence geometry has isolated tests that do not require a browser.
- Browser QA remains the source of truth for Rete view integration.

### Phase 3: Replace Reparent Preset With Local Controller

Replace `flowScopesPreset` with a local controller that is not tied to `ScopesPlugin`.

Scope:

- [x] listen to area pointer/node drag events directly;
- [x] track Cmd/Ctrl modifier state through `flow-reparent-state.ts`;
- [x] mark drag active/inactive for drop-target highlighting;
- [x] resolve top-most sequence under pointer;
- [x] dedupe moving descendants when a selected sequence and child are both selected;
- [x] update `.parent` only when Cmd/Ctrl is held on drop;
- [x] push `node_reparented` only when parent actually changed.

Keep `ScopesPlugin` mounted during this phase if needed, but do not use its preset.

Exit criteria:

- Reparent behavior is owned by Storyarn code.
- `flow-scopes-preset.ts` is deleted or reduced to a compatibility shim.
- Cmd/Ctrl reparent works with same UX as before.

Validation:

- drag without modifier never reparents;
- Cmd/Ctrl drag into sequence reparents;
- Cmd/Ctrl drag out to root reparents to `null`;
- multi-select reparent does not orphan descendants accidentally;
- remote `node_reparented` still updates local canvas.

### Phase 4: Replace Parent-Child Translation

Implement the remaining high-value behavior currently provided by `ScopesPlugin`: when a sequence moves, its descendants move with it.

Scope:

- [x] on `nodetranslated` for a sequence, compute delta from previous position;
- [x] translate descendants by the same delta;
- [x] recurse through nested sequences by calculating all descendants once;
- [x] avoid translating selected children twice when parent and child are both selected;
- [x] avoid creating infinite `nodetranslated` loops;
- [x] keep history/persistence behavior coherent.

Exit criteria:

- Moving a sequence preserves visual relative positions of all descendants.
- Moving a child inside a sequence still uses collision growth rules.
- Moving nested sequences does not freeze the browser.

Validation:

- browser drag a sequence with children;
- browser drag nested sequence;
- browser multi-select sequence + child;
- verify connections remain visible and aligned;
- verify position persistence after reload.

### Phase 5: Harden Ordering Behavior

Harden the local ordering behavior now that `ScopesPlugin` is no longer mounted.

Scope:

- [x] parent sequence should render behind children;
- [x] selected/moved nodes should have predictable z-order in all browser flows;
- [x] connections should not disappear behind sequence surfaces;
- [x] new connections should remain visible.

Do not reproduce plugin internals blindly. Implement the minimum ordering rules required by Storyarn's UI.

Exit criteria:

- Visual stacking is stable after create, select, drag, reparent, and reload.

Validation:

- browser screenshots before/after moving sequence;
- connection visibility in normal and nested sequences;
- minimap still renders coherent nodes.

### Phase 6: Replace Validation Workarounds

Remove plugin-specific lifecycle constraints.

Scope:

- delete `clearSequenceChildParents` if it only exists for plugin validator behavior;
- simplify flow reload cleanup if parent deletion no longer throws;
- make our own invariant checks explicit:
  - a node cannot parent itself;
  - a node cannot parent into its descendant;
  - parent target must be a sequence;
  - deleted sequence children match server behavior.

Exit criteria:

- no local code exists only to satisfy `rete-scopes-plugin` validation.
- delete/reload paths are simpler and covered by tests or browser QA.

### Phase 7: Remove `rete-scopes-plugin`

Remove the dependency once all behavior is locally owned.

Scope:

- remove imports from:
  - `reteSetup.ts`;
  - `editorHandlers.ts`;
  - `flowCanvasRuntime.ts`;
  - any remaining types.
- remove `runtime.scopes` if unused.
- remove `rete-scopes-plugin` from `package.json`.
- update `pnpm-lock.yaml`.

Exit criteria:

- `rg "rete-scopes-plugin|ScopesPlugin|scopepicked|scopereleased|getPickedNodes"` returns no production usage.
- Flow editor still supports sequences fully.

Validation:

- `pnpm install --lockfile-only`
- `pnpm run arch`
- `pnpm run lint -- <changed files>`
- `pnpm exec oxfmt --check <changed files>`
- `pnpm run test -- --run assets/app/test/modules/flows`
- browser QA for the full sequence matrix.

### Phase 8: Enable Future Sequence Surface Work

Only after the dependency removal is stable, implement sequence-specific UX on top of owned behavior.

Candidates:

- inline sequence name editing in `SequenceNode.vue`;
- visible sequence notes;
- inline editing for sequence notes;
- note-aware sequence minimum height;
- sequence header actions;
- richer drop target states.

Exit criteria:

- sequence UX evolves inside Storyarn-owned modules.
- no generic scope dependency constrains DOM structure or gesture behavior.

## Phase-Level Audit Template

Each implementation phase should start with a narrow audit. Use this template before editing:

```text
Phase:
Files touched by current behavior:
Events/pipes involved:
Server events involved:
Runtime state involved:
Current browser behavior:
Known regressions to protect:
Expected module boundary after phase:
Validation commands:
Manual browser checks:
```

## Browser QA Matrix

Minimum manual checks before removing the dependency:

- Load `/workspaces/:workspace/projects/:project/flows/:flow_id`.
- Create a sequence from one node.
- Create a sequence from multiple nodes.
- Move a node inside a sequence without crossing bounds.
- Move a node into the right/bottom bounds and confirm the sequence grows.
- Resize a sequence manually and confirm it cannot shrink below children.
- Move a sequence and confirm children and connections move correctly.
- Move a nested sequence and confirm parent growth is stable.
- Cmd/Ctrl drag a node into a sequence.
- Cmd/Ctrl drag a node out of a sequence.
- Multi-select sequence and child, then drag.
- Run auto-layout with sequences and nested sequences.
- Delete a sequence.
- Reload and confirm persisted geometry/parents.

## Recommended Starting Point

Start with Phase 0 and Phase 1 only.

The dependency removal should not begin until sequence geometry is extracted and covered. Most recent regressions were geometry/containment problems, not package wiring problems, so extracting that area first reduces risk and gives later phases a stable API.
