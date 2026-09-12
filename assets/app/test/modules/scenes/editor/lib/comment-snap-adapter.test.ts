import { afterEach, describe, expect, it } from "vitest";
import { CommentMagneticDrag } from "@components/comments/commentMagnetism";
import type { CommentPosition } from "@components/comments/types";
import {
  resolveSceneCommentPosition,
  sceneCommentSnapAdapter,
  type SceneCommentTargets,
} from "@modules/scenes/editor/lib/comment-snap-adapter";

function setup() {
  const container = document.createElement("div");
  document.body.append(container);
  const bounds = { left: 80, top: 40, width: 1000, height: 800 };
  container.getBoundingClientRect = () => ({
    ...bounds,
    x: bounds.left,
    y: bounds.top,
    right: bounds.left + bounds.width,
    bottom: bounds.top + bounds.height,
    toJSON: () => bounds,
  });
  const stage = { x: 20, y: 30, scaleX: 1, scaleY: 1 };
  const projection = {
    percentToPixel: (x: number, y: number) => ({ x: x * 10, y: y * 8 }),
    pixelToPercent: (x: number, y: number) => ({ x: x / 10, y: y / 8 }),
  };
  const targets: SceneCommentTargets = { pins: [], zones: [], connections: [], annotations: [] };
  const adapter = sceneCommentSnapAdapter({
    container: () => container,
    stage: () => stage,
    projection: () => projection,
    targets: () => targets,
  });
  const screen = (x: number, y: number) => ({
    x: bounds.left + stage.x + x * stage.scaleX,
    y: bounds.top + stage.y + y * stage.scaleY,
  });
  const dragAt = (point: CommentPosition) =>
    new CommentMagneticDrag(adapter, { position: adapter.fromScreen(point), context: null }, point);
  const annotation = (id = 4, x = 400, y = 400) => ({
    id,
    x,
    y,
    width: 100,
    height: 100,
    text: " Watch\n the gate ",
    layerId: 1,
  });
  return { container, bounds, stage, targets, adapter, projection, screen, dragAt, annotation };
}

afterEach(() => document.body.replaceChildren());

describe("Scene comment snap geometry", () => {
  it("converts percentage positions through independent zoom, pan, background origin and container offset", () => {
    const { adapter, stage, projection, bounds } = setup();
    stage.scaleX = 2;
    stage.scaleY = 0.5;
    projection.percentToPixel = (x, y) => ({ x: x * 10 - 500, y: y * 8 - 400 });
    projection.pixelToPercent = (x, y) => ({ x: (x + 500) / 10, y: (y + 400) / 8 });
    const position = { x: 60, y: 70 };
    expect(adapter.toScreen(position)).toEqual({ x: 300, y: 150 });
    expect(adapter.fromScreen({ x: 300, y: 150 })).toEqual(position);
    bounds.left = 200;
    stage.x = -50;
    stage.y = 100;
    expect(adapter.toScreen(position)).toEqual({ x: 350, y: 220 });
    expect(adapter.fromScreen({ x: 350, y: 220 })).toEqual(position);
    expect(adapter.clamp({ x: -30, y: 200 })).toEqual({ x: 0, y: 100 });
    expect(adapter.fromScreen({ x: -1000, y: 5000 })).toEqual({ x: 0, y: 100 });
  });

  it("offers the four rendered element types with useful labels and percent offsets", () => {
    const { targets, adapter, projection, annotation } = setup();
    targets.pins = [{ id: 1, x: 100, y: 100, radius: 20, label: "Gate", layerId: 1, opacity: 1 }];
    targets.zones = [
      { id: 2, name: "", points: [150, 200, 200, 100, 300, 200], layerId: 1, opacity: 1 },
    ];
    targets.connections = [
      {
        id: 3,
        points: [130, 100, 200, 300],
        connectedLayerIds: [1],
        opacity: 1,
        origin: { x: 10, y: 12.5 },
      },
    ];
    targets.annotations = [annotation()];
    const candidates = adapter.candidates()!;
    expect(candidates.map(({ context, label }) => [context.type, context.id, label])).toEqual([
      ["scene_zone", "2", "Zone #2"],
      ["scene_connection", "3", "Connection #3"],
      ["scene_pin", "1", "Gate"],
      ["scene_annotation", "4", "Watch the gate"],
    ]);
    const expectedOrigins = [
      { x: 15, y: 12.5 },
      { x: 10, y: 12.5 },
      { x: 10, y: 12.5 },
      { x: 40, y: 50 },
    ];
    candidates.forEach((candidate, index) => {
      const position = { x: 55, y: 65 };
      const context = adapter.context(candidate, position);
      expect(context.offset).toEqual({
        x: position.x - expectedOrigins[index].x,
        y: position.y - expectedOrigins[index].y,
      });
      expect(resolveSceneCommentPosition(null, context, targets, projection)).toEqual(position);
    });
  });

  it.each([0.5, 1, 4])("keeps entry and exit thresholds in screen pixels at zoom %s", (zoom) => {
    const { targets, stage, screen, dragAt, annotation } = setup();
    stage.scaleX = zoom;
    stage.scaleY = zoom;
    targets.annotations = [annotation(1, 100, 100)];
    const corner = screen(100, 100);
    const pointer = { x: corner.x - 40, y: corner.y + 20 };
    const drag = dragAt(pointer);
    expect(drag.update({ x: corner.x - 19, y: pointer.y }).context).toBeNull();
    expect(drag.update({ x: corner.x - 18, y: pointer.y }).context?.type).toBe("scene_annotation");
    expect(drag.preview.screen).toEqual({ x: corner.x, y: pointer.y });
    expect(drag.update({ x: corner.x - 28, y: pointer.y }).context?.type).toBe("scene_annotation");
    expect(drag.update({ x: corner.x - 29, y: pointer.y }).context).toBeNull();
  });

  it("uses the actual concave zone polygon instead of its bounding rectangle", () => {
    const { targets, screen, dragAt } = setup();
    targets.zones = [
      {
        id: 1,
        name: "L-shaped room",
        layerId: null,
        opacity: 1,
        points: [100, 100, 400, 100, 400, 150, 150, 150, 150, 400, 100, 400],
      },
    ];
    const notch = screen(300, 300);
    const drag = dragAt(notch);
    expect(drag.update(notch).context).toBeNull();
    const inside = screen(125, 300);
    expect(drag.update(inside).context?.type).toBe("scene_zone");
    expect(drag.preview.screen).toEqual(inside);
    expect(drag.update(screen(160, 300)).screen).toEqual(screen(150, 300));
  });

  it("snaps to the rendered waypoint path rather than the endpoint chord or line bounds", () => {
    const { targets, screen, dragAt } = setup();
    targets.connections = [
      {
        id: 3,
        points: [100, 100, 300, 400, 500, 100],
        label: "Patrol",
        connectedLayerIds: [],
        opacity: 1,
        origin: { x: 10, y: 12.5 },
      },
    ];
    const empty = screen(300, 100);
    const drag = dragAt(empty);
    expect(drag.update(empty).context).toBeNull();
    const segment = screen(200, 250);
    expect(drag.update(segment).context).toEqual({
      type: "scene_connection",
      id: "3",
      offset: { x: 10, y: 18.75 },
    });
    expect(drag.preview.screen).toEqual(segment);
  });

  it("stores a connection offset from its canonical origin, excluding the rendered endpoint gap", () => {
    const { targets, adapter, projection } = setup();
    targets.connections = [
      {
        id: 3,
        points: [124, 100, 476, 100],
        connectedLayerIds: [],
        opacity: 1,
        origin: { x: 10, y: 12.5 },
      },
    ];
    const candidate = adapter.candidates()![0];
    const context = adapter.context(candidate, { x: 12.4, y: 12.5 });
    expect(context.offset?.x).toBeCloseTo(2.4);
    targets.connections = [
      { ...targets.connections[0], origin: { x: 20, y: 25 }, points: [224, 200, 476, 100] },
    ];
    expect(resolveSceneCommentPosition({ x: 12.4, y: 12.5 }, context, targets, projection)).toEqual(
      { x: 22.4, y: 25 },
    );
  });

  it("uses a pin's circular footprint and does not magnetize its rectangular corners", () => {
    const { targets, screen, dragAt } = setup();
    targets.pins = [
      { id: 1, x: 300, y: 300, radius: 100, label: "Gate", layerId: null, opacity: 1 },
    ];
    const outsideCircle = screen(399, 399);
    const drag = dragAt(outsideCircle);
    expect(drag.update(outsideCircle).context).toBeNull();
    expect(drag.update(screen(405, 300)).context?.type).toBe("scene_pin");
    expect(drag.preview.screen.x).toBeCloseTo(screen(400, 300).x);
  });

  it("offers overlapping targets in visual order and lets the user cycle through all of them", () => {
    const { targets, screen, dragAt, annotation } = setup();
    targets.zones = [
      {
        id: 1,
        name: "Room",
        layerId: null,
        opacity: 1,
        points: [100, 100, 200, 100, 200, 200, 100, 200],
      },
    ];
    targets.pins = [
      { id: 2, x: 150, y: 150, radius: 20, label: "Gate", layerId: null, opacity: 1 },
    ];
    targets.annotations = [annotation(3, 100, 100)];
    const pointer = screen(150, 150);
    const drag = dragAt(pointer);
    expect(drag.update(pointer).context?.type).toBe("scene_annotation");
    expect(drag.cycle(1).context?.type).toBe("scene_pin");
    expect(drag.cycle(1).context?.type).toBe("scene_zone");
    expect(drag.cycle(1).context?.type).toBe("scene_annotation");
    expect(drag.update(pointer, true).context).toBeNull();
  });

  it("respects hidden layers and keeps a connection visible when one endpoint layer is visible", () => {
    const { targets, adapter, annotation } = setup();
    targets.layers = [
      { id: "1", visible: false },
      { id: 2, visible: true },
    ];
    targets.pins = [{ id: 1, x: 100, y: 100, radius: 20, label: "Hidden", layerId: 1, opacity: 1 }];
    targets.zones = [
      { id: 2, name: "Hidden", points: [100, 100, 200, 100, 200, 200], layerId: 1, opacity: 1 },
    ];
    targets.annotations = [annotation()];
    targets.connections = [
      {
        id: 3,
        points: [100, 100, 200, 200],
        connectedLayerIds: [1],
        opacity: 1,
        origin: { x: 10, y: 12.5 },
      },
      {
        id: 4,
        points: [100, 100, 200, 200],
        connectedLayerIds: [1, 2],
        opacity: 1,
        origin: { x: 10, y: 12.5 },
      },
    ];
    expect(adapter.candidates()?.map(({ context }) => context.id)).toEqual(["4"]);
  });

  it("retains full offscreen geometry for partially visible targets and follows offscreen context", () => {
    const { targets, adapter, projection, annotation } = setup();
    targets.annotations = [annotation(4, -30, 100)];
    expect(adapter.candidates()![0].geometry).toEqual({
      kind: "rect",
      left: 70,
      top: 170,
      width: 100,
      height: 100,
    });
    targets.annotations = [annotation(4, 2000, 100)];
    expect(adapter.candidates()).toEqual([]);
    expect(
      resolveSceneCommentPosition(
        { x: 10, y: 10 },
        { type: "scene_annotation", id: "4", offset: { x: -1, y: 2 } },
        targets,
        projection,
      ),
    ).toEqual({ x: 100, y: 14.5 });
  });

  it("keeps a rendered free-endpoint route available when its connected pin's layer is hidden", () => {
    const { targets, adapter, projection } = setup();
    targets.layers = [{ id: 1, visible: false }];
    targets.connections = [
      {
        id: 3,
        points: [100, 100, 200, 200],
        connectedLayerIds: [1],
        opacity: 1,
        freeEndpoint: true,
        origin: { x: 10, y: 12.5 },
      },
    ];
    expect(adapter.candidates()?.[0].context).toEqual({ type: "scene_connection", id: "3" });
    expect(
      resolveSceneCommentPosition(
        null,
        { type: "scene_connection", id: "3", offset: { x: 1, y: 2 } },
        targets,
        projection,
      ),
    ).toEqual({ x: 11, y: 14.5 });
  });

  it("follows hidden context through raw origins without offering it as a snap candidate", () => {
    const { targets, adapter, projection } = setup();
    targets.origins = [{ type: "scene_pin", id: 1, position: { x: 40, y: 50 } }];
    const context = { type: "scene_pin", id: "1", offset: { x: 5, y: -3 } };
    expect(adapter.candidates()).toEqual([]);
    expect(resolveSceneCommentPosition({ x: 10, y: 10 }, context, targets, projection)).toEqual({
      x: 45,
      y: 47,
    });
    targets.pins = [
      { id: 1, x: 600, y: 600, radius: 20, label: "Gate", layerId: null, opacity: 1 },
    ];
    expect(resolveSceneCommentPosition({ x: 10, y: 10 }, context, targets, projection)).toEqual({
      x: 65,
      y: 72,
    });
  });

  it("preserves fallback when context is removed or unavailable, and follows a restored available context", () => {
    const { targets, projection } = setup();
    const fallback = { x: 20, y: 30 };
    const context = { type: "scene_zone", id: "2", offset: { x: 5, y: 3 } };
    expect(resolveSceneCommentPosition(fallback, context, targets, projection)).toEqual(fallback);
    targets.zones = [
      { id: 2, name: "Room", layerId: null, opacity: 1, points: [300, 400, 400, 400, 400, 500] },
    ];
    expect(
      resolveSceneCommentPosition(
        fallback,
        { ...context, status: "unavailable" },
        targets,
        projection,
      ),
    ).toEqual(fallback);
    expect(
      resolveSceneCommentPosition(
        fallback,
        { ...context, status: "available" },
        targets,
        projection,
      ),
    ).toEqual({ x: 35, y: 53 });
    expect(context.offset).toEqual({ x: 5, y: 3 });
  });

  it("keeps pin icons available when their circle fill is transparent", () => {
    const { targets, adapter, screen, dragAt } = setup();
    targets.pins = [{ id: 1, x: 100, y: 100, radius: 20, label: "", layerId: null, opacity: 0 }];
    expect(adapter.candidates()?.[0].context).toEqual({ type: "scene_pin", id: "1" });
    const point = screen(100, 100);
    expect(dragAt(point).update(point).context?.type).toBe("scene_pin");
  });

  it("snaps only to the rendered label of a transparent zone", () => {
    const { targets, adapter, screen, dragAt } = setup();
    targets.zones = [
      {
        id: 3,
        name: "Gate",
        points: [100, 100, 400, 100, 400, 400, 100, 400],
        layerId: null,
        opacity: 0,
        showLabelText: true,
        labelText: "Gate",
        labelX: 200,
        labelTextX: 200,
        labelY: 200,
        labelWidth: 100,
        labelHeight: 20,
      },
    ];
    expect(adapter.candidates()?.[0].geometry).toEqual({
      kind: "rect",
      left: screen(200, 200).x,
      top: screen(200, 200).y,
      width: 100,
      height: 20,
    });
    const invisibleInterior = screen(150, 350);
    const drag = dragAt(invisibleInterior);
    expect(drag.update(invisibleInterior).context).toBeNull();
    expect(drag.update(screen(250, 210)).context?.type).toBe("scene_zone");
    targets.zones = [{ ...targets.zones[0], showLabelText: false }];
    expect(adapter.candidates()).toEqual([]);
  });

  it("uses the exact icon-label rectangle when a transparent zone has no visible text", () => {
    const { targets, adapter, screen } = setup();
    targets.zones = [
      {
        id: 3,
        name: "Gate",
        points: [100, 100, 400, 100, 400, 400],
        layerId: null,
        opacity: 0,
        labelIconCanvas: document.createElement("canvas"),
        labelIconX: 250,
        labelIconY: 200,
        labelIconSize: 16,
      },
    ];
    expect(adapter.candidates()?.[0].geometry).toEqual({
      kind: "rect",
      left: screen(250, 200).x,
      top: screen(250, 200).y,
      width: 16,
      height: 16,
    });
  });

  it("ignores malformed, invisible and absent targets", () => {
    const { targets, adapter, annotation, stage } = setup();
    targets.pins = [
      { id: 2, x: Number.NaN, y: 100, radius: 20, label: "", layerId: null, opacity: 1 },
    ];
    targets.zones = [
      { id: 3, name: "", points: [100, 100, 200, 200], layerId: null, opacity: 1 },
      { id: 5, name: "", points: [100, 100, 200, 200, 300, 100], layerId: null, opacity: 0 },
    ];
    targets.connections = [
      {
        id: 4,
        points: [100, 100, 200],
        connectedLayerIds: [],
        opacity: 1,
        origin: { x: 10, y: 10 },
      },
    ];
    targets.annotations = [{ ...annotation(), width: 0 }];
    expect(adapter.candidates()).toEqual([]);
    stage.scaleX = Number.NaN;
    expect(adapter.candidates()).toEqual([]);
    expect(
      sceneCommentSnapAdapter({
        container: () => null,
        stage: () => stage,
        targets: () => targets,
        projection: () => ({
          percentToPixel: (x, y) => ({ x, y }),
          pixelToPercent: (x, y) => ({ x, y }),
        }),
      }).candidates(),
    ).toEqual([]);
  });

  it("keeps legacy free positions and rejects malformed offsets without changing the model", () => {
    const { targets, projection } = setup();
    targets.origins = [{ type: "scene_pin", id: 1, position: { x: 40, y: 50 } }];
    const fallback = { x: 20, y: 30 };
    for (const offset of [undefined, null, { x: Number.NaN, y: 10 }, { x: 10, y: Infinity }]) {
      expect(
        resolveSceneCommentPosition(
          fallback,
          { type: "scene_pin", id: "1", offset },
          targets,
          projection,
        ),
      ).toEqual(fallback);
    }
    expect(resolveSceneCommentPosition(fallback, null, targets, projection)).toEqual(fallback);
    expect(resolveSceneCommentPosition(null, null, targets, projection)).toBeNull();
    expect(
      resolveSceneCommentPosition({ x: Infinity, y: 10 }, null, targets, projection),
    ).toBeNull();
    expect(
      resolveSceneCommentPosition(
        fallback,
        { type: "flow_node", id: "1", offset: { x: 0, y: 0 } },
        targets,
        projection,
      ),
    ).toEqual(fallback);
  });
});
