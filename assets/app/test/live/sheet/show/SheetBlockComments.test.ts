import { flushPromises, mount, type VueWrapper } from "@vue/test-utils";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { nextTick } from "vue";
import { createMockLive } from "@app/test/setup";
import type { SheetCommentsPanelState, SheetCommentThread } from "@modules/sheets/types/comments";

const live = createMockLive();
vi.mock("@shared/composables/useLive", () => ({ useLive: () => live }));
const { default: SheetBlockComments } =
  await import("@modules/sheets/components/chrome/SheetBlockComments.vue");

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
    type: "sheet_block",
    id: 42,
    sheet_id: 7,
    label: "Health",
    status: "available",
  },
  author,
  preview: "Increase the starting value.",
  position: { x: 25, y: 50 },
};
const base: SheetCommentsPanelState = {
  open: false,
  presentation: "panel",
  placing: false,
  draftPosition: null,
  draftId: null,
  threads: [thread],
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

let wrappers: VueWrapper[] = [];

function rect(left: number, top: number, width: number, height: number): DOMRect {
  return {
    left,
    top,
    width,
    height,
    right: left + width,
    bottom: top + height,
    x: left,
    y: top,
    toJSON: () => ({}),
  } as DOMRect;
}

function pointer(target: EventTarget, type: string, x: number, y: number, button = 0): MouseEvent {
  const event = new MouseEvent(type, {
    bubbles: true,
    cancelable: true,
    clientX: x,
    clientY: y,
    button,
  });
  Object.defineProperty(event, "pointerId", { value: 1 });
  target.dispatchEvent(event);
  return event;
}

function setup(
  state: Partial<SheetCommentsPanelState> = {},
  commentPins = [thread],
  focusThreadId: number | null = null,
) {
  const container = document.createElement("div");
  const block = document.createElement("div");
  const background = document.createElement("div");
  const input = document.createElement("input");
  const button = document.createElement("button");
  block.id = "sheet-block-42";
  block.dataset.sheetBlockId = "42";
  background.dataset.testid = "block-background";
  block.append(background, input, button);
  container.append(block);
  document.body.append(container);

  vi.spyOn(container, "getBoundingClientRect").mockReturnValue(rect(10, 20, 800, 800));
  vi.spyOn(block, "getBoundingClientRect").mockReturnValue(rect(110, 220, 400, 200));

  const wrapper = mount(SheetBlockComments, {
    attachTo: container,
    props: {
      container: () => container,
      state: { ...base, ...state },
      commentPins,
      focusThreadId,
    },
    global: { stubs: { SheetCommentsPanel: true } },
  });
  wrappers.push(wrapper);
  return { wrapper, container, block, background, input, button };
}

beforeEach(() => {
  vi.clearAllMocks();
  vi.stubGlobal(
    "ResizeObserver",
    class {
      observe() {}
      disconnect() {}
    },
  );
});

afterEach(() => {
  for (const wrapper of wrappers) wrapper.unmount();
  wrappers = [];
  document.body.innerHTML = "";
  vi.unstubAllGlobals();
});

describe("Sheet block comments", () => {
  it("positions pins from their block, previews on hover, and opens the thread on click", async () => {
    const { wrapper } = setup();
    await nextTick();

    const pin = wrapper.get("#sheet-comment-pin-12");
    expect(pin.attributes("style")).toContain("left: 200px");
    expect(pin.attributes("style")).toContain("top: 300px");

    await pin.trigger("focus");
    expect(wrapper.get('[role="tooltip"]').text()).toContain("Ada");
    expect(wrapper.get('[role="tooltip"]').text()).toContain("Increase the starting value.");

    await pin.trigger("click");
    expect(live.pushEvent).toHaveBeenLastCalledWith("comments_select_thread", {
      thread_id: 12,
      presentation: "canvas",
    });
  });

  it("does not describe the selected pin with the hidden preview while its dialog is open", async () => {
    const { wrapper } = setup({
      open: true,
      presentation: "canvas",
      thread,
    });
    await flushPromises();

    const pin = wrapper.get("#sheet-comment-pin-12");
    await pin.trigger("focus");

    expect(wrapper.find("#sheet-comment-preview").exists()).toBe(false);
    expect(pin.attributes("aria-describedby")).toBe("sheet-comment-pin-keyboard-instructions");
    expect(wrapper.find("#sheet-comment-pin-keyboard-instructions").exists()).toBe(true);
  });

  it("keeps comment interaction active while focus moves within the layer", async () => {
    const { wrapper, container } = setup();
    await nextTick();

    const pin = wrapper.get("#sheet-comment-pin-12").element as HTMLElement;
    pin.focus();
    await nextTick();
    expect(wrapper.emitted("interactionChange")?.at(-1)).toEqual([true]);

    const secondCommentControl = document.createElement("button");
    wrapper.get("[data-sheet-comment-ui]").element.append(secondCommentControl);
    const emissionCount = wrapper.emitted("interactionChange")?.length;
    secondCommentControl.focus();
    await new Promise((resolve) => setTimeout(resolve));

    expect(wrapper.emitted("interactionChange")?.length).toBe(emissionCount);
    expect(wrapper.emitted("interactionChange")?.at(-1)).toEqual([true]);

    const outside = document.createElement("button");
    container.append(outside);
    outside.focus();
    await new Promise((resolve) => setTimeout(resolve));

    expect(wrapper.emitted("interactionChange")?.at(-1)).toEqual([false]);
  });

  it("ends comment interaction when a focused pin disappears remotely", async () => {
    const { wrapper } = setup();
    await nextTick();

    (wrapper.get("#sheet-comment-pin-12").element as HTMLElement).focus();
    await nextTick();
    expect(wrapper.emitted("interactionChange")?.at(-1)).toEqual([true]);

    await wrapper.setProps({ commentPins: [] });
    await nextTick();
    await new Promise((resolve) => setTimeout(resolve));

    expect(wrapper.find("#sheet-comment-pin-12").exists()).toBe(false);
    expect(wrapper.emitted("interactionChange")?.at(-1)).toEqual([false]);
  });

  it("offers Add comment on a block background while preserving native editor menus", async () => {
    const { wrapper, background, input } = setup();

    const backgroundMenu = pointer(background, "contextmenu", 310, 320, 2);
    await nextTick();
    expect(backgroundMenu.defaultPrevented).toBe(true);
    expect(wrapper.get("#sheet-comment-context-menu").attributes("role")).toBe("menu");
    expect(wrapper.emitted("interactionChange")?.at(-1)).toEqual([true]);

    await wrapper.get("#sheet-comment-context-add").trigger("click");
    expect(live.pushEvent).toHaveBeenLastCalledWith("comments_place", {
      block_id: 42,
      x: 50,
      y: 50,
    });

    const inputMenu = pointer(input, "contextmenu", 310, 320, 2);
    await nextTick();
    expect(inputMenu.defaultPrevented).toBe(false);
    expect(wrapper.find("#sheet-comment-context-menu").exists()).toBe(false);
  });

  it("places a comment in the block center with Enter while placement mode is active", () => {
    const { block } = setup({ placing: true });
    block.tabIndex = 0;
    block.focus();
    block.dispatchEvent(
      new KeyboardEvent("keydown", { key: "Enter", bubbles: true, cancelable: true }),
    );

    expect(live.pushEvent).toHaveBeenLastCalledWith("comments_place", {
      block_id: 42,
      x: 50,
      y: 50,
    });
  });

  it("preserves interactive controls in comment mode and intercepts the block background", async () => {
    const { background, input, button } = setup({ placing: true });

    for (const control of [input, button]) {
      const controlPointerDown = vi.fn();
      const controlClick = vi.fn();
      control.addEventListener("pointerdown", controlPointerDown);
      control.addEventListener("click", controlClick);

      const pointerDown = pointer(control, "pointerdown", 210, 270);
      pointer(control, "pointerup", 210, 270);
      const click = pointer(control, "click", 210, 270);

      expect(pointerDown.defaultPrevented).toBe(false);
      expect(click.defaultPrevented).toBe(false);
      expect(controlPointerDown).toHaveBeenCalledOnce();
      expect(controlClick).toHaveBeenCalledOnce();
    }
    expect(live.pushEvent).not.toHaveBeenCalled();

    const blockPointerDown = vi.fn();
    const blockClick = vi.fn();
    background.addEventListener("pointerdown", blockPointerDown);
    background.addEventListener("click", blockClick);

    pointer(background, "pointerdown", 210, 270);
    pointer(background, "pointerup", 210, 270);
    pointer(background, "click", 210, 270);

    expect(live.pushEvent).toHaveBeenLastCalledWith("comments_place", {
      block_id: 42,
      x: 25,
      y: 25,
    });
    expect(blockPointerDown).not.toHaveBeenCalled();
    expect(blockClick).not.toHaveBeenCalled();
  });

  it("keeps a dragged pin inside its original block and persists the expected revision", async () => {
    const { wrapper } = setup();
    await nextTick();
    const pin = wrapper.get("#sheet-comment-pin-12").element;

    pointer(pin, "pointerdown", 210, 320);
    await nextTick();
    expect(wrapper.emitted("interactionChange")?.at(-1)).toEqual([true]);
    pointer(window, "pointermove", 900, 1_000);
    await nextTick();
    expect(wrapper.get("#sheet-comment-pin-12").attributes("style")).toContain("left: 500px");
    expect(wrapper.get("#sheet-comment-pin-12").attributes("style")).toContain("top: 400px");

    pointer(window, "pointerup", 900, 1_000);
    await nextTick();
    expect(wrapper.emitted("interactionChange")?.at(-1)).toEqual([false]);
    expect(live.pushEvent).toHaveBeenLastCalledWith(
      "comments_move",
      { thread_id: 12, x: 100, y: 100, expected_revision: 3 },
      expect.any(Function),
      expect.any(Function),
    );
  });

  it("reconciles a no-op boundary drag so the pin can be dragged again", async () => {
    const edgeThread = { ...thread, position: { x: 100, y: 100 } };
    const { wrapper } = setup({}, [edgeThread]);
    await nextTick();
    const pin = wrapper.get("#sheet-comment-pin-12").element;

    pointer(pin, "pointerdown", 500, 400);
    pointer(window, "pointermove", 900, 1_000);
    pointer(window, "pointerup", 900, 1_000);

    const firstMove = vi
      .mocked(live.pushEvent)
      .mock.calls.find(([event]) => event === "comments_move");
    expect(firstMove).toBeDefined();
    const reply = firstMove?.[2];
    expect(reply).toEqual(expect.any(Function));
    if (typeof reply === "function") reply({ ok: true, thread: edgeThread });

    pointer(pin, "pointerdown", 500, 400);
    pointer(window, "pointermove", 450, 350);
    pointer(window, "pointerup", 450, 350);

    expect(
      vi.mocked(live.pushEvent).mock.calls.filter(([event]) => event === "comments_move"),
    ).toHaveLength(2);
  });

  it("moves a focused pin with arrow keys in normalized block coordinates", async () => {
    const { wrapper } = setup();
    await nextTick();
    const pin = wrapper.get("#sheet-comment-pin-12");

    expect(pin.attributes("aria-describedby")).toContain("sheet-comment-pin-keyboard-instructions");
    await pin.trigger("keydown", { key: "ArrowRight" });

    expect(live.pushEvent).toHaveBeenLastCalledWith(
      "comments_move",
      { thread_id: 12, x: 30, y: 50, expected_revision: 3 },
      expect.any(Function),
      expect.any(Function),
    );
  });

  it("keeps pins readable but blocks creation and movement without comment access", async () => {
    const { wrapper, background } = setup({ canComment: false });
    await nextTick();
    const contextMenu = pointer(background, "contextmenu", 310, 320, 2);
    expect(contextMenu.defaultPrevented).toBe(false);

    const pin = wrapper.get("#sheet-comment-pin-12");
    pointer(pin.element, "pointerdown", 210, 320);
    pointer(window, "pointermove", 500, 500);
    pointer(window, "pointerup", 500, 500);
    expect(live.pushEvent).not.toHaveBeenCalled();

    await pin.trigger("click");
    expect(live.pushEvent).toHaveBeenLastCalledWith("comments_select_thread", {
      thread_id: 12,
      presentation: "canvas",
    });
  });

  it("supports the safe C shortcut and focuses a deep-linked block comment", async () => {
    const scrollIntoView = vi.spyOn(Element.prototype, "scrollIntoView");
    const { input } = setup({}, [thread], 12);
    await flushPromises();

    expect(scrollIntoView).toHaveBeenCalledWith({ behavior: "smooth", block: "center" });

    input.dispatchEvent(new KeyboardEvent("keydown", { key: "c", bubbles: true }));
    expect(live.pushEvent).not.toHaveBeenCalled();

    document.body.dispatchEvent(new KeyboardEvent("keydown", { key: "c", bubbles: true }));
    expect(live.pushEvent).toHaveBeenLastCalledWith("comments_mode", { active: true });
  });

  it("renders and focuses a resolved deep-linked thread omitted from open pins", async () => {
    const resolvedThread: SheetCommentThread = {
      ...thread,
      status: "resolved",
      resolved_at: "2026-09-05T10:00:00Z",
      resolved_by: author,
    };
    const scrollIntoView = vi.spyOn(Element.prototype, "scrollIntoView");
    const { wrapper } = setup(
      {
        open: true,
        presentation: "canvas",
        thread: resolvedThread,
        threads: [resolvedThread],
      },
      [],
      resolvedThread.id,
    );
    await flushPromises();

    expect(wrapper.find("#sheet-comment-pin-12").exists()).toBe(true);
    expect(wrapper.find("#sheet-comment-popover").exists()).toBe(true);
    expect(scrollIntoView).toHaveBeenCalledWith({ behavior: "smooth", block: "center" });
  });
});
