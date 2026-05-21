import { describe, expect, it } from "vitest";

import { createFlowSequenceGeometry } from "@modules/flows/editor/composables/flowSequenceGeometry";
import type { FlowCanvasRuntime } from "@modules/flows/editor/composables/flowCanvasRuntime";
import type { NodeView } from "@modules/flows/editor/composables/flowCanvasTypes";
import { FlowNode } from "@modules/flows/editor/lib/flow-node";

interface TestNodeOptions {
  x: number;
  y: number;
  width?: number;
  height?: number;
  parent?: string;
}

interface ResizeCall {
  id: string;
  width: number;
  height: number;
}

interface UpdateCall {
  type: string;
  id: string;
}

interface PushedEvent {
  event: string;
  payload: Record<string, unknown>;
}

function createNode(type: string, id: number, opts: TestNodeOptions): FlowNode {
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

function createHarness() {
  const nodes = new Map<string, FlowNode>();
  const nodeViews = new Map<string, NodeView>();
  const resizeCalls: ResizeCall[] = [];
  const updateCalls: UpdateCall[] = [];
  const pushedEvents: PushedEvent[] = [];
  let loadingDepth = 0;

  const editor = {
    getNode(id: string) {
      return nodes.get(id);
    },
    getNodes() {
      return [...nodes.values()];
    },
    getConnections() {
      return [{ id: "connection-1" }];
    },
  };

  const area = {
    nodeViews,
    async resize(id: string, width: number, height: number) {
      resizeCalls.push({ id, width, height });
    },
    async update(type: string, id: string) {
      updateCalls.push({ type, id });
    },
  };

  const runtime = {
    editor,
    area,
    destroyed: false,
    pendingSequenceGeometry: new Map(),
    hookProxy: {
      _flowContext: { selectedReteIds: new Set<string | number>() },
      pushEvent(event: string, payload: Record<string, unknown>) {
        pushedEvents.push({ event, payload });
      },
      enterLoadingFromServer() {
        loadingDepth++;
      },
      exitLoadingFromServer() {
        loadingDepth--;
      },
    },
  } as unknown as FlowCanvasRuntime;

  function addNode(type: string, id: number, opts: TestNodeOptions): FlowNode {
    const node = createNode(type, id, opts);
    nodes.set(node.id, node);
    nodeViews.set(node.id, {
      position: { x: opts.x, y: opts.y },
      element: document.createElement("div"),
    });
    return node;
  }

  function view(node: FlowNode): NodeView {
    const nodeView = nodeViews.get(node.id);
    if (!nodeView) {
      throw new Error(`Missing node view for ${node.id}`);
    }
    return nodeView;
  }

  function select(...ids: (string | number)[]) {
    runtime.hookProxy._flowContext.selectedReteIds = new Set(ids);
  }

  return {
    runtime,
    controller: createFlowSequenceGeometry(runtime),
    addNode,
    view,
    resizeCalls,
    updateCalls,
    pushedEvents,
    select,
    get loadingDepth() {
      return loadingDepth;
    },
  };
}

describe("createFlowSequenceGeometry", () => {
  it("fits a sequence around its children and persists tracked geometry", async () => {
    const h = createHarness();
    const sequence = h.addNode("sequence", 1, { x: 0, y: 0, width: 300, height: 200 });
    h.addNode("dialogue", 2, {
      x: 100,
      y: 80,
      width: 360,
      height: 220,
      parent: sequence.id,
    });

    await h.controller.fitSequencesToChildren({ mode: "fit", track: true });

    expect(h.view(sequence).position).toEqual({ x: 80, y: 40 });
    expect(h.view(sequence).element.style.transform).toBe("translate(80px, 40px)");
    expect(sequence.width).toBe(400);
    expect(sequence.height).toBe(280);
    expect(sequence.nodeData).toMatchObject({ width: 400, height: 280 });
    expect(h.resizeCalls).toContainEqual({ id: sequence.id, width: 400, height: 280 });
    expect(h.updateCalls).toContainEqual({ type: "connection", id: "connection-1" });
    expect(h.loadingDepth).toBe(0);

    expect(h.pushedEvents).toEqual([]);
    h.controller.flushPendingSequenceGeometry();
    expect(h.pushedEvents).toEqual([
      {
        event: "update_sequence_config",
        payload: { id: 1, position_x: 80, position_y: 40, width: 400, height: 280 },
      },
    ]);
  });

  it("does not resize a sequence when children already fit in contain mode", async () => {
    const h = createHarness();
    const sequence = h.addNode("sequence", 1, { x: 0, y: 0, width: 300, height: 200 });
    h.addNode("dialogue", 2, {
      x: 50,
      y: 60,
      width: 100,
      height: 80,
      parent: sequence.id,
    });

    await h.controller.fitSequencesToChildren();

    expect(h.view(sequence).position).toEqual({ x: 0, y: 0 });
    expect(sequence.width).toBe(300);
    expect(sequence.height).toBe(200);
    expect(h.resizeCalls).toEqual([]);
    expect(h.pushedEvents).toEqual([]);
    expect(h.loadingDepth).toBe(0);
  });

  it("expands the right and bottom edges when a child collides with the bounds", async () => {
    const h = createHarness();
    const sequence = h.addNode("sequence", 1, { x: 0, y: 0, width: 300, height: 200 });
    const child = h.addNode("dialogue", 2, {
      x: 260,
      y: 150,
      width: 100,
      height: 90,
      parent: sequence.id,
    });

    await h.controller.expandParentSequenceForNode(
      child,
      { x: 260, y: 150 },
      { allowModifier: false },
    );

    expect(h.view(sequence).position).toEqual({ x: 0, y: 0 });
    expect(sequence.width).toBe(380);
    expect(sequence.height).toBe(260);
    expect(h.resizeCalls).toContainEqual({ id: sequence.id, width: 380, height: 260 });

    h.controller.flushPendingSequenceGeometry();
    expect(h.pushedEvents).toEqual([
      {
        event: "update_sequence_config",
        payload: { id: 1, position_x: 0, position_y: 0, width: 380, height: 260 },
      },
    ]);
  });

  it("clamps manual sequence resize so it cannot become smaller than its children", async () => {
    const h = createHarness();
    const sequence = h.addNode("sequence", 1, { x: 0, y: 0, width: 500, height: 400 });
    h.addNode("dialogue", 2, {
      x: 260,
      y: 150,
      width: 100,
      height: 90,
      parent: sequence.id,
    });

    await h.controller.handleSequenceResize(
      new CustomEvent("flow-sequence-resize", {
        detail: {
          reteId: sequence.id,
          nodeId: sequence.nodeId,
          width: 250,
          height: 150,
          commit: true,
        },
      }),
    );

    expect(h.view(sequence).position).toEqual({ x: 0, y: 0 });
    expect(sequence.width).toBe(380);
    expect(sequence.height).toBe(260);
    expect(h.resizeCalls).toContainEqual({ id: sequence.id, width: 380, height: 260 });
    expect(h.pushedEvents).toEqual([
      {
        event: "update_sequence_config",
        payload: { id: 1, position_x: 0, position_y: 0, width: 380, height: 260 },
      },
    ]);
  });

  it("propagates nested sequence growth to parent sequences", async () => {
    const h = createHarness();
    const parent = h.addNode("sequence", 1, { x: 0, y: 0, width: 300, height: 200 });
    const sequence = h.addNode("sequence", 2, {
      x: 50,
      y: 50,
      width: 300,
      height: 200,
      parent: parent.id,
    });
    const child = h.addNode("dialogue", 3, {
      x: 330,
      y: 220,
      width: 100,
      height: 80,
      parent: sequence.id,
    });

    await h.controller.expandParentSequenceForNode(
      child,
      { x: 330, y: 220 },
      { allowModifier: false },
    );

    expect(h.view(sequence).position).toEqual({ x: 50, y: 50 });
    expect(sequence.width).toBe(400);
    expect(sequence.height).toBe(270);
    expect(h.view(parent).position).toEqual({ x: 0, y: 0 });
    expect(parent.width).toBe(470);
    expect(parent.height).toBe(340);
    expect(h.resizeCalls).toEqual([
      { id: sequence.id, width: 400, height: 270 },
      { id: parent.id, width: 470, height: 340 },
    ]);

    h.controller.flushPendingSequenceGeometry();
    expect(h.pushedEvents).toEqual([
      {
        event: "update_sequence_config",
        payload: { id: 2, position_x: 50, position_y: 50, width: 400, height: 270 },
      },
      {
        event: "update_sequence_config",
        payload: { id: 1, position_x: 0, position_y: 0, width: 470, height: 340 },
      },
    ]);
  });

  it("does not grow a selected ancestor while it is being dragged with its children", async () => {
    const h = createHarness();
    const sequence = h.addNode("sequence", 1, { x: 0, y: 0, width: 300, height: 200 });
    const child = h.addNode("dialogue", 2, {
      x: 260,
      y: 150,
      width: 100,
      height: 90,
      parent: sequence.id,
    });
    h.select(sequence.id);

    await h.controller.expandParentSequenceForNode(
      child,
      { x: 260, y: 150 },
      { allowModifier: false },
    );

    expect(sequence.width).toBe(300);
    expect(sequence.height).toBe(200);
    expect(h.resizeCalls).toEqual([]);
    expect(h.pushedEvents).toEqual([]);
  });
});
