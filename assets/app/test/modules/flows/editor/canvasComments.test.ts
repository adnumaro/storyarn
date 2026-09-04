import { mount, type VueWrapper } from "@vue/test-utils";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { nextTick } from "vue";
import { createMockLive } from "@app/test/setup";
import type { FlowCommentThread, FlowCommentsPanelState } from "@modules/flows/types/comments";
import {
  commentCanvasPoint,
  commentPopoverPosition,
} from "@modules/flows/editor/lib/comment-geometry";
import { createContextMenuItems } from "@modules/flows/editor/lib/context_menu_items";
import { FlowNode } from "@modules/flows/editor/lib/flow-node";
import {
  activeFlowPlacement,
  startFlowPlacement,
  cancelFlowPlacement,
} from "@modules/flows/editor/lib/flow-placement-state";

const live = createMockLive();
vi.mock("@shared/composables/useLive", () => ({ useLive: () => live }));
const { default: FlowCanvasComments } =
  await import("@modules/flows/editor/components/chrome/FlowCanvasComments.vue");
const thread: FlowCommentThread = {
  id: 12,
  status: "open",
  revision: 3,
  message_count: 1,
  created_at: "2026-09-04T09:00:00Z",
  last_activity_at: "2026-09-04T09:00:00Z",
  resolved_at: null,
  resolved_by: null,
  source: { type: "flow_node", id: 42, flow_id: 7, label: "Dialogue", status: "available" },
  author: { id: 4, display_name: "Ada", avatar_url: null },
  preview: "Why does the guard leave?",
  position: { x: 10, y: 20 },
};
const base: FlowCommentsPanelState = {
  open: false,
  presentation: "panel",
  placing: false,
  threads: [thread],
  nextCursor: null,
  thread: null,
  messages: [],
  messageNextCursor: null,
  members: [],
  canComment: true,
  selectedNodeId: null,
  error: null,
};
let wrappers: VueWrapper[] = [];
let frames: FrameRequestCallback[] = [];
const disconnect = vi.fn();

function pointer(target: EventTarget, type: string, x: number, y: number, button = 0) {
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
async function flushFrames() {
  const pending = frames;
  frames = [];
  for (const callback of pending) callback(0);
  await nextTick();
}
function setup(
  state: Partial<FlowCommentsPanelState> = {},
  pins = [thread],
  focusThreadId: number | null = null,
) {
  const surface = document.createElement("div");
  const container = document.createElement("div");
  surface.append(container);
  document.body.append(surface);
  vi.spyOn(container, "getBoundingClientRect").mockReturnValue({
    left: 10,
    top: 20,
    width: 1000,
    height: 800,
    right: 1010,
    bottom: 820,
    x: 10,
    y: 20,
    toJSON: () => ({}),
  });
  const pipes: Array<(context: { type: string }) => unknown> = [];
  const area = {
    area: { transform: { x: 100, y: 50, k: 2 }, translate: vi.fn() },
    nodeViews: new Map([["node-42", { position: { x: 150, y: 90 } }]]),
    addPipe: (pipe: (context: { type: string }) => unknown) => pipes.push(pipe),
  };
  const wrapper = mount(FlowCanvasComments, {
    attachTo: surface,
    props: {
      area: area as never,
      container,
      state: { ...base, ...state },
      commentPins: pins,
      focusThreadId,
    },
    global: { stubs: { FlowCommentsPanel: true } },
  });
  wrappers.push(wrapper);
  return { wrapper, area, container, pipes };
}

beforeEach(() => {
  vi.clearAllMocks();
  frames = [];
  vi.stubGlobal("requestAnimationFrame", (callback: FrameRequestCallback) => {
    frames.push(callback);
    return frames.length;
  });
  vi.stubGlobal("cancelAnimationFrame", vi.fn());
  vi.stubGlobal(
    "ResizeObserver",
    class {
      observe() {}
      disconnect() {
        disconnect();
      }
    },
  );
});
afterEach(() => {
  for (const wrapper of wrappers) wrapper.unmount();
  wrappers = [];
  cancelFlowPlacement();
  document.body.innerHTML = "";
  vi.unstubAllGlobals();
});

describe("spatial comment geometry and interactions", () => {
  it("preserves a pending dock placement when the comments overlay mounts", async () => {
    startFlowPlacement({ kind: "node", type: "dialogue" });
    setup();
    await nextTick();
    expect(activeFlowPlacement.value).toEqual({ kind: "node", type: "dialogue" });
    expect(live.pushEvent).not.toHaveBeenCalled();
  });

  it("uses absolute Rete origins for nested nodes and follows pan, zoom, and node movement", async () => {
    const { wrapper, area, pipes } = setup();
    await nextTick();
    expect(wrapper.get("#flow-comment-pin-12").attributes("style")).toContain("left: 420px");
    expect(wrapper.get("#flow-comment-pin-12").attributes("style")).toContain("top: 270px");
    area.nodeViews.get("node-42")!.position = { x: 250, y: 190 };
    area.area.transform = { x: 20, y: 30, k: 0.5 };
    pipes[0]({ type: "nodetranslated" });
    await flushFrames();
    expect(wrapper.get("#flow-comment-pin-12").attributes("style")).toContain("left: 150px");
    expect(wrapper.get("#flow-comment-pin-12").attributes("style")).toContain("top: 135px");
  });

  it("keeps free canvas pins independent of nodes and suppresses unavailable sources", () => {
    const free = {
      ...thread,
      source: { ...thread.source, type: "flow_canvas" as const },
      position: { x: 300, y: 400 },
    };
    expect(commentCanvasPoint(free, new Map())).toEqual({ x: 300, y: 400 });
    expect(commentCanvasPoint(thread, new Map())).toBeNull();
    expect(
      commentCanvasPoint({ ...free, source: { ...free.source, status: "unavailable" } }, new Map()),
    ).toBeNull();
    expect(
      commentPopoverPosition(
        { x: 490, y: 390 },
        { width: 500, height: 400 },
        { width: 300, height: 200 },
      ),
    ).toEqual({ x: 166, y: 188 });
  });

  it("places at the actual click with zoom conversion before any graph selection or drag", async () => {
    const { container } = setup({ placing: true });
    const graphPointerDown = vi.fn();
    const graphPointerUp = vi.fn();
    container.addEventListener("pointerdown", graphPointerDown);
    container.addEventListener("pointerup", graphPointerUp);
    const node = document.createElement("div");
    node.dataset.flowCommentNode = "42";
    container.append(node);
    pointer(node, "pointerdown", 500, 300);
    pointer(node, "pointerup", 500, 300);
    expect(live.pushEvent).toHaveBeenCalledWith("comments_place", { node_id: 42, x: 45, y: 25 });
    expect(graphPointerDown).not.toHaveBeenCalled();
    expect(graphPointerUp).not.toHaveBeenCalled();
    pointer(container, "pointerdown", 600, 400);
    expect(live.pushEvent).toHaveBeenLastCalledWith("comments_place", {
      node_id: null,
      x: 245,
      y: 165,
    });
  });

  it("shows a preview on hover or keyboard focus and opens a floating thread on click", async () => {
    const { wrapper } = setup();
    await nextTick();
    const pin = wrapper.get("#flow-comment-pin-12");
    await pin.trigger("pointerenter");
    expect(wrapper.get('[role="tooltip"]').text()).toContain("Ada");
    expect(wrapper.get('[role="tooltip"]').text()).toContain("Why does the guard leave?");
    await pin.trigger("pointerleave");
    expect(wrapper.find('[role="tooltip"]').exists()).toBe(false);
    await pin.trigger("focus");
    expect(wrapper.find('[role="tooltip"]').exists()).toBe(true);
    await pin.trigger("click");
    expect(live.pushEvent).toHaveBeenLastCalledWith("comments_select_thread", {
      thread_id: 12,
      presentation: "canvas",
    });
  });

  it("commits one move at pointerup in canvas units, suppresses the resulting click, and rolls back rejection", async () => {
    const { wrapper } = setup();
    await nextTick();
    const pin = wrapper.get("#flow-comment-pin-12");
    pointer(pin.element, "pointerdown", 200, 200);
    pointer(window, "pointermove", 240, 220);
    expect(live.pushEvent).not.toHaveBeenCalled();
    pointer(window, "pointerup", 240, 220);
    expect(live.pushEvent).toHaveBeenCalledWith(
      "comments_move",
      { thread_id: 12, x: 30, y: 30, expected_revision: 3 },
      expect.any(Function),
      expect.any(Function),
    );
    pin.element.dispatchEvent(new MouseEvent("click", { bubbles: true, detail: 1 }));
    expect(live.pushEvent).toHaveBeenCalledTimes(1);
    vi.mocked(live.pushEvent).mock.calls[0][2]!({ ok: false });
    await nextTick();
    expect(pin.attributes("style")).toContain("left: 420px");
    expect(wrapper.find('[role="alert"]').exists()).toBe(true);
  });

  it("moves a draft with an explicit preserve-draft signal", async () => {
    const { wrapper } = setup({
      open: true,
      presentation: "canvas",
      draftPosition: { x: 20, y: 30 },
    });
    await nextTick();
    pointer(wrapper.get("#flow-comment-draft-pin").element, "pointerdown", 200, 200);
    pointer(window, "pointermove", 220, 220);
    pointer(window, "pointerup", 220, 220);
    expect(live.pushEvent).toHaveBeenCalledWith(
      "comments_place",
      { node_id: null, x: 30, y: 40, moving_draft: true },
      expect.any(Function),
      expect.any(Function),
    );
    vi.mocked(live.pushEvent).mock.calls[0][3]!(new Error("Disconnected"));
    await nextTick();
    expect(wrapper.get("#flow-comment-draft-pin").attributes("style")).toContain("left: 140px");
  });

  it("allows viewers to read pins but never create or move them", async () => {
    const { wrapper, container } = setup({ canComment: false, placing: true });
    await nextTick();
    const pin = wrapper.get("#flow-comment-pin-12");
    pointer(pin.element, "pointerdown", 200, 200);
    pointer(window, "pointermove", 240, 220);
    pointer(window, "pointerup", 240, 220);
    pointer(container, "pointerdown", 500, 300);
    document.dispatchEvent(new KeyboardEvent("keydown", { key: "c", bubbles: true }));
    expect(live.pushEvent).not.toHaveBeenCalled();
    await pin.trigger("click");
    expect(live.pushEvent).toHaveBeenCalledExactlyOnceWith("comments_select_thread", {
      thread_id: 12,
      presentation: "canvas",
    });
  });

  it("honors C and Escape, ignores text fields/modifiers, and removes listeners at unmount", async () => {
    const { wrapper } = setup({ placing: true });
    document.dispatchEvent(new KeyboardEvent("keydown", { key: "Escape", bubbles: true }));
    expect(live.pushEvent).toHaveBeenLastCalledWith("comments_mode", { active: false });
    document.dispatchEvent(
      new KeyboardEvent("keydown", { key: "c", ctrlKey: true, bubbles: true }),
    );
    const input = document.createElement("textarea");
    document.body.append(input);
    input.dispatchEvent(new KeyboardEvent("keydown", { key: "c", bubbles: true }));
    expect(live.pushEvent).toHaveBeenCalledTimes(1);
    await wrapper.setProps({ state: { ...base, placing: false } });
    document.dispatchEvent(new KeyboardEvent("keydown", { key: "c", bubbles: true }));
    expect(live.pushEvent).toHaveBeenLastCalledWith("comments_mode", { active: true });
    wrapper.unmount();
    wrappers = [];
    document.dispatchEvent(new KeyboardEvent("keydown", { key: "c", bubbles: true }));
    expect(live.pushEvent).toHaveBeenCalledTimes(2);
    expect(disconnect).toHaveBeenCalledOnce();
  });

  it("focuses a free-canvas deep link without picking any node", async () => {
    const free = {
      ...thread,
      source: { ...thread.source, type: "flow_canvas" as const },
      position: { x: 300, y: 400 },
    };
    const { area } = setup({ open: true, thread: free, presentation: "canvas" }, [free], 12);
    await nextTick();
    expect(area.area.translate).toHaveBeenCalledWith(-200, -400);
    expect(live.pushEvent).not.toHaveBeenCalled();
  });

  it("removes a selected resolved pin and unmounts the popup when the thread closes", async () => {
    const resolved = { ...thread, status: "resolved" as const };
    const { wrapper } = setup({ open: true, presentation: "canvas", thread: resolved }, []);
    await nextTick();
    expect(wrapper.find("#flow-comment-pin-12").exists()).toBe(true);
    expect(wrapper.find("#flow-comment-popover").exists()).toBe(true);
    await wrapper.setProps({ state: { ...base, thread: resolved, open: false } });
    expect(wrapper.find("#flow-comment-pin-12").exists()).toBe(false);
    expect(wrapper.find("#flow-comment-popover").exists()).toBe(false);
  });
});

describe("Rete context menu comment placement", () => {
  it("uses the right-click target, not the selection, and snapshots the pointer", () => {
    const selected = new FlowNode("dialogue", 10, {});
    selected.id = "node-10";
    const target = new FlowNode("dialogue", 42, {});
    target.id = "node-42";
    const nodes = [selected, target];
    const pushEvent = vi.fn();
    const hook = {
      editor: { getNodes: () => nodes },
      _flowContext: { commentsEnabled: true, selectedReteIds: new Set([selected.id]) },
      _commentContextPoint: { x: 240, y: 160 },
      area: {
        area: { pointer: { x: 999, y: 999 } },
        nodeViews: new Map([[target.id, { position: { x: 150, y: 90 } }]]),
      },
      readonly: false,
      pushEvent,
      performAutoLayout: vi.fn(),
    };
    const items = createContextMenuItems(hook as never);
    const nodeComment = items(target).list.find((item) => item.key === "add_comment")!;
    hook._commentContextPoint = { x: 999, y: 999 };
    nodeComment.handler();
    expect(pushEvent).toHaveBeenLastCalledWith("comments_place", { node_id: 42, x: 90, y: 70 });
    items("root")
      .list.find((item) => item.key === "add_comment")!
      .handler();
    expect(pushEvent).toHaveBeenLastCalledWith("comments_place", { node_id: null, x: 999, y: 999 });
  });
});
