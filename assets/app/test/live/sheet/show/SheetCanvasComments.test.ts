import { flushPromises, mount, type VueWrapper } from "@vue/test-utils";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { nextTick } from "vue";
import { createMockLive } from "@app/test/setup";
import type { SheetCommentsPanelState, SheetCommentThread } from "@modules/sheets/types/comments";

const live = createMockLive();
vi.mock("@shared/composables/useLive", () => ({ useLive: () => live }));
const { default: SheetCanvasComments } =
  await import("@modules/sheets/components/chrome/SheetCanvasComments.vue");

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
  preview: "Increase the starting value.",
  position: { x: 25, y: 300 },
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
  statusFilter: "open",
  error: null,
};

let wrappers: VueWrapper[] = [];

function snapTarget(
  element: HTMLElement,
  type: string,
  id: string,
  bounds: DOMRect,
  label: string,
) {
  element.dataset.sheetCommentType = type;
  element.dataset.sheetCommentId = id;
  element.dataset.sheetCommentLabel = label;
  return vi.spyOn(element, "getBoundingClientRect").mockReturnValue(bounds);
}

async function refreshGeometry() {
  await flushPromises();
  await new Promise<void>((resolve) => window.requestAnimationFrame(() => resolve()));
  await nextTick();
}

function lastRequest(event: string) {
  const request = vi
    .mocked(live.pushEvent)
    .mock.calls.filter(([name]) => name === event)
    .at(-1);
  if (!request) throw new Error(`Expected ${event} request`);
  return request;
}

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

function pointer(
  target: EventTarget,
  type: string,
  x: number,
  y: number,
  button = 0,
  altKey = false,
): MouseEvent {
  const event = new MouseEvent(type, {
    bubbles: true,
    cancelable: true,
    clientX: x,
    clientY: y,
    button,
    altKey,
  });
  Object.defineProperty(event, "pointerId", { value: 1 });
  target.dispatchEvent(event);
  return event;
}

function scrollOwnerFixture(top = 40, height = 560, scrollHeight = 2_500): HTMLElement {
  const owner = document.createElement("div");
  owner.style.overflowY = "auto";
  Object.defineProperties(owner, {
    clientHeight: { configurable: true, value: height },
    scrollHeight: { configurable: true, value: scrollHeight },
  });
  vi.spyOn(owner, "getBoundingClientRect").mockReturnValue(rect(0, top, 820, height));
  return owner;
}

function setup(
  state: Partial<SheetCommentsPanelState> = {},
  commentPins = [thread],
  focusThreadId: number | null = null,
  surfaceHeight = 800,
  scrollOwner: HTMLElement | null = null,
  draftStorageKey: string | null = null,
  renderPanel = false,
) {
  const container = document.createElement("main");
  const header = document.createElement("header");
  const row = document.createElement("section");
  const block = document.createElement("div");
  const input = document.createElement("input");
  const button = document.createElement("button");
  const dragHandle = document.createElement("div");
  const outside = document.createElement("div");
  const commentsToggle = document.createElement("button");
  container.dataset.sheetCommentSurface = "true";
  header.dataset.testid = "sheet-header";
  row.dataset.testid = "three-block-row";
  block.dataset.sheetBlockId = "42";
  dragHandle.className = "block-drag-handle";
  commentsToggle.id = "sheet-comments-toggle";
  row.append(block);
  container.append(header, row, input, button, dragHandle);
  if (scrollOwner) {
    scrollOwner.append(container);
    document.body.append(commentsToggle, scrollOwner, outside);
  } else {
    document.body.append(commentsToggle, container, outside);
  }

  const surfaceRect = vi
    .spyOn(container, "getBoundingClientRect")
    .mockReturnValue(rect(10, 20, 800, surfaceHeight));

  const wrapper = mount(SheetCanvasComments, {
    attachTo: container,
    props: {
      container: () => container,
      state: { ...base, ...state },
      commentPins,
      focusThreadId,
      draftStorageKey,
    },
    global: { stubs: { SheetCommentsPanel: !renderPanel } },
  });
  wrappers.push(wrapper);
  return {
    wrapper,
    container,
    header,
    row,
    block,
    input,
    button,
    dragHandle,
    commentsToggle,
    outside,
    surfaceRect,
  };
}

beforeEach(() => {
  vi.clearAllMocks();
  window.sessionStorage.clear();
  vi.stubGlobal("innerHeight", 1_200);
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
  vi.restoreAllMocks();
});

describe("Sheet canvas comments", () => {
  it("positions pins against the whole sheet, previews them, and opens the thread", async () => {
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
    const { wrapper } = setup({ open: true, presentation: "canvas", thread });
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

    const outsideControl = document.createElement("button");
    container.append(outsideControl);
    outsideControl.focus();
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

  it("offers Add comment on the header and a multi-block row using sheet coordinates", async () => {
    const { wrapper, header, row } = setup();

    const headerMenu = pointer(header, "contextmenu", 410, 120, 2);
    await nextTick();
    expect(headerMenu.defaultPrevented).toBe(true);
    expect(wrapper.get("#sheet-comment-context-menu").attributes("role")).toBe("menu");
    await wrapper.get("#sheet-comment-context-add").trigger("click");
    expect(live.pushEvent).toHaveBeenLastCalledWith("comments_place", {
      x: 50,
      y: 100,
      context: null,
    });

    pointer(row, "contextmenu", 610, 520, 2);
    await nextTick();
    await wrapper.get("#sheet-comment-context-add").trigger("click");
    expect(live.pushEvent).toHaveBeenLastCalledWith("comments_place", {
      x: 75,
      y: 500,
      context: null,
    });
  });

  it("never opens placement outside the gray sheet bounds", async () => {
    const { wrapper, outside, row } = setup({ placing: true });

    pointer(outside, "pointerdown", 900, 400);
    pointer(outside, "contextmenu", 900, 400, 2);

    // A positioned descendant can still belong to the sheet DOM while being painted outside it.
    pointer(row, "pointerdown", 900, 400);
    pointer(row, "contextmenu", 900, 400, 2);
    await nextTick();

    expect(live.pushEvent).not.toHaveBeenCalled();
    expect(wrapper.find("#sheet-comment-context-menu").exists()).toBe(false);
  });

  it("places a comment in the sheet center with Enter while placement mode is active", () => {
    const { container } = setup({ placing: true });
    container.tabIndex = 0;
    container.focus();
    container.dispatchEvent(
      new KeyboardEvent("keydown", { key: "Enter", bubbles: true, cancelable: true }),
    );

    expect(live.pushEvent).toHaveBeenLastCalledWith("comments_place", {
      x: 50,
      y: 400,
      context: null,
    });
  });

  it("places with Enter in the visible part of a long sheet", () => {
    const scrollOwner = scrollOwnerFixture();
    const { container, surfaceRect } = setup({ placing: true }, [], null, 2_000, scrollOwner);
    scrollOwner.scrollTop = 400;
    surfaceRect.mockReturnValue(rect(10, -400, 800, 2_000));

    container.tabIndex = 0;
    container.focus();
    container.dispatchEvent(
      new KeyboardEvent("keydown", { key: "Enter", bubbles: true, cancelable: true }),
    );

    expect(live.pushEvent).toHaveBeenLastCalledWith("comments_place", {
      x: 50,
      y: 720,
      context: null,
    });
  });

  it("preserves interactive controls and places on any non-interactive sheet area", () => {
    const { header, input, button, dragHandle } = setup({ placing: true });

    for (const control of [input, button, dragHandle]) {
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

    const surfacePointerDown = vi.fn();
    header.addEventListener("pointerdown", surfacePointerDown);
    pointer(header, "pointerdown", 210, 270);
    pointer(header, "pointerup", 210, 270);
    pointer(header, "click", 210, 270);

    expect(live.pushEvent).toHaveBeenLastCalledWith("comments_place", {
      x: 25,
      y: 250,
      context: null,
    });
    expect(surfacePointerDown).not.toHaveBeenCalled();
  });

  it("drags across the entire sheet and keeps the pin center off the black exterior", async () => {
    const { wrapper } = setup();
    await nextTick();
    const pin = wrapper.get("#sheet-comment-pin-12").element;

    pointer(pin, "pointerdown", 210, 320);
    pointer(window, "pointermove", 1_000, 1_000);
    await nextTick();
    expect(wrapper.get("#sheet-comment-pin-12").attributes("style")).toContain("left: 784px");
    expect(wrapper.get("#sheet-comment-pin-12").attributes("style")).toContain("top: 784px");

    pointer(window, "pointerup", 1_000, 1_000);
    expect(live.pushEvent).toHaveBeenLastCalledWith(
      "comments_move",
      { thread_id: 12, x: 98, y: 784, context: null, expected_revision: 3 },
      expect.any(Function),
      expect.any(Function),
    );
  });

  it("uses the app scroll owner and current surface rect during a long sheet drag", async () => {
    vi.stubGlobal("innerHeight", 600);
    const animationFrames: FrameRequestCallback[] = [];
    vi.spyOn(window, "requestAnimationFrame").mockImplementation((callback) => {
      animationFrames.push(callback);
      return animationFrames.length;
    });
    vi.spyOn(window, "cancelAnimationFrame").mockImplementation(() => {});

    const longThread = { ...thread, position: { x: 25, y: 500 } };
    const scrollOwner = scrollOwnerFixture();
    const { wrapper, surfaceRect } = setup({}, [longThread], null, 2_000, scrollOwner);
    await nextTick();
    scrollOwner.scrollTop = 0;

    let surfaceTop = 40;
    surfaceRect.mockImplementation(() => rect(10, surfaceTop, 800, 2_000));
    const windowScroll = vi.spyOn(window, "scrollBy");
    const scrollBy = vi.fn((options: ScrollToOptions) => {
      const top = options.top ?? 0;
      scrollOwner.scrollTop += top;
      surfaceTop -= top;
    });
    Object.defineProperty(scrollOwner, "scrollBy", { configurable: true, value: scrollBy });

    const pin = wrapper.get("#sheet-comment-pin-12").element;
    pointer(pin, "pointerdown", 210, 540);
    pointer(window, "pointermove", 210, 590);
    for (const frame of animationFrames.splice(0)) frame(performance.now());
    expect(scrollBy).toHaveBeenCalled();
    expect(windowScroll).not.toHaveBeenCalled();
    pointer(window, "pointerup", 210, 590);

    const move = vi.mocked(live.pushEvent).mock.calls.find(([event]) => event === "comments_move");
    expect(move).toBeDefined();
    if (!move) throw new Error("Expected comments_move to be sent");
    expect(move[1]).toMatchObject({ thread_id: 12, x: 25, expected_revision: 3 });
    expect((move[1] as { y: number }).y).toBeGreaterThan(550);
  });

  it("releases a no-op boundary move after an unchanged success reply", async () => {
    const edgeThread = { ...thread, position: { x: 98, y: 784 } };
    const { wrapper } = setup({}, [edgeThread]);
    await nextTick();
    const pin = wrapper.get("#sheet-comment-pin-12").element;

    pointer(pin, "pointerdown", 794, 804);
    pointer(window, "pointermove", 900, 900);
    pointer(window, "pointerup", 900, 900);
    const firstMove = vi
      .mocked(live.pushEvent)
      .mock.calls.find(([event]) => event === "comments_move");
    expect(firstMove?.[2]).toEqual(expect.any(Function));
    if (typeof firstMove?.[2] === "function") firstMove[2]({ ok: true, thread: edgeThread });

    pointer(pin, "pointerdown", 794, 804);
    pointer(window, "pointermove", 700, 700);
    pointer(window, "pointerup", 700, 700);
    expect(
      vi.mocked(live.pushEvent).mock.calls.filter(([event]) => event === "comments_move"),
    ).toHaveLength(2);
  });

  it("moves a focused pin by equal visual steps on both axes", async () => {
    const { wrapper } = setup();
    await nextTick();
    const pin = wrapper.get("#sheet-comment-pin-12");

    await pin.trigger("keydown", { key: "ArrowRight" });
    await pin.trigger("keydown", { key: "ArrowDown" });
    await pin.trigger("keydown", { key: "ArrowUp", shiftKey: true });
    expect(live.pushEvent).not.toHaveBeenCalled();
    await pin.trigger("keydown", { key: "Enter" });
    expect(live.pushEvent).toHaveBeenLastCalledWith(
      "comments_move",
      { thread_id: 12, x: 26, y: 307, context: null, expected_revision: 3 },
      expect.any(Function),
      expect.any(Function),
    );
  });

  it("keeps pins readable but blocks creation and movement without comment access", async () => {
    const { wrapper, header } = setup({ canComment: false });
    await nextTick();
    const contextMenu = pointer(header, "contextmenu", 310, 320, 2);
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

  it("supports the safe C shortcut and scrolls a deep-linked sheet comment into view", async () => {
    const scrollIntoView = vi.spyOn(Element.prototype, "scrollIntoView");
    const { input } = setup({}, [thread], 12);
    await flushPromises();
    await new Promise<void>((resolve) => window.requestAnimationFrame(() => resolve()));

    expect(scrollIntoView).toHaveBeenCalledWith({
      behavior: "smooth",
      block: "center",
      inline: "center",
    });

    input.dispatchEvent(new KeyboardEvent("keydown", { key: "c", bubbles: true }));
    expect(live.pushEvent).not.toHaveBeenCalled();

    document.body.dispatchEvent(new KeyboardEvent("keydown", { key: "c", bubbles: true }));
    expect(live.pushEvent).toHaveBeenLastCalledWith("comments_mode", { active: true });
  });

  it("keeps the comment dialog inside the visible part of a scrolled Sheet", async () => {
    const visibleThread = { ...thread, position: { x: 25, y: 920 } };
    const scrollOwner = scrollOwnerFixture();
    const { wrapper, surfaceRect } = setup(
      { open: true, presentation: "canvas", thread: visibleThread },
      [visibleThread],
      null,
      2_000,
      scrollOwner,
    );
    scrollOwner.scrollTop = 400;
    surfaceRect.mockReturnValue(rect(10, -400, 800, 2_000));

    scrollOwner.dispatchEvent(new Event("scroll"));
    await flushPromises();
    vi.spyOn(
      wrapper.get("#sheet-comment-popover").element,
      "getBoundingClientRect",
    ).mockReturnValue(rect(0, 0, 360, 232));
    const measuredThread = { ...visibleThread, id: 13 };
    await wrapper.setProps({
      state: { ...base, open: true, presentation: "canvas", thread: measuredThread },
      commentPins: [measuredThread],
    });
    await flushPromises();

    expect(wrapper.get("#sheet-comment-popover").attributes("style")).toContain("top: 664px");
  });

  it("measures the rendered dialog and keeps it beside a pin near the bottom", async () => {
    const lowThread = { ...thread, position: { x: 25, y: 700 } };
    const { wrapper } = setup({ open: true, presentation: "canvas", thread: lowThread }, [
      lowThread,
    ]);
    await flushPromises();
    vi.spyOn(
      wrapper.get("#sheet-comment-popover").element,
      "getBoundingClientRect",
    ).mockReturnValue(rect(0, 0, 360, 232));
    const measuredThread = { ...lowThread, id: 13 };
    await wrapper.setProps({
      state: { ...base, open: true, presentation: "canvas", thread: measuredThread },
      commentPins: [measuredThread],
    });
    await flushPromises();

    expect(wrapper.get("#sheet-comment-popover").attributes("style")).toContain("top: 444px");

    const lowerThread = { ...measuredThread, position: { x: 25, y: 760 } };
    await wrapper.setProps({
      state: { ...base, open: true, presentation: "canvas", thread: lowerThread },
      commentPins: [lowerThread],
    });
    await flushPromises();

    expect(wrapper.get("#sheet-comment-popover").attributes("style")).toContain("top: 504px");
  });

  it("renders and focuses a resolved deep-linked thread omitted from open pins", async () => {
    const resolvedThread: SheetCommentThread = {
      ...thread,
      status: "resolved",
      resolved_at: "2026-09-05T10:00:00Z",
      resolved_by: author,
    };
    const scrollIntoView = vi.spyOn(Element.prototype, "scrollIntoView");
    const { wrapper, commentsToggle } = setup(
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
    await new Promise<void>((resolve) => window.requestAnimationFrame(() => resolve()));

    expect(wrapper.find("#sheet-comment-pin-12").exists()).toBe(true);
    expect(wrapper.find("#sheet-comment-popover").exists()).toBe(true);
    expect(scrollIntoView).toHaveBeenCalled();
    expect(document.activeElement).toBe(wrapper.get("#sheet-comment-popover").element);

    await wrapper.setProps({
      state: { ...base, open: false, presentation: "panel", threads: [resolvedThread] },
    });
    await flushPromises();

    expect(wrapper.find("#sheet-comment-pin-12").exists()).toBe(false);
    expect(document.activeElement).toBe(commentsToggle);
  });

  it("returns focus to the comments control after closing a draft conversation", async () => {
    const { wrapper, commentsToggle } = setup(
      {
        open: true,
        presentation: "canvas",
        draftPosition: { x: 40, y: 240 },
      },
      [],
    );
    await flushPromises();
    expect(document.activeElement).toBe(wrapper.get("#sheet-comment-popover").element);

    await wrapper.setProps({ state: { ...base, open: false, presentation: "panel" } });
    await flushPromises();

    expect(document.activeElement).toBe(commentsToggle);
  });

  it("restores a sheet-scoped draft position after a page reload", async () => {
    const storageKey = "storyarn:sheet-comment-draft:4:7";
    window.sessionStorage.setItem(
      storageKey,
      JSON.stringify({ position: { x: 40, y: 640 }, body: "Keep this draft" }),
    );

    setup({}, [], null, 800, null, storageKey);
    await flushPromises();

    expect(live.pushEvent).toHaveBeenLastCalledWith(
      "comments_place",
      { x: 40, y: 640, context: null },
      expect.any(Function),
      expect.any(Function),
    );
  });

  it("removes the saved draft when the draft conversation is explicitly closed", async () => {
    const storageKey = "storyarn:sheet-comment-draft:4:7";
    window.sessionStorage.setItem(
      storageKey,
      JSON.stringify({ position: { x: 40, y: 240 }, body: "Discard this draft" }),
    );
    const { wrapper } = setup(
      {
        open: true,
        presentation: "canvas",
        draftPosition: { x: 40, y: 240 },
      },
      [],
      null,
      800,
      null,
      storageKey,
    );

    await wrapper.setProps({ state: { ...base, open: false, presentation: "panel" } });
    await flushPromises();

    expect(window.sessionStorage.getItem(storageKey)).toBeNull();
  });

  it("keeps the saved draft when an existing thread is selected", async () => {
    const storageKey = "storyarn:sheet-comment-draft:4:7";
    const storedDraft = {
      position: { x: 40, y: 240 },
      body: "Return to this draft",
      mentionIds: [],
    };
    window.sessionStorage.setItem(storageKey, JSON.stringify(storedDraft));
    const { wrapper } = setup(
      {
        open: true,
        presentation: "canvas",
        draftPosition: storedDraft.position,
      },
      [thread],
      null,
      800,
      null,
      storageKey,
    );

    await wrapper.setProps({
      state: {
        ...base,
        open: true,
        presentation: "canvas",
        thread,
      },
    });
    await flushPromises();

    expect(JSON.parse(window.sessionStorage.getItem(storageKey) ?? "{}")).toEqual(storedDraft);
  });

  it("keeps drafts isolated when the mounted surface navigates to another sheet", async () => {
    const firstKey = "storyarn:sheet-comment-draft:4:7";
    const secondKey = "storyarn:sheet-comment-draft:4:8";
    window.sessionStorage.setItem(
      firstKey,
      JSON.stringify({ position: { x: 40, y: 240 }, body: "First Sheet" }),
    );
    window.sessionStorage.setItem(
      secondKey,
      JSON.stringify({ position: { x: 65, y: 520 }, body: "Second Sheet" }),
    );
    const { wrapper } = setup(
      {
        open: true,
        presentation: "canvas",
        draftPosition: { x: 40, y: 240 },
      },
      [],
      null,
      800,
      null,
      firstKey,
    );
    vi.mocked(live.pushEvent).mockClear();

    await wrapper.setProps({
      state: base,
      draftStorageKey: secondKey,
    });
    await flushPromises();

    expect(window.sessionStorage.getItem(firstKey)).toContain("First Sheet");
    expect(window.sessionStorage.getItem(secondKey)).toContain("Second Sheet");
    expect(live.pushEvent).toHaveBeenLastCalledWith(
      "comments_place",
      { x: 65, y: 520, context: null },
      expect.any(Function),
      expect.any(Function),
    );
  });

  it("previews header context and persists its offset with the released position", async () => {
    const { wrapper, header } = setup();
    snapTarget(header, "sheet_header", "7", rect(170, 100, 500, 100), "Header");
    await nextTick();
    const pin = wrapper.get("#sheet-comment-pin-12").element;
    pointer(pin, "pointerdown", 210, 320);
    pointer(window, "pointermove", 210, 150);
    await nextTick();
    expect(wrapper.get("#sheet-comment-snap-preview").text()).toContain("Header");
    expect(live.pushEvent).not.toHaveBeenCalled();
    pointer(window, "pointerup", 210, 150);
    expect(lastRequest("comments_move")[1]).toEqual({
      thread_id: 12,
      expected_revision: 3,
      x: 25,
      y: 130,
      context: { type: "sheet_header", id: "7", offset: { x: 5, y: 50 } },
    });
  });

  it("cycles from a block to its row with the keyboard and commits only on Enter", async () => {
    const { wrapper, row, block } = setup();
    const rowId = "4d92b7f1-0713-4cae-bd33-c749722399aa";
    snapTarget(row, "sheet_column_group", rowId, rect(90, 300, 640, 160), "Row of 3 blocks");
    snapTarget(block, "sheet_block", "42", rect(210, 300, 200, 160), "Starting power");
    await nextTick();
    const pin = wrapper.get("#sheet-comment-pin-12");
    await pin.trigger("keydown", { key: "ArrowRight" });
    expect(wrapper.get("#sheet-comment-snap-preview").text()).toContain("Starting power");
    await pin.trigger("keydown", { key: "]" });
    expect(wrapper.get("#sheet-comment-snap-preview").text()).toContain("Row of 3 blocks");
    expect(live.pushEvent).not.toHaveBeenCalled();
    await pin.trigger("keydown", { key: "Enter" });
    expect(lastRequest("comments_move")[1]).toEqual({
      thread_id: 12,
      expected_revision: 3,
      x: 26,
      y: 300,
      context: { type: "sheet_column_group", id: rowId, offset: { x: 16, y: 20 } },
    });
  });

  it("uses Alt on release to detach context and the toggle to place freely", async () => {
    const { wrapper, header } = setup({ placing: true });
    snapTarget(header, "sheet_header", "7", rect(170, 100, 500, 100), "Header");
    await nextTick();
    const pin = wrapper.get("#sheet-comment-pin-12").element;
    pointer(pin, "pointerdown", 210, 320);
    pointer(window, "pointermove", 210, 150);
    pointer(window, "pointerup", 210, 150, 0, true);
    expect(lastRequest("comments_move")[1]).toMatchObject({ x: 25, y: 130, context: null });
    await wrapper.get("#sheet-comment-magnetism-toggle").trigger("click");
    expect(wrapper.get("#sheet-comment-magnetism-toggle").attributes("aria-pressed")).toBe("false");
    pointer(header, "pointerdown", 210, 150);
    expect(lastRequest("comments_place")[1]).toEqual({ x: 25, y: 130, context: null });
  });

  it.each(["Escape", "lostpointercapture", "pointercancel", "blur"])(
    "restores the original position and context without saving after %s",
    async (cancel) => {
      const { wrapper, header } = setup();
      snapTarget(header, "sheet_header", "7", rect(170, 100, 500, 100), "Header");
      await nextTick();
      const pin = wrapper.get("#sheet-comment-pin-12");
      pointer(pin.element, "pointerdown", 210, 320);
      pointer(window, "pointermove", 210, 150);
      if (cancel === "Escape") await pin.trigger("keydown", { key: "Escape" });
      else if (cancel === "lostpointercapture") pointer(pin.element, cancel, 210, 150);
      else if (cancel === "blur") window.dispatchEvent(new Event("blur"));
      else pointer(window, cancel, 210, 150);
      pointer(window, "pointerup", 210, 150);
      await nextTick();
      expect(live.pushEvent).not.toHaveBeenCalled();
      expect(pin.attributes("style")).toContain("left: 200px");
      expect(pin.attributes("style")).toContain("top: 300px");
      expect(wrapper.find("#sheet-comment-snap-preview").exists()).toBe(false);
    },
  );

  it("waits for authoritative pin props after ACK and ignores an old failure during a newer move", async () => {
    const { wrapper } = setup();
    await nextTick();
    const pin = wrapper.get("#sheet-comment-pin-12");
    pointer(pin.element, "pointerdown", 210, 320);
    pointer(window, "pointerup", 250, 320);
    const first = lastRequest("comments_move");
    first[2]?.({ ok: true });
    await nextTick();
    expect(pin.attributes("aria-busy")).toBe("true");
    expect(pin.attributes("style")).toContain("left: 240px");
    pointer(pin.element, "pointerdown", 250, 320);
    pointer(window, "pointerup", 330, 320);
    expect(
      vi.mocked(live.pushEvent).mock.calls.filter(([event]) => event === "comments_move"),
    ).toHaveLength(1);

    const confirmed = { ...thread, revision: 4, position: { x: 30, y: 300 }, context: null };
    await wrapper.setProps({ commentPins: [confirmed] });
    expect(pin.attributes("aria-busy")).toBe("false");
    pointer(pin.element, "pointerdown", 250, 320);
    pointer(window, "pointerup", 330, 320);
    const second = lastRequest("comments_move");
    first[2]?.({ ok: false });
    await nextTick();
    expect(pin.attributes("aria-busy")).toBe("true");
    expect(pin.attributes("style")).toContain("left: 320px");
    expect(wrapper.find('[role="alert"]').exists()).toBe(false);
    second[2]?.({ ok: false });
    await nextTick();
    expect(pin.attributes("aria-busy")).toBe("false");
    expect(pin.attributes("style")).toContain("left: 240px");
    expect(wrapper.find('[role="alert"]').exists()).toBe(true);
  });

  it("keeps draft text and disables the composer until position and context props confirm its move", async () => {
    const draftState = {
      ...base,
      open: true,
      presentation: "canvas" as const,
      draftId: "draft-1",
      draftPosition: { x: 25, y: 300 },
    };
    const storageKey = "storyarn:sheet-comment-draft:4:7";
    const { wrapper, header } = setup(draftState, [], null, 800, null, storageKey, true);
    snapTarget(header, "sheet_header", "7", rect(170, 100, 500, 100), "Header");
    await flushPromises();
    await wrapper.get("#sheet-comment-body").setValue("Preserve this observation");
    const pin = wrapper.get("#sheet-comment-draft-pin");
    pointer(pin.element, "pointerdown", 210, 320);
    pointer(window, "pointermove", 210, 150);
    await nextTick();
    expect(wrapper.get("#sheet-comment-body").attributes("disabled")).toBeDefined();
    expect(wrapper.get("#sheet-comment-send").attributes("disabled")).toBeDefined();
    pointer(window, "pointerup", 210, 150);
    const move = lastRequest("comments_place");
    const draftContext = { type: "sheet_header", id: "7", offset: { x: 5, y: 50 } };
    expect(move[1]).toEqual({
      x: 25,
      y: 130,
      context: draftContext,
      moving_draft: true,
      draft_id: "draft-1",
    });
    move[2]?.({ ok: true });
    await nextTick();
    expect(pin.attributes("aria-busy")).toBe("true");
    expect(wrapper.get("#sheet-comment-send").attributes("disabled")).toBeDefined();
    await wrapper.setProps({
      state: { ...draftState, draftPosition: { x: 25, y: 130 }, draftContext },
    });
    expect(pin.attributes("aria-busy")).toBe("false");
    expect(wrapper.get("#sheet-comment-send").attributes("disabled")).toBeUndefined();
    expect((wrapper.get("#sheet-comment-body").element as HTMLTextAreaElement).value).toBe(
      "Preserve this observation",
    );
    expect(JSON.parse(window.sessionStorage.getItem(storageKey)!)).toMatchObject({
      body: "Preserve this observation",
      position: { x: 25, y: 130 },
      context: draftContext,
    });
  });

  it("ignores a replaced draft's late reply while its replacement is pending", async () => {
    const draftState = {
      ...base,
      open: true,
      presentation: "canvas" as const,
      draftId: "old-draft",
      draftPosition: { x: 25, y: 300 },
    };
    const { wrapper } = setup(draftState, []);
    await flushPromises();
    const pin = wrapper.get("#sheet-comment-draft-pin");
    pointer(pin.element, "pointerdown", 210, 320);
    pointer(window, "pointerup", 250, 320);
    const old = lastRequest("comments_place");
    await wrapper.setProps({
      state: { ...draftState, draftId: "replacement", draftPosition: { x: 40, y: 300 } },
    });
    pointer(pin.element, "pointerdown", 330, 320);
    pointer(window, "pointerup", 410, 320);
    const replacement = lastRequest("comments_place");
    old[2]?.({ ok: false });
    await nextTick();
    expect(pin.attributes("aria-busy")).toBe("true");
    expect(pin.attributes("style")).toContain("left: 400px");
    expect(wrapper.find('[role="alert"]').exists()).toBe(false);
    expect(replacement[1]).toMatchObject({ draft_id: "replacement", x: 50 });
  });

  it("follows contextual block layout changes and uses its saved fallback after removal", async () => {
    const context = {
      type: "sheet_block",
      id: "42",
      label: "Starting power",
      status: "available" as const,
      offset: { x: 5, y: 20 },
    };
    const contextual = { ...thread, context, position: { x: 60, y: 600 } };
    const { wrapper, block, container, surfaceRect } = setup({}, [contextual]);
    const blockRect = snapTarget(
      block,
      "sheet_block",
      "42",
      rect(170, 220, 500, 100),
      "Starting power",
    );
    await refreshGeometry();
    const pin = wrapper.get("#sheet-comment-pin-12");
    expect(pin.attributes("style")).toContain("left: 200px");
    expect(pin.attributes("style")).toContain("top: 220px");
    blockRect.mockReturnValue(rect(170, 420, 500, 100));
    container.setAttribute("data-layout-revision", "2");
    await refreshGeometry();
    expect(pin.attributes("style")).toContain("top: 420px");

    surfaceRect.mockReturnValue(rect(10, 20, 400, 800));
    blockRect.mockReturnValue(rect(90, 420, 260, 100));
    window.dispatchEvent(new Event("resize"));
    await nextTick();
    expect(pin.attributes("style")).toContain("left: 100px");
    block.remove();
    await refreshGeometry();
    expect(pin.attributes("style")).toContain("left: 240px");
    expect(pin.attributes("style")).toContain("top: 600px");
    expect(live.pushEvent).not.toHaveBeenCalled();
  });

  it("restores context with the saved draft after a reload", async () => {
    const storageKey = "storyarn:sheet-comment-draft:4:7";
    const context = { type: "sheet_header", id: "7", offset: { x: 5, y: 50 } };
    window.sessionStorage.setItem(
      storageKey,
      JSON.stringify({ body: "A header observation", position: { x: 25, y: 130 }, context }),
    );
    setup({}, [], null, 800, null, storageKey);
    await flushPromises();
    expect(lastRequest("comments_place")[1]).toEqual({ x: 25, y: 130, context });
  });

  it("retries a restored draft once as free placement if its context disappeared, retaining the text", async () => {
    const storageKey = "storyarn:sheet-comment-draft:4:7";
    const context = { type: "sheet_block", id: "42", offset: { x: 5, y: 20 } };
    const position = { x: 25, y: 300 };
    window.sessionStorage.setItem(
      storageKey,
      JSON.stringify({ body: "Keep this observation", position, context }),
    );
    const { wrapper } = setup({}, [], null, 800, null, storageKey);
    await flushPromises();
    const contextualRestore = lastRequest("comments_place");
    expect(contextualRestore[1]).toEqual({ ...position, context });
    contextualRestore[2]?.({ ok: false, context_unavailable: true });
    const freeRestore = lastRequest("comments_place");
    expect(freeRestore[1]).toEqual({ ...position, context: null });
    expect(JSON.parse(window.sessionStorage.getItem(storageKey)!)).toMatchObject({ context });
    await wrapper.setProps({
      state: {
        ...base,
        open: true,
        presentation: "canvas",
        draftId: "restored-draft",
        draftPosition: position,
        draftContext: null,
      },
    });
    expect(
      vi.mocked(live.pushEvent).mock.calls.filter(([event]) => event === "comments_place"),
    ).toHaveLength(2);
    expect(JSON.parse(window.sessionStorage.getItem(storageKey)!)).toMatchObject({
      body: "Keep this observation",
      position,
      context: null,
    });

    const replacementPosition = { x: 60, y: 500 };
    const replacementContext = { type: "sheet_header", id: "7", offset: { x: 5, y: 50 } };
    await wrapper.setProps({
      state: {
        ...base,
        open: true,
        presentation: "canvas",
        draftId: "replacement-draft",
        draftPosition: replacementPosition,
        draftContext: replacementContext,
      },
    });
    freeRestore[2]?.({ ok: true });
    await nextTick();
    expect(JSON.parse(window.sessionStorage.getItem(storageKey)!)).toMatchObject({
      body: "Keep this observation",
      position: replacementPosition,
      context: replacementContext,
    });
  });

  it("does not retry an old sheet's unavailable draft after navigation", async () => {
    const firstKey = "storyarn:sheet-comment-draft:4:7";
    const secondKey = "storyarn:sheet-comment-draft:4:8";
    const context = { type: "sheet_block", id: "42", offset: { x: 5, y: 20 } };
    const firstDraft = { body: "First sheet", position: { x: 25, y: 300 }, context };
    const secondDraft = { body: "Second sheet", position: { x: 60, y: 500 }, context: null };
    window.sessionStorage.setItem(firstKey, JSON.stringify(firstDraft));
    window.sessionStorage.setItem(secondKey, JSON.stringify(secondDraft));
    const { wrapper } = setup({}, [], null, 800, null, firstKey);
    await flushPromises();
    const firstRestore = lastRequest("comments_place");
    await wrapper.setProps({ draftStorageKey: secondKey });
    await flushPromises();
    const secondRestore = lastRequest("comments_place");
    expect(secondRestore[1]).toEqual({ ...secondDraft.position, context: null });
    firstRestore[2]?.({ ok: false, context_unavailable: true });
    await nextTick();
    expect(
      vi.mocked(live.pushEvent).mock.calls.filter(([event]) => event === "comments_place"),
    ).toHaveLength(2);
    expect(JSON.parse(window.sessionStorage.getItem(firstKey)!)).toEqual(firstDraft);
    expect(JSON.parse(window.sessionStorage.getItem(secondKey)!)).toEqual(secondDraft);
  });

  it("keeps an unchanged pin busy when its ACK advances the revision until authoritative props arrive", async () => {
    const edgeThread = { ...thread, position: { x: 98, y: 784 }, context: null };
    const { wrapper } = setup({}, [edgeThread]);
    await nextTick();
    const pin = wrapper.get("#sheet-comment-pin-12");
    pointer(pin.element, "pointerdown", 794, 804);
    pointer(window, "pointerup", 900, 900);
    const move = lastRequest("comments_move");
    const confirmed = { ...edgeThread, revision: 4 };
    move[2]?.({ ok: true, thread: confirmed });
    await nextTick();
    expect(pin.attributes("aria-busy")).toBe("true");
    pointer(pin.element, "pointerdown", 794, 804);
    pointer(window, "pointerup", 700, 700);
    expect(
      vi.mocked(live.pushEvent).mock.calls.filter(([event]) => event === "comments_move"),
    ).toHaveLength(1);
    await wrapper.setProps({ commentPins: [confirmed] });
    expect(pin.attributes("aria-busy")).toBe("false");
    pointer(pin.element, "pointerdown", 794, 804);
    pointer(window, "pointerup", 700, 700);
    expect(lastRequest("comments_move")[1]).toMatchObject({ expected_revision: 4 });
  });
});
