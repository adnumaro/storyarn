/**
 * Custom history preset for the flow canvas.
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
    if (!view) return;
    await this.area.translate(this.nodeId, this.prev);
  }

  async redo() {
    const view = this.area.nodeViews.get(this.nodeId);
    if (!view) return;
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
    if (!this.editor.getConnection(this.connection.id)) return;
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
    if (!this.editor.getConnection(this.connection.id)) return;
    await this.editor.removeConnection(this.connection.id);
  }
}

/**
 * Undo/redo action for node deletion.
 * Undo sends restore_node to server; redo sends delete_node.
 */
class DeleteNodeAction {
  constructor(hook, nodeId) {
    this.hook = hook;
    this.nodeId = nodeId;
  }

  async undo() {
    this.hook.pushEvent("restore_node", { id: this.nodeId });
  }

  async redo() {
    this.hook._historyTriggeredDelete = this.nodeId;
    this.hook.pushEvent("delete_node", { id: this.nodeId });
  }
}

/**
 * Creates a custom history preset for the flow canvas.
 * @param {Object} hook - The FlowCanvas hook instance (for isLoadingFromServer)
 * @returns {{ connect: (history: HistoryPlugin) => void }}
 */
export function createFlowHistoryPreset(hook) {
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
        if (hook.isLoadingFromServer) return context;

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
        if (!context || typeof context !== "object" || !("type" in context)) return context;

        if (context.type === "nodetranslated") {
          positions.set(context.data.id, { ...context.data.position });
        }
        return context;
      });

      // --- Drag tracking (area pipe) ---
      area.addPipe((context) => {
        if (!context || typeof context !== "object" || !("type" in context)) return context;

        if (context.type === "nodepicked") {
          picked.add(context.data.id);
        }

        if (context.type === "nodedragged") {
          picked.delete(context.data.id);
        }

        if (context.type === "nodetranslated") {
          if (hook.isLoadingFromServer) return context;

          const { id, position, previous } = context.data;

          // Only track drags (node is currently picked), not programmatic translates
          if (!picked.has(id)) return context;

          // Coalesce: find recent DragAction for same node
          const recent = history
            .getRecent(timing)
            .filter((r) => r.action instanceof DragAction && r.action.nodeId === id);

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

export { DeleteNodeAction };
