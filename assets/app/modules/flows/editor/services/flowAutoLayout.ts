import ELK, {
  type ElkExtendedEdge,
  type ElkNode,
  type ElkPort,
  type ElkShape,
  type LayoutOptions,
} from "elkjs";
import type { NodeEditor, NodeId } from "rete";
import type { AreaPlugin } from "rete-area-plugin";

import type { FlowNode } from "../lib/flow-node";
import { createFlowGraphQueries, type FlowGraphQueries } from "../lib/flowGraphQueries";
import type { FlowAreaExtra, FlowConnection, FlowSchemes } from "../lib/rete-schemes";
import type { Position } from "./historyPreset";

const elk = new ELK();

export const FLOW_AUTO_LAYOUT_OPTIONS: LayoutOptions = {
  "elk.algorithm": "layered",
  "elk.hierarchyHandling": "INCLUDE_CHILDREN",
  "elk.edgeRouting": "POLYLINE",
  "elk.direction": "RIGHT",
  "elk.spacing.nodeNode": "60",
  "elk.layered.spacing.nodeNodeBetweenLayers": "120",
};

const CLASSIC_PORT_SPACING = 35;
const CLASSIC_PORT_TOP = 35;
const CLASSIC_PORT_BOTTOM = 15;
const CLASSIC_PORT_SIZE = 15;

interface PortEntry {
  key: string;
  index?: number;
}

interface PortLayout {
  side: "EAST" | "WEST";
  x: number;
  y: number;
  width: number;
  height: number;
}

export interface FlowAutoLayoutContext {
  editor: NodeEditor<FlowSchemes>;
  area: AreaPlugin<FlowSchemes, FlowAreaExtra>;
}

export interface FlowAutoLayoutOptions {
  nodes?: FlowNode[];
  connections?: FlowConnection[];
  layoutOptions?: LayoutOptions;
  duration?: number;
  timingFunction?: (t: number) => number;
  onTick?: (t: number) => void;
  needsLayout?: (id: NodeId) => boolean;
}

export interface FlowAutoLayoutResult {
  source: ElkNode;
  result: ElkNode;
  previousPositions: Map<string, Position>;
  nextPositions: Map<string, Position>;
}

export function snapshotFlowPositions(
  area: AreaPlugin<FlowSchemes, FlowAreaExtra>,
): Map<string, Position> {
  const map = new Map<string, Position>();

  for (const [nodeId, view] of area.nodeViews) {
    map.set(nodeId, { x: view.position.x, y: view.position.y });
  }

  return map;
}

export function buildFlowElkGraph(
  nodes: FlowNode[],
  connections: FlowConnection[],
  options: LayoutOptions = {},
): ElkNode {
  const graph = createFlowGraphQueries(nodes, connections);

  return {
    id: "root",
    layoutOptions: {
      ...FLOW_AUTO_LAYOUT_OPTIONS,
      ...options,
    },
    ...graphToElk(graph),
  };
}

export async function runFlowAutoLayout(
  context: FlowAutoLayoutContext,
  options: FlowAutoLayoutOptions = {},
): Promise<FlowAutoLayoutResult> {
  const nodes = options.nodes ?? context.editor.getNodes();
  const connections = options.connections ?? context.editor.getConnections();
  const previousPositions = snapshotFlowPositions(context.area);
  const graph = buildFlowElkGraph(nodes, connections, options.layoutOptions);
  const source = cloneElkNode(graph);
  const result = await elk.layout(graph);
  const applier = new TransitionLayoutApplier(context, {
    duration: options.duration ?? 400,
    timingFunction: options.timingFunction,
    onTick: options.onTick,
    needsLayout: options.needsLayout,
  });

  try {
    if (result.children) {
      await applier.apply(result.children);
    }
  } finally {
    applier.destroy();
  }

  return {
    source,
    result,
    previousPositions,
    nextPositions: snapshotFlowPositions(context.area),
  };
}

function graphToElk(
  graph: FlowGraphQueries<FlowNode, FlowConnection>,
  parent?: string,
): Pick<ElkNode, "children" | "edges"> {
  return {
    children: graph.children(parent).map((node) => nodeToLayoutChild(node, graph)),
    edges: parent ? [] : graph.connections().map(connectionToLayoutEdge),
  };
}

function nodeToLayoutChild(
  node: FlowNode,
  graph: FlowGraphQueries<FlowNode, FlowConnection>,
): ElkNode {
  const inputs = portEntries(node.inputs);
  const outputs = portEntries(node.outputs);

  return {
    id: node.id,
    width: node.width,
    height: node.height,
    labels: [{ text: "label" in node ? node.label : "" }],
    ...graphToElk(graph, node.id),
    ports: [
      ...inputs.map((entry, index) =>
        elkPort(node, entry.key, "input", classicPortLayout(node, "input", index, inputs.length)),
      ),
      ...outputs.map((entry, index) =>
        elkPort(
          node,
          entry.key,
          "output",
          classicPortLayout(node, "output", index, outputs.length),
        ),
      ),
    ],
    layoutOptions: {
      portConstraints: "FIXED_POS",
    },
  };
}

function portEntries(ports: FlowNode["inputs"] | FlowNode["outputs"]): PortEntry[] {
  return Object.entries(ports ?? {})
    .map(([key, port]) => ({ key, index: (port as { index?: number } | undefined)?.index }))
    .sort((a, b) => (a.index ?? 0) - (b.index ?? 0));
}

function classicPortLayout(
  node: FlowNode,
  side: "input" | "output",
  index: number,
  ports: number,
): PortLayout {
  if (side === "output") {
    return {
      x: 0,
      y: CLASSIC_PORT_TOP + index * CLASSIC_PORT_SPACING,
      width: CLASSIC_PORT_SIZE,
      height: CLASSIC_PORT_SIZE,
      side: "EAST",
    };
  }

  return {
    x: 0,
    y:
      node.height -
      CLASSIC_PORT_BOTTOM -
      ports * CLASSIC_PORT_SPACING +
      index * CLASSIC_PORT_SPACING,
    width: CLASSIC_PORT_SIZE,
    height: CLASSIC_PORT_SIZE,
    side: "WEST",
  };
}

function elkPort(
  node: FlowNode,
  key: string,
  side: "input" | "output",
  layout: PortLayout,
): ElkPort {
  return {
    id: portId(node.id, key, side),
    width: layout.width,
    height: layout.height,
    x: layout.x,
    y: layout.y,
    properties: {
      side: layout.side,
    },
  } as ElkPort;
}

function connectionToLayoutEdge(connection: FlowConnection): ElkExtendedEdge {
  const sourceOutput = (connection as { sourceOutput?: string }).sourceOutput;
  const targetInput = (connection as { targetInput?: string }).targetInput;

  return {
    id: connection.id,
    sources: [sourceOutput ? portId(connection.source, sourceOutput, "output") : connection.source],
    targets: [targetInput ? portId(connection.target, targetInput, "input") : connection.target],
  };
}

function portId(id: NodeId, key: string, side: "input" | "output"): string {
  return [id, key, side].join("_");
}

function cloneElkNode(node: ElkNode): ElkNode {
  return JSON.parse(JSON.stringify(node)) as ElkNode;
}

class AnimationSystem {
  private activeAnimations = new Map<
    string,
    {
      startTime: number;
      duration: number;
      tick: (t: number) => void;
      done: (value: boolean) => void;
    }
  >();
  private frameId?: number;

  constructor() {
    this.start();
  }

  add(duration: number, id: string, tick: (t: number) => void): Promise<boolean> {
    const startTime = Date.now();

    return new Promise((done) => {
      this.activeAnimations.set(id, { startTime, duration, tick, done });
    });
  }

  cancel(id: string): void {
    this.activeAnimations.get(id)?.done(false);
    this.activeAnimations.delete(id);
  }

  stop(): void {
    if (typeof this.frameId !== "undefined") {
      cancelAnimationFrame(this.frameId);
    }
    for (const id of this.activeAnimations.keys()) {
      this.cancel(id);
    }
  }

  private start(): void {
    for (const [key, animation] of this.activeAnimations.entries()) {
      const t = Math.min(1, (Date.now() - animation.startTime) / animation.duration);

      if (t >= 1) {
        this.activeAnimations.delete(key);
        animation.tick(1);
        animation.done(true);
      } else if (t >= 0) {
        animation.tick(t);
      }
    }

    this.frameId = requestAnimationFrame(() => this.start());
  }
}

interface TransitionLayoutOptions {
  duration: number;
  timingFunction?: (t: number) => number;
  onTick?: (t: number) => void;
  needsLayout?: (id: NodeId) => boolean;
}

class TransitionLayoutApplier {
  private animation = new AnimationSystem();
  private timingFunction: (t: number) => number;

  constructor(
    private context: FlowAutoLayoutContext,
    private options: TransitionLayoutOptions,
  ) {
    this.timingFunction = options.timingFunction ?? ((t) => t);
  }

  async apply(nodes: ElkNode[], offset: Position = { x: 0, y: 0 }): Promise<void> {
    const validNodes = validShapes(nodes);

    await Promise.all(
      validNodes.map(({ id, x, y, width, height, children }) => {
        const childNodes = children ?? [];
        const hasChildren = childNodes.length > 0;
        const needsLayout = this.options.needsLayout ? this.options.needsLayout(id) : true;
        const forceSelf = !hasChildren || needsLayout;

        return Promise.all([
          hasChildren && this.apply(childNodes, { x: offset.x + x, y: offset.y + y }),
          forceSelf && this.resizeNode(id, width, height),
          forceSelf && this.translateNode(id, offset.x + x, offset.y + y),
        ]);
      }),
    );
  }

  destroy(): void {
    this.animation.stop();
  }

  private applyTiming(from: number, to: number, t: number): number {
    const k = this.timingFunction(t);
    return from * (1 - k) + to * k;
  }

  private async resizeNode(id: NodeId, width: number, height: number): Promise<boolean> {
    const node = this.context.editor.getNode(id);
    if (!node) return false;

    const previous = { width: node.width, height: node.height };

    return await this.animation.add(this.options.duration, `${id}_resize`, (t) => {
      const currentWidth = this.applyTiming(previous.width, width, t);
      const currentHeight = this.applyTiming(previous.height, height, t);

      this.options.onTick?.(t);
      void this.context.area.resize(id, currentWidth, currentHeight);
    });
  }

  private async translateNode(id: NodeId, x: number, y: number): Promise<boolean> {
    const view = this.context.area.nodeViews.get(id);
    if (!view) return false;

    const previous = { ...view.position };

    return await this.animation.add(this.options.duration, `${id}_translate`, (t) => {
      const currentX = this.applyTiming(previous.x, x, t);
      const currentY = this.applyTiming(previous.y, y, t);

      this.options.onTick?.(t);
      void view.translate(currentX, currentY);
    });
  }
}

function validShapes<Shape extends ElkShape>(shapes: Shape[]): (Shape & Required<ElkShape>)[] {
  return shapes.filter((shape): shape is Shape & Required<ElkShape> => {
    const { x, y, width, height } = shape;
    return ![typeof x, typeof y, typeof width, typeof height].includes("undefined");
  });
}
