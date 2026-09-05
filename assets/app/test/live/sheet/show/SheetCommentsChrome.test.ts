import { mount } from "@vue/test-utils";
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
  selectedBlockId: null,
  selectedBlockLabel: null,
  statusFilter: "open",
  error: null,
};
const passthrough = { template: "<div><slot /></div>" };

beforeEach(() => vi.mocked(live.pushEvent).mockClear());

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

  it("creates a block thread with its source id and normalized position", async () => {
    const position = { x: 25, y: 50 };
    const wrapper = mount(SheetCommentsPanel, {
      props: {
        embedded: true,
        state: {
          ...comments,
          presentation: "canvas",
          selectedBlockId: 42,
          selectedBlockLabel: "Health",
          draftPosition: position,
          draftId: "sheet-block-draft",
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
        block_id: 42,
        body: "Increase the starting value.",
        position,
      }),
      expect.any(Function),
      expect.any(Function),
    );
    expect(wrapper.find("#sheet-comment-send").exists()).toBe(true);
  });
});
