import { createMockLive, withSetup } from "../setup";
import type { UseServerSearchReturn } from "../../shared/composables/useServerSearch";

const mockLive = createMockLive();

vi.mock("@shared/composables/useLive", () => ({
  useLive: () => mockLive,
}));

// Import after mock is set up
const { useServerSearch } = await import("../../shared/composables/useServerSearch");

describe("useServerSearch", () => {
  let ss: UseServerSearchReturn;
  let unmount: () => void;

  beforeEach(() => {
    vi.useFakeTimers();
    vi.clearAllMocks();
    const { result, app } = withSetup(() => useServerSearch());
    ss = result;
    unmount = () => app.unmount();
  });

  afterEach(() => {
    unmount();
    vi.useRealTimers();
  });

  describe("initial state", () => {
    it("starts with empty query", () => {
      expect(ss.query.value).toBe("");
    });

    it("starts with loading false", () => {
      expect(ss.loading.value).toBe(false);
    });
  });

  describe("search", () => {
    it("sets query immediately", () => {
      ss.search("hello");
      expect(ss.query.value).toBe("hello");
    });

    it("sets loading to true immediately", () => {
      ss.search("hello");
      expect(ss.loading.value).toBe(true);
    });

    it("pushes event after debounce", () => {
      ss.search("test");

      expect(mockLive.pushEvent).not.toHaveBeenCalled();

      vi.advanceTimersByTime(300);

      expect(mockLive.pushEvent).toHaveBeenCalledWith(
        "search",
        { query: "test" },
        expect.any(Function),
      );
    });

    it("debounces multiple rapid searches", () => {
      ss.search("a");
      ss.search("ab");
      ss.search("abc");

      vi.advanceTimersByTime(300);

      // Only the last call should fire
      expect(mockLive.pushEvent).toHaveBeenCalledTimes(1);
      expect(mockLive.pushEvent).toHaveBeenCalledWith(
        "search",
        { query: "abc" },
        expect.any(Function),
      );
    });

    it("resets loading when server callback fires", () => {
      ss.search("test");
      vi.advanceTimersByTime(300);

      expect(ss.loading.value).toBe(true);

      // Simulate server callback
      const callback = vi.mocked(mockLive.pushEvent).mock.calls[0][2] as () => void;
      callback();

      expect(ss.loading.value).toBe(false);
    });
  });

  describe("custom options", () => {
    it("uses custom event names", () => {
      const { result, app } = withSetup(() =>
        useServerSearch({
          searchEvent: "search_sheets",
          loadMoreEvent: "load_more_sheets",
        }),
      );

      result.search("query");
      vi.advanceTimersByTime(300);

      expect(mockLive.pushEvent).toHaveBeenCalledWith(
        "search_sheets",
        { query: "query" },
        expect.any(Function),
      );

      vi.clearAllMocks();
      result.loadMore();
      expect(mockLive.pushEvent).toHaveBeenCalledWith("load_more_sheets", {});

      app.unmount();
    });

    it("respects custom debounce timing", () => {
      const { result, app } = withSetup(() => useServerSearch({ debounceMs: 500 }));

      result.search("test");
      vi.advanceTimersByTime(300);
      expect(mockLive.pushEvent).not.toHaveBeenCalled();

      vi.advanceTimersByTime(200);
      expect(mockLive.pushEvent).toHaveBeenCalledTimes(1);

      app.unmount();
    });
  });

  describe("loadMore", () => {
    it("pushes load_more event with empty payload", () => {
      ss.loadMore();
      expect(mockLive.pushEvent).toHaveBeenCalledWith("load_more", {});
    });
  });

  describe("reset", () => {
    it("clears query and loading", () => {
      ss.search("hello");
      expect(ss.query.value).toBe("hello");
      expect(ss.loading.value).toBe(true);

      ss.reset();
      expect(ss.query.value).toBe("");
      expect(ss.loading.value).toBe(false);
    });
  });
});
