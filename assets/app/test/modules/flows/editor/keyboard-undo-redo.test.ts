import { describe, expect, it, vi } from "vitest";
import { keyboard } from "@modules/flows/editor/services/keyboard";
import type { HookProxy } from "@modules/flows/editor/services/editorHandlers";

function setup() {
  const undoHistory = vi.fn();
  const redoHistory = vi.fn();
  const hook = { selectedNodeId: null, undoHistory, redoHistory } as unknown as HookProxy;
  const handler = keyboard(hook);
  handler.init();
  return { undoHistory, redoHistory, handler };
}

function press(init: KeyboardEventInit) {
  document.body.dispatchEvent(new KeyboardEvent("keydown", { bubbles: true, ...init }));
}

describe("flow canvas undo and redo shortcuts", () => {
  it("redoes with Ctrl+Shift+Z when the platform reports an upper-case key", () => {
    const { redoHistory, undoHistory, handler } = setup();

    try {
      // Windows and Linux report `key: "Z"` while Shift is held.
      press({ key: "Z", ctrlKey: true, shiftKey: true });

      expect(redoHistory).toHaveBeenCalledOnce();
      expect(undoHistory).not.toHaveBeenCalled();
    } finally {
      handler.destroy();
    }
  });

  it("does not delete a node another collaborator has locked", () => {
    const pushEvent = vi.fn();
    const hook = {
      selectedNodeId: 7,
      pushEvent,
      _flowContext: { nodeLocks: { "7": { userId: 2, name: "ana", color: "#e11d48" } } },
    } as unknown as HookProxy;
    const handler = keyboard(hook);
    handler.init();

    try {
      press({ key: "Delete" });

      expect(pushEvent).not.toHaveBeenCalled();
      expect(hook.selectedNodeId).toBe(7);
    } finally {
      handler.destroy();
    }
  });

  it("undoes with Ctrl+Z while Caps Lock is on", () => {
    const { redoHistory, undoHistory, handler } = setup();

    try {
      press({ key: "Z", ctrlKey: true });

      expect(undoHistory).toHaveBeenCalledOnce();
      expect(redoHistory).not.toHaveBeenCalled();
    } finally {
      handler.destroy();
    }
  });
});
