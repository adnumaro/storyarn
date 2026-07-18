/**
 * Composable managing the Rete.js flow canvas lifecycle.
 * Replaces the V1 FlowCanvas Phoenix hook -- Vue owns the editor.
 *
 * Handles: plugin setup, 3-phase node/connection loading, socket deferral,
 * node size sync, hub map rebuild, event bindings, auto-layout, and cleanup.
 */

import { ClassicPreset } from "rete";
import { onUnmounted } from "vue";

import { FlowNode } from "../lib/flow-node";
import type { FlowAreaExtra, FlowConnection } from "../lib/rete-schemes";
import { debug } from "../services/debug";
import {
  editorHandlers,
  type FlowContext,
  type HookProxy,
  type HubMapEntry,
} from "../services/editorHandlers";
import { keyboard } from "../services/keyboard";
import { lod } from "../services/lod";
import { navigation } from "../services/navigation";
import { buildConnectionRemovalPayload } from "../services/connectionIdentity";

import { createFlowPlacement } from "../services/flowPlacement";
import { createPlugins, finalizeSetup } from "../services/reteSetup";
import { performFlowCanvasAutoLayout } from "./flowCanvasAutoLayout";
import { createFlowCanvasRuntime } from "./flowCanvasRuntime";
import { setupFlowCanvasServerEvents } from "./flowCanvasServerEvents";
import type {
  ConnectionData,
  FlowCanvasOpts,
  FlowCanvasReturn,
  FlowData,
  InitOpts,
  NodeServerData,
} from "./flowCanvasTypes";
import { createFlowSequenceGeometry, type FlowSequenceFitOptions } from "./flowSequenceGeometry";
import { createFlowMarquee } from "../services/flowMarquee";

export type { FlowCanvasReturn } from "./flowCanvasTypes";

function addHubToMap(map: Record<string, HubMapEntry>, node: FlowNode): void {
  if (node.nodeType !== "hub" || !node.nodeData?.hub_id) {
    return;
  }

  map[node.nodeData.hub_id as string] = {
    color_hex: (node.nodeData.color_hex as string) || null,
    label: (node.nodeData.label as string) || "",
    jumpCount: 0,
  };
}

function countJumpForHub(map: Record<string, HubMapEntry>, node: FlowNode): void {
  if (node.nodeType !== "jump" || !node.nodeData?.target_hub_id) {
    return;
  }

  const entry = map[node.nodeData.target_hub_id as string];
  if (entry) {
    entry.jumpCount++;
  }
}

export function buildHubsMap(
  nodeMap: ReadonlyMap<string | number, FlowNode>,
): Record<string, HubMapEntry> {
  const map: Record<string, HubMapEntry> = {};

  for (const [, node] of nodeMap) {
    addHubToMap(map, node);
  }

  for (const [, node] of nodeMap) {
    countJumpForHub(map, node);
  }

  return map;
}

export function useFlowCanvas({ pushEvent, handleEvent }: FlowCanvasOpts): FlowCanvasReturn {
  const runtime = createFlowCanvasRuntime(
    { pushEvent, handleEvent },
    {
      addNodeToEditor,
      addConnectionToEditor,
      rebuildHubsMap,
      syncNodeSize,
      syncAllNodeSizes,
      fitSequencesToChildren,
      loadFlow: loadInitialFlowData,
      performAutoLayout,
    },
  );

  const editor = runtime.editorRef;
  const area = runtime.areaRef;
  const loading = runtime.loading;
  const toolbarState = runtime.toolbarState;
  const hookProxy: HookProxy = runtime.hookProxy;
  const flowSequenceGeometry = createFlowSequenceGeometry(runtime);

  // --- Toolbar positioning ---

  function selectNodeForToolbar(reteNodeId: string): void {
    const node = runtime.editor!.getNode(reteNodeId);
    if (!node) {
      clearToolbar();
      return;
    }
    toolbarState.reteNodeId = reteNodeId;
    toolbarState.nodeId = node.nodeId;
    toolbarState.nodeType = node.nodeType;
    toolbarState.nodeData = node.nodeData;
    toolbarState.visible = true;
    hookProxy._flowContext.selectedReteNodeId = reteNodeId;
  }

  function clearToolbar(): void {
    toolbarState.visible = false;
    toolbarState.reteNodeId = null;
    toolbarState.nodeId = null;
    toolbarState.nodeType = null;
    toolbarState.nodeData = null;
    hookProxy._flowContext.selectedReteNodeId = null;
  }

  // --- Inline edit ---

  function enterInlineEdit(reteNodeId: string): void {
    exitInlineEdit();
    const node = runtime.editor!.getNode(reteNodeId);
    if (!node) {
      return;
    }
    const type = node.nodeType;
    if (type !== "dialogue" && type !== "annotation") {
      return;
    }

    const ctx = (hookProxy as { _flowContext: FlowContext })._flowContext;
    if (!ctx) {
      return;
    }
    ctx.editingNodeId = reteNodeId;
    // Edit-mode body is taller than view-mode (inputs + inline editor).
    // Re-measure so rete's wrapper height matches the rendered node.
    void syncNodeSize(reteNodeId);
  }

  function exitInlineEdit(): void {
    const ctx = (hookProxy as { _flowContext: FlowContext })._flowContext;
    if (!ctx || !ctx.editingNodeId) {
      return;
    }

    const editingId = ctx.editingNodeId;
    // Blur active input/textarea/contenteditable inside the node so blur
    // handlers fire and save. Contenteditable covers the TipTap inline editor
    // — its onBlur handler is what commits the dialogue text on Esc.
    const nodeView = runtime.area?.nodeViews.get(editingId);
    if (nodeView) {
      const focused = nodeView.element.querySelector(
        'textarea:focus, input:focus, [contenteditable="true"]:focus',
      ) as HTMLElement | null;
      if (focused) {
        focused.blur();
      }
    }

    ctx.editingNodeId = null;
    void syncNodeSize(editingId);
  }

  function handleInlineEditSave(reteNodeId: string, field: string, value: unknown): void {
    const node = runtime.editor!.getNode(reteNodeId);
    if (!node) {
      return;
    }

    if (field === "text" && node.nodeType === "annotation") {
      node.nodeData = { ...node.nodeData, text: value as string };
      pushEvent("update_node_field", { field: "text", value: value as string });
    } else if (field === "text") {
      // Dialogue inline editor (TipTap, screenplay-format) emits HTML
      // directly. Persist through `update_node_text` — same wire as the
      // sidebar editor in FlowDialoguePanel.
      const content = value as string;
      node.nodeData = { ...node.nodeData, text: content };
      pushEvent("update_node_text", { id: node.nodeId, content });
    } else if (field === "speaker_sheet_id") {
      const newSpeakerId = value || null;
      node.nodeData = { ...node.nodeData, speaker_sheet_id: newSpeakerId };
      node._updateTs = Date.now();
      runtime.area!.update("node", node.id);
      pushEvent("update_node_field", {
        field: "speaker_sheet_id",
        value: newSpeakerId as string,
      });
    } else {
      node.nodeData = { ...node.nodeData, [field]: value };
      pushEvent("update_node_field", { field, value: value as string });
    }
  }

  // --- Init helpers ---

  function initHandlers(): void {
    runtime.editorHandlers = editorHandlers(hookProxy);
    runtime.navigationHandler = navigation(runtime.area!, runtime.nodeMap, pushEvent);
    runtime.debugHandler = debug(hookProxy.area, hookProxy.editor, runtime.nodeMap, undefined);

    hookProxy.editorHandlers = runtime.editorHandlers;
    hookProxy.navigationHandler = runtime.navigationHandler;
    hookProxy.debugHandler = runtime.debugHandler;

    runtime.editorHandlers.init();
  }

  function initPlugins(containerEl: HTMLElement): void {
    const plugins = createPlugins(containerEl, hookProxy);
    runtime.editor = plugins.editor;
    runtime.area = plugins.area;
    runtime.connection = plugins.connection;
    runtime.history = plugins.history;
    runtime.minimap = plugins.minimap;

    editor.value = runtime.editor;
    area.value = runtime.area;
  }

  function setupCanvasClickHandler(containerEl: HTMLElement): void {
    runtime.canvasClickController = new AbortController();
    containerEl.addEventListener(
      "pointerdown",
      (e: PointerEvent) => {
        if (e.button !== 0) {
          return;
        }
        const nodeEl = (e.target as HTMLElement).closest("[data-testid='node']");
        if (!nodeEl) {
          if ((hookProxy as { _flowContext: FlowContext })._flowContext?.editingNodeId) {
            exitInlineEdit();
          }
          clearToolbar();
          runtime.selectedNodeId = null;
        }
      },
      { signal: runtime.canvasClickController.signal },
    );
  }

  function setupSequenceResizeHandler(containerEl: HTMLElement): void {
    if (hookProxy._readonly) {
      return;
    }

    runtime.sequenceResizeController = new AbortController();
    containerEl.addEventListener(
      "flow-sequence-resize",
      (event) => {
        void flowSequenceGeometry.handleSequenceResize(event);
      },
      { signal: runtime.sequenceResizeController.signal },
    );
  }

  function fitSequencesToChildren(opts: FlowSequenceFitOptions = {}): Promise<void> {
    return flowSequenceGeometry.fitSequencesToChildren(opts);
  }

  function expandParentSequenceForNode(
    node: FlowNode,
    position: { x: number; y: number },
    opts: { allowModifier: boolean },
  ): Promise<void> {
    return flowSequenceGeometry.expandParentSequenceForNode(node, position, opts);
  }

  function flushPendingSequenceGeometry(): void {
    flowSequenceGeometry.flushPendingSequenceGeometry();
  }

  async function loadInitialFlowData(flowData: FlowData): Promise<void> {
    hookProxy._hubsMap = {};
    if (!flowData.nodes) {
      return;
    }

    runtime.deferSocketCalc = true;
    runtime.loadingFromServerCount++;

    // Parent nodes should exist before their children reference them via
    // `parent`. Sort nodes so ancestors load first.
    const sorted = sortNodesByParentDepth(flowData.nodes);

    for (const nodeData of sorted) {
      await addNodeToEditor(nodeData);
    }

    runtime.deferSocketCalc = false;
    await flushDeferredSockets();

    for (const connData of flowData.connections || []) {
      await addConnectionToEditor(connData);
    }

    runtime.loadingFromServerCount = Math.max(0, runtime.loadingFromServerCount - 1);
  }

  function sortNodesByParentDepth(
    nodes: NonNullable<FlowData["nodes"]>,
  ): NonNullable<FlowData["nodes"]> {
    const byId = new Map(nodes.map((n) => [Number(n.id), n]));
    const depth = new Map<number, number>();

    function nodeDepth(id: number, seen = new Set<number>()): number {
      if (depth.has(id)) return depth.get(id)!;
      if (seen.has(id)) return 0; // cycle safety — shouldn't happen with FK
      seen.add(id);
      const n = byId.get(id);
      if (!n || n.parent_id == null) {
        depth.set(id, 0);
        return 0;
      }
      const d = 1 + nodeDepth(n.parent_id, seen);
      depth.set(id, d);
      return d;
    }

    return [...nodes].sort((a, b) => nodeDepth(Number(a.id)) - nodeDepth(Number(b.id)));
  }

  function setupLOD(containerEl: HTMLElement): void {
    runtime.lodController = lod(runtime.area!, hookProxy);
    hookProxy.lodController = runtime.lodController;

    runtime.area!.addPipe((context) => {
      if ((context as { type: string }).type === "zoomed") {
        runtime.lodController!.onZoom();
        const k = runtime.area!.area.transform.k;
        containerEl.style.setProperty("--canvas-zoom", String(k));
        hookProxy._flowContext.zoom = k;
      }
      return context;
    });
  }

  function setupKeyboard(): void {
    if (hookProxy._readonly) {
      return;
    }
    runtime.keyboardHandler = keyboard(hookProxy, null);
    runtime.keyboardHandler.init();
    hookProxy.keyboardHandler = runtime.keyboardHandler;
  }

  function activatePostLoadPlugins(): void {
    if (runtime.history && !hookProxy._readonly) {
      runtime.area!.use(runtime.history);
    }
    if (runtime.minimap) {
      runtime.area!.use(runtime.minimap);
    }
  }

  // --- Init ---

  function applyInitOpts(containerEl: HTMLElement, opts: InitOpts): void {
    hookProxy._containerEl = containerEl;
    hookProxy._sheetsMap = opts.sheetsMap || {};
    hookProxy._readonly = opts.readonly || false;
    hookProxy._currentUserId = opts.userId || 0;
    hookProxy._currentUserColor = opts.userColor || "#3b82f6";
  }

  async function finalizeInit(flowData: FlowData): Promise<void> {
    await syncAllNodeSizes();
    await fitSequencesToChildren();
    const selection = await finalizeSetup(
      runtime.area!,
      runtime.editor!,
      (flowData.nodes?.length ?? 0) > 0,
      hookProxy._flowContext,
    );
    await recalculateAllSockets();

    // Marquee selection (drag-rectangle). Only active while the dock's tool
    // is in "select" mode — the composable watches `activeFlowTool` internally.
    if (!hookProxy._readonly && hookProxy._containerEl) {
      runtime.marqueeTeardown = createFlowMarquee({
        containerEl: hookProxy._containerEl,
        area: runtime.area!,
        editor: runtime.editor!,
        selection,
      });
      runtime.placementTeardown = createFlowPlacement({
        containerEl: hookProxy._containerEl,
        editor: runtime.editor!,
        area: runtime.area!,
        pushEvent,
      });
    }

    if ((flowData.nodes?.length ?? 0) > 0) {
      await rebuildHubsMap();
    }

    loading.value = false;
  }

  async function init(
    containerEl: HTMLElement,
    flowData: FlowData,
    opts: InitOpts = {},
  ): Promise<void> {
    applyInitOpts(containerEl, opts);

    initPlugins(containerEl);
    hookProxy._flowContext.canEdit = !hookProxy._readonly;

    if (!hookProxy._readonly) {
      initHandlers();
    }

    syncFlowContext();

    (hookProxy as { _flowContext: FlowContext })._flowContext.onInlineEditSave =
      handleInlineEditSave;

    setupCanvasClickHandler(containerEl);
    setupSequenceResizeHandler(containerEl);
    setupLOD(containerEl);

    await loadInitialFlowData(flowData);
    activatePostLoadPlugins();

    setupAreaPipes();
    setupFlowCanvasServerEvents(runtime);
    setupKeyboard();

    await finalizeInit(flowData);
  }

  // --- Node/Connection CRUD ---

  async function addNodeToEditor(nodeData: NodeServerData): Promise<FlowNode> {
    const node = new FlowNode(nodeData.type, nodeData.id, nodeData.data);
    node.id = `node-${nodeData.id}`;

    if (nodeData.parent_id != null) {
      node.parent = `node-${nodeData.parent_id}`;
    }

    await runtime.editor!.addNode(node);

    const x = nodeData.position?.x || 0;
    const y = nodeData.position?.y || 0;

    if (runtime.deferSocketCalc) {
      const view = runtime.area!.nodeViews.get(node.id);
      if (view) {
        view.translate(x, y);
      }
    } else {
      await runtime.area!.translate(node.id, { x, y });
    }

    // Sequences render via `Sequence.vue`, which deliberately does NOT bind
    // `:style="{ width, height }"` (see the comment in that file). Width
    // and height live as inline DOM styles written by `area.resize`.
    // Kickstart the resize here with the FlowNode's own width/height
    // (seeded from `data.width/height` in the constructor) so the bbox
    // shows up correctly before any interaction.
    if (node.nodeType === "sequence") {
      await runtime.area!.resize(node.id, node.width, node.height);
    }

    runtime.nodeMap.set(nodeData.id, node);
    return node;
  }

  async function addConnectionToEditor(
    connData: ConnectionData,
  ): Promise<FlowConnection | undefined> {
    const sourceNode = runtime.nodeMap.get(connData.source_node_id);
    const targetNode = runtime.nodeMap.get(connData.target_node_id);
    if (!sourceNode || !targetNode) {
      return;
    }

    if (!sourceNode.outputs[connData.source_pin]) {
      return;
    }
    if (!targetNode.inputs[connData.target_pin]) {
      return;
    }

    const connection = new ClassicPreset.Connection(
      sourceNode,
      connData.source_pin,
      targetNode,
      connData.target_pin,
    );
    connection.id = `conn-${connData.id}`;

    runtime.connectionDataMap.set(connection.id, {
      id: connData.id,
      label: connData.label || null,
      condition: connData.condition,
    });

    await runtime.editor!.addConnection(connection);
    return connection;
  }

  // --- Socket management ---

  async function flushDeferredSockets(): Promise<void> {
    const deferred = runtime.deferredSockets;
    runtime.deferredSockets = [];
    await new Promise((r) => requestAnimationFrame(r));
    for (const ctx of deferred) {
      await runtime.area!.emit(ctx as FlowAreaExtra);
    }
  }

  async function recalculateAllSockets(): Promise<void> {
    const events = runtime.socketRenderedEvents;
    if (!events || events.length === 0) {
      return;
    }
    runtime.socketRenderedEvents = [];
    runtime.isRecalculatingSockets = true;
    await new Promise((r) => requestAnimationFrame(r));
    for (const ctx of events) {
      await runtime.area!.emit(ctx as FlowAreaExtra);
    }
    runtime.isRecalculatingSockets = false;
  }

  // --- Node size sync (Vue DOM, no shadow DOM) ---

  async function syncNodeSize(nodeId: string): Promise<void> {
    const view = runtime.area!.nodeViews.get(nodeId);
    if (!view) {
      return;
    }
    const nodeEl = view.element.querySelector("[data-testid='node']") as HTMLElement | null;
    if (!nodeEl) {
      return;
    }

    await new Promise((r) => requestAnimationFrame(r));
    const w = nodeEl.offsetWidth;
    const h = nodeEl.offsetHeight;
    if (w > 0 && h > 0) {
      const node = runtime.editor!.getNode(nodeId);
      if (node) {
        node.width = w;
        node.height = h;
      }
      await runtime.area!.resize(nodeId, w, h);
    }
  }

  async function syncAllNodeSizes(): Promise<void> {
    await new Promise((r) => requestAnimationFrame(r));
    for (const [nodeId] of runtime.area!.nodeViews) {
      await syncNodeSize(nodeId);
    }
  }

  // --- Hub map ---

  async function updateHubAndJumpNodes(): Promise<void> {
    const ts = Date.now();
    for (const [, node] of runtime.nodeMap) {
      if (node.nodeType === "hub" || node.nodeType === "jump") {
        node._updateTs = ts;
        await runtime.area!.update("node", node.id);
      }
    }
  }

  async function rebuildHubsMap(): Promise<void> {
    const map = buildHubsMap(runtime.nodeMap);
    hookProxy._hubsMap = map;
    syncFlowContext();
    await updateHubAndJumpNodes();
  }

  // --- Sync reactive flow context (used by Vue node components via inject) ---

  function syncFlowContext(): void {
    const ctx = (hookProxy as { _flowContext: FlowContext })._flowContext;
    if (!ctx) {
      return;
    }
    ctx.sheetsMap = hookProxy._sheetsMap || {};
    ctx.hubsMap = hookProxy._hubsMap || {};
  }

  // --- Area pipe helpers ---

  async function handleNodeTranslated(context: unknown): Promise<void> {
    if (hookProxy.isLoadingFromServer) {
      return;
    }
    const ctxData = (context as { data: { id: string; position: { x: number; y: number } } }).data;
    const node = runtime.editor!.getNode(ctxData.id);
    if (node?.nodeId) {
      await expandParentSequenceForNode(node, ctxData.position, { allowModifier: false });
      runtime.editorHandlers!.throttleNodeMoved(node.nodeId, ctxData.position);
    }
  }

  async function handleNodeDragged(context: unknown): Promise<void> {
    // Rete's `nodedragged` fires ONCE per drag gesture, for the node the
    // user actually grabbed. But `selectableNodes`'s `nodetranslated` pipe
    // translates every *selected* node by the same delta while dragging,
    // so `throttleNodeMoved` leaves pending positions in
    // `_pendingPositions` for each of them. If we only flush the dragged
    // node, the other selected ones' positions are broadcast as
    // `node_dragging` (preview only, no DB write) and never committed.
    // Flush everything that has a pending position, not just the grabbed
    // one.
    const pending = hookProxy._pendingPositions ?? {};
    const nodeIds = Object.keys(pending);
    for (const nodeId of nodeIds) {
      const node = hookProxy.nodeMap.get(Number(nodeId)) ?? hookProxy.nodeMap.get(nodeId);
      if (node) {
        await expandParentSequenceForNode(node, pending[nodeId], { allowModifier: false });
      }
      // Keys are string-numeric; convert back to the raw type flushNodeMoved expects.
      const numeric = Number(nodeId);
      runtime.editorHandlers!.flushNodeMoved(Number.isFinite(numeric) ? numeric : nodeId);
    }
    // Fallback for the grabbed node, in case it had no pending (edge case).
    const node = runtime.editor!.getNode((context as { data: { id: string } }).data.id);
    if (node?.nodeId && !nodeIds.includes(String(node.nodeId))) {
      const view = flowSequenceGeometry.nodeView(node.id);
      if (view) {
        await expandParentSequenceForNode(node, view.position, { allowModifier: false });
      }
      runtime.editorHandlers!.flushNodeMoved(node.nodeId);
    }
    flushPendingSequenceGeometry();
  }

  function setNodeDragTextSelectionDisabled(disabled: boolean): void {
    const container = runtime.area?.container;
    if (!container) {
      return;
    }

    container.classList.toggle("flow-canvas-node-dragging", disabled);

    if (disabled) {
      document.getSelection()?.removeAllRanges();
    }
  }

  // --- Area pipes (drag, selection, connections) ---

  function setupAreaPipes(): void {
    if (hookProxy._readonly) {
      runtime.area!.addPipe((context) => {
        if ((context as { type: string }).type === "nodepicked") {
          const node = runtime.editor!.getNode((context as { data: { id: string } }).data.id);
          if (node?.nodeId) {
            runtime.selectedNodeId = node.nodeId;
            pushEvent("node_selected", { id: node.nodeId });
          }
        }
        return context;
      });
      return;
    }

    // Node drag + toolbar reposition
    runtime.area!.addPipe(async (context) => {
      const type = (context as { type: string }).type;
      if (type === "nodetranslated") {
        setNodeDragTextSelectionDisabled(true);
        await handleNodeTranslated(context);
      } else if (type === "nodedragged") {
        try {
          await handleNodeDragged(context);
        } finally {
          setNodeDragTextSelectionDisabled(false);
        }
      } else if (type === "pointerup") {
        setNodeDragTextSelectionDisabled(false);
      }
      return context;
    });

    // Node selection + double-click
    runtime.area!.addPipe((context) => {
      if ((context as { type: string }).type === "nodepicked") {
        const nodeId = (context as { data: { id: string } }).data.id;
        const node = runtime.editor!.getNode(nodeId);
        if (node?.nodeId) {
          const now = Date.now();
          const isDoubleClick =
            runtime.lastClickedNodeId === node.nodeId && now - runtime.lastNodeClickTime < 300;

          runtime.lastNodeClickTime = now;
          runtime.lastClickedNodeId = node.nodeId;
          runtime.selectedNodeId = node.nodeId;

          if (isDoubleClick) {
            const reteNode = runtime.editor!.getNode(nodeId);
            const type = reteNode?.nodeType;
            if (type === "dialogue" || type === "annotation") {
              enterInlineEdit(nodeId);
            } else {
              pushEvent("node_double_clicked", { id: node.nodeId });
            }
          } else {
            selectNodeForToolbar(nodeId);
            pushEvent("node_selected", { id: node.nodeId });
          }
        }
      }
      return context;
    });

    // Connection created
    runtime.editor!.addPipe((context) => {
      if (
        (context as { type: string }).type === "connectioncreate" &&
        !hookProxy.isLoadingFromServer
      ) {
        const conn = (
          context as {
            data: { source: string; sourceOutput: string; target: string; targetInput: string };
          }
        ).data;
        const sourceNode = runtime.editor!.getNode(conn.source);
        const targetNode = runtime.editor!.getNode(conn.target);

        if (sourceNode?.nodeId && targetNode?.nodeId) {
          pushEvent("connection_created", {
            source_node_id: sourceNode.nodeId,
            source_pin: conn.sourceOutput,
            target_node_id: targetNode.nodeId,
            target_pin: conn.targetInput,
          });
        }
      }
      return context;
    });

    // Connection deleted
    runtime.editor!.addPipe((context) => {
      if (
        (context as { type: string }).type === "connectionremove" &&
        !hookProxy.isLoadingFromServer
      ) {
        const conn = (
          context as {
            data: {
              id: string;
              source: string;
              sourceOutput: string;
              target: string;
              targetInput: string;
            };
          }
        ).data;
        const sourceNode = runtime.editor!.getNode(conn.source);
        const targetNode = runtime.editor!.getNode(conn.target);

        if (sourceNode?.nodeId && targetNode?.nodeId) {
          const persistedId = runtime.connectionDataMap.get(conn.id)?.id;

          pushEvent(
            "connection_deleted",
            buildConnectionRemovalPayload(conn, sourceNode.nodeId, targetNode.nodeId, persistedId),
          );
        }
      }
      return context;
    });
  }

  // --- Cleanup ---

  function cleanupEventControllers(): void {
    runtime.canvasClickController?.abort();
    runtime.sequenceResizeController?.abort();
    hookProxy._eventBindingsController?.abort();
  }

  function destroyHandlers(): void {
    runtime.lodController?.destroy();
    runtime.keyboardHandler?.destroy();
    runtime.editorHandlers?.destroy();
    runtime.navigationHandler?.destroy();
    runtime.debugHandler?.destroy();
    runtime.marqueeTeardown?.();
    runtime.marqueeTeardown = null;
    runtime.placementTeardown?.();
    runtime.placementTeardown = null;
  }

  function destroy(): void {
    runtime.destroyed = true;
    setNodeDragTextSelectionDisabled(false);
    cleanupEventControllers();
    destroyHandlers();
    runtime.nodeMoveQueue = null;
    runtime.nodeUpdateQueue = null;
    runtime.area?.destroy();
  }

  onUnmounted(destroy);

  function setToolbarProps(props: Record<string, unknown>): void {
    if (hookProxy._flowContext) {
      hookProxy._flowContext.toolbarProps = props;
    }
  }

  async function performAutoLayout(): Promise<void> {
    await performFlowCanvasAutoLayout(runtime, {
      fitSequencesToChildren,
      flushPendingSequenceGeometry,
    });
  }

  return {
    editor,
    area,
    loading,
    toolbarState,
    init,
    addNodeToEditor,
    addConnectionToEditor,
    rebuildHubsMap,
    syncNodeSize,
    setToolbarProps,
    destroy,
  };
}
