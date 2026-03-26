/**
 * Composable managing the Rete.js flow editor lifecycle.
 * Replaces the V1 FlowCanvas Phoenix hook — Vue owns the editor.
 *
 * Handles: plugin setup, 3-phase node/connection loading, socket deferral,
 * node size sync, hub map rebuild, event bindings, auto-layout, and cleanup.
 */

import { onUnmounted, ref, shallowRef } from "vue";
import { ClassicPreset } from "rete";
import { AreaExtensions } from "rete-area-plugin";

import { FlowNode } from "@/js/flow_canvas/flow_node.js";
import {
	createCursorHandler,
	createDebugHandler,
	createEditorHandlers,
	createKeyboardHandler,
	createLockHandler,
	createNavigationHandler,
} from "@/js/flow_canvas/handlers/index.js";
import { buildBatchPositions } from "@/js/flow_canvas/history_preset.js";
import { createLodController } from "@/js/flow_canvas/lod_controller.js";
import { createMinimapToggle } from "@/js/flow_canvas/minimap_toggle.js";

import { createPlugins, finalizeSetup } from "../setup.js";

/**
 * @param {Object} opts
 * @param {Function} opts.pushEvent - useLive().pushEvent
 * @param {Function} opts.handleEvent - useLive().handleEvent
 */
export function useFlowEditor({ pushEvent, handleEvent }) {
	const editor = shallowRef(null);
	const area = shallowRef(null);
	const loading = ref(true);

	// Internal state (not reactive — performance-critical)
	let _editor = null;
	let _area = null;
	let _connection = null;
	let _history = null;
	let _arrange = null;
	let _minimap = null;
	let _render = null;

	let _nodeMap = new Map();
	let _connectionDataMap = new Map();
	let _loadingFromServerCount = 0;
	let _deferSocketCalc = false;
	let _deferredSockets = [];
	let _socketRenderedEvents = [];
	let _isRecalculatingSockets = false;
	let _nodeMoveQueue = Promise.resolve();
	let _nodeUpdateQueue = Promise.resolve();

	let _editorHandlers = null;
	let _cursorHandler = null;
	let _lockHandler = null;
	let _navigationHandler = null;
	let _debugHandler = null;
	let _keyboardHandler = null;
	let _lodController = null;
	let _minimapToggle = null;

	let _selectedNodeId = null;
	let _lastNodeClickTime = 0;
	let _lastClickedNodeId = null;
	let _destroyed = false;

	// Expose as a "hook-like" object for handler modules that expect `hook.pushEvent`, etc.
	const hookProxy = {
		get pushEvent() { return pushEvent; },
		get handleEvent() { return handleEvent; },
		get editor() { return _editor; },
		get area() { return _area; },
		get connection() { return _connection; },
		get history() { return _history; },
		get arrange() { return _arrange; },
		get nodeMap() { return _nodeMap; },
		get connectionDataMap() { return _connectionDataMap; },
		get sheetsMap() { return hookProxy._sheetsMap || {}; },
		get hubsMap() { return hookProxy._hubsMap || {}; },
		get labels() { return hookProxy._labels || {}; },
		get currentLod() { return _lodController?.currentLod || "full"; },
		get readonly() { return hookProxy._readonly || false; },
		get currentUserId() { return hookProxy._currentUserId || 0; },
		get currentUserColor() { return hookProxy._currentUserColor || "#3b82f6"; },
		get selectedNodeId() { return _selectedNodeId; },
		set selectedNodeId(v) { _selectedNodeId = v; },
		get lastNodeClickTime() { return _lastNodeClickTime; },
		set lastNodeClickTime(v) { _lastNodeClickTime = v; },
		get lastClickedNodeId() { return _lastClickedNodeId; },
		set lastClickedNodeId(v) { _lastClickedNodeId = v; },
		get isLoadingFromServer() { return _loadingFromServerCount > 0; },
		get _deferSocketCalc() { return _deferSocketCalc; },
		get _deferredSockets() { return _deferredSockets; },
		get _socketRenderedEvents() { return _socketRenderedEvents; },
		set _socketRenderedEvents(v) { _socketRenderedEvents = v; },
		get _isRecalculatingSockets() { return _isRecalculatingSockets; },
		// el proxy — handlers use hook.el for DOM queries
		get el() { return hookProxy._containerEl; },
		// Expose enterLoadingFromServer/exitLoadingFromServer
		enterLoadingFromServer() { _loadingFromServerCount++; },
		exitLoadingFromServer() { _loadingFromServerCount = Math.max(0, _loadingFromServerCount - 1); },
		// Internal refs for handlers
		_sheetsMap: {},
		_hubsMap: {},
		_labels: {},
		_readonly: false,
		_currentUserId: 0,
		_currentUserColor: "#3b82f6",
		_containerEl: null,
		_inlineEditingNodeId: null,
		_speakerPopover: null,
		_eventBindingsController: null,
		editorHandlers: null,
		cursorHandler: null,
		lockHandler: null,
		navigationHandler: null,
		debugHandler: null,
		keyboardHandler: null,
		floatingToolbar: null,
		lodController: null,
		minimapToggle: null,
	};

	// --- Init ---

	async function init(containerEl, flowData, opts = {}) {
		hookProxy._containerEl = containerEl;
		hookProxy._sheetsMap = opts.sheetsMap || {};
		hookProxy._labels = opts.labels || {};
		hookProxy._readonly = opts.readonly || false;
		hookProxy._currentUserId = opts.userId || 0;
		hookProxy._currentUserColor = opts.userColor || "#3b82f6";

		// Create handlers (skip collab/mutation in readonly)
		if (!hookProxy._readonly) {
			_editorHandlers = createEditorHandlers(hookProxy);
			_cursorHandler = createCursorHandler(hookProxy);
			_lockHandler = createLockHandler(hookProxy);
			_navigationHandler = createNavigationHandler(hookProxy);
			_debugHandler = createDebugHandler(hookProxy);

			hookProxy.editorHandlers = _editorHandlers;
			hookProxy.cursorHandler = _cursorHandler;
			hookProxy.lockHandler = _lockHandler;
			hookProxy.navigationHandler = _navigationHandler;
			hookProxy.debugHandler = _debugHandler;

			_cursorHandler.init();
			_lockHandler.init();
			_editorHandlers.init();
		}

		// Create plugins
		const plugins = createPlugins(containerEl, hookProxy);
		_editor = plugins.editor;
		_area = plugins.area;
		_connection = plugins.connection;
		_history = plugins.history;
		_arrange = plugins.arrange;
		_minimap = plugins.minimap;
		_render = plugins.render;

		editor.value = _editor;
		area.value = _area;

		// Sync shared reactive context with initial data
		syncFlowContext();

		// LOD
		const nodeCount = flowData.nodes?.length || 0;
		const initialLod = nodeCount >= 50 ? "simplified" : "full";
		_lodController = createLodController(hookProxy, initialLod);
		hookProxy.lodController = _lodController;

		// 3-phase load
		hookProxy._hubsMap = {};
		if (flowData.nodes) {
			_deferSocketCalc = true;
			_loadingFromServerCount++;

			for (const nodeData of flowData.nodes) {
				await addNodeToEditor(nodeData);
			}

			_deferSocketCalc = false;
			await flushDeferredSockets();

			for (const connData of flowData.connections || []) {
				await addConnectionToEditor(connData);
			}

			_loadingFromServerCount = Math.max(0, _loadingFromServerCount - 1);
		}

		// History + minimap after load
		if (_history && !hookProxy._readonly) {
			_area.use(_history);
		}
		if (_minimap) {
			_area.use(_minimap);
		}

		_minimapToggle = createMinimapToggle(hookProxy);
		_minimapToggle.init();
		hookProxy.minimapToggle = _minimapToggle;

		// Event bindings
		setupAreaPipes();
		setupServerEvents();

		// LOD zoom watcher
		_area.addPipe((context) => {
			if (context.type === "zoomed") {
				_lodController.onZoom();
				const k = _area.area.transform.k;
				containerEl.style.setProperty("--canvas-zoom", k);
			}
			return context;
		});

		// Keyboard
		if (!hookProxy._readonly) {
			_keyboardHandler = createKeyboardHandler(hookProxy, _lockHandler);
			_keyboardHandler.init();
			hookProxy.keyboardHandler = _keyboardHandler;
		}

		// Sync sizes + finalize
		await syncAllNodeSizes();
		await finalizeSetup(_area, _editor, flowData.nodes?.length > 0);
		await recalculateAllSockets();

		if (flowData.nodes?.length > 0) {
			await rebuildHubsMap();
		}

		loading.value = false;
	}

	// --- Node/Connection CRUD ---

	async function addNodeToEditor(nodeData) {
		const node = new FlowNode(nodeData.type, nodeData.id, nodeData.data);
		node.id = `node-${nodeData.id}`;

		await _editor.addNode(node);

		const x = nodeData.position?.x || 0;
		const y = nodeData.position?.y || 0;

		if (_deferSocketCalc) {
			const view = _area.nodeViews.get(node.id);
			if (view) view.translate(x, y);
		} else {
			await _area.translate(node.id, { x, y });
		}

		_nodeMap.set(nodeData.id, node);
		return node;
	}

	async function addConnectionToEditor(connData) {
		const sourceNode = _nodeMap.get(connData.source_node_id);
		const targetNode = _nodeMap.get(connData.target_node_id);
		if (!sourceNode || !targetNode) return;

		if (!sourceNode.outputs[connData.source_pin]) return;
		if (!targetNode.inputs[connData.target_pin]) return;

		const connection = new ClassicPreset.Connection(
			sourceNode,
			connData.source_pin,
			targetNode,
			connData.target_pin,
		);
		connection.id = `conn-${connData.id}`;

		_connectionDataMap.set(connection.id, {
			id: connData.id,
			label: connData.label,
			condition: connData.condition,
		});

		await _editor.addConnection(connection);
		return connection;
	}

	// --- Socket management ---

	async function flushDeferredSockets() {
		const deferred = _deferredSockets;
		_deferredSockets = [];
		await new Promise((r) => requestAnimationFrame(r));
		for (const ctx of deferred) {
			await _area.emit(ctx);
		}
	}

	async function recalculateAllSockets() {
		const events = _socketRenderedEvents;
		if (!events || events.length === 0) return;
		_socketRenderedEvents = [];
		_isRecalculatingSockets = true;
		await new Promise((r) => requestAnimationFrame(r));
		for (const ctx of events) {
			await _area.emit(ctx);
		}
		_isRecalculatingSockets = false;
	}

	// --- Node size sync (Vue DOM, no shadow DOM) ---

	async function syncNodeSize(nodeId) {
		const view = _area.nodeViews.get(nodeId);
		if (!view) return;
		const nodeEl = view.element.querySelector("[data-testid='node']");
		if (!nodeEl) return;

		await new Promise((r) => requestAnimationFrame(r));
		const w = nodeEl.offsetWidth;
		const h = nodeEl.offsetHeight;
		if (w > 0 && h > 0) {
			const node = _editor.getNode(nodeId);
			if (node) {
				node.width = w;
				node.height = h;
			}
			await _area.resize(nodeId, w, h);
		}
	}

	async function syncAllNodeSizes() {
		await new Promise((r) => requestAnimationFrame(r));
		for (const [nodeId] of _area.nodeViews) {
			await syncNodeSize(nodeId);
		}
	}

	// --- Hub map ---

	async function rebuildHubsMap() {
		const map = {};
		for (const [, node] of _nodeMap) {
			if (node.nodeType === "hub" && node.nodeData?.hub_id) {
				map[node.nodeData.hub_id] = {
					color_hex: node.nodeData.color_hex || null,
					label: node.nodeData.label || "",
					jumpCount: 0,
				};
			}
		}
		for (const [, node] of _nodeMap) {
			if (node.nodeType === "jump" && node.nodeData?.target_hub_id) {
				const entry = map[node.nodeData.target_hub_id];
				if (entry) entry.jumpCount++;
			}
		}
		hookProxy._hubsMap = map;
		syncFlowContext();

		const ts = Date.now();
		for (const [, node] of _nodeMap) {
			if (node.nodeType === "hub" || node.nodeType === "jump") {
				node._updateTs = ts;
				await _area.update("node", node.id);
			}
		}
	}

	// --- Sync reactive flow context (used by Vue node components via inject) ---

	function syncFlowContext() {
		const ctx = hookProxy._flowContext;
		if (!ctx) return;
		ctx.sheetsMap = hookProxy._sheetsMap || {};
		ctx.hubsMap = hookProxy._hubsMap || {};
		ctx.labels = hookProxy._labels || {};
	}

	// --- Area pipes (drag, selection, connections) ---

	function setupAreaPipes() {
		if (hookProxy._readonly) {
			_area.addPipe((context) => {
				if (context.type === "nodepicked") {
					const node = _editor.getNode(context.data.id);
					if (node?.nodeId) {
						_selectedNodeId = node.nodeId;
						pushEvent("node_selected", { id: node.nodeId });
					}
				}
				return context;
			});
			return;
		}

		// Node drag
		_area.addPipe((context) => {
			if (context.type === "nodetranslated" && !hookProxy.isLoadingFromServer) {
				const node = _editor.getNode(context.data.id);
				if (node?.nodeId) {
					_editorHandlers.throttleNodeMoved(node.nodeId, context.data.position);
				}
			}
			if (context.type === "nodedragged") {
				const node = _editor.getNode(context.data.id);
				if (node?.nodeId) {
					_editorHandlers.flushNodeMoved(node.nodeId);
				}
			}
			return context;
		});

		// Node selection + double-click
		_area.addPipe((context) => {
			if (context.type === "nodepicked") {
				const node = _editor.getNode(context.data.id);
				if (node?.nodeId) {
					const now = Date.now();
					const isDoubleClick =
						_lastClickedNodeId === node.nodeId && now - _lastNodeClickTime < 300;

					_lastNodeClickTime = now;
					_lastClickedNodeId = node.nodeId;
					_selectedNodeId = node.nodeId;

					if (isDoubleClick) {
						pushEvent("node_double_clicked", { id: node.nodeId });
					} else {
						pushEvent("node_selected", { id: node.nodeId });
					}
				}
			}
			return context;
		});

		// Connection created
		_editor.addPipe((context) => {
			if (context.type === "connectioncreate" && !hookProxy.isLoadingFromServer) {
				const conn = context.data;
				const sourceNode = _editor.getNode(conn.source);
				const targetNode = _editor.getNode(conn.target);

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
		_editor.addPipe((context) => {
			if (context.type === "connectionremove" && !hookProxy.isLoadingFromServer) {
				const conn = context.data;
				const sourceNode = _editor.getNode(conn.source);
				const targetNode = _editor.getNode(conn.target);

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

	function setupServerEvents() {
		if (!_editorHandlers) return;

		handleEvent("flow_updated", (data) => _editorHandlers.handleFlowUpdated(data));

		_nodeMoveQueue = Promise.resolve();
		handleEvent("node_moved", (data) => {
			_nodeMoveQueue = _nodeMoveQueue
				.then(() => {
					if (!_area || _destroyed) return;
					return _editorHandlers.handleNodeMoved(data);
				})
				.catch(() => {});
		});

		handleEvent("node_added", (data) => _editorHandlers.handleNodeAdded(data));
		handleEvent("node_removed", (data) => _editorHandlers.handleNodeRemoved(data));
		handleEvent("node_restored", (data) => _editorHandlers.handleNodeRestored(data));

		_nodeUpdateQueue = Promise.resolve();
		handleEvent("node_updated", (data) => {
			_nodeUpdateQueue = _nodeUpdateQueue
				.then(() => {
					if (!_area || _destroyed) return;
					return _editorHandlers.handleNodeUpdated(data);
				})
				.catch(() => {});
		});

		handleEvent("node_data_changed", (data) => _editorHandlers.handleNodeDataChanged(data));
		handleEvent("flow_meta_changed", (data) => _editorHandlers.handleFlowMetaChanged(data));
		handleEvent("connection_added", (data) => _editorHandlers.handleConnectionAdded(data));
		handleEvent("connection_removed", (data) => _editorHandlers.handleConnectionRemoved(data));
		handleEvent("connection_updated", (data) => _editorHandlers.handleConnectionUpdated(data));

		if (_navigationHandler) {
			handleEvent("navigate_to_hub", (data) => _navigationHandler.navigateToHub(data.jump_db_id));
			handleEvent("navigate_to_node", (data) => _navigationHandler.navigateToNode(data.node_db_id));
			handleEvent("navigate_to_jumps", (data) => _navigationHandler.navigateToJumps(data.hub_db_id));
		}
	}

	// --- Cleanup ---

	function destroy() {
		_destroyed = true;
		hookProxy._eventBindingsController?.abort();
		_lodController?.destroy();
		_cursorHandler?.destroy();
		_lockHandler?.destroy();
		_keyboardHandler?.destroy();
		_editorHandlers?.destroy();
		_navigationHandler?.destroy();
		_debugHandler?.destroy();
		_minimapToggle?.destroy();
		_nodeMoveQueue = null;
		_nodeUpdateQueue = null;
		if (_area) _area.destroy();
	}

	onUnmounted(destroy);

	return {
		editor,
		area,
		loading,
		init,
		addNodeToEditor,
		addConnectionToEditor,
		rebuildHubsMap,
		syncNodeSize,
		destroy,
	};
}
