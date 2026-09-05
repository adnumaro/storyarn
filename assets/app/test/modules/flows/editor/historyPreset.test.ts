import {
  HistoryCommandQueue,
  SequenceCompositionAction,
  sequenceCompositionCoalesceTarget,
  type HistoryHookProxy,
  type SequenceCompositionSnapshot,
} from "@modules/flows/editor/services/historyPreset";

function snapshot(sourceId: number | null): SequenceCompositionSnapshot {
  return {
    version: 1,
    owner_id: 42,
    flow_id: 7,
    owner_type: "dialogue",
    composition_source_id: sourceId,
    position_x: 0,
    position_y: 0,
    config: null,
    visual_layers: [],
  };
}

describe("SequenceCompositionAction", () => {
  it("restores the previous and current snapshots through the LiveView contract", async () => {
    const pushEvent = vi.fn(
      (
        _event: string,
        _payload: Record<string, unknown>,
        callback?: (reply: Record<string, unknown>) => void,
      ) => callback?.({}),
    );
    const hook = { pushEvent, invalidateHistory: vi.fn() } as unknown as HistoryHookProxy;
    const previous = snapshot(10);
    const current = snapshot(20);
    const action = new SequenceCompositionAction(hook, 42, "composition-source", previous, current);

    await action.undo();
    await action.redo();

    expect(pushEvent).toHaveBeenNthCalledWith(
      1,
      "restore_sequence_composition",
      {
        id: 42,
        snapshot: previous,
        expected_current: current,
      },
      expect.any(Function),
      expect.any(Function),
    );
    expect(pushEvent).toHaveBeenNthCalledWith(
      2,
      "restore_sequence_composition",
      {
        id: 42,
        snapshot: current,
        expected_current: previous,
      },
      expect.any(Function),
      expect.any(Function),
    );
  });

  it("waits for the LiveView acknowledgement before completing", async () => {
    let acknowledge: ((reply: Record<string, unknown>) => void) | undefined;
    const pushEvent = vi.fn(
      (
        _event: string,
        _payload: Record<string, unknown>,
        callback?: (reply: Record<string, unknown>) => void,
      ) => {
        acknowledge = callback;
      },
    );
    const hook = { pushEvent, invalidateHistory: vi.fn() } as unknown as HistoryHookProxy;
    const action = new SequenceCompositionAction(
      hook,
      42,
      "composition-source",
      snapshot(10),
      snapshot(20),
    );
    let completed = false;

    const undo = action.undo().then(() => {
      completed = true;
    });
    await Promise.resolve();
    expect(completed).toBe(false);

    acknowledge?.({});
    await undo;
    expect(completed).toBe(true);
  });

  it("invalidates history after a transport failure and ignores a late acknowledgement", async () => {
    const invalidateHistory = vi.fn();
    const pushEvent = vi.fn(
      (
        _event: string,
        _payload: Record<string, unknown>,
        callback?: (reply: Record<string, unknown>) => void,
        onError?: (error: unknown) => void,
      ) => {
        onError?.(new Error("disconnected"));
        callback?.({});
      },
    );
    const hook = { pushEvent, invalidateHistory } as unknown as HistoryHookProxy;
    const action = new SequenceCompositionAction(
      hook,
      42,
      "composition-source",
      snapshot(10),
      snapshot(20),
    );

    await expect(action.undo()).resolves.toBeUndefined();
    expect(invalidateHistory).toHaveBeenCalledOnce();
  });
});

describe("sequence composition history coalescing", () => {
  it("coalesces only a continuous top action", () => {
    const hook = { pushEvent: vi.fn(), invalidateHistory: vi.fn() } as unknown as HistoryHookProxy;
    const first = new SequenceCompositionAction(
      hook,
      42,
      "layer:hero:x",
      snapshot(10),
      snapshot(20),
    );
    const intervening = new SequenceCompositionAction(
      hook,
      42,
      "layer:room:opacity",
      snapshot(20),
      snapshot(30),
    );

    expect(
      sequenceCompositionCoalesceTarget(
        [{ action: first, time: 1 }],
        42,
        "layer:hero:x",
        snapshot(20),
      )?.action,
    ).toBe(first);
    expect(
      sequenceCompositionCoalesceTarget(
        [
          { action: intervening, time: 2 },
          { action: first, time: 1 },
        ],
        42,
        "layer:hero:x",
        snapshot(20),
      ),
    ).toBeNull();
    expect(
      sequenceCompositionCoalesceTarget(
        [{ action: first, time: 1 }],
        42,
        "layer:hero:x",
        snapshot(99),
      ),
    ).toBeNull();
  });
});

describe("HistoryCommandQueue", () => {
  it("serializes rapid undo commands until each action is acknowledged", async () => {
    let acknowledgeFirst!: () => void;
    const first = new Promise<void>((resolve) => {
      acknowledgeFirst = resolve;
    });
    const undo = vi.fn().mockReturnValueOnce(first).mockResolvedValue(undefined);
    const history = { undo, redo: vi.fn().mockResolvedValue(undefined), clear: vi.fn() };
    const queue = new HistoryCommandQueue(() => history);

    const firstUndo = queue.undo();
    const secondUndo = queue.undo();
    await Promise.resolve();
    expect(undo).toHaveBeenCalledTimes(1);

    acknowledgeFirst();
    await Promise.all([firstUndo, secondUndo]);
    expect(undo).toHaveBeenCalledTimes(2);
  });

  it("waits for an in-flight action before clearing and skips older queued commands", async () => {
    let acknowledge!: () => void;
    const inFlight = new Promise<void>((resolve) => {
      acknowledge = resolve;
    });
    const undo = vi.fn().mockReturnValue(inFlight);
    const clear = vi.fn();
    const history = { undo, redo: vi.fn().mockResolvedValue(undefined), clear };
    const queue = new HistoryCommandQueue(() => history);

    const firstUndo = queue.undo();
    await Promise.resolve();
    const staleUndo = queue.undo();
    const invalidation = queue.invalidate();

    expect(clear).not.toHaveBeenCalled();
    acknowledge();
    await Promise.all([firstUndo, staleUndo, invalidation]);

    expect(undo).toHaveBeenCalledOnce();
    expect(clear).toHaveBeenCalledOnce();
  });
});
