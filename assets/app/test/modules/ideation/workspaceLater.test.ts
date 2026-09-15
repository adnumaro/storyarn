import { afterEach, describe, expect, it, vi } from "vitest";
import { shallowMount, flushPromises, type VueWrapper } from "@vue/test-utils";
import { defineComponent, h } from "vue";
import Workspace from "@modules/ideation/BrainstormingWorkspace.vue";
import { createMockLive } from "../../setup";
import { board, idea, round } from "./fixtures";

const Canvas = defineComponent({
  name: "BrainstormingCanvas",
  props: ["notes", "selectedIds"],
  setup(_props, { expose, slots }) {
    expose({ focus: vi.fn() });
    return () => h("div", slots.selection?.({ connectionTools: {} }));
  },
});
let wrapper: VueWrapper;
const closed = round({ id: 20, number: 1, status: "closed" });
const active = round({ id: 21, number: 2, status: "active", prompt: null });
function workspace() {
  const live = createMockLive();
  const current = board({
    rounds: [closed, active],
    active_round: active,
    ideas: [
      idea({ id: 10, round_id: 20, state: "parked", body: "<p>Waiting</p>" }),
      idea({ id: 11, round_id: 20, state: "parked", body: "<p>Already brought</p>" }),
      idea({
        id: 12,
        round_id: 21,
        source_idea_id: 11,
        source_revision: 1,
        body: "<p>Brought</p>",
      }),
      idea({ id: 13, round_id: 21, state: "parked", body: "<p>Parked here</p>" }),
    ],
  });
  wrapper = shallowMount(Workspace, {
    // The session tree's "For later" link arrives as a prop.
    props: {
      board: current,
      baseUrl: "/brainstorming",
      linked: { round_id: null, view: "later", seq: 1 },
    },
    global: {
      provide: { _live_vue: live },
      renderStubDefaultSlot: true,
      stubs: { BrainstormingCanvas: Canvas },
    },
  });
  return { live, current };
}
afterEach(() => {
  wrapper?.unmount();
  vi.restoreAllMocks();
});

describe("the For later list", () => {
  it("lists parked notes that have no copy ahead, and brings one into the round in progress", async () => {
    const { live } = workspace();
    await flushPromises();
    expect(wrapper.find("#canvas-list-note-10").exists()).toBe(true);
    expect(wrapper.find("#canvas-list-note-13").exists()).toBe(true);
    expect(wrapper.find("#canvas-list-note-11").exists()).toBe(false);
    expect(wrapper.find("#canvas-list-note-12").exists()).toBe(false);
    // Only a note of another round can be brought; one parked in the round in progress comes back instead.
    expect(wrapper.find("#canvas-list-bring-13").exists()).toBe(false);

    await wrapper.get("#canvas-list-bring-10").trigger("click");
    await flushPromises();
    expect(vi.mocked(live.pushEvent).mock.calls.map(([name]) => name)).toContain(
      "bring_idea_forward",
    );
    const [, payload] = vi
      .mocked(live.pushEvent)
      .mock.calls.find(([name]) => name === "bring_idea_forward")!;
    expect(payload).toMatchObject({
      idea_id: 10,
      canvas: { x: expect.any(Number), y: expect.any(Number) },
    });
  });
});
