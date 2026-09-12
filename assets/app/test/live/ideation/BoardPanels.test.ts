import { describe, expect, it, vi } from "vitest";
import { mount } from "@vue/test-utils";
import BoardPanels from "@app/live/ideation/BoardPanels.vue";
import type { BrainstormingCommentsState } from "@app/live/ideation/commentTypes";
import type { ReferencesPanelState } from "@app/live/ideation/referenceTypes";

const comments: BrainstormingCommentsState = {
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
  context: "comments-1",
};

const references: ReferencesPanelState = {
  open: false,
  context: "references-1",
  ideaId: null,
  focusedReferenceId: null,
  items: [],
  nextCursor: null,
  results: [],
  searched: false,
  historyReferenceId: null,
  history: [],
  canEdit: true,
  error: null,
};

describe("Brainstorming panel composition", () => {
  it("keeps comments visible with references closed and scopes each sibling's events independently", async () => {
    const pushEvent = vi.fn();
    const wrapper = mount(BoardPanels, {
      props: { comments, references, epoch: "epoch-1", sessionId: 12, baseUrl: "/brainstorming" },
      global: {
        provide: {
          _live_vue: {
            pushEvent,
            handleEvent: vi.fn(),
            removeHandleEvent: vi.fn(),
            upload: vi.fn(),
          },
        },
        stubs: {
          Sidebar: { template: "<aside><slot name='header'/><slot/><slot name='footer'/></aside>" },
          ConfirmDialog: true,
        },
      },
    });

    expect(wrapper.find("#brainstorming-comment-body").exists()).toBe(true);
    expect(wrapper.find("#brainstorming-reference-search-form").exists()).toBe(false);
    await wrapper.get("#brainstorming-comment-body").setValue("Discuss this design");
    await wrapper.get("form").trigger("submit");
    expect(pushEvent.mock.calls[0][0]).toBe("comments_create");
    expect(pushEvent.mock.calls[0][1]).toMatchObject({
      epoch: "epoch-1",
      session_id: 12,
      comment_context: "comments-1",
      body: "Discuss this design",
    });
    expect(pushEvent.mock.calls[0][1]).not.toHaveProperty("reference_context");

    await wrapper.setProps({
      comments: { ...comments, open: false, context: "comments-closed" },
      references: { ...references, open: true, context: "references-2" },
    });
    expect(wrapper.find("#brainstorming-comment-body").exists()).toBe(false);
    expect(wrapper.find("#brainstorming-reference-search-form").exists()).toBe(true);
    await wrapper.get("#brainstorming-reference-query").setValue("Hero");
    await wrapper.get("#brainstorming-reference-search-form").trigger("submit");
    expect(pushEvent.mock.calls[1][0]).toBe("references_search");
    expect(pushEvent.mock.calls[1][1]).toMatchObject({
      epoch: "epoch-1",
      session_id: 12,
      reference_context: "references-2",
      search: "Hero",
    });
    expect(pushEvent.mock.calls[1][1]).not.toHaveProperty("comment_context");
    wrapper.unmount();
  });
});
