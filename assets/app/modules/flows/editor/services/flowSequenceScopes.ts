import type { NodeEditor } from "rete";
import type { AreaPlugin } from "rete-area-plugin";

import {
  isReparentModifierActive,
  markDragActive,
  markDragInactive,
  syncReparentModifierFromPointerEvent,
} from "../lib/flow-reparent-state";
import type { FlowContext } from "./editorHandlers";
import type { FlowAreaExtra, FlowSchemes } from "../lib/rete-schemes";

interface SequenceScopeNode {
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

function getScopeNode(
  editor: NodeEditor<FlowSchemes>,
  nodeId: string,
): SequenceScopeNode | undefined {
  return editor.getNode(nodeId) as unknown as SequenceScopeNode | undefined;
}

function hasAncestorInSet(nodeId: string, ids: string[], editor: NodeEditor<FlowSchemes>): boolean {
  let current = getScopeNode(editor, nodeId);
  while (current?.parent) {
    if (ids.includes(current.parent)) {
      return true;
    }
    current = getScopeNode(editor, current.parent);
  }
  return false;
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
  return ids.filter((id) => !hasAncestorInSet(id, ids, editor));
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
  const candidates = editor
    .getNodes()
    .map((node) => {
      const scopeNode = node as unknown as SequenceScopeNode;
      const view = area.nodeViews.get(scopeNode.id) as SequenceScopeView | undefined;
      return view ? { node: scopeNode, view } : null;
    })
    .filter(
      (entry): entry is { node: SequenceScopeNode; view: SequenceScopeView } =>
        Boolean(entry) &&
        entry!.node.nodeType === "sequence" &&
        !movingIds.includes(entry!.node.id) &&
        !hasAncestorInSet(entry!.node.id, movingIds, editor) &&
        pointerInsideSequence(pointer, entry!.node, entry!.view),
    );

  const areaChildren = Array.from(area.area.content.holder.childNodes);
  candidates.sort(
    (a, b) => areaChildren.indexOf(b.view.element) - areaChildren.indexOf(a.view.element),
  );
  return candidates[0]?.node;
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

  for (const node of movingNodes) {
    const previousParent = node.parent;
    node.parent = newParentId;
    if (previousParent !== newParentId) {
      opts.onReparented(node.id, newParentId);
    }
  }
}

export function installFlowSequenceScopes(
  opts: FlowSequenceScopesOptions,
): FlowSequenceScopesController {
  let destroyed = false;

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

  async function handlePipeContext(context: { type: string; data?: unknown }): Promise<void> {
    syncModifierState(context);

    if (context.type === "nodepicked") {
      markDragActive();
    } else if (context.type === "pointerup") {
      markDragInactive();
    } else if (context.type === "nodedragged") {
      await handleNodeDragged(context);
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
