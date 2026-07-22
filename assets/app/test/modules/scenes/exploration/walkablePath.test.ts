import { describe, expect, it } from "vitest";
import {
  findShortestWalkablePath,
  isPointInWalkableArea,
  isSegmentInWalkableArea,
} from "../../../../modules/scenes/exploration/lib/walkablePath";
import type {
  ExplorationZone,
  PixelPoint,
  Vertex,
} from "../../../../modules/scenes/exploration/types";

function zone(vertices: Vertex[], id = "zone-1"): ExplorationZone {
  return {
    id,
    actionType: "walkable",
    isWalkable: true,
    vertices,
    visibility: "visible",
  };
}

function routeLength(start: PixelPoint, route: PixelPoint[]): number {
  let current = start;
  let total = 0;

  for (const point of route) {
    total += Math.hypot(point.x - current.x, point.y - current.y);
    current = point;
  }

  return total;
}

describe("walkable pathfinding", () => {
  it("uses the direct segment when it remains inside a convex polygon", () => {
    const polygon = zone([
      { x: 0, y: 0 },
      { x: 10, y: 0 },
      { x: 10, y: 10 },
      { x: 0, y: 10 },
    ]);
    const target = { x: 9, y: 9 };

    expect(findShortestWalkablePath({ x: 1, y: 1 }, target, [polygon])).toEqual([target]);
  });

  it("routes around a concavity using the shortest visible polygon vertices", () => {
    const polygon = zone([
      { x: 0, y: 0 },
      { x: 10, y: 0 },
      { x: 10, y: 10 },
      { x: 7, y: 10 },
      { x: 7, y: 3 },
      { x: 3, y: 3 },
      { x: 3, y: 10 },
      { x: 0, y: 10 },
    ]);
    const start = { x: 1, y: 8 };
    const target = { x: 9, y: 8 };
    const route = findShortestWalkablePath(start, target, [polygon]);

    expect(route).toEqual([{ x: 3, y: 3 }, { x: 7, y: 3 }, target]);
    expect(routeLength(start, route || [])).toBeCloseTo(14.7703, 4);

    let segmentStart = start;
    for (const waypoint of route || []) {
      expect(isSegmentInWalkableArea(segmentStart, waypoint, [polygon])).toBe(true);
      segmentStart = waypoint;
    }
  });

  it("returns no route when the target is in a disconnected walkable polygon", () => {
    const left = zone(
      [
        { x: 0, y: 0 },
        { x: 4, y: 0 },
        { x: 4, y: 4 },
        { x: 0, y: 4 },
      ],
      "left",
    );
    const right = zone(
      [
        { x: 6, y: 0 },
        { x: 10, y: 0 },
        { x: 10, y: 4 },
        { x: 6, y: 4 },
      ],
      "right",
    );

    expect(findShortestWalkablePath({ x: 1, y: 1 }, { x: 9, y: 1 }, [left, right])).toBeNull();
  });

  it("treats polygon edges as walkable", () => {
    const polygon = zone([
      { x: 0, y: 0 },
      { x: 10, y: 0 },
      { x: 10, y: 10 },
      { x: 0, y: 10 },
    ]);

    expect(isPointInWalkableArea({ x: 0, y: 5 }, [polygon])).toBe(true);
    expect(isSegmentInWalkableArea({ x: 0, y: 1 }, { x: 0, y: 9 }, [polygon])).toBe(true);
  });

  it("does not treat a repeated adjacent vertex as containing every point", () => {
    const polygon = zone([
      { x: 0, y: 0 },
      { x: 10, y: 0 },
      { x: 10, y: 0 },
      { x: 10, y: 10 },
      { x: 0, y: 10 },
    ]);

    expect(isPointInWalkableArea({ x: 50, y: 50 }, [polygon])).toBe(false);
    expect(isSegmentInWalkableArea({ x: 1, y: 1 }, { x: 50, y: 50 }, [polygon])).toBe(false);
  });

  it("crosses between overlapping walkable polygons", () => {
    const left = zone(
      [
        { x: 0, y: 0 },
        { x: 6, y: 0 },
        { x: 6, y: 6 },
        { x: 0, y: 6 },
      ],
      "left",
    );
    const right = zone(
      [
        { x: 4, y: 4 },
        { x: 10, y: 4 },
        { x: 10, y: 10 },
        { x: 4, y: 10 },
      ],
      "right",
    );

    expect(findShortestWalkablePath({ x: 1, y: 1 }, { x: 9, y: 9 }, [left, right])).toEqual([
      { x: 9, y: 9 },
    ]);
  });

  it("deduplicates candidates from many overlapping polygons", () => {
    const vertices = [
      { x: 0, y: 0 },
      { x: 10, y: 0 },
      { x: 10, y: 10 },
      { x: 7, y: 10 },
      { x: 7, y: 3 },
      { x: 3, y: 3 },
      { x: 3, y: 10 },
      { x: 0, y: 10 },
    ];
    const polygons = Array.from({ length: 40 }, (_, index) => zone(vertices, `zone-${index}`));
    const target = { x: 9, y: 8 };

    expect(findShortestWalkablePath({ x: 1, y: 8 }, target, polygons)).toEqual([
      { x: 3, y: 3 },
      { x: 7, y: 3 },
      target,
    ]);
  });

  it("rejects non-finite and oversized coordinates", () => {
    const polygon = zone([
      { x: 0, y: 0 },
      { x: 10, y: 0 },
      { x: Number.POSITIVE_INFINITY, y: 10 },
      { x: 0, y: 10 },
    ]);

    expect(isPointInWalkableArea({ x: 1, y: 1 }, [polygon])).toBe(false);
    expect(findShortestWalkablePath({ x: 1, y: 1 }, { x: 2, y: 2 }, [polygon])).toBeNull();
    expect(findShortestWalkablePath({ x: Number.NaN, y: 1 }, { x: 2, y: 2 }, [])).toBeNull();
  });

  it("rejects a zone whose vertex count exceeds the pathfinding budget", () => {
    const vertices = Array.from({ length: 1_025 }, (_, index) => {
      const angle = (index / 1_025) * Math.PI * 2;
      return { x: Math.cos(angle) * 100, y: Math.sin(angle) * 100 };
    });

    expect(findShortestWalkablePath({ x: 0, y: 0 }, { x: 10, y: 10 }, [zone(vertices)])).toBeNull();
  });

  it("rejects oversized polygon lists before scanning malformed entries", () => {
    let vertexReads = 0;
    const polygons = Array.from({ length: 1_025 }, () => ({
      get vertices() {
        vertexReads += 1;
        return [];
      },
    }));

    expect(findShortestWalkablePath({ x: 0, y: 0 }, { x: 10, y: 10 }, polygons)).toBeNull();
    expect(vertexReads).toBe(0);
  });
});
