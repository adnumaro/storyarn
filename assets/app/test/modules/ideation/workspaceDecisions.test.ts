import { afterEach, describe, expect, it, vi } from "vitest";
import { shallowMount, flushPromises, type VueWrapper } from "@vue/test-utils";
import { defineComponent, h } from "vue";
import Workspace from "@modules/ideation/BrainstormingWorkspace.vue";
import { createMockLive } from "../../setup";
import { board, idea, ideaGroup, round } from "./fixtures";
import type { Board } from "@modules/ideation/types";
const Canvas = defineComponent({
  name: "BrainstormingCanvas",
  props: ["notes", "selectedIds"],
  setup(_props, { expose, slots }) {
    expose({ focus: vi.fn() });
    return () => h("div", slots.selection?.({ connectionTools: {} }));
  },
});
let wrapper: VueWrapper;
function workspace(overrides: Partial<Board> = {}, decisionDraft = false) {
  const live = createMockLive();
  const current = board({
    ideas: [idea({ visibility: "shared", published_revision: 2 }), idea({ id: 11 })],
    ...overrides,
  });
  wrapper = shallowMount(Workspace, {
    props: { board: current, baseUrl: "/brainstorming", decisionDraft },
    global: {
      provide: { _live_vue: live },
      renderStubDefaultSlot: true,
      stubs: { BrainstormingCanvas: Canvas },
    },
  });
  return { live, current, canvas: wrapper.getComponent(Canvas) };
}
afterEach(() => {
  wrapper?.unmount();
  vi.restoreAllMocks();
});
describe("decisions from the brainstorming canvas", () => {
  it("previews shared selected ideas by ID without sending private draft content or accepting anything", async () => {
    const { live, canvas } = workspace();
    canvas.vm.$emit("select", [10]);
    await flushPromises();
    await wrapper.get("#brainstorming-propose-decision").trigger("click");
    await wrapper.get("#brainstorming-propose-decision").trigger("click");
    expect(live.pushEvent).toHaveBeenCalledTimes(1);
    expect(vi.mocked(live.pushEvent).mock.calls[0].slice(0, 2)).toEqual([
      "decisions_new",
      { idea_ids: [10], session_id: 1, epoch: "epoch-one" },
    ]);
  });
  it("adds the selection to an open proposal instead of starting another", async () => {
    const { live, canvas } = workspace({}, true);
    canvas.vm.$emit("select", [10]);
    await flushPromises();
    expect(wrapper.get("#brainstorming-propose-decision").attributes("aria-label")).toBe(
      "Add to the proposal",
    );
    await wrapper.get("#brainstorming-propose-decision").trigger("click");
    expect(vi.mocked(live.pushEvent).mock.calls[0].slice(0, 2)).toEqual([
      "decisions_add_sources",
      { idea_ids: [10], session_id: 1, epoch: "epoch-one" },
    ]);
  });
  it("blocks a mixed shared/private selection and a group of a private round", async () => {
    const { live, canvas, current } = workspace();
    canvas.vm.$emit("select", [10, 11]);
    await flushPromises();
    await wrapper.get("#brainstorming-propose-decision").trigger("click");
    expect(live.pushEvent).not.toHaveBeenCalled();
    // The group's notes belong to a round that is still private.
    await wrapper.setProps({
      board: {
        ...current,
        rounds: [round({ id: 20, private: true })],
        ideas: current.ideas.map((idea) => ({ ...idea, round_id: 20 })),
        groups: [ideaGroup()],
      },
    });
    canvas.vm.$emit("propose-group-decision", 40);
    await flushPromises();
    expect(live.pushEvent).not.toHaveBeenCalled();
  });
  it("previews a group as a single source and ignores a late failure from the previous session", async () => {
    const { live, canvas, current } = workspace();
    canvas.vm.$emit("propose-group-decision", 40);
    await flushPromises();
    const [event, payload, reply] = vi.mocked(live.pushEvent).mock.calls[0];
    expect(event).toBe("decisions_new");
    expect(payload).toEqual({ group_id: 40, session_id: 1, epoch: "epoch-one" });
    await wrapper.setProps({
      board: { ...current, epoch: "epoch-two", session: { ...current.session!, id: 2 } },
    });
    reply?.({ status: "error", code: "private_round" });
    await flushPromises();
    expect(wrapper.text()).not.toContain("Decisions are available when");
  });
});
