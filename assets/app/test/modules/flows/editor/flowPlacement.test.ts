import { afterEach, describe, expect, it, vi } from "vitest";
import { nextTick } from "vue";

import {
  cancelFlowPlacement,
  startFlowPlacement,
} from "@modules/flows/editor/lib/flow-placement-state";
import { createFlowPlacement } from "@modules/flows/editor/services/flowPlacement";

function pointerEvent(type: string, init: MouseEventInit): Event {
  return new MouseEvent(type, {
    bubbles: true,
    cancelable: true,
    button: 0,
    ...init,
  });
}

function setupPlacement() {
  const container = document.createElement("div");
  document.body.appendChild(container);
  Object.defineProperty(container, "getBoundingClientRect", {
    value: () => ({
      left: 10,
      top: 20,
      width: 1000,
      height: 800,
      right: 1010,
      bottom: 820,
      x: 10,
      y: 20,
      toJSON: () => ({}),
    }),
  });

  const area = {
    area: {
      transform: { x: 100, y: 50, k: 2 },
    },
    nodeViews: new Map(),
  };
  const nodes: unknown[] = [];
  const editor = {
    getNodes: () => nodes,
    getNode: (id: string) => nodes.find((node) => (node as { id?: string }).id === id) ?? undefined,
  };
  const pushEvent = vi.fn();
  const teardown = createFlowPlacement({
    containerEl: container,
    editor: editor as never,
    area: area as never,
    pushEvent,
  });

  return { container, area, nodes, pushEvent, teardown };
}

afterEach(() => {
  cancelFlowPlacement();
  document.body.innerHTML = "";
});

describe("createFlowPlacement", () => {
  it("shows a placement shadow while a dock node is pending", async () => {
    const { container, teardown } = setupPlacement();

    startFlowPlacement({ kind: "node", type: "dialogue" });
    await nextTick();
    container.dispatchEvent(pointerEvent("pointermove", { clientX: 500, clientY: 300 }));

    const shadow = container.querySelector<HTMLElement>(".flow-placement-shadow");
    expect(container.classList.contains("flow-placement-active")).toBe(true);
    expect(shadow?.dataset.kind).toBe("dialogue");
    expect(shadow?.style.display).toBe("block");

    teardown();
  });

  it("creates a node at the clicked canvas coordinates and clears placement", async () => {
    const { container, pushEvent, teardown } = setupPlacement();

    startFlowPlacement({ kind: "node", type: "dialogue" });
    await nextTick();
    container.dispatchEvent(pointerEvent("pointerdown", { clientX: 500, clientY: 300 }));
    await nextTick();

    expect(pushEvent).toHaveBeenCalledWith("add_node", {
      type: "dialogue",
      position_x: 195,
      position_y: 115,
    });
    expect(container.classList.contains("flow-placement-active")).toBe(false);

    teardown();
  });

  it("creates annotations through the annotation event", async () => {
    const { container, pushEvent, teardown } = setupPlacement();

    startFlowPlacement({ kind: "annotation" });
    await nextTick();
    container.dispatchEvent(pointerEvent("pointerdown", { clientX: 320, clientY: 240 }));

    expect(pushEvent).toHaveBeenCalledWith("add_annotation", {
      position_x: 105,
      position_y: 85,
    });

    teardown();
  });

  it("sets parent_id when placement is inside a sequence", async () => {
    const { container, area, nodes, pushEvent, teardown } = setupPlacement();
    const sequence = {
      id: "node-10",
      nodeId: 10,
      nodeType: "sequence",
      width: 300,
      height: 200,
    };
    nodes.push(sequence);
    area.nodeViews.set(sequence.id, {
      position: { x: 150, y: 80 },
    });

    startFlowPlacement({ kind: "node", type: "dialogue" });
    await nextTick();
    container.dispatchEvent(pointerEvent("pointerdown", { clientX: 500, clientY: 300 }));

    expect(pushEvent).toHaveBeenCalledWith("add_node", {
      type: "dialogue",
      position_x: 195,
      position_y: 115,
      parent_id: 10,
    });

    teardown();
  });

  it("cancels pending placement with Escape", async () => {
    const { container, teardown } = setupPlacement();

    startFlowPlacement({ kind: "node", type: "sequence" });
    await nextTick();
    document.dispatchEvent(new KeyboardEvent("keydown", { key: "Escape", bubbles: true }));
    await nextTick();

    expect(container.classList.contains("flow-placement-active")).toBe(false);
    expect(container.querySelector(".flow-placement-shadow")).toBeNull();

    teardown();
  });
});
