import { flushPromises, mount } from "@vue/test-utils";
import { afterEach, describe, expect, it, vi } from "vitest";
import { defineComponent, nextTick } from "vue";
import SheetSurface from "@app/live/sheet/show/SheetSurface.vue";
import type { SheetDeepLinkTarget } from "@modules/sheets/composables/useSheetHighlight";
import type { SheetCommentsPanelState, SheetCommentThread } from "@modules/sheets/types/comments";
import { createMockLive } from "@app/test/setup";

type SheetSurfaceProps = InstanceType<typeof SheetSurface>["$props"];
type SheetSurfaceContent = NonNullable<SheetSurfaceProps["surface"]["content"]>;

const content: SheetSurfaceContent = {
  blocks: [],
  inheritedGroups: [],
  workspaceSlug: "workspace",
  projectSlug: "project",
  canEdit: true,
  formulaEditing: null,
  blockLocks: {},
  currentUserId: 1,
};

const comments: SheetCommentsPanelState = {
  open: false,
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

const commentThread: SheetCommentThread = {
  id: 12,
  status: "open",
  revision: 3,
  message_count: 1,
  created_at: "2026-09-05T09:00:00Z",
  last_activity_at: "2026-09-05T09:00:00Z",
  resolved_at: null,
  resolved_by: null,
  source: {
    type: "sheet_block",
    id: 42,
    sheet_id: 10,
    label: "Health",
    status: "available",
  },
  author: { id: 4, display_name: "Ada", avatar_url: null },
  preview: "Increase the starting value.",
  position: { x: 25, y: 50 },
};

const BlockListStub = defineComponent({
  name: "BlockListStub",
  props: { commentsActive: Boolean },
  template: `
    <div>
      <div id="sheet-block-42" data-sheet-block-id="42">
        <div data-sheet-row-id="7">
          <div data-sheet-column-id="9">Health</div>
        </div>
      </div>
    </div>
  `,
});

function surfaceProps(
  contentProps: SheetSurfaceContent | null = content,
): SheetSurfaceProps["surface"] {
  return {
    health: null,
    tabs: { currentTab: "content", canEdit: true, compact: false },
    content: contentProps,
  };
}

function mountSurface(
  highlightTarget: SheetDeepLinkTarget | null,
  surface: SheetSurfaceProps["surface"] = surfaceProps(),
) {
  const live = createMockLive();
  const wrapper = mount(SheetSurface, {
    attachTo: document.body,
    props: {
      sheet: { id: 10, name: "Hero" },
      canEdit: true,
      sourceShortcut: null,
      highlightTarget,
      surface,
      panels: null,
    },
    global: {
      provide: { _live_vue: live },
      stubs: {
        SheetContentHeader: true,
        SheetTabs: true,
        SheetShowPanels: true,
        CollabToast: true,
        BlockList: BlockListStub,
      },
    },
  });

  return wrapper;
}

async function settleHighlight(): Promise<void> {
  await flushPromises();
  await Promise.resolve();
}

afterEach(() => {
  document.body.innerHTML = "";
  vi.restoreAllMocks();
  vi.unstubAllGlobals();
});

describe("SheetSurface deep-link highlights", () => {
  it("scrolls and temporarily highlights an initial block target", async () => {
    const scrollIntoView = vi.spyOn(Element.prototype, "scrollIntoView");
    mountSurface({ kind: "block", blockId: 42, requestId: 1 });

    await settleHighlight();

    const block = document.getElementById("sheet-block-42");
    expect(scrollIntoView).toHaveBeenCalledWith({ behavior: "smooth", block: "center" });
    expect(block?.classList.contains("ring-2")).toBe(true);
  });

  it("waits for content and reacts to a changed cell target without searching another block", async () => {
    const scrollIntoView = vi.spyOn(Element.prototype, "scrollIntoView");
    const wrapper = mountSurface({ kind: "block", blockId: 42, requestId: 1 }, surfaceProps(null));

    await settleHighlight();
    expect(scrollIntoView).not.toHaveBeenCalled();

    await wrapper.setProps({ surface: surfaceProps() });
    await settleHighlight();

    const block = document.getElementById("sheet-block-42");
    const cell = document.querySelector<HTMLElement>(
      '#sheet-block-42 [data-sheet-row-id="7"] [data-sheet-column-id="9"]',
    );

    expect(block?.classList.contains("ring-2")).toBe(true);

    await wrapper.setProps({
      highlightTarget: {
        kind: "cell",
        blockId: 42,
        rowId: 7,
        columnId: 9,
        requestId: 2,
      },
    });
    await settleHighlight();

    expect(block?.classList.contains("ring-2")).toBe(false);
    expect(cell?.classList.contains("ring-2")).toBe(true);
    expect(scrollIntoView).toHaveBeenLastCalledWith({
      behavior: "smooth",
      block: "center",
    });

    await wrapper.setProps({
      highlightTarget: {
        kind: "cell",
        blockId: 999,
        rowId: 7,
        columnId: 9,
        requestId: 3,
      },
    });
    await settleHighlight();

    expect(cell?.classList.contains("ring-2")).toBe(false);
    expect(scrollIntoView).toHaveBeenCalledTimes(2);
  });

  it("mounts the comment layer from the live surface and marks block interaction as active", async () => {
    vi.stubGlobal(
      "ResizeObserver",
      class {
        observe() {}
        disconnect() {}
      },
    );
    const commentContent = {
      ...content,
      comments,
      commentPins: [],
      commentFocusThreadId: null,
    };
    const wrapper = mountSurface(null, surfaceProps(commentContent));
    await flushPromises();

    expect(wrapper.find("[data-testid='sheet-block-comments']").exists()).toBe(true);
    const blockList = wrapper.findComponent(BlockListStub);
    expect(blockList.props("commentsActive")).toBe(false);

    document.getElementById("sheet-block-42")?.dispatchEvent(
      new MouseEvent("contextmenu", {
        bubbles: true,
        cancelable: true,
        clientX: 8,
        clientY: 8,
        button: 2,
      }),
    );
    await nextTick();
    expect(blockList.props("commentsActive")).toBe(true);

    document.body.dispatchEvent(new MouseEvent("pointerdown", { bubbles: true, cancelable: true }));
    await new Promise((resolve) => setTimeout(resolve));
    await nextTick();
    expect(blockList.props("commentsActive")).toBe(false);

    await wrapper.setProps({
      surface: surfaceProps({
        ...commentContent,
        comments: { ...comments, open: true },
      }),
    });
    await nextTick();
    expect(blockList.props("commentsActive")).toBe(true);
  });

  it("marks keyboard focus within comment pins as active", async () => {
    vi.stubGlobal(
      "ResizeObserver",
      class {
        observe() {}
        disconnect() {}
      },
    );
    const wrapper = mountSurface(
      null,
      surfaceProps({
        ...content,
        comments,
        commentPins: [commentThread],
        commentFocusThreadId: null,
      }),
    );
    await flushPromises();

    const blockList = wrapper.findComponent(BlockListStub);
    expect(blockList.props("commentsActive")).toBe(false);

    (wrapper.get("#sheet-comment-pin-12").element as HTMLElement).focus();
    await nextTick();
    expect(blockList.props("commentsActive")).toBe(true);

    await wrapper.setProps({
      surface: surfaceProps({
        ...content,
        comments,
        commentPins: [],
        commentFocusThreadId: null,
      }),
    });
    await nextTick();
    await new Promise((resolve) => setTimeout(resolve));
    await nextTick();
    expect(wrapper.find("#sheet-comment-pin-12").exists()).toBe(false);
    expect(blockList.props("commentsActive")).toBe(false);
  });
});
