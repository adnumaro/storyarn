import type { FlowNode } from "../lib/flow-node";
import { createFlowGraphQueries } from "../lib/flowGraphQueries";
import { isReparentModifierActive } from "../lib/flow-reparent-state";
import { SEQUENCE_MIN_HEIGHT, SEQUENCE_MIN_WIDTH, SEQUENCE_PADDING } from "../lib/sequence-layout";
import type { FlowCanvasRuntime } from "./flowCanvasRuntime";
import type {
  NodeBounds,
  NodeView,
  SequenceExpansionOpts,
  SequenceFitMode,
  SequenceGeometry,
  SequenceResizeDetail,
} from "./flowCanvasTypes";

export interface FlowSequenceGeometryController {
  handleSequenceResize(event: Event): Promise<void>;
  nodeView(nodeId: string): NodeView | null;
  fitSequencesToChildren(opts?: FlowSequenceFitOptions): Promise<void>;
  expandParentSequenceForNode(
    node: FlowNode,
    position: { x: number; y: number },
    opts: { allowModifier: boolean },
  ): Promise<void>;
  flushPendingSequenceGeometry(): void;
}

export interface FlowSequenceFitOptions {
  track?: boolean;
  mode?: SequenceFitMode;
}

export function createFlowSequenceGeometry(
  runtime: FlowCanvasRuntime,
): FlowSequenceGeometryController {
  function nodeView(nodeId: string): NodeView | null {
    return (runtime.area?.nodeViews.get(nodeId) as NodeView | undefined) ?? null;
  }

  function flowGraph() {
    return runtime.editor ? createFlowGraphQueries(runtime.editor.getNodes()) : null;
  }

  function sequenceGeometry(sequence: FlowNode): SequenceGeometry | null {
    const view = nodeView(sequence.id);
    if (!view) {
      return null;
    }

    return {
      x: view.position.x,
      y: view.position.y,
      width: sequence.width,
      height: sequence.height,
    };
  }

  function sequenceChildren(sequenceId: string): FlowNode[] {
    return flowGraph()?.children(sequenceId) ?? [];
  }

  function nodeBounds(node: FlowNode, position?: { x: number; y: number }): NodeBounds | null {
    const view = nodeView(node.id);
    const resolvedPosition = position ?? view?.position;
    if (!resolvedPosition) {
      return null;
    }

    return {
      left: resolvedPosition.x,
      top: resolvedPosition.y,
      right: resolvedPosition.x + node.width,
      bottom: resolvedPosition.y + node.height,
    };
  }

  function sequenceMinimumSize(sequence: FlowNode): { width: number; height: number } {
    const geometry = sequenceGeometry(sequence);
    if (!geometry) {
      return { width: SEQUENCE_MIN_WIDTH, height: SEQUENCE_MIN_HEIGHT };
    }

    return sequenceChildren(sequence.id).reduce(
      (minSize, child) => {
        const childBounds = nodeBounds(child);
        if (!childBounds) {
          return minSize;
        }

        return {
          width: Math.max(
            minSize.width,
            Math.ceil(childBounds.right - geometry.x + SEQUENCE_PADDING.right),
          ),
          height: Math.max(
            minSize.height,
            Math.ceil(childBounds.bottom - geometry.y + SEQUENCE_PADDING.bottom),
          ),
        };
      },
      { width: SEQUENCE_MIN_WIDTH, height: SEQUENCE_MIN_HEIGHT },
    );
  }

  function clampSequenceSize(
    sequence: FlowNode,
    size: { width: number; height: number },
  ): { width: number; height: number } {
    const minimum = sequenceMinimumSize(sequence);
    return {
      width: Math.max(size.width, minimum.width),
      height: Math.max(size.height, minimum.height),
    };
  }

  function expandGeometryToContainBounds(
    geometry: SequenceGeometry,
    bounds: NodeBounds,
  ): SequenceGeometry {
    const left = Math.min(geometry.x, bounds.left - SEQUENCE_PADDING.left);
    const top = Math.min(geometry.y, bounds.top - SEQUENCE_PADDING.top);
    const right = Math.max(geometry.x + geometry.width, bounds.right + SEQUENCE_PADDING.right);
    const bottom = Math.max(geometry.y + geometry.height, bounds.bottom + SEQUENCE_PADDING.bottom);

    return {
      x: Math.floor(left),
      y: Math.floor(top),
      width: Math.max(SEQUENCE_MIN_WIDTH, Math.ceil(right - left)),
      height: Math.max(SEQUENCE_MIN_HEIGHT, Math.ceil(bottom - top)),
    };
  }

  function fitGeometryToChildBounds(
    sequence: FlowNode,
    current: SequenceGeometry,
  ): SequenceGeometry {
    const childrenBounds = sequenceChildren(sequence.id)
      .map((child) => nodeBounds(child))
      .filter((bounds): bounds is NodeBounds => Boolean(bounds));

    if (childrenBounds.length === 0) {
      return current;
    }

    const left = Math.min(...childrenBounds.map((bounds) => bounds.left)) - SEQUENCE_PADDING.left;
    const top = Math.min(...childrenBounds.map((bounds) => bounds.top)) - SEQUENCE_PADDING.top;
    const right =
      Math.max(...childrenBounds.map((bounds) => bounds.right)) + SEQUENCE_PADDING.right;
    const bottom =
      Math.max(...childrenBounds.map((bounds) => bounds.bottom)) + SEQUENCE_PADDING.bottom;

    return {
      x: Math.floor(left),
      y: Math.floor(top),
      width: Math.max(SEQUENCE_MIN_WIDTH, Math.ceil(right - left)),
      height: Math.max(SEQUENCE_MIN_HEIGHT, Math.ceil(bottom - top)),
    };
  }

  function geometryChanged(a: SequenceGeometry, b: SequenceGeometry): boolean {
    return (
      Math.abs(a.x - b.x) > 0.5 ||
      Math.abs(a.y - b.y) > 0.5 ||
      Math.abs(a.width - b.width) > 0.5 ||
      Math.abs(a.height - b.height) > 0.5
    );
  }

  function moveSequenceViewSilently(view: NodeView, x: number, y: number): void {
    // Expanding a sequence left/up changes the bbox origin, not the sequence's content.
    // Calling view.translate would emit nodetranslated and move descendants too.
    view.position = { x, y };
    view.element.style.transform = `translate(${x}px, ${y}px)`;
  }

  async function refreshConnections(): Promise<void> {
    if (!runtime.editor || !runtime.area) {
      return;
    }
    for (const connection of runtime.editor.getConnections()) {
      await runtime.area.update("connection", connection.id);
    }
  }

  async function applySequenceGeometry(
    sequence: FlowNode,
    geometry: SequenceGeometry,
    opts: { track: boolean },
  ): Promise<void> {
    const view = nodeView(sequence.id);
    if (!view || !runtime.area) {
      return;
    }

    if (
      Math.abs(view.position.x - geometry.x) > 0.5 ||
      Math.abs(view.position.y - geometry.y) > 0.5
    ) {
      moveSequenceViewSilently(view, geometry.x, geometry.y);
    }

    sequence.width = geometry.width;
    sequence.height = geometry.height;
    sequence.nodeData = { ...sequence.nodeData, width: geometry.width, height: geometry.height };
    await runtime.area.resize(sequence.id, geometry.width, geometry.height);

    if (opts.track) {
      runtime.pendingSequenceGeometry.set(sequence.id, {
        nodeId: sequence.nodeId,
        ...geometry,
      });
    }

    await refreshConnections();
  }

  function sequencesDeepestFirst(): FlowNode[] {
    return flowGraph()?.deepestFirst((node) => node.nodeType === "sequence") ?? [];
  }

  async function ensureSequenceContainsChildren(
    sequence: FlowNode,
    opts: { track: boolean; mode?: SequenceFitMode },
  ): Promise<void> {
    const current = sequenceGeometry(sequence);
    if (!current) {
      return;
    }

    const geometry =
      opts.mode === "fit"
        ? fitGeometryToChildBounds(sequence, current)
        : sequenceChildren(sequence.id).reduce((acc, child) => {
            const bounds = nodeBounds(child);
            return bounds ? expandGeometryToContainBounds(acc, bounds) : acc;
          }, current);

    if (geometryChanged(current, geometry)) {
      await applySequenceGeometry(sequence, geometry, opts);
    }
  }

  async function fitSequencesToChildren(opts: FlowSequenceFitOptions = {}): Promise<void> {
    if (!runtime.editor || runtime.destroyed) {
      return;
    }

    runtime.hookProxy.enterLoadingFromServer();
    try {
      for (const sequence of sequencesDeepestFirst()) {
        await ensureSequenceContainsChildren(sequence, {
          track: opts.track ?? false,
          mode: opts.mode ?? "contain",
        });
      }
      await refreshConnections();
    } finally {
      runtime.hookProxy.exitLoadingFromServer();
    }
  }

  function hasSelectedAncestor(node: FlowNode): boolean {
    const selected = runtime.hookProxy._flowContext?.selectedReteIds;
    if (!selected || selected.size === 0) {
      return false;
    }

    return flowGraph()?.hasAnyAncestor(node.id, [...selected].map(String)) ?? false;
  }

  function canExpandParentSequence(node: FlowNode, opts: { allowModifier: boolean }): boolean {
    return Boolean(
      runtime.editor &&
      node.parent &&
      !hasSelectedAncestor(node) &&
      (opts.allowModifier || !isReparentModifierActive()),
    );
  }

  function parentSequenceForNode(node: FlowNode): FlowNode | null {
    if (!runtime.editor || !node.parent) {
      return null;
    }

    const parent = flowGraph()?.node(node.parent);
    return parent?.nodeType === "sequence" ? parent : null;
  }

  async function expandContainingSequencesForGeometry(
    sequence: FlowNode,
    geometry: SequenceGeometry,
    opts: SequenceExpansionOpts,
  ): Promise<void> {
    if (!canExpandParentSequence(sequence, { allowModifier: opts.allowModifier })) {
      return;
    }

    const parent = parentSequenceForNode(sequence);
    if (!parent) {
      return;
    }

    const current = sequenceGeometry(parent);
    if (!current) {
      return;
    }

    const bounds = {
      left: geometry.x,
      top: geometry.y,
      right: geometry.x + geometry.width,
      bottom: geometry.y + geometry.height,
    };
    const next = expandGeometryToContainBounds(current, bounds);

    if (geometryChanged(current, next)) {
      await applySequenceGeometry(parent, next, { track: opts.track });
      await expandContainingSequencesForGeometry(parent, next, opts);
    }
  }

  async function expandParentSequenceForNode(
    node: FlowNode,
    position: { x: number; y: number },
    opts: { allowModifier: boolean },
  ): Promise<void> {
    if (!canExpandParentSequence(node, opts)) {
      return;
    }

    const parent = parentSequenceForNode(node);
    if (!parent) {
      return;
    }

    const current = sequenceGeometry(parent);
    const bounds = nodeBounds(node, position);
    if (!current || !bounds) {
      return;
    }

    const geometry = expandGeometryToContainBounds(current, bounds);
    if (geometryChanged(current, geometry)) {
      await applySequenceGeometry(parent, geometry, { track: true });
      await expandContainingSequencesForGeometry(parent, geometry, {
        allowModifier: opts.allowModifier,
        track: true,
      });
    }
  }

  function pushSequenceGeometry(sequence: FlowNode, geometry: SequenceGeometry): void {
    runtime.hookProxy.pushEvent("update_sequence_config", {
      id: sequence.nodeId,
      position_x: geometry.x,
      position_y: geometry.y,
      width: geometry.width,
      height: geometry.height,
    });
  }

  function flushPendingSequenceGeometry(): void {
    for (const patch of runtime.pendingSequenceGeometry.values()) {
      runtime.hookProxy.pushEvent("update_sequence_config", {
        id: patch.nodeId,
        position_x: patch.x,
        position_y: patch.y,
        width: patch.width,
        height: patch.height,
      });
    }
    runtime.pendingSequenceGeometry.clear();
  }

  async function handleSequenceResize(event: Event): Promise<void> {
    if (!runtime.editor || !runtime.area || runtime.destroyed) {
      return;
    }

    const { reteId, width, height, commit } = (event as CustomEvent<SequenceResizeDetail>).detail;
    const node = runtime.editor.getNode(String(reteId));
    if (!node || node.nodeType !== "sequence") {
      return;
    }

    const current = sequenceGeometry(node);
    if (!current) {
      return;
    }

    const size = clampSequenceSize(node, { width, height });
    const geometry = { ...current, width: size.width, height: size.height };
    await applySequenceGeometry(node, geometry, { track: false });
    await expandContainingSequencesForGeometry(node, geometry, {
      allowModifier: true,
      track: commit,
    });

    if (commit) {
      pushSequenceGeometry(node, geometry);
      flushPendingSequenceGeometry();
    }
  }

  return {
    handleSequenceResize,
    nodeView,
    fitSequencesToChildren,
    expandParentSequenceForNode,
    flushPendingSequenceGeometry,
  };
}
