import { afterEach, describe, expect, it, vi } from "vitest";
import { shallowMount, flushPromises, type VueWrapper } from "@vue/test-utils";
import { defineComponent, h } from "vue";
import BrainstormingWorkspace from "@modules/ideation/BrainstormingWorkspace.vue";
import CanvasShapePicker from "@modules/ideation/components/CanvasShapePicker.vue";
import { createMockLive } from "../../setup";
import { board, idea } from "./fixtures";
import type { CanvasPlacement, Idea } from "@modules/ideation/types";

const Canvas = defineComponent({
  name: "BrainstormingCanvas",
  props: ["notes", "editingId", "permissions", "historyState", "selectedIds"],
  setup(_props, { expose, slots }) {
    expose({ focus: vi.fn() });
    return () => h("div", slots.selection?.({ connectionTools: {} }));
  },
});
let wrapper: VueWrapper;
function workspace(defer = false) {
  const live = createMockLive();
  const current = board({
    ideas: [
      idea({ canvas: { x: 30, y: 40, color: "mint", version: 0 } }),
      idea({ id: 11, canvas: { x: 430, y: 40, shape: "ellipse", version: 0 } }),
    ],
  });
  const moves = vi.fn();
  const replies: Array<() => void> = [];
  vi.mocked(live.pushEvent).mockImplementation((event, payload, callback) => {
    if (event !== "move_idea") return;
    moves(payload);
    const id = Number(payload!.idea_id);
    const placement = payload as CanvasPlacement;
    const result = {
      ...current.ideas.find((n) => n.id === id)?.canvas,
      x: placement.x,
      y: placement.y,
      shape: placement.shape,
      width: placement.width,
      version: Number(payload!.version) + 1,
    };
    const reply = () => callback?.({ status: "ok", value: result });
    if (defer) replies.push(reply);
    else reply();
  });
  wrapper = shallowMount(BrainstormingWorkspace, {
    props: { board: current, baseUrl: "/brainstorming" },
    global: { provide: { _live_vue: live }, stubs: { BrainstormingCanvas: Canvas } },
  });
  return { current, canvas: wrapper.getComponent(Canvas), moves, replies };
}
afterEach(() => {
  wrapper?.unmount();
  vi.restoreAllMocks();
});

describe("canvas shape actions", () => {
  it("initializes a legacy note's displayed position when changing its shape", async () => {
    const { canvas, moves, current } = workspace();
    await wrapper.setProps({ board: { ...current, ideas: [idea({ canvas: {} })] } });
    canvas.vm.$emit("select", [10]);
    await flushPromises();
    wrapper.getComponent(CanvasShapePicker).vm.$emit("change", "diamond");
    await flushPromises();
    expect(moves).toHaveBeenCalledWith(
      expect.objectContaining({
        x: 0,
        y: 580,
        width: 528,
        shape: "diamond",
      }),
    );
  });
  it("keeps a new empty note and its editor open when choosing a shape before writing", async () => {
    const { canvas, moves } = workspace();
    canvas.vm.$emit("add", { x: 20, y: 30 });
    await flushPromises();
    const id = canvas.props("editingId");
    expect(id).toBeLessThan(0);
    wrapper.getComponent(CanvasShapePicker).vm.$emit("change", "diamond");
    await flushPromises();
    expect(canvas.props("editingId")).toBe(id);
    expect(canvas.props("notes").find((note: Idea) => note.id === id)?.canvas.shape).toBe(
      "diamond",
    );
    expect(moves).not.toHaveBeenCalled();
  });
  it("changes mixed selected shapes in one undo step and restores the legacy rectangle", async () => {
    const { canvas, moves } = workspace();
    canvas.vm.$emit("select", [10, 11]);
    await flushPromises();
    expect(wrapper.getComponent(CanvasShapePicker).props("value")).toBeNull();
    wrapper.getComponent(CanvasShapePicker).vm.$emit("change", "diamond");
    await flushPromises();
    expect(moves).toHaveBeenCalledTimes(2);
    expect(canvas.props("notes").map((n: Idea) => n.canvas?.shape)).toEqual(["diamond", "diamond"]);
    expect(wrapper.getComponent(CanvasShapePicker).props("value")).toBe("diamond");
    expect(canvas.props("notes")[0].canvas.width).toBe(528);
    wrapper.getComponent(CanvasShapePicker).vm.$emit("change", "diamond");
    await flushPromises();
    expect(moves).toHaveBeenCalledTimes(2);
    canvas.vm.$emit("undo");
    await flushPromises();
    expect(canvas.props("notes").map((n: Idea) => n.canvas?.shape)).toEqual([
      "rectangle",
      "ellipse",
    ]);
    expect(canvas.props("notes")[0].canvas.width).toBe(280);
    expect(canvas.props("historyState")).toMatchObject({ canUndo: false, canRedo: true });
    canvas.vm.$emit("redo");
    await flushPromises();
    expect(canvas.props("notes").map((n: Idea) => n.canvas?.shape)).toEqual(["diamond", "diamond"]);
    expect(canvas.props("notes")[0].body).toBe("<p>Original text</p>");
    expect(canvas.props("notes")[0].canvas).toMatchObject({ x: 30, y: 40, color: "mint" });
  });

  it("waits for shape persistence before undo and restores redo after the acknowledgement", async () => {
    const { canvas, moves, replies } = workspace(true);
    canvas.vm.$emit("select", [10]);
    await flushPromises();
    wrapper.getComponent(CanvasShapePicker).vm.$emit("change", "ellipse");
    canvas.vm.$emit("undo");
    await flushPromises();
    expect(moves).toHaveBeenCalledTimes(1);
    expect(canvas.props("historyState").busy).toBe(true);
    replies.shift()!();
    await flushPromises();
    expect(moves).toHaveBeenCalledTimes(2);
    expect(moves).toHaveBeenLastCalledWith(
      expect.objectContaining({ shape: "rectangle", version: 1 }),
    );
    replies.shift()!();
    await flushPromises();
    expect(canvas.props("historyState")).toMatchObject({
      canUndo: false,
      canRedo: true,
      busy: false,
    });
  });

  it("does not overwrite a newer shape from another participant during undo", async () => {
    const { canvas, moves, current } = workspace();
    canvas.vm.$emit("select", [10]);
    await flushPromises();
    wrapper.getComponent(CanvasShapePicker).vm.$emit("change", "diamond");
    await flushPromises();
    await wrapper.setProps({
      board: {
        ...current,
        ideas: [idea({ canvas: { x: 30, y: 40, shape: "ellipse", version: 5 } }), current.ideas[1]],
      },
    });
    moves.mockClear();
    canvas.vm.$emit("undo");
    await flushPromises();
    expect(moves).not.toHaveBeenCalled();
    expect(canvas.props("notes")[0].canvas.shape).toBe("ellipse");
  });

  it("hides the picker and stops shape writes after editing access is revoked", async () => {
    const { canvas, moves, current } = workspace();
    canvas.vm.$emit("select", [10]);
    await flushPromises();
    expect(wrapper.findComponent(CanvasShapePicker).exists()).toBe(true);
    await wrapper.setProps({ board: { ...current, can_edit: false } });
    expect(wrapper.findComponent(CanvasShapePicker).exists()).toBe(false);
    expect(moves).not.toHaveBeenCalled();
  });
});
