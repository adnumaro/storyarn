import { mount, type VueWrapper } from "@vue/test-utils";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { nextTick, reactive } from "vue";
import { createMockLive } from "@app/test/setup";
import type { SceneCommentsPanelState, SceneCommentThread } from "@modules/scenes/types/comments";

const live = createMockLive();
vi.mock("@shared/composables/useLive", () => ({ useLive: () => live }));
const { default: SceneCanvasComments } =
  await import("@modules/scenes/editor/components/chrome/SceneCanvasComments.vue");

const author = { id: 4, display_name: "Ada", avatar_url: null };
const thread: SceneCommentThread = {
  id: 12,
  status: "open",
  revision: 3,
  message_count: 1,
  created_at: "2026-09-04T09:00:00Z",
  last_activity_at: "2026-09-04T09:00:00Z",
  resolved_at: null,
  resolved_by: null,
  source: {
    type: "scene_canvas",
    id: 7,
    scene_id: 7,
    label: "Scene canvas",
    status: "available",
  },
  author,
  preview: "Move the encounter here.",
  position: { x: 10, y: 20 },
};
const base: SceneCommentsPanelState = {
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
const projection = {
  percentToPixel: (x: number, y: number) => ({ x: x * 10, y: y * 8 }),
  pixelToPercent: (x: number, y: number) => ({ x: x / 10, y: y / 8 }),
};
let wrappers: VueWrapper[] = [];
const disconnect = vi.fn();

function pointer(
  target: EventTarget,
  type: string,
  x: number,
  y: number,
  button = 0,
  ctrlKey = false,
): MouseEvent {
  const event = new MouseEvent(type, {
    bubbles: true,
    cancelable: true,
    clientX: x,
    clientY: y,
    button,
    ctrlKey,
  });
  Object.defineProperty(event, "pointerId", { value: 1 });
  target.dispatchEvent(event);
  return event;
}

function setup(
  state: Partial<SceneCommentsPanelState> = {},
  commentPins = [thread],
  focusThreadId: number | null = null,
  backgroundSettled = true,
) {
  const container = document.createElement("div");
  const canvas = document.createElement("canvas");
  const elementSurface = document.createElement("div");
  elementSurface.dataset.sceneElement = "pin-42";
  container.append(canvas, elementSurface);
  document.body.append(container);
  vi.spyOn(container, "getBoundingClientRect").mockReturnValue({
    left: 10,
    top: 20,
    width: 1_000,
    height: 800,
    right: 1_010,
    bottom: 820,
    x: 10,
    y: 20,
    toJSON: () => ({}),
  });
  const stage = reactive({ x: 100, y: 50, scaleX: 2, scaleY: 2 });
  const wrapper = mount(SceneCanvasComments, {
    attachTo: container,
    props: {
      container,
      stage,
      projection,
      backgroundSettled,
      state: { ...base, ...state },
      commentPins,
      focusThreadId,
    },
    global: { stubs: { SceneCommentsPanel: true } },
  });
  wrappers.push(wrapper);
  return { wrapper, container, canvas, elementSurface, stage };
}

beforeEach(() => {
  vi.clearAllMocks();
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
  document.body.innerHTML = "";
  vi.unstubAllGlobals();
});

describe("Scene canvas comments", () => {
  it("follows pan and zoom, and opens pins for pointer or keyboard users", async () => {
    const { wrapper, stage } = setup();
    await nextTick();
    const pin = wrapper.get("#scene-comment-pin-12");
    expect(pin.attributes("style")).toContain("left: 300px");
    expect(pin.attributes("style")).toContain("top: 370px");

    stage.x = -50;
    stage.y = 20;
    stage.scaleX = 0.5;
    stage.scaleY = 0.5;
    await nextTick();
    expect(pin.attributes("style")).toContain("left: 0px");
    expect(pin.attributes("style")).toContain("top: 100px");

    await pin.trigger("focus");
    expect(wrapper.get('[role="tooltip"]').text()).toContain("Ada");
    expect(wrapper.get('[role="tooltip"]').text()).toContain("Move the encounter here.");
    await pin.trigger("click");
    expect(live.pushEvent).toHaveBeenLastCalledWith("comments_select_thread", {
      thread_id: 12,
      presentation: "canvas",
    });
  });

  it("intercepts placement over both the bare canvas and an element through the compatible click", async () => {
    const { canvas, elementSurface } = setup({ placing: true });
    await nextTick();
    const canvasPointerDown = vi.fn();
    const canvasPointerUp = vi.fn();
    const canvasClick = vi.fn();
    canvas.addEventListener("pointerdown", canvasPointerDown);
    canvas.addEventListener("pointerup", canvasPointerUp);
    canvas.addEventListener("click", canvasClick);

    pointer(canvas, "pointerdown", 500, 300);
    pointer(canvas, "pointerup", 500, 300);
    pointer(canvas, "click", 500, 300);
    expect(live.pushEvent).toHaveBeenLastCalledWith("comments_place", {
      x: 19.5,
      y: 14.375,
    });
    expect(canvasPointerDown).not.toHaveBeenCalled();
    expect(canvasPointerUp).not.toHaveBeenCalled();
    expect(canvasClick).not.toHaveBeenCalled();

    const elementClick = vi.fn();
    elementSurface.addEventListener("click", elementClick);
    pointer(elementSurface, "pointerdown", 610, 420);
    pointer(elementSurface, "pointerup", 610, 420);
    pointer(elementSurface, "click", 610, 420);
    expect(live.pushEvent).toHaveBeenLastCalledWith("comments_place", {
      x: 25,
      y: 21.875,
    });
    expect(elementClick).not.toHaveBeenCalled();
    expect(live.pushEvent).toHaveBeenCalledTimes(2);
  });

  it("waits for the background before accepting placement or context actions", async () => {
    const { wrapper, canvas } = setup({ placing: true }, [thread], null, false);
    await nextTick();

    pointer(canvas, "pointerdown", 500, 300);
    pointer(canvas, "pointerup", 500, 300);
    pointer(canvas, "click", 500, 300);
    pointer(canvas, "contextmenu", 510, 340, 2);
    await nextTick();
    expect(live.pushEvent).not.toHaveBeenCalled();
    expect(wrapper.find("#scene-comment-context-menu").exists()).toBe(false);

    await wrapper.setProps({ backgroundSettled: true });
    pointer(canvas, "pointerdown", 500, 300);
    pointer(canvas, "pointerup", 500, 300);
    pointer(canvas, "click", 500, 300);
    expect(live.pushEvent).toHaveBeenLastCalledWith("comments_place", {
      x: 19.5,
      y: 14.375,
    });

    pointer(canvas, "contextmenu", 510, 340, 2);
    await nextTick();
    await wrapper.get("#scene-comment-context-add").trigger("click");
    expect(live.pushEvent).toHaveBeenLastCalledWith("comments_place", {
      x: 20,
      y: 16.875,
    });
    expect(live.pushEvent).toHaveBeenCalledTimes(2);
  });

  it("offers a custom context-menu action at a clamped logical position", async () => {
    const { wrapper, canvas } = setup();
    const nativeContextMenu = vi.fn();
    canvas.addEventListener("contextmenu", nativeContextMenu);
    pointer(canvas, "contextmenu", 510, 340, 2);
    await nextTick();
    expect(nativeContextMenu).not.toHaveBeenCalled();
    expect(wrapper.get("#scene-comment-context-menu").attributes("role")).toBe("menu");
    await wrapper.get("#scene-comment-context-add").trigger("click");
    expect(live.pushEvent).toHaveBeenLastCalledWith("comments_place", {
      x: 20,
      y: 16.875,
    });
    expect(wrapper.find("#scene-comment-context-menu").exists()).toBe(false);
  });

  it("blocks the full secondary-button gesture before Konva can start a zone drag", async () => {
    const { wrapper, canvas } = setup();
    const konvaPointerDown = vi.fn();
    const konvaPointerUp = vi.fn();
    const konvaMouseDown = vi.fn();
    const konvaMouseUp = vi.fn();
    const konvaClick = vi.fn();
    const konvaAuxClick = vi.fn();
    canvas.addEventListener("pointerdown", konvaPointerDown);
    canvas.addEventListener("pointerup", konvaPointerUp);
    canvas.addEventListener("mousedown", konvaMouseDown);
    canvas.addEventListener("mouseup", konvaMouseUp);
    canvas.addEventListener("click", konvaClick);
    canvas.addEventListener("auxclick", konvaAuxClick);

    const pointerDown = pointer(canvas, "pointerdown", 510, 340, 2);
    const mouseDown = pointer(canvas, "mousedown", 510, 340, 2);
    pointer(canvas, "pointerup", 510, 340, 2);
    pointer(canvas, "mouseup", 510, 340, 2);
    pointer(canvas, "contextmenu", 510, 340, 2);
    pointer(canvas, "click", 510, 340, 2);
    pointer(canvas, "auxclick", 510, 340, 2);
    await nextTick();

    expect(pointerDown.defaultPrevented).toBe(true);
    expect(mouseDown.defaultPrevented).toBe(true);
    expect(konvaPointerDown).not.toHaveBeenCalled();
    expect(konvaPointerUp).not.toHaveBeenCalled();
    expect(konvaMouseDown).not.toHaveBeenCalled();
    expect(konvaMouseUp).not.toHaveBeenCalled();
    expect(konvaClick).not.toHaveBeenCalled();
    expect(konvaAuxClick).not.toHaveBeenCalled();
    expect(wrapper.find("#scene-comment-context-menu").exists()).toBe(true);

    const ctrlPointerDown = pointer(canvas, "pointerdown", 520, 350, 0, true);
    const ctrlMouseDown = pointer(canvas, "mousedown", 520, 350, 0, true);
    pointer(canvas, "pointerup", 520, 350, 0, true);
    pointer(canvas, "mouseup", 520, 350, 0, true);
    pointer(canvas, "contextmenu", 520, 350, 0, true);
    pointer(canvas, "click", 520, 350, 0, true);
    expect(ctrlPointerDown.defaultPrevented).toBe(true);
    expect(ctrlMouseDown.defaultPrevented).toBe(true);
    expect(konvaMouseDown).not.toHaveBeenCalled();
  });

  it("keeps viewer pins readable without enabling placement, context actions, or movement", async () => {
    const { wrapper, canvas } = setup({ canComment: false, placing: true });
    await nextTick();
    pointer(canvas, "pointerdown", 500, 300);
    pointer(canvas, "contextmenu", 500, 300, 2);
    const pin = wrapper.get("#scene-comment-pin-12");
    pointer(pin.element, "pointerdown", 300, 370);
    pointer(window, "pointermove", 400, 450);
    pointer(window, "pointerup", 400, 450);
    document.dispatchEvent(new KeyboardEvent("keydown", { key: "c", bubbles: true }));
    expect(live.pushEvent).not.toHaveBeenCalled();
    expect(wrapper.find("#scene-comment-context-menu").exists()).toBe(false);

    await pin.trigger("click");
    expect(live.pushEvent).toHaveBeenCalledExactlyOnceWith("comments_select_thread", {
      thread_id: 12,
      presentation: "canvas",
    });
  });

  it("rolls a rejected move back and reports the failure", async () => {
    const { wrapper } = setup();
    await nextTick();
    const pin = wrapper.get("#scene-comment-pin-12");
    pointer(pin.element, "pointerdown", 300, 370);
    pointer(window, "pointermove", 400, 450);
    pointer(window, "pointerup", 400, 450);
    expect(live.pushEvent).toHaveBeenCalledWith(
      "comments_move",
      { thread_id: 12, x: 15, y: 25, expected_revision: 3 },
      expect.any(Function),
      expect.any(Function),
    );
    vi.mocked(live.pushEvent).mock.calls[0][2]!({ ok: false });
    await nextTick();
    expect(pin.attributes("style")).toContain("left: 300px");
    expect(pin.attributes("style")).toContain("top: 370px");
    expect(wrapper.get('[role="alert"]').text()).toContain("Could not update");
  });

  it("blocks pin drag while the background loads and restores it when settled", async () => {
    const { wrapper } = setup({}, [thread], null, false);
    await nextTick();
    const pin = wrapper.get("#scene-comment-pin-12");

    pointer(pin.element, "pointerdown", 300, 370);
    pointer(window, "pointermove", 400, 450);
    pointer(window, "pointerup", 400, 450);
    expect(live.pushEvent).not.toHaveBeenCalled();
    expect(pin.attributes("style")).toContain("left: 300px");
    expect(pin.attributes("style")).toContain("top: 370px");

    await wrapper.setProps({ backgroundSettled: true });
    pointer(pin.element, "pointerdown", 300, 370);
    pointer(window, "pointermove", 400, 450);
    pointer(window, "pointerup", 400, 450);
    expect(live.pushEvent).toHaveBeenLastCalledWith(
      "comments_move",
      { thread_id: 12, x: 15, y: 25, expected_revision: 3 },
      expect.any(Function),
      expect.any(Function),
    );
  });

  it("rolls an active drag back without persisting when the background becomes unsettled", async () => {
    const { wrapper } = setup();
    await nextTick();
    const pin = wrapper.get("#scene-comment-pin-12");

    pointer(pin.element, "pointerdown", 300, 370);
    pointer(window, "pointermove", 400, 450);
    await nextTick();
    expect(pin.attributes("style")).toContain("left: 400px");
    expect(pin.attributes("style")).toContain("top: 450px");

    await wrapper.setProps({ backgroundSettled: false });
    expect(pin.attributes("style")).toContain("left: 300px");
    expect(pin.attributes("style")).toContain("top: 370px");
    pointer(window, "pointerup", 400, 450);
    expect(live.pushEvent).not.toHaveBeenCalled();
  });

  it("releases a boundary no-op after an unchanged success reply", async () => {
    const edge = { ...thread, position: { x: 100, y: 100 } };
    const { wrapper } = setup({}, [edge]);
    await nextTick();
    const pin = wrapper.get("#scene-comment-pin-12");
    pointer(pin.element, "pointerdown", 500, 500);
    pointer(window, "pointermove", 550, 550);
    pointer(window, "pointerup", 550, 550);
    expect(live.pushEvent).toHaveBeenLastCalledWith(
      "comments_move",
      { thread_id: 12, x: 100, y: 100, expected_revision: 3 },
      expect.any(Function),
      expect.any(Function),
    );
    vi.mocked(live.pushEvent).mock.calls[0][2]!({
      ok: true,
      thread: { position: { x: 100, y: 100 }, revision: 3 },
    });

    pointer(pin.element, "pointerdown", 500, 500);
    pointer(window, "pointermove", 400, 420);
    pointer(window, "pointerup", 400, 420);
    expect(live.pushEvent).toHaveBeenLastCalledWith(
      "comments_move",
      { thread_id: 12, x: 95, y: 95, expected_revision: 3 },
      expect.any(Function),
      expect.any(Function),
    );
    expect(live.pushEvent).toHaveBeenCalledTimes(2);
  });

  it("keeps an accepted move visible until the matching server revision arrives", async () => {
    const { wrapper } = setup();
    await nextTick();
    const pin = wrapper.get("#scene-comment-pin-12");
    pointer(pin.element, "pointerdown", 300, 370);
    pointer(window, "pointermove", 400, 450);
    pointer(window, "pointerup", 400, 450);
    vi.mocked(live.pushEvent).mock.calls[0][2]!({
      ok: true,
      thread: { position: { x: 15, y: 25 }, revision: 4 },
    });
    await nextTick();
    expect(pin.attributes("style")).toContain("left: 400px");
    expect(pin.attributes("style")).toContain("top: 450px");

    await wrapper.setProps({
      commentPins: [{ ...thread, revision: 4, position: { x: 15, y: 25 } }],
    });
    expect(pin.attributes("style")).toContain("left: 400px");
    expect(pin.attributes("style")).toContain("top: 450px");
  });

  it("waits for background readiness before centering a deep-linked thread", async () => {
    const { wrapper, stage } = setup({}, [thread], 12, false);
    await nextTick();
    expect(stage).toEqual({ x: 100, y: 50, scaleX: 2, scaleY: 2 });
    await wrapper.setProps({ backgroundSettled: true });
    expect(stage.x).toBe(200);
    expect(stage.y).toBe(80);
  });

  it("honors keyboard controls and removes every global and canvas listener on unmount", async () => {
    const { wrapper, container, canvas } = setup();
    document.dispatchEvent(new KeyboardEvent("keydown", { key: "c", bubbles: true }));
    expect(live.pushEvent).toHaveBeenLastCalledWith("comments_mode", { active: true });
    wrapper.unmount();
    wrappers = [];
    vi.mocked(live.pushEvent).mockClear();
    document.dispatchEvent(new KeyboardEvent("keydown", { key: "c", bubbles: true }));
    pointer(canvas, "pointerdown", 500, 300);
    pointer(window, "pointermove", 600, 400);
    expect(live.pushEvent).not.toHaveBeenCalled();
    expect(container.dataset.commentPlacing).toBeUndefined();
    expect(disconnect).toHaveBeenCalledOnce();
  });
});
