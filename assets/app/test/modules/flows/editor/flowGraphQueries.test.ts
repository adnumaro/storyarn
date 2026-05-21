import { describe, expect, it } from "vitest";

import { createFlowGraphQueries } from "@modules/flows/editor/lib/flowGraphQueries";

interface TestNode {
  id: string;
  parent?: string;
}

interface TestConnection {
  id: string;
  source: string;
  target: string;
}

function ids(items: Array<{ id: string }>): string[] {
  return items.map((item) => item.id);
}

describe("createFlowGraphQueries", () => {
  const nodes: TestNode[] = [
    { id: "root-a" },
    { id: "root-b" },
    { id: "child-a", parent: "root-a" },
    { id: "nested-a", parent: "child-a" },
    { id: "child-b", parent: "root-b" },
  ];
  const connections: TestConnection[] = [
    { id: "a-b", source: "root-a", target: "root-b" },
    { id: "nested-b", source: "nested-a", target: "root-b" },
    { id: "b-child", source: "root-b", target: "child-b" },
  ];

  it("queries parent-child subgraphs", () => {
    const graph = createFlowGraphQueries(nodes, connections);

    expect(ids(graph.children(undefined))).toEqual(["root-a", "root-b"]);
    expect(ids(graph.children("root-a"))).toEqual(["child-a"]);
    expect(ids(graph.descendants("root-a"))).toEqual(["child-a", "nested-a"]);
    expect(ids(graph.ancestors("nested-a"))).toEqual(["child-a", "root-a"]);
    expect(graph.hasAncestor("nested-a", "root-a")).toBe(true);
    expect(graph.hasAnyAncestor("nested-a", new Set(["root-b", "child-a"]))).toBe(true);
    expect(graph.depth("nested-a")).toBe(2);
    expect(ids(graph.deepestFirst())).toEqual([
      "nested-a",
      "child-a",
      "child-b",
      "root-a",
      "root-b",
    ]);
    expect(graph.topAncestor("nested-a")?.id).toBe("root-a");
  });

  it("queries incident and directional connections", () => {
    const graph = createFlowGraphQueries(nodes, connections);

    expect(ids(graph.incidentConnections("root-b"))).toEqual(["a-b", "nested-b", "b-child"]);
    expect(ids(graph.incomingConnections("root-b"))).toEqual(["a-b", "nested-b"]);
    expect(ids(graph.outgoingConnections("root-b"))).toEqual(["b-child"]);
  });

  it("stops traversal on parent cycles", () => {
    const graph = createFlowGraphQueries([
      { id: "a", parent: "b" },
      { id: "b", parent: "a" },
    ]);

    expect(ids(graph.ancestors("a"))).toEqual(["b"]);
    expect(graph.depth("a")).toBe(1);
  });
});
