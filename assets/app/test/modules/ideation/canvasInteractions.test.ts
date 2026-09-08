import { afterEach, describe, expect, it, vi } from "vitest";
import { defineComponent, h, nextTick, reactive, ref } from "vue";
import { mount, type VueWrapper } from "@vue/test-utils";
import BrainstormingCanvas from "@modules/ideation/components/BrainstormingCanvas.vue";
import { idea } from "./fixtures";

vi.mock("@modules/ideation/composables/useCanvasViewport", () => ({
  useCanvasViewport: () => ({
    view: reactive({ x: 0, y: 0, zoom: 1, width: 800, height: 600 }),
    space: ref(false),
    transform: ref(""),
    world: (x: number, y: number) => ({ x, y }),
    zoomTo: vi.fn(),
    wheel: vi.fn(),
    fit: vi.fn(),
  }),
}));
const NoteStub = defineComponent({
  props: ["note", "editing"],
  setup: (props) => () =>
    h("article", { tabindex: 0, "data-test-note": props.note.id }, [
      h("div", { contenteditable: String(props.editing) }, "Text"),
    ]),
});
const mounted: VueWrapper[] = [];
function canvas(props = {}) {
  const wrapper = mount(BrainstormingCanvas, {
    attachTo: document.body,
    props: {
      notes: [idea({ canvas: { x: 10, y: 20 } }), idea({ id: 11, canvas: { x: 400, y: 50 } })],
      selectedIds: [10],
      editingId: null,
      writable: true,
      noteKey: (id: number) => String(id),
      historyState: { canUndo: true, canRedo: true, busy: false },
      members: [],
      statuses: {},
      context: { epoch: "a", session_id: 1 },
      ...props,
    },
    global: { stubs: { CanvasNote: NoteStub, CanvasCursors: true } },
  });
  mounted.push(wrapper);
  return wrapper;
}
afterEach(() => {
  for (const wrapper of mounted.splice(0)) wrapper.unmount();
  vi.restoreAllMocks();
});
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
function copyEvent(wrapper: VueWrapper, name: string, target = wrapper.element) {
  const event = new Event(name, { bubbles: true, cancelable: true }) as ClipboardEvent;
  target.dispatchEvent(event);
  return event;
}
async function pointer(target: Element, type: string, options: PointerEventInit = {}) {
  target.dispatchEvent(new PointerEvent(type, { bubbles: true, cancelable: true, ...options }));
  await nextTick();
}
describe("canvas keyboard and selection", () => {
  it("dispatches destructive and duplicate shortcuts for the visible selection only", () => {
    const wrapper = canvas({ selectedIds: [10, 11, 999] });
    expect(key(wrapper, "Delete").defaultPrevented).toBe(true);
    key(wrapper, "Backspace");
    expect(wrapper.emitted("remove")).toEqual([[[10, 11]], [[10, 11]]]);
    key(wrapper, "d", { metaKey: true });
    key(wrapper, "D", { ctrlKey: true });
    expect(wrapper.emitted("duplicate")).toEqual([[[10, 11]], [[10, 11]]]);
    expect(key(wrapper, "c", { metaKey: true }).defaultPrevented).toBe(false);
    expect(key(wrapper, "v", { ctrlKey: true }).defaultPrevented).toBe(false);
    expect(key(wrapper, "x", { metaKey: true }).defaultPrevented).toBe(false);
  });
  it("uses native clipboard events and the pointer insertion point", async () => {
    const wrapper = canvas({ selectedIds: [10, 11] });
    const copied = copyEvent(wrapper, "copy");
    const cut = copyEvent(wrapper, "cut");
    expect(wrapper.emitted("copy")?.[0]).toEqual([copied, [10, 11]]);
    expect(wrapper.emitted("cut")?.[0]).toEqual([cut, [10, 11]]);
    copyEvent(wrapper, "paste");
    expect(wrapper.emitted("paste")?.[0][1]).toEqual({ x: 400, y: 300 });
    await pointer(wrapper.element, "pointermove", { clientX: 75, clientY: 100 });
    copyEvent(wrapper, "paste");
    expect(wrapper.emitted("paste")?.[1][1]).toEqual({ x: 75, y: 100 });
    await wrapper.trigger("pointerleave");
    copyEvent(wrapper, "paste");
    expect(wrapper.emitted("paste")?.[2][1]).toEqual({ x: 400, y: 300 });
  });
  it("leaves shortcuts and clipboard events inside the text editor untouched", () => {
    const wrapper = canvas({ editingId: 10 });
    const text = wrapper.get('[contenteditable="true"]').element;
    for (const name of ["a", "d", "z", "y", "c", "x", "v"])
      expect(key(wrapper, name, { metaKey: true }, text).defaultPrevented).toBe(false);
    for (const name of ["Delete", "Backspace", "Escape", "Enter", "ArrowUp"])
      key(wrapper, name, {}, text);
    for (const name of ["copy", "cut", "paste"]) copyEvent(wrapper, name, text);
    for (const event of [
      "select",
      "duplicate",
      "undo",
      "redo",
      "remove",
      "edit",
      "move",
      "copy",
      "cut",
      "paste",
    ])
      expect(wrapper.emitted(event)).toBeUndefined();
  });
  it("selects all, deselects with Escape and edits a selected note with Enter", () => {
    const wrapper = canvas();
    key(wrapper, "a", { ctrlKey: true });
    expect(wrapper.emitted("select")?.[0]).toEqual([[10, 11]]);
    key(wrapper, "Enter");
    expect(wrapper.emitted("edit")?.[0]).toEqual([10]);
    key(wrapper, "Escape");
    expect(wrapper.emitted("select")?.[1]).toEqual([[]]);
  });
  it("routes undo/redo while disabling writes during an operation or in read-only mode", async () => {
    const wrapper = canvas();
    key(wrapper, "z", { metaKey: true });
    key(wrapper, "z", { metaKey: true, shiftKey: true });
    key(wrapper, "y", { ctrlKey: true });
    expect(wrapper.emitted("undo")).toHaveLength(1);
    expect(wrapper.emitted("redo")).toHaveLength(2);
    await wrapper.setProps({ historyState: { canUndo: true, canRedo: true, busy: true } });
    for (const name of ["z", "d"]) key(wrapper, name, { ctrlKey: true });
    key(wrapper, "Delete");
    copyEvent(wrapper, "cut");
    copyEvent(wrapper, "paste");
    expect(wrapper.emitted("undo")).toHaveLength(1);
    for (const event of ["duplicate", "remove", "cut", "paste"])
      expect(wrapper.emitted(event)).toBeUndefined();
    expect(wrapper.get("#brainstorming-undo").attributes("disabled")).toBeDefined();
    await wrapper.setProps({
      writable: false,
      historyState: { canUndo: true, canRedo: true, busy: false },
    });
    key(wrapper, "d", { metaKey: true });
    key(wrapper, "Delete");
    copyEvent(wrapper, "cut");
    expect(wrapper.emitted("duplicate")).toBeUndefined();
    expect(wrapper.emitted("remove")).toBeUndefined();
    copyEvent(wrapper, "copy");
    expect(wrapper.emitted("copy")).toHaveLength(1);
  });
  it("nudges the whole selection as one operation and Shift toggles membership", async () => {
    const wrapper = canvas({ selectedIds: [10, 11] });
    key(wrapper, "ArrowRight", { shiftKey: true });
    expect(wrapper.emitted("move")?.[0]).toEqual([
      [
        { id: 10, point: { x: 30, y: 20 } },
        { id: 11, point: { x: 420, y: 50 } },
      ],
    ]);
    await pointer(wrapper.get('[data-note-id="11"]').element, "pointerdown", {
      button: 0,
      pointerId: 1,
      shiftKey: true,
    });
    expect(wrapper.emitted("select")?.[0]).toEqual([[10]]);
  });
  it("keeps all selected notes during drag and commits their positions together", async () => {
    const wrapper = canvas({ selectedIds: [10, 11] });
    const note = wrapper.get('[data-note-id="10"]');
    Object.assign(note.element, { setPointerCapture: vi.fn(), hasPointerCapture: () => false });
    await pointer(note.element, "pointerdown", {
      button: 0,
      pointerId: 1,
      clientX: 10,
      clientY: 20,
    });
    await pointer(wrapper.element, "pointermove", { pointerId: 1, clientX: 35, clientY: 50 });
    await pointer(wrapper.element, "pointerup", { pointerId: 1 });
    expect(wrapper.emitted("select")?.[0]).toEqual([[10, 11]]);
    expect(wrapper.emitted("move")?.[0]).toEqual([
      [
        { id: 10, point: { x: 35, y: 50 } },
        { id: 11, point: { x: 425, y: 80 } },
      ],
    ]);
    await nextTick();
    expect(wrapper.emitted("move")).toHaveLength(1);
  });
  it("double-click on a note edits it and never creates a second note", async () => {
    const wrapper = canvas();
    await wrapper.get('[data-test-note="10"]').trigger("dblclick");
    expect(wrapper.emitted("edit")?.[0]).toEqual([10]);
    expect(wrapper.emitted("add")).toBeUndefined();
  });
});
