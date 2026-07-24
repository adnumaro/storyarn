import { ClassicPreset } from "rete";
import { beforeEach, describe, expect, it, vi } from "vitest";

import { FlowNode } from "@modules/flows/editor/lib/flow-node";
import type { FlowConnection } from "@modules/flows/editor/lib/rete-schemes";
import { navigation } from "@modules/flows/editor/services/navigation";

const zoomAt = vi.fn();

vi.mock("rete-area-plugin", () => ({
  AreaExtensions: {
    zoomAt: (...args: unknown[]) => zoomAt(...args),
  },
}));

function node(type: string, id: number, data: Record<string, unknown> = {}): FlowNode {
  const n = new FlowNode(type, id, data);
  n.id = `node-${id}`;
  return n;
}

function connection(
  source: FlowNode,
  sourceOutput: string,
  target: FlowNode,
  targetInput: string,
): FlowConnection {
  const conn = new ClassicPreset.Connection(source, sourceOutput, target, targetInput);
  conn.id = `conn-${sourceOutput}`;
  return conn as FlowConnection;
}

/**
 * Minimal rete doubles: navigation only reads `nodeViews`/`connectionViews`
 * and the editor's node/connection lists.
 */
function setup(nodes: FlowNode[], connections: FlowConnection[]) {
  const nodeViews = new Map(
    nodes.map((n) => {
      const element = document.createElement("div");
      const inner = document.createElement("div");
      inner.dataset.testid = "node";
      element.appendChild(inner);
      return [n.id, { element }];
    }),
  );

  const connectionViews = new Map(
    connections.map((c) => [c.id, { element: document.createElement("div") }]),
  );

  const area = { nodeViews, connectionViews } as never;
  const editor = { getNodes: () => nodes, getConnections: () => connections } as never;
  const nodeMap = new Map<string | number, FlowNode>(nodes.map((n) => [n.nodeId, n]));

  return {
    handler: navigation(area, nodeMap, vi.fn(), editor),
    connectionViews,
    nodeViews,
  };
}

describe("navigation.navigateToConnection", () => {
  beforeEach(() => {
    zoomAt.mockClear();
  });

  it("highlights the connection matching the exact pin pair", () => {
    const dialogue = node("dialogue", 1, {
      responses: [{ id: "r1" }, { id: "r2" }],
    });
    const target = node("exit", 2);
    const first = connection(dialogue, "r1", target, "input");
    const second = connection(dialogue, "r2", target, "input");

    const { handler, connectionViews } = setup([dialogue, target], [first, second]);

    handler.navigateToConnection({
      sourceDbId: 1,
      sourcePin: "r2",
      targetDbId: 2,
      targetPin: "input",
    });

    expect(zoomAt).toHaveBeenCalledTimes(1);
    expect(
      connectionViews.get("conn-r2")!.element.style.getPropertyValue("--conn-evidence-stroke"),
    ).not.toBe("");
    // The parallel edge on another pin is never styled as the evidence.
    expect(
      connectionViews.get("conn-r1")!.element.style.getPropertyValue("--conn-evidence-stroke"),
    ).toBe("");
  });

  it("falls back to the endpoint nodes when the edge is not rendered", () => {
    const dialogue = node("dialogue", 1, { responses: [{ id: "r1" }] });
    const target = node("exit", 2);
    const rendered = connection(dialogue, "r1", target, "input");

    const { handler, connectionViews, nodeViews } = setup([dialogue, target], [rendered]);

    // A stale pin ("r9") has no socket, so the canvas never drew that edge.
    handler.navigateToConnection({
      sourceDbId: 1,
      sourcePin: "r9",
      targetDbId: 2,
      targetPin: "input",
    });

    expect(
      connectionViews.get("conn-r1")!.element.style.getPropertyValue("--conn-evidence-stroke"),
    ).toBe("");

    for (const view of nodeViews.values()) {
      const el = view.element.querySelector("[data-testid='node']") as HTMLElement;
      expect(el.classList.contains("nav-highlight")).toBe(true);
    }
  });

  it("does nothing when an endpoint node is gone", () => {
    const dialogue = node("dialogue", 1, { responses: [{ id: "r1" }] });
    const target = node("exit", 2);
    const rendered = connection(dialogue, "r1", target, "input");

    const { handler } = setup([dialogue, target], [rendered]);

    handler.navigateToConnection({
      sourceDbId: 1,
      sourcePin: "r1",
      targetDbId: 999,
      targetPin: "input",
    });

    expect(zoomAt).not.toHaveBeenCalled();
  });

  it("never touches the debug panel's --conn-* variables", () => {
    const dialogue = node("dialogue", 1, { responses: [{ id: "r1" }] });
    const target = node("exit", 2);
    const rendered = connection(dialogue, "r1", target, "input");

    const { handler, connectionViews } = setup([dialogue, target], [rendered]);
    const el = connectionViews.get("conn-r1")!.element;
    // An active debug highlight on the same edge.
    el.style.setProperty("--conn-stroke", "debug-color");

    handler.navigateToConnection({
      sourceDbId: 1,
      sourcePin: "r1",
      targetDbId: 2,
      targetPin: "input",
    });
    handler.clearHighlights();

    expect(el.style.getPropertyValue("--conn-stroke")).toBe("debug-color");
    expect(el.style.getPropertyValue("--conn-evidence-stroke")).toBe("");
  });
});
