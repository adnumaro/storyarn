import { mount, type VueWrapper } from "@vue/test-utils";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { nextTick } from "vue";
import { createMockLive } from "@app/test/setup";
import type { FlowCommentThread, FlowCommentsPanelState } from "@modules/flows/types/comments";
import {
  commentCanvasPoint,
  commentNodeId,
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
  source: { type: "flow_canvas", id: 7, flow_id: 7, label: "Flow", status: "available" },
  context: {
    type: "flow_node",
    id: "42",
    label: "Dialogue",
    status: "available",
    offset: { x: 10, y: 20 },
  },
  author: { id: 4, display_name: "Ada", avatar_url: null },
  preview: "Why does the guard leave?",
  position: { x: 160, y: 110 },
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

function pointer(
  target: EventTarget,
  type: string,
  x: number,
  y: number,
  button = 0,
  options: MouseEventInit & { pointerId?: number } = {},
) {
  const event = new MouseEvent(type, {
    bubbles: true,
    cancelable: true,
    clientX: x,
    clientY: y,
    button,
    ...options,
  });
  Object.defineProperty(event, "pointerId", { value: options.pointerId ?? 1 });
  target.dispatchEvent(event);
  return event;
}
function key(target: EventTarget, value: string, options: KeyboardEventInit = {}) {
  const event = new KeyboardEvent("keydown", {
    key: value,
    bubbles: true,
    cancelable: true,
    ...options,
  });
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
  function addNode(id: number, position = { x: 150, y: 90 }, size = { width: 100, height: 60 }) {
    const element = document.createElement("div");
    element.dataset.flowCommentNode = String(id);
    element.dataset.flowCommentLabel = id === 42 ? "Dialogue" : `Node ${id}`;
    area.nodeViews.set(`node-${id}`, { position });
    vi.spyOn(element, "getBoundingClientRect").mockImplementation(() => {
      const node = area.nodeViews.get(`node-${id}`)!;
      const { x, y, k } = area.area.transform;
      const left = 10 + x + node.position.x * k;
      const top = 20 + y + node.position.y * k;
      return {
        x: left,
        y: top,
        left,
        top,
        width: size.width * k,
        height: size.height * k,
        right: left + size.width * k,
        bottom: top + size.height * k,
        toJSON: () => ({}),
      };
    });
    container.append(element);
    return element;
  }
  const node = addNode(42);
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
  return { wrapper, area, container, pipes, node, addNode };
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
      context: null,
      position: { x: 300, y: 400 },
    };
    expect(commentCanvasPoint(free, new Map())).toEqual({ x: 300, y: 400 });
    expect(commentCanvasPoint(thread, new Map())).toEqual(thread.position);
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

  it("retains the surface position when node context becomes unavailable", () => {
    const detached = {
      ...thread,
      context: { ...thread.context!, status: "unavailable" as const },
    };
    const nodes = new Map([["node-42", { position: { x: 500, y: 600 } }]]);
    expect(commentCanvasPoint(detached, nodes)).toEqual(thread.position);
    expect(commentNodeId(detached)).toBeNull();
    expect(commentNodeId(thread)).toBe(42);
    expect(commentCanvasPoint(thread, nodes)).toEqual({ x: 510, y: 620 });
  });

  it("keeps legacy offsets readable while suppressing ambiguous unavailable anchors", () => {
    const legacy = {
      ...thread,
      source: { ...thread.source, type: "flow_node" as const, id: 42 },
      context: null,
      position: { x: 10, y: 20 },
    };
    const nodes = new Map([["node-42", { position: { x: 150, y: 90 } }]]);
    expect(commentCanvasPoint(legacy, nodes)).toEqual({ x: 160, y: 110 });
    expect(commentCanvasPoint(legacy, new Map())).toBeNull();
    expect(
      commentCanvasPoint(
        {
          ...legacy,
          source: { ...legacy.source, status: "unavailable" },
        },
        nodes,
      ),
    ).toBeNull();
  });

  it("places at the actual click with zoom conversion before any graph selection or drag", async () => {
    const { container, node } = setup({ placing: true });
    const graphPointerDown = vi.fn();
    const graphPointerUp = vi.fn();
    container.addEventListener("pointerdown", graphPointerDown);
    container.addEventListener("pointerup", graphPointerUp);
    pointer(node, "pointerdown", 500, 300);
    pointer(node, "pointerup", 500, 300);
    expect(live.pushEvent).toHaveBeenCalledWith("comments_place", {
      node_id: null,
      x: 195,
      y: 115,
      context: { type: "flow_node", id: "42", offset: { x: 45, y: 25 } },
    });
    expect(graphPointerDown).not.toHaveBeenCalled();
    expect(graphPointerUp).not.toHaveBeenCalled();
    pointer(container, "pointerdown", 600, 400);
    expect(live.pushEvent).toHaveBeenLastCalledWith("comments_place", {
      node_id: null,
      x: 245,
      y: 165,
      context: null,
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
      {
        thread_id: 12,
        x: 180,
        y: 120,
        expected_revision: 3,
        context: { type: "flow_node", id: "42", offset: { x: 30, y: 30 } },
      },
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

  it("starts a contextual drag at the node's current position and preserves the offset", async () => {
    const { wrapper, area, pipes } = setup();
    area.nodeViews.get("node-42")!.position = { x: 250, y: 190 };
    pipes[0]({ type: "nodetranslated" });
    await flushFrames();
    pointer(wrapper.get("#flow-comment-pin-12").element, "pointerdown", 200, 200);
    pointer(window, "pointermove", 240, 220);
    await nextTick();
    expect(wrapper.get("#flow-comment-pin-12").attributes("style")).toContain("left: 660px");
    pointer(window, "pointerup", 240, 220);
    expect(live.pushEvent).toHaveBeenCalledWith(
      "comments_move",
      {
        thread_id: 12,
        x: 280,
        y: 220,
        expected_revision: 3,
        context: { type: "flow_node", id: "42", offset: { x: 30, y: 30 } },
      },
      expect.any(Function),
      expect.any(Function),
    );
  });

  it("recomputes the preview after zoom changes mid-gesture and commits current canvas coordinates", async () => {
    const { wrapper, area, pipes } = setup();
    await nextTick();
    const pin = wrapper.get("#flow-comment-pin-12");
    pointer(pin.element, "pointerdown", 430, 290);
    pointer(window, "pointermove", 450, 300);
    await nextTick();
    expect(pin.attributes("style")).toContain("left: 440px");
    area.area.transform = { x: 20, y: 30, k: 0.5 };
    pipes[0]({ type: "zoomed" });
    await flushFrames();
    expect(pin.attributes("style")).toContain("left: 440px");
    expect(wrapper.get("#flow-comment-snap-preview").text()).toContain("Free");
    pointer(window, "pointermove", 130, 110);
    await nextTick();
    expect(pin.attributes("style")).toContain("left: 120px");
    expect(wrapper.get("#flow-comment-snap-preview").text()).toContain("Dialogue");
    expect(live.pushEvent).not.toHaveBeenCalled();
    pointer(window, "pointerup", 130, 110);
    expect(live.pushEvent).toHaveBeenCalledExactlyOnceWith(
      "comments_move",
      {
        thread_id: 12,
        x: 200,
        y: 120,
        expected_revision: 3,
        context: { type: "flow_node", id: "42", offset: { x: 50, y: 30 } },
      },
      expect.any(Function),
      expect.any(Function),
    );
  });

  it("uses the release coordinates and modifier even when they differ from the last pointer move", async () => {
    const { wrapper } = setup();
    await nextTick();
    pointer(wrapper.get("#flow-comment-pin-12").element, "pointerdown", 430, 290);
    pointer(window, "pointermove", 450, 300);
    pointer(window, "pointerup", 470, 310, 0, { altKey: true });
    expect(live.pushEvent).toHaveBeenCalledExactlyOnceWith(
      "comments_move",
      { thread_id: 12, x: 180, y: 120, context: null, expected_revision: 3 },
      expect.any(Function),
      expect.any(Function),
    );
  });

  it("handles a release that crosses the drag threshold before any pointermove", async () => {
    const { wrapper } = setup();
    await nextTick();
    pointer(wrapper.get("#flow-comment-pin-12").element, "pointerdown", 430, 290);
    pointer(window, "pointerup", 470, 310);
    expect(live.pushEvent).toHaveBeenCalledExactlyOnceWith(
      "comments_move",
      {
        thread_id: 12,
        x: 180,
        y: 120,
        context: { type: "flow_node", id: "42", offset: { x: 30, y: 30 } },
        expected_revision: 3,
      },
      expect.any(Function),
      expect.any(Function),
    );
  });

  it.each(["Escape", "pointercancel", "lostpointercapture", "blur"])(
    "rolls back both the pin and context preview without writes on %s",
    async (cancel) => {
      const { wrapper } = setup();
      await nextTick();
      const pin = wrapper.get("#flow-comment-pin-12");
      pointer(pin.element, "pointerdown", 430, 290);
      pointer(window, "pointermove", 700, 500);
      await nextTick();
      expect(pin.attributes("style")).toContain("left: 690px");
      expect(wrapper.get("#flow-comment-snap-preview").text()).toContain("Free");
      if (cancel === "Escape") key(pin.element, "Escape");
      else if (cancel === "blur") window.dispatchEvent(new Event("blur"));
      else pointer(cancel === "lostpointercapture" ? pin.element : window, cancel, 700, 500);
      await nextTick();
      expect(pin.attributes("style")).toContain("left: 420px");
      expect(wrapper.find("#flow-comment-snap-preview").exists()).toBe(false);
      pointer(window, "pointerup", 700, 500);
      expect(live.pushEvent).not.toHaveBeenCalled();
    },
  );

  it("ignores another pointer during a drag and keeps its own preview", async () => {
    const { wrapper } = setup();
    await nextTick();
    const pin = wrapper.get("#flow-comment-pin-12");
    pointer(pin.element, "pointerdown", 430, 290);
    pointer(window, "pointermove", 470, 310);
    pointer(window, "pointermove", 900, 700, 0, { pointerId: 2 });
    pointer(window, "pointerup", 900, 700, 0, { pointerId: 2 });
    await nextTick();
    expect(pin.attributes("style")).toContain("left: 460px");
    expect(live.pushEvent).not.toHaveBeenCalled();
    key(pin.element, "Escape");
  });

  it("moves with arrow keys in screen pixels and commits position and context together on Enter", async () => {
    const { wrapper } = setup();
    await nextTick();
    const pin = wrapper.get("#flow-comment-pin-12");
    key(pin.element, "ArrowRight");
    key(pin.element, "ArrowDown", { shiftKey: true });
    await nextTick();
    expect(pin.attributes("style")).toContain("left: 430px");
    expect(pin.attributes("style")).toContain("top: 271px");
    expect(live.pushEvent).not.toHaveBeenCalled();
    key(pin.element, "Enter");
    expect(live.pushEvent).toHaveBeenCalledExactlyOnceWith(
      "comments_move",
      {
        thread_id: 12,
        x: 165,
        y: 110.5,
        context: { type: "flow_node", id: "42", offset: { x: 15, y: 20.5 } },
        expected_revision: 3,
      },
      expect.any(Function),
      expect.any(Function),
    );
  });

  it("supports keyboard cancellation and explicit free positioning with magnetism disabled", async () => {
    const { wrapper } = setup();
    await nextTick();
    const pin = wrapper.get("#flow-comment-pin-12");
    key(pin.element, "ArrowRight");
    key(pin.element, "Escape");
    await nextTick();
    expect(pin.attributes("style")).toContain("left: 420px");
    expect(live.pushEvent).not.toHaveBeenCalled();
    await wrapper.get("#flow-comment-magnetism-toggle").trigger("click");
    expect(wrapper.get("#flow-comment-magnetism-toggle").attributes("aria-pressed")).toBe("false");
    key(pin.element, "ArrowRight");
    key(pin.element, "Enter");
    expect(live.pushEvent).toHaveBeenCalledExactlyOnceWith(
      "comments_move",
      { thread_id: 12, x: 165, y: 110, context: null, expected_revision: 3 },
      expect.any(Function),
      expect.any(Function),
    );
  });

  it("cycles overlapping contexts by keyboard before committing the chosen target", async () => {
    const free = { ...thread, context: null };
    const { wrapper, addNode } = setup({}, [free]);
    addNode(43, { x: 140, y: 80 }, { width: 200, height: 120 });
    await nextTick();
    const pin = wrapper.get("#flow-comment-pin-12");
    key(pin.element, "ArrowRight");
    await nextTick();
    expect(wrapper.get("#flow-comment-snap-preview").text()).toContain("Dialogue");
    key(pin.element, "]");
    await nextTick();
    expect(wrapper.get("#flow-comment-snap-preview").text()).toContain("Node 43");
    expect(live.pushEvent).not.toHaveBeenCalled();
    key(pin.element, "Enter");
    expect(live.pushEvent).toHaveBeenCalledExactlyOnceWith(
      "comments_move",
      {
        thread_id: 12,
        x: 165,
        y: 110,
        context: { type: "flow_node", id: "43", offset: { x: 25, y: 30 } },
        expected_revision: 3,
      },
      expect.any(Function),
      expect.any(Function),
    );
  });

  it("does not let an old failed request roll back a newer pending move", async () => {
    const { wrapper } = setup();
    await nextTick();
    const pin = wrapper.get("#flow-comment-pin-12");
    pointer(pin.element, "pointerdown", 430, 290);
    pointer(window, "pointerup", 470, 310);
    const firstFailure = vi.mocked(live.pushEvent).mock.calls[0][3]!;
    const updated = {
      ...thread,
      revision: 4,
      position: { x: 180, y: 120 },
      context: { ...thread.context!, offset: { x: 30, y: 30 } },
    };
    await wrapper.setProps({ commentPins: [updated] });
    pointer(pin.element, "pointerdown", 470, 310);
    pointer(window, "pointerup", 490, 330);
    await nextTick();
    expect(pin.attributes("aria-busy")).toBe("true");
    firstFailure(new Error("Late disconnect for the first request"));
    await nextTick();
    expect(pin.attributes("style")).toContain("left: 480px");
    expect(pin.attributes("aria-busy")).toBe("true");
    expect(wrapper.find('[role="alert"]').exists()).toBe(false);
    expect(live.pushEvent).toHaveBeenCalledTimes(2);
    expect(vi.mocked(live.pushEvent).mock.calls[1][1]).toMatchObject({ expected_revision: 4 });
  });

  it("keeps an acknowledged move pending until authoritative props confirm the revision", async () => {
    const { wrapper } = setup();
    await nextTick();
    const pin = wrapper.get("#flow-comment-pin-12");
    pointer(pin.element, "pointerdown", 430, 290);
    pointer(window, "pointerup", 470, 310);
    vi.mocked(live.pushEvent).mock.calls[0][2]!({ ok: true });
    await nextTick();
    expect(pin.attributes("style")).toContain("left: 460px");
    expect(pin.attributes("aria-busy")).toBe("true");
    pointer(pin.element, "pointerdown", 470, 310);
    pointer(window, "pointerup", 490, 330);
    expect(live.pushEvent).toHaveBeenCalledTimes(1);

    const confirmed = {
      ...thread,
      revision: 4,
      position: { x: 180, y: 120 },
      context: { ...thread.context!, offset: { x: 30, y: 30 } },
    };
    await wrapper.setProps({ commentPins: [confirmed] });
    expect(pin.attributes("style")).toContain("left: 460px");
    expect(pin.attributes("aria-busy")).toBe("false");
  });

  it("confirms a selected resolved thread move from its detail props even without a list pin", async () => {
    const resolved = { ...thread, status: "resolved" as const };
    const initialState = { ...base, open: true, presentation: "canvas" as const, thread: resolved };
    const { wrapper } = setup(initialState, []);
    await nextTick();
    const pin = wrapper.get("#flow-comment-pin-12");
    pointer(pin.element, "pointerdown", 430, 290);
    pointer(window, "pointerup", 470, 310);
    vi.mocked(live.pushEvent).mock.calls[0][2]!({ ok: true });
    await nextTick();
    expect(pin.attributes("style")).toContain("left: 460px");
    expect(pin.attributes("aria-busy")).toBe("true");

    await wrapper.setProps({
      state: {
        ...initialState,
        thread: {
          ...resolved,
          revision: 4,
          position: { x: 180, y: 120 },
          context: { ...thread.context!, offset: { x: 30, y: 30 } },
        },
      },
    });
    expect(pin.attributes("style")).toContain("left: 460px");
    expect(pin.attributes("aria-busy")).toBe("false");
  });

  it("rechecks deleted targets at release and preserves the final pin position while detaching", async () => {
    const { wrapper, area, node } = setup();
    await nextTick();
    pointer(wrapper.get("#flow-comment-pin-12").element, "pointerdown", 430, 290);
    pointer(window, "pointermove", 470, 310);
    node.remove();
    area.nodeViews.delete("node-42");
    pointer(window, "pointerup", 470, 310);
    expect(live.pushEvent).toHaveBeenCalledExactlyOnceWith(
      "comments_move",
      { thread_id: 12, x: 180, y: 120, context: null, expected_revision: 3 },
      expect.any(Function),
      expect.any(Function),
    );
  });

  it("moves a draft with an explicit preserve-draft signal", async () => {
    const { wrapper } = setup({
      open: true,
      presentation: "canvas",
      draftPosition: { x: 20, y: 30 },
      draftId: "draft-one",
    });
    await nextTick();
    pointer(wrapper.get("#flow-comment-draft-pin").element, "pointerdown", 200, 200);
    pointer(window, "pointermove", 220, 220);
    pointer(window, "pointerup", 220, 220);
    expect(live.pushEvent).toHaveBeenCalledWith(
      "comments_place",
      { node_id: null, x: 30, y: 40, context: null, moving_draft: true, draft_id: "draft-one" },
      expect.any(Function),
      expect.any(Function),
    );
    vi.mocked(live.pushEvent).mock.calls[0][3]!(new Error("Disconnected"));
    await nextTick();
    expect(wrapper.get("#flow-comment-draft-pin").attributes("style")).toContain("left: 140px");
  });

  it("follows a moved draft context and sends its resolved position to the embedded composer", async () => {
    const context = { type: "flow_node", id: "42", offset: { x: 10, y: 20 } };
    const { wrapper, area, pipes } = setup({
      open: true,
      presentation: "canvas",
      draftId: "contextual-draft",
      draftPosition: { x: 160, y: 110 },
      draftContext: context,
      selectedNodeId: null,
    });
    await nextTick();
    area.nodeViews.get("node-42")!.position = { x: 250, y: 190 };
    pipes[0]({ type: "nodetranslated" });
    await flushFrames();

    const pin = wrapper.get("#flow-comment-draft-pin");
    expect(pin.attributes("style")).toContain("left: 620px");
    expect(pin.attributes("style")).toContain("top: 470px");
    expect(wrapper.getComponent({ name: "FlowCommentsPanel" }).props("state")).toMatchObject({
      draftPosition: { x: 260, y: 210 },
      draftContext: context,
      selectedNodeId: null,
      draftPending: false,
    });
    expect(live.pushEvent).not.toHaveBeenCalled();
  });

  it("keeps draft creation pending through preview and placement acknowledgement", async () => {
    const { wrapper } = setup({
      open: true,
      presentation: "canvas",
      draftPosition: { x: 20, y: 30 },
      draftContext: null,
      draftId: "draft-pending",
    });
    await nextTick();
    const pin = wrapper.get("#flow-comment-draft-pin");
    const panel = wrapper.getComponent({ name: "FlowCommentsPanel" });
    pointer(pin.element, "pointerdown", 150, 130);
    pointer(window, "pointermove", 470, 310);
    await nextTick();
    expect(panel.props("state")).toMatchObject({
      draftPending: true,
      draftPosition: { x: 180, y: 120 },
      draftContext: { type: "flow_node", id: "42", offset: { x: 30, y: 30 } },
      selectedNodeId: null,
      draftId: "draft-pending",
    });
    expect(live.pushEvent).not.toHaveBeenCalled();
    pointer(window, "pointerup", 470, 310);
    await nextTick();
    expect(panel.props("state").draftPending).toBe(true);
    expect(pin.attributes("aria-busy")).toBe("true");
    vi.mocked(live.pushEvent).mock.calls[0][2]!({ ok: false });
    await nextTick();
    expect(panel.props("state")).toMatchObject({
      draftPending: false,
      draftPosition: { x: 20, y: 30 },
      draftContext: null,
      draftId: "draft-pending",
    });
  });

  it("keeps an acknowledged draft move blocked until position and context props both match", async () => {
    const initialState = {
      ...base,
      open: true,
      presentation: "canvas" as const,
      draftPosition: { x: 20, y: 30 },
      draftContext: null,
      draftId: "draft-ack",
    };
    const { wrapper } = setup(initialState);
    await nextTick();
    const pin = wrapper.get("#flow-comment-draft-pin");
    const panel = wrapper.getComponent({ name: "FlowCommentsPanel" });
    pointer(pin.element, "pointerdown", 150, 130);
    pointer(window, "pointerup", 470, 310);
    const reply = vi.mocked(live.pushEvent).mock.calls[0][2]!;
    const failure = vi.mocked(live.pushEvent).mock.calls[0][3]!;
    reply({ ok: true });
    await nextTick();
    expect(panel.props("state")).toMatchObject({
      draftPending: true,
      draftPosition: { x: 180, y: 120 },
      draftContext: { type: "flow_node", id: "42", offset: { x: 30, y: 30 } },
    });
    expect(pin.attributes("aria-busy")).toBe("true");

    const positionConfirmed = { ...initialState, draftPosition: { x: 180, y: 120 } };
    await wrapper.setProps({ state: positionConfirmed });
    expect(panel.props("state").draftPending).toBe(true);
    await wrapper.setProps({
      state: {
        ...positionConfirmed,
        draftContext: { type: "flow_node", id: "42", offset: { x: 30, y: 30 } },
      },
    });
    expect(panel.props("state").draftPending).toBe(false);
    expect(pin.attributes("style")).toContain("left: 460px");
    expect(pin.attributes("aria-busy")).toBe("false");
    failure(new Error("Stale error after authoritative confirmation"));
    await nextTick();
    expect(wrapper.find('[role="alert"]').exists()).toBe(false);
  });

  it("can explicitly reattach unavailable context to a valid visible target", async () => {
    const unavailable = {
      ...thread,
      context: { ...thread.context!, status: "unavailable" as const },
    };
    const { wrapper } = setup({}, [unavailable]);
    await nextTick();
    pointer(wrapper.get("#flow-comment-pin-12").element, "pointerdown", 430, 290);
    pointer(window, "pointerup", 470, 310);
    expect(vi.mocked(live.pushEvent).mock.calls[0][1]).toMatchObject({
      x: 180,
      y: 120,
      context: { type: "flow_node", id: "42", offset: { x: 30, y: 30 } },
    });
  });

  it("explicitly clears unavailable context when no visible target remains", async () => {
    const unavailable = {
      ...thread,
      context: { ...thread.context!, status: "unavailable" as const },
    };
    const { wrapper, node } = setup({}, [unavailable]);
    node.remove();
    await nextTick();
    pointer(wrapper.get("#flow-comment-pin-12").element, "pointerdown", 200, 200);
    pointer(window, "pointermove", 240, 220);
    pointer(window, "pointerup", 240, 220);
    expect(live.pushEvent).toHaveBeenCalledWith(
      "comments_move",
      { thread_id: 12, x: 180, y: 120, context: null, expected_revision: 3 },
      expect.any(Function),
      expect.any(Function),
    );
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
      context: null,
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
