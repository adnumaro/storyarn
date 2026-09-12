import { mount, type VueWrapper } from "@vue/test-utils";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { nextTick, reactive } from "vue";
import { createMockLive } from "@app/test/setup";
import { readCommentDraft, updateCommentDraft } from "@components/comments/commentDraftStorage";
import type { SceneCommentTargets } from "@modules/scenes/editor/lib/comment-snap-adapter";
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
const targets: SceneCommentTargets = {
  pins: [{ id: 42, x: 200, y: 160, radius: 12, label: "Northern gate", layerId: null, opacity: 1 }],
  zones: [],
  connections: [],
  annotations: [],
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
  altKey = false,
): MouseEvent {
  const event = new MouseEvent(type, {
    bubbles: true,
    cancelable: true,
    clientX: x,
    clientY: y,
    button,
    ctrlKey,
    altKey,
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
  targets: SceneCommentTargets = { pins: [], zones: [], connections: [], annotations: [] },
) {
  const container = document.createElement("div");
  const canvas = document.createElement("canvas");
  const elementSurface = document.createElement("div");
  elementSurface.dataset.sceneElement = "pin-42";
  const nonCanvasUi = document.createElement("div");
  container.append(canvas, elementSurface, nonCanvasUi);
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
      targets,
    },
    global: { stubs: { SceneCommentsPanel: true } },
  });
  wrappers.push(wrapper);
  return { wrapper, container, canvas, elementSurface, nonCanvasUi, stage };
}

beforeEach(() => {
  vi.clearAllMocks();
  sessionStorage.clear();
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
      context: null,
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
      context: null,
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
      context: null,
    });

    pointer(canvas, "contextmenu", 510, 340, 2);
    await nextTick();
    await wrapper.get("#scene-comment-context-add").trigger("click");
    expect(live.pushEvent).toHaveBeenLastCalledWith("comments_place", {
      x: 20,
      y: 16.875,
      context: null,
    });
    expect(live.pushEvent).toHaveBeenCalledTimes(2);
  });

  it("ignores non-canvas UI and offers a context action on the canvas", async () => {
    const { wrapper, canvas, nonCanvasUi } = setup();
    const nativeUiContextMenu = vi.fn();
    nonCanvasUi.addEventListener("contextmenu", nativeUiContextMenu);
    const uiEvent = pointer(nonCanvasUi, "contextmenu", 510, 340, 2);
    await nextTick();
    expect(uiEvent.defaultPrevented).toBe(false);
    expect(nativeUiContextMenu).toHaveBeenCalledOnce();
    expect(wrapper.find("#scene-comment-context-menu").exists()).toBe(false);

    const nativeContextMenu = vi.fn();
    canvas.addEventListener("contextmenu", nativeContextMenu);
    const canvasEvent = pointer(canvas, "contextmenu", 510, 340, 2);
    await nextTick();
    expect(canvasEvent.defaultPrevented).toBe(true);
    expect(nativeContextMenu).not.toHaveBeenCalled();
    expect(wrapper.get("#scene-comment-context-menu").attributes("role")).toBe("menu");
    await wrapper.get("#scene-comment-context-add").trigger("click");
    expect(live.pushEvent).toHaveBeenLastCalledWith("comments_place", {
      x: 20,
      y: 16.875,
      context: null,
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
      { thread_id: 12, x: 15, y: 25, expected_revision: 3, context: null },
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
      { thread_id: 12, x: 15, y: 25, expected_revision: 3, context: null },
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
      { thread_id: 12, x: 100, y: 100, expected_revision: 3, context: null },
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
      { thread_id: 12, x: 95, y: 95, expected_revision: 3, context: null },
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

  it("previews a magnetic target without persisting until the gesture is released", async () => {
    const { wrapper } = setup({}, [thread], null, true, targets);
    await nextTick();
    const pin = wrapper.get("#scene-comment-pin-12");
    pointer(pin.element, "pointerdown", 310, 390);
    pointer(window, "pointermove", 510, 390);
    await nextTick();

    expect(wrapper.get("#scene-comment-snap-preview").text()).toContain("Northern gate");
    expect(live.pushEvent).not.toHaveBeenCalled();
    pointer(window, "pointerup", 510, 390);
    expect(live.pushEvent).toHaveBeenCalledExactlyOnceWith(
      "comments_move",
      expect.objectContaining({
        thread_id: thread.id,
        expected_revision: thread.revision,
        context: expect.objectContaining({ type: "scene_pin", id: "42" }),
      }),
      expect.any(Function),
      expect.any(Function),
    );
    await nextTick();
    expect(pin.attributes("aria-busy")).toBe("true");
    expect(wrapper.find("#scene-comment-snap-preview").exists()).toBe(false);
  });

  it("supports temporary free placement with Alt and cancels without leaving a hover tooltip", async () => {
    const { wrapper } = setup({}, [thread], null, true, targets);
    await nextTick();
    const pin = wrapper.get("#scene-comment-pin-12");
    pointer(pin.element, "pointerdown", 310, 390);
    pointer(window, "pointermove", 510, 390);
    await nextTick();
    expect(wrapper.get("#scene-comment-snap-preview").text()).toContain("Northern gate");

    document.dispatchEvent(new KeyboardEvent("keydown", { key: "Alt", bubbles: true }));
    await nextTick();
    expect(wrapper.get("#scene-comment-snap-preview").text()).toContain("Free position");
    document.dispatchEvent(
      new KeyboardEvent("keydown", { key: "PageDown", altKey: true, bubbles: true }),
    );
    await nextTick();
    expect(wrapper.get("#scene-comment-snap-preview").text()).toContain("Free position");
    document.dispatchEvent(new KeyboardEvent("keydown", { key: "Escape", bubbles: true }));
    pointer(window, "pointerup", 510, 390);
    await nextTick();
    expect(live.pushEvent).not.toHaveBeenCalled();
    expect(pin.attributes("style")).toContain("left: 300px");
    expect(wrapper.find("#scene-comment-preview").exists()).toBe(false);

    pointer(pin.element, "pointerdown", 310, 390, 0, false, true);
    pointer(window, "pointermove", 510, 390, 0, false, true);
    pointer(window, "pointerup", 510, 390, 0, false, true);
    expect(live.pushEvent).toHaveBeenCalledWith(
      "comments_move",
      expect.objectContaining({ context: null }),
      expect.any(Function),
      expect.any(Function),
    );
  });

  it.each(["]", "PageDown"])(
    "cycles overlapping contexts by keyboard and persists the chosen one on Enter using %s",
    async (cycleKey) => {
      const overlap: SceneCommentTargets = {
        ...targets,
        annotations: [
          { id: 80, x: 180, y: 150, width: 40, height: 30, text: "Lighting note", layerId: null },
        ],
      };
      const nearby = { ...thread, position: { x: 20, y: 20 } };
      const { wrapper } = setup({}, [nearby], null, true, overlap);
      await nextTick();
      const pin = wrapper.get("#scene-comment-pin-12");
      await pin.trigger("keydown", { key: "ArrowRight" });
      const first = wrapper.get("#scene-comment-snap-preview").text();
      const cycleButton = wrapper.get("#scene-comment-snap-preview button");
      await cycleButton.trigger("click");
      expect(wrapper.get("#scene-comment-snap-preview").text()).not.toBe(first);
      await pin.trigger("keydown", { key: "PageUp" });
      expect(wrapper.get("#scene-comment-snap-preview").text()).toBe(first);
      await pin.trigger("keydown", { key: cycleKey });
      const second = wrapper.get("#scene-comment-snap-preview").text();
      expect(second).not.toBe(first);
      expect([first, second].some((text) => text.includes("Northern gate"))).toBe(true);
      expect([first, second].some((text) => text.includes("Lighting note"))).toBe(true);
      expect(live.pushEvent).not.toHaveBeenCalled();
      await pin.trigger("keydown", { key: "Enter" });
      expect(live.pushEvent).toHaveBeenCalledWith(
        "comments_move",
        expect.objectContaining({
          context: expect.objectContaining({ id: second.includes("Lighting note") ? "80" : "42" }),
        }),
        expect.any(Function),
        expect.any(Function),
      );
    },
  );

  it("cycles both ways during pointer capture without intercepting focus or text editing", async () => {
    const overlap: SceneCommentTargets = {
      ...targets,
      annotations: [
        { id: 80, x: 180, y: 150, width: 40, height: 30, text: "Lighting note", layerId: null },
      ],
    };
    const nearby = { ...thread, position: { x: 20, y: 20 } };
    const { wrapper, container } = setup({}, [nearby], null, true, overlap);
    await nextTick();
    const pin = wrapper.get("#scene-comment-pin-12");
    const capture = vi.fn();
    Object.defineProperty(pin.element, "setPointerCapture", { value: capture, configurable: true });
    pointer(pin.element, "pointerdown", 510, 390);
    pointer(window, "pointermove", 520, 390);
    await nextTick();
    expect(capture).toHaveBeenCalled();
    const first = wrapper.get("#scene-comment-snap-preview").text();
    expect(wrapper.find("#scene-comment-snap-preview button").exists()).toBe(false);
    expect(first).toContain("Page Up/Page Down");

    const input = document.createElement("textarea");
    container.append(input);
    const editing = new KeyboardEvent("keydown", {
      key: "PageDown",
      bubbles: true,
      cancelable: true,
    });
    input.dispatchEvent(editing);
    const tab = new KeyboardEvent("keydown", { key: "Tab", bubbles: true, cancelable: true });
    pin.element.dispatchEvent(tab);
    await nextTick();
    expect(editing.defaultPrevented).toBe(false);
    expect(tab.defaultPrevented).toBe(false);
    expect(wrapper.get("#scene-comment-snap-preview").text()).toBe(first);

    await pin.trigger("keydown", { key: "PageDown" });
    const second = wrapper.get("#scene-comment-snap-preview").text();
    expect(second).not.toBe(first);
    await pin.trigger("keydown", { key: "PageUp" });
    expect(wrapper.get("#scene-comment-snap-preview").text()).toBe(first);
    await pin.trigger("keydown", { key: "PageDown" });
    expect(live.pushEvent).not.toHaveBeenCalled();
    pointer(window, "pointerup", 520, 390);
    expect(live.pushEvent).toHaveBeenCalledWith(
      "comments_move",
      expect.objectContaining({
        context: expect.objectContaining({ id: second.includes("Lighting note") ? "80" : "42" }),
      }),
      expect.any(Function),
      expect.any(Function),
    );
  });

  it("ignores an older failure after a newer revision has started another move", async () => {
    const { wrapper } = setup();
    await nextTick();
    const pin = wrapper.get("#scene-comment-pin-12");
    pointer(pin.element, "pointerdown", 300, 370);
    pointer(window, "pointermove", 400, 450);
    pointer(window, "pointerup", 400, 450);
    const oldReply = vi.mocked(live.pushEvent).mock.calls[0][2]!;
    await wrapper.setProps({
      commentPins: [{ ...thread, revision: 4, position: { x: 15, y: 25 } }],
    });

    pointer(pin.element, "pointerdown", 400, 450);
    pointer(window, "pointermove", 440, 470);
    pointer(window, "pointerup", 440, 470);
    oldReply({ ok: false });
    await nextTick();
    expect(pin.attributes("aria-busy")).toBe("true");
    expect(pin.attributes("style")).toContain("left: 440px");
    expect(wrapper.find('[role="alert"]').exists()).toBe(false);
    expect(live.pushEvent).toHaveBeenCalledTimes(2);
  });

  it("keeps a draft pending until the server confirms its position and its selected context", async () => {
    const draft = {
      ...base,
      open: true,
      presentation: "canvas" as const,
      draftId: "draft-a",
      draftPosition: { x: 10, y: 20 },
    };
    const { wrapper } = setup(draft, [], null, true, targets);
    await nextTick();
    const pin = wrapper.get("#scene-comment-draft-pin");
    pointer(pin.element, "pointerdown", 310, 390);
    pointer(window, "pointermove", 510, 390);
    pointer(window, "pointerup", 510, 390);
    const [, payload, onReply] = vi.mocked(live.pushEvent).mock.calls[0];
    expect(payload).toMatchObject({
      moving_draft: true,
      draft_id: "draft-a",
      context: { id: "42" },
    });
    onReply!({ ok: true });
    await wrapper.setProps({
      state: { ...draft, draftPosition: { x: payload!.x as number, y: payload!.y as number } },
    });
    expect(pin.attributes("aria-busy")).toBe("true");
    await wrapper.setProps({
      state: {
        ...draft,
        draftPosition: { x: payload!.x as number, y: payload!.y as number },
        draftContext: payload!.context as SceneCommentsPanelState["draftContext"],
      },
    });
    expect(pin.attributes("aria-busy")).toBe("false");
  });

  it("does not apply a pending draft failure to a replacement draft", async () => {
    const draft = {
      ...base,
      open: true,
      presentation: "canvas" as const,
      draftId: "draft-a",
      draftPosition: { x: 10, y: 20 },
    };
    const { wrapper } = setup(draft, []);
    await nextTick();
    const pin = wrapper.get("#scene-comment-draft-pin");
    pointer(pin.element, "pointerdown", 300, 370);
    pointer(window, "pointermove", 400, 450);
    pointer(window, "pointerup", 400, 450);
    const oldReply = vi.mocked(live.pushEvent).mock.calls[0][2]!;
    await wrapper.setProps({
      state: { ...draft, draftId: "draft-b", draftPosition: { x: 5, y: 5 } },
    });
    oldReply({ ok: false });
    await nextTick();
    expect(pin.attributes("aria-busy")).toBe("false");
    expect(pin.attributes("style")).toContain("left: 200px");
    expect(wrapper.find('[role="alert"]').exists()).toBe(false);
  });

  it("accepts authoritative draft detachment when its target disappears during the move request", async () => {
    const draft = {
      ...base,
      open: true,
      presentation: "canvas" as const,
      draftId: "draft-a",
      draftPosition: { x: 10, y: 20 },
    };
    const { wrapper } = setup(draft, [], null, true, targets);
    await nextTick();
    const pin = wrapper.get("#scene-comment-draft-pin");
    pointer(pin.element, "pointerdown", 310, 390);
    pointer(window, "pointermove", 510, 390);
    pointer(window, "pointerup", 510, 390);
    const [, payload, onReply] = vi.mocked(live.pushEvent).mock.calls[0];
    const position = { x: payload!.x as number, y: payload!.y as number };
    expect(payload).toMatchObject({ context: { id: "42" } });
    onReply!({ ok: true, draft: { id: "draft-a", position, context: null } });
    await nextTick();
    expect(pin.attributes("aria-busy")).toBe("true");
    await wrapper.setProps({ state: { ...draft, draftPosition: position, draftContext: null } });
    expect(pin.attributes("aria-busy")).toBe("false");
    expect(wrapper.findComponent({ name: "SceneCommentsPanel" }).props("state").draftPending).toBe(
      false,
    );
  });

  it("keeps the latest visible draft position when a moved context is removed", async () => {
    const draft = {
      ...base,
      open: true,
      presentation: "canvas" as const,
      draftId: "draft-a",
      draftPosition: { x: 22, y: 23 },
      draftContext: { type: "scene_pin", id: "42", offset: { x: 2, y: 3 } },
    };
    const { wrapper } = setup(draft, [], null, true, targets);
    await nextTick();
    await wrapper.setProps({
      targets: { ...targets, pins: [{ ...targets.pins[0], x: 300, y: 240 }] },
    });
    const pin = wrapper.get("#scene-comment-draft-pin");
    expect(pin.attributes("style")).toContain("left: 740px");
    expect(pin.attributes("style")).toContain("top: 578px");
    expect(live.pushEvent).not.toHaveBeenCalled();
    await wrapper.setProps({
      targets: { ...targets, pins: [] },
      state: { ...draft, draftContext: null },
    });
    expect(live.pushEvent).toHaveBeenCalledExactlyOnceWith(
      "comments_place",
      { x: 32, y: 33, context: null, moving_draft: true, draft_id: "draft-a" },
      expect.any(Function),
      expect.any(Function),
    );
    expect(pin.attributes("style")).toContain("left: 740px");
    expect(pin.attributes("style")).toContain("top: 578px");
  });

  it("recovers stored context and retries freely when unavailable without losing composer text", async () => {
    const key = "storyarn:scene-comment-draft:4:scene-canvas-7";
    const context = { type: "scene_pin", id: "42", offset: { x: 2, y: 3 } };
    updateCommentDraft(key, {
      coordinateSpace: "canvas",
      position: { x: 22, y: 23 },
      context,
      body: "Keep this review",
    });
    const { wrapper } = setup();
    await wrapper.setProps({ draftStorageKey: key });
    await nextTick();
    expect(live.pushEvent).toHaveBeenCalledWith(
      "comments_place",
      { x: 22, y: 23, context },
      expect.any(Function),
      expect.any(Function),
    );
    vi.mocked(live.pushEvent).mock.calls[0][2]!({ ok: false, context_unavailable: true });
    expect(live.pushEvent).toHaveBeenLastCalledWith(
      "comments_place",
      { x: 22, y: 23, context: null },
      expect.any(Function),
      expect.any(Function),
    );
    await wrapper.setProps({
      state: {
        ...base,
        open: true,
        presentation: "canvas",
        draftId: "restored",
        draftPosition: { x: 22, y: 23 },
        draftContext: null,
      },
    });
    expect(readCommentDraft(key)).toMatchObject({ body: "Keep this review", context: null });
    await wrapper.setProps({ state: { ...base } });
    expect(readCommentDraft(key)).toMatchObject({
      body: "Keep this review",
      position: { x: 22, y: 23 },
    });
  });

  it("does not reopen a deliberately closed draft when the canvas becomes ready again", async () => {
    const key = "storyarn:scene-comment-draft:4:7";
    updateCommentDraft(key, {
      coordinateSpace: "canvas",
      position: { x: 10, y: 20 },
      body: "Keep for reload",
    });
    const { wrapper } = setup({
      open: true,
      presentation: "canvas",
      draftId: "active",
      draftPosition: { x: 10, y: 20 },
    });
    await wrapper.setProps({ draftStorageKey: key });
    await nextTick();
    vi.mocked(live.pushEvent).mockClear();
    await wrapper.setProps({ state: { ...base }, backgroundSettled: false });
    await wrapper.setProps({ backgroundSettled: true });
    await nextTick();
    expect(live.pushEvent).not.toHaveBeenCalled();
    expect(readCommentDraft(key)).toMatchObject({ body: "Keep for reload" });
  });

  it("does not resurrect a recovery after another draft has been opened and closed", async () => {
    const key = "storyarn:scene-comment-draft:4:scene-canvas-7";
    updateCommentDraft(key, {
      coordinateSpace: "canvas",
      position: { x: 22, y: 23 },
      context: { type: "scene_pin", id: "42" },
      body: "Old draft",
    });
    const { wrapper } = setup();
    await wrapper.setProps({ draftStorageKey: key });
    await nextTick();
    const onReply = vi.mocked(live.pushEvent).mock.calls[0][2]!;
    await wrapper.setProps({
      state: {
        ...base,
        open: true,
        presentation: "canvas",
        draftId: "new-draft",
        draftPosition: { x: 10, y: 10 },
      },
    });
    await wrapper.setProps({ state: { ...base } });
    onReply({ ok: false, context_unavailable: true });
    expect(live.pushEvent).toHaveBeenCalledTimes(1);
    expect(wrapper.find("#scene-comment-draft-pin").exists()).toBe(false);
  });

  it.each(["canvas", "panel"] as const)(
    "offers local hidden-context reveal from %s without pushing a layer mutation",
    async (presentation) => {
      const { wrapper } = setup({ open: true, presentation, thread });
      await wrapper.setProps({ contextVisibility: { hidden: true, local: false } });
      await wrapper.get("#scene-comment-reveal-context").trigger("click");
      expect(wrapper.emitted("revealContext")).toHaveLength(1);
      expect(live.pushEvent).not.toHaveBeenCalled();
      await wrapper.setProps({ contextVisibility: { hidden: false, local: true } });
      expect(wrapper.find("#scene-comment-reveal-context").exists()).toBe(false);
      await wrapper.get("#scene-comment-reset-local-layers").trigger("click");
      expect(wrapper.emitted("resetLocalLayers")).toHaveLength(1);
      expect(live.pushEvent).not.toHaveBeenCalled();
    },
  );

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
