/**
 * Composable managing the Rete.js flow canvas lifecycle.
 * Replaces the V1 FlowCanvas Phoenix hook -- Vue owns the editor.
 *
 * Handles: plugin setup, 3-phase node/connection loading, socket deferral,
 * node size sync, hub map rebuild, event bindings, auto-layout, and cleanup.
 */

import { ClassicPreset, type NodeEditor } from "rete";
import type { AreaPlugin } from "rete-area-plugin";
import type { HistoryPlugin } from "rete-history-plugin";
import type { ConnectionPlugin } from "rete-connection-plugin";
import type { AutoArrangePlugin } from "rete-auto-arrange-plugin";
import type { MinimapPlugin } from "rete-minimap-plugin";
import type { ScopesPlugin } from "rete-scopes-plugin";
import { onUnmounted, reactive, ref, shallowRef, type Ref, type ShallowRef } from "vue";

import { FlowNode } from "../lib/flow-node";
import type { NodeData } from "../lib/node-configs";
import type { FlowSchemes, FlowAreaExtra, FlowConnection } from "../lib/rete-schemes";
import { debug } from "../services/debug";
import { AutoLayoutAction, buildBatchPositions, type Position } from "../services/historyPreset";
import {
  editorHandlers,
  type EditorHandlers,
  type FlowContext,
  type HookProxy,
  type SheetMapEntry,
  type NodeMovedPayload,
  type NodeServerPayload,
  type NodeRemovedPayload,
  type NodeRestoredPayload,
  type NodeUpdatedPayload,
  type NodeDataChangedPayload,
  type FlowMetaChangedPayload,
  type ConnectionServerPayload,
  type ConnectionRemovedPayload,
  type ConnectionUpdatedPayload,
  type FlowUpdatedPayload,
} from "../services/editorHandlers";
import { keyboard, type KeyboardHandler } from "../services/keyboard";
import { lod, type LodController } from "../services/lod";
import { navigation, type NavigationHandler } from "../services/navigation";

import { createPlugins, finalizeSetup } from "../services/reteSetup";
import type {
  DebugHandler,
  DebugHighlightNodeData,
  DebugHighlightConnectionsData,
  DebugUpdateBreakpointsData,
} from "../services/debug";
import { createFlowMarquee } from "../services/flowMarquee";

interface FlowCanvasOpts {
  pushEvent: (event: string, payload: Record<string, unknown>) => void;
  handleEvent: (event: string, callback: (data: Record<string, unknown>) => void) => void;
}

interface ToolbarState {
  visible: boolean;
  nodeId: string | number | null;
  reteNodeId: string | null;
  nodeType: string | null;
  nodeData: NodeData | null;
  x: number;
  y: number;
  width: number;
  height: number;
}

interface InitOpts {
  sheetsMap?: Record<string, SheetMapEntry>;
  readonly?: boolean;
  userId?: number;
  userColor?: string;
}

interface FlowData {
  nodes?: {
    type: string;
    id: string | number;
    data: NodeData;
    position?: { x: number; y: number };
    parent_id?: number | null;
  }[];
  connections?: {
    id: number;
    source_node_id: string | number;
    target_node_id: string | number;
    source_pin: string;
    target_pin: string;
    label?: string;
    condition?: unknown;
  }[];
}

interface ConnectionData {
  id: number;
  source_node_id: string | number;
  target_node_id: string | number;
  source_pin: string;
  target_pin: string;
  label?: string;
  condition?: unknown;
}

interface NodeServerData {
  type: string;
  id: string | number;
  data: NodeData;
  position?: { x: number; y: number };
  parent_id?: number | null;
}

export interface FlowCanvasReturn {
  editor: ShallowRef<NodeEditor<FlowSchemes> | null>;
  area: ShallowRef<AreaPlugin<FlowSchemes, FlowAreaExtra> | null>;
  loading: Ref<boolean>;
  toolbarState: ToolbarState;
  init(containerEl: HTMLElement, flowData: FlowData, opts?: InitOpts): Promise<void>;
  addNodeToEditor(nodeData: NodeServerData): Promise<FlowNode>;
  addConnectionToEditor(connData: ConnectionData): Promise<FlowConnection | undefined>;
  rebuildHubsMap(): Promise<void>;
  syncNodeSize(nodeId: string): Promise<void>;
  destroy(): void;
  setToolbarProps(props: Record<string, unknown>): void;
}

export function useFlowCanvas({ pushEvent, handleEvent }: FlowCanvasOpts): FlowCanvasReturn {
  const editor = shallowRef<NodeEditor<FlowSchemes> | null>(null);
  const area = shallowRef<AreaPlugin<FlowSchemes, FlowAreaExtra> | null>(null);
  const loading = ref(true);

  // Reactive toolbar positioning -- updated on node pick, drag, zoom, pan
  const toolbarState: ToolbarState = reactive({
    visible: false,
    nodeId: null,
    reteNodeId: null,
    nodeType: null,
    nodeData: null,
    x: 0,
    y: 0,
    width: 0,
    height: 0,
  });

  // Internal state (not reactive -- performance-critical)
  let _editor: NodeEditor<FlowSchemes> | null = null;
  let _area: AreaPlugin<FlowSchemes, FlowAreaExtra> | null = null;
  let _connection: ConnectionPlugin<FlowSchemes> | null = null;
  let _history: HistoryPlugin<FlowSchemes> | null = null;
  let _arrange: AutoArrangePlugin<FlowSchemes> | null = null;
  let _minimap: MinimapPlugin<FlowSchemes> | null = null;
  let _scopes: ScopesPlugin<FlowSchemes> | null = null;
  let _marqueeTeardown: (() => void) | null = null;

  const _nodeMap = new Map<string | number, FlowNode>();
  const _connectionDataMap = new Map<
    string,
    { id: number; label: string | null; condition: unknown }
  >();
  let _loadingFromServerCount = 0;
  let _deferSocketCalc = false;
  let _deferredSockets: unknown[] = [];
  let _socketRenderedEvents: unknown[] = [];
  let _isRecalculatingSockets = false;
  let _nodeMoveQueue: Promise<void> | null = Promise.resolve();
  let _nodeUpdateQueue: Promise<void> | null = Promise.resolve();

  let _editorHandlers: EditorHandlers | null = null;
  let _navigationHandler: NavigationHandler | null = null;
  let _debugHandler: DebugHandler | null = null;
  let _keyboardHandler: KeyboardHandler | null = null;
  let _lodController: LodController | null = null;

  let _selectedNodeId: string | number | null = null;
  let _lastNodeClickTime = 0;
  let _lastClickedNodeId: string | number | null = null;
  let _destroyed = false;
  let _canvasClickController: AbortController | null = null;
  let _autoLayoutInProgress = false;

  // Expose as a "hook-like" object for handler modules that expect `hook.pushEvent`, etc.
  const hookProxy: HookProxy = {
    get pushEvent() {
      return pushEvent;
    },
    get handleEvent() {
      return handleEvent;
    },
    get editor() {
      return _editor!;
    },
    get area() {
      return _area!;
    },
    get connection() {
      return _connection;
    },
    get history() {
      return _history;
    },
    get arrange() {
      return _arrange;
    },
    get scopes() {
      return _scopes!;
    },
    get nodeMap() {
      return _nodeMap;
    },
    get connectionDataMap() {
      return _connectionDataMap;
    },
    get sheetsMap() {
      return hookProxy._sheetsMap || {};
    },
    get hubsMap() {
      return hookProxy._hubsMap || {};
    },
    get currentLod() {
      return _lodController?.currentLod || "full";
    },
    get readonly() {
      return hookProxy._readonly || false;
    },
    get currentUserId() {
      return hookProxy._currentUserId || 0;
    },
    get currentUserColor() {
      return hookProxy._currentUserColor || "#3b82f6";
    },
    get selectedNodeId() {
      return _selectedNodeId;
    },
    set selectedNodeId(v: string | number | null) {
      _selectedNodeId = v;
    },
    get lastNodeClickTime() {
      return _lastNodeClickTime;
    },
    set lastNodeClickTime(v: number) {
      _lastNodeClickTime = v;
    },
    get lastClickedNodeId() {
      return _lastClickedNodeId;
    },
    set lastClickedNodeId(v: string | number | null) {
      _lastClickedNodeId = v;
    },
    get isLoadingFromServer() {
      return _loadingFromServerCount > 0;
    },
    get _deferSocketCalc() {
      return _deferSocketCalc;
    },
    get _deferredSockets() {
      return _deferredSockets;
    },
    get _socketRenderedEvents() {
      return _socketRenderedEvents;
    },
    set _socketRenderedEvents(v: unknown[]) {
      _socketRenderedEvents = v;
    },
    get _isRecalculatingSockets() {
      return _isRecalculatingSockets;
    },
    // el proxy -- handlers use hook.el for DOM queries
    get el() {
      return hookProxy._containerEl;
    },
    // Expose enterLoadingFromServer/exitLoadingFromServer
    enterLoadingFromServer() {
      _loadingFromServerCount++;
    },
    exitLoadingFromServer() {
      _loadingFromServerCount = Math.max(0, _loadingFromServerCount - 1);
    },
    performAutoLayout() {
      return performAutoLayout();
    },
    // Internal refs for handlers
    _sheetsMap: {},
    _hubsMap: {},
    _readonly: false,
    _currentUserId: 0,
    _currentUserColor: "#3b82f6",
    _containerEl: null,
    _inlineEditingNodeId: null,
    _speakerPopover: null,
    _eventBindingsController: null,
    editorHandlers: null,
    navigationHandler: null,
    debugHandler: null,
    keyboardHandler: null,
    lodController: null,
    addNodeToEditor,
    addConnectionToEditor,
    rebuildHubsMap,
    syncNodeSize,
    syncAllNodeSizes,
    loadFlow: loadInitialFlowData,
  } as HookProxy;

  // --- Toolbar positioning ---

  function selectNodeForToolbar(reteNodeId: string): void {
    const node = _editor!.getNode(reteNodeId);
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
    const node = _editor!.getNode(reteNodeId);
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
    const nodeView = _area?.nodeViews.get(editingId);
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
    const node = _editor!.getNode(reteNodeId);
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
      _area!.update("node", node.id);
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
    _editorHandlers = editorHandlers(hookProxy);
    _navigationHandler = navigation(_area!, _nodeMap, pushEvent);
    _debugHandler = debug(hookProxy.area, hookProxy.editor, _nodeMap, undefined);

    hookProxy.editorHandlers = _editorHandlers;
    hookProxy.navigationHandler = _navigationHandler;
    hookProxy.debugHandler = _debugHandler;

    _editorHandlers.init();
  }

  function initPlugins(containerEl: HTMLElement): void {
    const plugins = createPlugins(containerEl, hookProxy);
    _editor = plugins.editor;
    _area = plugins.area;
    _connection = plugins.connection;
    _history = plugins.history;
    _arrange = plugins.arrange;
    _minimap = plugins.minimap;
    _scopes = plugins.scopes;

    editor.value = _editor;
    area.value = _area;
  }

  function setupCanvasClickHandler(containerEl: HTMLElement): void {
    _canvasClickController = new AbortController();
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
          _selectedNodeId = null;
        }
      },
      { signal: _canvasClickController.signal },
    );
  }

  async function loadInitialFlowData(flowData: FlowData): Promise<void> {
    hookProxy._hubsMap = {};
    if (!flowData.nodes) {
      return;
    }

    _deferSocketCalc = true;
    _loadingFromServerCount++;

    // rete-scopes-plugin requires parents to exist before their children
    // reference them via `parent`. Sort nodes so ancestors load first.
    const sorted = sortNodesByParentDepth(flowData.nodes);

    for (const nodeData of sorted) {
      await addNodeToEditor(nodeData);
    }

    _deferSocketCalc = false;
    await flushDeferredSockets();

    for (const connData of flowData.connections || []) {
      await addConnectionToEditor(connData);
    }

    _loadingFromServerCount = Math.max(0, _loadingFromServerCount - 1);
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
    _lodController = lod(_area!, hookProxy);
    hookProxy.lodController = _lodController;

    _area!.addPipe((context) => {
      if ((context as { type: string }).type === "zoomed") {
        _lodController!.onZoom();
        const k = _area!.area.transform.k;
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
    _keyboardHandler = keyboard(hookProxy, null);
    _keyboardHandler.init();
    hookProxy.keyboardHandler = _keyboardHandler;
  }

  function activatePostLoadPlugins(): void {
    if (_history && !hookProxy._readonly) {
      _area!.use(_history);
    }
    if (_minimap) {
      _area!.use(_minimap);
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
    const selection = await finalizeSetup(
      _area!,
      _editor!,
      (flowData.nodes?.length ?? 0) > 0,
      hookProxy._flowContext,
    );
    await recalculateAllSockets();

    // Marquee selection (drag-rectangle). Only active while the dock's tool
    // is in "select" mode — the composable watches `activeFlowTool` internally.
    if (!hookProxy._readonly && hookProxy._containerEl) {
      _marqueeTeardown = createFlowMarquee({
        containerEl: hookProxy._containerEl,
        area: _area!,
        editor: _editor!,
        selection,
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
    setupLOD(containerEl);

    await loadInitialFlowData(flowData);
    activatePostLoadPlugins();

    setupAreaPipes();
    setupServerEvents();
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

    await _editor!.addNode(node);

    const x = nodeData.position?.x || 0;
    const y = nodeData.position?.y || 0;

    if (_deferSocketCalc) {
      const view = _area!.nodeViews.get(node.id);
      if (view) {
        view.translate(x, y);
      }
    } else {
      await _area!.translate(node.id, { x, y });
    }

    // Sequences render via `Sequence.vue`, which deliberately does NOT bind
    // `:style="{ width, height }"` (see the comment in that file). Width
    // and height live as inline DOM styles written by
    // `rete-area-plugin`'s `area.resize`. The plugin calls `area.resize`
    // only from `resizeParent` — triggered by a child's `nodetranslated`
    // / `noderemoved` / `scopeupdated`. For an empty sequence on initial
    // load (or for one that just lost its last child via reparent), there
    // is no child to trigger it, so the Sequence div collapses to the
    // header's intrinsic size. Kickstart the resize here with the
    // FlowNode's own width/height (seeded from `data.width/height` in the
    // constructor) so the bbox shows up correctly before any interaction.
    if (node.nodeType === "sequence") {
      await _area!.resize(node.id, node.width, node.height);
    }

    _nodeMap.set(nodeData.id, node);
    return node;
  }

  async function addConnectionToEditor(
    connData: ConnectionData,
  ): Promise<FlowConnection | undefined> {
    const sourceNode = _nodeMap.get(connData.source_node_id);
    const targetNode = _nodeMap.get(connData.target_node_id);
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

    _connectionDataMap.set(connection.id, {
      id: connData.id,
      label: connData.label || null,
      condition: connData.condition,
    });

    await _editor!.addConnection(connection);
    return connection;
  }

  // --- Socket management ---

  async function flushDeferredSockets(): Promise<void> {
    const deferred = _deferredSockets;
    _deferredSockets = [];
    await new Promise((r) => requestAnimationFrame(r));
    for (const ctx of deferred) {
      await _area!.emit(ctx as FlowAreaExtra);
    }
  }

  async function recalculateAllSockets(): Promise<void> {
    const events = _socketRenderedEvents;
    if (!events || events.length === 0) {
      return;
    }
    _socketRenderedEvents = [];
    _isRecalculatingSockets = true;
    await new Promise((r) => requestAnimationFrame(r));
    for (const ctx of events) {
      await _area!.emit(ctx as FlowAreaExtra);
    }
    _isRecalculatingSockets = false;
  }

  // --- Node size sync (Vue DOM, no shadow DOM) ---

  async function syncNodeSize(nodeId: string): Promise<void> {
    const view = _area!.nodeViews.get(nodeId);
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
      const node = _editor!.getNode(nodeId);
      if (node) {
        node.width = w;
        node.height = h;
      }
      await _area!.resize(nodeId, w, h);
    }
  }

  async function syncAllNodeSizes(): Promise<void> {
    await new Promise((r) => requestAnimationFrame(r));
    for (const [nodeId] of _area!.nodeViews) {
      await syncNodeSize(nodeId);
    }
  }

  // --- Hub map ---

  function buildHubMap(): Record<
    string,
    { color_hex: string | null; label: string; jumpCount: number }
  > {
    const map: Record<string, { color_hex: string | null; label: string; jumpCount: number }> = {};
    for (const [, node] of _nodeMap) {
      if (node.nodeType === "hub" && node.nodeData?.hub_id) {
        map[node.nodeData.hub_id as string] = {
          color_hex: (node.nodeData.color_hex as string) || null,
          label: (node.nodeData.label as string) || "",
          jumpCount: 0,
        };
      }
    }
    return map;
  }

  function countHubJumps(
    map: Record<string, { color_hex: string | null; label: string; jumpCount: number }>,
  ): void {
    for (const [, node] of _nodeMap) {
      if (node.nodeType === "jump" && node.nodeData?.target_hub_id) {
        const entry = map[node.nodeData.target_hub_id as string];
        if (entry) {
          entry.jumpCount++;
        }
      }
    }
  }

  async function updateHubAndJumpNodes(): Promise<void> {
    const ts = Date.now();
    for (const [, node] of _nodeMap) {
      if (node.nodeType === "hub" || node.nodeType === "jump") {
        node._updateTs = ts;
        await _area!.update("node", node.id);
      }
    }
  }

  async function rebuildHubsMap(): Promise<void> {
    const map = buildHubMap();
    countHubJumps(map);
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

  function handleNodeTranslated(context: unknown): void {
    if (hookProxy.isLoadingFromServer) {
      return;
    }
    const ctxData = (context as { data: { id: string; position: { x: number; y: number } } }).data;
    const node = _editor!.getNode(ctxData.id);
    if (node?.nodeId) {
      _editorHandlers!.throttleNodeMoved(node.nodeId, ctxData.position);
    }
  }

  function handleNodeDragged(context: unknown): void {
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
      // Keys are string-numeric; convert back to the raw type flushNodeMoved expects.
      const numeric = Number(nodeId);
      _editorHandlers!.flushNodeMoved(Number.isFinite(numeric) ? numeric : nodeId);
    }
    // Fallback for the grabbed node, in case it had no pending (edge case).
    const node = _editor!.getNode((context as { data: { id: string } }).data.id);
    if (node?.nodeId && !nodeIds.includes(String(node.nodeId))) {
      _editorHandlers!.flushNodeMoved(node.nodeId);
    }
  }

  // --- Area pipes (drag, selection, connections) ---

  function setupAreaPipes(): void {
    if (hookProxy._readonly) {
      _area!.addPipe((context) => {
        if ((context as { type: string }).type === "nodepicked") {
          const node = _editor!.getNode((context as { data: { id: string } }).data.id);
          if (node?.nodeId) {
            _selectedNodeId = node.nodeId;
            pushEvent("node_selected", { id: node.nodeId });
          }
        }
        return context;
      });
      return;
    }

    // Node drag + toolbar reposition
    _area!.addPipe((context) => {
      const type = (context as { type: string }).type;
      if (type === "nodetranslated") {
        handleNodeTranslated(context);
      } else if (type === "nodedragged") {
        handleNodeDragged(context);
      }
      return context;
    });

    // Node selection + double-click
    _area!.addPipe((context) => {
      if ((context as { type: string }).type === "nodepicked") {
        const nodeId = (context as { data: { id: string } }).data.id;
        const node = _editor!.getNode(nodeId);
        if (node?.nodeId) {
          const now = Date.now();
          const isDoubleClick =
            _lastClickedNodeId === node.nodeId && now - _lastNodeClickTime < 300;

          _lastNodeClickTime = now;
          _lastClickedNodeId = node.nodeId;
          _selectedNodeId = node.nodeId;

          if (isDoubleClick) {
            const reteNode = _editor!.getNode(nodeId);
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
    _editor!.addPipe((context) => {
      if (
        (context as { type: string }).type === "connectioncreate" &&
        !hookProxy.isLoadingFromServer
      ) {
        const conn = (
          context as {
            data: { source: string; sourceOutput: string; target: string; targetInput: string };
          }
        ).data;
        const sourceNode = _editor!.getNode(conn.source);
        const targetNode = _editor!.getNode(conn.target);

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
    _editor!.addPipe((context) => {
      if (
        (context as { type: string }).type === "connectionremove" &&
        !hookProxy.isLoadingFromServer
      ) {
        const conn = (context as { data: { source: string; target: string } }).data;
        const sourceNode = _editor!.getNode(conn.source);
        const targetNode = _editor!.getNode(conn.target);

        if (sourceNode?.nodeId && targetNode?.nodeId) {
          pushEvent("connection_deleted", {
            source_node_id: sourceNode.nodeId,
            target_node_id: targetNode.nodeId,
          });
        }
      }
      return context;
    });
  }

  // --- Server event handlers ---

  function setupServerEvents(): void {
    if (!_editorHandlers) {
      return;
    }

    handleEvent("flow_updated", (data) =>
      _editorHandlers!.handleFlowUpdated(data as FlowUpdatedPayload),
    );

    _nodeMoveQueue = Promise.resolve();
    handleEvent("node_moved", (raw) => {
      if (!_nodeMoveQueue) {
        return;
      }
      const data = raw as unknown as NodeMovedPayload;
      _nodeMoveQueue = _nodeMoveQueue
        .then(() => {
          if (!_area || _destroyed) {
            return;
          }
          return _editorHandlers!.handleNodeMoved(data);
        })
        .catch(() => {});
    });

    handleEvent("node_reparented", (raw) => {
      if (_destroyed) {
        return;
      }
      const payload = raw as unknown as {
        node_id: string | number;
        parent_id: string | number | null;
      };
      _editorHandlers!.handleNodeReparented(payload);
    });

    handleEvent("sequence_renamed", (raw) => {
      if (_destroyed) {
        return;
      }
      const payload = raw as unknown as { node_id: string | number; name: string };
      _editorHandlers!.handleSequenceRenamed(payload);
    });

    handleEvent("node_added", (data) => {
      if (_destroyed) {
        return;
      }
      _editorHandlers!.handleNodeAdded(data as unknown as NodeServerPayload);
    });
    handleEvent("node_removed", (data) => {
      if (_destroyed) {
        return;
      }
      _editorHandlers!.handleNodeRemoved(data as unknown as NodeRemovedPayload);
    });
    handleEvent("node_restored", (data) => {
      if (_destroyed) {
        return;
      }
      _editorHandlers!.handleNodeRestored(data as unknown as NodeRestoredPayload);
    });

    _nodeUpdateQueue = Promise.resolve();
    handleEvent("node_updated", (raw) => {
      if (!_nodeUpdateQueue) {
        return;
      }
      const data = raw as unknown as NodeUpdatedPayload;
      _nodeUpdateQueue = _nodeUpdateQueue
        .then(async () => {
          if (!_area || _destroyed) {
            return;
          }
          await _editorHandlers!.handleNodeUpdated(data);
          // Sync toolbar if the updated node is the one selected
          if (toolbarState.nodeId && String(data.id) === String(toolbarState.nodeId)) {
            const reteNode = _nodeMap.get(data.id);
            if (reteNode) {
              toolbarState.nodeData = { ...reteNode.nodeData };
            }
          }
        })
        .catch(() => {});
    });

    handleEvent("node_data_changed", (data) =>
      _editorHandlers!.handleNodeDataChanged(data as unknown as NodeDataChangedPayload),
    );
    handleEvent("flow_meta_changed", (data) =>
      _editorHandlers!.handleFlowMetaChanged(data as unknown as FlowMetaChangedPayload),
    );
    handleEvent("connection_added", (data) =>
      _editorHandlers!.handleConnectionAdded(data as unknown as ConnectionServerPayload),
    );
    handleEvent("connection_removed", (data) =>
      _editorHandlers!.handleConnectionRemoved(data as unknown as ConnectionRemovedPayload),
    );
    handleEvent("connection_updated", (data) =>
      _editorHandlers!.handleConnectionUpdated(data as unknown as ConnectionUpdatedPayload),
    );

    if (_navigationHandler) {
      handleEvent("navigate_to_hub", (data) =>
        _navigationHandler!.navigateToHub(data.jump_db_id as number),
      );
      handleEvent("navigate_to_node", (data) =>
        _navigationHandler!.navigateToNode(data.node_db_id as number),
      );
      handleEvent("navigate_to_jumps", (data) =>
        _navigationHandler!.navigateToJumps(data.hub_db_id as number),
      );
    }

    if (_debugHandler) {
      handleEvent("debug_highlight_node", (data) =>
        _debugHandler!.handleHighlightNode(data as unknown as DebugHighlightNodeData),
      );
      handleEvent("debug_highlight_connections", (data) =>
        _debugHandler!.handleHighlightConnections(data as unknown as DebugHighlightConnectionsData),
      );
      handleEvent("debug_update_breakpoints", (data) =>
        _debugHandler!.handleUpdateBreakpoints(data as unknown as DebugUpdateBreakpointsData),
      );
      handleEvent("debug_clear_highlights", () => _debugHandler!.handleClearHighlights());
    }
  }

  // --- Cleanup ---

  function destroy(): void {
    _destroyed = true;
    _canvasClickController?.abort();
    hookProxy._eventBindingsController?.abort();
    _lodController?.destroy();
    _keyboardHandler?.destroy();
    _editorHandlers?.destroy();
    _navigationHandler?.destroy();
    _debugHandler?.destroy();
    _marqueeTeardown?.();
    _marqueeTeardown = null;
    _nodeMoveQueue = null;
    _nodeUpdateQueue = null;
    if (_area) {
      _area.destroy();
    }
  }

  onUnmounted(destroy);

  function setToolbarProps(props: Record<string, unknown>): void {
    if (hookProxy._flowContext) {
      hookProxy._flowContext.toolbarProps = props;
    }
  }

  // --- Auto-layout (client-side via rete-auto-arrange-plugin + elkjs) ---

  function snapshotPositions(): Map<string, Position> {
    const map = new Map<string, Position>();
    if (!_editor || !_area) {
      return map;
    }
    for (const node of _editor.getNodes()) {
      const view = _area.nodeViews.get(node.id);
      if (view) {
        map.set(node.id, { x: view.position.x, y: view.position.y });
      }
    }
    return map;
  }

  async function performAutoLayout(): Promise<void> {
    if (_autoLayoutInProgress) return;
    if (!_arrange || !_area || !_editor) return;
    _autoLayoutInProgress = true;
    try {
      const { ArrangeAppliers } = await import("rete-auto-arrange-plugin");
      const { AreaExtensions } = await import("rete-area-plugin");

      const prevPositions = snapshotPositions();

      const applier = new ArrangeAppliers.TransitionApplier<FlowSchemes, never>({
        duration: 400,
        timingFunction: (t: number) => t * (2 - t),
      });

      _loadingFromServerCount++;
      try {
        await _arrange.layout({
          applier,
          options: {
            "elk.algorithm": "layered",
            "elk.direction": "RIGHT",
            "elk.spacing.nodeNode": "60",
            "elk.layered.spacing.nodeNodeBetweenLayers": "120",
          },
        });
      } finally {
        _loadingFromServerCount = Math.max(0, _loadingFromServerCount - 1);
      }

      await AreaExtensions.zoomAt(_area, _editor.getNodes());

      const newPositions = snapshotPositions();
      pushEvent("batch_update_positions", {
        positions: buildBatchPositions(newPositions),
      });

      if (_history) {
        _history.add(new AutoLayoutAction(hookProxy, _area, prevPositions, newPositions));
      }
    } catch (error) {
      // biome-ignore lint/suspicious/noConsole: error feedback for unlikely ELK layout failure
      console.error("Auto-layout failed:", error);
    } finally {
      _autoLayoutInProgress = false;
    }
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
