import { afterEach, describe, expect, it, vi } from "vitest";
import { defineComponent, h, nextTick, reactive, ref } from "vue";
import { mount, type VueWrapper } from "@vue/test-utils";
import BrainstormingCanvas from "@modules/ideation/components/BrainstormingCanvas.vue";
import CanvasConnectionTools from "@modules/ideation/components/CanvasConnectionTools.vue";
import { idea, ideaGroup } from "./fixtures";

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
  it("connects and disconnects the visible selection without adding an origin badge", () => {
    const wrapper = canvas({ selectedIds: [12, 10, 11, 999] });
    expect(wrapper.find("#connection-origin-badge-12").exists()).toBe(false);
    key(wrapper, "l");
    key(wrapper, "L", { shiftKey: true });
    expect(wrapper.emitted("connectSelection")).toEqual([
      [[12, 10, 11], true],
      [[12, 10, 11], false],
    ]);
    expect(wrapper.emitted("connect")).toBeUndefined();
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
    expect(wrapper.emitted("addConnected")).toEqual([[[10, 11, 12], { x: 315, y: 784 }]]);
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
    expect((created[0][1] as { x: number }).x).toBe(-214);
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
    expect(line.attributes("x1")).toBe("294");
    expect(line.attributes("x2")).toBe("496");
    expect(line.attributes("marker-end")).toBe("url(#brainstorming-connection-arrow)");
    await (
      wrapper.vm as unknown as { revealNote: (note: ReturnType<typeof idea>) => Promise<void> }
    ).revealNote(idea({ id: 20, canvas: { x: 1000, y: 100, width: 280 } }));
    expect(view.x).toBe(-344);
    expect(view.y).toBe(0);
    expect(view.zoom).toBe(1);
  });
});

async function pointer(target: Element, type: string, point: { x: number; y: number }) {
  target.dispatchEvent(
    new PointerEvent(type, {
      bubbles: true,
      cancelable: true,
      pointerId: 9,
      button: 0,
      clientX: point.x,
      clientY: point.y,
    }),
  );
  await nextTick();
}

function dragSurface(wrapper: VueWrapper, id: number) {
  const element = wrapper.get(`[data-note-id="${id}"]`).element;
  Object.assign(element, { setPointerCapture: vi.fn(), hasPointerCapture: () => false });
  return element;
}

describe("direct connection manipulation", () => {
  it("places selectable connections above group frames and below notes", async () => {
    const wrapper = canvas({
      selectedIds: [],
      groupState: {
        groups: [ideaGroup()],
        selectedId: null,
        save: vi.fn(async () => true),
        move: vi.fn(async () => undefined),
      },
    });
    await nextTick();
    const frame = wrapper.get("#canvas-group-40").element;
    const svg = wrapper.get("#canvas-connection-10-11").element.closest("svg")!;
    const note = wrapper.get('[data-note-id="10"]').element;
    expect(frame.parentElement).toBe(svg.parentElement);
    const layers = [...frame.parentElement!.children];
    expect(layers.indexOf(frame)).toBeLessThan(layers.indexOf(svg));
    expect(layers.indexOf(svg)).toBeLessThan(layers.indexOf(note));
    await wrapper.get("#canvas-connection-10-11").trigger("click");
    expect(wrapper.find("#brainstorming-connection-toolbar").exists()).toBe(true);
  });

  it("keeps connection actions inside the viewport when a long line's midpoint is off screen", async () => {
    const wrapper = canvas({
      selectedIds: [],
      notes: [
        idea({ canvas: { x: 100, y: 0, width: 280, links: [11] } }),
        idea({ id: 11, canvas: { x: 100, y: 2200, width: 280 } }),
      ],
    });
    await nextTick();
    await wrapper.get("#canvas-connection-10-11").trigger("click");
    const toolbar = wrapper.get("#brainstorming-connection-toolbar").element as HTMLElement;
    expect(Number.parseFloat(toolbar.style.top)).toBeLessThanOrEqual(view.height - 80);
    view.height = 360;
    await nextTick();
    expect(Number.parseFloat(toolbar.style.top)).toBeLessThanOrEqual(view.height - 80);
    view.y = -2200;
    await nextTick();
    expect(Number.parseFloat(toolbar.style.top)).toBeGreaterThanOrEqual(48);
  });

  it("selects an association, changes its direction and deletes all reciprocal records together", async () => {
    const wrapper = canvas({
      selectedIds: [],
      notes: [
        idea({ canvas: { x: 10, y: 20, width: 280, links: [11] } }),
        idea({ id: 11, canvas: { x: 500, y: 20, width: 280, links: [10] } }),
      ],
    });
    await nextTick();
    expect(wrapper.findAll("[data-connection-source]")).toHaveLength(1);
    const hit = wrapper.get("#canvas-connection-10-11");
    expect(hit.attributes("role")).toBe("button");
    expect(hit.attributes("stroke-width")).toBe("12");
    await hit.trigger("keydown", { key: "Enter" });
    expect(wrapper.emitted("select")?.at(-1)).toEqual([[]]);
    expect(wrapper.get("#brainstorming-connection-toolbar").attributes("role")).toBe("toolbar");
    await wrapper.get("#connection-direction-none").trigger("click");
    expect(wrapper.emitted("changeConnections")).toEqual([
      [
        [
          { source_id: 10, target_id: 11, connected: true, direction: "none" },
          { source_id: 11, target_id: 10, connected: false, direction: "forward" },
        ],
      ],
    ]);
    key(wrapper, "Delete");
    expect(wrapper.emitted("changeConnections")?.at(-1)).toEqual([
      [
        { source_id: 10, target_id: 11, connected: false, direction: "forward" },
        { source_id: 11, target_id: 10, connected: false, direction: "forward" },
      ],
    ]);
    key(wrapper, "z", { metaKey: true });
    expect(wrapper.emitted("undo")).toHaveLength(1);
    expect(wrapper.emitted("remove")).toBeUndefined();
  });

  it("previews the connection tool and highlights the destination before committing", async () => {
    const wrapper = canvas({ selectedIds: [] });
    key(wrapper, "l");
    await nextTick();
    await pointer(dragSurface(wrapper, 10), "pointerdown", { x: 40, y: 40 });
    await pointer(wrapper.element, "pointermove", { x: 350, y: 60 });
    expect(wrapper.find("#brainstorming-connection-preview").exists()).toBe(true);
    await pointer(wrapper.element, "pointermove", { x: 540, y: 40 });
    expect(wrapper.find("#connection-target-11").exists()).toBe(true);
    expect(wrapper.emitted("connect")).toBeUndefined();
    key(wrapper, "Escape");
    await nextTick();
    expect(wrapper.find("#brainstorming-connection-preview").exists()).toBe(false);
    expect(wrapper.find("#connection-target-11").exists()).toBe(false);
  });

  it("connects a dragged note on a target and returns the note to its original position", async () => {
    const wrapper = canvas({ selectedIds: [10] });
    const source = dragSurface(wrapper, 10);
    await pointer(source, "pointerdown", { x: 40, y: 40 });
    // Events still target the source under pointer capture, not the destination.
    await pointer(source, "pointermove", { x: 540, y: 40 });
    expect(wrapper.find("#connection-target-11").exists()).toBe(true);
    expect(wrapper.find("#brainstorming-connection-preview").exists()).toBe(true);
    await pointer(source, "pointerup", { x: 540, y: 40 });
    expect(wrapper.emitted("connect")).toEqual([[10, 11, true]]);
    expect(wrapper.emitted("move")).toBeUndefined();
    expect(wrapper.get('[data-note-id="10"]').attributes("style")).toContain(
      "translate(10px, 20px)",
    );
    expect(wrapper.find("#connection-target-11").exists()).toBe(false);
  });

  it("cancels a pending drop connection with Escape without moving either note", async () => {
    const wrapper = canvas({ selectedIds: [10] });
    const source = dragSurface(wrapper, 10);
    await pointer(source, "pointerdown", { x: 40, y: 40 });
    await pointer(source, "pointermove", { x: 540, y: 40 });
    key(wrapper, "Escape");
    await pointer(source, "pointerup", { x: 540, y: 40 });
    expect(wrapper.emitted("connect")).toBeUndefined();
    expect(wrapper.emitted("move")).toBeUndefined();
    expect(wrapper.get('[data-note-id="10"]').attributes("style")).toContain(
      "translate(10px, 20px)",
    );
    expect(wrapper.find("#brainstorming-connection-preview").exists()).toBe(false);
  });

  it("keeps movement for free space and multiple selected notes", async () => {
    for (const selectedIds of [[10], [10, 12]]) {
      const wrapper = canvas({ selectedIds });
      const source = dragSurface(wrapper, 10);
      await pointer(source, "pointerdown", { x: 40, y: 40 });
      const point = selectedIds.length === 1 ? { x: 1000, y: 40 } : { x: 540, y: 40 };
      await pointer(source, "pointermove", point);
      await pointer(source, "pointerup", point);
      expect(wrapper.emitted("connect")).toBeUndefined();
      expect(wrapper.emitted("move")).toHaveLength(1);
    }
  });

  it("uses measured text width for connectors and preserves the viewport when restoring editing focus", async () => {
    vi.spyOn(HTMLElement.prototype, "offsetWidth", "get").mockImplementation(
      function (this: HTMLElement) {
        return this.id === "canvas-note-10" ? 120 : 160;
      },
    );
    const wrapper = canvas({ selectedIds: [10] });
    await nextTick();
    await nextTick();
    const line = wrapper.get('[data-connection-source="10"]');
    expect(line.attributes("x1")).toBe("134");
    view.x = -500;
    view.y = -400;
    view.zoom = 0.7;
    await (wrapper.vm as unknown as { focusEditing: () => Promise<void> }).focusEditing();
    expect(view).toMatchObject({ x: -500, y: -400, zoom: 0.7 });
  });

  it("allows read-only inspection but never writes a connection", async () => {
    const wrapper = canvas({ selectedIds: [], permissions: { edit: false, create: false } });
    await wrapper.get("#canvas-connection-10-11").trigger("click");
    expect(wrapper.find("#brainstorming-connection-toolbar").exists()).toBe(false);
    key(wrapper, "Delete");
    expect(wrapper.emitted("changeConnections")).toBeUndefined();
    expect(wrapper.emitted("remove")).toBeUndefined();
  });
});
