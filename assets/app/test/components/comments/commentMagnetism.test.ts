import { describe, expect, it } from "vitest";
import {
  COMMENT_SNAP_ENTER_PX,
  COMMENT_SNAP_EXIT_PX,
  CommentMagneticDrag,
  type CommentContextReference,
  type CommentMagneticAdapter,
  type CommentSnapCandidate,
  type CommentSnapGeometry,
} from "../../../components/comments/commentMagnetism";
import type { CommentPosition } from "../../../components/comments/types";

function candidate(
  id: string,
  geometry: CommentSnapGeometry,
  priority?: number,
): CommentSnapCandidate {
  return { context: { type: "flow_node", id }, label: `Target ${id}`, geometry, priority };
}

function setup(initialContext: CommentContextReference | null = null) {
  let candidates: readonly CommentSnapCandidate[] | null = [];
  const transform = { zoom: 1, x: 0, y: 0 };
  const adapter: CommentMagneticAdapter = {
    candidates: () => candidates,
    toScreen: ({ x, y }) => ({
      x: x * transform.zoom + transform.x,
      y: y * transform.zoom + transform.y,
    }),
    fromScreen: ({ x, y }) => ({
      x: (x - transform.x) / transform.zoom,
      y: (y - transform.y) / transform.zoom,
    }),
    clamp: (position) => position,
    context: (target, position) => ({ ...target.context, offset: { ...position } }),
  };
  const drag = new CommentMagneticDrag(
    adapter,
    { position: { x: 0, y: 0 }, context: initialContext },
    { x: 0, y: 0 },
  );

  return {
    drag,
    adapter,
    transform,
    targets: (next: readonly CommentSnapCandidate[] | null) => {
      candidates = next;
    },
  };
}

describe("CommentMagneticDrag", () => {
  it("enters at 18 client pixels, retains the target through 28 pixels, and detaches beyond it", () => {
    const { drag, targets } = setup();
    targets([candidate("node", { kind: "rect", left: 100, top: 50, width: 100, height: 60 })]);

    expect(drag.update({ x: 100 - COMMENT_SNAP_ENTER_PX - 1, y: 80 }).context).toBeNull();
    expect(drag.update({ x: 100 - COMMENT_SNAP_ENTER_PX, y: 80 }).position).toEqual({
      x: 100,
      y: 80,
    });
    expect(drag.update({ x: 100 - COMMENT_SNAP_EXIT_PX, y: 80 }).candidate?.context.id).toBe(
      "node",
    );
    expect(drag.update({ x: 100 - COMMENT_SNAP_EXIT_PX - 1, y: 80 }).context).toBeNull();
    expect(drag.preview.position).toEqual({ x: 71, y: 80 });
    expect(drag.update({ x: 75, y: 80 }).context).toBeNull();
  });

  it("uses current transforms and fresh geometry after zoom and pan change during a drag", () => {
    const { adapter, transform, targets } = setup();
    transform.zoom = 2;
    transform.x = 40;
    transform.y = 30;
    const drag = new CommentMagneticDrag(
      adapter,
      { position: { x: 10, y: 20 }, context: null },
      { x: 65, y: 77 },
    );

    expect(drag.update({ x: 105, y: 117 }).position).toEqual({ x: 30, y: 40 });
    transform.zoom = 0.5;
    transform.x = -20;
    transform.y = 10;
    targets([candidate("zoomed", { kind: "rect", left: 100, top: 80, width: 40, height: 30 })]);

    // The original grab offset remains five/seven screen pixels at the new zoom.
    const preview = drag.update({ x: 89, y: 97 });
    expect(preview.screen).toEqual({ x: 100, y: 90 });
    expect(preview.position).toEqual({ x: 240, y: 160 });
    expect(preview.context).toEqual({
      type: "flow_node",
      id: "zoomed",
      offset: { x: 240, y: 160 },
    });

    targets([candidate("zoomed", { kind: "rect", left: 160, top: 80, width: 40, height: 30 })]);
    expect(drag.update({ x: 89, y: 97 }).context).toBeNull();
    expect(drag.preview.position).toEqual({ x: 208, y: 160 });
  });

  it("chooses ties deterministically regardless of adapter iteration order", () => {
    const items = [
      candidate("z", { kind: "point", x: 0, y: 10 }),
      candidate("a", { kind: "point", x: 10, y: 0 }),
    ];
    for (const ordered of [items, [...items].reverse()]) {
      const { drag, targets } = setup();
      targets(ordered);
      expect(drag.update({ x: 0, y: 0 }).candidate?.context.id).toBe("a");
    }
  });

  it("prefers distance, then explicit priority, then the smaller contained target", () => {
    const { drag, targets } = setup();
    targets([
      candidate("far-priority", { kind: "point", x: 10, y: 0 }, 100),
      candidate("row", { kind: "rect", left: -40, top: -40, width: 80, height: 80 }),
      candidate("block", { kind: "rect", left: -10, top: -10, width: 20, height: 20 }),
    ]);
    expect(drag.update({ x: 0, y: 0 }).candidate?.context.id).toBe("block");

    const prioritized = setup();
    prioritized.targets([
      candidate("row", { kind: "rect", left: -40, top: -40, width: 80, height: 80 }, 1),
      candidate("block", { kind: "rect", left: -10, top: -10, width: 20, height: 20 }),
    ]);
    expect(prioritized.drag.update({ x: 0, y: 0 }).candidate?.context.id).toBe("row");
  });

  it("cycles every nested target and keeps the explicit choice while moving within it", () => {
    const { drag, targets } = setup();
    const row = candidate("row", { kind: "rect", left: 0, top: 0, width: 300, height: 100 });
    row.context.type = "sheet_column_group";
    const block = candidate("block", { kind: "rect", left: 0, top: 0, width: 80, height: 100 });
    block.context.type = "sheet_block";
    const duplicate = { ...block, label: "Repeated DOM representation" };
    targets([row, duplicate, block]);

    expect(drag.update({ x: 40, y: 30 }).candidates).toHaveLength(2);
    expect(drag.preview.candidate?.context.id).toBe("block");
    expect(drag.cycle(1).candidate?.context.id).toBe("row");
    expect(drag.update({ x: 42, y: 35 }).candidate?.context.id).toBe("row");
    expect(drag.cycle(1).candidate?.context.id).toBe("block");
    expect(drag.cycle(-1).candidate?.context.id).toBe("row");
    expect(drag.preview.position).toEqual({ x: 42, y: 35 });
  });

  it("retains an active target instead of flickering to a closer overlapping neighbor", () => {
    const { drag, targets } = setup();
    targets([
      candidate("left", { kind: "point", x: 0, y: 0 }),
      candidate("right", { kind: "point", x: 35, y: 0 }),
    ]);
    expect(drag.update({ x: 0, y: 0 }).candidate?.context.id).toBe("left");
    expect(drag.update({ x: 25, y: 0 }).candidate?.context.id).toBe("left");
    expect(drag.preview.candidates.map(({ context }) => context.id)).toEqual(["right", "left"]);
    expect(drag.cycle(1).candidate?.context.id).toBe("right");
    expect(drag.update({ x: 29, y: 0 }).candidate?.context.id).toBe("right");
  });

  it("matches stable context identities when labels, offsets, and candidate objects change", () => {
    const initial = { type: "flow_node", id: "prior", offset: { x: 1, y: 2 } };
    const { drag, targets } = setup(initial);
    targets([
      candidate("preferred", { kind: "point", x: 0, y: 0 }),
      { ...candidate("prior", { kind: "point", x: 20, y: 0 }), label: "Renamed node" },
    ]);
    expect(drag.update({ x: 0, y: 0 }).candidate?.context.id).toBe("prior");
    expect(drag.preview.context?.offset).toEqual({ x: 20, y: 0 });
  });

  it("detaches when a supported adapter loses its target, but preserves unsupported context", () => {
    const initial = { type: "sheet_header", id: "1", offset: null };
    const { drag, targets } = setup(initial);
    targets(null);
    expect(drag.update({ x: 20, y: 30 }).context).toEqual(initial);
    expect(drag.preview.position).toEqual({ x: 20, y: 30 });

    targets([]);
    expect(drag.update({ x: 21, y: 31 }).context).toBeNull();
  });

  it("lets an unsupported adapter retain and adjust an existing context offset", () => {
    const { drag, targets, adapter } = setup({ type: "legacy", id: "1", offset: { x: 5, y: 6 } });
    targets(null);
    adapter.moveContext = (context, position) => ({
      ...context,
      offset: { x: position.x - 10, y: position.y - 20 },
    });
    expect(drag.update({ x: 30, y: 40 }).context).toEqual({
      type: "legacy",
      id: "1",
      offset: { x: 20, y: 20 },
    });
  });

  it("suppresses magnetism and clears context even for unsupported adapters", () => {
    const { drag, targets } = setup({ type: "old", id: "1" });
    targets([candidate("node", { kind: "point", x: 20, y: 20 })]);
    expect(drag.update({ x: 22, y: 22 }).position).toEqual({ x: 20, y: 20 });
    const free = drag.update({ x: 22, y: 22 }, true);
    expect(free.position).toEqual({ x: 22, y: 22 });
    expect(free.context).toBeNull();
    expect(free.candidates).toEqual([]);
    expect(drag.cycle(1).context).toBeNull();
    expect(drag.update({ x: 22, y: 22 }).candidate?.context.id).toBe("node");

    targets(null);
    expect(drag.update({ x: 22, y: 22 }, true).context).toBeNull();
  });

  it("cancels to a defensive copy of the complete initial state", () => {
    const { adapter, targets } = setup();
    const initial = {
      position: { x: 30, y: 40 },
      context: { type: "flow_node", id: "original", offset: { x: 5, y: 6 } },
    };
    const drag = new CommentMagneticDrag(adapter, initial, initial.position);
    initial.position.x = 999;
    initial.context.offset.x = 999;
    targets([candidate("new", { kind: "point", x: 100, y: 100 })]);
    drag.update({ x: 100, y: 100 });

    const cancelled = drag.cancel();
    expect(cancelled).toEqual({
      position: { x: 30, y: 40 },
      context: { type: "flow_node", id: "original", offset: { x: 5, y: 6 } },
    });
    cancelled.position.x = 999;
    cancelled.context!.offset!.x = 999;
    expect(drag.cancel().position).toEqual({ x: 30, y: 40 });
    expect(drag.preview.context?.offset).toEqual({ x: 5, y: 6 });
  });

  it("keeps returned preview objects from mutating the current drag state", () => {
    const { drag, targets } = setup();
    targets([
      candidate("node", {
        kind: "polyline",
        points: [
          { x: 0, y: 0 },
          { x: 10, y: 0 },
        ],
      }),
    ]);
    const preview = drag.update({ x: 4, y: 3 });
    preview.position.x = 999;
    preview.screen.x = 999;
    preview.context!.offset!.x = 999;
    preview.candidate!.context.id = "changed";
    const geometry = preview.candidates[0].geometry;
    if (geometry.kind === "polyline") geometry.points[0].x = 999;

    expect(drag.preview.position).toEqual({ x: 4, y: 0 });
    expect(drag.preview.context?.offset).toEqual({ x: 4, y: 0 });
    expect(drag.preview.candidate?.context.id).toBe("node");
    expect(drag.preview.candidates[0].geometry).toEqual({
      kind: "polyline",
      points: [
        { x: 0, y: 0 },
        { x: 10, y: 0 },
      ],
    });
  });

  it("clamps the free and snapped position to the owning surface", () => {
    const { drag, adapter, targets } = setup();
    adapter.clamp = ({ x, y }) => ({
      x: Math.max(0, Math.min(100, x)),
      y: Math.max(0, Math.min(100, y)),
    });
    expect(drag.update({ x: -20, y: 200 }).position).toEqual({ x: 0, y: 100 });
    targets([candidate("edge", { kind: "point", x: 105, y: 50 })]);
    expect(drag.update({ x: 90, y: 50 }).position).toEqual({ x: 100, y: 50 });
    expect(drag.preview.context?.offset).toEqual({ x: 100, y: 50 });
  });

  it("ignores invalid pointer and transform results instead of emitting nonfinite positions", () => {
    const { drag, adapter } = setup();
    drag.update({ x: 20, y: 30 });
    expect(drag.update({ x: Number.NaN, y: 30 }).position).toEqual({ x: 20, y: 30 });
    adapter.fromScreen = () => ({ x: Number.POSITIVE_INFINITY, y: 1 });
    expect(drag.update({ x: 40, y: 50 }).position).toEqual({ x: 20, y: 30 });
    adapter.fromScreen = (position) => position;
    adapter.clamp = () => ({ x: 1, y: Number.NaN });
    expect(drag.update({ x: 40, y: 50 }).position).toEqual({ x: 20, y: 30 });
  });
});

describe("comment snap geometry", () => {
  it.each<{
    name: string;
    geometry: CommentSnapGeometry;
    pointer: CommentPosition;
    expected: CommentPosition;
  }>([
    {
      name: "rect corner",
      geometry: { kind: "rect", left: 10, top: 20, width: 30, height: 40 },
      pointer: { x: 4, y: 13 },
      expected: { x: 10, y: 20 },
    },
    {
      name: "rect interior",
      geometry: { kind: "rect", left: 10, top: 20, width: 30, height: 40 },
      pointer: { x: 25, y: 45 },
      expected: { x: 25, y: 45 },
    },
    {
      name: "point",
      geometry: { kind: "point", x: 10, y: 20 },
      pointer: { x: 15, y: 25 },
      expected: { x: 10, y: 20 },
    },
    {
      name: "diagonal segment",
      geometry: {
        kind: "polyline",
        points: [
          { x: 0, y: 0 },
          { x: 20, y: 20 },
        ],
      },
      pointer: { x: 20, y: 0 },
      expected: { x: 10, y: 10 },
    },
    {
      name: "segment endpoint",
      geometry: {
        kind: "polyline",
        points: [
          { x: 0, y: 0 },
          { x: 20, y: 0 },
        ],
      },
      pointer: { x: 24, y: 3 },
      expected: { x: 20, y: 0 },
    },
    {
      name: "polyline nearest segment",
      geometry: {
        kind: "polyline",
        points: [
          { x: 0, y: 0 },
          { x: 20, y: 0 },
          { x: 20, y: 30 },
        ],
      },
      pointer: { x: 25, y: 20 },
      expected: { x: 20, y: 20 },
    },
    {
      name: "closed polygon edge",
      geometry: {
        kind: "polyline",
        closed: true,
        points: [
          { x: 0, y: 0 },
          { x: 30, y: 0 },
          { x: 30, y: 30 },
        ],
      },
      pointer: { x: 7, y: 13 },
      expected: { x: 10, y: 10 },
    },
    {
      name: "closed polygon interior",
      geometry: {
        kind: "polyline",
        closed: true,
        points: [
          { x: 0, y: 0 },
          { x: 30, y: 0 },
          { x: 30, y: 30 },
        ],
      },
      pointer: { x: 20, y: 10 },
      expected: { x: 20, y: 10 },
    },
  ])("projects $name in client pixels", ({ geometry, pointer, expected }) => {
    const { drag, targets } = setup();
    targets([candidate("geometry", geometry)]);
    const preview = drag.update(pointer);
    expect(preview.candidate?.context.id).toBe("geometry");
    expect(preview.position.x).toBeCloseTo(expected.x);
    expect(preview.position.y).toBeCloseTo(expected.y);
  });

  it.each<CommentSnapGeometry>([
    { kind: "rect", left: 0, top: 0, width: 0, height: 10 },
    { kind: "rect", left: 0, top: 0, width: 10, height: -1 },
    { kind: "rect", left: Number.NaN, top: 0, width: 10, height: 10 },
    { kind: "rect", left: Number.MAX_VALUE, top: 0, width: Number.MAX_VALUE, height: 10 },
    { kind: "point", x: Number.POSITIVE_INFINITY, y: 0 },
    { kind: "polyline", points: [] },
    { kind: "polyline", points: [{ x: 0, y: 0 }] },
    {
      kind: "polyline",
      points: [
        { x: 0, y: 0 },
        { x: 0, y: 0 },
      ],
    },
    {
      kind: "polyline",
      points: [
        { x: 0, y: 0 },
        { x: Number.NaN, y: 0 },
      ],
    },
    {
      kind: "polyline",
      closed: true,
      points: [
        { x: 0, y: 0 },
        { x: 10, y: 10 },
      ],
    },
  ])("ignores empty or invalid geometry: %j", (geometry) => {
    const { drag, targets } = setup();
    targets([candidate("invalid", geometry)]);
    expect(drag.update({ x: 0, y: 0 }).candidates).toEqual([]);
    expect(drag.preview.context).toBeNull();
    expect(drag.preview.position).toEqual({ x: 0, y: 0 });
  });
});
