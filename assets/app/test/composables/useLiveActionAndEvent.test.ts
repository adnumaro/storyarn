import { afterEach, describe, expect, it, vi } from "vitest";
import { useLiveAction } from "@shared/composables/useLiveAction";
import { useLiveEvent } from "@shared/composables/useLiveEvent";
import { createMockLive, createPromiseMockLive, withSetup } from "../setup";

afterEach(() => {
  vi.useRealTimers();
});

describe("useLiveAction", () => {
  it("settles on the reply", async () => {
    const live = createPromiseMockLive(
      {},
      vi.fn(() => Promise.resolve({ ok: true })),
    );
    const onReply = vi.fn();
    const { result, app } = withSetup(() => useLiveAction(), { live });

    result.push("save_entry", { id: 1 }, { onReply });
    expect(result.pending.value).toBe(true);
    await Promise.resolve();
    await Promise.resolve();

    expect(result.pending.value).toBe(false);
    expect(onReply).toHaveBeenCalledWith({ ok: true });
    app.unmount();
  });

  it("settles when the transport drops the push", async () => {
    const live = createPromiseMockLive(
      {},
      vi.fn(() => Promise.reject(new Error("disconnected"))),
    );
    const onError = vi.fn();
    vi.spyOn(console, "warn").mockImplementation(() => {});
    const { result, app } = withSetup(() => useLiveAction(), { live });

    result.push("sync_glossary", {}, { onError });
    await Promise.resolve();
    await Promise.resolve();

    expect(result.pending.value).toBe(false);
    expect(onError).toHaveBeenCalledOnce();
    app.unmount();
  });

  it("settles after its timeout when no reply ever comes, and ignores a late reply", () => {
    vi.useFakeTimers();
    let reply!: (value: Record<string, unknown>) => void;
    const live = createPromiseMockLive(
      {},
      vi.fn(() => new Promise<Record<string, unknown>>((resolve) => (reply = resolve))),
    );
    const onReply = vi.fn();
    const onError = vi.fn();
    const { result, app } = withSetup(() => useLiveAction(undefined, 1_000), { live });

    result.push("translate_with_deepl", {}, { onReply, onError });
    vi.advanceTimersByTime(1_000);

    expect(result.pending.value).toBe(false);
    expect(onError).toHaveBeenCalledOnce();

    reply({ ok: true });
    expect(onReply).not.toHaveBeenCalled();
    app.unmount();
  });
});

describe("useLiveEvent", () => {
  it("removes its handler when the component unmounts", () => {
    const live = createMockLive();
    vi.mocked(live.handleEvent).mockReturnValue(42);
    const handler = vi.fn();
    const { app } = withSetup(() => useLiveEvent("version_created", handler), { live });

    expect(live.handleEvent).toHaveBeenCalledWith("version_created", handler);
    expect(live.removeHandleEvent).not.toHaveBeenCalled();

    app.unmount();

    expect(live.removeHandleEvent).toHaveBeenCalledWith(42);
  });

  it("registers one handler per mount, so opening a panel twice does not double it", () => {
    const live = createMockLive();
    let next = 0;
    vi.mocked(live.handleEvent).mockImplementation(() => ++next);

    const first = withSetup(() => useLiveEvent("versions_loaded", vi.fn()), { live });
    first.app.unmount();
    const second = withSetup(() => useLiveEvent("versions_loaded", vi.fn()), { live });

    expect(live.handleEvent).toHaveBeenCalledTimes(2);
    expect(live.removeHandleEvent).toHaveBeenCalledWith(1);
    second.app.unmount();
    expect(live.removeHandleEvent).toHaveBeenCalledWith(2);
  });
});
