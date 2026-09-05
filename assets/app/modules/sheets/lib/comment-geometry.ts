import type { SheetCommentPosition, SheetCommentThread } from "../types/comments";

export function clampSheetCommentPosition(position: SheetCommentPosition): SheetCommentPosition {
  return {
    x: Math.max(0, Math.min(100, position.x)),
    y: Math.max(0, Math.min(100, position.y)),
  };
}

export function sheetCommentPointFromClient(
  point: SheetCommentPosition,
  blockRect: Pick<DOMRect, "left" | "top" | "width" | "height">,
): SheetCommentPosition {
  if (blockRect.width <= 0 || blockRect.height <= 0) return { x: 0, y: 0 };

  return clampSheetCommentPosition({
    x: ((point.x - blockRect.left) / blockRect.width) * 100,
    y: ((point.y - blockRect.top) / blockRect.height) * 100,
  });
}

export function sheetCommentScreenPoint(
  thread: SheetCommentThread,
  container: HTMLElement,
  position = thread.position,
): SheetCommentPosition | null {
  if (
    thread.source.type !== "sheet_block" ||
    thread.source.status !== "available" ||
    !position ||
    !Number.isFinite(position.x) ||
    !Number.isFinite(position.y)
  )
    return null;

  return sheetCommentPositionForBlock(thread.source.id, position, container);
}

export function sheetCommentPositionForBlock(
  blockId: number,
  position: SheetCommentPosition,
  container: HTMLElement,
): SheetCommentPosition | null {
  const block = findSheetCommentBlock(container, blockId);
  if (!block) return null;

  const normalized = clampSheetCommentPosition(position);
  const containerRect = container.getBoundingClientRect();
  const blockRect = block.getBoundingClientRect();

  return {
    x: blockRect.left - containerRect.left + (blockRect.width * normalized.x) / 100,
    y: blockRect.top - containerRect.top + (blockRect.height * normalized.y) / 100,
  };
}

export function findSheetCommentBlock(container: HTMLElement, blockId: number): HTMLElement | null {
  return (
    Array.from(container.querySelectorAll<HTMLElement>("[data-sheet-block-id]")).find(
      (element) => element.dataset.sheetBlockId === String(blockId),
    ) ?? null
  );
}
