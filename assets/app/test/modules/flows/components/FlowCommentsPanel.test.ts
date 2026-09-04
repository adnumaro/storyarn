import { beforeEach, describe, expect, it, vi } from "vitest";
import { mount } from "@vue/test-utils";
import { createMockLive } from "@app/test/setup";
import type {
  FlowCommentMessage,
  FlowCommentPosition,
  FlowCommentsPanelState,
  FlowCommentThread,
} from "@modules/flows/types/comments";

const mockLive = createMockLive();
vi.mock("@shared/composables/useLive", () => ({ useLive: () => mockLive }));
const { default: FlowCommentsPanel } =
  await import("@modules/flows/editor/components/panels/FlowCommentsPanel.vue");
const { default: FlowCommentComposer } =
  await import("@modules/flows/editor/components/panels/comments/FlowCommentComposer.vue");

const author = { id: 4, display_name: "Ada", avatar_url: null };
const member = { id: 8, display_name: "Grace", avatar_url: null };
const thread: FlowCommentThread = {
  id: 12,
  status: "open",
  revision: 3,
  message_count: 1,
  created_at: "2026-09-04T09:00:00Z",
  last_activity_at: "2026-09-04T09:00:00Z",
  resolved_at: null,
  resolved_by: null,
  author,
  preview: "Why does the guard leave?",
  source: { type: "flow_node", id: 42, flow_id: 7, label: "Dialogue #42", status: "available" },
};
const message: FlowCommentMessage = {
  id: 21,
  thread_id: 12,
  parent_id: null,
  body: "Why does the guard leave?",
  author,
  mentions: [member],
  inserted_at: "2026-09-04T09:00:00Z",
};
const base: FlowCommentsPanelState = {
  open: true,
  threads: [thread],
  nextCursor: null,
  thread: null,
  messages: [],
  messageNextCursor: null,
  members: [author, member],
  canComment: true,
  selectedNodeId: null,
  error: null,
  statusFilter: "open",
};
const passthrough = { template: "<div><slot /></div>" };
const stubs = {
  Sidebar: { template: "<aside><slot name='header'/><slot/><slot name='footer'/></aside>" },
  Popover: passthrough,
  PopoverContent: passthrough,
  PopoverTrigger: passthrough,
};

function panel(overrides: Partial<FlowCommentsPanelState> = {}, embedded = false) {
  return mount(FlowCommentsPanel, {
    props: { state: { ...base, ...overrides }, embedded },
    global: { stubs },
  });
}

function composer(
  overrides: Partial<{
    nodeId: number | null;
    threadId: number | null;
    parentId: number | null;
    position: FlowCommentPosition | null;
    draftId: string | null;
    disabled: boolean;
  }> = {},
) {
  return mount(FlowCommentComposer, {
    props: { nodeId: 42, members: [author, member], ...overrides },
    global: { stubs },
  });
}

function lastReply() {
  return vi.mocked(mockLive.pushEvent).mock.calls.at(-1)![2]!;
}

describe("Flow comments panel", () => {
  beforeEach(() => vi.mocked(mockLive.pushEvent).mockClear());

  it("lists thread previews and selects the thread with its stable id", async () => {
    const wrapper = panel();
    expect(wrapper.get("#flow-comment-thread-12").text()).toContain(thread.preview);
    await wrapper.get("#flow-comment-thread-12").trigger("click");
    expect(mockLive.pushEvent).toHaveBeenCalledWith("comments_select_thread", { thread_id: 12 });
  });

  it("renders a compact canvas draft without the sidebar or thread index", async () => {
    const position = { x: -240.5, y: 180 };
    const wrapper = panel({ presentation: "canvas", draftPosition: position }, true);
    expect(wrapper.find("aside").exists()).toBe(false);
    expect(wrapper.find("#flow-comments-filter").exists()).toBe(false);
    expect(wrapper.find("#flow-comment-thread-12").exists()).toBe(false);
    await wrapper.get("textarea").setValue("Connect these two branches.");
    await wrapper.get("form").trigger("submit");
    expect(mockLive.pushEvent).toHaveBeenCalledWith(
      "comments_create",
      expect.objectContaining({ node_id: null, position, body: "Connect these two branches." }),
      expect.any(Function),
      expect.any(Function),
    );
    await wrapper.get("#flow-comment-popover-close").trigger("click");
    expect(mockLive.pushEvent).toHaveBeenCalledWith("comments_close", {});
  });

  it("keeps canvas threads readable and resolvable in the floating conversation", async () => {
    const wrapper = panel(
      {
        presentation: "canvas",
        thread: { ...thread, source: { ...thread.source, type: "flow_canvas", id: 7 } },
        messages: [message],
      },
      true,
    );
    expect(wrapper.text()).toContain("Flow canvas");
    expect(wrapper.text()).toContain(message.body);
    expect(wrapper.text()).toContain(member.display_name);
    expect(wrapper.text()).not.toContain("All threads");
    await wrapper.get("#flow-comment-status").trigger("click");
    expect(mockLive.pushEvent).toHaveBeenCalledWith(
      "comments_set_status",
      { thread_id: 12, status: "resolved", expected_revision: 3 },
      expect.any(Function),
      expect.any(Function),
    );
  });

  it("does not duplicate the conversation in the sidebar while it is on the canvas", () => {
    const wrapper = panel({ presentation: "canvas", thread, messages: [message] });
    expect(wrapper.find("#flow-comments-content").exists()).toBe(false);
    expect(wrapper.find("textarea").exists()).toBe(false);
    expect(wrapper.get("aside").attributes("open")).toBe("false");
  });

  it("filters resolved discussions and loads subsequent thread pages", async () => {
    const wrapper = panel({ nextCursor: 11 });
    await wrapper.get("#flow-comments-filter").setValue("resolved");
    expect(mockLive.pushEvent).toHaveBeenCalledWith("comments_filter", { status: "resolved" });
    await wrapper
      .findAll("button")
      .find((button) => button.text() === "Load more threads")!
      .trigger("click");
    expect(mockLive.pushEvent).toHaveBeenCalledWith("comments_load_more", {});
  });

  it("allows viewers to read messages without reply or resolution controls", () => {
    const wrapper = panel({ thread, messages: [message], canComment: false });
    expect(wrapper.text()).toContain(message.body);
    expect(wrapper.text()).toContain(member.display_name);
    expect(wrapper.find("#flow-comment-status").exists()).toBe(false);
    expect(wrapper.find("textarea").exists()).toBe(false);
  });

  it("preserves unavailable node discussions and disables mutations", () => {
    const wrapper = panel({
      thread: { ...thread, source: { ...thread.source, status: "unavailable" } },
      messages: [message],
    });
    expect(wrapper.text()).toContain("This node is no longer available");
    expect(wrapper.text()).toContain(message.body);
    expect(wrapper.find("#flow-comment-status").exists()).toBe(false);
    expect(wrapper.get("textarea").attributes("disabled")).toBeDefined();
  });

  it("resolves with the current revision and reports server failures", async () => {
    const wrapper = panel({ thread, messages: [message] });
    await wrapper.get("#flow-comment-status").trigger("click");
    expect(mockLive.pushEvent).toHaveBeenCalledWith(
      "comments_set_status",
      { thread_id: 12, status: "resolved", expected_revision: 3 },
      expect.any(Function),
      expect.any(Function),
    );
    lastReply()({ ok: false, error: "This thread changed. Try again." });
    await wrapper.vm.$nextTick();
    expect(wrapper.get('[role="alert"]').text()).toContain("This thread changed");
    expect(wrapper.get("#flow-comment-status").attributes("disabled")).toBeUndefined();
  });

  it("requires reopening a resolved discussion before replying", async () => {
    const wrapper = panel({ thread: { ...thread, status: "resolved" }, messages: [message] });
    expect(wrapper.get("textarea").attributes("disabled")).toBeDefined();
    await wrapper.get("#flow-comment-status").trigger("click");
    expect(mockLive.pushEvent).toHaveBeenCalledWith(
      "comments_set_status",
      { thread_id: 12, status: "open", expected_revision: 3 },
      expect.any(Function),
      expect.any(Function),
    );
  });

  it.each(["reply", "transport"] as const)(
    "ignores a stale %s callback after navigating A to B to A during a newer request",
    async (failureKind) => {
      const wrapper = panel({ thread, messages: [message] });
      await wrapper.get("#flow-comment-status").trigger("click");
      const oldRequest = vi.mocked(mockLive.pushEvent).mock.calls.at(-1)!;
      await wrapper.setProps({ state: { ...base, thread: { ...thread, id: 13 } } });
      await wrapper.setProps({ state: { ...base, thread, messages: [message] } });
      await wrapper.get("#flow-comment-status").trigger("click");
      const currentRequest = vi.mocked(mockLive.pushEvent).mock.calls.at(-1)!;

      if (failureKind === "reply") oldRequest[2]!({ ok: false, error: "Old response" });
      else oldRequest[3]!(new Error("Old transport failure"));
      await wrapper.vm.$nextTick();

      expect(wrapper.get("#flow-comment-status").attributes("disabled")).toBeDefined();
      expect(wrapper.find('[role="alert"]').exists()).toBe(false);
      currentRequest[2]!({ ok: true });
      await wrapper.vm.$nextTick();
      expect(wrapper.get("#flow-comment-status").attributes("disabled")).toBeUndefined();
    },
  );

  it.each(["reply", "transport"] as const)(
    "preserves the newer error when a stale %s callback returns after navigating A to B to A",
    async (failureKind) => {
      const wrapper = panel({ thread, messages: [message] });
      await wrapper.get("#flow-comment-status").trigger("click");
      const oldRequest = vi.mocked(mockLive.pushEvent).mock.calls.at(-1)!;
      await wrapper.setProps({ state: { ...base, thread: { ...thread, id: 13 } } });
      await wrapper.setProps({ state: { ...base, thread, messages: [message] } });
      await wrapper.get("#flow-comment-status").trigger("click");
      lastReply()({ ok: false, error: "Current request failed" });
      await wrapper.vm.$nextTick();

      if (failureKind === "reply") oldRequest[2]!({ ok: false, error: "Old response" });
      else oldRequest[3]!(new Error("Old transport failure"));
      await wrapper.vm.$nextTick();

      expect(wrapper.get('[role="alert"]').text()).toBe("Current request failed");
    },
  );

  it("submits an explicit reply to the chosen message", async () => {
    const reply: FlowCommentMessage = {
      ...message,
      id: 22,
      parent_id: 21,
      author: member,
      body: "He has another duty.",
    };
    const wrapper = panel({ thread, messages: [message, reply] });
    await wrapper.get('button[aria-label="Reply to Grace"]').trigger("click");
    await wrapper.get("textarea").setValue("What duty?");
    await wrapper.get("form").trigger("submit");
    expect(mockLive.pushEvent).toHaveBeenCalledWith(
      "comments_reply",
      expect.objectContaining({ thread_id: 12, parent_id: 22, body: "What duty?" }),
      expect.any(Function),
      expect.any(Function),
    );
  });
});

describe("Flow comment composer delivery", () => {
  beforeEach(() => vi.mocked(mockLive.pushEvent).mockClear());

  it("retains a failed draft and reuses the request id when retrying", async () => {
    const wrapper = composer();
    await wrapper.get("textarea").setValue("  Reconsider this response.  ");
    await wrapper.get("form").trigger("submit");
    const firstPayload = vi.mocked(mockLive.pushEvent).mock.calls[0][1];
    expect(firstPayload).toMatchObject({
      node_id: 42,
      body: "Reconsider this response.",
      mention_user_ids: [],
    });
    expect(firstPayload?.client_request_id).toMatch(/^[a-f0-9-]{36}$/);
    lastReply()({ ok: false, error: "Please retry." });
    await wrapper.vm.$nextTick();
    expect((wrapper.get("textarea").element as HTMLTextAreaElement).value).toContain(
      "Reconsider this response.",
    );
    await wrapper.get("form").trigger("submit");
    expect(vi.mocked(mockLive.pushEvent).mock.calls[1][1]).toEqual(firstPayload);
    lastReply()({ ok: true });
    await wrapper.vm.$nextTick();
    expect((wrapper.get("textarea").element as HTMLTextAreaElement).value).toBe("");
  });

  it("preserves independent drafts and retry ids for free canvas positions", async () => {
    const firstPosition = { x: -125.5, y: 250 };
    const secondPosition = { x: 80, y: 250 };
    const wrapper = composer({ nodeId: null, position: firstPosition });
    await wrapper.get("textarea").setValue("First canvas draft");
    await wrapper.get("form").trigger("submit");
    const request = vi.mocked(mockLive.pushEvent).mock.calls.at(-1)!;
    request[3]!(new Error("Response lost"));
    await wrapper.setProps({ position: secondPosition });
    expect((wrapper.get("textarea").element as HTMLTextAreaElement).value).toBe("");
    await wrapper.get("textarea").setValue("Second canvas draft");
    await wrapper.setProps({ nodeId: 42, position: null });
    await wrapper.get("textarea").setValue("Node draft");
    await wrapper.setProps({ nodeId: null, position: { ...firstPosition } });
    expect((wrapper.get("textarea").element as HTMLTextAreaElement).value).toBe(
      "First canvas draft",
    );
    await wrapper.get("form").trigger("submit");
    expect(vi.mocked(mockLive.pushEvent).mock.calls.at(-1)![1]).toEqual(request[1]);
    await wrapper.setProps({ position: secondPosition });
    lastReply()({ ok: true });
    await wrapper.vm.$nextTick();
    expect((wrapper.get("textarea").element as HTMLTextAreaElement).value).toBe(
      "Second canvas draft",
    );
    expect(wrapper.emitted("sent")).toBeUndefined();
    await wrapper.setProps({ nodeId: 42, position: null });
    expect((wrapper.get("textarea").element as HTMLTextAreaElement).value).toBe("Node draft");
  });

  it("does not send an unplaced draft or include a position in replies", async () => {
    const wrapper = composer({ nodeId: null });
    await wrapper.get("textarea").setValue("Needs a position");
    await wrapper.get("form").trigger("submit");
    expect(mockLive.pushEvent).not.toHaveBeenCalled();
    await wrapper.setProps({ threadId: 12, parentId: 21, position: { x: 50, y: 60 } });
    await wrapper.get("textarea").setValue("A reply");
    await wrapper.get("form").trigger("submit");
    expect(vi.mocked(mockLive.pushEvent).mock.calls.at(-1)![1]).not.toHaveProperty("position");
  });

  it("keeps the same draft when its pin moves and uses the new position when sending", async () => {
    const firstPosition = { x: 20, y: 30 };
    const movedPosition = { x: 90, y: 110 };
    const wrapper = composer({ nodeId: null, position: firstPosition, draftId: "draft-a" });
    await wrapper.get("textarea").setValue("Move this comment closer to the ending.");
    await wrapper.setProps({ position: movedPosition });
    expect((wrapper.get("textarea").element as HTMLTextAreaElement).value).toBe(
      "Move this comment closer to the ending.",
    );
    await wrapper.get("form").trigger("submit");
    const movedRequest = vi.mocked(mockLive.pushEvent).mock.calls.at(-1)!;
    expect(movedRequest[1]).toMatchObject({ node_id: null, position: movedPosition });
    movedRequest[2]!({ ok: false });
    await wrapper.setProps({ position: firstPosition });
    await wrapper.get("form").trigger("submit");
    const nextRequest = vi.mocked(mockLive.pushEvent).mock.calls.at(-1)!;
    expect(nextRequest[1]?.client_request_id).not.toBe(movedRequest[1]?.client_request_id);
    expect(nextRequest[1]?.position).toEqual(firstPosition);
    await wrapper.setProps({ draftId: "draft-b" });
    expect((wrapper.get("textarea").element as HTMLTextAreaElement).value).toBe("");
    await wrapper.setProps({ draftId: "draft-a" });
    expect((wrapper.get("textarea").element as HTMLTextAreaElement).value).toBe(
      "Move this comment closer to the ending.",
    );
  });

  it("keeps drafts for different nodes separate and survives transport errors", async () => {
    const wrapper = composer();
    await wrapper.get("textarea").setValue("Node 42 draft");
    await wrapper.get("form").trigger("submit");
    vi.mocked(mockLive.pushEvent).mock.calls[0][3]!(new Error("Disconnected"));
    await wrapper.setProps({ nodeId: 43 });
    await wrapper.get("textarea").setValue("Node 43 draft");
    await wrapper.setProps({ nodeId: 42 });
    expect((wrapper.get("textarea").element as HTMLTextAreaElement).value).toBe("Node 42 draft");
    expect(wrapper.get('[role="alert"]').text()).toContain("Your draft is saved");
  });

  it("sends mentions as explicit member ids and rotates id after content changes", async () => {
    const wrapper = composer();
    await wrapper
      .findAll("button")
      .find((button) => button.text() === "Grace")!
      .trigger("click");
    await wrapper.get("textarea").setValue("Please review.");
    await wrapper.get("form").trigger("submit");
    const first = vi.mocked(mockLive.pushEvent).mock.calls[0][1];
    expect(first?.mention_user_ids).toEqual([8]);
    lastReply()({ ok: false });
    await wrapper.vm.$nextTick();
    await wrapper.get("textarea").setValue("Please review the ending.");
    await wrapper.get("form").trigger("submit");
    expect(vi.mocked(mockLive.pushEvent).mock.calls[1][1]?.client_request_id).not.toBe(
      first?.client_request_id,
    );
  });

  it("reuses the same request after a lost response and reordering the same mentions", async () => {
    const wrapper = composer();
    const thirdMember = { id: 20, display_name: "Lin", avatar_url: null };
    await wrapper.setProps({ members: [author, member, thirdMember] });
    for (const name of ["Ada", "Grace", "Lin"]) {
      await wrapper
        .findAll("button[aria-pressed]")
        .find((button) => button.text() === name)!
        .trigger("click");
    }
    await wrapper.get("textarea").setValue("Please review this scene.");
    await wrapper.get("form").trigger("submit");
    const originalRequest = vi.mocked(mockLive.pushEvent).mock.calls.at(-1)!;
    originalRequest[3]!(new Error("Response lost after commit"));
    await wrapper.vm.$nextTick();

    await wrapper.get('button[aria-label="Remove mention of Ada"]').trigger("click");
    await wrapper
      .findAll("button[aria-pressed]")
      .find((button) => button.text() === "Ada")!
      .trigger("click");
    await wrapper.get("form").trigger("submit");
    const retry = vi.mocked(mockLive.pushEvent).mock.calls.at(-1)!;

    expect(retry[1]).toEqual(originalRequest[1]);
    expect(retry[1]?.mention_user_ids).toEqual([4, 8, 20]);
  });

  it("clears only the submitted draft if context changes before acknowledgment", async () => {
    const wrapper = composer();
    await wrapper.get("textarea").setValue("First draft");
    await wrapper.get("form").trigger("submit");
    const reply = lastReply();
    await wrapper.setProps({ nodeId: 43 });
    await wrapper.get("textarea").setValue("Second draft");
    reply({ ok: true });
    await wrapper.vm.$nextTick();
    expect((wrapper.get("textarea").element as HTMLTextAreaElement).value).toBe("Second draft");
    await wrapper.setProps({ nodeId: 42 });
    expect((wrapper.get("textarea").element as HTMLTextAreaElement).value).toBe("");
  });
});
