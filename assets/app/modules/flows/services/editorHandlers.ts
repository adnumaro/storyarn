/**
 * Editor handlers for node and connection CRUD operations (V2 Vue-native).
 *
 * Replaces V1 editor_handlers.js -- no Lit imports, uses Vue-native
 * FlowNode and needsRebuild from node-configs.ts.
 */

import { ClassicPreset, type NodeEditor } from "rete";
import type { AreaPlugin } from "rete-area-plugin";
import type { HistoryPlugin } from "rete-history-plugin";
import type { FlowNode } from "../lib/flow-node";
import { FlowNode as FlowNodeClass } from "../lib/flow-node";
import type { NodeData } from "../lib/node-configs";
import { needsRebuild } from "../lib/node-configs";
import type { FlowSchemes, FlowAreaExtra } from "../lib/rete-schemes";
import {
  CreateNodeAction,
  DeleteNodeAction,
  FLOW_META_COALESCE_MS,
  FlowMetaAction,
  NODE_DATA_COALESCE_MS,
  NodeDataAction,
} from "./historyPreset";

export interface FlowContext {
  sheetsMap: Record<string, unknown>;
  hubsMap: Record<string, unknown>;
  labels: Record<string, string>;
  lod: string;
  editingNodeId: string | null;
  onInlineEditSave: ((reteNodeId: string, field: string, value: unknown) => void) | null;
  nodeDataVersion: number;
}

export interface HookProxy {
  pushEvent: (event: string, payload: Record<string, unknown>) => void;
  handleEvent: (event: string, callback: (data: Record<string, unknown>) => void) => void;
  editor: NodeEditor<FlowSchemes>;
  area: AreaPlugin<FlowSchemes, FlowAreaExtra>;
  connection: unknown;
  history: HistoryPlugin<FlowSchemes> | null;
  arrange: unknown;
  nodeMap: Map<string | number, FlowNode>;
  connectionDataMap: Map<string, { id: number; label: string | null; condition: unknown }>;
  sheetsMap: Record<string, unknown>;
  hubsMap: Record<string, unknown>;
  labels: Record<string, string>;
  currentLod: string;
  readonly: boolean;
  currentUserId: number;
  currentUserColor: string;
  selectedNodeId: string | number | null;
  lastNodeClickTime: number;
  lastClickedNodeId: string | number | null;
  isLoadingFromServer: boolean;
  _deferSocketCalc: boolean;
  _deferredSockets: unknown[];
  _socketRenderedEvents: unknown[];
  _isRecalculatingSockets: boolean;
  el: HTMLElement | null;
  enterLoadingFromServer(): void;
  exitLoadingFromServer(): void;
  _sheetsMap: Record<string, unknown>;
  _hubsMap: Record<string, unknown>;
  _labels: Record<string, string>;
  _readonly: boolean;
  _currentUserId: number;
  _currentUserColor: string;
  _containerEl: HTMLElement | null;
  _inlineEditingNodeId: string | null;
  _speakerPopover: unknown;
  _eventBindingsController: AbortController | null;
  _flowContext: FlowContext;
  _historyTriggeredDelete?: string | number | null;
  _throttleTimers?: Record<string | number, ReturnType<typeof setTimeout>>;
  _pendingPositions?: Record<string | number, { x: number; y: number }>;
  editorHandlers: EditorHandlers | null;
  navigationHandler: unknown;
  debugHandler: unknown;
  keyboardHandler: unknown;
  lodController: unknown;
  addNodeToEditor(data: Record<string, unknown>): Promise<FlowNode>;
  addConnectionToEditor(data: Record<string, unknown>): Promise<unknown>;
  rebuildHubsMap(): Promise<void>;
  syncNodeSize(nodeId: string): Promise<void>;
  syncAllNodeSizes(): Promise<void>;
  loadFlow(data: Record<string, unknown>): Promise<void>;
}

interface Position {
  x: number;
  y: number;
}

export interface EditorHandlers {
  init(): void;
  throttleNodeMoved(nodeId: string | number, position: Position): void;
  flushNodeMoved(nodeId: string | number): void;
  handleNodeMoved(data: Record<string, unknown>): Promise<void>;
  handleFlowUpdated(data: Record<string, unknown>): Promise<void>;
  handleNodeAdded(data: Record<string, unknown>): Promise<void>;
  handleNodeRemoved(data: Record<string, unknown>): Promise<void>;
  handleNodeRestored(data: Record<string, unknown>): Promise<void>;
  handleNodeUpdated(data: Record<string, unknown>): Promise<void>;
  rebuildNode(id: string | number, existingNode: FlowNode, nodeData: NodeData): Promise<void>;
  handleConnectionAdded(data: Record<string, unknown>): Promise<void>;
  handleConnectionRemoved(data: Record<string, unknown>): Promise<void>;
  handleNodeDataChanged(data: Record<string, unknown>): void;
  handleFlowMetaChanged(data: Record<string, unknown>): void;
  handleConnectionUpdated(data: Record<string, unknown>): void;
  destroy(): void;
}

export function editorHandlers(hook: HookProxy): EditorHandlers {
  return {
    init() {
      hook._throttleTimers = {};
      hook._pendingPositions = {};
    },

    throttleNodeMoved(nodeId: string | number, position: Position) {
      hook._pendingPositions![nodeId] = position;
      if (hook._throttleTimers![nodeId]) {
        return;
      }

      hook._throttleTimers![nodeId] = setTimeout(() => {
        const pos = hook._pendingPositions![nodeId];
        if (pos) {
          hook.pushEvent("node_dragging", {
            id: nodeId,
            position_x: pos.x,
            position_y: pos.y,
          });
        }
        delete hook._throttleTimers![nodeId];
      }, 100);
    },

    flushNodeMoved(nodeId: string | number) {
      if (hook._throttleTimers![nodeId]) {
        clearTimeout(hook._throttleTimers![nodeId]);
        delete hook._throttleTimers![nodeId];
      }

      const pos = hook._pendingPositions![nodeId];
      if (pos) {
        hook.pushEvent("node_moved", {
          id: nodeId,
          position_x: pos.x,
          position_y: pos.y,
        });
        delete hook._pendingPositions![nodeId];
      }
    },

    async handleNodeMoved(data: Record<string, unknown>) {
      const { node_id, x, y } = data as { node_id: string | number; x: number; y: number };
      const node = hook.nodeMap.get(node_id);
      if (!node) {
        return;
      }

      hook.enterLoadingFromServer();
      try {
        await hook.area.translate(node.id, { x, y });
      } finally {
        hook.exitLoadingFromServer();
      }
    },

    async handleFlowUpdated(data: Record<string, unknown>) {
      hook.history?.clear();

      for (const conn of hook.editor.getConnections()) {
        try {
          await hook.editor.removeConnection(conn.id);
        } catch {}
      }
      for (const node of hook.editor.getNodes()) {
        try {
          await hook.editor.removeNode(node.id);
        } catch {}
      }
      hook.nodeMap.clear();
      hook.connectionDataMap.clear();
      await hook.loadFlow(data);
      await hook.rebuildHubsMap();

      await new Promise((resolve) => requestAnimationFrame(() => requestAnimationFrame(resolve)));
      await hook.syncAllNodeSizes();
    },

    async handleNodeAdded(data: Record<string, unknown>) {
      hook.enterLoadingFromServer();
      try {
        await hook.addNodeToEditor(data);
      } finally {
        hook.exitLoadingFromServer();
      }
      if ((data as { self?: boolean }).self && hook.history) {
        hook.history.add(new CreateNodeAction(hook, data.id as string | number));
      }
      if (data.type === "hub" || data.type === "jump") {
        await hook.rebuildHubsMap();
      }
    },

    async handleNodeRemoved(data: Record<string, unknown>) {
      const node = hook.nodeMap.get(data.id as string | number);
      if (node) {
        // Exit inline edit if needed
        const ctx = hook._flowContext;
        if (ctx?.editingNodeId === node.id) {
          ctx.editingNodeId = null;
        }

        if (hook._throttleTimers?.[data.id as string | number]) {
          clearTimeout(hook._throttleTimers[data.id as string | number]);
          delete hook._throttleTimers[data.id as string | number];
        }

        if ((data as { self?: boolean }).self && hook._historyTriggeredDelete !== data.id) {
          hook.history?.add(new DeleteNodeAction(hook, data.id as string | number));
        }
        if (hook._historyTriggeredDelete === data.id) {
          hook._historyTriggeredDelete = null;
        }

        const needsHubRebuild = node.nodeType === "hub" || node.nodeType === "jump";
        hook.enterLoadingFromServer();
        try {
          const connections = [...hook.editor.getConnections()];
          for (const conn of connections) {
            if (conn.source === node.id || conn.target === node.id) {
              hook.connectionDataMap.delete(conn.id);
              await hook.editor.removeConnection(conn.id);
            }
          }
          await hook.editor.removeNode(node.id);
        } finally {
          hook.exitLoadingFromServer();
        }
        hook.nodeMap.delete(data.id as string | number);
        if (hook.selectedNodeId === data.id) {
          hook.selectedNodeId = null;
        }
        if (needsHubRebuild) {
          await hook.rebuildHubsMap();
        }
      }
    },

    async handleNodeRestored(data: Record<string, unknown>) {
      hook.enterLoadingFromServer();
      try {
        const nodeData = (data as { node: Record<string, unknown> }).node;
        const node = await hook.addNodeToEditor(nodeData);
        if (node) {
          await hook.area.update("node", node.id);
          await hook.syncNodeSize(node.id);
        }
        for (const conn of ((data as { connections?: Record<string, unknown>[] }).connections ||
          [])) {
          if (!hook.editor.getConnection(`conn-${conn.id}`)) {
            await hook.addConnectionToEditor(conn);
          }
        }
      } finally {
        hook.exitLoadingFromServer();
      }
      const nodeData = (data as { node: Record<string, unknown> }).node;
      if (nodeData.type === "hub" || nodeData.type === "jump") {
        await hook.rebuildHubsMap();
      }
    },

    async handleNodeUpdated(data: Record<string, unknown>) {
      const { id, data: nodeData } = data as { id: string | number; data: NodeData };
      const existingNode = hook.nodeMap.get(id);
      if (!existingNode) {
        return;
      }

      // Skip while inline editing
      const ctx = hook._flowContext;
      if (ctx?.editingNodeId === existingNode.id) {
        existingNode.nodeData = { ...nodeData };
        return;
      }

      const shouldRebuild = needsRebuild(existingNode.nodeType, existingNode.nodeData, nodeData);

      if (shouldRebuild) {
        await this.rebuildNode(id, existingNode, nodeData);
      } else {
        // Update nodeData and bump reactive version (no area.update -- preserves sockets)
        existingNode.nodeData = { ...nodeData };
        if (ctx) {
          ctx.nodeDataVersion = (ctx.nodeDataVersion || 0) + 1;
        }
      }

      if (existingNode.nodeType === "hub" || existingNode.nodeType === "jump") {
        await hook.rebuildHubsMap();
      }
    },

    async rebuildNode(id: string | number, existingNode: FlowNode, nodeData: NodeData) {
      // Exit inline edit if needed
      const ctx = hook._flowContext;
      if (ctx?.editingNodeId === existingNode.id) {
        ctx.editingNodeId = null;
      }

      const view = hook.area.nodeViews.get(existingNode.id);
      const position: Position = view ? { ...view.position } : { x: 0, y: 0 };

      hook.enterLoadingFromServer();
      try {
        const connections = [...hook.editor.getConnections()];
        const affectedConnections: {
          source: string | number | undefined;
          sourceOutput: string;
          target: string | number | undefined;
          targetInput: string;
          connData: { id: number; label: string | null; condition: unknown } | undefined;
        }[] = [];

        for (const conn of connections) {
          if (conn.source === existingNode.id || conn.target === existingNode.id) {
            affectedConnections.push({
              source: (hook.editor.getNode(conn.source))?.nodeId,
              sourceOutput: conn.sourceOutput,
              target: (hook.editor.getNode(conn.target))?.nodeId,
              targetInput: conn.targetInput,
              connData: hook.connectionDataMap.get(conn.id),
            });
            hook.connectionDataMap.delete(conn.id);
            await hook.editor.removeConnection(conn.id);
          }
        }

        await hook.editor.removeNode(existingNode.id);
        hook.nodeMap.delete(id);

        const newNode = new FlowNodeClass(existingNode.nodeType, id, nodeData);
        newNode.id = `node-${id}`;

        await hook.editor.addNode(newNode);
        await hook.area.translate(newNode.id, position);
        hook.nodeMap.set(id, newNode);

        await hook.area.update("node", newNode.id);
        await hook.syncNodeSize(newNode.id);

        for (const connInfo of affectedConnections) {
          const sourceNode = hook.nodeMap.get(connInfo.source!);
          const targetNode = hook.nodeMap.get(connInfo.target!);
          if (sourceNode && targetNode) {
            if (
              sourceNode.outputs[connInfo.sourceOutput] &&
              targetNode.inputs[connInfo.targetInput]
            ) {
              const connection = new ClassicPreset.Connection(
                sourceNode,
                connInfo.sourceOutput,
                targetNode,
                connInfo.targetInput,
              );
              await hook.editor.addConnection(connection);
              if (connInfo.connData) {
                hook.connectionDataMap.set(connection.id, connInfo.connData);
              }
            }
          }
        }
      } finally {
        hook.exitLoadingFromServer();
      }
    },

    async handleConnectionAdded(data: Record<string, unknown>) {
      const existingConn = hook.editor
        .getConnections()
        .find(
          (c) =>
            (hook.editor.getNode(c.source))?.nodeId ===
              data.source_node_id &&
            c.sourceOutput === data.source_pin &&
            (hook.editor.getNode(c.target))?.nodeId ===
              data.target_node_id &&
            c.targetInput === data.target_pin,
        );

      if (existingConn) {
        hook.connectionDataMap.set(existingConn.id, {
          id: data.id as number,
          label: (data.label as string) || null,
          condition: data.condition || null,
        });
        return;
      }

      hook.enterLoadingFromServer();
      try {
        await hook.addConnectionToEditor(data);
      } finally {
        hook.exitLoadingFromServer();
      }
    },

    async handleConnectionRemoved(data: Record<string, unknown>) {
      hook.enterLoadingFromServer();
      try {
        const connections = hook.editor.getConnections();
        for (const conn of connections) {
          const sourceNode = hook.editor.getNode(conn.source);
          const targetNode = hook.editor.getNode(conn.target);

          if (
            sourceNode?.nodeId === data.source_node_id &&
            targetNode?.nodeId === data.target_node_id
          ) {
            hook.connectionDataMap.delete(conn.id);
            await hook.editor.removeConnection(conn.id);
            break;
          }
        }
      } finally {
        hook.exitLoadingFromServer();
      }
    },

    handleNodeDataChanged(data: Record<string, unknown>) {
      if (!hook.history) {
        return;
      }
      const { id, prev_data: prevData, new_data: newData } = data as {
        id: string | number;
        prev_data: NodeData;
        new_data: NodeData;
      };

      const recent = hook.history
        .getRecent(NODE_DATA_COALESCE_MS)
        .filter((r) => r.action instanceof NodeDataAction && r.action.nodeId === id);

      if (recent[0]) {
        (recent[0].action as NodeDataAction).newData = newData;
        recent[0].time = Date.now();
      } else {
        hook.history.add(new NodeDataAction(hook, id, prevData, newData));
      }
    },

    handleFlowMetaChanged(data: Record<string, unknown>) {
      if (!hook.history) {
        return;
      }
      const { field, prev, new: newValue } = data as {
        field: string;
        prev: unknown;
        new: unknown;
      };

      const recent = hook.history
        .getRecent(FLOW_META_COALESCE_MS)
        .filter((r) => r.action instanceof FlowMetaAction && r.action.field === field);

      if (recent[0]) {
        (recent[0].action as FlowMetaAction).newValue = newValue;
        recent[0].time = Date.now();
      } else {
        hook.history.add(new FlowMetaAction(hook, field, prev, newValue));
      }
    },

    handleConnectionUpdated(data: Record<string, unknown>) {
      const connId = `conn-${data.id}`;
      hook.connectionDataMap.set(connId, {
        id: data.id as number,
        label: data.label as string,
        condition: data.condition,
      });

      const conn = hook.editor.getConnections().find((c) => c.id === connId);
      if (conn) {
        hook.area.update("connection", conn.id);
      }
    },

    destroy() {
      for (const timer of Object.values(hook._throttleTimers || {})) {
        clearTimeout(timer);
      }
    },
  };
}
