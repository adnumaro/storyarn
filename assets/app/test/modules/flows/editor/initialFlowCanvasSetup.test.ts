import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { AreaExtensions } from "rete-area-plugin";

vi.mock("rete-area-plugin", async (importOriginal) => {
  const original = await importOriginal<typeof import("rete-area-plugin")>();
  return {
    ...original,
    AreaExtensions: {
      ...original.AreaExtensions,
      selector: vi.fn(() => ({})),
      selectableNodes: vi.fn(() => ({ select: vi.fn(), unselect: vi.fn() })),
      accumulateOnCtrl: vi.fn(),
      zoomAt: vi.fn().mockResolvedValue(undefined),
    },
  };
});
const { finalizeSetup } = await import("@modules/flows/editor/services/reteSetup");

let nextFrame: FrameRequestCallback;
beforeEach(() => {
  vi.clearAllMocks();
  vi.useFakeTimers();
  vi.stubGlobal("requestAnimationFrame", (callback: FrameRequestCallback) => {
    nextFrame = callback;
    return 1;
  });
});
afterEach(() => {
  vi.useRealTimers();
  vi.unstubAllGlobals();
});

function beginSetup() {
  const area = { addPipe: vi.fn() };
  const editor = { getNodes: vi.fn(() => []) };
  let destroyed = false;
  let ready = false;
  const promise = finalizeSetup(
    area as never,
    editor as never,
    true,
    undefined,
    () => destroyed,
  ).then(() => {
    ready = true;
  });
  return {
    destroy: () => {
      destroyed = true;
    },
    promise,
    ready: () => ready,
  };
}

describe("initial canvas readiness", () => {
  it("waits for both viewport fit passes before declaring the canvas ready", async () => {
    const setup = beginSetup();
    await Promise.resolve();
    expect(setup.ready()).toBe(false);
    await vi.advanceTimersByTimeAsync(100);
    expect(AreaExtensions.zoomAt).toHaveBeenCalledTimes(1);
    expect(setup.ready()).toBe(false);
    nextFrame(0);
    await setup.promise;
    expect(AreaExtensions.zoomAt).toHaveBeenCalledTimes(2);
    expect(setup.ready()).toBe(true);
  });

  it("settles without fitting when destroyed during the initial delay", async () => {
    const setup = beginSetup();
    setup.destroy();
    await vi.advanceTimersByTimeAsync(100);
    await setup.promise;
    expect(AreaExtensions.zoomAt).not.toHaveBeenCalled();
    expect(setup.ready()).toBe(true);
  });

  it("settles without the second fit when destroyed before its animation frame", async () => {
    const setup = beginSetup();
    await vi.advanceTimersByTimeAsync(100);
    setup.destroy();
    nextFrame(0);
    await setup.promise;
    expect(AreaExtensions.zoomAt).toHaveBeenCalledTimes(1);
    expect(setup.ready()).toBe(true);
  });
});
