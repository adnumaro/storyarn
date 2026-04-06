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
import type { HookProxy } from "./editorHandlers";

interface Position {
  x: number;
  y: number;
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

  constructor(area: AreaPlugin<FlowSchemes, FlowAreaExtra>, nodeId: string, prev: Position, next: Position) {
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

  constructor(
    editor: NodeEditor<FlowSchemes>,
    connection: FlowConnection,
  ) {
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

  constructor(
    editor: NodeEditor<FlowSchemes>,
    connection: FlowConnection,
  ) {
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
  hookProxy: HookProxy;
  nodeId: string | number;

  constructor(hookProxy: HookProxy, nodeId: string | number) {
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
  hookProxy: HookProxy;
  nodeId: string | number;

  constructor(hookProxy: HookProxy, nodeId: string | number) {
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
  hookProxy: HookProxy;
  field: string;
  prevValue: unknown;
  newValue: unknown;

  constructor(hookProxy: HookProxy, field: string, prevValue: unknown, newValue: unknown) {
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
  hookProxy: HookProxy;
  nodeId: string | number;
  prevData: NodeData;
  newData: NodeData;

  constructor(
    hookProxy: HookProxy,
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
      data: this.prevData as unknown as Record<string, unknown>,
    });
  }

  async redo(): Promise<void> {
    this.hookProxy.pushEvent("restore_node_data", {
      id: this.nodeId,
      data: this.newData as unknown as Record<string, unknown>,
    });
  }
}

/**
 * Converts a Map<reteNodeId, {x, y}> to the server batch payload format.
 * Shared by AutoLayoutAction and performAutoLayout.
 */
export function buildBatchPositions(
  positionsMap: Map<string, Position>,
): { id: number; position_x: number; position_y: number }[] {
  const result: { id: number; position_x: number; position_y: number }[] = [];
  for (const [reteNodeId, pos] of positionsMap) {
    const serverId = reteNodeId.replace("node-", "");
    const id = Number.parseInt(serverId, 10);
    if (Number.isNaN(id)) {
      continue;
    }
    result.push({ id, position_x: pos.x, position_y: pos.y });
  }
  return result;
}

/**
 * Undo/redo action for auto-layout.
 * Stores full position snapshots (before and after) for all nodes.
 * Both operations push batch_update_positions to persist.
 */
class AutoLayoutAction implements Action {
  hookProxy: HookProxy;
  prevPositions: Map<string, Position>;
  newPositions: Map<string, Position>;

  constructor(
    hookProxy: HookProxy,
    prevPositions: Map<string, Position>,
    newPositions: Map<string, Position>,
  ) {
    this.hookProxy = hookProxy;
    this.prevPositions = prevPositions;
    this.newPositions = newPositions;
  }

  async undo(): Promise<void> {
    await this._applyPositions(this.prevPositions);
  }

  async redo(): Promise<void> {
    await this._applyPositions(this.newPositions);
  }

  async _applyPositions(positions: Map<string, Position>): Promise<void> {
    this.hookProxy.enterLoadingFromServer();
    try {
      for (const [reteNodeId, pos] of positions) {
        const view = this.hookProxy.area.nodeViews.get(reteNodeId);
        if (view) {
          await this.hookProxy.area.translate(reteNodeId, pos);
        }
      }
    } finally {
      this.hookProxy.exitLoadingFromServer();
    }

    this.hookProxy.pushEvent("batch_update_positions", {
      positions: buildBatchPositions(positions) as unknown as Record<string, unknown>,
    });
  }
}

/**
 * Creates a custom history preset for the flow canvas.
 */
export function historyPreset(hookProxy: HookProxy): { connect(history: HistoryPlugin<FlowSchemes>): void } {
  return {
    connect(history: HistoryPlugin<FlowSchemes>) {
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
          const connection = editor.getConnection(
            (context as { data: { id: string } }).data.id,
          );
          if (connection) {
            history.add(
              new AddConnectionAction(editor, connection),
            );
          }
        }

        if ((context as { type: string }).type === "connectionremoved") {
          const connection = (context as { data: FlowConnection }).data;
          if (connection) {
            history.add(
              new RemoveConnectionAction(editor, connection),
            );
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
            history.add(
              new DragAction(area, id, previous, position),
            );
          }
        }

        return context;
      });
    },
  };
}

export { AutoLayoutAction };
