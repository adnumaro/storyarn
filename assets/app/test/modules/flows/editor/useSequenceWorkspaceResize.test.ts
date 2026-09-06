import { mount } from "@vue/test-utils";
import { defineComponent, h, nextTick, ref } from "vue";
import { useSequenceWorkspaceResize } from "@modules/flows/editor/composables/useSequenceWorkspaceResize";

let notifyResize: ResizeObserverCallback;
const disconnect = vi.fn();

function pointer(target: EventTarget, type: string, clientX = 100, pointerId = 1, button = 0) {
  const event = new MouseEvent(type, { bubbles: true, cancelable: true, clientX, button });
  Object.defineProperty(event, "pointerId", { value: pointerId });
  target.dispatchEvent(event);
}

function harness(width = 1200) {
  vi.spyOn(HTMLElement.prototype, "getBoundingClientRect").mockReturnValue({ width } as DOMRect);
  const root = ref<HTMLElement | null>(null);
  const libraryOpen = ref(true);
  const inspectorOpen = ref(true);
  let api!: ReturnType<typeof useSequenceWorkspaceResize>;
  const wrapper = mount(
    defineComponent({
      setup() {
        api = useSequenceWorkspaceResize({
          root,
          libraryOpen: () => libraryOpen.value,
          inspectorOpen: () => inspectorOpen.value,
        });
        return () =>
          h(
            "section",
            { ref: root },
            ["library", "inspector"].map((name) => {
              const panel = name as "library" | "inspector";
              return h("button", {
                "data-panel": panel,
                onPointerdown: (event: PointerEvent) => api.startResize(event, panel),
                onKeydown: (event: KeyboardEvent) => api.onResizeKeydown(event, panel),
              });
            }),
          );
      },
    }),
    { attachTo: document.body },
  );
  return { api, wrapper, libraryOpen, inspectorOpen };
}

async function resizeRoot(width: number) {
  notifyResize([{ contentRect: { width } } as ResizeObserverEntry], {} as ResizeObserver);
  await nextTick();
}

describe("useSequenceWorkspaceResize", () => {
  beforeEach(() => {
    disconnect.mockClear();
    vi.stubGlobal(
      "ResizeObserver",
      class {
        constructor(callback: ResizeObserverCallback) {
          notifyResize = callback;
        }
        observe() {}
        disconnect = disconnect;
      },
    );
  });
  afterEach(() => {
    document.body.removeAttribute("style");
    vi.restoreAllMocks();
    vi.unstubAllGlobals();
  });

  it("starts at the requested widths and keeps the canvas available on smaller desktops", async () => {
    const { api, wrapper } = harness();
    await nextTick();
    expect(api.libraryWidth.value).toBe(240);
    expect(api.inspectorWidth.value).toBe(288);
    await resizeRoot(781);
    expect(api.compact.value).toBe(false);
    expect(api.libraryWidth.value).toBeGreaterThanOrEqual(180);
    expect(api.inspectorWidth.value).toBeGreaterThanOrEqual(240);
    expect(781 - api.libraryWidth.value - api.inspectorWidth.value - 12).toBeGreaterThanOrEqual(
      320,
    );
    await resizeRoot(1200);
    expect(api.libraryWidth.value).toBe(240);
    expect(api.inspectorWidth.value).toBe(288);
    wrapper.unmount();
  });

  it.each(["library", "inspector"] as const)(
    "resizes %s in the separator's physical direction and keeps it after release",
    async (panel) => {
      const { api, wrapper } = harness();
      await nextTick();
      document.body.style.setProperty("cursor", "help", "important");
      document.body.style.userSelect = "text";
      pointer(wrapper.get(`[data-panel="${panel}"]`).element, "pointerdown");
      expect(document.body.style.cursor).toBe("col-resize");
      expect(document.body.style.userSelect).toBe("none");
      pointer(window, "pointermove", 140);
      expect(api.libraryWidth.value).toBe(panel === "library" ? 280 : 240);
      expect(api.inspectorWidth.value).toBe(panel === "inspector" ? 248 : 288);
      pointer(window, "pointerup", 140);
      expect(api.resizing.value).toBeNull();
      expect(document.body.style.cursor).toBe("help");
      expect(document.body.style.getPropertyPriority("cursor")).toBe("important");
      expect(document.body.style.userSelect).toBe("text");
      pointer(window, "pointermove", 300);
      expect(api.libraryWidth.value).toBe(panel === "library" ? 280 : 240);
      wrapper.unmount();
    },
  );

  it("clamps to available canvas space and restores a folded panel's chosen width", async () => {
    const { api, wrapper, inspectorOpen } = harness(900);
    await nextTick();
    pointer(wrapper.get('[data-panel="library"]').element, "pointerdown");
    pointer(window, "pointerup", 1000);
    expect(api.libraryWidth.value).toBe(280);
    expect(api.inspectorWidth.value).toBe(288);
    inspectorOpen.value = false;
    await nextTick();
    expect(api.inspectorWidth.value).toBe(0);
    expect(api.libraryLimits.value.max).toBe(420);
    inspectorOpen.value = true;
    await nextTick();
    expect(api.inspectorWidth.value).toBe(288);
    expect(api.libraryWidth.value).toBe(280);
    wrapper.unmount();
  });

  it.each(["pointercancel", "escape", "blur", "fold", "compact", "unmount"])(
    "rolls back and clears browser styles on %s",
    async (reason) => {
      const { api, wrapper, libraryOpen } = harness();
      await nextTick();
      pointer(wrapper.get('[data-panel="library"]').element, "pointerdown");
      pointer(window, "pointermove", 200);
      expect(api.libraryWidth.value).toBe(340);
      if (reason === "pointercancel") pointer(window, "pointercancel");
      if (reason === "escape")
        window.dispatchEvent(new KeyboardEvent("keydown", { key: "Escape" }));
      if (reason === "blur") window.dispatchEvent(new Event("blur"));
      if (reason === "fold") {
        libraryOpen.value = false;
        await nextTick();
        libraryOpen.value = true;
      }
      if (reason === "compact") await resizeRoot(700);
      if (reason === "unmount") wrapper.unmount();
      await nextTick();
      expect(api.libraryWidth.value).toBe(240);
      expect(api.resizing.value).toBeNull();
      expect(document.body.style.cursor).toBe("");
      expect(document.body.style.userSelect).toBe("");
      pointer(window, "pointerup", 200);
      expect(api.libraryWidth.value).toBe(240);
      if (reason !== "unmount") wrapper.unmount();
      expect(disconnect).toHaveBeenCalled();
    },
  );

  it("supports arrows, Shift and Home/End without allowing graph shortcuts through", async () => {
    const { api, wrapper } = harness();
    await nextTick();
    const library = wrapper.get('[data-panel="library"]');
    const inspector = wrapper.get('[data-panel="inspector"]');
    await library.trigger("keydown", { key: "ArrowRight" });
    await library.trigger("keydown", { key: "ArrowRight", shiftKey: true, repeat: true });
    expect(api.libraryWidth.value).toBe(290);
    window.dispatchEvent(new KeyboardEvent("keyup", { key: "ArrowRight" }));
    await inspector.trigger("keydown", { key: "ArrowLeft" });
    window.dispatchEvent(new KeyboardEvent("keyup", { key: "ArrowLeft" }));
    expect(api.inspectorWidth.value).toBe(298);
    await library.trigger("keydown", { key: "Home" });
    window.dispatchEvent(new KeyboardEvent("keyup", { key: "Home" }));
    expect(api.libraryWidth.value).toBe(180);
    await library.trigger("keydown", { key: "End" });
    window.dispatchEvent(new KeyboardEvent("keyup", { key: "End" }));
    expect(api.libraryWidth.value).toBe(420);
    const event = new KeyboardEvent("keydown", {
      key: "ArrowRight",
      bubbles: true,
      cancelable: true,
    });
    const bubbled = vi.fn();
    window.addEventListener("keydown", bubbled);
    inspector.element.dispatchEvent(event);
    expect(event.defaultPrevented).toBe(true);
    expect(bubbled).not.toHaveBeenCalled();
    window.removeEventListener("keydown", bubbled);
    wrapper.unmount();
  });

  it("cancels an unfinished keyboard resize with Escape", async () => {
    const { api, wrapper } = harness();
    await nextTick();
    await wrapper.get('[data-panel="library"]').trigger("keydown", { key: "End" });
    expect(api.libraryWidth.value).toBe(420);
    window.dispatchEvent(new KeyboardEvent("keydown", { key: "Escape" }));
    window.dispatchEvent(new KeyboardEvent("keyup", { key: "End" }));
    expect(api.libraryWidth.value).toBe(240);
    wrapper.unmount();
  });

  it("ignores unrelated pointers and disables resizing in tab layout", async () => {
    const { api, wrapper } = harness();
    await nextTick();
    const library = wrapper.get('[data-panel="library"]');
    pointer(library.element, "pointerdown", 100, 1, 2);
    expect(api.resizing.value).toBeNull();
    pointer(library.element, "pointerdown");
    pointer(window, "pointermove", 200, 2);
    pointer(window, "pointerup", 200, 2);
    expect(api.libraryWidth.value).toBe(240);
    expect(api.resizing.value).toBe("library");
    pointer(window, "pointerup", 100);
    await resizeRoot(780);
    expect(api.compact.value).toBe(true);
    pointer(library.element, "pointerdown");
    await library.trigger("keydown", { key: "End" });
    expect(api.resizing.value).toBeNull();
    expect(api.libraryWidth.value).toBe(240);
    wrapper.unmount();
  });
});
