import { afterEach, describe, expect, it, vi } from "vitest";
import { defineComponent, h, nextTick, reactive, ref } from "vue";
import { mount, type VueWrapper } from "@vue/test-utils";
import BrainstormingCanvas from "@modules/ideation/components/BrainstormingCanvas.vue";
import CanvasConnectionTools from "@modules/ideation/components/CanvasConnectionTools.vue";
import { idea } from "./fixtures";

let view: { x: number; y: number; zoom: number; width: number; height: number };
vi.mock("@modules/ideation/composables/useCanvasViewport", () => ({
  useCanvasViewport: () => {
    view = reactive({ x: 0, y: 0, zoom: 1, width: 1000, height: 800 });
    return {
      view,
      space: ref(false),
      transform: ref(""),
      world: (x: number, y: number) => ({ x, y }),
      zoomTo: vi.fn(),
      wheel: vi.fn(),
      fit: vi.fn(),
    };
  },
}));
const NoteStub = defineComponent({
  props: ["note", "editing"],
  setup: (props) => () =>
    h("article", { id: `canvas-note-${props.note.id}`, tabindex: 0 }, [
      h("div", { contenteditable: String(props.editing) }, "Text"),
    ]),
});
const mounted: VueWrapper[] = [];
function canvas(props = {}) {
  const wrapper = mount(BrainstormingCanvas, {
    attachTo: document.body,
    props: {
      notes: [
        idea({ canvas: { x: 10, y: 20, width: 280, links: [11] } }),
        idea({ id: 11, canvas: { x: 500, y: 20, width: 280 } }),
        idea({ id: 12, canvas: { x: 500, y: 400, width: 280 } }),
      ],
      selectedIds: [10, 11, 12],
      editingId: null,
      permissions: { edit: true, create: true },
      noteKey: (id: number) => String(id),
      historyState: { canUndo: true, canRedo: true, busy: false },
      members: [],
      statuses: {},
      collaboration: { context: { epoch: "a", session_id: 1 }, cursors: false },
      ...props,
    },
    slots: { selection: ({ connectionTools }) => h(CanvasConnectionTools, connectionTools) },
    global: { stubs: { CanvasNote: NoteStub, CanvasCursors: true } },
  });
  Object.assign(wrapper.element, {
    setPointerCapture: vi.fn(),
    hasPointerCapture: () => false,
    releasePointerCapture: vi.fn(),
  });
  mounted.push(wrapper);
  return wrapper;
}
function key(
  wrapper: VueWrapper,
  name: string,
  options: KeyboardEventInit = {},
  target = wrapper.element,
) {
  const event = new KeyboardEvent("keydown", {
    key: name,
    bubbles: true,
    cancelable: true,
    ...options,
  });
  target.dispatchEvent(event);
  return event;
}
afterEach(() => {
  for (const wrapper of mounted.splice(0)) wrapper.unmount();
  vi.restoreAllMocks();
});

describe("canvas connection shortcuts", () => {
  it("connects from the highlighted origin and disconnects only the visible selection", () => {
    const wrapper = canvas({ selectedIds: [12, 10, 11, 999] });
    expect(wrapper.find("#connection-origin-badge-12").exists()).toBe(true);
    key(wrapper, "l");
    key(wrapper, "L", { shiftKey: true });
    expect(wrapper.emitted("connectSelection")).toEqual([
      [[12, 10, 11], true],
      [[12, 10, 11], false],
    ]);
    expect(wrapper.emitted("connect")).toBeUndefined();
  });

  it("changes the origin without losing selection or moving the contextual toolbar", async () => {
    const wrapper = canvas();
    const tools = wrapper.getComponent(CanvasConnectionTools);
    tools.vm.$emit("origin", 11);
    await nextTick();
    expect(wrapper.find("#connection-origin-badge-11").exists()).toBe(true);
    expect(wrapper.emitted("select")).toBeUndefined();
    expect(tools.props("selection").map((note: { id: number }) => note.id)).toEqual([11, 10, 12]);
    key(wrapper, "l");
    expect(wrapper.emitted("connectSelection")).toEqual([[[11, 10, 12], true]]);
    await wrapper.setProps({ selectedIds: [10, 12] });
    expect(wrapper.find("#connection-origin-badge-10").exists()).toBe(true);
  });

  it.each([{ selectedIds: [] }, { selectedIds: [10] }])(
    "keeps L as the manual tool with selection %j",
    async ({ selectedIds }) => {
      const wrapper = canvas({ selectedIds });
      key(wrapper, "l");
      await nextTick();
      expect(wrapper.text()).toContain("first note");
      expect(wrapper.emitted("connectSelection")).toBeUndefined();
    },
  );

  it("leaves modified L, IME and repeated presses untouched", () => {
    const wrapper = canvas();
    for (const options of [
      { isComposing: true },
      { repeat: true },
      { ctrlKey: true },
      { metaKey: true },
      { altKey: true },
    ]) {
      key(wrapper, "l", options);
    }
    expect(wrapper.emitted("connectSelection")).toBeUndefined();
  });

  it.each([
    { permissions: { edit: false, create: false } },
    { historyState: { canUndo: true, canRedo: true, busy: true } },
  ])("blocks every connection write when unavailable: %j", (props) => {
    const wrapper = canvas(props);
    key(wrapper, "l");
    key(wrapper, "L", { shiftKey: true });
    key(wrapper, "ArrowRight", { altKey: true, shiftKey: true });
    expect(wrapper.emitted("connectSelection")).toBeUndefined();
    expect(wrapper.emitted("addConnected")).toBeUndefined();
  });

  it("does not intercept note text editing, IME or unrelated Alt-arrow navigation", () => {
    const wrapper = canvas({ editingId: 10 });
    const text = wrapper.get('[contenteditable="true"]').element;
    expect(key(wrapper, "l", {}, text).defaultPrevented).toBe(false);
    expect(
      key(wrapper, "ArrowRight", { altKey: true, shiftKey: true }, text).defaultPrevented,
    ).toBe(false);
    expect(key(wrapper, "ArrowRight", { altKey: true }).defaultPrevented).toBe(false);
    expect(
      key(wrapper, "ArrowRight", { altKey: true, shiftKey: true, isComposing: true })
        .defaultPrevented,
    ).toBe(false);
    expect(wrapper.emitted("connectSelection")).toBeUndefined();
    expect(wrapper.emitted("addConnected")).toBeUndefined();
    expect(wrapper.emitted("move")).toBeUndefined();
  });

  it("preserves existing-note connections when contributions close but prevents new destinations", () => {
    const wrapper = canvas({ permissions: { edit: true, create: false } });
    key(wrapper, "l");
    key(wrapper, "ArrowRight", { altKey: true, shiftKey: true });
    expect(wrapper.emitted("connectSelection")).toHaveLength(1);
    expect(wrapper.emitted("addConnected")).toBeUndefined();
  });

  it("creates one connected note below all selected measured bounds, independent of zoom", async () => {
    vi.spyOn(HTMLElement.prototype, "offsetHeight", "get").mockImplementation(
      function (this: HTMLElement) {
        return this.id === "canvas-note-10" ? 700 : 260;
      },
    );
    const wrapper = canvas();
    await nextTick();
    await nextTick();
    view.zoom = 0.5;
    view.x = -300;
    view.y = 200;
    key(wrapper, "ArrowDown", { altKey: true, shiftKey: true });
    expect(wrapper.emitted("addConnected")).toEqual([[[10, 11, 12], { x: 255, y: 784 }]]);
    expect(wrapper.emitted("move")).toBeUndefined();
    key(wrapper, "ArrowDown", { altKey: true, shiftKey: true, repeat: true });
    expect(wrapper.emitted("addConnected")).toHaveLength(1);
  });

  it("exposes the same connection actions to the contextual menu", () => {
    const wrapper = canvas();
    const tools = wrapper.getComponent(CanvasConnectionTools);
    expect(tools.props("hasConnections")).toBe(true);
    tools.vm.$emit("connect");
    tools.vm.$emit("disconnect");
    tools.vm.$emit("create", "left");
    expect(wrapper.emitted("connectSelection")).toEqual([
      [[10, 11, 12], true],
      [[10, 11, 12], false],
    ]);
    expect(wrapper.emitted("addConnected")?.[0][0]).toEqual([10, 11, 12]);
    const created = wrapper.emitted("addConnected")!;
    expect((created[0][1] as { x: number }).x).toBe(-334);
  });

  it("does not write connections during a marquee or a note drag", async () => {
    const wrapper = canvas();
    for (const target of [wrapper.element, wrapper.get('[data-note-id="10"]').element]) {
      Object.assign(target, { setPointerCapture: vi.fn(), hasPointerCapture: () => false });
      target.dispatchEvent(
        new PointerEvent("pointerdown", {
          bubbles: true,
          button: 0,
          pointerId: 1,
          clientX: 20,
          clientY: 30,
        }),
      );
      key(wrapper, "l");
      key(wrapper, "ArrowDown", { altKey: true, shiftKey: true });
      expect(wrapper.emitted("connectSelection")).toBeUndefined();
      expect(wrapper.emitted("addConnected")).toBeUndefined();
      target.dispatchEvent(new PointerEvent("pointercancel", { bubbles: true, pointerId: 1 }));
      await nextTick();
    }
    key(wrapper, "l");
    expect(wrapper.emitted("connectSelection")).toHaveLength(1);
  });

  it("draws arrows at the visible note edges and exposes minimal reveal for a new note", async () => {
    const wrapper = canvas({ selectedIds: [10] });
    await nextTick();
    await nextTick();
    const line = wrapper.get("svg line");
    expect(line.attributes("x1")).toBe("296");
    expect(line.attributes("x2")).toBe("494");
    expect(line.attributes("marker-end")).toBe("url(#brainstorming-connection-arrow)");
    await (
      wrapper.vm as unknown as { revealNote: (note: ReturnType<typeof idea>) => Promise<void> }
    ).revealNote(idea({ id: 20, canvas: { x: 1000, y: 100, width: 280 } }));
    expect(view.x).toBe(-344);
    expect(view.y).toBe(0);
    expect(view.zoom).toBe(1);
  });
});
