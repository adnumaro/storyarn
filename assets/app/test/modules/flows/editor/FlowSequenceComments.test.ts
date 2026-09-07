import { mount } from "@vue/test-utils";
import { createMockLive } from "@app/test/setup";
import type { FlowCommentsPanelState, FlowCommentThread } from "@modules/flows/types/comments";
const live = createMockLive();
vi.mock("@shared/composables/useLive", () => ({ useLive: () => live }));
const { default: Comments } =
  await import("@modules/flows/editor/components/sequence/FlowSequenceComments.vue");
const author = { id: 4, display_name: "Ada", avatar_url: null };
const thread: FlowCommentThread = {
  id: 12,
  status: "open",
  revision: 1,
  message_count: 1,
  created_at: "2026-09-06T12:00:00Z",
  last_activity_at: "2026-09-06T12:00:00Z",
  resolved_at: null,
  resolved_by: null,
  author,
  preview: "Move the character",
  source: { type: "flow_node", id: 42, flow_id: 7, label: "Dialogue #42", status: "available" },
};
function state(overrides: Partial<FlowCommentsPanelState> = {}): FlowCommentsPanelState {
  return {
    open: true,
    presentation: "workspace",
    selectedNodeId: 42,
    threads: [thread],
    thread: null,
    nextCursor: null,
    messages: [],
    messageNextCursor: null,
    members: [author],
    canComment: true,
    error: null,
    ...overrides,
  };
}
beforeEach(() => vi.mocked(live.pushEvent).mockClear());
it("opens the current intervention, reuses the thread and keeps Back scoped to Sequence", async () => {
  const wrapper = mount(Comments, { props: { nodeId: 42, state: state({ open: false }) } });
  await wrapper.get("[data-sequence-comments-toggle]").trigger("click");
  expect(live.pushEvent).toHaveBeenCalledWith("comments_open", {
    node_id: 42,
    presentation: "workspace",
  });
  await wrapper.setProps({ state: state() });
  await wrapper.get("#sequence-comment-thread-12").trigger("click");
  expect(live.pushEvent).toHaveBeenCalledWith("comments_select_thread", { thread_id: 12 });
  await wrapper.setProps({ state: state({ thread }) });
  await wrapper.get("#sequence-comment-back").trigger("click");
  expect(live.pushEvent).toHaveBeenLastCalledWith("comments_open", {
    node_id: 42,
    presentation: "workspace",
  });
  wrapper.unmount();
});
it("follows intervention changes and closes the workspace discussion on unmount", async () => {
  const wrapper = mount(Comments, { props: { nodeId: 42, state: state() } });
  await wrapper.setProps({ nodeId: 43 });
  expect(live.pushEvent).toHaveBeenCalledWith("comments_open", {
    node_id: 43,
    presentation: "workspace",
  });
  expect(wrapper.find("#sequence-comments").exists()).toBe(false);
  wrapper.unmount();
  expect(live.pushEvent).toHaveBeenLastCalledWith("comments_close", {});
});
it("does not show another surface's conversation and respects read-only access", async () => {
  const wrapper = mount(Comments, {
    props: { nodeId: 42, state: state({ presentation: "canvas" }) },
  });
  expect(wrapper.find("#sequence-comments").exists()).toBe(false);
  await wrapper.setProps({ state: state({ canComment: false }) });
  expect(wrapper.find("textarea").exists()).toBe(false);
  wrapper.unmount();
});
