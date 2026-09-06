import type { SequenceVisualLayer } from "@modules/flows/sequence/types";
import { finiteValue } from "@modules/flows/sequence/numbers";

export { finiteValue };

export interface LayerGeometry {
  x: number;
  y: number;
  width: number;
  height: number;
}

export type ResizeCorner = "nw" | "ne" | "sw" | "se";
export type ResizeSide = "n" | "e" | "s" | "w";
export type ResizeHandle = ResizeCorner | ResizeSide;
export const RESIZE_CORNERS: ResizeCorner[] = ["nw", "ne", "sw", "se"];
export const RESIZE_SIDES: ResizeSide[] = ["n", "e", "s", "w"];

interface ResizeAxis {
  position: number;
  size: number;
  factor: number;
  change: number;
}

export function clamp(value: number, min: number, max: number): number {
  return Math.min(max, Math.max(min, value));
}

export function layerGeometry(layer: SequenceVisualLayer): LayerGeometry {
  return {
    x: clamp(finiteValue(layer.x, 0), -10, 10),
    y: clamp(finiteValue(layer.y, 0), -10, 10),
    width: Math.max(Number.EPSILON, finiteValue(layer.width, 1)),
    height: Math.max(Number.EPSILON, finiteValue(layer.height, 1)),
  };
}

export function layerAnchor(layer: SequenceVisualLayer) {
  return {
    x: clamp(finiteValue(layer.anchor_x ?? layer.anchorX, 0), 0, 1),
    y: clamp(finiteValue(layer.anchor_y ?? layer.anchorY, 0), 0, 1),
  };
}

export function moveLayer(geometry: LayerGeometry, dx: number, dy: number): LayerGeometry {
  return { ...geometry, x: clamp(geometry.x + dx, -10, 10), y: clamp(geometry.y + dy, -10, 10) };
}

/** Keep the opposite corner, or a side's opposite midpoint, fixed while resizing. */
export function resizeLayer(
  geometry: LayerGeometry,
  anchor: { x: number; y: number },
  handle: ResizeHandle,
  dx: number,
  dy: number,
  keepProportions = true,
): LayerGeometry {
  const horizontal = Number(handle.includes("e")) - Number(handle.includes("w"));
  const vertical = Number(handle.includes("s")) - Number(handle.includes("n"));
  const xAxis = resizeAxis(geometry.x, geometry.width, anchor.x, horizontal, dx);
  const yAxis = resizeAxis(geometry.y, geometry.height, anchor.y, vertical, dy);
  const change = Math.abs(xAxis.change) >= Math.abs(yAxis.change) ? xAxis.change : yAxis.change;
  const proportional = keepProportions || (horizontal && vertical);
  let scaleX = 1;
  let scaleY = 1;
  if (proportional) {
    scaleX = constrainScale(1 + change, [xAxis, yAxis]);
    scaleY = scaleX;
  } else {
    if (horizontal) scaleX = constrainScale(1 + change, [xAxis]);
    if (vertical) scaleY = constrainScale(1 + change, [yAxis]);
  }

  return {
    x: geometry.x + xAxis.factor * (scaleX - 1),
    y: geometry.y + yAxis.factor * (scaleY - 1),
    width: geometry.width * scaleX,
    height: geometry.height * scaleY,
  };
}

function resizeAxis(
  position: number,
  size: number,
  anchor: number,
  direction: number,
  delta: number,
): ResizeAxis {
  // The fixed point is the opposite edge, or the midpoint on an inactive axis.
  const opposite = (1 - direction) / 2;
  return { position, size, factor: (anchor - opposite) * size, change: (delta / size) * direction };
}

function constrainScale(scale: number, axes: ResizeAxis[]): number {
  let minimum = 0;
  let maximum = Infinity;
  // Bound scale rather than clamping coordinates, which would move the fixed point.
  for (const { position, size, factor } of axes) {
    minimum = Math.max(minimum, 0.0001 / size);
    maximum = Math.min(maximum, 20 / size);
    if (factor === 0) continue;
    const first = 1 + (-10 - position) / factor;
    const second = 1 + (10 - position) / factor;
    minimum = Math.max(minimum, Math.min(first, second));
    maximum = Math.min(maximum, Math.max(first, second));
  }

  return clamp(scale, minimum, maximum);
}

export function changedGeometry(
  previous: LayerGeometry,
  current: LayerGeometry,
): Partial<LayerGeometry> {
  const changes: Partial<LayerGeometry> = {};
  for (const field of ["x", "y", "width", "height"] as const) {
    const value = Math.round(current[field] * 10_000) / 10_000;
    if (value !== Math.round(previous[field] * 10_000) / 10_000) changes[field] = value;
  }
  return changes;
}

export function layerFrameStyle(layer: SequenceVisualLayer, stackIndex: number) {
  const geometry = layerGeometry(layer);
  const anchor = layerAnchor(layer);
  return {
    left: `${geometry.x * 100}%`,
    top: `${geometry.y * 100}%`,
    width: `${geometry.width * 100}%`,
    height: `${geometry.height * 100}%`,
    transform: `translate(${-anchor.x * 100}%, ${-anchor.y * 100}%)`,
    zIndex: stackIndex,
  };
}
