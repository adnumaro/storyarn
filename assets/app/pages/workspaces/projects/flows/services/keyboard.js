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

  function handleNavigation(e) {
    if (!e.altKey || e.ctrlKey || e.metaKey || e.shiftKey) return false;
    if (e.key === "ArrowLeft") {
      e.preventDefault();
      hook.pushEvent("nav_back", {});
      return true;
    }
    if (e.key === "ArrowRight") {
      e.preventDefault();
      hook.pushEvent("nav_forward", {});
      return true;
    }
    return false;
  }

  function isUndo(e) {
    return (e.ctrlKey || e.metaKey) && e.key === "z" && !e.shiftKey;
  }

  function isRedo(e) {
    return (e.ctrlKey || e.metaKey) && (e.key === "y" || (e.key === "z" && e.shiftKey));
  }

  function handleUndoRedo(e) {
    if (isUndo(e)) {
      if (isEditable(e.target)) return true;
      e.preventDefault();
      hook.history?.undo();
      return true;
    }
    if (isRedo(e)) {
      if (isEditable(e.target)) return true;
      e.preventDefault();
      hook.history?.redo();
      return true;
    }
    return false;
  }

  function handleScreenplayShortcut(e) {
    if (!e.shiftKey || !e.altKey || e.key !== "F" || !hook.selectedNodeId) return false;
    const reteNode = hook.nodeMap?.get(hook.selectedNodeId);
    if (reteNode?.nodeType === "dialogue") {
      e.preventDefault();
      exitInlineEdit();
      hook.pushEvent("open_screenplay", { id: hook.selectedNodeId });
      return true;
    }
    return false;
  }

  function handleEscape(e) {
    if (e.key !== "Escape") return false;
    e.preventDefault();
    const ctx = hook._flowContext;
    if (ctx?.editingNodeId) {
      exitInlineEdit();
    } else if (hook.selectedNodeId) {
      hook.pushEvent("deselect_node", {});
      hook.selectedNodeId = null;
    }
    return true;
  }

  function handleDelete(e) {
    if (e.key !== "Delete" && e.key !== "Backspace") return false;
    if (!hook.selectedNodeId) return false;
    if (lockHandler.isNodeLocked(hook.selectedNodeId)) return true;
    e.preventDefault();
    hook.pushEvent("delete_node", { id: hook.selectedNodeId });
    hook.selectedNodeId = null;
    return true;
  }

  function handleDuplicate(e) {
    if (!(e.ctrlKey || e.metaKey) || e.key !== "d" || !hook.selectedNodeId) return false;
    e.preventDefault();
    hook.pushEvent("duplicate_node", { id: hook.selectedNodeId });
    return true;
  }

  const INLINE_EDITABLE = new Set(["dialogue", "annotation"]);
  const BUILDER_EDITABLE = new Set(["condition", "instruction"]);

  function handleInlineEdit(e) {
    if (e.key !== "e" || e.ctrlKey || e.metaKey || !hook.selectedNodeId) return false;
    const reteNode = hook.nodeMap?.get(hook.selectedNodeId);
    if (!reteNode) return true;
    e.preventDefault();
    if (INLINE_EDITABLE.has(reteNode.nodeType)) {
      enterInlineEdit(reteNode.id);
    } else if (BUILDER_EDITABLE.has(reteNode.nodeType)) {
      hook.pushEvent("open_builder", {});
    }
    return true;
  }

  function handleKeyboard(e) {
    if (handleNavigation(e)) return;
    if (handleUndoRedo(e)) return;
    if (handleScreenplayShortcut(e)) return;
    if (isEditable(e.target)) return;
    if (handleEscape(e)) return;
    if (hook._flowContext?.editingNodeId) return;
    if (handleDelete(e)) return;
    if (handleDuplicate(e)) return;
    handleInlineEdit(e);
  }

  return {
    init() {
      this._keydownListener = (e) => handleKeyboard(e);
      document.addEventListener("keydown", this._keydownListener);
    },

    destroy() {
      if (this._keydownListener) {
        document.removeEventListener("keydown", this._keydownListener);
      }
    },
  };
}
