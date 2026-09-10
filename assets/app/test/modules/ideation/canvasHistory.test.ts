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
  return { targets: () => [], undo: vi.fn(async () => true), redo: vi.fn(async () => true) };
}

describe("canvas local command history", () => {
  it("moves commands between stacks only after the server acknowledgement", async () => {
    const history = useCanvasHistory(vi.fn());
    const undo = pending();
    const action = {
      targets: () => [],
      undo: vi.fn(() => undo.promise),
      redo: vi.fn(async () => true),
    };
    history.push(action);
    const undoing = history.undo();
    expect(history.busy.value).toBe(true);
    expect(history.canUndo.value).toBe(true);
    expect(history.canRedo.value).toBe(false);
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
  it("queues rapid undo and redo intentions using the stack at each turn", async () => {
    const history = useCanvasHistory(vi.fn());
    const gate = pending();
    const calls: string[] = [];
    const first = {
      targets: () => [],
      undo: vi.fn(async () => {
        calls.push("undo first");
        return true;
      }),
      redo: vi.fn(async () => {
        calls.push("redo first");
        return true;
      }),
    };
    const second = {
      targets: () => [],
      undo: vi.fn(async () => {
        calls.push("undo second");
        return gate.promise;
      }),
      redo: vi.fn(async () => {
        calls.push("redo second");
        return true;
      }),
    };
    history.push(first);
    history.push(second);
    const running = [history.undo(), history.undo(), history.redo(), history.redo()];
    expect(calls).toEqual(["undo second"]);
    expect(history.busy.value).toBe(true);
    expect(history.canRedo.value).toBe(false);
    gate.resolve(true);
    await Promise.all(running);
    expect(calls).toEqual(["undo second", "undo first", "redo first", "redo second"]);
    expect(history.busy.value).toBe(false);
    expect(history.canUndo.value).toBe(true);
    expect(history.canRedo.value).toBe(false);
  });
  it("waits for a normal write to record its command before executing queued undo", async () => {
    const history = useCanvasHistory(vi.fn());
    const gate = pending();
    const action = command();
    const writing = history
      .run(() => gate.promise)
      .then((saved) => {
        if (saved) history.push(action);
      });
    const undoing = history.undo();
    expect(action.undo).not.toHaveBeenCalled();
    gate.resolve(true);
    await Promise.all([writing, undoing]);
    expect(action.undo).toHaveBeenCalledTimes(1);
    expect(history.canUndo.value).toBe(false);
    expect(history.canRedo.value).toBe(true);
  });
  it("preserves a new action recorded while undo awaits acknowledgement and invalidates redo", async () => {
    const history = useCanvasHistory(vi.fn());
    const gate = pending();
    const older = command();
    older.undo.mockImplementation(() => gate.promise);
    const newer = command();
    history.push(older);
    const undoing = history.undo();
    history.push(newer);
    gate.resolve(true);
    await undoing;
    expect(history.canUndo.value).toBe(true);
    expect(history.canRedo.value).toBe(false);
    await history.undo();
    expect(newer.undo).toHaveBeenCalledTimes(1);
    expect(older.undo).toHaveBeenCalledTimes(1);
  });
  it("keeps an acknowledged redo behind actions recorded while it was in flight", async () => {
    const history = useCanvasHistory(vi.fn());
    const gate = pending();
    const older = command();
    older.redo.mockImplementation(() => gate.promise);
    const newer = command();
    history.push(older);
    await history.undo();
    const redoing = history.redo();
    history.push(newer);
    gate.resolve(true);
    await redoing;
    await history.undo();
    expect(newer.undo).toHaveBeenCalledTimes(1);
    expect(older.undo).toHaveBeenCalledTimes(1);
    await history.undo();
    expect(older.undo).toHaveBeenCalledTimes(2);
  });
  it("cancels queued intentions after reset even if an old acknowledgement arrives later", async () => {
    const history = useCanvasHistory(vi.fn());
    const gate = pending();
    const old = command();
    old.undo.mockImplementation(() => gate.promise);
    history.push(old);
    const running = [history.undo(), history.redo(), history.undo()];
    history.clear();
    const fresh = command();
    history.push(fresh);
    gate.resolve(true);
    await Promise.all(running);
    expect(old.undo).toHaveBeenCalledTimes(1);
    expect(old.redo).not.toHaveBeenCalled();
    expect(fresh.undo).not.toHaveBeenCalled();
    expect(history.canUndo.value).toBe(true);
    expect(history.canRedo.value).toBe(false);
    expect(history.busy.value).toBe(false);
  });
  it("stops queued intentions on offline uncertainty and permits an explicit later retry", async () => {
    const error = vi.fn();
    const history = useCanvasHistory(error, () => true);
    const gate = pending();
    const action = command();
    action.undo.mockImplementationOnce(() => gate.promise);
    history.push(action);
    const running = [history.undo(), history.undo(), history.redo(), history.undo()];
    gate.resolve(false);
    await Promise.all(running);
    expect(action.undo).toHaveBeenCalledTimes(1);
    expect(action.redo).not.toHaveBeenCalled();
    expect(error).toHaveBeenCalledTimes(1);
    expect(history.canUndo.value).toBe(true);
    await history.undo();
    expect(action.undo).toHaveBeenCalledTimes(2);
    expect(history.canRedo.value).toBe(true);
  });
  it("continues queued undo after a definitive rejection without repeating the rejected action", async () => {
    const error = vi.fn();
    const history = useCanvasHistory(error);
    const previous = command();
    const rejected = command();
    rejected.undo.mockResolvedValue(false);
    history.push(previous);
    history.push(rejected);
    await Promise.all([history.undo(), history.undo()]);
    expect(rejected.undo).toHaveBeenCalledTimes(1);
    expect(previous.undo).toHaveBeenCalledTimes(1);
    expect(error).toHaveBeenCalledTimes(1);
    expect(history.canUndo.value).toBe(false);
    expect(history.canRedo.value).toBe(true);
  });
  it("drops a rejected command so the next undo reaches the previous action", async () => {
    const error = vi.fn();
    const history = useCanvasHistory(error);
    const previous = command();
    const action = command();
    action.undo.mockResolvedValue(false);
    history.push(previous);
    history.push(action);
    await history.undo();
    expect(error).toHaveBeenCalledTimes(1);
    expect(history.canUndo.value).toBe(true);
    expect(history.canRedo.value).toBe(false);
    await history.undo();
    expect(action.undo).toHaveBeenCalledTimes(1);
    expect(previous.undo).toHaveBeenCalledTimes(1);
    expect(history.canUndo.value).toBe(false);
    expect(history.canRedo.value).toBe(true);
    await history.redo();
    expect(previous.redo).toHaveBeenCalledTimes(1);
    expect(action.redo).not.toHaveBeenCalled();
    expect(error).toHaveBeenCalledTimes(1);
  });
  it("also drops a rejected redo without blocking later redo commands", async () => {
    const history = useCanvasHistory(vi.fn());
    const first = command();
    const second = command();
    first.redo.mockResolvedValue(false);
    history.push(first);
    history.push(second);
    await history.undo();
    await history.undo();
    await history.redo();
    await history.redo();
    expect(first.redo).toHaveBeenCalledTimes(1);
    expect(second.redo).toHaveBeenCalledTimes(1);
    expect(history.canRedo.value).toBe(false);
  });
  it("keeps uncertain offline or thrown commands retryable and reports failures once", async () => {
    const error = vi.fn();
    let offline = true;
    const history = useCanvasHistory(error, () => offline);
    const action = command();
    action.undo.mockResolvedValueOnce(false).mockRejectedValueOnce(new Error("uncertain"));
    history.push(action);
    await history.undo();
    expect(error).toHaveBeenCalledTimes(1);
    expect(history.canUndo.value).toBe(true);
    expect(history.canRedo.value).toBe(false);
    offline = false;
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
    history.push({ targets: () => [], undo: () => old.promise, redo: async () => true });
    const oldUndo = history.undo();
    history.clear();
    expect(history.canUndo.value).toBe(false);
    expect(history.canRedo.value).toBe(false);
    const newAction = {
      targets: () => [],
      undo: vi.fn(() => fresh.promise),
      redo: async () => true,
    };
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
    history.push({ targets: () => [], undo: () => old.promise, redo: async () => true });
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
  it("resolves command targets for each direction at the moment of execution", async () => {
    const prepare = vi.fn(async () => true);
    const history = useCanvasHistory(vi.fn(), () => false, prepare);
    let id = -1;
    const action = {
      ...command(),
      targets: (undo: boolean) => [{ id, ...(undo ? {} : { restoring: { roundId: 20 } }) }],
    };
    history.push(action);
    id = 42;
    await history.undo();
    expect(prepare).toHaveBeenLastCalledWith([{ id: 42 }]);
    await history.redo();
    expect(prepare).toHaveBeenLastCalledWith([{ id: 42, restoring: { roundId: 20 } }]);
  });
});
