import { describe, expect, it } from "vitest";
import {
  connectedPlacement,
  connectionEndpoints,
  displayConnections,
  connectionStyleChanges,
  noteContainsPoint,
  readableViewport,
} from "@modules/ideation/lib/connectionGeometry";
import type { NoteShape } from "@modules/ideation/types";

describe("connected note placement", () => {
  const source = { x: 100, y: 200, width: 280, height: 600 };

  it.each([
    ["up", { x: 160, y: 92 }],
    ["right", { x: 444, y: 478 }],
    ["down", { x: 160, y: 864 }],
    ["left", { x: -124, y: 478 }],
  ] as const)("places a connected note %s using the measured source height", (direction, point) => {
    expect(connectedPlacement([source], [source], direction)).toEqual(point);
  });

  it("places one destination beyond the entire selection and skips occupied positions", () => {
    const second = { x: 800, y: 400, width: 400, height: 300 };
    const obstacle = { x: 1240, y: 300, width: 280, height: 600 };
    expect(connectedPlacement([source, second], [source, second, obstacle], "right")).toEqual({
      x: 1584,
      y: 478,
    });
  });

  it("advances past several obstacles without rearranging them", () => {
    const obstacles = [
      source,
      { x: 444, y: 200, width: 280, height: 600 },
      { x: 788, y: 200, width: 280, height: 600 },
    ];
    const before = structuredClone(obstacles);
    expect(connectedPlacement([source], obstacles, "right")).toEqual({ x: 1132, y: 478 });
    expect(obstacles).toEqual(before);
    expect(connectedPlacement([], obstacles, "right")).toBeNull();
  });
});

describe("visible connection direction", () => {
  it("terminates at the measured edges, leaving the arrow outside the destination", () => {
    expect(
      connectionEndpoints(
        { x: 0, y: 0, width: 280, height: 600 },
        { x: 600, y: 0, width: 280, height: 600 },
      ),
    ).toEqual({ x1: 286, y1: 300, x2: 594, y2: 300 });
    expect(
      connectionEndpoints(
        { x: 0, y: 0, width: 280, height: 600 },
        { x: 0, y: 900, width: 280, height: 300 },
      ),
    ).toEqual({ x1: 140, y1: 606, x2: 140, y2: 894 });
  });

  it("does not draw an inverted line between overlapping or coincident notes", () => {
    const note = { x: 0, y: 0, width: 280, height: 260 };
    expect(connectionEndpoints(note, note)).toBeNull();
    expect(connectionEndpoints(note, { ...note, x: 20 })).toBeNull();
  });

  it.each<NoteShape>(["rectangle", "ellipse", "diamond"])(
    "meets both %s outlines along diagonal connections with different dimensions",
    (shape) => {
      const source = { x: 50, y: -100, width: 280, height: 600, shape };
      const target = { x: 600, y: 1000, width: 480, height: 260, shape };
      const line = connectionEndpoints(source, target, 0)!;
      const boundary = (x: number, y: number, note: typeof source) => {
        const dx = Math.abs((x - note.x - note.width / 2) / (note.width / 2));
        const dy = Math.abs((y - note.y - note.height / 2) / (note.height / 2));
        if (shape === "ellipse") return dx * dx + dy * dy;
        if (shape === "diamond") return dx + dy;
        return Math.max(dx, dy);
      };
      expect(boundary(line.x1, line.y1, source)).toBeCloseTo(1, 10);
      expect(boundary(line.x2, line.y2, target)).toBeCloseTo(1, 10);

      const spaced = connectionEndpoints(source, target, 12)!;
      expect(Math.hypot(spaced.x1 - line.x1, spaced.y1 - line.y1)).toBeCloseTo(12, 10);
      expect(Math.hypot(spaced.x2 - line.x2, spaced.y2 - line.y2)).toBeCloseTo(12, 10);
    },
  );

  it("uses each endpoint's shape independently", () => {
    const source = { x: 0, y: 0, width: 200, height: 200, shape: "ellipse" as const };
    const target = { x: 400, y: 400, width: 200, height: 200, shape: "diamond" as const };
    const line = connectionEndpoints(source, target, 0)!;
    expect(line.x1).toBeCloseTo(100 + 100 / Math.sqrt(2), 10);
    expect(line.y1).toBeCloseTo(line.x1, 10);
    expect(line.x2).toBeCloseTo(450, 10);
    expect(line.y2).toBeCloseTo(450, 10);
  });

  it("keeps a diagonal connection visible when only the shapes' bounding boxes overlap", () => {
    const note = { x: 0, y: 0, width: 200, height: 200, shape: "diamond" as const };
    expect(connectionEndpoints(note, { ...note, x: 150, y: 150 }, 0)).toEqual({
      x1: 150,
      y1: 150,
      x2: 200,
      y2: 200,
    });
    expect(connectionEndpoints(note, { ...note, x: 50, y: 50 }, 0)).toBeNull();
  });
});

describe("reveal connected note for editing", () => {
  const view = { x: 0, y: 0, zoom: 1, width: 1000, height: 800 };
  it("keeps a readable visible note in place and pans only as far as necessary", () => {
    expect(readableViewport({ x: 100, y: 200, width: 280, height: 260 }, view)).toEqual({
      x: 0,
      y: 0,
      zoom: 1,
    });
    expect(readableViewport({ x: 1000, y: 200, width: 280, height: 260 }, view)).toEqual({
      x: -344,
      y: 0,
      zoom: 1,
    });
  });
  it("restores a readable zoom and prioritizes the beginning of an overlong note", () => {
    const result = readableViewport(
      { x: 100, y: 2000, width: 280, height: 2000 },
      { ...view, zoom: 0.25 },
    );
    expect(result.zoom).toBe(0.85);
    expect(result.y + 2000 * result.zoom).toBe(96);
    expect(result.x + 100 * result.zoom).toBeGreaterThanOrEqual(64);
  });
});

describe("association projection", () => {
  it("keeps legacy arrows and combines reciprocal records into one visible association", () => {
    const [line] = displayConnections([
      { id: 10, canvas: { links: [11, 12] } },
      { id: 11, canvas: { links: [10] } },
    ]);
    expect(line).toMatchObject({ key: "10-11", source: 10, target: 11, direction: "both" });
    expect(line.edges).toHaveLength(2);
    expect(connectionStyleChanges(line, "none")).toEqual([
      { source_id: 10, target_id: 11, connected: true, direction: "none" },
      { source_id: 11, target_id: 10, connected: false, direction: "forward" },
    ]);
  });

  it("normalizes arrow direction relative to the displayed endpoints while retaining persisted IDs", () => {
    for (const [direction, visible] of [
      ["none", "none"],
      ["forward", "backward"],
      ["backward", "forward"],
      ["both", "both"],
    ] as const) {
      const [line] = displayConnections([
        { id: 10 },
        { id: 11, canvas: { links: [10], link_directions: { 10: direction } } },
      ]);
      expect(line.direction).toBe(visible);
      expect(line.edges).toEqual([{ source_id: 11, target_id: 10, connected: true, direction }]);
    }
  });

  it("has no arrows on an explicitly plain association and hides unreadable endpoints", () => {
    const lines = displayConnections([
      { id: 10, canvas: { links: [11, 12], link_directions: { 11: "none" } } },
      { id: 11 },
    ]);
    expect(lines).toHaveLength(1);
    expect(lines[0].direction).toBe("none");
  });
});

describe("note drop target", () => {
  const bounds = { x: 100, y: 100, width: 200, height: 100 };
  it("hits only the visible shape, including plain text bounds", () => {
    expect(noteContainsPoint({ ...bounds, shape: "plain" }, { x: 105, y: 105 })).toBe(true);
    expect(noteContainsPoint({ ...bounds, shape: "ellipse" }, { x: 105, y: 105 })).toBe(false);
    expect(noteContainsPoint({ ...bounds, shape: "diamond" }, { x: 105, y: 105 })).toBe(false);
    for (const shape of ["plain", "rectangle", "ellipse", "diamond"] as const) {
      expect(noteContainsPoint({ ...bounds, shape }, { x: 200, y: 150 })).toBe(true);
      expect(noteContainsPoint({ ...bounds, shape }, { x: 310, y: 150 })).toBe(false);
    }
  });
});
