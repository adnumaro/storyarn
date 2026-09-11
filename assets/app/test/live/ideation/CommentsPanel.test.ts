import { describe, expect, it, vi } from "vitest";
import { mount } from "@vue/test-utils";
import Panel from "@app/live/ideation/CommentsPanel.vue";
import type { CommentsPanelState, CommentThread } from "@components/comments/types";

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
const thread: CommentThread = {
  id: 7,
  status: "open",
  revision: 2,
  message_count: 1,
  created_at: "2026-09-11T10:00:00Z",
  last_activity_at: "2026-09-11T10:00:00Z",
  resolved_at: null,
  resolved_by: null,
  author: { id: 1, display_name: "Designer", avatar_url: null },
  source: { type: "ideation_group", id: 22, label: "Group #22", status: "available" },
  following: false,
  unread: true,
  last_message_id: 45,
};
function panel(overrides: Partial<typeof state> & { groupId?: number | null } = {}) {
  const pushEvent = vi.fn();
  const wrapper = mount(Panel, {
    props: {
      state: { ...state, ...overrides },
      epoch: "epoch-1",
      sessionId: 12,
      baseUrl: "/brainstorming",
    },
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
    expect(wrapper.text()).toContain("Mention people");
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

  it("allows viewers to follow and explicitly acknowledge only the received message watermark", async () => {
    const { wrapper, pushEvent } = panel({ thread, groupId: 22, canComment: false });
    expect(pushEvent).not.toHaveBeenCalled();
    expect(wrapper.find("textarea").exists()).toBe(false);
    await wrapper.get("#brainstorming-comment-follow").trigger("click");
    expect(pushEvent.mock.calls[0][0]).toBe("comments_follow");
    expect(pushEvent.mock.calls[0][1]).toMatchObject({
      thread_id: 7,
      following: true,
      comment_context: "context-1",
      epoch: "epoch-1",
      session_id: 12,
    });
    pushEvent.mock.calls[0][2]({ ok: true });
    await wrapper.vm.$nextTick();
    await wrapper.get("#brainstorming-comment-read").trigger("click");
    expect(pushEvent.mock.calls[1][0]).toBe("comments_read");
    expect(pushEvent.mock.calls[1][1]).toMatchObject({ thread_id: 7, message_id: 45 });
    pushEvent.mock.calls[1][2]({ ok: false });
    await wrapper.vm.$nextTick();
    expect(wrapper.get("[role='alert']").text()).toContain("Could not update");
    expect(wrapper.get("#brainstorming-comment-follow").attributes("disabled")).toBeUndefined();
    wrapper.unmount();
  });

  it("ignores a late personal-state reply after changing the discussion context", async () => {
    const { wrapper, pushEvent } = panel({ thread });
    await wrapper.get("#brainstorming-comment-follow").trigger("click");
    const late = pushEvent.mock.calls[0][2];
    await wrapper.setProps({
      state: { ...state, thread: { ...thread, id: 8 }, context: "context-2" },
    });
    late({ ok: false });
    await wrapper.vm.$nextTick();
    expect(wrapper.find("[role='alert']").exists()).toBe(false);
    expect(wrapper.get("#brainstorming-comment-follow").attributes("disabled")).toBeUndefined();
    wrapper.unmount();
  });
});
