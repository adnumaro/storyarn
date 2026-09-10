import { describe, expect, it } from "vitest";
import {
  connectedPlacement,
  connectionEndpoints,
  readableViewport,
} from "@modules/ideation/lib/connectionGeometry";

describe("connected note placement", () => {
  const source = { x: 100, y: 200, width: 280, height: 600 };

  it.each([
    ["up", { x: 100, y: -124 }],
    ["right", { x: 444, y: 370 }],
    ["down", { x: 100, y: 864 }],
    ["left", { x: -244, y: 370 }],
  ] as const)("places a connected note %s using the measured source height", (direction, point) => {
    expect(connectedPlacement([source], [source], direction)).toEqual(point);
  });

  it("places one destination beyond the entire selection and skips occupied positions", () => {
    const second = { x: 800, y: 400, width: 400, height: 300 };
    const obstacle = { x: 1240, y: 300, width: 280, height: 600 };
    expect(connectedPlacement([source, second], [source, second, obstacle], "right")).toEqual({
      x: 1584,
      y: 370,
    });
  });

  it("advances past several obstacles without rearranging them", () => {
    const obstacles = [
      source,
      { x: 444, y: 200, width: 280, height: 600 },
      { x: 788, y: 200, width: 280, height: 600 },
    ];
    const before = structuredClone(obstacles);
    expect(connectedPlacement([source], obstacles, "right")).toEqual({ x: 1132, y: 370 });
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
