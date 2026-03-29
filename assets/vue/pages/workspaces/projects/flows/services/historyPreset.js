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

/**
 * Undo/redo action for node drags.
 * Uses area.translate() which fires nodetranslated → debounced server push.
 */
class DragAction {
	constructor(area, nodeId, prev, next) {
		this.area = area;
		this.nodeId = nodeId;
		this.prev = { ...prev };
		this.next = { ...next };
	}

	async undo() {
		const view = this.area.nodeViews.get(this.nodeId);
		if (!view) {
			return;
		}
		await this.area.translate(this.nodeId, this.prev);
	}

	async redo() {
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
class AddConnectionAction {
	constructor(editor, connection) {
		this.editor = editor;
		this.connection = connection;
	}

	async undo() {
		if (!this.editor.getConnection(this.connection.id)) {
			return;
		}
		await this.editor.removeConnection(this.connection.id);
	}

	async redo() {
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
class RemoveConnectionAction {
	constructor(editor, connection) {
		this.editor = editor;
		this.connection = connection;
	}

	async undo() {
		if (
			!this.editor.getNode(this.connection.source) ||
			!this.editor.getNode(this.connection.target)
		) {
			return;
		}
		await this.editor.addConnection(this.connection);
	}

	async redo() {
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
export class DeleteNodeAction {
	constructor(hookProxy, nodeId) {
		this.hookProxy = hookProxy;
		this.nodeId = nodeId;
	}

	async undo() {
		this.hookProxy.pushEvent("restore_node", { id: this.nodeId });
	}

	async redo() {
		this.hookProxy._historyTriggeredDelete = this.nodeId;
		this.hookProxy.pushEvent("delete_node", { id: this.nodeId });
	}
}

/**
 * Undo/redo action for node creation.
 * Undo deletes the node; redo restores it.
 */
export class CreateNodeAction {
	constructor(hookProxy, nodeId) {
		this.hookProxy = hookProxy;
		this.nodeId = nodeId;
	}

	async undo() {
		this.hookProxy._historyTriggeredDelete = this.nodeId;
		this.hookProxy.pushEvent("delete_node", { id: this.nodeId });
	}

	async redo() {
		this.hookProxy.pushEvent("restore_node", { id: this.nodeId });
	}
}

/**
 * Undo/redo action for flow metadata (name, shortcut) changes.
 * Undo restores the previous value; redo restores the new one.
 */
export const FLOW_META_COALESCE_MS = 2000;

export class FlowMetaAction {
	constructor(hookProxy, field, prevValue, newValue) {
		this.hookProxy = hookProxy;
		this.field = field;
		this.prevValue = prevValue;
		this.newValue = newValue;
	}

	async undo() {
		this.hookProxy.pushEvent("restore_flow_meta", {
			field: this.field,
			value: this.prevValue,
		});
	}

	async redo() {
		this.hookProxy.pushEvent("restore_flow_meta", {
			field: this.field,
			value: this.newValue,
		});
	}
}

/**
 * Undo/redo action for node data (property) changes.
 * Undo restores the previous data snapshot; redo restores the new one.
 */
export const NODE_DATA_COALESCE_MS = 1000;

export class NodeDataAction {
	constructor(hookProxy, nodeId, prevData, newData) {
		this.hookProxy = hookProxy;
		this.nodeId = nodeId;
		this.prevData = prevData;
		this.newData = newData;
	}

	async undo() {
		this.hookProxy.pushEvent("restore_node_data", {
			id: this.nodeId,
			data: this.prevData,
		});
	}

	async redo() {
		this.hookProxy.pushEvent("restore_node_data", {
			id: this.nodeId,
			data: this.newData,
		});
	}
}

/**
 * Converts a Map<reteNodeId, {x, y}> to the server batch payload format.
 * Shared by AutoLayoutAction and performAutoLayout.
 * @param {Map<string, {x: number, y: number}>} positionsMap
 * @returns {Array<{id: number, position_x: number, position_y: number}>}
 */
export function buildBatchPositions(positionsMap) {
	const result = [];
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
class AutoLayoutAction {
	constructor(hookProxy, prevPositions, newPositions) {
		this.hookProxy = hookProxy;
		this.prevPositions = prevPositions;
		this.newPositions = newPositions;
	}

	async undo() {
		await this._applyPositions(this.prevPositions);
	}

	async redo() {
		await this._applyPositions(this.newPositions);
	}

	async _applyPositions(positions) {
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
			positions: buildBatchPositions(positions),
		});
	}
}

/**
 * Creates a custom history preset for the flow canvas.
 * @param {Object} hookProxy - The hookProxy from useFlowEditor (exposes pushEvent, area, isLoadingFromServer, etc.)
 * @returns {{ connect: (history: HistoryPlugin) => void }}
 */
export function historyPreset(hookProxy) {
	return {
		connect(history) {
			const area = history.parentScope();
			const editor = area.parentScope();
			const timing = history.timing * 2;

			// Track latest known position per node (for drag start reference)
			const positions = new Map();

			// Nodes currently being dragged (picked but not yet released)
			const picked = new Set();

			// --- Connection tracking (editor pipe) ---
			editor.addPipe((context) => {
				if (hookProxy.isLoadingFromServer) {
					return context;
				}

				if (context.type === "connectioncreated") {
					const connection = editor.getConnection(context.data.id);
					if (connection) {
						history.add(new AddConnectionAction(editor, connection));
					}
				}

				if (context.type === "connectionremoved") {
					const connection = context.data;
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

				if (context.type === "nodetranslated") {
					positions.set(context.data.id, { ...context.data.position });
				}
				return context;
			});

			// --- Drag tracking (area pipe) ---
			area.addPipe((context) => {
				if (!context || typeof context !== "object" || !("type" in context)) {
					return context;
				}

				if (context.type === "nodepicked") {
					picked.add(context.data.id);
				}

				if (context.type === "nodedragged") {
					picked.delete(context.data.id);
				}

				if (context.type === "nodetranslated") {
					if (hookProxy.isLoadingFromServer) {
						return context;
					}

					const { id, position, previous } = context.data;

					// Only track drags (node is currently picked), not programmatic translates
					if (!picked.has(id)) {
						return context;
					}

					// Coalesce: find recent DragAction for same node
					const recent = history
						.getRecent(timing)
						.filter(
							(r) => r.action instanceof DragAction && r.action.nodeId === id,
						);

					if (recent[0]) {
						// Update existing action's endpoint and timestamp
						recent[0].action.next = { ...position };
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

export { AutoLayoutAction };
