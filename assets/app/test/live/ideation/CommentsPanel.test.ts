import { describe, expect, it, vi } from "vitest";
import { mount } from "@vue/test-utils";
import Panel from "@app/live/ideation/CommentsPanel.vue";
import type { CommentsPanelState } from "@components/comments/types";

const state: CommentsPanelState & { ideaId: number | null; context: string } = {
  open: true,
  presentation: "workspace",
  threads: [],
  nextCursor: null,
  thread: null,
  messages: [],
  messageNextCursor: null,
  members: [],
  canComment: true,
  selectedSourceId: 12,
  statusFilter: "open",
  error: null,
  ideaId: null,
  context: "context-1",
};
function panel() {
  const pushEvent = vi.fn();
  const wrapper = mount(Panel, {
    props: { state: { ...state }, epoch: "epoch-1", sessionId: 12, baseUrl: "/brainstorming" },
    global: {
      provide: {
        _live_vue: { pushEvent, handleEvent: vi.fn(), removeHandleEvent: vi.fn(), upload: vi.fn() },
      },
      stubs: {
        Sidebar: { template: "<aside><slot name='header'/><slot/><slot name='footer'/></aside>" },
      },
    },
  });
  return { wrapper, pushEvent };
}

describe("Brainstorming comments boundary", () => {
  it("scopes the reused composer to the board and retries without duplicating request identity", async () => {
    const { wrapper, pushEvent } = panel();
    await wrapper.get("#brainstorming-comment-body").setValue("Why this ending?");
    await wrapper.get("form").trigger("submit");
    const [event, request, callback] = pushEvent.mock.calls[0];
    expect(event).toBe("comments_create");
    expect(request).toMatchObject({
      epoch: "epoch-1",
      session_id: 12,
      comment_context: "context-1",
      body: "Why this ending?",
      mention_user_ids: [],
    });
    callback({ ok: false, error: "unavailable" });
    await wrapper.vm.$nextTick();
    expect((wrapper.get("textarea").element as HTMLTextAreaElement).value).toBe("Why this ending?");
    await wrapper.get("form").trigger("submit");
    expect(pushEvent.mock.calls[1][1].client_request_id).toBe(request.client_request_id);
    expect(wrapper.text()).not.toContain("Mention people");
    wrapper.unmount();
  });

  it("drops the private composer when the server invalidates the discussion", async () => {
    const { wrapper } = panel();
    await wrapper.get("textarea").setValue("Private buffer");
    await wrapper.setProps({ state: { ...state, open: false, context: "revoked" } });
    expect(wrapper.find("textarea").exists()).toBe(false);
    await wrapper.setProps({ state: { ...state, context: "new-context" } });
    expect((wrapper.get("textarea").element as HTMLTextAreaElement).value).toBe("");
    wrapper.unmount();
  });
});
