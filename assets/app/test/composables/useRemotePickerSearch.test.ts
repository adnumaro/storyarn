import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { createMockLive, withSetup } from "../setup";

const mockLive = createMockLive();

vi.mock("@shared/composables/useLive", () => ({
  useLive: () => mockLive,
}));

const { useRemotePickerSearch } = await import("../../shared/composables/useRemotePickerSearch");

describe("useRemotePickerSearch", () => {
  beforeEach(() => {
    vi.useFakeTimers();
    vi.clearAllMocks();
    vi.mocked(mockLive.handleEvent).mockReturnValue(42);
  });

  afterEach(() => {
    vi.useRealTimers();
  });

  function setup() {
    return withSetup(() =>
      useRemotePickerSearch<{ id: number }>({
        enabled: true,
        event: "search_assets",
        limit: 10,
        debounceMs: 0,
        responseTimeoutMs: 100,
      }),
    );
  }

  it("unregisters its LiveView result handler on unmount", () => {
    const { app } = setup();

    expect(mockLive.handleEvent).toHaveBeenCalledOnce();
    app.unmount();

    expect(mockLive.removeHandleEvent).toHaveBeenCalledWith(42);
  });

  it("stops searching when a response is dropped", () => {
    const { result, app } = setup();

    vi.advanceTimersByTime(0);
    expect(result.isSearching.value).toBe(true);

    vi.advanceTimersByTime(100);
    expect(result.isSearching.value).toBe(false);

    app.unmount();
  });

  it("stops searching when pushing the request fails", () => {
    const { result, app } = setup();

    vi.advanceTimersByTime(0);
    const onError = vi.mocked(mockLive.pushEvent).mock.calls[0]?.[3];
    onError?.(new Error("disconnected"));

    expect(result.isSearching.value).toBe(false);
    app.unmount();
  });
});
