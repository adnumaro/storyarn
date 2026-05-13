import { ClassicPreset } from "rete";
import { describe, expect, it } from "vitest";

import { FlowNode } from "@modules/flows/editor/lib/flow-node";
import type { FlowConnection } from "@modules/flows/editor/lib/rete-schemes";
import {
  buildFlowElkGraph,
  FLOW_AUTO_LAYOUT_OPTIONS,
} from "@modules/flows/editor/services/flowAutoLayout";

function node(type: string, id: number, parent?: string): FlowNode {
  const n = new FlowNode(type, id);
  n.id = `node-${id}`;
  n.width = 190;
  n.height = 130;
  n.parent = parent;
  return n;
}

function connection(source: FlowNode, sourceOutput: string, target: FlowNode, targetInput: string) {
  const conn = new ClassicPreset.Connection(source, sourceOutput, target, targetInput);
  conn.id = `conn-${source.nodeId}-${target.nodeId}`;
  return conn as FlowConnection;
}

describe("buildFlowElkGraph", () => {
  it("serializes nodes, ports, and root-level edges with the current classic layout", () => {
    const entry = node("entry", 1);
    const dialogue = node("dialogue", 2);
    const conn = connection(entry, "output", dialogue, "input");

    const graph = buildFlowElkGraph([entry, dialogue], [conn]);

    expect(graph.layoutOptions).toEqual(FLOW_AUTO_LAYOUT_OPTIONS);
    expect(graph.children?.map((child) => child.id)).toEqual(["node-1", "node-2"]);
    expect(graph.edges).toEqual([
      {
        id: "conn-1-2",
        sources: ["node-1_output_output"],
        targets: ["node-2_input_input"],
      },
    ]);

    expect(graph.children?.[0]?.ports).toEqual([
      {
        id: "node-1_output_output",
        width: 15,
        height: 15,
        x: 0,
        y: 35,
        properties: { side: "EAST" },
      },
    ]);
    expect(graph.children?.[1]?.ports).toEqual([
      {
        id: "node-2_input_input",
        width: 15,
        height: 15,
        x: 0,
        y: 80,
        properties: { side: "WEST" },
      },
      {
        id: "node-2_output_output",
        width: 15,
        height: 15,
        x: 0,
        y: 35,
        properties: { side: "EAST" },
      },
    ]);
  });

  it("preserves sequence hierarchy through node parent ids", () => {
    const parentSequence = node("sequence", 10);
    const childSequence = node("sequence", 11, parentSequence.id);
    const dialogue = node("dialogue", 12, childSequence.id);
    const outside = node("exit", 13);

    const graph = buildFlowElkGraph([parentSequence, childSequence, dialogue, outside], []);
    const rootIds = graph.children?.map((child) => child.id);
    const nestedSequence = graph.children?.[0]?.children?.[0];

    expect(rootIds).toEqual(["node-10", "node-13"]);
    expect(nestedSequence?.id).toBe("node-11");
    expect(nestedSequence?.children?.map((child) => child.id)).toEqual(["node-12"]);
  });

  it("allows callers to override ELK layout options without replacing defaults", () => {
    const graph = buildFlowElkGraph([node("entry", 1)], [], {
      "elk.direction": "DOWN",
    });

    expect(graph.layoutOptions).toMatchObject({
      "elk.algorithm": "layered",
      "elk.hierarchyHandling": "INCLUDE_CHILDREN",
      "elk.direction": "DOWN",
    });
  });
});
