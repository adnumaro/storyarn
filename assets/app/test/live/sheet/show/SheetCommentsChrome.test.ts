import { flushPromises, mount } from "@vue/test-utils";
import { beforeEach, describe, expect, it, vi } from "vitest";
import { createMockLive } from "@app/test/setup";
import type {
  SheetCommentMessage,
  SheetCommentsPanelState,
  SheetCommentThread,
} from "@modules/sheets/types/comments";

const live = createMockLive();
vi.mock("@shared/composables/useLive", () => ({ useLive: () => live }));
const { default: SheetHeader } = await import("@app/live/sheet/show/SheetHeader.vue");
const { default: SheetShowPanels } =
  await import("@modules/sheets/components/panels/SheetShowPanels.vue");
const { default: SheetCommentPopover } =
  await import("@modules/sheets/components/panels/SheetCommentPopover.vue");

const comments: SheetCommentsPanelState = {
  open: true,
  presentation: "canvas",
  placing: false,
  draftPosition: null,
  draftId: null,
  threads: [],
  nextCursor: null,
  thread: null,
  messages: [],
  messageNextCursor: null,
  members: [],
  canComment: true,
  statusFilter: "open",
  error: null,
};
const passthrough = { template: "<div><slot /></div>" };

beforeEach(() => {
  vi.mocked(live.pushEvent).mockClear();
  window.sessionStorage.clear();
});

describe("Sheet comments chrome wiring", () => {
  it("keeps the Sheet header free of comment controls", () => {
    const wrapper = mount(SheetHeader, { global: { stubs: { SheetHealthStatus: true } } });
    expect(wrapper.find("#sheet-comments-toggle").exists()).toBe(false);
    expect(wrapper.find("#sheet-comments-create-mode").exists()).toBe(false);
  });

  it("does not mount a comments sidebar alongside the active sheet tab", () => {
    const wrapper = mount(SheetShowPanels, {
      props: {
        panels: {
          currentTab: "content",
          compact: false,
          references: null,
          audio: null,
          history: null,
        },
      },
      global: {
        stubs: {
          SheetCommentPopover: {
            props: ["state"],
            template: '<section data-testid="comments-panel" />',
          },
        },
      },
    });

    expect(wrapper.find('[data-testid="comments-panel"]').exists()).toBe(false);
    expect(wrapper.find("#sheet-comments-panel").exists()).toBe(false);
  });

  it("creates a sheet canvas thread with its surface position", async () => {
    const position = { x: 25, y: 50 };
    const wrapper = mount(SheetCommentPopover, {
      props: {
        state: {
          ...comments,
          presentation: "canvas",
          draftPosition: position,
          draftId: "sheet-canvas-draft",
        },
      },
      global: {
        stubs: {
          Sidebar: {
            template: "<aside><slot name='header'/><slot/><slot name='footer'/></aside>",
          },
          Popover: passthrough,
          PopoverContent: passthrough,
          PopoverTrigger: passthrough,
        },
      },
    });

    await wrapper.get("#sheet-comment-body").setValue("Increase the starting value.");
    await wrapper.get("form").trigger("submit");
    expect(live.pushEvent).toHaveBeenCalledWith(
      "comments_create",
      expect.objectContaining({
        body: "Increase the starting value.",
        position,
      }),
      expect.any(Function),
      expect.any(Function),
    );
    expect(wrapper.find("#sheet-comment-send").exists()).toBe(true);
  });

  it("restores the text of a sheet draft and clears it after a confirmed send", async () => {
    const storageKey = "storyarn:sheet-comment-draft:4:7";
    const position = { x: 25, y: 50 };
    window.sessionStorage.setItem(
      storageKey,
      JSON.stringify({ position, body: "A draft that survives reload", mentionIds: [] }),
    );
    const wrapper = mount(SheetCommentPopover, {
      props: {
        draftStorageKey: storageKey,
        state: {
          ...comments,
          presentation: "canvas",
          draftPosition: position,
          draftId: "new-server-draft-id",
        },
      },
      global: {
        stubs: {
          Sidebar: {
            template: "<aside><slot name='header'/><slot/><slot name='footer'/></aside>",
          },
          Popover: passthrough,
          PopoverContent: passthrough,
          PopoverTrigger: passthrough,
        },
      },
    });

    expect(wrapper.get<HTMLTextAreaElement>("#sheet-comment-body").element.value).toBe(
      "A draft that survives reload",
    );
    await wrapper.get("#sheet-comment-body").setValue("Updated before sending");
    await flushPromises();
    expect(JSON.parse(window.sessionStorage.getItem(storageKey) ?? "{}").body).toBe(
      "Updated before sending",
    );

    await wrapper.get("form").trigger("submit");
    const create = vi
      .mocked(live.pushEvent)
      .mock.calls.find(([event]) => event === "comments_create");
    expect(create?.[2]).toEqual(expect.any(Function));

    const nextStorageKey = "storyarn:sheet-comment-draft:4:8";
    window.sessionStorage.setItem(
      nextStorageKey,
      JSON.stringify({
        position: { x: 30, y: 70 },
        body: "A draft from another Sheet",
        mentionIds: [],
      }),
    );
    await wrapper.setProps({
      draftStorageKey: nextStorageKey,
      state: {
        ...comments,
        presentation: "canvas",
        draftPosition: { x: 30, y: 70 },
        draftId: "another-server-draft-id",
      },
    });
    if (typeof create?.[2] === "function") create[2]({ ok: true });
    await flushPromises();

    expect(window.sessionStorage.getItem(storageKey)).toBeNull();
    expect(window.sessionStorage.getItem(nextStorageKey)).toContain("A draft from another Sheet");

    await wrapper.get("#sheet-comment-body").setValue("A later Sheet draft");
    await flushPromises();

    expect(JSON.parse(window.sessionStorage.getItem(nextStorageKey) ?? "{}").body).toBe(
      "A later Sheet draft",
    );
  });

  it("keeps the saved new-comment draft after a confirmed reply", async () => {
    const storageKey = "storyarn:sheet-comment-draft:4:7";
    const storedDraft = {
      position: { x: 25, y: 50 },
      body: "Keep this top-level draft",
      mentionIds: [],
    };
    const author = { id: 4, display_name: "Ada", avatar_url: null };
    const thread: SheetCommentThread = {
      id: 12,
      status: "open",
      revision: 3,
      message_count: 1,
      created_at: "2026-09-05T09:00:00Z",
      last_activity_at: "2026-09-05T09:00:00Z",
      resolved_at: null,
      resolved_by: null,
      source: {
        type: "sheet_canvas",
        id: 7,
        sheet_id: 7,
        label: "Hero",
        status: "available",
      },
      author,
      root_message_id: 21,
      position: storedDraft.position,
    };
    const rootMessage: SheetCommentMessage = {
      id: 21,
      thread_id: thread.id,
      parent_id: null,
      body: "Existing comment",
      author,
      mentions: [],
      inserted_at: "2026-09-05T09:00:00Z",
    };
    window.sessionStorage.setItem(storageKey, JSON.stringify(storedDraft));

    const wrapper = mount(SheetCommentPopover, {
      props: {
        draftStorageKey: storageKey,
        state: { ...comments, presentation: "canvas", thread, messages: [rootMessage] },
      },
      global: {
        stubs: {
          Sidebar: {
            template: "<aside><slot name='header'/><slot/><slot name='footer'/></aside>",
          },
          Popover: passthrough,
          PopoverContent: passthrough,
          PopoverTrigger: passthrough,
        },
      },
    });

    await wrapper.get("#sheet-comment-body").setValue("A reply");
    await wrapper.get("form").trigger("submit");
    const reply = vi
      .mocked(live.pushEvent)
      .mock.calls.find(([event]) => event === "comments_reply");
    expect(reply?.[2]).toEqual(expect.any(Function));
    if (typeof reply?.[2] === "function") reply[2]({ ok: true });
    await flushPromises();

    expect(JSON.parse(window.sessionStorage.getItem(storageKey) ?? "{}")).toEqual(storedDraft);
  });

  it("clears a submitted new-comment draft after the server selects its thread", async () => {
    const storageKey = "storyarn:sheet-comment-draft:4:7";
    const position = { x: 25, y: 50 };
    window.sessionStorage.setItem(
      storageKey,
      JSON.stringify({ position, body: "Publish this draft", mentionIds: [] }),
    );
    const wrapper = mount(SheetCommentPopover, {
      props: {
        draftStorageKey: storageKey,
        state: {
          ...comments,
          presentation: "canvas",
          draftPosition: position,
          draftId: "server-draft-id",
        },
      },
      global: {
        stubs: {
          Sidebar: {
            template: "<aside><slot name='header'/><slot/><slot name='footer'/></aside>",
          },
          Popover: passthrough,
          PopoverContent: passthrough,
          PopoverTrigger: passthrough,
        },
      },
    });

    await wrapper.get("form").trigger("submit");
    const create = vi
      .mocked(live.pushEvent)
      .mock.calls.find(([event]) => event === "comments_create");
    expect(create?.[2]).toEqual(expect.any(Function));

    await wrapper.setProps({
      state: {
        ...comments,
        presentation: "canvas",
        thread: {
          id: 12,
          status: "open",
          revision: 1,
          message_count: 1,
          created_at: "2026-09-05T09:00:00Z",
          last_activity_at: "2026-09-05T09:00:00Z",
          resolved_at: null,
          resolved_by: null,
          source: {
            type: "sheet_canvas",
            id: 7,
            sheet_id: 7,
            label: "Hero",
            status: "available",
          },
          author: { id: 4, display_name: "Ada", avatar_url: null },
          root_message_id: 21,
          position,
        },
      },
    });
    if (typeof create?.[2] === "function") create[2]({ ok: true });
    await flushPromises();

    expect(window.sessionStorage.getItem(storageKey)).toBeNull();
  });

  it("reuses the same request id when a pending draft is retried after reload", async () => {
    const storageKey = "storyarn:sheet-comment-draft:4:7";
    const position = { x: 25, y: 50 };
    const panelProps = {
      draftStorageKey: storageKey,
      state: {
        ...comments,
        presentation: "canvas" as const,
        draftPosition: position,
        draftId: "server-draft-id",
      },
    };
    const global = {
      stubs: {
        Sidebar: {
          template: "<aside><slot name='header'/><slot/><slot name='footer'/></aside>",
        },
        Popover: passthrough,
        PopoverContent: passthrough,
        PopoverTrigger: passthrough,
      },
    };
    const first = mount(SheetCommentPopover, { props: panelProps, global });
    await first.get("#sheet-comment-body").setValue("Retry this exact draft");
    await first.get("form").trigger("submit");
    const firstCreate = vi
      .mocked(live.pushEvent)
      .mock.calls.find(([event]) => event === "comments_create");
    const firstRequestId = (firstCreate?.[1] as { client_request_id?: string })?.client_request_id;
    expect(firstRequestId).toEqual(expect.any(String));
    expect(JSON.parse(window.sessionStorage.getItem(storageKey) ?? "{}").requestId).toBe(
      firstRequestId,
    );

    first.unmount();
    vi.mocked(live.pushEvent).mockClear();
    const restored = mount(SheetCommentPopover, { props: panelProps, global });
    expect(restored.get<HTMLTextAreaElement>("#sheet-comment-body").element.value).toBe(
      "Retry this exact draft",
    );
    await restored.get("form").trigger("submit");
    const retriedCreate = vi
      .mocked(live.pushEvent)
      .mock.calls.find(([event]) => event === "comments_create");

    expect((retriedCreate?.[1] as { client_request_id?: string })?.client_request_id).toBe(
      firstRequestId,
    );
  });
});
