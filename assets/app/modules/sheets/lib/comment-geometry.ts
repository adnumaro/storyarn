import type { SheetCommentPosition, SheetCommentThread } from "../types/comments";

export const SHEET_COMMENT_PIN_RADIUS = 16;

export function clampSheetCommentPosition(position: SheetCommentPosition): SheetCommentPosition {
  return {
    x: Math.max(0, Math.min(100, position.x)),
    y: Math.max(0, position.y),
  };
}

function centerBounds(size: number, inset: number): { min: number; max: number } {
  const center = Math.max(0, size / 2);
  return size >= inset * 2 ? { min: inset, max: size - inset } : { min: center, max: center };
}

function clampCenter(value: number, size: number, inset: number): number {
  const bounds = centerBounds(size, inset);
  return Math.max(bounds.min, Math.min(bounds.max, value));
}

export function sheetCommentPointFromClient(
  point: SheetCommentPosition,
  surfaceRect: Pick<DOMRect, "left" | "top" | "width" | "height">,
  inset = SHEET_COMMENT_PIN_RADIUS,
): SheetCommentPosition {
  if (surfaceRect.width <= 0 || surfaceRect.height <= 0) return { x: 0, y: 0 };

  const x = clampCenter(point.x - surfaceRect.left, surfaceRect.width, inset);
  const y = clampCenter(point.y - surfaceRect.top, surfaceRect.height, inset);

  return { x: (x / surfaceRect.width) * 100, y };
}

export function sheetCommentCanvasPoint(
  thread: SheetCommentThread,
  position = thread.position,
): SheetCommentPosition | null {
  if (
    thread.source.type !== "sheet_canvas" ||
    thread.source.status !== "available" ||
    !position ||
    !Number.isFinite(position.x) ||
    !Number.isFinite(position.y)
  )
    return null;

  return clampSheetCommentPosition(position);
}

export function sheetCommentScreenPoint(
  thread: SheetCommentThread,
  container: HTMLElement,
  position = thread.position,
): SheetCommentPosition | null {
  const normalized = sheetCommentCanvasPoint(thread, position);
  if (!normalized) return null;
  return sheetCommentPositionForSurface(normalized, container);
}

export function sheetCommentPositionForSurface(
  position: SheetCommentPosition,
  container: HTMLElement,
  inset = SHEET_COMMENT_PIN_RADIUS,
): SheetCommentPosition {
  const normalized = clampSheetCommentPosition(position);
  const surfaceRect = container.getBoundingClientRect();

  return {
    x: clampCenter((surfaceRect.width * normalized.x) / 100, surfaceRect.width, inset),
    y: clampCenter(normalized.y, surfaceRect.height, inset),
  };
}

export function constrainSheetCommentPositionToSurface(
  position: SheetCommentPosition,
  surfaceRect: Pick<DOMRect, "width" | "height">,
  inset = SHEET_COMMENT_PIN_RADIUS,
): SheetCommentPosition {
  if (surfaceRect.width <= 0 || surfaceRect.height <= 0) return { x: 0, y: 0 };

  const normalized = clampSheetCommentPosition(position);
  const x = clampCenter((surfaceRect.width * normalized.x) / 100, surfaceRect.width, inset);
  const y = clampCenter(normalized.y, surfaceRect.height, inset);
  return { x: (x / surfaceRect.width) * 100, y };
}
