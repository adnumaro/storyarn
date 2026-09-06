import { keyboard } from "@modules/flows/editor/services/keyboard";
import type { HookProxy } from "@modules/flows/editor/services/editorHandlers";

describe("sequence workspace keyboard boundary", () => {
  it("keeps graph actions outside the workspace and shares composition undo", () => {
    const pushEvent = vi.fn();
    const undoHistory = vi.fn();
    const hook = { selectedNodeId: 20, pushEvent, undoHistory } as unknown as HookProxy;
    const handler = keyboard(hook, null);
    const workspace = document.createElement("section");
    workspace.dataset.sequenceWorkspace = "";
    const layer = document.createElement("button");
    workspace.append(layer);
    document.body.append(workspace);
    handler.init();

    try {
      for (const [key, metaKey] of [
        ["Delete", false],
        ["d", true],
        ["Escape", false],
      ] as const) {
        layer.dispatchEvent(new KeyboardEvent("keydown", { key, metaKey, bubbles: true }));
      }
      expect(pushEvent).not.toHaveBeenCalled();
      expect(hook.selectedNodeId).toBe(20);

      layer.dispatchEvent(new KeyboardEvent("keydown", { key: "z", metaKey: true, bubbles: true }));
      expect(undoHistory).toHaveBeenCalledOnce();

      document.body.dispatchEvent(new KeyboardEvent("keydown", { key: "Delete", bubbles: true }));
      expect(pushEvent).toHaveBeenCalledWith("delete_node", { id: 20 });
    } finally {
      handler.destroy();
      workspace.remove();
    }
  });

  it("handles Alt+arrows inside the workspace without using browser history", () => {
    const pushEvent = vi.fn();
    const hook = { selectedNodeId: 20, pushEvent } as unknown as HookProxy;
    const handler = keyboard(hook, null);
    const workspace = document.createElement("section");
    workspace.dataset.sequenceWorkspace = "";
    const layer = document.createElement("button");
    workspace.append(layer);
    document.body.append(workspace);
    handler.init();

    try {
      for (const [key, navigation] of [
        ["ArrowLeft", "nav_back"],
        ["ArrowRight", "nav_forward"],
      ]) {
        const event = new KeyboardEvent("keydown", {
          key,
          altKey: true,
          bubbles: true,
          cancelable: true,
        });
        layer.dispatchEvent(event);
        expect(event.defaultPrevented).toBe(true);
        expect(pushEvent).toHaveBeenLastCalledWith(navigation, {});
      }
      expect(pushEvent).toHaveBeenCalledTimes(2);
      expect(hook.selectedNodeId).toBe(20);
    } finally {
      handler.destroy();
      workspace.remove();
    }
  });
});
