import { flushPromises, mount } from "@vue/test-utils";
import { beforeEach, describe, expect, it, vi } from "vitest";
import { createMockLive } from "@app/test/setup";
import type { SheetCommentsPanelState } from "@modules/sheets/types/comments";

const live = createMockLive();
vi.mock("@shared/composables/useLive", () => ({ useLive: () => live }));
const { default: SheetHeader } = await import("@app/live/sheet/show/SheetHeader.vue");
const { default: SheetShowPanels } =
  await import("@modules/sheets/components/panels/SheetShowPanels.vue");
const { default: SheetCommentsPanel } =
  await import("@modules/sheets/components/panels/SheetCommentsPanel.vue");

const comments: SheetCommentsPanelState = {
  open: true,
  presentation: "panel",
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
  it("exposes comment mode, count, and a viewer-safe panel toggle in the header", async () => {
    const wrapper = mount(SheetHeader, {
      props: {
        health: { errorItems: [], warningItems: [], infoItems: [] },
        comments: { count: 3, open: false, placing: false, canComment: true },
      },
      global: {
        stubs: {
          SheetHealthStatus: true,
          ToolbarTooltip: passthrough,
        },
      },
    });

    expect(wrapper.get("#sheet-comments-toggle").text()).toContain("3");
    await wrapper.get("#sheet-comments-create-mode").trigger("click");
    expect(live.pushEvent).toHaveBeenLastCalledWith("comments_mode", { active: true });
    await wrapper.get("#sheet-comments-toggle").trigger("click");
    expect(live.pushEvent).toHaveBeenLastCalledWith("comments_open", {});

    await wrapper.setProps({
      comments: { count: 3, open: true, placing: false, canComment: false },
    });
    expect(wrapper.find("#sheet-comments-create-mode").exists()).toBe(false);
    expect(wrapper.get("#sheet-comments-toggle").attributes("aria-expanded")).toBe("true");
    await wrapper.get("#sheet-comments-toggle").trigger("click");
    expect(live.pushEvent).toHaveBeenLastCalledWith("comments_close", {});
  });

  it("mounts the shared panel alongside the active sheet tab", () => {
    const wrapper = mount(SheetShowPanels, {
      props: {
        panels: {
          comments,
          currentTab: "content",
          compact: false,
          references: null,
          audio: null,
          history: null,
        },
      },
      global: {
        stubs: {
          SheetCommentsPanel: {
            props: ["state"],
            template: '<section data-testid="comments-panel" />',
          },
        },
      },
    });

    expect(wrapper.find('[data-testid="comments-panel"]').exists()).toBe(true);
    expect(wrapper.find("#sheet-comments-panel").exists()).toBe(true);
  });

  it("creates a sheet canvas thread with its surface position", async () => {
    const position = { x: 25, y: 50 };
    const wrapper = mount(SheetCommentsPanel, {
      props: {
        embedded: true,
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
    const wrapper = mount(SheetCommentsPanel, {
      props: {
        embedded: true,
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

  it("reuses the same request id when a pending draft is retried after reload", async () => {
    const storageKey = "storyarn:sheet-comment-draft:4:7";
    const position = { x: 25, y: 50 };
    const panelProps = {
      embedded: true,
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
    const first = mount(SheetCommentsPanel, { props: panelProps, global });
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
    const restored = mount(SheetCommentsPanel, { props: panelProps, global });
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
