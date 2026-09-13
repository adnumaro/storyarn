import { mount, flushPromises } from "@vue/test-utils";
import { createMockLive } from "@app/test/setup";
import type { FlowCommentsPanelState, FlowCommentThread } from "@modules/flows/types/comments";
const live = createMockLive();
vi.mock("@shared/composables/useLive", () => ({ useLive: () => live }));
const { default: Comments } =
  await import("@modules/flows/editor/components/sequence/FlowSequenceCommentDialog.vue");
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
  source: { type: "flow_canvas", id: 7, flow_id: 7, label: "Flow", status: "available" },
  context: {
    type: "flow_node",
    id: "42",
    label: "Dialogue #42",
    status: "available",
    offset: { x: 16, y: 16 },
  },
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
it("shows a contextual composer without a toolbar toggle or thread list", async () => {
  const wrapper = mount(Comments, {
    attachTo: document.body,
    global: { stubs: { DialogPortal: { template: "<div><slot /></div>" } } },
    props: { nodeId: 42, state: state() },
  });
  await flushPromises();
  expect(wrapper.find("[data-sequence-comments-toggle]").exists()).toBe(false);
  expect(wrapper.find("#sequence-comment-thread-12").exists()).toBe(false);
  expect(wrapper.find("#sequence-comment-body").exists()).toBe(true);
  expect(wrapper.find("aside").exists()).toBe(false);
  wrapper.unmount();
});
it("follows intervention changes and closes the workspace discussion on unmount", async () => {
  const wrapper = mount(Comments, {
    attachTo: document.body,
    global: { stubs: { DialogPortal: { template: "<div><slot /></div>" } } },
    props: { nodeId: 42, state: state() },
  });
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
    attachTo: document.body,
    global: { stubs: { DialogPortal: { template: "<div><slot /></div>" } } },
    props: { nodeId: 42, state: state({ presentation: "canvas" }) },
  });
  expect(wrapper.find("#sequence-comments").exists()).toBe(false);
  await wrapper.setProps({ state: state({ canComment: false }) });
  expect(wrapper.find("textarea").exists()).toBe(false);
  wrapper.unmount();
});
