import { afterEach, describe, expect, it, vi } from "vitest";
import { defineComponent, h, nextTick, reactive, ref } from "vue";
import { mount, type VueWrapper } from "@vue/test-utils";
import BrainstormingCanvas from "@modules/ideation/components/BrainstormingCanvas.vue";
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
        rounds: [
          round({ id: 20, number: 1, status: "closed", canvas_offset_y: 0, prompt: "First?" }),
          round({ id: 21, number: 2, status: "active", canvas_offset_y: 500, prompt: null }),
        ],
        canManage: true,
        pending: false,
      },
      ...props,
    },
    global: { stubs: { CanvasNote: NoteStub, CanvasCursors: true } },
  });
  mounted.push(wrapper);
  return wrapper;
}
afterEach(() => {
  for (const wrapper of mounted.splice(0)) wrapper.unmount();
  Object.assign(view, { x: 0, y: 0, zoom: 1 });
});

describe("round bands on the canvas", () => {
  it("draws one header per round at its canvas offset, in screen space, following the viewport", async () => {
    const wrapper = canvas();
    const first = wrapper.get("#brainstorming-band-20");
    const second = wrapper.get("#brainstorming-band-21");
    expect(first.attributes("style")).toContain("top: 0px");
    expect(second.attributes("style")).toContain("top: 500px");
    expect(first.text()).toContain("Round 1");
    expect(first.text()).toContain("First?");
    expect(first.text()).toContain("Closed");
    expect(second.text()).toContain("In progress");
    view.y = -100;
    view.zoom = 0.5;
    await nextTick();
    expect(wrapper.get("#brainstorming-band-21").attributes("style")).toContain("top: 150px");
  });

  it("offers the facilitator round actions on the right rounds only", async () => {
    const wrapper = canvas();
    expect(wrapper.find("#brainstorming-round-close-20").exists()).toBe(false);
    expect(wrapper.find("#brainstorming-round-new-20").exists()).toBe(false);
    expect(wrapper.find("#brainstorming-round-close-21").exists()).toBe(true);
    await wrapper.get("#brainstorming-round-close-21").trigger("click");
    expect(wrapper.emitted("closeRound")).toEqual([[21]]);
    await wrapper.get("#brainstorming-round-new-21").trigger("click");
    // 560 + the 96 px fallback note height + the gap under the lowest note.
    expect(wrapper.emitted("newRound")).toEqual([[816]]);
  });

  it("keeps the last closed band able to start the next round and hides actions from members", () => {
    const closed = canvas({
      bands: {
        rounds: [
          round({ id: 20, number: 1, status: "closed", canvas_offset_y: 0 }),
          round({ id: 21, number: 2, status: "closed", canvas_offset_y: 500 }),
        ],
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
        rounds: [
          round({ id: 20, number: 1, canvas_offset_y: 0 }),
          round({ id: 21, number: 2, canvas_offset_y: 500 }),
        ],
        canManage: false,
        pending: false,
      },
    });
    expect(member.find("#brainstorming-round-new-21").exists()).toBe(false);
    expect(member.find("#brainstorming-round-next").exists()).toBe(false);
    expect(member.find("#brainstorming-band-21").exists()).toBe(true);
  });

  it("stays quiet with a single round and only shows its question when there is one", () => {
    const quiet = canvas({
      notes: [idea({ id: 10, round_id: 20, canvas: { x: 10, y: 60 } })],
      bands: {
        rounds: [round({ id: 20, number: 1, canvas_offset_y: 0, prompt: null })],
        canManage: true,
        pending: false,
      },
    });
    expect(quiet.find("#brainstorming-band-20").exists()).toBe(false);
    expect(quiet.find("#brainstorming-round-next").exists()).toBe(true);
    quiet.unmount();
    mounted.splice(mounted.indexOf(quiet), 1);

    const asked = canvas({
      notes: [idea({ id: 10, round_id: 20, canvas: { x: 10, y: 60 } })],
      bands: {
        rounds: [round({ id: 20, number: 1, canvas_offset_y: 0, prompt: "Where does Mara go?" })],
        canManage: true,
        pending: false,
      },
    });
    const header = asked.get("#brainstorming-band-20");
    expect(header.text()).toContain("Where does Mara go?");
    expect(header.text()).not.toContain("Round 1");
    expect(asked.find("#brainstorming-round-new-20").exists()).toBe(false);
  });

  it("places the next-round affordance under the lowest note and scrolls a band to the top", async () => {
    const wrapper = canvas();
    expect(wrapper.get("#brainstorming-round-next").attributes("style")).toContain("top: 816px");
    await wrapper.get("#brainstorming-round-next button").trigger("click");
    expect(wrapper.emitted("newRound")).toEqual([[816]]);
    (
      wrapper.vm as unknown as { scrollToRound: (round: { canvas_offset_y: number }) => void }
    ).scrollToRound(round({ id: 21, canvas_offset_y: 500 }));
    expect(view.y).toBe(60 - 500);
    view.zoom = 0.5;
    (
      wrapper.vm as unknown as { scrollToRound: (round: { canvas_offset_y: number }) => void }
    ).scrollToRound(round({ id: 21, canvas_offset_y: 500 }));
    expect(view.y).toBe(60 - 250);
  });
});
