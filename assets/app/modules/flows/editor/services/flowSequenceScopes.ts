import type { NodeEditor } from "rete";
import type { AreaPlugin } from "rete-area-plugin";

import {
  isReparentModifierActive,
  markDragActive,
  markDragInactive,
  syncReparentModifierFromPointerEvent,
} from "../lib/flow-reparent-state";
import {
  createFlowGraphQueries,
  type FlowGraphConnectionLike,
  type FlowGraphQueries,
  type FlowGraphNodeLike,
} from "../lib/flowGraphQueries";
import type { FlowContext } from "./editorHandlers";
import type { FlowAreaExtra, FlowSchemes } from "../lib/rete-schemes";

interface SequenceScopeNode extends FlowGraphNodeLike {
  id: string;
  parent?: string;
  nodeType?: string;
  width: number;
  height: number;
  selected?: boolean;
}

interface SequenceScopeView {
  position: { x: number; y: number };
  element: HTMLElement;
  translate?: (x: number, y: number) => Promise<void> | void;
}

interface SequenceScopeConnection extends FlowGraphConnectionLike {
  id: string;
  source: string;
  target: string;
}

interface SequenceAreaContent {
  holder: HTMLElement;
  reorder?: (element: Element, before: ChildNode | null) => void;
}

export type SequenceReparentListener = (nodeId: string, newParentId: string | undefined) => void;

export interface FlowSequenceScopesController {
  destroy(): void;
}

export interface FlowSequenceScopesOptions {
  area: AreaPlugin<FlowSchemes, FlowAreaExtra>;
  editor: NodeEditor<FlowSchemes>;
  flowContext: FlowContext;
  onReparented: SequenceReparentListener;
}

export interface FlowSequenceStackingOptions {
  area: AreaPlugin<FlowSchemes, FlowAreaExtra>;
  editor: NodeEditor<FlowSchemes>;
}

export type FlowSequenceParentResolution =
  | { ok: true; parentId: string | undefined }
  | {
      ok: false;
      reason:
        | "missing_node"
        | "self_parent"
        | "missing_parent"
        | "parent_not_sequence"
        | "descendant_parent";
    };

function getScopeNode(
  editor: NodeEditor<FlowSchemes>,
  nodeId: string,
): SequenceScopeNode | undefined {
  return editor.getNode(nodeId) as unknown as SequenceScopeNode | undefined;
}

function scopeNodes(editor: NodeEditor<FlowSchemes>): SequenceScopeNode[] {
  return editor.getNodes().map((node) => node as unknown as SequenceScopeNode);
}

function nodeView(
  area: AreaPlugin<FlowSchemes, FlowAreaExtra>,
  nodeId: string,
): SequenceScopeView | undefined {
  return area.nodeViews.get(nodeId) as SequenceScopeView | undefined;
}

function connectionViewElement(
  area: AreaPlugin<FlowSchemes, FlowAreaExtra>,
  connectionId: string,
): Element | null {
  const areaWithConnections = area as unknown as {
    connectionViews?: Map<string, { element: Element }>;
  };
  return areaWithConnections.connectionViews?.get(connectionId)?.element ?? null;
}

function areaContent(area: AreaPlugin<FlowSchemes, FlowAreaExtra>): SequenceAreaContent {
  return area.area.content as unknown as SequenceAreaContent;
}

function reorderElement(
  area: AreaPlugin<FlowSchemes, FlowAreaExtra>,
  element: Element,
  before: ChildNode | null,
): void {
  const content = areaContent(area);
  if (typeof content.reorder === "function") {
    content.reorder(element, before);
    return;
  }

  if (before) {
    content.holder.insertBefore(element, before);
  } else {
    content.holder.appendChild(element);
  }
}

function scopeConnections(editor: NodeEditor<FlowSchemes>): SequenceScopeConnection[] {
  return editor.getConnections() as unknown as SequenceScopeConnection[];
}

export function resolveFlowSequenceParent(
  editor: NodeEditor<FlowSchemes>,
  nodeId: string,
  parentId: string | undefined,
): FlowSequenceParentResolution {
  const graph = createFlowGraphQueries(scopeNodes(editor));
  const node = graph.node(nodeId);
  if (!node) {
    return { ok: false, reason: "missing_node" };
  }

  if (!parentId) {
    return { ok: true, parentId: undefined };
  }

  if (parentId === nodeId) {
    return { ok: false, reason: "self_parent" };
  }

  const parent = graph.node(parentId);
  if (!parent) {
    return { ok: false, reason: "missing_parent" };
  }

  if (parent.nodeType !== "sequence") {
    return { ok: false, reason: "parent_not_sequence" };
  }

  if (graph.hasAncestor(parentId, nodeId)) {
    return { ok: false, reason: "descendant_parent" };
  }

  return { ok: true, parentId };
}

function selectedNodeIds(editor: NodeEditor<FlowSchemes>, flowContext: FlowContext): string[] {
  const contextIds = [...flowContext.selectedReteIds].map(String);
  if (contextIds.length > 0) {
    return contextIds;
  }

  return editor
    .getNodes()
    .filter((node) => (node as unknown as SequenceScopeNode).selected)
    .map((node) => (node as unknown as SequenceScopeNode).id);
}

function selectedNodeIdSet(editor: NodeEditor<FlowSchemes>, flowContext: FlowContext): Set<string> {
  return new Set(selectedNodeIds(editor, flowContext));
}

function hasSelectedAncestorBelowRoot(
  nodeId: string,
  rootId: string,
  selected: Set<string>,
  graph: FlowGraphQueries<SequenceScopeNode, FlowGraphConnectionLike>,
): boolean {
  for (const ancestor of graph.ancestors(nodeId)) {
    if (ancestor.id === rootId) {
      return false;
    }
    if (selected.has(ancestor.id)) {
      return true;
    }
  }
  return false;
}

function currentMovingIds(
  pickedId: string,
  editor: NodeEditor<FlowSchemes>,
  flowContext: FlowContext,
): string[] {
  const selected = selectedNodeIds(editor, flowContext);
  if (selected.includes(pickedId)) {
    return selected;
  }
  return [pickedId];
}

function movingRootIds(ids: string[], editor: NodeEditor<FlowSchemes>): string[] {
  const graph = createFlowGraphQueries(scopeNodes(editor));
  return ids.filter((id) => !graph.hasAnyAncestor(id, ids));
}

function pointerInsideSequence(
  pointer: { x: number; y: number },
  node: SequenceScopeNode,
  view: SequenceScopeView,
): boolean {
  return (
    pointer.x > view.position.x &&
    pointer.y > view.position.y &&
    pointer.x < view.position.x + node.width &&
    pointer.y < view.position.y + node.height
  );
}

function resolveDropTarget(
  pointer: { x: number; y: number },
  movingIds: string[],
  editor: NodeEditor<FlowSchemes>,
  area: AreaPlugin<FlowSchemes, FlowAreaExtra>,
): SequenceScopeNode | undefined {
  const graph = createFlowGraphQueries(scopeNodes(editor));
  const candidates = graph
    .nodes()
    .map((node) => {
      const view = nodeView(area, node.id);
      return view ? { node, view } : null;
    })
    .filter(
      (entry): entry is { node: SequenceScopeNode; view: SequenceScopeView } =>
        Boolean(entry) &&
        entry!.node.nodeType === "sequence" &&
        !movingIds.includes(entry!.node.id) &&
        !graph.hasAnyAncestor(entry!.node.id, movingIds) &&
        pointerInsideSequence(pointer, entry!.node, entry!.view),
    );

  const areaChildren = Array.from(areaContent(area).holder.childNodes);
  candidates.sort(
    (a, b) => areaChildren.indexOf(b.view.element) - areaChildren.indexOf(a.view.element),
  );
  return candidates[0]?.node;
}

function bringConnectionForward(
  connectionId: string,
  area: AreaPlugin<FlowSchemes, FlowAreaExtra>,
): void {
  const element = connectionViewElement(area, connectionId);
  if (element) {
    reorderElement(area, element, null);
  }
}

function bringConnectionBack(
  connectionId: string,
  area: AreaPlugin<FlowSchemes, FlowAreaExtra>,
): void {
  const element = connectionViewElement(area, connectionId);
  const firstChild = areaContent(area).holder.firstChild;
  if (element) {
    reorderElement(area, element, firstChild);
  }
}

function bringForward(
  nodeId: string,
  opts: FlowSequenceStackingOptions,
  graph = createFlowGraphQueries(scopeNodes(opts.editor), scopeConnections(opts.editor)),
): void {
  const view = nodeView(opts.area, nodeId);
  const connections = graph.incidentConnections(nodeId);

  for (const connection of connections) {
    bringConnectionForward(connection.id, opts.area);
  }

  if (view) {
    reorderElement(opts.area, view.element, null);
  }

  for (const child of graph.children(nodeId)) {
    bringForward(child.id, opts, graph);
  }
}

export function normalizeFlowSequenceStacking(
  opts: FlowSequenceStackingOptions,
  nodeId?: string,
): void {
  const graph = createFlowGraphQueries(scopeNodes(opts.editor), scopeConnections(opts.editor));

  if (nodeId) {
    const node = graph.node(nodeId);
    if (node) {
      bringForward(graph.topAncestor(node.id)?.id ?? node.id, opts, graph);
    }
    return;
  }

  for (const node of graph.nodes()) {
    if (!node.parent) {
      bringForward(node.id, opts, graph);
    }
  }
}

function syncModifierState(context: { type: string; data?: unknown }): void {
  if (
    context.type !== "pointerdown" &&
    context.type !== "pointermove" &&
    context.type !== "pointerup"
  ) {
    return;
  }

  const event = (context.data as { event?: PointerEvent } | undefined)?.event;
  if (event) {
    syncReparentModifierFromPointerEvent(event);
  }
}

async function reparentNodes(
  ids: string[],
  pointer: { x: number; y: number },
  opts: FlowSequenceScopesOptions,
): Promise<void> {
  const movingIds = movingRootIds(ids, opts.editor);
  const movingNodes = movingIds
    .map((id) => getScopeNode(opts.editor, id))
    .filter((node): node is SequenceScopeNode => Boolean(node));
  const newParentId = resolveDropTarget(pointer, movingIds, opts.editor, opts.area)?.id;
  const changedNodes: SequenceScopeNode[] = [];

  for (const node of movingNodes) {
    const parentChange = resolveFlowSequenceParent(opts.editor, node.id, newParentId);
    if (!parentChange.ok) {
      continue;
    }

    const previousParent = node.parent;
    node.parent = parentChange.parentId;
    if (previousParent !== parentChange.parentId) {
      changedNodes.push(node);
      opts.onReparented(node.id, parentChange.parentId);
    }
  }

  for (const node of changedNodes) {
    normalizeFlowSequenceStacking(opts, node.id);
  }
}

export function installFlowSequenceScopes(
  opts: FlowSequenceScopesOptions,
): FlowSequenceScopesController {
  let destroyed = false;
  const activeTranslations = new Map<string, number>();

  function incrementTranslation(nodeId: string): void {
    activeTranslations.set(nodeId, (activeTranslations.get(nodeId) ?? 0) + 1);
  }

  function decrementTranslation(nodeId: string): void {
    const next = (activeTranslations.get(nodeId) ?? 0) - 1;
    if (next <= 0) {
      activeTranslations.delete(nodeId);
    } else {
      activeTranslations.set(nodeId, next);
    }
  }

  function isTranslating(nodeId: string): boolean {
    return (activeTranslations.get(nodeId) ?? 0) > 0;
  }

  async function translateNode(node: SequenceScopeNode, dx: number, dy: number): Promise<void> {
    const view = nodeView(opts.area, node.id);
    if (!view) {
      return;
    }

    const x = view.position.x + dx;
    const y = view.position.y + dy;
    incrementTranslation(node.id);
    try {
      if (typeof view.translate === "function") {
        await view.translate(x, y);
      } else {
        view.position = { x, y };
        view.element.style.transform = `translate(${x}px, ${y}px)`;
      }
    } finally {
      decrementTranslation(node.id);
    }
  }

  async function translateDescendants(
    sequence: SequenceScopeNode,
    data: { position: { x: number; y: number }; previous: { x: number; y: number } },
  ): Promise<void> {
    const dx = data.position.x - data.previous.x;
    const dy = data.position.y - data.previous.y;
    if (dx === 0 && dy === 0) {
      return;
    }

    const selected = selectedNodeIdSet(opts.editor, opts.flowContext);
    const graph = createFlowGraphQueries(scopeNodes(opts.editor));
    const movableDescendants = graph
      .descendants(sequence.id)
      .filter(
        (node) =>
          !selected.has(node.id) &&
          !node.selected &&
          !hasSelectedAncestorBelowRoot(node.id, sequence.id, selected, graph),
      );

    for (const node of movableDescendants) {
      await translateNode(node, dx, dy);
    }
  }

  async function handleNodeDragged(context: { type: string; data?: unknown }): Promise<void> {
    const draggedId = (context.data as { id?: string } | undefined)?.id;
    markDragInactive();
    if (!draggedId || !isReparentModifierActive()) {
      return;
    }

    await reparentNodes(
      currentMovingIds(draggedId, opts.editor, opts.flowContext),
      opts.area.area.pointer,
      opts,
    );
  }

  async function handleNodeTranslated(context: { type: string; data?: unknown }): Promise<void> {
    const data = context.data as
      | { id?: string; position?: { x: number; y: number }; previous?: { x: number; y: number } }
      | undefined;
    if (!data?.id || !data.position || !data.previous || isTranslating(data.id)) {
      return;
    }

    const node = getScopeNode(opts.editor, data.id);
    if (node?.nodeType === "sequence") {
      await translateDescendants(node, { position: data.position, previous: data.previous });
    }
  }

  function handleConnectionCreated(context: { type: string; data?: unknown }): void {
    const connectionId = (context.data as { id?: string } | undefined)?.id;
    if (!connectionId) {
      return;
    }

    const connection = scopeConnections(opts.editor).find(({ id }) => id === connectionId);
    if (!connection) {
      return;
    }

    bringConnectionBack(connection.id, opts.area);
    bringForward(connection.source, opts);
    bringForward(connection.target, opts);
  }

  async function handlePipeContext(context: { type: string; data?: unknown }): Promise<void> {
    syncModifierState(context);

    if (context.type === "nodepicked") {
      markDragActive();
      const pickedId = (context.data as { id?: string } | undefined)?.id;
      if (pickedId) {
        normalizeFlowSequenceStacking(opts, pickedId);
      }
    } else if (context.type === "pointerup") {
      markDragInactive();
    } else if (context.type === "nodedragged") {
      await handleNodeDragged(context);
    } else if (context.type === "nodetranslated") {
      await handleNodeTranslated(context);
    } else if (context.type === "connectioncreated") {
      handleConnectionCreated(context);
    }
  }

  opts.area.addPipe(async (raw) => {
    const candidate = raw as unknown;
    if (destroyed || !candidate || typeof candidate !== "object" || !("type" in candidate)) {
      return raw;
    }

    const context = candidate as { type: string; data?: unknown };
    await handlePipeContext(context);
    return raw;
  });

  return {
    destroy() {
      destroyed = true;
      markDragInactive();
    },
  };
}
