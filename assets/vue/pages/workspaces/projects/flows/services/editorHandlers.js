/**
 * Editor handlers for node and connection CRUD operations (V2 Vue-native).
 *
 * Replaces V1 editor_handlers.js — no Lit imports, uses Vue-native
 * FlowNode and needsRebuild from node-configs.js.
 */

import { ClassicPreset } from "rete";
import { FlowNode } from "../lib/flow-node.js";
import { needsRebuild } from "../lib/node-configs.js";
import {
	CreateNodeAction,
	DeleteNodeAction,
	FLOW_META_COALESCE_MS,
	FlowMetaAction,
	NODE_DATA_COALESCE_MS,
	NodeDataAction,
} from "./historyPreset.js";

/**
 * @param {Object} hook - The hookProxy from useFlowEditor
 */
export function editorHandlers(hook) {
	return {
		init() {
			hook._throttleTimers = {};
			hook._pendingPositions = {};
		},

		throttleNodeMoved(nodeId, position) {
			hook._pendingPositions[nodeId] = position;
			if (hook._throttleTimers[nodeId]) {
				return;
			}

			hook._throttleTimers[nodeId] = setTimeout(() => {
				const pos = hook._pendingPositions[nodeId];
				if (pos) {
					hook.pushEvent("node_dragging", {
						id: nodeId,
						position_x: pos.x,
						position_y: pos.y,
					});
				}
				delete hook._throttleTimers[nodeId];
			}, 100);
		},

		flushNodeMoved(nodeId) {
			if (hook._throttleTimers[nodeId]) {
				clearTimeout(hook._throttleTimers[nodeId]);
				delete hook._throttleTimers[nodeId];
			}

			const pos = hook._pendingPositions[nodeId];
			if (pos) {
				hook.pushEvent("node_moved", {
					id: nodeId,
					position_x: pos.x,
					position_y: pos.y,
				});
				delete hook._pendingPositions[nodeId];
			}
		},

		async handleNodeMoved(data) {
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

		async handleFlowUpdated(data) {
			hook.history?.clear();

			for (const conn of [...hook.editor.getConnections()]) {
				try {
					await hook.editor.removeConnection(conn.id);
				} catch {}
			}
			for (const node of [...hook.editor.getNodes()]) {
				try {
					await hook.editor.removeNode(node.id);
				} catch {}
			}
			hook.nodeMap.clear();
			hook.connectionDataMap.clear();
			await hook.loadFlow(data);
			await hook.rebuildHubsMap();

			await new Promise((resolve) =>
				requestAnimationFrame(() => requestAnimationFrame(resolve)),
			);
			await hook.syncAllNodeSizes();
		},

		async handleNodeAdded(data) {
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

		async handleNodeRemoved(data) {
			const node = hook.nodeMap.get(data.id);
			if (node) {
				// Exit inline edit if needed
				const ctx = hook._flowContext;
				if (ctx?.editingNodeId === node.id) {
					ctx.editingNodeId = null;
				}

				if (hook._throttleTimers?.[data.id]) {
					clearTimeout(hook._throttleTimers[data.id]);
					delete hook._throttleTimers[data.id];
				}

				if (data.self && hook._historyTriggeredDelete !== data.id) {
					hook.history?.add(new DeleteNodeAction(hook, data.id));
				}
				if (hook._historyTriggeredDelete === data.id) {
					hook._historyTriggeredDelete = null;
				}

				const needsHubRebuild =
					node.nodeType === "hub" || node.nodeType === "jump";
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
				hook.nodeMap.delete(data.id);
				if (hook.selectedNodeId === data.id) {
					hook.selectedNodeId = null;
				}
				if (needsHubRebuild) {
					await hook.rebuildHubsMap();
				}
			}
		},

		async handleNodeRestored(data) {
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

		async handleNodeUpdated(data) {
			const { id, data: nodeData } = data;
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

			const shouldRebuild = needsRebuild(
				existingNode.nodeType,
				existingNode.nodeData,
				nodeData,
			);

			if (shouldRebuild) {
				await this.rebuildNode(id, existingNode, nodeData);
			} else {
				// Update nodeData and bump reactive version (no area.update — preserves sockets)
				existingNode.nodeData = { ...nodeData };
				if (ctx) {
					ctx.nodeDataVersion = (ctx.nodeDataVersion || 0) + 1;
				}
			}

			if (existingNode.nodeType === "hub" || existingNode.nodeType === "jump") {
				await hook.rebuildHubsMap();
			}
		},

		async rebuildNode(id, existingNode, nodeData) {
			// Exit inline edit if needed
			const ctx = hook._flowContext;
			if (ctx?.editingNodeId === existingNode.id) {
				ctx.editingNodeId = null;
			}

			const view = hook.area.nodeViews.get(existingNode.id);
			const position = view ? { ...view.position } : { x: 0, y: 0 };

			hook.enterLoadingFromServer();
			try {
				const connections = [...hook.editor.getConnections()];
				const affectedConnections = [];

				for (const conn of connections) {
					if (
						conn.source === existingNode.id ||
						conn.target === existingNode.id
					) {
						affectedConnections.push({
							source: hook.editor.getNode(conn.source)?.nodeId,
							sourceOutput: conn.sourceOutput,
							target: hook.editor.getNode(conn.target)?.nodeId,
							targetInput: conn.targetInput,
							connData: hook.connectionDataMap.get(conn.id),
						});
						hook.connectionDataMap.delete(conn.id);
						await hook.editor.removeConnection(conn.id);
					}
				}

				await hook.editor.removeNode(existingNode.id);
				hook.nodeMap.delete(id);

				const newNode = new FlowNode(existingNode.nodeType, id, nodeData);
				newNode.id = `node-${id}`;

				await hook.editor.addNode(newNode);
				await hook.area.translate(newNode.id, position);
				hook.nodeMap.set(id, newNode);

				await hook.area.update("node", newNode.id);
				await hook.syncNodeSize(newNode.id);

				for (const connInfo of affectedConnections) {
					const sourceNode = hook.nodeMap.get(connInfo.source);
					const targetNode = hook.nodeMap.get(connInfo.target);
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

		async handleConnectionAdded(data) {
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

		async handleConnectionRemoved(data) {
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

		handleNodeDataChanged(data) {
			if (!hook.history) {
				return;
			}
			const { id, prev_data: prevData, new_data: newData } = data;

			const recent = hook.history
				.getRecent(NODE_DATA_COALESCE_MS)
				.filter(
					(r) => r.action instanceof NodeDataAction && r.action.nodeId === id,
				);

			if (recent[0]) {
				recent[0].action.newData = newData;
				recent[0].time = Date.now();
			} else {
				hook.history.add(new NodeDataAction(hook, id, prevData, newData));
			}
		},

		handleFlowMetaChanged(data) {
			if (!hook.history) {
				return;
			}
			const { field, prev, new: newValue } = data;

			const recent = hook.history
				.getRecent(FLOW_META_COALESCE_MS)
				.filter(
					(r) => r.action instanceof FlowMetaAction && r.action.field === field,
				);

			if (recent[0]) {
				recent[0].action.newValue = newValue;
				recent[0].time = Date.now();
			} else {
				hook.history.add(new FlowMetaAction(hook, field, prev, newValue));
			}
		},

		handleConnectionUpdated(data) {
			const connId = `conn-${data.id}`;
			hook.connectionDataMap.set(connId, {
				id: data.id,
				label: data.label,
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
