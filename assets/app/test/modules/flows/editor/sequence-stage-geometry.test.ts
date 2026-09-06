import {
  layerGeometry,
  layerFrameStyle,
  moveLayer,
  resizeLayer,
  RESIZE_CORNERS,
  RESIZE_SIDES,
} from "@modules/flows/editor/lib/sequence-stage-geometry";

const geometry = { x: 0.5, y: 0.6, width: 0.4, height: 0.5 };

describe("sequence stage geometry", () => {
  it("supports positions outside the frame and sizes larger than the frame", () => {
    expect(
      layerGeometry({ id: 1, kind: "prop", url: "/prop.png", x: -2, y: 3, width: 4, height: 5 }),
    ).toEqual({ x: -2, y: 3, width: 4, height: 5 });
    expect(
      layerFrameStyle({ id: 1, kind: "prop", url: "/prop.png", x: -2, width: 4 }, 3),
    ).toMatchObject({ left: "-200%", width: "400%", zIndex: 3 });
    expect(moveLayer(geometry, -20, 20)).toEqual({ ...geometry, x: -10, y: 10 });
  });

  it.each(RESIZE_CORNERS)(
    "preserves proportions and the opposite corner when resizing %s",
    (corner) => {
      const anchor = { x: 0.5, y: 1 };
      const east = corner.endsWith("e");
      const south = corner.startsWith("s");
      const resized = resizeLayer(geometry, anchor, corner, east ? 0.1 : -0.1, south ? 0.1 : -0.1);
      expect(resized.width).toBeCloseTo(0.5);
      expect(resized.height).toBeCloseTo(0.625);
      expect(resized.width / resized.height).toBeCloseTo(geometry.width / geometry.height);
      const fixedX = (frame: typeof geometry) =>
        frame.x + ((east ? 0 : 1) - anchor.x) * frame.width;
      const fixedY = (frame: typeof geometry) =>
        frame.y + ((south ? 0 : 1) - anchor.y) * frame.height;
      expect(fixedX(resized)).toBeCloseTo(fixedX(geometry));
      expect(fixedY(resized)).toBeCloseTo(fixedY(geometry));
    },
  );

  it("respects limits without deforming or moving the fixed corner", () => {
    const frame = { x: -9.9, y: -9.9, width: 0.4, height: 0.5 };
    const resized = resizeLayer(frame, { x: 0, y: 0 }, "nw", -2, -2);
    expect(resized.x).toBeGreaterThanOrEqual(-10);
    expect(resized.y).toBe(-10);
    expect(resized.width / resized.height).toBeCloseTo(0.8);
    expect(resized.x + resized.width).toBeCloseTo(frame.x + frame.width);
    expect(resized.y + resized.height).toBeCloseTo(frame.y + frame.height);
    const huge = resizeLayer(geometry, { x: 0, y: 0 }, "se", 100, 100);
    expect(huge.height).toBe(20);
    expect(huge.width).toBe(16);
  });

  it.each(RESIZE_SIDES)("changes only the active dimension from side %s", (side) => {
    const anchor = { x: 0.25, y: 0.8 };
    const horizontal = side === "e" || side === "w";
    const resized = resizeLayer(
      geometry,
      anchor,
      side,
      side === "w" ? -0.1 : 0.1,
      side === "n" ? -0.1 : 0.1,
      false,
    );
    expect(resized.width).toBeCloseTo(geometry.width + (horizontal ? 0.1 : 0));
    expect(resized.height).toBeCloseTo(geometry.height + (horizontal ? 0 : 0.1));
    if (horizontal) {
      expect(resized.y).toBe(geometry.y);
      const opposite = (side === "e" ? 0 : 1) - anchor.x;
      expect(resized.x + opposite * resized.width).toBeCloseTo(
        geometry.x + opposite * geometry.width,
      );
    } else {
      expect(resized.x).toBe(geometry.x);
      const opposite = (side === "s" ? 0 : 1) - anchor.y;
      expect(resized.y + opposite * resized.height).toBeCloseTo(
        geometry.y + opposite * geometry.height,
      );
    }
  });

  it.each(RESIZE_SIDES)("preserves the opposite midpoint and proportion from side %s", (side) => {
    const anchor = { x: 0.25, y: 0.8 };
    const resized = resizeLayer(
      geometry,
      anchor,
      side,
      side === "w" ? -0.1 : 0.1,
      side === "n" ? -0.1 : 0.1,
    );
    const opposite = {
      n: { x: 0.5, y: 1 },
      e: { x: 0, y: 0.5 },
      s: { x: 0.5, y: 0 },
      w: { x: 1, y: 0.5 },
    }[side];
    const oppositeX = opposite.x - anchor.x;
    const oppositeY = opposite.y - anchor.y;
    expect(resized.width / resized.height).toBeCloseTo(geometry.width / geometry.height);
    expect(resized.x + oppositeX * resized.width).toBeCloseTo(
      geometry.x + oppositeX * geometry.width,
    );
    expect(resized.y + oppositeY * resized.height).toBeCloseTo(
      geometry.y + oppositeY * geometry.height,
    );
  });

  it("bounds side resizing without shifting its fixed edge", () => {
    const frame = { ...geometry, x: -9.9 };
    const limited = resizeLayer(frame, { x: 0, y: 0 }, "w", -100, 0, false);
    expect(limited.x).toBe(-10);
    expect(limited.width).toBeCloseTo(0.5);
    expect(limited.x + limited.width).toBeCloseTo(frame.x + frame.width);
    expect(resizeLayer(geometry, { x: 0, y: 0 }, "e", 100, 0, false).width).toBe(20);
    const minimum = resizeLayer(geometry, { x: 0, y: 0 }, "n", 0, 100, false);
    expect(minimum.height).toBeCloseTo(0.0001);
    expect(minimum.y + minimum.height).toBeCloseTo(geometry.y + geometry.height);
  });
});
