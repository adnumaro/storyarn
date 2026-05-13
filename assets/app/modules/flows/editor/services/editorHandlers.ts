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
import type { FlowSchemes, FlowAreaExtra, FlowConnection } from "../lib/rete-schemes";
import type { SheetMapEntry } from "../../types";
import { normalizeFlowSequenceStacking } from "./flowSequenceScopes";
import {
  CreateNodeAction,
  DeleteNodeAction,
  FLOW_META_COALESCE_MS,
  FlowMetaAction,
  NODE_DATA_COALESCE_MS,
  NodeDataAction,
} from "./historyPreset";

export type { SheetMapEntry };

// ---------------------------------------------------------------------------
// Server event payload interfaces
// ---------------------------------------------------------------------------

export interface NodeMovedPayload {
  node_id: string | number;
  x: number;
  y: number;
}

export interface NodeServerPayload {
  id: string | number;
  type: string;
  data: NodeData;
  position?: { x: number; y: number };
  parent_id?: number | null;
  self?: boolean;
}

export interface NodeRemovedPayload {
  id: string | number;
  self?: boolean;
}

export interface NodeRestoredPayload {
  node: NodeServerPayload;
  connections?: ConnectionServerPayload[];
}

export interface NodeUpdatedPayload {
  id: string | number;
  data: NodeData;
}

export interface ConnectionServerPayload {
  id: number;
  source_node_id: string | number;
  target_node_id: string | number;
  source_pin: string;
  target_pin: string;
  label?: string;
  condition?: unknown;
}

export interface ConnectionRemovedPayload {
  source_node_id: string | number;
  target_node_id: string | number;
}

export interface ConnectionUpdatedPayload {
  id: number;
  label?: string;
  condition?: unknown;
}

export interface NodeDataChangedPayload {
  id: string | number;
  prev_data: NodeData;
  new_data: NodeData;
}

export interface FlowMetaChangedPayload {
  field: string;
  prev: unknown;
  new: unknown;
}

export interface FlowUpdatedPayload {
  nodes?: NodeServerPayload[];
  connections?: ConnectionServerPayload[];
}

export interface SequenceConfigUpdatedPayload {
  sequence_id: string | number;
  position_x?: number | null;
  position_y?: number | null;
  width?: number | null;
  height?: number | null;
}

export interface HubMapEntry {
  color_hex: string | null;
  label: string;
  jumpCount: number;
}

// ---------------------------------------------------------------------------
// FlowContext & HookProxy
// ---------------------------------------------------------------------------

export interface FlowContext {
  sheetsMap: Record<string, SheetMapEntry>;
  hubsMap: Record<string, HubMapEntry>;
  lod: string;
  editingNodeId: string | null;
  onInlineEditSave: ((reteNodeId: string, field: string, value: unknown) => void) | null;
  nodeDataVersion: number;
  selectedReteNodeId: string | null;
  /** Rete ids of all currently-selected nodes (click + marquee). Reactive so
   *  FlowNode.vue can render a selection ring when `data.id ∈ this set`. */
  selectedReteIds: Set<string | number>;
  canEdit: boolean;
  toolbarProps: Record<string, unknown>;
  zoom: number;
}

export interface HookProxy {
  pushEvent: (event: string, payload: Record<string, unknown>) => void;
  handleEvent: (event: string, callback: (data: Record<string, unknown>) => void) => void;
  editor: NodeEditor<FlowSchemes>;
  area: AreaPlugin<FlowSchemes, FlowAreaExtra>;
  connection: unknown;
  history: HistoryPlugin<FlowSchemes> | null;
  nodeMap: Map<string | number, FlowNode>;
  connectionDataMap: Map<string, { id: number; label: string | null; condition: unknown }>;
  sheetsMap: Record<string, SheetMapEntry>;
  hubsMap: Record<string, HubMapEntry>;
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
  performAutoLayout(): Promise<void>;
  _sheetsMap: Record<string, SheetMapEntry>;
  _hubsMap: Record<string, HubMapEntry>;
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
  addNodeToEditor(data: NodeServerPayload): Promise<FlowNode>;
  addConnectionToEditor(data: ConnectionServerPayload): Promise<FlowConnection | undefined>;
  rebuildHubsMap(): Promise<void>;
  syncNodeSize(nodeId: string): Promise<void>;
  syncAllNodeSizes(): Promise<void>;
  fitSequencesToChildren(): Promise<void>;
  loadFlow(data: FlowUpdatedPayload): Promise<void>;
}

interface Position {
  x: number;
  y: number;
}

export interface NodeReparentedPayload {
  node_id: string | number;
  parent_id: string | number | null;
}

export interface SequenceRenamedPayload {
  node_id: string | number;
  name: string;
}

export interface EditorHandlers {
  init(): void;
  throttleNodeMoved(nodeId: string | number, position: Position): void;
  flushNodeMoved(nodeId: string | number): void;
  handleNodeMoved(data: NodeMovedPayload): Promise<void>;
  handleNodeReparented(data: NodeReparentedPayload): Promise<void>;
  handleSequenceRenamed(data: SequenceRenamedPayload): void;
  handleSequenceConfigUpdated(data: SequenceConfigUpdatedPayload): Promise<void>;
  handleFlowUpdated(data: FlowUpdatedPayload): Promise<void>;
  handleNodeAdded(data: NodeServerPayload): Promise<void>;
  handleNodeRemoved(data: NodeRemovedPayload): Promise<void>;
  handleNodeRestored(data: NodeRestoredPayload): Promise<void>;
  handleNodeUpdated(data: NodeUpdatedPayload): Promise<void>;
  rebuildNode(id: string | number, existingNode: FlowNode, nodeData: NodeData): Promise<void>;
  handleConnectionAdded(data: ConnectionServerPayload): Promise<void>;
  handleConnectionRemoved(data: ConnectionRemovedPayload): Promise<void>;
  handleNodeDataChanged(data: NodeDataChangedPayload): void;
  handleFlowMetaChanged(data: FlowMetaChangedPayload): void;
  handleConnectionUpdated(data: ConnectionUpdatedPayload): void;
  destroy(): void;
}

// ---------------------------------------------------------------------------
// Private helpers (extracted to reduce per-method complexity)
// ---------------------------------------------------------------------------

function cleanupEditContext(hook: HookProxy, node: FlowNode): void {
  const ctx = hook._flowContext;
  if (ctx?.editingNodeId === node.id) {
    ctx.editingNodeId = null;
  }
}

function cleanupThrottleTimer(hook: HookProxy, nodeId: string | number): void {
  if (hook._throttleTimers?.[nodeId]) {
    clearTimeout(hook._throttleTimers[nodeId]);
    delete hook._throttleTimers[nodeId];
  }
}

async function removeRelatedConnections(hook: HookProxy, reteNodeId: string): Promise<void> {
  const connections = [...hook.editor.getConnections()];
  for (const conn of connections) {
    if (conn.source === reteNodeId || conn.target === reteNodeId) {
      hook.connectionDataMap.delete(conn.id);
      await hook.editor.removeConnection(conn.id);
    }
  }
}

function recordNodeDeleteHistory(hook: HookProxy, data: NodeRemovedPayload): void {
  if (data.self && hook._historyTriggeredDelete !== data.id) {
    hook.history?.add(new DeleteNodeAction(hook, data.id));
  }
  if (hook._historyTriggeredDelete === data.id) {
    hook._historyTriggeredDelete = null;
  }
}

function clearSequenceChildParents(hook: HookProxy, node: FlowNode): void {
  if (node.nodeType !== "sequence") {
    return;
  }

  // The server-side `flow_node_parent_nullify` trigger has already nilified
  // child `parent_id` rows, so mirroring that locally keeps the editor
  // consistent if accompanying `node_updated` broadcasts arrive after us.
  for (const child of hook.editor.getNodes()) {
    if (child.parent === node.id) {
      child.parent = undefined;
    }
  }
}

function clearSelectedNode(hook: HookProxy, nodeId: string | number): void {
  if (hook.selectedNodeId === nodeId) {
    hook.selectedNodeId = null;
  }
}

interface AffectedConnection {
  source: string | number | undefined;
  sourceOutput: string;
  target: string | number | undefined;
  targetInput: string;
  connData: { id: number; label: string | null; condition: unknown } | undefined;
}

function collectAffectedConnections(hook: HookProxy, reteNodeId: string): AffectedConnection[] {
  const connections = [...hook.editor.getConnections()];
  const affected: AffectedConnection[] = [];

  for (const conn of connections) {
    if (conn.source === reteNodeId || conn.target === reteNodeId) {
      affected.push({
        source: hook.editor.getNode(conn.source)?.nodeId,
        sourceOutput: conn.sourceOutput,
        target: hook.editor.getNode(conn.target)?.nodeId,
        targetInput: conn.targetInput,
        connData: hook.connectionDataMap.get(conn.id),
      });
    }
  }
  return affected;
}

async function removeAffectedConnections(hook: HookProxy, reteNodeId: string): Promise<void> {
  const connections = [...hook.editor.getConnections()];
  for (const conn of connections) {
    if (conn.source === reteNodeId || conn.target === reteNodeId) {
      hook.connectionDataMap.delete(conn.id);
      await hook.editor.removeConnection(conn.id);
    }
  }
}

async function reconnectNode(
  hook: HookProxy,
  affectedConnections: AffectedConnection[],
): Promise<void> {
  for (const connInfo of affectedConnections) {
    const sourceNode = hook.nodeMap.get(connInfo.source!);
    const targetNode = hook.nodeMap.get(connInfo.target!);
    if (!sourceNode || !targetNode) {
      continue;
    }
    if (!sourceNode.outputs[connInfo.sourceOutput] || !targetNode.inputs[connInfo.targetInput]) {
      continue;
    }
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

function sequenceView(hook: HookProxy, nodeId: string) {
  return hook.area.nodeViews.get(nodeId) as
    | { position: { x: number; y: number }; translate?: (x: number, y: number) => void }
    | undefined;
}

function translateSequenceView(
  view: { position: { x: number; y: number }; translate?: (x: number, y: number) => void },
  x: number,
  y: number,
): void {
  if (typeof view.translate === "function") {
    view.translate(x, y);
  } else {
    view.position.x = x;
    view.position.y = y;
  }
}

async function refreshAllConnections(hook: HookProxy): Promise<void> {
  for (const connection of hook.editor.getConnections()) {
    await hook.area.update("connection", connection.id);
  }
}

async function applyRemoteSequenceGeometry(
  hook: HookProxy,
  node: FlowNode,
  data: SequenceConfigUpdatedPayload,
): Promise<void> {
  const view = sequenceView(hook, node.id);
  const width = typeof data.width === "number" ? data.width : node.width;
  const height = typeof data.height === "number" ? data.height : node.height;

  hook.enterLoadingFromServer();
  try {
    if (view && typeof data.position_x === "number" && typeof data.position_y === "number") {
      translateSequenceView(view, data.position_x, data.position_y);
    }

    node.width = width;
    node.height = height;
    node.nodeData = { ...node.nodeData, width, height };
    await hook.area.resize(node.id, width, height);
    await refreshAllConnections(hook);
  } finally {
    hook.exitLoadingFromServer();
  }
}

// ---------------------------------------------------------------------------
// Main factory
// ---------------------------------------------------------------------------

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

    async handleNodeMoved(data: NodeMovedPayload) {
      const { node_id, x, y } = data;
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

    // Remote sequence rename — mutate the in-memory node's nodeData.name
    // and bump `nodeDataVersion` so any component reading the Vue-reactive
    // mirror re-renders. `Sequence.vue` binds the header label to
    // `data.nodeData?.name` via a computed, so updating the field on the
    // class instance + bumping the version is enough.
    handleSequenceRenamed(data) {
      const node = hook.nodeMap.get(data.node_id);
      if (!node) {
        return;
      }
      node.nodeData = { ...node.nodeData, name: data.name };
      const ctx = hook._flowContext;
      if (ctx) {
        ctx.nodeDataVersion = (ctx.nodeDataVersion || 0) + 1;
      }
    },

    async handleSequenceConfigUpdated(data) {
      const node = hook.nodeMap.get(data.sequence_id);
      if (!node || node.nodeType !== "sequence") {
        return;
      }

      await applyRemoteSequenceGeometry(hook, node, data);

      const ctx = hook._flowContext;
      if (ctx) {
        ctx.nodeDataVersion = (ctx.nodeDataVersion || 0) + 1;
      }
    },

    // Remote reparent (another collaborator dragged+dropped a node or used
    // the context-menu "Remove from sequence…"). Mirror the change on the
    // local rete editor and ensure sequence containers still contain their
    // children without compacting the previous parent.
    async handleNodeReparented(data) {
      const { node_id, parent_id } = data;
      const node = hook.nodeMap.get(node_id);
      if (!node) {
        return;
      }

      const newParent = parent_id == null ? undefined : `node-${parent_id}`;

      hook.enterLoadingFromServer();
      try {
        node.parent = newParent;
        normalizeFlowSequenceStacking({ area: hook.area, editor: hook.editor }, node.id);
        await hook.fitSequencesToChildren();
      } finally {
        hook.exitLoadingFromServer();
      }
    },

    async handleFlowUpdated(data: FlowUpdatedPayload) {
      hook.history?.clear();

      hook.enterLoadingFromServer();
      try {
        for (const conn of hook.editor.getConnections()) {
          try {
            await hook.editor.removeConnection(conn.id);
          } catch {}
        }
        // Clear every `.parent` pointer before wiping so every removeNode
        // succeeds in any iteration order and stale local parents cannot
        // outlive the server snapshot.
        for (const node of hook.editor.getNodes()) {
          node.parent = undefined;
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
        await hook.fitSequencesToChildren();
      } finally {
        hook.exitLoadingFromServer();
      }
    },

    async handleNodeAdded(data: NodeServerPayload) {
      hook.enterLoadingFromServer();
      try {
        await hook.addNodeToEditor(data);
      } finally {
        hook.exitLoadingFromServer();
      }
      if (data.self && hook.history) {
        hook.history.add(new CreateNodeAction(hook, data.id));
      }
      if (data.type === "hub" || data.type === "jump") {
        await hook.rebuildHubsMap();
      }
    },

    async handleNodeRemoved(data: NodeRemovedPayload) {
      const node = hook.nodeMap.get(data.id);
      if (!node) {
        return;
      }

      cleanupEditContext(hook, node);
      cleanupThrottleTimer(hook, data.id);
      recordNodeDeleteHistory(hook, data);

      const needsHubRebuild = node.nodeType === "hub" || node.nodeType === "jump";
      hook.enterLoadingFromServer();
      try {
        await removeRelatedConnections(hook, node.id);
        clearSequenceChildParents(hook, node);
        await hook.editor.removeNode(node.id);
      } finally {
        hook.exitLoadingFromServer();
      }
      hook.nodeMap.delete(data.id);
      clearSelectedNode(hook, data.id);
      if (needsHubRebuild) {
        await hook.rebuildHubsMap();
      }
    },

    async handleNodeRestored(data: NodeRestoredPayload) {
      hook.enterLoadingFromServer();
      try {
        const node = await hook.addNodeToEditor(data.node);
        if (node) {
          await hook.area.update("node", node.id);
          await hook.syncNodeSize(node.id);
        }
        for (const conn of data.connections || []) {
          if (!hook.editor.getConnection(`conn-${conn.id}`)) {
            await hook.addConnectionToEditor(conn);
          }
        }
      } finally {
        hook.exitLoadingFromServer();
      }
      if (data.node.type === "hub" || data.node.type === "jump") {
        await hook.rebuildHubsMap();
      }
    },

    async handleNodeUpdated(data: NodeUpdatedPayload) {
      const { id, data: nodeData } = data;
      const existingNode = hook.nodeMap.get(id);
      if (!existingNode) {
        return;
      }

      // While inline editing we skip rebuildNode (would destroy input focus),
      // but we still bump nodeDataVersion so view mode renders the fresh value
      // when the user exits edit mode.
      const ctx = hook._flowContext;
      if (ctx?.editingNodeId === existingNode.id) {
        existingNode.nodeData = { ...nodeData };
        ctx.nodeDataVersion = (ctx.nodeDataVersion || 0) + 1;
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
        await hook.syncNodeSize(existingNode.id);
      }

      if (existingNode.nodeType === "hub" || existingNode.nodeType === "jump") {
        await hook.rebuildHubsMap();
      }
    },

    async rebuildNode(id: string | number, existingNode: FlowNode, nodeData: NodeData) {
      cleanupEditContext(hook, existingNode);

      const view = hook.area.nodeViews.get(existingNode.id);
      const position: Position = view ? { ...view.position } : { x: 0, y: 0 };

      hook.enterLoadingFromServer();
      try {
        const affected = collectAffectedConnections(hook, existingNode.id);
        await removeAffectedConnections(hook, existingNode.id);
        await hook.editor.removeNode(existingNode.id);
        hook.nodeMap.delete(id);

        const newNode = new FlowNodeClass(existingNode.nodeType, id, nodeData);
        newNode.id = `node-${id}`;

        await hook.editor.addNode(newNode);
        await hook.area.translate(newNode.id, position);
        hook.nodeMap.set(id, newNode);

        await hook.area.update("node", newNode.id);
        await hook.syncNodeSize(newNode.id);

        await reconnectNode(hook, affected);
      } finally {
        hook.exitLoadingFromServer();
      }
    },

    async handleConnectionAdded(data: ConnectionServerPayload) {
      const existingConn = hook.editor
        .getConnections()
        .find(
          (c) =>
            hook.editor.getNode(c.source)?.nodeId === data.source_node_id &&
            c.sourceOutput === data.source_pin &&
            hook.editor.getNode(c.target)?.nodeId === data.target_node_id &&
            c.targetInput === data.target_pin,
        );

      if (existingConn) {
        hook.connectionDataMap.set(existingConn.id, {
          id: data.id,
          label: data.label || null,
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

    async handleConnectionRemoved(data: ConnectionRemovedPayload) {
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

    handleNodeDataChanged(data: NodeDataChangedPayload) {
      if (!hook.history) {
        return;
      }
      const { id, prev_data: prevData, new_data: newData } = data;

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

    handleFlowMetaChanged(data: FlowMetaChangedPayload) {
      if (!hook.history) {
        return;
      }
      const { field, prev, new: newValue } = data;

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

    handleConnectionUpdated(data: ConnectionUpdatedPayload) {
      const connId = `conn-${data.id}`;
      hook.connectionDataMap.set(connId, {
        id: data.id,
        label: data.label || null,
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
