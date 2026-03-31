/**
 * Keyboard shortcuts handler for the flow canvas (V2 Vue-native).
 *
 * Uses flowContext for inline edit state instead of V1 event_bindings.
 */

function isEditable(el) {
  const tag = el.tagName;
  return tag === "INPUT" || tag === "TEXTAREA" || tag === "SELECT" || el.isContentEditable;
}

export function keyboard(hook, lockHandler) {
  function enterInlineEdit(reteNodeId) {
    const node = hook.editor.getNode(reteNodeId);
    if (!node) {
      return;
    }
    const type = node.nodeType;
    if (type !== "dialogue" && type !== "annotation") {
      return;
    }
    const ctx = hook._flowContext;
    if (ctx) {
      ctx.editingNodeId = reteNodeId;
    }
    hook._inlineEditingNodeId = reteNodeId;
  }

  function exitInlineEdit() {
    const ctx = hook._flowContext;
    if (!ctx?.editingNodeId) {
      return;
    }
    const nodeView = hook.area?.nodeViews.get(ctx.editingNodeId);
    if (nodeView) {
      const focused = nodeView.element.querySelector("textarea:focus, input:focus");
      if (focused) {
        focused.blur();
      }
    }
    ctx.editingNodeId = null;
    hook._inlineEditingNodeId = null;
  }

  return {
    init() {
      this._keydownListener = (e) => this.handleKeyboard(e);
      document.addEventListener("keydown", this._keydownListener);
    },

    handleKeyboard(e) {
      // Alt+Left/Right — navigation history
      if (e.altKey && !e.ctrlKey && !e.metaKey && !e.shiftKey) {
        if (e.key === "ArrowLeft") {
          e.preventDefault();
          hook.pushEvent("nav_back", {});
          return;
        }
        if (e.key === "ArrowRight") {
          e.preventDefault();
          hook.pushEvent("nav_forward", {});
          return;
        }
      }

      // Undo — Ctrl+Z / Cmd+Z
      if ((e.ctrlKey || e.metaKey) && e.key === "z" && !e.shiftKey) {
        if (isEditable(e.target)) {
          return;
        }
        e.preventDefault();
        hook.history?.undo();
        return;
      }

      // Redo — Ctrl+Y / Cmd+Y / Ctrl+Shift+Z
      if ((e.ctrlKey || e.metaKey) && (e.key === "y" || (e.key === "z" && e.shiftKey))) {
        if (isEditable(e.target)) {
          return;
        }
        e.preventDefault();
        hook.history?.redo();
        return;
      }

      // Shift+Alt+F — fullscreen screenplay editor
      if (e.shiftKey && e.altKey && e.key === "F" && hook.selectedNodeId) {
        const reteNode = hook.nodeMap?.get(hook.selectedNodeId);
        if (reteNode?.nodeType === "dialogue") {
          e.preventDefault();
          exitInlineEdit();
          hook.pushEvent("open_screenplay", { id: hook.selectedNodeId });
          return;
        }
      }

      if (isEditable(e.target)) {
        return;
      }

      // Escape
      if (e.key === "Escape") {
        e.preventDefault();
        const ctx = hook._flowContext;
        if (ctx?.editingNodeId) {
          exitInlineEdit();
        } else if (hook.selectedNodeId) {
          hook.pushEvent("deselect_node", {});
          hook.selectedNodeId = null;
        }
        return;
      }

      // Skip while inline editing
      if (hook._flowContext?.editingNodeId) {
        return;
      }

      // Delete/Backspace
      if (e.key === "Delete" || e.key === "Backspace") {
        if (hook.selectedNodeId) {
          e.preventDefault();
          if (lockHandler.isNodeLocked(hook.selectedNodeId)) {
            return;
          }
          hook.pushEvent("delete_node", { id: hook.selectedNodeId });
          hook.selectedNodeId = null;
          return;
        }
      }

      // Ctrl+D — duplicate
      if ((e.ctrlKey || e.metaKey) && e.key === "d" && hook.selectedNodeId) {
        e.preventDefault();
        hook.pushEvent("duplicate_node", { id: hook.selectedNodeId });
        return;
      }

      // E — inline edit or open builder
      if (e.key === "e" && !e.ctrlKey && !e.metaKey && hook.selectedNodeId) {
        const reteNode = hook.nodeMap?.get(hook.selectedNodeId);
        if (!reteNode) {
          return;
        }
        const nodeType = reteNode.nodeType;

        if (nodeType === "dialogue" || nodeType === "annotation") {
          e.preventDefault();
          enterInlineEdit(reteNode.id);
        } else if (nodeType === "condition" || nodeType === "instruction") {
          e.preventDefault();
          hook.pushEvent("open_builder", {});
        }
        return;
      }
    },

    destroy() {
      if (this._keydownListener) {
        document.removeEventListener("keydown", this._keydownListener);
      }
    },
  };
}
