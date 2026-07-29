import { flushPromises, mount } from "@vue/test-utils";
import { afterEach, describe, expect, it, vi } from "vitest";
import SheetSurface from "@app/live/sheet/show/SheetSurface.vue";
import type { SheetDeepLinkTarget } from "@modules/sheets/composables/useSheetHighlight";
import { createMockLive } from "@app/test/setup";

type SheetSurfaceProps = InstanceType<typeof SheetSurface>["$props"];

const content = {
  blocks: [],
  inheritedGroups: [],
  workspaceSlug: "workspace",
  projectSlug: "project",
  canEdit: true,
  formulaEditing: null,
  blockLocks: {},
  currentUserId: 1,
};

function surfaceProps(contentProps: typeof content | null = content): SheetSurfaceProps["surface"] {
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
        BlockList: {
          template: `
            <div>
              <div id="sheet-block-42" data-sheet-block-id="42">
                <div data-sheet-row-id="7">
                  <div data-sheet-column-id="9">Health</div>
                </div>
              </div>
            </div>
          `,
        },
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
});
