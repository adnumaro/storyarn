import type { CommentPosition } from "./types";

export function commentPopoverPosition(
  point: CommentPosition,
  bounds: { width: number; height: number },
  size: { width: number; height: number },
): CommentPosition {
  const margin = 12;
  const right = point.x + 24;
  const x = right + size.width <= bounds.width - margin ? right : point.x - size.width - 24;

  return {
    x: Math.max(margin, Math.min(x, bounds.width - size.width - margin)),
    y: Math.max(margin, Math.min(point.y - 18, bounds.height - size.height - margin)),
  };
}
