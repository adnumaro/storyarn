# Flow Auto Layout Migration

## Objective

Replace `rete-auto-arrange-plugin` with a small Storyarn-owned auto-layout service for the flow editor.

The goal is not to change the user-facing auto-layout behavior first. The first migration should keep the current layout output as close as possible while removing the stale plugin wrapper and using `elkjs` directly.

## Baseline Before Migration

- `package.json` depends on `rete-auto-arrange-plugin@2.0.2`.
- `package.json` also depends directly on `elkjs@0.11.1`.
- `rete-auto-arrange-plugin@2.0.2` declares peer dependency `elkjs@^0.8.2`.
- With pnpm, `elkjs@0.11.1` is installed as the peer for the plugin, producing an unmet peer warning.
- The flow editor currently uses:
  - `AutoArrangePlugin` and `Presets.classic.setup()` in `assets/app/modules/flows/editor/services/reteSetup.ts`.
  - `ArrangeAppliers.TransitionApplier` and `_arrange.layout(...)` in `assets/app/modules/flows/editor/composables/useFlowCanvas.ts`.

## Implementation Status

- `assets/app/modules/flows/editor/services/flowAutoLayout.ts` owns ELK graph serialization, layout execution, and animated position application.
- `useFlowCanvas.ts` calls the local flow auto-layout service and then runs sequence auto-fit before persisting positions.
- Sequence auto-fit is intentionally different from normal drag containment:
  - dragging a node keeps the current sequence size unless the node collides with a boundary;
  - auto-layout recalculates sequence bounds from direct children and propagates the fitted geometry through nested sequences.
- `reteSetup.ts` no longer creates or mounts `AutoArrangePlugin`.
- `package.json` and `pnpm-lock.yaml` no longer include `rete-auto-arrange-plugin`; `elkjs` remains the direct layout dependency.

## Why Own This Code

The upstream plugin is a thin wrapper around ELK:

1. Build an ELK graph from Rete nodes and connections.
2. Convert Rete inputs/outputs to fixed ELK ports.
3. Run `elk.layout(graph)`.
4. Apply resulting node positions and sizes through the Rete area.
5. Optionally animate the application.

Storyarn now has flow-specific behavior that the generic plugin does not understand:

- Sequence nodes have custom containment and resize rules.
- Nested sequences must propagate geometry changes to ancestors.
- Reparenting is Cmd/Ctrl gated.
- Position persistence happens through `batch_update_positions`.
- History needs `AutoLayoutAction`.
- Connection refresh must happen after sequence/node geometry changes.

Owning the layout adapter lets us keep ELK updated directly and make layout behavior explicit in the flow domain.

## Target Shape

Create a flow-domain service:

```text
assets/app/modules/flows/editor/services/flowAutoLayout.ts
```

Suggested public API:

```ts
type FlowAutoLayoutOptions = {
  nodes?: FlowNode[];
  connections?: FlowConnection[];
  layoutOptions?: ElkLayoutOptions;
  duration?: number;
  onTick?: () => void;
};

type FlowAutoLayoutResult = {
  source: ElkNode;
  result: ElkNode;
  previousPositions: Map<string, Position>;
  nextPositions: Map<string, Position>;
};

async function runFlowAutoLayout(
  ctx,
  options?: FlowAutoLayoutOptions,
): Promise<FlowAutoLayoutResult>;
```

The service should own:

- ELK graph serialization.
- Port positioning equivalent to the current classic preset.
- Layout execution through `elkjs`.
- Applying positions to Rete views.
- Optional transition animation.
- Connection refresh after layout.

`useFlowCanvas.ts` should keep orchestration only:

- guard `_autoLayoutInProgress`;
- call the service;
- call `AreaExtensions.zoomAt`;
- push `batch_update_positions`;
- add `AutoLayoutAction`.

## Migration Plan

### Phase 1: Characterize Current Behavior

- Capture current auto-layout options:
  - `elk.algorithm = layered`
  - `elk.direction = RIGHT`
  - `elk.spacing.nodeNode = 60`
  - `elk.layered.spacing.nodeNodeBetweenLayers = 120`
- Capture current port layout:
  - output ports: `EAST`, top offset `35`, spacing `35`;
  - input ports: `WEST`, bottom offset `15`, spacing `35`;
  - fixed port constraints.
- Record current limitations:
  - edges are root-level only in the plugin implementation;
  - nested sequence behavior is generic ELK hierarchy handling.

### Phase 2: Implement Local ELK Graph Builder

- Add `flowAutoLayout.ts`.
- Convert each `FlowNode` to an `ElkNode`.
- Preserve parent-child hierarchy using `node.parent`.
- Convert Rete connections to ELK edges.
- Keep current layout options as defaults.
- Do not remove `rete-auto-arrange-plugin` yet.

Validation:

- Unit-test graph serialization for:
  - a simple two-node flow;
  - a node with multiple outputs;
  - a sequence with children;
  - nested sequences.

### Phase 3: Implement Local Applier

- Add immediate and animated application paths.
- Use Rete area APIs deliberately:
  - normal nodes can use the standard view translation path;
  - sequences should go through the same sequence-safe geometry helpers or a narrow adapter to avoid reintroducing child-drag side effects.
- Refresh all connections after layout.

Validation:

- Auto-layout from the context menu still moves nodes.
- Connections remain visible and aligned.
- Sequences still contain their children after layout.
- Nested sequences do not freeze the browser.

### Phase 4: Switch Runtime Usage

- Replace `_arrange.layout(...)` usage in `useFlowCanvas.ts` with `runFlowAutoLayout(...)`.
- Remove `AutoArrangePlugin` creation and `ArrangePresets.classic.setup()` from `reteSetup.ts`.
- Keep `elkjs` as the only layout dependency.

Validation:

- `pnpm run arch`
- `pnpm run lint -- <changed TS/Vue files>`
- `pnpm run fmt:check`
- `mix compile`
- Manual browser test on `/flows/:id`:
  - run auto-layout on a normal flow;
  - run auto-layout with sequences;
  - run auto-layout with nested sequences;
  - verify reload persists positions.

### Phase 5: Remove Plugin Dependency

- Remove `rete-auto-arrange-plugin` from `package.json`.
- Update `pnpm-lock.yaml`.
- Confirm no imports remain.

Validation:

- `pnpm install --lockfile-only`
- `pnpm run arch`
- `pnpm run test -- --run assets/app/test/modules/flows`
- `mix test test/storyarn_web/live/flow_live`

## Risks

- ELK hierarchy behavior may differ once we own edge nesting decisions.
- Sequence layout may need a Storyarn-specific rule instead of reproducing the plugin exactly.
- Animated application can re-trigger expensive Rete updates if every frame refreshes connections.
- Current tests do not deeply cover the canvas visual layout, so manual browser verification is required.

## Recommended First Implementation

Start with a compatibility implementation:

- Same default options.
- Same port positions.
- Same animation duration.
- Same final persisted payload.

Only after the plugin is removed should we improve sequence-specific layout semantics.
