import { createMockLive, withSetup } from "../test/setup";
import type { UseUndoRedoReturn } from "./useUndoRedo";

const mockLive = createMockLive();

vi.mock("@composables/useLive", () => ({
  useLive: () => mockLive,
}));

// Import after mock is set up
const { useUndoRedo } = await import("./useUndoRedo");

describe("useUndoRedo", () => {
  let ur: UseUndoRedoReturn;
  let unmount: () => void;

  beforeEach(() => {
    vi.clearAllMocks();
    const { result, app } = withSetup(() => useUndoRedo());
    ur = result;
    unmount = () => app.unmount();
  });

  afterEach(() => {
    unmount();
  });

  describe("initial state", () => {
    it("starts with canUndo false", () => {
      expect(ur.canUndo.value).toBe(false);
    });

    it("starts with canRedo false", () => {
      expect(ur.canRedo.value).toBe(false);
    });
  });

  describe("push", () => {
    it("enables canUndo after pushing an action", () => {
      ur.push({ type: "update_value" });
      expect(ur.canUndo.value).toBe(true);
    });

    it("clears the redo stack on new push", () => {
      ur.push({ type: "a" });
      ur.undo();
      expect(ur.canRedo.value).toBe(true);

      ur.push({ type: "b" });
      expect(ur.canRedo.value).toBe(false);
    });
  });

  describe("undo", () => {
    it("pushes event to server with the action", () => {
      const action = { type: "update_value", blockId: 1, prev: "old", next: "new" };
      ur.push(action);
      ur.undo();

      expect(mockLive.pushEvent).toHaveBeenCalledWith("undo", action);
    });

    it("moves action to redo stack", () => {
      ur.push({ type: "a" });
      ur.undo();

      expect(ur.canUndo.value).toBe(false);
      expect(ur.canRedo.value).toBe(true);
    });

    it("does nothing when undo stack is empty", () => {
      ur.undo();
      expect(mockLive.pushEvent).not.toHaveBeenCalled();
    });

    it("undoes multiple actions in LIFO order", () => {
      ur.push({ type: "first" });
      ur.push({ type: "second" });

      ur.undo();
      expect(mockLive.pushEvent).toHaveBeenLastCalledWith("undo", { type: "second" });

      ur.undo();
      expect(mockLive.pushEvent).toHaveBeenLastCalledWith("undo", { type: "first" });
    });
  });

  describe("redo", () => {
    it("pushes event to server with the action", () => {
      const action = { type: "update_value" };
      ur.push(action);
      ur.undo();
      vi.clearAllMocks();

      ur.redo();
      expect(mockLive.pushEvent).toHaveBeenCalledWith("redo", action);
    });

    it("moves action back to undo stack", () => {
      ur.push({ type: "a" });
      ur.undo();
      ur.redo();

      expect(ur.canUndo.value).toBe(true);
      expect(ur.canRedo.value).toBe(false);
    });

    it("does nothing when redo stack is empty", () => {
      ur.redo();
      expect(mockLive.pushEvent).not.toHaveBeenCalled();
    });
  });

  describe("clear", () => {
    it("empties both stacks", () => {
      ur.push({ type: "a" });
      ur.push({ type: "b" });
      ur.undo();

      expect(ur.canUndo.value).toBe(true);
      expect(ur.canRedo.value).toBe(true);

      ur.clear();
      expect(ur.canUndo.value).toBe(false);
      expect(ur.canRedo.value).toBe(false);
    });
  });

  describe("maxStack overflow", () => {
    it("drops oldest action when maxStack is exceeded", () => {
      const { result, app } = withSetup(() => useUndoRedo({ maxStack: 3 }));

      result.push({ type: "a" });
      result.push({ type: "b" });
      result.push({ type: "c" });
      result.push({ type: "d" }); // "a" should be evicted

      // Undo all 3 remaining
      result.undo();
      expect(mockLive.pushEvent).toHaveBeenLastCalledWith("undo", { type: "d" });
      result.undo();
      expect(mockLive.pushEvent).toHaveBeenLastCalledWith("undo", { type: "c" });
      result.undo();
      expect(mockLive.pushEvent).toHaveBeenLastCalledWith("undo", { type: "b" });

      // Stack is empty now — "a" was dropped
      result.undo();
      expect(ur.canUndo.value).toBe(false);

      app.unmount();
    });
  });

  describe("custom event names", () => {
    it("uses custom undo/redo event names", () => {
      const { result, app } = withSetup(() =>
        useUndoRedo({ undoEvent: "revert_change", redoEvent: "reapply_change" }),
      );

      const action = { type: "test" };
      result.push(action);

      result.undo();
      expect(mockLive.pushEvent).toHaveBeenCalledWith("revert_change", action);

      result.redo();
      expect(mockLive.pushEvent).toHaveBeenCalledWith("reapply_change", action);

      app.unmount();
    });
  });

  describe("undo-redo round trip", () => {
    it("supports undo then redo then undo again", () => {
      const action = { type: "round_trip" };
      ur.push(action);

      ur.undo();
      expect(ur.canUndo.value).toBe(false);
      expect(ur.canRedo.value).toBe(true);

      ur.redo();
      expect(ur.canUndo.value).toBe(true);
      expect(ur.canRedo.value).toBe(false);

      ur.undo();
      expect(ur.canUndo.value).toBe(false);
      expect(ur.canRedo.value).toBe(true);
    });
  });
});
