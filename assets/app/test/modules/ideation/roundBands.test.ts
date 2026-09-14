import { afterEach, describe, expect, it, vi } from "vitest";
import { defineComponent, h, nextTick, reactive, ref } from "vue";
import { mount, type VueWrapper } from "@vue/test-utils";
import BrainstormingCanvas from "@modules/ideation/components/BrainstormingCanvas.vue";
import { bandAt, bandOffsets } from "@modules/ideation/lib/bands";
import { idea, round } from "./fixtures";

const view = reactive({ x: 0, y: 0, zoom: 1, width: 800, height: 600 });
vi.mock("@modules/ideation/composables/useCanvasViewport", () => ({
  useCanvasViewport: () => ({
    view,
    space: ref(false),
    transform: ref(""),
    world: (x: number, y: number) => ({ x, y }),
    zoomTo: vi.fn(),
    wheel: vi.fn(),
    fit: vi.fn(),
  }),
}));
const NoteStub = defineComponent({
  props: ["note"],
  setup: (props) => () => h("article", { "data-test-note": props.note.id }, "Text"),
});
const mounted: VueWrapper[] = [];
async function pointer(target: Element, type: string, options: PointerEventInit = {}) {
  target.dispatchEvent(new PointerEvent(type, { bubbles: true, cancelable: true, ...options }));
  await nextTick();
}
const capturing = () => ({
  setPointerCapture: vi.fn(),
  hasPointerCapture: () => false,
  releasePointerCapture: vi.fn(),
});
const twoRounds = () => [
  round({ id: 20, number: 1, status: "closed", prompt: "First?" }),
  round({ id: 21, number: 2, status: "active", prompt: null }),
];
function canvas(props = {}) {
  const wrapper = mount(BrainstormingCanvas, {
    attachTo: document.body,
    props: {
      notes: [
        idea({ id: 10, round_id: 20, canvas: { x: 10, y: 60 } }),
        idea({ id: 11, round_id: 21, canvas: { x: 40, y: 560 } }),
      ],
      selectedIds: [],
      editingId: null,
      permissions: { edit: true, create: true },
      historyState: { canUndo: false, canRedo: false, busy: false },
      members: [],
      statuses: {},
      collaboration: { context: { epoch: "a", session_id: 1 }, cursors: false },
      bands: {
        rounds: twoRounds(),
        offsets: new Map([
          [20, 0],
          [21, 500],
        ]),
        canManage: true,
        pending: false,
      },
      ...props,
    },
    global: { stubs: { CanvasNote: NoteStub, CanvasCursors: true } },
  });
  Object.assign(wrapper.element, capturing());
  mounted.push(wrapper);
  return wrapper;
}
afterEach(() => {
  for (const wrapper of mounted.splice(0)) wrapper.unmount();
  Object.assign(view, { x: 0, y: 0, zoom: 1 });
});

describe("band layout", () => {
  it("stacks bands as tall as their content, with a floor for empty ones", () => {
    const rounds = [
      round({ id: 3, number: 3 }),
      round({ id: 1, number: 1 }),
      round({ id: 2, number: 2 }),
    ];
    const content = new Map([
      [1, 156],
      [2, null],
      [3, 900],
    ]);
    const offsets = bandOffsets(rounds, (id) => content.get(id) ?? null);
    // 156 + 160 is under the 320 floor; an empty band is 320 tall.
    expect([...offsets]).toEqual([
      [1, 0],
      [2, 320],
      [3, 640],
    ]);
    expect(bandAt(rounds, offsets, -50)).toBe(1);
    expect(bandAt(rounds, offsets, 319)).toBe(1);
    expect(bandAt(rounds, offsets, 320)).toBe(2);
    expect(bandAt(rounds, offsets, 5000)).toBe(3);
    expect(bandAt([], offsets, 10)).toBeNull();
  });
});

describe("round bands on the canvas", () => {
  it("draws one header per round at its offset in screen space and reports the layout it measures", async () => {
    const wrapper = canvas();
    const first = wrapper.get("#brainstorming-band-20");
    expect(first.attributes("style")).toContain("top: 0px");
    expect(wrapper.get("#brainstorming-band-21").attributes("style")).toContain("top: 500px");
    expect(first.text()).toContain("Round 1");
    expect(first.text()).toContain("First?");
    expect(first.text()).toContain("Closed");
    expect(wrapper.get("#brainstorming-band-21").text()).toContain("In progress");
    // Note 10 ends at 60 + 96, so band 1 is 320 tall: the given 500 is corrected.
    expect(wrapper.emitted("bands")).toEqual([
      [
        new Map([
          [20, 0],
          [21, 320],
        ]),
      ],
    ]);
    await wrapper.setProps({
      bands: {
        rounds: twoRounds(),
        offsets: new Map([
          [20, 0],
          [21, 320],
        ]),
        canManage: true,
        pending: false,
      },
    });
    expect(wrapper.emitted("bands")).toHaveLength(1);
    view.y = -100;
    view.zoom = 0.5;
    await nextTick();
    expect(wrapper.get("#brainstorming-band-21").attributes("style")).toContain("top: 60px");
  });

  it("grows a band while a note is dragged past its bottom and shrinks it back", async () => {
    const wrapper = canvas({
      bands: {
        rounds: twoRounds(),
        offsets: new Map([
          [20, 0],
          [21, 320],
        ]),
        canManage: true,
        pending: false,
      },
    });
    const note = wrapper.get('[data-note-id="10"]');
    Object.assign(note.element, capturing());
    await pointer(note.element, "pointerdown", {
      button: 0,
      pointerId: 1,
      clientX: 20,
      clientY: 70,
    });
    await pointer(wrapper.element, "pointermove", { pointerId: 1, clientX: 20, clientY: 470 });
    // The note now ends at 460 + 96; the next header follows 160 below.
    expect(wrapper.emitted("bands")?.at(-1)).toEqual([
      new Map([
        [20, 0],
        [21, 716],
      ]),
    ]);
    await pointer(wrapper.element, "pointermove", { pointerId: 1, clientX: 20, clientY: 90 });
    // Back near the top: 80 + 96 + 160.
    expect(wrapper.emitted("bands")?.at(-1)).toEqual([
      new Map([
        [20, 0],
        [21, 336],
      ]),
    ]);
    await pointer(wrapper.element, "pointerup", { pointerId: 1 });
    expect(wrapper.emitted("move")).toEqual([[[{ id: 10, point: { x: 10, y: 80 } }]]]);
  });

  it("offers the facilitator round actions on the right rounds only", async () => {
    const wrapper = canvas();
    expect(wrapper.find("#brainstorming-round-close-20").exists()).toBe(false);
    expect(wrapper.find("#brainstorming-round-new-20").exists()).toBe(false);
    expect(wrapper.find("#brainstorming-round-close-21").exists()).toBe(true);
    await wrapper.get("#brainstorming-round-close-21").trigger("click");
    expect(wrapper.emitted("closeRound")).toEqual([[21]]);
    await wrapper.get("#brainstorming-round-new-21").trigger("click");
    expect(wrapper.emitted("newRound")).toEqual([[]]);
  });

  it("keeps the last closed band able to start the next round and hides actions from members", () => {
    const closed = canvas({
      bands: {
        rounds: [
          round({ id: 20, number: 1, status: "closed" }),
          round({ id: 21, number: 2, status: "closed" }),
        ],
        offsets: new Map([
          [20, 0],
          [21, 320],
        ]),
        canManage: true,
        pending: false,
      },
    });
    expect(closed.find("#brainstorming-round-new-20").exists()).toBe(false);
    expect(closed.find("#brainstorming-round-new-21").exists()).toBe(true);
    expect(closed.find("#brainstorming-round-close-21").exists()).toBe(false);
    closed.unmount();
    mounted.splice(mounted.indexOf(closed), 1);

    const member = canvas({
      bands: {
        rounds: [round({ id: 20, number: 1 }), round({ id: 21, number: 2 })],
        offsets: new Map([
          [20, 0],
          [21, 320],
        ]),
        canManage: false,
        pending: false,
      },
    });
    expect(member.find("#brainstorming-round-new-21").exists()).toBe(false);
    expect(member.find("#brainstorming-band-21").exists()).toBe(true);
  });

  it("stays quiet with a single round and only shows its question when there is one", () => {
    const quiet = canvas({
      notes: [idea({ id: 10, round_id: 20, canvas: { x: 10, y: 60 } })],
      bands: {
        rounds: [round({ id: 20, number: 1, prompt: null })],
        offsets: new Map([[20, 0]]),
        canManage: true,
        pending: false,
      },
    });
    expect(quiet.find("#brainstorming-band-20").exists()).toBe(false);
    expect(quiet.find("#brainstorming-round-next").exists()).toBe(false);
    quiet.unmount();
    mounted.splice(mounted.indexOf(quiet), 1);

    const asked = canvas({
      notes: [idea({ id: 10, round_id: 20, canvas: { x: 10, y: 60 } })],
      bands: {
        rounds: [round({ id: 20, number: 1, prompt: "Where does Mara go?" })],
        offsets: new Map([[20, 0]]),
        canManage: true,
        pending: false,
      },
    });
    const header = asked.get("#brainstorming-band-20");
    expect(header.text()).toContain("Where does Mara go?");
    expect(header.text()).not.toContain("Round 1");
    expect(asked.find("#brainstorming-round-new-20").exists()).toBe(false);
  });

  it("scrolls a band's header to the top at any zoom", () => {
    const wrapper = canvas();
    const scroll = (wrapper.vm as unknown as { scrollToRound: (round: { id: number }) => void })
      .scrollToRound;
    scroll(round({ id: 21 }));
    expect(view.y).toBe(60 - 500);
    view.zoom = 0.5;
    scroll(round({ id: 21 }));
    expect(view.y).toBe(60 - 250);
  });
});
