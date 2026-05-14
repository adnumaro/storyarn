import { nextTick } from "vue";
import { withSetup } from "../setup";
import { useResponsiveSidebar } from "../../shared/composables/useResponsiveSidebar";

type MediaQueryListener = (event: MediaQueryListEvent) => void;

function mockMatchMedia(initialMatches: boolean) {
  const listeners = new Set<MediaQueryListener>();
  const addEventListener = vi.fn((_event: "change", listener: MediaQueryListener) => {
    listeners.add(listener);
  });
  const removeEventListener = vi.fn((_event: "change", listener: MediaQueryListener) => {
    listeners.delete(listener);
  });

  Object.defineProperty(window, "matchMedia", {
    configurable: true,
    value: vi.fn((query: string) => {
      return {
        media: query,
        matches: initialMatches,
        addEventListener,
        removeEventListener,
      } as unknown as MediaQueryList;
    }),
  });

  return {
    dispatch(matches: boolean) {
      listeners.forEach((listener) => listener({ matches } as MediaQueryListEvent));
    },
  };
}

describe("useResponsiveSidebar", () => {
  it("opens automatically on desktop", () => {
    mockMatchMedia(true);

    const { result, app } = withSetup(() => useResponsiveSidebar());

    expect(result.sidebarOpen.value).toBe(true);
    app.unmount();
  });

  it("can be toggled on mobile", () => {
    mockMatchMedia(false);

    const { result, app } = withSetup(() => useResponsiveSidebar());
    expect(result.sidebarOpen.value).toBe(false);

    result.toggleSidebar();

    expect(result.sidebarOpen.value).toBe(true);
    app.unmount();
  });

  it("clears mobile state when desktop opens", async () => {
    const media = mockMatchMedia(false);

    const { result, app } = withSetup(() => useResponsiveSidebar());
    result.openSidebar();
    expect(result.mobileSidebarOpen.value).toBe(true);

    media.dispatch(true);
    await nextTick();

    expect(result.mobileSidebarOpen.value).toBe(false);
    expect(result.sidebarOpen.value).toBe(true);
    app.unmount();
  });
});
