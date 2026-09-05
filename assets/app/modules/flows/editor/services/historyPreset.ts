/**
 * Custom history preset for the flow canvas (Vue composable version).
 *
 * Tracks drag (node translate), connection add/remove, and node deletion.
 * Node deletion uses server-side soft-delete: undo sends restore_node,
 * redo sends delete_node.
 *
 * Uses area.translate() instead of view.translate() so that position changes
 * from undo/redo fire through the area pipe chain and get synced to the server.
 */

import type { NodeEditor } from "rete";
import type { AreaPlugin } from "rete-area-plugin";
import type { HistoryAction as Action, HistoryPlugin } from "rete-history-plugin";
import type { NodeData } from "../lib/node-configs";
import type { FlowSchemes, FlowAreaExtra, FlowConnection } from "../lib/rete-schemes";

/**
 * Minimal editor capabilities required by history actions.
 *
 * Keeping this contract local prevents the history preset from depending on
 * the editor-handlers factory that consumes it.
 */
export interface HistoryHookProxy {
  pushEvent(
    event: string,
    payload: Record<string, unknown>,
    callback?: (reply: Record<string, unknown>) => void,
    onError?: (error: unknown) => void,
  ): void;
  isLoadingFromServer: boolean;
  _historyTriggeredDelete?: string | number | null;
  enterLoadingFromServer(): void;
  exitLoadingFromServer(): void;
  invalidateHistory(): void;
}

interface HistoryCommandTarget {
  undo(): Promise<void>;
  redo(): Promise<void>;
  clear(): void;
}

/**
 * Serializes undo/redo calls around their asynchronous actions. Invalidation is
 * queued behind an in-flight command, so HistoryPlugin cannot re-add a record
 * after a conflict or transport failure cleared the stacks.
 */
export class HistoryCommandQueue {
  private tail: Promise<void> = Promise.resolve();
  private generation = 0;

  constructor(private readonly getHistory: () => HistoryCommandTarget | null) {}

  undo(): Promise<void> {
    return this.enqueue("undo");
  }

  redo(): Promise<void> {
    return this.enqueue("redo");
  }

  invalidate(): Promise<void> {
    const generation = ++this.generation;
    const clear = this.tail
      .catch(() => undefined)
      .then(() => {
        if (generation === this.generation) this.getHistory()?.clear();
      });

    this.tail = clear.catch(() => undefined);
    return clear;
  }

  private enqueue(command: "undo" | "redo"): Promise<void> {
    const generation = this.generation;
    const operation = this.tail.then(async () => {
      if (generation !== this.generation) return;

      try {
        await this.getHistory()?.[command]();
      } catch {
        void this.invalidate();
      }
    });

    this.tail = operation.catch(() => undefined);
    return operation;
  }
}

export interface Position {
  x: number;
  y: number;
}

export interface BatchPosition {
  id: number;
  position_x: number;
  position_y: number;
}

/**
 * Converts a `reteNodeId → position` map into the wire shape the
 * `batch_update_positions` server endpoint expects. Skips entries whose
 * rete id does not parse to a numeric server id.
 */
export function buildBatchPositions(positionsMap: Map<string, Position>): BatchPosition[] {
  const result: BatchPosition[] = [];
  for (const [reteNodeId, pos] of positionsMap) {
    const id = Number.parseInt(reteNodeId.replace(/^node-/, ""), 10);
    if (Number.isNaN(id)) continue;
    result.push({ id, position_x: pos.x, position_y: pos.y });
  }
  return result;
}

/**
 * Undo/redo action for node drags.
 * Uses area.translate() which fires nodetranslated -> debounced server push.
 */
class DragAction implements Action {
  area: AreaPlugin<FlowSchemes, FlowAreaExtra>;
  nodeId: string;
  prev: Position;
  next: Position;

  constructor(
    area: AreaPlugin<FlowSchemes, FlowAreaExtra>,
    nodeId: string,
    prev: Position,
    next: Position,
  ) {
    this.area = area;
    this.nodeId = nodeId;
    this.prev = { ...prev };
    this.next = { ...next };
  }

  async undo(): Promise<void> {
    const view = this.area.nodeViews.get(this.nodeId);
    if (!view) {
      return;
    }
    await this.area.translate(this.nodeId, this.prev);
  }

  async redo(): Promise<void> {
    const view = this.area.nodeViews.get(this.nodeId);
    if (!view) {
      return;
    }
    await this.area.translate(this.nodeId, this.next);
  }
}

/**
 * Undo/redo action for an added connection.
 * Undo removes it; redo re-adds it.
 */
class AddConnectionAction implements Action {
  editor: NodeEditor<FlowSchemes>;
  connection: FlowConnection;

  constructor(editor: NodeEditor<FlowSchemes>, connection: FlowConnection) {
    this.editor = editor;
    this.connection = connection;
  }

  async undo(): Promise<void> {
    if (!this.editor.getConnection(this.connection.id)) {
      return;
    }
    await this.editor.removeConnection(this.connection.id);
  }

  async redo(): Promise<void> {
    // Skip if source or target node was deleted since the action was recorded
    if (
      !this.editor.getNode(this.connection.source) ||
      !this.editor.getNode(this.connection.target)
    ) {
      return;
    }
    await this.editor.addConnection(this.connection);
  }
}

/**
 * Undo/redo action for a removed connection.
 * Undo re-adds it; redo removes it.
 */
class RemoveConnectionAction implements Action {
  editor: NodeEditor<FlowSchemes>;
  connection: FlowConnection;

  constructor(editor: NodeEditor<FlowSchemes>, connection: FlowConnection) {
    this.editor = editor;
    this.connection = connection;
  }

  async undo(): Promise<void> {
    if (
      !this.editor.getNode(this.connection.source) ||
      !this.editor.getNode(this.connection.target)
    ) {
      return;
    }
    await this.editor.addConnection(this.connection);
  }

  async redo(): Promise<void> {
    if (!this.editor.getConnection(this.connection.id)) {
      return;
    }
    await this.editor.removeConnection(this.connection.id);
  }
}

/**
 * Undo/redo action for node deletion.
 * Undo sends restore_node to server; redo sends delete_node.
 */
export class DeleteNodeAction implements Action {
  hookProxy: HistoryHookProxy;
  nodeId: string | number;

  constructor(hookProxy: HistoryHookProxy, nodeId: string | number) {
    this.hookProxy = hookProxy;
    this.nodeId = nodeId;
  }

  async undo(): Promise<void> {
    this.hookProxy.pushEvent("restore_node", { id: this.nodeId });
  }

  async redo(): Promise<void> {
    this.hookProxy._historyTriggeredDelete = this.nodeId;
    this.hookProxy.pushEvent("delete_node", { id: this.nodeId });
  }
}

/**
 * Undo/redo action for node creation.
 * Undo deletes the node; redo restores it.
 */
export class CreateNodeAction implements Action {
  hookProxy: HistoryHookProxy;
  nodeId: string | number;

  constructor(hookProxy: HistoryHookProxy, nodeId: string | number) {
    this.hookProxy = hookProxy;
    this.nodeId = nodeId;
  }

  async undo(): Promise<void> {
    this.hookProxy._historyTriggeredDelete = this.nodeId;
    this.hookProxy.pushEvent("delete_node", { id: this.nodeId });
  }

  async redo(): Promise<void> {
    this.hookProxy.pushEvent("restore_node", { id: this.nodeId });
  }
}

/**
 * Undo/redo action for flow metadata (name, shortcut) changes.
 * Undo restores the previous value; redo restores the new one.
 */
export const FLOW_META_COALESCE_MS = 2000;

export class FlowMetaAction implements Action {
  hookProxy: HistoryHookProxy;
  field: string;
  prevValue: unknown;
  newValue: unknown;

  constructor(hookProxy: HistoryHookProxy, field: string, prevValue: unknown, newValue: unknown) {
    this.hookProxy = hookProxy;
    this.field = field;
    this.prevValue = prevValue;
    this.newValue = newValue;
  }

  async undo(): Promise<void> {
    this.hookProxy.pushEvent("restore_flow_meta", {
      field: this.field,
      value: this.prevValue as string,
    });
  }

  async redo(): Promise<void> {
    this.hookProxy.pushEvent("restore_flow_meta", {
      field: this.field,
      value: this.newValue as string,
    });
  }
}

/**
 * Undo/redo action for node data (property) changes.
 * Undo restores the previous data snapshot; redo restores the new one.
 */
export const NODE_DATA_COALESCE_MS = 1000;

export class NodeDataAction implements Action {
  hookProxy: HistoryHookProxy;
  nodeId: string | number;
  prevData: NodeData;
  newData: NodeData;

  constructor(
    hookProxy: HistoryHookProxy,
    nodeId: string | number,
    prevData: NodeData,
    newData: NodeData,
  ) {
    this.hookProxy = hookProxy;
    this.nodeId = nodeId;
    this.prevData = prevData;
    this.newData = newData;
  }

  async undo(): Promise<void> {
    this.hookProxy.pushEvent("restore_node_data", {
      id: this.nodeId,
      data: this.prevData,
    });
  }

  async redo(): Promise<void> {
    this.hookProxy.pushEvent("restore_node_data", {
      id: this.nodeId,
      data: this.newData,
    });
  }
}

export interface SequenceVisualLayerSnapshot {
  asset_id: number | null;
  layer_key: string;
  overridden_fields: string[];
  removed: boolean;
  kind: string;
  label: string | null;
  z_index: number;
  slot: string;
  x: number;
  y: number;
  width: number;
  height: number;
  anchor_x: number;
  anchor_y: number;
  fit: string;
  opacity: number;
  visible: boolean;
}

export interface SequenceCompositionSnapshot {
  version: number;
  owner_id: number;
  flow_id: number;
  owner_type: "sequence" | "dialogue";
  composition_source_id: number | null;
  position_x: number;
  position_y: number;
  config: { name: string; width: number; height: number } | null;
  visual_layers: SequenceVisualLayerSnapshot[];
}

interface SequenceCompositionHistoryRecord {
  action: unknown;
  time: number;
}

type SequenceCompositionActionRecord = SequenceCompositionHistoryRecord & {
  action: SequenceCompositionAction;
};

/** The server snapshots are JSON values, so compare them structurally. */
export function sequenceCompositionSnapshotsEqual(left: unknown, right: unknown): boolean {
  if (Object.is(left, right)) return true;
  if (!isJsonContainer(left) || !isJsonContainer(right)) return false;

  if (Array.isArray(left)) return Array.isArray(right) && jsonArraysEqual(left, right);
  if (Array.isArray(right)) return false;
  return jsonRecordsEqual(left, right);
}

function isJsonContainer(value: unknown): value is Record<string, unknown> | unknown[] {
  return typeof value === "object" && value !== null;
}

function jsonArraysEqual(left: unknown[], right: unknown[]): boolean {
  if (left.length !== right.length) return false;
  return left.every((value, index) => sequenceCompositionSnapshotsEqual(value, right[index]));
}

function jsonRecordsEqual(left: Record<string, unknown>, right: Record<string, unknown>): boolean {
  const leftKeys = Object.keys(left);
  const rightKeys = Object.keys(right);
  if (leftKeys.length !== rightKeys.length) return false;

  return leftKeys.every(
    (key) =>
      Object.prototype.hasOwnProperty.call(right, key) &&
      sequenceCompositionSnapshotsEqual(left[key], right[key]),
  );
}

/**
 * Coalescing is valid only for the top history action and a continuous
 * previous/current snapshot pair. Looking deeper would rewrite history behind
 * an intervening action and make its optimistic expected-current check stale.
 */
export function sequenceCompositionCoalesceTarget(
  recent: readonly SequenceCompositionHistoryRecord[],
  ownerId: string | number,
  historyKey: string,
  previous: SequenceCompositionSnapshot,
): SequenceCompositionActionRecord | null {
  const latest = recent[0];
  if (!(latest?.action instanceof SequenceCompositionAction)) return null;

  return String(latest.action.ownerId) === String(ownerId) &&
    latest.action.historyKey === historyKey &&
    sequenceCompositionSnapshotsEqual(latest.action.current, previous)
    ? (latest as SequenceCompositionActionRecord)
    : null;
}

/** Undo/redo action for the complete local state of one composition owner. */
export class SequenceCompositionAction implements Action {
  hookProxy: HistoryHookProxy;
  ownerId: string | number;
  historyKey: string;
  previous: SequenceCompositionSnapshot;
  current: SequenceCompositionSnapshot;

  constructor(
    hookProxy: HistoryHookProxy,
    ownerId: string | number,
    historyKey: string,
    previous: SequenceCompositionSnapshot,
    current: SequenceCompositionSnapshot,
  ) {
    this.hookProxy = hookProxy;
    this.ownerId = ownerId;
    this.historyKey = historyKey;
    this.previous = previous;
    this.current = current;
  }

  async undo(): Promise<void> {
    await this.restore(this.previous, this.current);
  }

  async redo(): Promise<void> {
    await this.restore(this.current, this.previous);
  }

  private restore(
    snapshot: SequenceCompositionSnapshot,
    expectedCurrent: SequenceCompositionSnapshot,
  ): Promise<void> {
    return new Promise((resolve) => {
      let settled = false;
      const settle = () => {
        if (settled) return;
        settled = true;
        resolve();
      };

      this.hookProxy.pushEvent(
        "restore_sequence_composition",
        {
          id: this.ownerId,
          snapshot,
          expected_current: expectedCurrent,
        },
        settle,
        () => {
          this.hookProxy.invalidateHistory();
          settle();
        },
      );
    });
  }
}

/**
 * Undo/redo action for auto-layout.
 * Stores full position snapshots (before and after) for all nodes.
 * Both operations replay positions through `area.translate` while
 * loading-from-server is set (to suppress per-node server pushes), then
 * persist the resulting layout in one batch via `batch_update_positions`.
 */
export class AutoLayoutAction implements Action {
  hookProxy: HistoryHookProxy;
  area: AreaPlugin<FlowSchemes, FlowAreaExtra>;
  prevPositions: Map<string, Position>;
  newPositions: Map<string, Position>;

  constructor(
    hookProxy: HistoryHookProxy,
    area: AreaPlugin<FlowSchemes, FlowAreaExtra>,
    prevPositions: Map<string, Position>,
    newPositions: Map<string, Position>,
  ) {
    this.hookProxy = hookProxy;
    this.area = area;
    this.prevPositions = new Map(prevPositions);
    this.newPositions = new Map(newPositions);
  }

  async undo(): Promise<void> {
    await this.applyPositions(this.prevPositions);
  }

  async redo(): Promise<void> {
    await this.applyPositions(this.newPositions);
  }

  private async applyPositions(positions: Map<string, Position>): Promise<void> {
    this.hookProxy.enterLoadingFromServer();
    try {
      for (const [reteNodeId, pos] of positions) {
        const view = this.area.nodeViews.get(reteNodeId);
        if (view) {
          await this.area.translate(reteNodeId, pos);
        }
      }
    } finally {
      this.hookProxy.exitLoadingFromServer();
    }
    this.hookProxy.pushEvent("batch_update_positions", {
      positions: buildBatchPositions(positions),
    });
  }
}

/**
 * Creates a custom history preset for the flow canvas.
 */
export function historyPreset(hookProxy: HistoryHookProxy): {
  connect(history: HistoryPlugin<FlowSchemes>): void;
} {
  return {
    connect(history: HistoryPlugin<FlowSchemes>) {
      // Rete.js parentScope() returns a generic Scope type; cast needed for typed plugin access
      const area = history.parentScope() as unknown as AreaPlugin<FlowSchemes, FlowAreaExtra>;
      const editor = (area as unknown as { parentScope(): NodeEditor<FlowSchemes> }).parentScope();
      const timing = history.timing * 2;

      // Track latest known position per node (for drag start reference)
      const positions = new Map<string, Position>();

      // Nodes currently being dragged (picked but not yet released)
      const picked = new Set<string>();

      // --- Connection tracking (editor pipe) ---
      editor.addPipe((context) => {
        if (hookProxy.isLoadingFromServer) {
          return context;
        }

        if ((context as { type: string }).type === "connectioncreated") {
          const connection = editor.getConnection((context as { data: { id: string } }).data.id);
          if (connection) {
            history.add(new AddConnectionAction(editor, connection));
          }
        }

        if ((context as { type: string }).type === "connectionremoved") {
          const connection = (context as { data: FlowConnection }).data;
          if (connection) {
            history.add(new RemoveConnectionAction(editor, connection));
          }
        }

        return context;
      });

      // --- Position tracking (always runs, even during server loads) ---
      area.addPipe((context) => {
        if (!context || typeof context !== "object" || !("type" in context)) {
          return context;
        }

        if ((context as { type: string }).type === "nodetranslated") {
          const data = (context as { data: { id: string; position: Position } }).data;
          positions.set(data.id, { ...data.position });
        }
        return context;
      });

      // --- Drag tracking (area pipe) ---
      area.addPipe((context) => {
        if (!context || typeof context !== "object" || !("type" in context)) {
          return context;
        }

        if ((context as { type: string }).type === "nodepicked") {
          picked.add((context as { data: { id: string } }).data.id);
        }

        if ((context as { type: string }).type === "nodedragged") {
          picked.delete((context as { data: { id: string } }).data.id);
        }

        if ((context as { type: string }).type === "nodetranslated") {
          if (hookProxy.isLoadingFromServer) {
            return context;
          }

          const { id, position, previous } = (
            context as { data: { id: string; position: Position; previous: Position } }
          ).data;

          // Only track drags (node is currently picked), not programmatic translates
          if (!picked.has(id)) {
            return context;
          }

          // Coalesce: find recent DragAction for same node
          const recent = history
            .getRecent(timing)
            .filter((r) => r.action instanceof DragAction && r.action.nodeId === id);

          if (recent[0]) {
            // Update existing action's endpoint and timestamp
            (recent[0].action as DragAction).next = { ...position };
            recent[0].time = Date.now();
          } else {
            history.add(new DragAction(area, id, previous, position));
          }
        }

        return context;
      });
    },
  };
}
