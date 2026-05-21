export interface FlowGraphNodeLike {
  id: string;
  parent?: string;
}

export interface FlowGraphConnectionLike {
  id: string;
  source: string;
  target: string;
}

export interface FlowGraphQueries<
  Node extends FlowGraphNodeLike,
  Connection extends FlowGraphConnectionLike,
> {
  nodes(): Node[];
  connections(): Connection[];
  node(id: string): Node | undefined;
  children(parentId: string | undefined): Node[];
  descendants(parentId: string): Node[];
  ancestors(nodeId: string): Node[];
  hasAncestor(nodeId: string, ancestorId: string): boolean;
  hasAnyAncestor(nodeId: string, ancestorIds: Iterable<string>): boolean;
  depth(nodeId: string): number;
  deepestFirst(predicate?: (node: Node) => boolean): Node[];
  topAncestor(nodeId: string): Node | undefined;
  incidentConnections(nodeId: string): Connection[];
  incomingConnections(nodeId: string): Connection[];
  outgoingConnections(nodeId: string): Connection[];
}

export function createFlowGraphQueries<
  Node extends FlowGraphNodeLike,
  Connection extends FlowGraphConnectionLike = FlowGraphConnectionLike,
>(
  nodes: Iterable<Node>,
  connections: Iterable<Connection> = [],
): FlowGraphQueries<Node, Connection> {
  const nodeList = Array.from(nodes);
  const connectionList = Array.from(connections);
  const nodeById = new Map(nodeList.map((node) => [node.id, node]));
  const childrenByParent = new Map<string | undefined, Node[]>();
  const incidentByNode = new Map<string, Connection[]>();
  const incomingByNode = new Map<string, Connection[]>();
  const outgoingByNode = new Map<string, Connection[]>();

  for (const node of nodeList) {
    const children = childrenByParent.get(node.parent) ?? [];
    children.push(node);
    childrenByParent.set(node.parent, children);
  }

  for (const connection of connectionList) {
    const sourceIncident = incidentByNode.get(connection.source) ?? [];
    sourceIncident.push(connection);
    incidentByNode.set(connection.source, sourceIncident);

    if (connection.target !== connection.source) {
      const targetIncident = incidentByNode.get(connection.target) ?? [];
      targetIncident.push(connection);
      incidentByNode.set(connection.target, targetIncident);
    }

    const outgoing = outgoingByNode.get(connection.source) ?? [];
    outgoing.push(connection);
    outgoingByNode.set(connection.source, outgoing);

    const incoming = incomingByNode.get(connection.target) ?? [];
    incoming.push(connection);
    incomingByNode.set(connection.target, incoming);
  }

  function node(id: string): Node | undefined {
    return nodeById.get(id);
  }

  function children(parentId: string | undefined): Node[] {
    return childrenByParent.get(parentId) ?? [];
  }

  function descendants(parentId: string): Node[] {
    const result: Node[] = [];
    const visited = new Set<string>();

    function visit(id: string): void {
      if (visited.has(id)) {
        return;
      }
      visited.add(id);

      for (const child of children(id)) {
        result.push(child);
        visit(child.id);
      }
    }

    visit(parentId);
    return result;
  }

  function ancestors(nodeId: string): Node[] {
    const result: Node[] = [];
    const visited = new Set<string>();
    let current = node(nodeId);

    while (current?.parent) {
      if (current.parent === nodeId) {
        break;
      }

      if (visited.has(current.parent)) {
        break;
      }
      visited.add(current.parent);

      const parent = node(current.parent);
      if (!parent) {
        break;
      }

      result.push(parent);
      current = parent;
    }

    return result;
  }

  function hasAncestor(nodeId: string, ancestorId: string): boolean {
    return ancestors(nodeId).some((ancestor) => ancestor.id === ancestorId);
  }

  function hasAnyAncestor(nodeId: string, ancestorIds: Iterable<string>): boolean {
    const idSet = ancestorIds instanceof Set ? ancestorIds : new Set(ancestorIds);
    return ancestors(nodeId).some((ancestor) => idSet.has(ancestor.id));
  }

  function depth(nodeId: string): number {
    return ancestors(nodeId).length;
  }

  function deepestFirst(predicate: (node: Node) => boolean = () => true): Node[] {
    return nodeList.filter(predicate).sort((a, b) => depth(b.id) - depth(a.id));
  }

  function topAncestor(nodeId: string): Node | undefined {
    const current = node(nodeId);
    const allAncestors = ancestors(nodeId);
    return allAncestors[allAncestors.length - 1] ?? current;
  }

  function incidentConnections(nodeId: string): Connection[] {
    return incidentByNode.get(nodeId) ?? [];
  }

  function incomingConnections(nodeId: string): Connection[] {
    return incomingByNode.get(nodeId) ?? [];
  }

  function outgoingConnections(nodeId: string): Connection[] {
    return outgoingByNode.get(nodeId) ?? [];
  }

  return {
    nodes: () => nodeList,
    connections: () => connectionList,
    node,
    children,
    descendants,
    ancestors,
    hasAncestor,
    hasAnyAncestor,
    depth,
    deepestFirst,
    topAncestor,
    incidentConnections,
    incomingConnections,
    outgoingConnections,
  };
}
