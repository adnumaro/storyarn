import type {
  CommentMagneticAdapter,
  CommentSnapCandidate,
} from "@components/comments/commentMagnetism";
import type { CommentContextReference, CommentPosition } from "@components/comments/types";
import {
  constrainSheetCommentPositionToSurface,
  sheetCommentSurfaceSize,
} from "./comment-geometry";

export const SHEET_COMMENT_TARGET_SELECTOR = "[data-sheet-comment-type][data-sheet-comment-id]";

const TARGET_TYPES = new Set([
  "sheet_cover",
  "sheet_header",
  "sheet_title",
  "sheet_block",
  "sheet_column_group",
]);

interface Bounds {
  left: number;
  top: number;
  right: number;
  bottom: number;
}

type ResolvableContext = CommentContextReference & { status?: "available" | "unavailable" };

function positionFromScreen(point: CommentPosition, container: HTMLElement): CommentPosition {
  const rect = container.getBoundingClientRect();
  const size = sheetCommentSurfaceSize(container);
  if (rect.width <= 0 || rect.height <= 0) return { x: 0, y: 0 };
  return {
    x: ((point.x - rect.left) / rect.width) * 100,
    y: ((point.y - rect.top) / rect.height) * size.height,
  };
}

function screenFromPosition(position: CommentPosition, container: HTMLElement): CommentPosition {
  const rect = container.getBoundingClientRect();
  const size = sheetCommentSurfaceSize(container);
  return {
    x: rect.left + (position.x / 100) * rect.width,
    y: rect.top + (size.height > 0 ? (position.y / size.height) * rect.height : 0),
  };
}

function clampPosition(position: CommentPosition, container: HTMLElement): CommentPosition {
  return constrainSheetCommentPositionToSurface(position, sheetCommentSurfaceSize(container));
}

function intersect(left: Bounds, right: Bounds): Bounds {
  return {
    left: Math.max(left.left, right.left),
    top: Math.max(left.top, right.top),
    right: Math.min(left.right, right.right),
    bottom: Math.min(left.bottom, right.bottom),
  };
}

function rendered(element: HTMLElement): boolean {
  if (element.closest('[hidden], [aria-hidden="true"], [inert]')) return false;
  for (let current: HTMLElement | null = element; current; current = current.parentElement) {
    const style = getComputedStyle(current);
    if (
      style.display === "none" ||
      style.visibility === "hidden" ||
      style.visibility === "collapse" ||
      style.opacity === "0"
    )
      return false;
  }
  const rect = element.getBoundingClientRect();
  return (
    [rect.left, rect.top, rect.width, rect.height].every(Number.isFinite) &&
    rect.width > 0 &&
    rect.height > 0
  );
}

function clipToAncestor(bounds: Bounds, parent: HTMLElement): Bounds {
  const style = getComputedStyle(parent);
  const clipX = /^(auto|scroll|hidden|clip)$/.test(style.overflowX || style.overflow);
  const clipY = /^(auto|scroll|hidden|clip)$/.test(style.overflowY || style.overflow);
  if (!clipX && !clipY) return bounds;
  const rect = parent.getBoundingClientRect();
  return intersect(bounds, {
    left: clipX ? rect.left : bounds.left,
    right: clipX ? rect.right : bounds.right,
    top: clipY ? rect.top : bounds.top,
    bottom: clipY ? rect.bottom : bounds.bottom,
  });
}

function visibleBounds(element: HTMLElement, container: HTMLElement): Bounds | null {
  if (!rendered(element)) return null;
  let bounds = intersect(element.getBoundingClientRect(), container.getBoundingClientRect());
  bounds = intersect(bounds, {
    left: 0,
    top: 0,
    right: window.innerWidth,
    bottom: window.innerHeight,
  });
  for (let parent = element.parentElement; parent; parent = parent.parentElement) {
    bounds = clipToAncestor(bounds, parent);
  }
  return bounds.right > bounds.left && bounds.bottom > bounds.top ? bounds : null;
}

function targets(container: HTMLElement): HTMLElement[] {
  return Array.from(container.querySelectorAll<HTMLElement>(SHEET_COMMENT_TARGET_SELECTOR)).filter(
    (element) =>
      TARGET_TYPES.has(element.dataset.sheetCommentType ?? "") &&
      Boolean(element.dataset.sheetCommentId) &&
      element.closest("[data-sheet-comment-surface]") === container,
  );
}

function targetForContext(
  context: CommentContextReference,
  container: HTMLElement,
): HTMLElement | undefined {
  return targets(container).find(
    (element) =>
      element.dataset.sheetCommentType === context.type &&
      element.dataset.sheetCommentId === context.id &&
      rendered(element),
  );
}

function targetOrigin(element: HTMLElement, container: HTMLElement): CommentPosition {
  const rect = element.getBoundingClientRect();
  return positionFromScreen({ x: rect.left, y: rect.top }, container);
}

/** Reads live geometry each time; optional references never change the owning sheet. */
export function sheetCommentSnapAdapter(container: HTMLElement): CommentMagneticAdapter {
  return {
    candidates() {
      const candidates: CommentSnapCandidate[] = [];
      for (const element of targets(container)) {
        const bounds = visibleBounds(element, container);
        if (!bounds) continue;
        candidates.push({
          context: {
            type: element.dataset.sheetCommentType!,
            id: element.dataset.sheetCommentId!,
          },
          label: element.dataset.sheetCommentLabel || element.dataset.sheetCommentId!,
          geometry: {
            kind: "rect",
            left: bounds.left,
            top: bounds.top,
            width: bounds.right - bounds.left,
            height: bounds.bottom - bounds.top,
          },
        });
      }
      return candidates;
    },
    toScreen: (position) => screenFromPosition(position, container),
    fromScreen: (point) => positionFromScreen(point, container),
    clamp: (position) => clampPosition(position, container),
    context(candidate, position) {
      const target = targetForContext(candidate.context, container);
      if (!target) return { ...candidate.context };
      const origin = targetOrigin(target, container);
      return {
        ...candidate.context,
        offset: { x: position.x - origin.x, y: position.y - origin.y },
      };
    },
  };
}

/** Hidden, deleted or unavailable targets keep the last saved absolute fallback. */
export function resolveSheetCommentPosition(
  position: CommentPosition,
  context: ResolvableContext | null | undefined,
  container: HTMLElement,
): CommentPosition {
  const fallback = () => clampPosition(position, container);
  if (
    !context ||
    context.status === "unavailable" ||
    !context.offset ||
    !Number.isFinite(context.offset.x) ||
    !Number.isFinite(context.offset.y)
  )
    return fallback();
  const target = targetForContext(context, container);
  if (!target) return fallback();
  const origin = targetOrigin(target, container);
  return clampPosition(
    { x: origin.x + context.offset.x, y: origin.y + context.offset.y },
    container,
  );
}
