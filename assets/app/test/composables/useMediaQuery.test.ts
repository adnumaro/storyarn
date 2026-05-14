import { nextTick } from "vue";
import { withSetup } from "../setup";
import { useMediaQuery } from "../../shared/composables/useMediaQuery";

type MediaQueryListener = (event: MediaQueryListEvent) => void;

function mockMatchMedia(initialMatches: boolean) {
  const listeners = new Set<MediaQueryListener>();
  const addEventListener = vi.fn((_event: "change", listener: MediaQueryListener) => {
    listeners.add(listener);
  });
  const removeEventListener = vi.fn((_event: "change", listener: MediaQueryListener) => {
    listeners.delete(listener);
  });

  const matchMedia = vi.fn((query: string) => {
    return {
      media: query,
      matches: initialMatches,
      addEventListener,
      removeEventListener,
    } as unknown as MediaQueryList;
  });

  Object.defineProperty(window, "matchMedia", {
    configurable: true,
    value: matchMedia,
  });

  return {
    addEventListener,
    matchMedia,
    removeEventListener,
    dispatch(matches: boolean) {
      listeners.forEach((listener) => listener({ matches } as MediaQueryListEvent));
    },
  };
}

describe("useMediaQuery", () => {
  it("reads the current media query state on mount", () => {
    const media = mockMatchMedia(true);

    const { result, app } = withSetup(() => useMediaQuery("(min-width: 1024px)"));

    expect(media.matchMedia).toHaveBeenCalledWith("(min-width: 1024px)");
    expect(result.value).toBe(true);
    app.unmount();
  });

  it("updates when the media query changes", async () => {
    const media = mockMatchMedia(false);

    const { result, app } = withSetup(() => useMediaQuery("(min-width: 1024px)"));
    expect(result.value).toBe(false);

    media.dispatch(true);
    await nextTick();

    expect(result.value).toBe(true);
    app.unmount();
  });

  it("removes the media query listener on unmount", () => {
    const media = mockMatchMedia(false);

    const { app } = withSetup(() => useMediaQuery("(min-width: 1024px)"));
    app.unmount();

    expect(media.removeEventListener).toHaveBeenCalledOnce();
  });
});
