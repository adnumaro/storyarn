/**
 * Custom replacement for `ScopesPresets.classic.setup()`.
 *
 * Why a custom preset?
 *
 *   1. The classic preset's `reassignParent` runs unconditionally on
 *      `nodedragged`, so any drag of a node out of its sequence visually
 *      orphans the node (and can shrink the sequence to the empty-children
 *      min size via `resizeParent`). Users expected the sequence to stay
 *      big and the node to stay logically inside unless they explicitly
 *      asked for reparenting — i.e. hold Cmd/Ctrl while dragging.
 *
 *   2. The classic preset's `reassignParent` doesn't dedupe multi-selection
 *      where a sequence and its own children are both in `ids`; the parent
 *      loses its children and shrinks to min size. We want the descendant
 *      filter so a parent moves as a unit.
 *
 * This preset:
 *
 *   - On `nodepicked` — schedules a 250 ms timer that captures the
 *     currently-selected nodes (falling back to the picked id). Same
 *     timer semantics as `useScopeAgent`. Marks drag as active so the
 *     drop-target indicator can light up.
 *
 *   - On `nodetranslated` — cancels the pending pick timer if the user
 *     actually moved (mirrors the classic preset). Normal child movement
 *     keeps the sequence bbox stable; explicit resize/reparent operations
 *     decide when the container should change.
 *
 *   - On `nodedragged` — releases the candidates. If Cmd/Ctrl was held,
 *     runs our own `reassignParent` (deduped) and reports the change via
 *     `onReparented`. If not held, does nothing — the flow canvas handles
 *     collision-based sequence growth separately.
 *
 * We also skip the classic preset's `useVisualEffects` opacity dim. Drop
 * targets get their own visual treatment in `Sequence.vue` (background +
 * border change via the `reparentGestureActive` ref), which is the only
 * feedback the user explicitly asked for.
 */

import type { BaseSchemes, NodeEditor } from "rete";
import type { AgentParams, AgentContext } from "rete-scopes-plugin/_types/agents/types";

import {
  isReparentModifierActive,
  markDragActive,
  markDragInactive,
  syncReparentModifierFromPointerEvent,
} from "./flow-reparent-state";

interface ScopeNode {
  id: string;
  parent?: string;
  nodeType?: string;
  width: number;
  height: number;
  selected?: boolean;
}

// rete-scopes-plugin doesn't export tight types for the area it runs
// against (the concrete BaseAreaPlugin subclass), so we describe the
// subset we actually use. Kept structural to avoid fighting the plugin's
// internal generic constraints.
interface ScopeArea {
  area: { pointer: { x: number; y: number }; content: { holder: HTMLElement } };
  nodeViews: Map<string, { position: { x: number; y: number }; element: HTMLElement }>;
  addPipe: (handler: (context: unknown) => Promise<unknown> | unknown) => void;
}

type ReparentListener = (nodeId: string, newParentId: string | undefined) => void;

/**
 * If any ancestor of `nodeId` is in `ids`, return true. Used to dedupe
 * the moving set so a sequence's children aren't treated as independently-
 * moving when the sequence itself is dragged (they come along via
 * `translateChildren` in rete-scopes' own `nodetranslated` handler).
 */
function hasAncestorInSet<S extends BaseSchemes>(
  nodeId: string,
  ids: string[],
  editor: NodeEditor<S>,
): boolean {
  let current = editor.getNode(nodeId) as unknown as ScopeNode | undefined;
  while (current?.parent) {
    if (ids.includes(current.parent)) return true;
    current = editor.getNode(current.parent) as unknown as ScopeNode | undefined;
  }
  return false;
}

/**
 * Drop-resolver: reassigns `.parent` on every id in the moving set based on
 * where the pointer landed, then reports the change through `onReparented`
 * for persistence. Sequence geometry is handled by `useFlowCanvas`.
 *
 * Differences vs the classic `reassignParent`:
 *   - Dedupes descendants out of `ids` so their `.parent` isn't nullified
 *     when an ancestor is also moving.
 *   - Emits a callback per node whose parent actually changed, so the
 *     caller can push it to the server.
 */
async function reassignParent<S extends BaseSchemes>(
  ids: string[],
  pointer: { x: number; y: number },
  props: { editor: NodeEditor<S>; area: ScopeArea },
  onReparented: ReparentListener,
): Promise<void> {
  if (ids.length === 0) return;

  // Dedupe: any id whose ancestor is also in ids is dropped — it'll be
  // carried along by its ancestor via rete-scopes' own translateChildren.
  const movingIds = ids.filter((id) => !hasAncestorInSet(id, ids, props.editor));
  const movingNodes = movingIds
    .map((id) => props.editor.getNode(id))
    .filter((n): n is NonNullable<typeof n> => Boolean(n)) as unknown as ScopeNode[];

  // Find overlay candidates (non-moving nodes whose bbox contains the pointer).
  const overlayCandidates = props.editor
    .getNodes()
    .map((node) => {
      const view = props.area.nodeViews.get((node as unknown as ScopeNode).id);
      return view ? { node: node as unknown as ScopeNode, view } : null;
    })
    .filter(
      (
        entry,
      ): entry is {
        node: ScopeNode;
        view: { position: { x: number; y: number }; element: HTMLElement };
      } =>
        Boolean(entry) &&
        entry!.node.nodeType === "sequence" &&
        !movingIds.includes(entry!.node.id) &&
        !hasAncestorInSet(entry!.node.id, movingIds, props.editor) &&
        pointer.x > entry!.view.position.x &&
        pointer.y > entry!.view.position.y &&
        pointer.x < entry!.view.position.x + entry!.node.width &&
        pointer.y < entry!.view.position.y + entry!.node.height,
    );

  // Stack order: the top-most candidate (last in the area's DOM order) wins.
  const areaChildren = Array.from(props.area.area.content.holder.childNodes);
  overlayCandidates.sort(
    (a, b) => areaChildren.indexOf(b.view.element) - areaChildren.indexOf(a.view.element),
  );
  const topOverlay = overlayCandidates[0];

  const newParentId = topOverlay?.node.id;

  // Reassign and report only when .parent actually changes.
  for (const node of movingNodes) {
    const previousParent = node.parent;
    node.parent = newParentId;
    if (previousParent !== newParentId) {
      onReparented(node.id, newParentId);
    }
  }
}

/**
 * Entrypoint. Returns a preset usable via `scopes.addPreset(...)` in place
 * of `ScopesPresets.classic.setup()`.
 *
 * Key differences vs the classic preset:
 *
 * 1. **No long-press gate.** Classic waits 250 ms on `nodepicked` before
 *    capturing ids; `nodetranslated` within that window cancels it, so
 *    fast drags get `ids=[]` and no reparent. Our modifier already signals
 *    intent, so we capture the moving set at drop time directly from the
 *    drag target + current selection.
 *
 * 2. **No `scopepicked` / `scopereleased` emissions.** Those events
 *    populate `getPickedNodes(scopes)` internally. We do not need those
 *    events because this preset owns only reparent intent; flow-specific
 *    sequence growth is handled by the canvas.
 *
 * What we keep:
 *
 *   - `markDragActive` / `markDragInactive` drive `reparentGestureActive`
 *     so `Sequence.vue`'s drop-target highlight knows when to show.
 *   - `nodedragged` runs our own `reassignParent` when the modifier is
 *     held at release time.
 */
export function flowScopesPreset<S extends BaseSchemes>(opts: {
  /** Called with (nodeId, newParentId-or-undefined) whenever a reparent actually changes `.parent`. */
  onReparented: ReparentListener;
}): (params: AgentParams, context: AgentContext<unknown>) => void {
  return (_params, context) => {
    const area = context.area as unknown as ScopeArea;
    const editor = context.editor as unknown as NodeEditor<S>;

    function currentMovingIds(pickedId: string): string[] {
      const selected = editor
        .getNodes()
        .filter((n) => (n as unknown as ScopeNode).selected)
        .map((n) => (n as unknown as ScopeNode).id);
      // If the picked id is in the selection → use the full selection.
      // Otherwise → the drag is scoped to just the picked id (rete's
      // selectableNodes replaces the selection with the picked one in
      // that case too, but we don't trust that to have run yet).
      if (selected.includes(pickedId)) {
        return selected;
      }
      return [pickedId];
    }

    function syncModifierState(ctx: { type: string; data?: unknown }): void {
      if (ctx.type !== "pointerdown" && ctx.type !== "pointermove" && ctx.type !== "pointerup") {
        return;
      }
      const evt = (ctx.data as { event?: PointerEvent } | undefined)?.event;
      if (evt) {
        syncReparentModifierFromPointerEvent(evt);
      }
    }

    async function handleNodeDragged(ctx: { type: string; data?: unknown }): Promise<void> {
      if (ctx.type !== "nodedragged") {
        return;
      }

      const pointer = area.area.pointer;
      const draggedId = (ctx.data as { id: string } | undefined)?.id ?? "";
      markDragInactive();
      if (!isReparentModifierActive() || !draggedId) {
        return;
      }

      await reassignParent(
        currentMovingIds(draggedId),
        pointer,
        { area, editor },
        opts.onReparented,
      );
    }

    area.addPipe(async (raw: unknown) => {
      if (!raw || typeof raw !== "object" || !("type" in raw)) {
        return raw;
      }
      const ctx = raw as { type: string; data?: unknown };
      // Pointer events carry `metaKey` / `ctrlKey` straight from the
      // browser — more reliable than our document-level keyboard listener
      // when the page is in an iframe harness (Cowork) that intercepts
      // keyboard focus.
      syncModifierState(ctx);
      if (ctx.type === "nodepicked") {
        markDragActive();
      }
      await handleNodeDragged(ctx);
      return raw;
    });
  };
}
