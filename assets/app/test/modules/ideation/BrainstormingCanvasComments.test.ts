import { afterEach, describe, expect, it, vi } from "vitest";
import { mount, type VueWrapper } from "@vue/test-utils";
import CanvasComments from "@modules/ideation/BrainstormingCanvasComments.vue";
import type { BrainstormingCommentsState } from "@modules/ideation/commentTypes";
import type { CommentThread } from "@components/comments/types";

const thread: CommentThread = {
  id: 7,
  status: "open",
  revision: 3,
  message_count: 1,
  created_at: "",
  last_activity_at: "",
  resolved_at: null,
  resolved_by: null,
  author: { id: 1, display_name: "Writer", avatar_url: null },
  source: { type: "ideation_session", id: 12, label: "Board", status: "available" },
  position: { x: 50, y: 60 },
  preview: "Review this ending",
};
const initial: BrainstormingCommentsState = {
  open: false,
  presentation: "canvas",
  pins: [thread],
  threads: [],
  nextCursor: null,
  thread: null,
  messages: [],
  messageNextCursor: null,
  members: [],
  canComment: true,
  selectedSourceId: 12,
  error: null,
  ideaId: null,
  groupId: null,
  context: "context-1",
};
let wrapper: VueWrapper;
function setup(state: Partial<BrainstormingCommentsState> = {}) {
  vi.stubGlobal(
    "ResizeObserver",
    class {
      observe() {}
      disconnect() {}
    },
  );
  const pushEvent = vi.fn();
  wrapper = mount(CanvasComments, {
    attachTo: document.body,
    props: {
      state: { ...initial, ...state },
      view: { x: 100, y: 100, zoom: 2, width: 800, height: 600 },
      epoch: "epoch-1",
      sessionId: 12,
      baseUrl: "/brainstorming",
      notes: [],
      groups: [],
    },
    global: {
      provide: {
        _live_vue: { pushEvent, handleEvent: vi.fn(), removeHandleEvent: vi.fn(), upload: vi.fn() },
      },
    },
  });
  return pushEvent;
}
afterEach(() => {
  wrapper?.unmount();
  vi.unstubAllGlobals();
});

describe("Brainstorming canvas comments", () => {
  it("keeps the composer beside a world-positioned draft without a modal", async () => {
    setup({ open: true, draftPosition: { x: 50, y: 60 } });
    expect(wrapper.find('[role="dialog"]').exists()).toBe(false);
    expect(wrapper.get("#brainstorming-comment-draft-pin").attributes("style")).toContain(
      "left: 200px",
    );
    expect(wrapper.get("#brainstorming-comment-popover").attributes("style")).toContain(
      "left: 224px",
    );
    await wrapper.get("textarea").setValue("Keep this draft");
    await wrapper.setProps({ view: { x: 140, y: 100, zoom: 2, width: 800, height: 600 } });
    expect(wrapper.get("#brainstorming-comment-draft-pin").attributes("style")).toContain(
      "left: 240px",
    );
    expect((wrapper.get("textarea").element as HTMLTextAreaElement).value).toBe("Keep this draft");
  });

  it("moves a pin in world coordinates and commits against its revision", async () => {
    const push = setup();
    const pin = wrapper.get("#brainstorming-comment-pin-7");
    await pin.trigger("keydown", { key: "ArrowRight" });
    await pin.trigger("keydown", { key: "ArrowDown", shiftKey: true });
    expect(push).not.toHaveBeenCalled();
    expect(pin.attributes("style")).toContain("left: 210px");
    await pin.trigger("keydown", { key: "Enter" });
    expect(push).toHaveBeenCalledWith(
      "comments_move",
      {
        epoch: "epoch-1",
        session_id: 12,
        comment_context: "context-1",
        thread_id: 7,
        expected_revision: 3,
        position: { x: 55, y: 60.5 },
      },
      expect.any(Function),
    );
    push.mock.calls[0][2]({ ok: false });
    await wrapper.vm.$nextTick();
    expect(pin.attributes("style")).toContain("left: 200px");
    expect(wrapper.find('[role="alert"]').exists()).toBe(true);
  });

  it("cancels a draft move without losing its composer", async () => {
    const push = setup({ open: true, draftPosition: { x: 50, y: 60 } });
    await wrapper.get("textarea").setValue("Keep the text");
    const pin = wrapper.get("#brainstorming-comment-draft-pin");
    await pin.trigger("keydown", { key: "ArrowRight" });
    await pin.trigger("keydown", { key: "Escape" });
    expect(push).not.toHaveBeenCalled();
    expect(pin.attributes("style")).toContain("left: 200px");
    expect((wrapper.get("textarea").element as HTMLTextAreaElement).value).toBe("Keep the text");
  });

  it("lets viewers open a pin but prevents moving it", async () => {
    const push = setup({ canComment: false });
    const pin = wrapper.get("#brainstorming-comment-pin-7");
    await pin.trigger("keydown", { key: "ArrowRight" });
    expect(push).not.toHaveBeenCalled();
    await pin.trigger("click");
    expect(push.mock.calls[0].slice(0, 2)).toEqual([
      "comments_select_thread",
      {
        thread_id: 7,
        epoch: "epoch-1",
        session_id: 12,
        comment_context: "context-1",
      },
    ]);
  });
});
