import { afterEach, describe, expect, it } from "vitest";
import { CommentMagneticDrag } from "@components/comments/commentMagnetism";
import {
  commentCanvasPoint,
  contextualCommentPoint,
  type CommentPoint,
} from "@modules/flows/editor/lib/comment-geometry";
import {
  flowCommentSnapAdapter,
  resolveFlowCommentPosition,
} from "@modules/flows/editor/lib/comment-snap-adapter";
import type { FlowCommentThread } from "@modules/flows/types/comments";

function measure(
  element: HTMLElement,
  bounds: () => { left: number; top: number; width: number; height: number },
) {
  element.getBoundingClientRect = () => {
    const rect = bounds();
    return {
      ...rect,
      x: rect.left,
      y: rect.top,
      right: rect.left + rect.width,
      bottom: rect.top + rect.height,
      toJSON: () => rect,
    };
  };
}

function setup() {
  const container = document.createElement("div");
  document.body.append(container);
  const bounds = { left: 80, top: 40, width: 800, height: 600 };
  measure(container, () => bounds);
  const area = {
    area: { transform: { x: 20, y: 30, k: 2 } },
    nodeViews: new Map<string, { position: CommentPoint }>(),
  };
  const adapter = flowCommentSnapAdapter(area, container);

  function node(
    id = "42",
    position = { x: 100, y: 100 },
    size = { width: 100, height: 60 },
    parent = container,
  ) {
    const element = document.createElement("div");
    element.dataset.flowCommentNode = id;
    element.dataset.flowCommentLabel = id === "42" ? "Guard dialogue" : "Entrance sequence";
    const view = { position };
    area.nodeViews.set(`node-${id}`, view);
    measure(element, () => {
      const { x, y, k } = area.area.transform;
      return {
        left: bounds.left + x + view.position.x * k,
        top: bounds.top + y + view.position.y * k,
        width: size.width * k,
        height: size.height * k,
      };
    });
    parent.append(element);
    return { element, view };
  }
  return { container, bounds, area, adapter, node };
}

afterEach(() => document.body.replaceChildren());

describe("Flow comment snap geometry", () => {
  it("converts client pixels to absolute Rete coordinates through live pan, zoom and layout changes", () => {
    const { area, adapter, bounds } = setup();
    const saved = { x: 120, y: 130 };
    expect(adapter.toScreen(saved)).toEqual({ x: 340, y: 330 });
    expect(adapter.fromScreen({ x: 340, y: 330 })).toEqual(saved);

    area.area.transform = { x: -200, y: 100, k: 0.5 };
    bounds.left = 200;
    bounds.top = 50;
    expect(adapter.toScreen(saved)).toEqual({ x: 60, y: 215 });
    expect(adapter.fromScreen({ x: 60, y: 215 })).toEqual(saved);
    expect(adapter.clamp({ x: -5000, y: 15000 })).toEqual({ x: -5000, y: 15000 });
  });

  it.each([0.5, 1, 2])("keeps the snap threshold in screen pixels at zoom %s", (zoom) => {
    const { area, adapter, node } = setup();
    area.area.transform.k = zoom;
    const { element } = node();
    const rect = element.getBoundingClientRect();
    const start = { x: rect.left - 40, y: rect.top + 20 };
    const drag = new CommentMagneticDrag(
      adapter,
      { position: adapter.fromScreen(start), context: null },
      start,
    );

    expect(drag.update({ x: rect.left - 19, y: start.y }).context).toBeNull();
    const snapped = drag.update({ x: rect.left - 18, y: start.y });
    expect(snapped.context).toEqual({
      type: "flow_node",
      id: "42",
      offset: { x: 0, y: 20 / zoom },
    });
    expect(snapped.screen).toEqual({ x: rect.left, y: start.y });
    expect(drag.update({ x: rect.left - 28, y: start.y }).context?.id).toBe("42");
    expect(drag.update({ x: rect.left - 29, y: start.y }).context).toBeNull();
  });

  it("uses absolute child origins within Sequence and offers both overlapping contexts", () => {
    const { area, adapter, container, node } = setup();
    const sequence = node("7", { x: 50, y: 50 }, { width: 300, height: 200 });
    const child = node("42", { x: 100, y: 100 }, undefined, sequence.element);
    const saved = { x: 110, y: 120 };
    const pointer = adapter.toScreen(saved);
    const drag = new CommentMagneticDrag(adapter, { position: saved, context: null }, pointer);

    expect(drag.update(pointer).candidate?.label).toBe("Guard dialogue");
    expect(drag.preview.context).toEqual({
      type: "flow_node",
      id: "42",
      offset: { x: 10, y: 20 },
    });
    expect(drag.cycle(1).context).toEqual({
      type: "flow_node",
      id: "7",
      offset: { x: 60, y: 70 },
    });

    const context = { type: "flow_node", id: "42", offset: { x: 10, y: 20 } };
    sequence.view.position = { x: 300, y: 200 };
    child.view.position = { x: 350, y: 250 };
    expect(resolveFlowCommentPosition(saved, context, area, container)).toEqual({ x: 360, y: 270 });
    container.append(child.element);
    child.view.position = { x: 700, y: 400 };
    expect(resolveFlowCommentPosition(saved, context, area, container)).toEqual({ x: 710, y: 420 });
    expect(context.offset).toEqual({ x: 10, y: 20 });
  });

  it("retains complete target rectangles and follows offscreen nodes for navigation", () => {
    const { area, adapter, container, node } = setup();
    const { view } = node("42", { x: -50, y: 100 });
    expect(adapter.candidates()?.[0].geometry).toEqual({
      kind: "rect",
      left: 0,
      top: 270,
      width: 200,
      height: 120,
    });
    view.position.x = 2000;
    const context = { type: "flow_node", id: "42", offset: { x: 10, y: 20 } };
    expect(adapter.candidates()).toEqual([]);
    expect(resolveFlowCommentPosition({ x: 110, y: 120 }, context, area, container)).toEqual({
      x: 2010,
      y: 120,
    });
  });

  it.each(["hidden", "aria-hidden", "inert", "display", "visibility", "opacity"])(
    "does not snap to targets hidden by ancestor %s and preserves their saved fallback",
    (hiddenBy) => {
      const { area, adapter, container, node } = setup();
      const parent = document.createElement("div");
      container.append(parent);
      node("42", undefined, undefined, parent);
      if (hiddenBy === "display") parent.style.display = "none";
      else if (hiddenBy === "visibility") parent.style.visibility = "hidden";
      else if (hiddenBy === "opacity") parent.style.opacity = "0";
      else parent.setAttribute(hiddenBy, "true");
      const fallback = { x: 500, y: 500 };
      const context = { type: "flow_node", id: "42", offset: { x: 10, y: 20 } };
      expect(adapter.candidates()).toEqual([]);
      expect(resolveFlowCommentPosition(fallback, context, area, container)).toEqual(fallback);
    },
  );

  it("falls back after deletion or unavailable context and follows the node when restored", () => {
    const { area, adapter, container, node } = setup();
    const { element, view } = node();
    const fallback = { x: 500, y: 500 };
    const context = { type: "flow_node", id: "42", offset: { x: 10, y: 20 } };

    expect(
      resolveFlowCommentPosition(fallback, { ...context, status: "unavailable" }, area, container),
    ).toEqual(fallback);
    area.nodeViews.delete("node-42");
    expect(adapter.candidates()).toEqual([]);
    expect(resolveFlowCommentPosition(fallback, context, area, container)).toEqual(fallback);
    area.nodeViews.set("node-42", view);
    view.position = { x: 300, y: 200 };
    expect(resolveFlowCommentPosition(fallback, context, area, container)).toEqual({
      x: 310,
      y: 220,
    });

    // Rete may have its authoritative view before Vue remounts a reparented node.
    element.remove();
    expect(resolveFlowCommentPosition(fallback, context, area, container)).toEqual({
      x: 310,
      y: 220,
    });
    expect(context.offset).toEqual({ x: 10, y: 20 });
  });

  it("matches context IDs literally when checking whether their targets are hidden", () => {
    const { area, container, node } = setup();
    node("42");
    const id = '42"\\child]';
    const { element } = node(id);
    element.hidden = true;
    const fallback = { x: 500, y: 500 };
    const context = { type: "flow_node", id, offset: { x: 10, y: 20 } };

    expect(resolveFlowCommentPosition(fallback, context, area, container)).toEqual(fallback);
    element.hidden = false;
    expect(resolveFlowCommentPosition(fallback, context, area, container)).toEqual({
      x: 110,
      y: 120,
    });
  });

  it("ignores zero-sized and stale DOM targets without losing valid node references", () => {
    const { area, adapter, node } = setup();
    node("7", undefined, { width: 100, height: 0 });
    node("42");
    area.nodeViews.delete("node-42");
    expect(adapter.candidates()).toEqual([]);
  });

  it("keeps missing or malformed offsets at their saved canvas position", () => {
    const { area, node } = setup();
    node();
    const fallback = { x: 500, y: 500 };
    for (const offset of [undefined, null, { x: Number.NaN, y: 10 }, { x: 10, y: Infinity }]) {
      expect(
        contextualCommentPoint(fallback, { type: "flow_node", id: "42", offset }, area.nodeViews),
      ).toEqual(fallback);
    }
    expect(contextualCommentPoint(null, null, area.nodeViews)).toBeNull();
    expect(
      contextualCommentPoint(
        fallback,
        { type: "scene_pin", id: "42", offset: { x: 10, y: 20 } },
        area.nodeViews,
      ),
    ).toEqual(fallback);
  });

  it("preserves legacy node offsets while canonical Flow threads accept absolute pending movement", () => {
    const { area, node } = setup();
    node();
    const legacy: FlowCommentThread = {
      id: 1,
      status: "open",
      revision: 1,
      message_count: 1,
      created_at: "2026-09-12T08:00:00Z",
      last_activity_at: "2026-09-12T08:00:00Z",
      resolved_at: null,
      resolved_by: null,
      source: { type: "flow_node", id: 42, flow_id: 7, label: "Guard", status: "available" },
      author: { id: 1, display_name: "Ada", avatar_url: null },
      position: { x: 10, y: 20 },
    };
    expect(commentCanvasPoint(legacy, area.nodeViews)).toEqual({ x: 110, y: 120 });
    expect(commentCanvasPoint({ ...legacy, position: null }, area.nodeViews)).toEqual({
      x: 116,
      y: 116,
    });
    const canonical = {
      ...legacy,
      source: { ...legacy.source, type: "flow_canvas" as const, id: 7 },
      context: {
        type: "flow_node",
        id: "42",
        label: "Guard",
        status: "available" as const,
        offset: { x: 10, y: 20 },
      },
      position: { x: 110, y: 120 },
    };
    expect(commentCanvasPoint(canonical, area.nodeViews, { x: 500, y: 600 })).toEqual({
      x: 500,
      y: 600,
    });
  });
});
