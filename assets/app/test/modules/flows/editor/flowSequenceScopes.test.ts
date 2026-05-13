import { afterEach, describe, expect, it } from "vitest";

import { FlowNode } from "@modules/flows/editor/lib/flow-node";
import {
  markDragInactive,
  reparentGestureActive,
  syncReparentModifierFromPointerEvent,
} from "@modules/flows/editor/lib/flow-reparent-state";
import type { FlowContext } from "@modules/flows/editor/services/editorHandlers";
import {
  installFlowSequenceScopes,
  type SequenceReparentListener,
} from "@modules/flows/editor/services/flowSequenceScopes";
import type { FlowAreaExtra, FlowSchemes } from "@modules/flows/editor/lib/rete-schemes";
import type { NodeEditor } from "rete";
import type { AreaPlugin } from "rete-area-plugin";

interface AddNodeOptions {
  x: number;
  y: number;
  width?: number;
  height?: number;
  parent?: string;
}

interface ReparentEvent {
  nodeId: string;
  newParentId: string | undefined;
}

type Pipe = (context: unknown) => unknown | Promise<unknown>;

function createNode(type: string, id: number, opts: AddNodeOptions): FlowNode {
  const node = new FlowNode(type, id, {
    width: opts.width,
    height: opts.height,
  });
  node.id = `node-${id}`;
  node.width = opts.width ?? node.width;
  node.height = opts.height ?? node.height;
  node.parent = opts.parent;
  return node;
}

function modifierEvent(metaKey: boolean): PointerEvent {
  return { ctrlKey: false, metaKey } as PointerEvent;
}

function createHarness() {
  const nodes = new Map<string, FlowNode>();
  const nodeViews = new Map<string, { position: { x: number; y: number }; element: HTMLElement }>();
  const pipes: Pipe[] = [];
  const holder = document.createElement("div");
  const pointer = { x: 0, y: 0 };
  const reparented: ReparentEvent[] = [];

  const editor = {
    getNode(id: string) {
      return nodes.get(id);
    },
    getNodes() {
      return [...nodes.values()];
    },
  } as unknown as NodeEditor<FlowSchemes>;

  const area = {
    nodeViews,
    area: {
      pointer,
      content: { holder },
    },
    addPipe(handler: Pipe) {
      pipes.push(handler);
    },
  } as unknown as AreaPlugin<FlowSchemes, FlowAreaExtra>;

  const flowContext = {
    selectedReteIds: new Set<string | number>(),
  } as FlowContext;

  const onReparented: SequenceReparentListener = (nodeId, newParentId) => {
    reparented.push({ nodeId, newParentId });
  };

  installFlowSequenceScopes({ area, editor, flowContext, onReparented });

  async function emit(context: unknown): Promise<unknown> {
    let current = context;
    for (const pipe of pipes) {
      if (current === undefined) {
        return undefined;
      }
      current = await pipe(current);
    }
    return current;
  }

  function addNode(type: string, id: number, opts: AddNodeOptions): FlowNode {
    const node = createNode(type, id, opts);
    const element = document.createElement("div");
    holder.appendChild(element);
    nodes.set(node.id, node);
    nodeViews.set(node.id, {
      position: { x: opts.x, y: opts.y },
      element,
    });
    return node;
  }

  function select(...ids: (string | number)[]): void {
    flowContext.selectedReteIds = new Set(ids);
  }

  function setPointer(x: number, y: number): void {
    pointer.x = x;
    pointer.y = y;
  }

  return {
    addNode,
    emit,
    reparented,
    select,
    setPointer,
  };
}

afterEach(() => {
  markDragInactive();
  syncReparentModifierFromPointerEvent(modifierEvent(false));
});

describe("installFlowSequenceScopes", () => {
  it("does not reparent dragged nodes without Cmd/Ctrl", async () => {
    const h = createHarness();
    const sequence = h.addNode("sequence", 1, { x: 0, y: 0, width: 300, height: 200 });
    const dialogue = h.addNode("dialogue", 2, { x: 400, y: 0 });

    h.setPointer(50, 50);
    await h.emit({ type: "pointerdown", data: { event: modifierEvent(false) } });
    await h.emit({ type: "nodepicked", data: { id: dialogue.id } });
    await h.emit({ type: "nodedragged", data: { id: dialogue.id } });

    expect(dialogue.parent).toBeUndefined();
    expect(sequence.parent).toBeUndefined();
    expect(h.reparented).toEqual([]);
  });

  it("reparents a dragged node to the top-most sequence under the pointer", async () => {
    const h = createHarness();
    const lowerSequence = h.addNode("sequence", 1, { x: 0, y: 0, width: 300, height: 200 });
    const upperSequence = h.addNode("sequence", 2, { x: 0, y: 0, width: 300, height: 200 });
    const dialogue = h.addNode("dialogue", 3, { x: 400, y: 0 });

    h.setPointer(50, 50);
    await h.emit({ type: "pointerdown", data: { event: modifierEvent(true) } });
    await h.emit({ type: "nodepicked", data: { id: dialogue.id } });
    expect(reparentGestureActive.value).toBe(true);

    await h.emit({ type: "nodedragged", data: { id: dialogue.id } });

    expect(dialogue.parent).toBe(upperSequence.id);
    expect(lowerSequence.parent).toBeUndefined();
    expect(reparentGestureActive.value).toBe(false);
    expect(h.reparented).toEqual([{ nodeId: dialogue.id, newParentId: upperSequence.id }]);
  });

  it("reparents to root when Cmd/Ctrl dropping outside any sequence", async () => {
    const h = createHarness();
    const sequence = h.addNode("sequence", 1, { x: 0, y: 0, width: 300, height: 200 });
    const dialogue = h.addNode("dialogue", 2, { x: 50, y: 50, parent: sequence.id });

    h.setPointer(500, 500);
    await h.emit({ type: "pointerdown", data: { event: modifierEvent(true) } });
    await h.emit({ type: "nodepicked", data: { id: dialogue.id } });
    await h.emit({ type: "nodedragged", data: { id: dialogue.id } });

    expect(dialogue.parent).toBeUndefined();
    expect(h.reparented).toEqual([{ nodeId: dialogue.id, newParentId: undefined }]);
  });

  it("dedupes selected descendants when a selected sequence is dragged", async () => {
    const h = createHarness();
    const target = h.addNode("sequence", 1, { x: 0, y: 0, width: 300, height: 200 });
    const sequence = h.addNode("sequence", 2, { x: 400, y: 0, width: 300, height: 200 });
    const child = h.addNode("dialogue", 3, { x: 450, y: 50, parent: sequence.id });
    h.select(sequence.id, child.id);

    h.setPointer(50, 50);
    await h.emit({ type: "pointerdown", data: { event: modifierEvent(true) } });
    await h.emit({ type: "nodepicked", data: { id: sequence.id } });
    await h.emit({ type: "nodedragged", data: { id: sequence.id } });

    expect(sequence.parent).toBe(target.id);
    expect(child.parent).toBe(sequence.id);
    expect(h.reparented).toEqual([{ nodeId: sequence.id, newParentId: target.id }]);
  });

  it("does not allow dropping a sequence into one of its descendants", async () => {
    const h = createHarness();
    const sequence = h.addNode("sequence", 1, { x: 0, y: 0, width: 300, height: 200 });
    const childSequence = h.addNode("sequence", 2, {
      x: 40,
      y: 60,
      width: 200,
      height: 120,
      parent: sequence.id,
    });

    h.setPointer(50, 70);
    await h.emit({ type: "pointerdown", data: { event: modifierEvent(true) } });
    await h.emit({ type: "nodepicked", data: { id: sequence.id } });
    await h.emit({ type: "nodedragged", data: { id: sequence.id } });

    expect(sequence.parent).toBeUndefined();
    expect(childSequence.parent).toBe(sequence.id);
    expect(h.reparented).toEqual([]);
  });

  it("clears the reparent target state on pointerup without a completed drag", async () => {
    const h = createHarness();
    const dialogue = h.addNode("dialogue", 1, { x: 0, y: 0 });

    await h.emit({ type: "pointerdown", data: { event: modifierEvent(true) } });
    await h.emit({ type: "nodepicked", data: { id: dialogue.id } });
    expect(reparentGestureActive.value).toBe(true);

    await h.emit({ type: "pointerup", data: { event: modifierEvent(true) } });

    expect(reparentGestureActive.value).toBe(false);
    expect(h.reparented).toEqual([]);
  });
});
