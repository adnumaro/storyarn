import { afterEach, describe, expect, it, vi } from "vitest";
import { defineComponent, h, nextTick, reactive, ref } from "vue";
import { mount, type VueWrapper } from "@vue/test-utils";
import BrainstormingCanvas from "@modules/ideation/components/BrainstormingCanvas.vue";
import { idea, ideaGroup } from "./fixtures";

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
      permissions: { edit: true, create: true },
      noteKey: (id: number) => String(id),
      historyState: { canUndo: true, canRedo: true, busy: false },
      members: [],
      statuses: {},
      collaboration: { context: { epoch: "a", session_id: 1 }, cursors: true },
      ...props,
    },
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
afterEach(() => {
  for (const wrapper of mounted.splice(0)) wrapper.unmount();
  vi.restoreAllMocks();
  vi.useRealTimers();
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
  it("blocks new-note gestures and clipboard insertion when contributions close while preserving existing-note shortcuts", async () => {
    const wrapper = canvas({ permissions: { edit: true, create: false } });
    key(wrapper, "n");
    key(wrapper, "d", { metaKey: true });
    copyEvent(wrapper, "paste");
    await wrapper.trigger("dblclick");
    expect(wrapper.emitted("add")).toBeUndefined();
    expect(wrapper.emitted("duplicate")).toBeUndefined();
    expect(wrapper.emitted("paste")).toBeUndefined();
    expect(wrapper.find("#new-brainstorming-idea").exists()).toBe(false);
    key(wrapper, "Delete");
    key(wrapper, "z", { metaKey: true });
    key(wrapper, "z", { metaKey: true, shiftKey: true });
    copyEvent(wrapper, "copy");
    expect(wrapper.emitted("remove")).toEqual([[[10]]]);
    expect(wrapper.emitted("undo")).toHaveLength(1);
    expect(wrapper.emitted("redo")).toHaveLength(1);
    expect(wrapper.emitted("copy")).toHaveLength(1);
    await wrapper.get('[data-test-note="10"]').trigger("dblclick");
    expect(wrapper.emitted("edit")).toEqual([[10]]);
  });

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
  it.each(["Control", "Meta"] as const)(
    "clears group selection before %s+A selects notes and Delete removes only those notes",
    async (modifier) => {
      const selectedIds = reactive<number[]>([]);
      const selectedGroup = ref<number | null>(40);
      const groupState = reactive({
        groups: [ideaGroup()],
        selectedId: selectedGroup,
        save: vi.fn(),
        move: vi.fn(),
      });
      const wrapper = canvas({
        selectedIds,
        groupState,
        onSelect: (ids: number[]) => {
          selectedIds.splice(0, selectedIds.length, ...ids);
        },
        onSelectGroup: (id: number | null) => {
          selectedGroup.value = id;
        },
      });
      key(wrapper, "a", { ctrlKey: modifier === "Control", metaKey: modifier === "Meta" });
      await nextTick();
      expect(selectedGroup.value).toBeNull();
      expect(selectedIds).toEqual([10, 11]);
      key(wrapper, "Delete");
      expect(wrapper.emitted("remove")).toEqual([[[10, 11]]]);
      expect(wrapper.emitted("deleteGroup")).toBeUndefined();
    },
  );
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
    expect(wrapper.emitted("undo")).toHaveLength(2);
    for (const event of ["duplicate", "remove", "cut", "paste"])
      expect(wrapper.emitted(event)).toBeUndefined();
    expect(wrapper.find("#brainstorming-undo").exists()).toBe(false);
    expect(wrapper.find("#brainstorming-redo").exists()).toBe(false);
    await wrapper.setProps({
      permissions: { edit: false, create: false },
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
  it("queues rapid history keys from canvas controls while preserving native text undo", async () => {
    const wrapper = canvas({ historyState: { canUndo: false, canRedo: false, busy: true } });
    const button = wrapper.get("button[aria-label='Zoom in']").element;
    key(wrapper, "z", { metaKey: true }, button);
    key(wrapper, "z", { metaKey: true, repeat: true }, button);
    key(wrapper, "y", { metaKey: true }, button);
    expect(wrapper.emitted("undo")).toHaveLength(2);
    expect(wrapper.emitted("redo")).toHaveLength(1);
    await wrapper.setProps({ editingId: 10 });
    const editor = wrapper.get('[contenteditable="true"]').element;
    key(wrapper, "z", { metaKey: true }, editor);
    expect(wrapper.emitted("undo")).toHaveLength(2);
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
  it("selects the frame independently while notes retain their own editing and selection", async () => {
    const wrapper = canvas({
      groupState: { groups: [ideaGroup()], selectedId: 40, save: vi.fn(), move: vi.fn() },
    });
    await pointer(wrapper.get("#canvas-group-40").element, "pointerdown", {
      button: 0,
      pointerId: 1,
    });
    await pointer(wrapper.element, "pointerup", { pointerId: 1 });
    expect(wrapper.emitted("selectGroup")?.[0]).toEqual([40]);
    expect(wrapper.emitted("select")?.[0]).toEqual([[]]);
    await pointer(wrapper.get('[data-note-id="10"]').element, "pointerdown", {
      button: 0,
      pointerId: 2,
      shiftKey: true,
    });
    expect(wrapper.emitted("selectGroup")?.at(-1)).toEqual([null]);
    await wrapper.get('[data-note-id="10"]').trigger("dblclick");
    expect(wrapper.emitted("edit")?.at(-1)).toEqual([10]);
  });
  it("moves all group members from the title handle and retains the preview until acknowledgement", async () => {
    let resolve: () => void = () => {};
    const move = vi.fn(
      () =>
        new Promise<void>((done) => {
          resolve = done;
        }),
    );
    const wrapper = canvas({
      selectedIds: [],
      groupState: { groups: [ideaGroup()], selectedId: 40, save: vi.fn(), move },
    });
    const frame = wrapper.get("#canvas-group-40");
    Object.assign(frame.element, { setPointerCapture: vi.fn(), hasPointerCapture: () => false });
    await pointer(frame.get("header").element, "pointerdown", {
      button: 0,
      pointerId: 1,
      clientX: 10,
      clientY: 20,
    });
    await pointer(wrapper.element, "pointermove", { pointerId: 1, clientX: 35, clientY: 50 });
    await pointer(wrapper.element, "pointerup", { pointerId: 1 });
    expect(move).toHaveBeenCalledWith(
      40,
      { x: 7, y: -14 },
      {
        version: 1,
        member_versions: ideaGroup().members.map((member) => ({
          id: member.idea_id,
          version: member.canvas.version ?? 0,
        })),
      },
    );
    expect(wrapper.get('[data-note-id="10"]').attributes("style")).toContain(
      "translate(35px, 50px)",
    );
    expect(wrapper.get('[data-note-id="11"]').attributes("style")).toContain(
      "translate(425px, 80px)",
    );
    resolve();
    await nextTick();
    await nextTick();
    expect(wrapper.emitted("move")).toBeUndefined();
  });
  it("keeps pointer-down group and member versions when remote props change during a drag", async () => {
    const group = reactive(ideaGroup());
    const move = vi.fn(async () => {});
    const wrapper = canvas({
      selectedIds: [],
      groupState: { groups: [group], selectedId: 40, save: vi.fn(), move },
    });
    const frame = wrapper.get("#canvas-group-40");
    Object.assign(frame.element, { setPointerCapture: vi.fn(), hasPointerCapture: () => false });
    await pointer(frame.get("header").element, "pointerdown", {
      button: 0,
      pointerId: 1,
      clientX: 10,
      clientY: 20,
    });
    group.version = 2;
    group.canvas.x = 982;
    group.members[0].canvas.x = 1010;
    group.members[0].canvas.version = 7;
    group.members[1].canvas.version = 9;
    await nextTick();
    await pointer(wrapper.element, "pointermove", { pointerId: 1, clientX: 35, clientY: 50 });
    await pointer(wrapper.element, "pointerup", { pointerId: 1 });
    expect(move).toHaveBeenCalledExactlyOnceWith(
      40,
      { x: 7, y: -14 },
      {
        version: 1,
        member_versions: [
          { id: 10, version: 1 },
          { id: 11, version: 1 },
        ],
      },
    );
    expect(group.version).toBe(2);
    expect(group.members[0].canvas.version).toBe(7);
  });
  it("deletes the selected group with the keyboard while leaving source notes untouched", () => {
    const wrapper = canvas({
      selectedIds: [],
      groupState: { groups: [ideaGroup()], selectedId: 40, save: vi.fn(), move: vi.fn() },
    });
    key(wrapper, "Delete");
    expect(wrapper.emitted("deleteGroup")).toEqual([[40]]);
    expect(wrapper.emitted("remove")).toBeUndefined();
    expect(wrapper.find("#group-delete-40").exists()).toBe(true);
  });
  it("merges consecutive arrow presses on a group into one movement", async () => {
    vi.useFakeTimers();
    const move = vi.fn(() => Promise.resolve());
    const wrapper = canvas({
      selectedIds: [],
      groupState: { groups: [ideaGroup()], selectedId: 40, save: vi.fn(), move },
    });
    key(wrapper, "ArrowRight");
    key(wrapper, "ArrowRight", { shiftKey: true });
    key(wrapper, "ArrowDown");
    await nextTick();
    expect(move).not.toHaveBeenCalled();
    expect(wrapper.get("#canvas-group-40").attributes("style")).toContain("translate(4px, -42px)");
    await vi.advanceTimersByTimeAsync(200);
    expect(move).toHaveBeenCalledTimes(1);
    expect(move).toHaveBeenCalledWith(
      40,
      { x: 4, y: -42 },
      {
        version: 1,
        member_versions: [
          { id: 10, version: 1 },
          { id: 11, version: 1 },
        ],
      },
    );
  });
  it("moves a synthesis-only frame by its anchor and sends the anchor", async () => {
    vi.useFakeTimers();
    const move = vi.fn(() => Promise.resolve());
    const group = ideaGroup({ idea_ids: [], members: [] });
    const wrapper = canvas({
      selectedIds: [],
      groupState: { groups: [group], selectedId: 40, save: vi.fn(), move },
    });
    key(wrapper, "ArrowRight");
    key(wrapper, "ArrowRight");
    await nextTick();
    expect(wrapper.get("#canvas-group-40").attributes("style")).toContain(
      "translate(-14px, -44px)",
    );
    await vi.advanceTimersByTimeAsync(200);
    expect(move).toHaveBeenCalledWith(40, { x: -14, y: -44 }, { version: 1, member_versions: [] });
  });
  it("keeps a queued movement while another write is in flight and sends it afterwards", async () => {
    vi.useFakeTimers();
    const move = vi.fn(() => Promise.resolve());
    const wrapper = canvas({
      selectedIds: [],
      groupState: { groups: [ideaGroup()], selectedId: 40, save: vi.fn(), move },
    });
    key(wrapper, "ArrowRight");
    await wrapper.setProps({ historyState: { canUndo: true, canRedo: true, busy: true } });
    await vi.advanceTimersByTimeAsync(400);
    expect(move).not.toHaveBeenCalled();
    expect(wrapper.get("#canvas-group-40").attributes("style")).toContain(
      "translate(-16px, -44px)",
    );
    await wrapper.setProps({ historyState: { canUndo: true, canRedo: true, busy: false } });
    await vi.advanceTimersByTimeAsync(200);
    expect(move).toHaveBeenCalledTimes(1);
    expect(move).toHaveBeenCalledWith(40, { x: -16, y: -44 }, expect.anything());
  });
  it("commits a settling movement on pointer-down and keeps the click as a selection", async () => {
    vi.useFakeTimers();
    const move = vi.fn(() => Promise.resolve());
    const wrapper = canvas({
      selectedIds: [],
      groupState: { groups: [ideaGroup()], selectedId: 40, save: vi.fn(), move },
    });
    key(wrapper, "ArrowDown");
    const header = wrapper.get("#canvas-group-40 header").element as HTMLElement;
    Object.assign(header, { setPointerCapture: vi.fn(), hasPointerCapture: () => false });
    await pointer(header, "pointerdown", { button: 0, pointerId: 1, clientX: 5, clientY: 5 });
    expect(move).toHaveBeenCalledTimes(1);
    expect(move).toHaveBeenCalledWith(40, { x: -18, y: -42 }, expect.anything());
    expect(wrapper.emitted("selectGroup")?.at(-1)).toEqual([40]);
    await pointer(wrapper.element, "pointermove", { pointerId: 1, clientX: 60, clientY: 60 });
    await pointer(wrapper.element, "pointerup", { pointerId: 1 });
    expect(move).toHaveBeenCalledTimes(1);
    // A note click inside the window selects without starting a drag: jsdom has
    // no setPointerCapture, so beginning one here would throw.
    key(wrapper, "ArrowDown");
    await pointer(wrapper.get('[data-note-id="11"]').element, "pointerdown", {
      button: 0,
      pointerId: 2,
    });
    expect(move).toHaveBeenCalledTimes(2);
    expect(wrapper.emitted("select")?.at(-1)).toEqual([[11]]);
  });
  it("does not drag, nudge or ungroup unseen members through a filter", async () => {
    const move = vi.fn();
    const wrapper = canvas({
      notes: [idea({ canvas: { x: 10, y: 20 } })],
      selectedIds: [],
      groupState: { groups: [ideaGroup()], selectedId: 40, save: vi.fn(), move },
    });
    const frame = wrapper.get("#canvas-group-40");
    await pointer(frame.get("header").element, "pointerdown", { button: 0, pointerId: 1 });
    await pointer(wrapper.element, "pointermove", { pointerId: 1, clientX: 100, clientY: 100 });
    await pointer(wrapper.element, "pointerup", { pointerId: 1 });
    key(wrapper, "ArrowRight");
    key(wrapper, "g", { ctrlKey: true, shiftKey: true });
    expect(move).not.toHaveBeenCalled();
    expect(wrapper.emitted("separateGroup")).toBeUndefined();
    expect(frame.text()).toContain("1 of 2 notes visible");
    expect(frame.get("#group-separate-40").attributes("disabled")).toBeDefined();
  });
});
