import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { flushPromises } from "@vue/test-utils";
import { withSetup } from "@app/test/setup";
import {
  startFlowPlacement,
  cancelFlowPlacement,
} from "@modules/flows/editor/lib/flow-placement-state";
import { useFlowCanvas } from "@modules/flows/editor/composables/useFlowCanvas";
import type { HookProxy } from "@modules/flows/editor/services/editorHandlers";
import type { App } from "vue";

const mocks = vi.hoisted(() => ({
  createPlugins: vi.fn(),
  finalizeSetup: vi.fn(),
  fitSequencesToChildren: vi.fn(),
}));
vi.mock("@modules/flows/editor/services/reteSetup", () => mocks);
vi.mock("@modules/flows/editor/services/editorHandlers", () => ({
  editorHandlers: () => ({ init: vi.fn(), destroy: vi.fn() }),
}));
vi.mock("@modules/flows/editor/services/navigation", () => ({
  navigation: () => ({ destroy: vi.fn() }),
}));
vi.mock("@modules/flows/editor/services/debug", () => ({ debug: () => ({ destroy: vi.fn() }) }));
vi.mock("@modules/flows/editor/services/lod", () => ({
  lod: () => ({ destroy: vi.fn(), onZoom: vi.fn() }),
}));
vi.mock("@modules/flows/editor/services/flowMarquee", () => ({
  createFlowMarquee: vi.fn(() => vi.fn()),
}));
vi.mock("@modules/flows/editor/composables/flowSequenceGeometry", () => ({
  createFlowSequenceGeometry: () => ({
    fitSequencesToChildren: mocks.fitSequencesToChildren,
    handleSequenceResize: vi.fn(),
    nodeView: vi.fn(),
    expandParentSequenceForNode: vi.fn(),
    flushPendingSequenceGeometry: vi.fn(),
  }),
}));

let mounted: App[] = [];
let nodes: Array<Record<string, unknown>> = [];
let nodeViews = new Map<string, { position: { x: number; y: number }; element: HTMLElement }>();
beforeEach(() => {
  vi.clearAllMocks();
  nodes = [];
  nodeViews = new Map();
  mocks.fitSequencesToChildren.mockResolvedValue(undefined);
  vi.stubGlobal("requestAnimationFrame", (callback: FrameRequestCallback) => {
    queueMicrotask(() => callback(0));
    return 1;
  });
  mocks.createPlugins.mockImplementation((container: HTMLElement, hook: HookProxy) => {
    hook._flowContext = {
      sheetsMap: {},
      hubsMap: {},
      lod: "full",
      editingNodeId: null,
      onInlineEditSave: null,
      nodeDataVersion: 0,
      selectedReteNodeId: null,
      selectedReteIds: new Set(),
      canEdit: true,
      toolbarProps: {},
      zoom: 1,
    };
    const getNode = (id: string) => nodes.find((node) => node.id === id);
    return {
      editor: { getNodes: () => nodes, getNode, getConnections: () => [], addPipe: vi.fn() },
      area: {
        container,
        nodeViews,
        area: { transform: { x: 0, y: 0, k: 1 } },
        addPipe: vi.fn(),
        destroy: vi.fn(),
      },
      connection: {},
      history: null,
      minimap: null,
    };
  });
});
afterEach(() => {
  for (const app of mounted) app.unmount();
  mounted = [];
  cancelFlowPlacement();
  document.body.innerHTML = "";
  vi.unstubAllGlobals();
});

async function beginLoading(options: { holdGeometry?: boolean; sequence?: boolean } = {}) {
  let finishFit!: () => void;
  let finishGeometry = () => {};
  if (options.sequence) {
    nodes.push({
      id: "node-10",
      nodeId: 10,
      nodeType: "sequence",
      width: 100,
      height: 100,
    });
    nodeViews.set("node-10", {
      position: { x: 0, y: 0 },
      element: document.createElement("div"),
    });
  }
  if (options.holdGeometry) {
    mocks.fitSequencesToChildren.mockReturnValue(
      new Promise<void>((resolve) => {
        finishGeometry = resolve;
      }),
    );
  }
  mocks.finalizeSetup.mockReturnValue(
    new Promise((resolve) => {
      finishFit = () => resolve({ selector: {}, select: vi.fn(), unselect: vi.fn() });
    }),
  );
  const pushEvent = vi.fn();
  const { result, app } = withSetup(() => useFlowCanvas({ pushEvent, handleEvent: vi.fn() }));
  mounted.push(app);
  const container = document.createElement("div");
  document.body.append(container);
  let ready = false;
  const initialized = result.init(container, { nodes: [], connections: [] }).then(() => {
    ready = true;
  });
  await flushPromises();
  if (!options.holdGeometry) expect(mocks.finalizeSetup).toHaveBeenCalledOnce();
  expect(ready).toBe(false);
  return {
    app,
    container,
    pushEvent,
    finishGeometry: () => finishGeometry(),
    finishFit: () => finishFit(),
    initialized,
  };
}

function place(container: HTMLElement) {
  startFlowPlacement({ kind: "node", type: "dialogue" });
  container.dispatchEvent(
    new MouseEvent("pointerdown", {
      bubbles: true,
      cancelable: true,
      button: 0,
      clientX: 180,
      clientY: 160,
    }),
  );
}

describe("dock placement before initial viewport readiness", () => {
  it("accepts the first placement while the viewport fit is still pending", async () => {
    const setup = await beginLoading();
    place(setup.container);
    expect(setup.pushEvent).toHaveBeenCalledWith("add_node", {
      type: "dialogue",
      position_x: 180,
      position_y: 160,
    });
    setup.finishFit();
    await setup.initialized;
  });

  it("removes the early placement handler when unmounted during the pending fit", async () => {
    const setup = await beginLoading();
    setup.app.unmount();
    mounted = [];
    place(setup.container);
    expect(setup.pushEvent).not.toHaveBeenCalled();
    setup.finishFit();
    await setup.initialized;
    place(setup.container);
    expect(setup.pushEvent).not.toHaveBeenCalled();
  });

  it("waits for fitted sequence bounds before resolving parent_id", async () => {
    const setup = await beginLoading({ holdGeometry: true, sequence: true });
    place(setup.container);
    expect(setup.pushEvent).not.toHaveBeenCalled();

    Object.assign(nodes[0], { width: 300, height: 300 });
    setup.finishGeometry();
    await flushPromises();
    expect(setup.pushEvent).toHaveBeenCalledWith("add_node", {
      type: "dialogue",
      position_x: 180,
      position_y: 160,
      parent_id: 10,
    });

    setup.finishFit();
    await setup.initialized;
  });

  it("invalidates a captured sequence placement when unmounted during geometry fitting", async () => {
    const setup = await beginLoading({ holdGeometry: true, sequence: true });
    place(setup.container);
    setup.app.unmount();
    mounted = [];

    Object.assign(nodes[0], { width: 300, height: 300 });
    setup.finishGeometry();
    await flushPromises();
    expect(setup.pushEvent).not.toHaveBeenCalled();

    setup.finishFit();
    await setup.initialized;
  });
});
