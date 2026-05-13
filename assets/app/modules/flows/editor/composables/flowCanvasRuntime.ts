import type { NodeEditor } from "rete";
import type { AreaPlugin } from "rete-area-plugin";
import type { ConnectionPlugin } from "rete-connection-plugin";
import type { HistoryPlugin } from "rete-history-plugin";
import type { MinimapPlugin } from "rete-minimap-plugin";
import { reactive, ref, shallowRef, type Ref, type ShallowRef } from "vue";

import type { FlowNode } from "../lib/flow-node";
import type { FlowAreaExtra, FlowConnection, FlowSchemes } from "../lib/rete-schemes";
import type { DebugHandler } from "../services/debug";
import type {
  ConnectionServerPayload,
  EditorHandlers,
  FlowUpdatedPayload,
  HookProxy,
  NodeServerPayload,
} from "../services/editorHandlers";
import type { KeyboardHandler } from "../services/keyboard";
import type { LodController } from "../services/lod";
import type { NavigationHandler } from "../services/navigation";
import type { FlowCanvasOpts, SequenceGeometryPatch, ToolbarState } from "./flowCanvasTypes";

export interface FlowCanvasRuntimeCallbacks {
  addNodeToEditor(data: NodeServerPayload): Promise<FlowNode>;
  addConnectionToEditor(data: ConnectionServerPayload): Promise<FlowConnection | undefined>;
  rebuildHubsMap(): Promise<void>;
  syncNodeSize(nodeId: string): Promise<void>;
  syncAllNodeSizes(): Promise<void>;
  fitSequencesToChildren(): Promise<void>;
  loadFlow(data: FlowUpdatedPayload): Promise<void>;
  performAutoLayout(): Promise<void>;
}

export interface FlowCanvasRuntime {
  editorRef: ShallowRef<NodeEditor<FlowSchemes> | null>;
  areaRef: ShallowRef<AreaPlugin<FlowSchemes, FlowAreaExtra> | null>;
  loading: Ref<boolean>;
  toolbarState: ToolbarState;
  hookProxy: HookProxy;

  editor: NodeEditor<FlowSchemes> | null;
  area: AreaPlugin<FlowSchemes, FlowAreaExtra> | null;
  connection: ConnectionPlugin<FlowSchemes> | null;
  history: HistoryPlugin<FlowSchemes> | null;
  minimap: MinimapPlugin<FlowSchemes> | null;
  marqueeTeardown: (() => void) | null;
  placementTeardown: (() => void) | null;

  nodeMap: Map<string | number, FlowNode>;
  connectionDataMap: Map<string, { id: number; label: string | null; condition: unknown }>;
  pendingSequenceGeometry: Map<string, SequenceGeometryPatch>;
  loadingFromServerCount: number;
  deferSocketCalc: boolean;
  deferredSockets: unknown[];
  socketRenderedEvents: unknown[];
  isRecalculatingSockets: boolean;
  nodeMoveQueue: Promise<void> | null;
  nodeUpdateQueue: Promise<void> | null;

  editorHandlers: EditorHandlers | null;
  navigationHandler: NavigationHandler | null;
  debugHandler: DebugHandler | null;
  keyboardHandler: KeyboardHandler | null;
  lodController: LodController | null;

  selectedNodeId: string | number | null;
  lastNodeClickTime: number;
  lastClickedNodeId: string | number | null;
  destroyed: boolean;
  canvasClickController: AbortController | null;
  sequenceResizeController: AbortController | null;
  autoLayoutInProgress: boolean;
}

export function createFlowCanvasRuntime(
  { pushEvent, handleEvent }: FlowCanvasOpts,
  callbacks: FlowCanvasRuntimeCallbacks,
): FlowCanvasRuntime {
  const runtime: FlowCanvasRuntime = {
    editorRef: shallowRef<NodeEditor<FlowSchemes> | null>(null),
    areaRef: shallowRef<AreaPlugin<FlowSchemes, FlowAreaExtra> | null>(null),
    loading: ref(true),
    toolbarState: reactive<ToolbarState>({
      visible: false,
      nodeId: null,
      reteNodeId: null,
      nodeType: null,
      nodeData: null,
      x: 0,
      y: 0,
      width: 0,
      height: 0,
    }),
    hookProxy: null as unknown as HookProxy,

    editor: null,
    area: null,
    connection: null,
    history: null,
    minimap: null,
    marqueeTeardown: null,
    placementTeardown: null,

    nodeMap: new Map<string | number, FlowNode>(),
    connectionDataMap: new Map<string, { id: number; label: string | null; condition: unknown }>(),
    pendingSequenceGeometry: new Map<string, SequenceGeometryPatch>(),
    loadingFromServerCount: 0,
    deferSocketCalc: false,
    deferredSockets: [],
    socketRenderedEvents: [],
    isRecalculatingSockets: false,
    nodeMoveQueue: Promise.resolve(),
    nodeUpdateQueue: Promise.resolve(),

    editorHandlers: null,
    navigationHandler: null,
    debugHandler: null,
    keyboardHandler: null,
    lodController: null,

    selectedNodeId: null,
    lastNodeClickTime: 0,
    lastClickedNodeId: null,
    destroyed: false,
    canvasClickController: null,
    sequenceResizeController: null,
    autoLayoutInProgress: false,
  };

  const hookProxy: HookProxy = {
    get pushEvent() {
      return pushEvent;
    },
    get handleEvent() {
      return handleEvent;
    },
    get editor() {
      return runtime.editor!;
    },
    get area() {
      return runtime.area!;
    },
    get connection() {
      return runtime.connection;
    },
    get history() {
      return runtime.history;
    },
    get nodeMap() {
      return runtime.nodeMap;
    },
    get connectionDataMap() {
      return runtime.connectionDataMap;
    },
    get sheetsMap() {
      return hookProxy._sheetsMap || {};
    },
    get hubsMap() {
      return hookProxy._hubsMap || {};
    },
    get currentLod() {
      return runtime.lodController?.currentLod || "full";
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
      return runtime.selectedNodeId;
    },
    set selectedNodeId(value: string | number | null) {
      runtime.selectedNodeId = value;
    },
    get lastNodeClickTime() {
      return runtime.lastNodeClickTime;
    },
    set lastNodeClickTime(value: number) {
      runtime.lastNodeClickTime = value;
    },
    get lastClickedNodeId() {
      return runtime.lastClickedNodeId;
    },
    set lastClickedNodeId(value: string | number | null) {
      runtime.lastClickedNodeId = value;
    },
    get isLoadingFromServer() {
      return runtime.loadingFromServerCount > 0;
    },
    get _deferSocketCalc() {
      return runtime.deferSocketCalc;
    },
    get _deferredSockets() {
      return runtime.deferredSockets;
    },
    get _socketRenderedEvents() {
      return runtime.socketRenderedEvents;
    },
    set _socketRenderedEvents(value: unknown[]) {
      runtime.socketRenderedEvents = value;
    },
    get _isRecalculatingSockets() {
      return runtime.isRecalculatingSockets;
    },
    get el() {
      return hookProxy._containerEl;
    },
    enterLoadingFromServer() {
      runtime.loadingFromServerCount++;
    },
    exitLoadingFromServer() {
      runtime.loadingFromServerCount = Math.max(0, runtime.loadingFromServerCount - 1);
    },
    performAutoLayout: callbacks.performAutoLayout,
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
    addNodeToEditor: callbacks.addNodeToEditor,
    addConnectionToEditor: callbacks.addConnectionToEditor,
    rebuildHubsMap: callbacks.rebuildHubsMap,
    syncNodeSize: callbacks.syncNodeSize,
    syncAllNodeSizes: callbacks.syncAllNodeSizes,
    fitSequencesToChildren: callbacks.fitSequencesToChildren,
    loadFlow: callbacks.loadFlow,
  } as HookProxy;

  runtime.hookProxy = hookProxy;

  return runtime;
}
