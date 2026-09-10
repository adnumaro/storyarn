import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { defineComponent, h, nextTick, reactive, ref, type PropType } from "vue";
import { mount, type VueWrapper } from "@vue/test-utils";
import BrainstormingCanvas from "@modules/ideation/components/BrainstormingCanvas.vue";
import type { CanvasIdea, IdeaGroup } from "@modules/ideation/types";
import { idea, ideaGroup } from "./fixtures";

interface Point {
  x: number;
  y: number;
}
interface Options {
  notes?: CanvasIdea[];
  selectedIds?: number[];
  groups?: IdeaGroup[];
  selectedGroup?: number | null;
  edit?: boolean;
  editingId?: number | null;
}
const mounted: VueWrapper[] = [];
const rectangle = { left: 50, top: 70, width: 1000, height: 700 };
const NoteStub = defineComponent({
  props: {
    note: { type: Object as PropType<CanvasIdea>, required: true },
    editing: Boolean,
    selected: Boolean,
  },
  setup: (props) => () =>
    h(
      "article",
      {
        id: `canvas-note-${props.note.id}`,
        tabindex: 0,
        "aria-selected": String(props.selected),
        "data-test-height": props.note.id === 11 ? "180" : "120",
      },
      [h("div", { contenteditable: String(props.editing) }, "The original note")],
    ),
});

beforeEach(() => {
  vi.stubGlobal(
    "ResizeObserver",
    class {
      observe() {}
      disconnect() {}
    },
  );
  vi.spyOn(HTMLElement.prototype, "clientWidth", "get").mockImplementation(
    function (this: HTMLElement) {
      return this.id === "brainstorming-canvas" ? rectangle.width : 0;
    },
  );
  vi.spyOn(HTMLElement.prototype, "clientHeight", "get").mockImplementation(
    function (this: HTMLElement) {
      return this.id === "brainstorming-canvas" ? rectangle.height : 0;
    },
  );
  vi.spyOn(HTMLElement.prototype, "offsetHeight", "get").mockImplementation(
    function (this: HTMLElement) {
      return Number(this.dataset.testHeight ?? 0);
    },
  );
  vi.spyOn(HTMLElement.prototype, "getBoundingClientRect").mockImplementation(
    function (this: HTMLElement) {
      return this.id === "brainstorming-canvas"
        ? new DOMRect(rectangle.left, rectangle.top, rectangle.width, rectangle.height)
        : new DOMRect();
    },
  );
});

afterEach(() => {
  for (const wrapper of mounted.splice(0)) wrapper.unmount();
  vi.restoreAllMocks();
  vi.unstubAllGlobals();
});

function installCapture(element: Element) {
  const pointers = new Set<number>();
  Object.assign(element, {
    setPointerCapture: vi.fn((id: number) => pointers.add(id)),
    hasPointerCapture: (id: number) => pointers.has(id),
    releasePointerCapture: vi.fn((id: number) => {
      pointers.delete(id);
      element.dispatchEvent(
        new PointerEvent("lostpointercapture", { bubbles: true, pointerId: id }),
      );
    }),
  });
  return pointers;
}

async function canvas(options: Options = {}) {
  const selected = reactive([...(options.selectedIds ?? [])]);
  const state = reactive({
    groups: options.groups ?? [],
    selectedId: options.selectedGroup ?? null,
    save: vi.fn(async () => true),
    move: vi.fn(async () => undefined),
  });
  const wrapper = mount(BrainstormingCanvas, {
    attachTo: document.body,
    props: {
      notes: options.notes ?? [
        idea({ canvas: { x: 100, y: 100, width: 100 } }),
        idea({ id: 11, canvas: { x: 350, y: 120, width: 100 } }),
        idea({ id: 12, canvas: { x: 650, y: 100, width: 100 } }),
      ],
      selectedIds: selected,
      groupState: state,
      editingId: options.editingId ?? null,
      permissions: { edit: options.edit ?? true, create: options.edit ?? true },
      noteKey: (id: number) => String(id),
      historyState: { canUndo: true, canRedo: true, busy: false },
      members: [],
      statuses: {},
      collaboration: { context: { epoch: "area-session", session_id: 1 }, cursors: false },
      onSelect: (ids: number[]) => selected.splice(0, selected.length, ...ids),
      onSelectGroup: (id: number | null) => {
        state.selectedId = id;
      },
    },
    global: { stubs: { CanvasNote: NoteStub, CanvasCursors: true } },
  });
  mounted.push(wrapper);
  const captured = installCapture(wrapper.element);
  for (const child of wrapper.findAll("[data-note-id], [data-group-id]"))
    installCapture(child.element);
  await nextTick();
  return { wrapper, selected, state, captured };
}

type CanvasElement = Pick<VueWrapper, "element">;

function viewport(wrapper: CanvasElement) {
  const layer = (wrapper.element as HTMLElement).querySelector<HTMLElement>(
    ":scope > .origin-top-left",
  );
  const values = layer?.style.transform.match(
    /translate\(([-\d.]+)px,\s*([-\d.]+)px\) scale\(([-\d.]+)\)/,
  );
  if (!values) throw new Error("The canvas must expose its rendered viewport transform");
  return { x: Number(values[1]), y: Number(values[2]), zoom: Number(values[3]) };
}

function client(wrapper: CanvasElement, point: Point): Point {
  const view = viewport(wrapper);
  return {
    x: rectangle.left + view.x + point.x * view.zoom,
    y: rectangle.top + view.y + point.y * view.zoom,
  };
}

async function pointer(target: Element, type: string, at: Point, options: PointerEventInit = {}) {
  const event = new PointerEvent(type, {
    bubbles: true,
    cancelable: true,
    pointerId: 1,
    button: 0,
    buttons: type === "pointerup" ? 0 : 1,
    clientX: at.x,
    clientY: at.y,
    ...options,
  });
  target.dispatchEvent(event);
  await nextTick();
  return event;
}

function key(target: EventTarget, value: string, options: KeyboardEventInit = {}) {
  const event = new KeyboardEvent("keydown", {
    key: value,
    bubbles: true,
    cancelable: true,
    ...options,
  });
  target.dispatchEvent(event);
  return event;
}

async function start(wrapper: CanvasElement, point: Point, options: PointerEventInit = {}) {
  return pointer(wrapper.element, "pointerdown", client(wrapper, point), options);
}

async function move(wrapper: CanvasElement, point: Point, options: PointerEventInit = {}) {
  return pointer(wrapper.element, "pointermove", client(wrapper, point), options);
}

async function finish(wrapper: CanvasElement, point: Point) {
  return pointer(wrapper.element, "pointerup", client(wrapper, point));
}

describe("canvas area selection", () => {
  it("keeps the gesture when a parent render recreates history props after selection updates", async () => {
    const selected = ref<number[]>([12]);
    const groupId = ref<number | null>(null);
    const host = mount(
      defineComponent({
        setup: () => () =>
          h(BrainstormingCanvas, {
            notes: [
              idea({ canvas: { x: 100, y: 100, width: 100 } }),
              idea({ id: 11, canvas: { x: 350, y: 120, width: 100 } }),
              idea({ id: 12, canvas: { x: 650, y: 100, width: 100 } }),
            ],
            selectedIds: selected.value,
            groupState: {
              groups: [],
              selectedId: groupId.value,
              save: async () => true,
              move: async () => undefined,
            },
            historyState: { canUndo: true, canRedo: false, busy: false },
            editingId: null,
            permissions: { edit: true, create: true },
            noteKey: (id: number) => String(id),
            members: [],
            statuses: {},
            collaboration: { context: { epoch: "parent-session", session_id: 1 }, cursors: false },
            onSelect: (ids: number[]) => {
              selected.value = ids;
            },
            onSelectGroup: (id: number | null) => {
              groupId.value = id;
            },
          }),
      }),
      {
        attachTo: document.body,
        global: { stubs: { CanvasNote: NoteStub, CanvasCursors: true } },
      },
    );
    mounted.push(host);
    const wrapper = host.getComponent(BrainstormingCanvas);
    const captured = installCapture(wrapper.element);
    await nextTick();
    await nextTick();
    const before = wrapper.props("historyState");
    await start(wrapper, { x: 90, y: 80 });
    expect(wrapper.props("historyState")).not.toBe(before);
    expect(captured.has(1)).toBe(true);
    await move(wrapper, { x: 351, y: 121 });
    expect(selected.value).toEqual([10, 11]);
    expect(wrapper.find("#brainstorming-selection-area").exists()).toBe(true);
    await finish(wrapper, { x: 351, y: 121 });
    expect(selected.value).toEqual([10, 11]);
    expect(captured.size).toBe(0);
  });

  it("previews touched notes and commits after capture releases without moving or creating content", async () => {
    const { wrapper, selected, captured } = await canvas();
    await start(wrapper, { x: 90, y: 80 });
    expect(wrapper.find("#brainstorming-selection-area").exists()).toBe(false);
    await move(wrapper, { x: 351, y: 121 });
    expect(wrapper.find("#brainstorming-selection-area").exists()).toBe(true);
    expect(selected).toEqual([10, 11]);
    expect(wrapper.get("#canvas-note-10").attributes("aria-selected")).toBe("true");
    expect(wrapper.get("#canvas-note-11").attributes("aria-selected")).toBe("true");
    await finish(wrapper, { x: 351, y: 121 });
    expect(selected).toEqual([10, 11]);
    expect(captured.size).toBe(0);
    expect(wrapper.find("#brainstorming-selection-area").exists()).toBe(false);
    for (const event of ["move", "add", "createGroup", "undo", "redo"])
      expect(wrapper.emitted(event)).toBeUndefined();
  });

  it("keeps a short background gesture as a click without displaying a selection rectangle", async () => {
    const { wrapper, selected } = await canvas({ selectedIds: [12] });
    const origin = client(wrapper, { x: 90, y: 80 });
    await pointer(wrapper.element, "pointerdown", origin);
    await pointer(wrapper.element, "pointermove", { x: origin.x + 2, y: origin.y + 1 });
    expect(wrapper.find("#brainstorming-selection-area").exists()).toBe(false);
    await pointer(wrapper.element, "pointerup", { x: origin.x + 2, y: origin.y + 1 });
    expect(selected).toEqual([]);
    expect(wrapper.emitted("add")).toBeUndefined();
  });

  it("supports reverse dragging and removes notes when the rectangle shrinks away from them", async () => {
    const { wrapper, selected } = await canvas();
    await start(wrapper, { x: 500, y: 350 });
    await move(wrapper, { x: 90, y: 80 });
    expect(selected).toEqual([10, 11]);
    await move(wrapper, { x: 340, y: 110 });
    expect(selected).toEqual([11]);
    await finish(wrapper, { x: 340, y: 110 });
    expect(selected).toEqual([11]);
  });

  it("adds to the initial selection with Shift while allowing the new area to shrink", async () => {
    const { wrapper, selected } = await canvas({ selectedIds: [12] });
    await start(wrapper, { x: 500, y: 350 }, { shiftKey: true });
    await move(wrapper, { x: 90, y: 80 }, { shiftKey: true });
    expect([...selected].sort()).toEqual([10, 11, 12]);
    await move(wrapper, { x: 340, y: 110 }, { shiftKey: true });
    expect([...selected].sort()).toEqual([11, 12]);
    await finish(wrapper, { x: 340, y: 110 });
    expect([...selected].sort()).toEqual([11, 12]);
  });

  it("uses actual viewport pan, zoom and container offsets when hit-testing note bodies", async () => {
    const { wrapper, selected } = await canvas();
    const initial = viewport(wrapper);
    wrapper.element.dispatchEvent(new WheelEvent("wheel", { deltaX: 125, deltaY: -85 }));
    wrapper.element.dispatchEvent(
      new WheelEvent("wheel", {
        ctrlKey: true,
        deltaY: 65,
        clientX: rectangle.left + 430,
        clientY: rectangle.top + 280,
      }),
    );
    await nextTick();
    expect(viewport(wrapper).zoom).toBeLessThan(initial.zoom);
    expect(viewport(wrapper).x).not.toBe(initial.x);
    await start(wrapper, { x: 345, y: 270 });
    await move(wrapper, { x: 355, y: 295 });
    expect(selected).toEqual([11]);
    await finish(wrapper, { x: 355, y: 295 });
    expect(selected).toEqual([11]);
  });

  it.each(["Escape", "pointercancel", "lostpointercapture", "blur"])(
    "restores the original selection and ends the gesture on %s",
    async (reason) => {
      const { wrapper, selected } = await canvas({ selectedIds: [12] });
      await start(wrapper, { x: 90, y: 80 });
      await move(wrapper, { x: 351, y: 121 });
      expect(selected).toEqual([10, 11]);
      if (reason === "Escape") key(wrapper.element, "Escape");
      else if (reason === "blur") window.dispatchEvent(new Event("blur"));
      else await pointer(wrapper.element, reason, client(wrapper, { x: 351, y: 121 }));
      await nextTick();
      expect(selected).toEqual([12]);
      expect(wrapper.find("#brainstorming-selection-area").exists()).toBe(false);
      await move(wrapper, { x: 690, y: 180 });
      await finish(wrapper, { x: 690, y: 180 });
      expect(selected).toEqual([12]);
    },
  );

  it("ignores another pointer without abandoning the active selection gesture", async () => {
    const { wrapper, selected } = await canvas();
    await start(wrapper, { x: 90, y: 80 });
    await move(wrapper, { x: 351, y: 121 });
    expect(selected).toEqual([10, 11]);
    await start(wrapper, { x: 620, y: 80 }, { pointerId: 2 });
    await move(wrapper, { x: 760, y: 240 }, { pointerId: 2 });
    await pointer(wrapper.element, "pointerup", client(wrapper, { x: 760, y: 240 }), {
      pointerId: 2,
    });
    expect(selected).toEqual([10, 11]);
    expect(wrapper.find("#brainstorming-selection-area").exists()).toBe(true);
    await finish(wrapper, { x: 351, y: 121 });
    expect(wrapper.find("#brainstorming-selection-area").exists()).toBe(false);
  });

  it.each(["Space", "hand", "middle"])(
    "retains the existing selection when panning with %s",
    async (method) => {
      const { wrapper, selected } = await canvas({ selectedIds: [12] });
      if (method === "Space") key(wrapper.element, " ", { code: "Space" });
      else if (method === "hand") key(wrapper.element, "h");
      const initial = viewport(wrapper);
      const origin = client(wrapper, { x: 90, y: 80 });
      await pointer(wrapper.element, "pointerdown", origin, {
        button: method === "middle" ? 1 : 0,
      });
      await pointer(wrapper.element, "pointermove", { x: origin.x + 160, y: origin.y + 60 });
      expect(viewport(wrapper).x).toBe(initial.x + 160);
      expect(viewport(wrapper).y).toBe(initial.y + 60);
      expect(wrapper.find("#brainstorming-selection-area").exists()).toBe(false);
      await pointer(wrapper.element, "pointerup", { x: origin.x + 160, y: origin.y + 60 });
      expect(selected).toEqual([12]);
      expect(wrapper.emitted("move")).toBeUndefined();
    },
  );

  it("can select visible notes without edit permission and excludes unloaded group members", async () => {
    const visible = idea({ canvas: { x: 100, y: 100, width: 100 } });
    const { wrapper, selected } = await canvas({
      edit: false,
      notes: [visible],
      groups: [ideaGroup()],
    });
    await start(wrapper, { x: 70, y: 70 });
    await move(wrapper, { x: 750, y: 350 });
    await finish(wrapper, { x: 750, y: 350 });
    expect(selected).toEqual([10]);
    key(wrapper.element, "Delete");
    expect(wrapper.emitted("remove")).toBeUndefined();
    expect(wrapper.emitted("deleteGroup")).toBeUndefined();
  });

  it("selects a group by clicking its blank body but starts a note marquee when dragging there", async () => {
    const { wrapper, selected, state } = await canvas({ groups: [ideaGroup()] });
    const frame = wrapper.get("#canvas-group-40").element;
    const origin = client(wrapper, { x: 240, y: 100 });
    await pointer(frame, "pointerdown", origin);
    await pointer(wrapper.element, "pointerup", origin);
    expect(state.selectedId).toBe(40);
    await pointer(frame, "pointerdown", origin);
    await move(wrapper, { x: 150, y: 180 });
    expect(selected).toEqual([10]);
    expect(state.selectedId).toBeNull();
    await finish(wrapper, { x: 150, y: 180 });
    key(wrapper.element, "Delete");
    expect(wrapper.emitted("remove")).toEqual([[[10]]]);
    expect(wrapper.emitted("deleteGroup")).toBeUndefined();
    expect(state.move).not.toHaveBeenCalled();
  });

  it("continues moving a group from its header instead of selecting notes by area", async () => {
    const { wrapper, selected, state } = await canvas({ groups: [ideaGroup()] });
    const header = wrapper.get("#canvas-group-40 > header").element;
    const origin = client(wrapper, { x: 10, y: -20 });
    await pointer(header, "pointerdown", origin);
    await pointer(wrapper.element, "pointermove", { x: origin.x + 80, y: origin.y + 40 });
    expect(wrapper.find("#brainstorming-selection-area").exists()).toBe(false);
    await pointer(wrapper.element, "pointerup", { x: origin.x + 80, y: origin.y + 40 });
    expect(state.move).toHaveBeenCalledOnce();
    expect(selected).toEqual([]);
    expect(state.selectedId).toBe(40);
  });

  it("does not start a marquee from a group's synthesis text", async () => {
    const { wrapper, selected } = await canvas({
      groups: [ideaGroup({ synthesis: "A synthesis with selectable meaning." })],
    });
    const synthesis = wrapper.get(".group-synthesis p").element;
    await pointer(synthesis, "pointerdown", client(wrapper, { x: 500, y: 100 }));
    await move(wrapper, { x: 90, y: 80 });
    await finish(wrapper, { x: 90, y: 80 });
    expect(selected).toEqual([]);
    expect(wrapper.find("#brainstorming-selection-area").exists()).toBe(false);
  });

  it("leaves note text selection and editor shortcuts untouched", async () => {
    const { wrapper, selected } = await canvas({ selectedIds: [10], editingId: 10 });
    const text = wrapper.get('[contenteditable="true"]').element;
    const event = await pointer(text, "pointerdown", client(wrapper, { x: 120, y: 120 }));
    await move(wrapper, { x: 430, y: 150 });
    await finish(wrapper, { x: 430, y: 150 });
    expect(event.defaultPrevented).toBe(false);
    expect(selected).toEqual([10]);
    expect(wrapper.find("#brainstorming-selection-area").exists()).toBe(false);
    expect(key(text, "z", { metaKey: true }).defaultPrevented).toBe(false);
    expect(wrapper.emitted("undo")).toBeUndefined();
    expect(wrapper.emitted("finish")).toBeUndefined();
  });
});
