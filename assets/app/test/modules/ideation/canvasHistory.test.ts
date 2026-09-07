import { describe, expect, it, vi } from "vitest";
import { useCanvasHistory } from "@modules/ideation/composables/useCanvasHistory";

function pending() {
  let resolve!: (value: boolean) => void;
  let reject!: (reason: Error) => void;
  const promise = new Promise<boolean>((yes, no) => {
    resolve = yes;
    reject = no;
  });
  return { promise, resolve, reject };
}
function command() {
  return { undo: vi.fn(async () => true), redo: vi.fn(async () => true) };
}

describe("canvas local command history", () => {
  it("moves commands between stacks only after the server acknowledgement", async () => {
    const history = useCanvasHistory(vi.fn());
    const undo = pending();
    const action = { undo: vi.fn(() => undo.promise), redo: vi.fn(async () => true) };
    history.push(action);
    const undoing = history.undo();
    expect(history.busy.value).toBe(true);
    expect(history.canUndo.value).toBe(true);
    expect(history.canRedo.value).toBe(false);
    await history.undo();
    await history.redo();
    expect(action.undo).toHaveBeenCalledTimes(1);
    expect(action.redo).not.toHaveBeenCalled();
    undo.resolve(true);
    await undoing;
    expect(history.busy.value).toBe(false);
    expect(history.canUndo.value).toBe(false);
    expect(history.canRedo.value).toBe(true);
    await history.redo();
    expect(action.redo).toHaveBeenCalledTimes(1);
    expect(history.canUndo.value).toBe(true);
    expect(history.canRedo.value).toBe(false);
  });
  it("keeps failed or thrown commands retryable and reports each failure once", async () => {
    const error = vi.fn();
    const history = useCanvasHistory(error);
    const action = command();
    action.undo.mockResolvedValueOnce(false).mockRejectedValueOnce(new Error("offline"));
    history.push(action);
    await history.undo();
    expect(error).toHaveBeenCalledTimes(1);
    expect(history.canUndo.value).toBe(true);
    expect(history.canRedo.value).toBe(false);
    await history.undo();
    expect(error).toHaveBeenCalledTimes(2);
    expect(history.canUndo.value).toBe(true);
    expect(history.busy.value).toBe(false);
    await history.undo();
    expect(history.canRedo.value).toBe(true);
    expect(action.undo).toHaveBeenCalledTimes(3);
  });
  it("ignores late acknowledgements after reset without disturbing a new operation", async () => {
    const error = vi.fn();
    const history = useCanvasHistory(error);
    const old = pending();
    const fresh = pending();
    history.push({ undo: () => old.promise, redo: async () => true });
    const oldUndo = history.undo();
    history.clear();
    expect(history.canUndo.value).toBe(false);
    expect(history.canRedo.value).toBe(false);
    const newAction = { undo: vi.fn(() => fresh.promise), redo: async () => true };
    history.push(newAction);
    const freshUndo = history.undo();
    old.resolve(true);
    await oldUndo;
    expect(history.busy.value).toBe(true);
    expect(history.canUndo.value).toBe(true);
    expect(history.canRedo.value).toBe(false);
    fresh.resolve(true);
    await freshUndo;
    expect(history.busy.value).toBe(false);
    expect(history.canUndo.value).toBe(false);
    expect(history.canRedo.value).toBe(true);
    expect(error).not.toHaveBeenCalled();
  });
  it("does not report errors from an invalidated operation", async () => {
    const error = vi.fn();
    const history = useCanvasHistory(error);
    const old = pending();
    history.push({ undo: () => old.promise, redo: async () => true });
    const undoing = history.undo();
    history.clear();
    old.reject(new Error("old session failed"));
    await undoing;
    expect(error).not.toHaveBeenCalled();
    expect(history.canUndo.value).toBe(false);
    expect(history.canRedo.value).toBe(false);
  });
  it("bounds session-local history and drops the redo branch after a new command", async () => {
    const history = useCanvasHistory(vi.fn());
    const actions = Array.from({ length: 51 }, command);
    for (const action of actions) history.push(action);
    for (let i = 0; i < 50; i++) await history.undo();
    expect(actions[0].undo).not.toHaveBeenCalled();
    expect(actions[1].undo).toHaveBeenCalledTimes(1);
    expect(history.canUndo.value).toBe(false);
    expect(history.canRedo.value).toBe(true);
    const replacement = command();
    history.push(replacement);
    expect(history.canRedo.value).toBe(false);
    await history.undo();
    expect(replacement.undo).toHaveBeenCalledTimes(1);
  });
  it("guards composed operations against re-entry and returns no result after reset", async () => {
    const history = useCanvasHistory(vi.fn());
    const first = pending();
    const running = history.run(() => first.promise);
    const skipped = vi.fn(async () => "ignored");
    expect(await history.run(skipped)).toBeUndefined();
    expect(skipped).not.toHaveBeenCalled();
    history.clear();
    first.resolve(true);
    expect(await running).toBeUndefined();
    expect(history.busy.value).toBe(false);
  });
});
