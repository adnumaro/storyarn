import type {
  CommentMagneticAdapter,
  CommentSnapCandidate,
} from "@components/comments/commentMagnetism";
import {
  commentPointFromClient,
  commentScreenPoint,
  contextualCommentPoint,
  type CommentNodeView,
  type CommentPoint,
  type CommentViewport,
  type ResolvableFlowCommentContext,
} from "./comment-geometry";

interface FlowCommentArea {
  area: { transform: CommentViewport };
  nodeViews: ReadonlyMap<string, CommentNodeView>;
}

const NODE_SELECTOR = "[data-flow-comment-node]";

/** Rete owns geometry; comments retain a Flow owner and an optional node reference. */
export function flowCommentSnapAdapter(
  area: FlowCommentArea,
  container: HTMLElement,
): CommentMagneticAdapter {
  return {
    candidates() {
      const viewport = container.getBoundingClientRect();
      const candidates: CommentSnapCandidate[] = [];
      for (const element of container.querySelectorAll<HTMLElement>(NODE_SELECTOR)) {
        const id = element.dataset.flowCommentNode;
        if (!id || !area.nodeViews.has(`node-${id}`)) continue;
        const rect = element.getBoundingClientRect();
        if (!visibleTarget(element, rect, viewport)) continue;
        candidates.push({
          context: { type: "flow_node", id },
          label: element.dataset.flowCommentLabel || id,
          geometry: {
            kind: "rect",
            left: rect.left,
            top: rect.top,
            width: rect.width,
            height: rect.height,
          },
        });
      }
      return candidates;
    },
    toScreen(position) {
      const rect = container.getBoundingClientRect();
      const point = commentScreenPoint(position, area.area.transform);
      return { x: point.x + rect.left, y: point.y + rect.top };
    },
    fromScreen(point) {
      return commentPointFromClient(point, container.getBoundingClientRect(), area.area.transform);
    },
    clamp(position) {
      return {
        x: Math.max(-10_000_000, Math.min(10_000_000, position.x)),
        y: Math.max(-10_000_000, Math.min(10_000_000, position.y)),
      };
    },
    context(candidate, position) {
      const node = area.nodeViews.get(`node-${candidate.context.id}`);
      return {
        type: candidate.context.type,
        id: candidate.context.id,
        offset: {
          x: position.x - (node?.position.x ?? 0),
          y: position.y - (node?.position.y ?? 0),
        },
      };
    },
  };
}

function visibleTarget(element: HTMLElement, rect: DOMRect, viewport: DOMRect): boolean {
  const intersects =
    rect.right > viewport.left &&
    rect.left < viewport.right &&
    rect.bottom > viewport.top &&
    rect.top < viewport.bottom;
  return intersects && renderedTarget(element, rect);
}

function renderedTarget(element: HTMLElement, rect = element.getBoundingClientRect()): boolean {
  if (element.closest('[hidden], [aria-hidden="true"], [inert]')) return false;
  if (
    ![rect.left, rect.top, rect.width, rect.height].every(Number.isFinite) ||
    rect.width <= 0 ||
    rect.height <= 0
  )
    return false;
  for (let parent: HTMLElement | null = element; parent; parent = parent.parentElement) {
    const style = getComputedStyle(parent);
    if (
      style.display === "none" ||
      ["hidden", "collapse"].includes(style.visibility) ||
      style.opacity === "0"
    )
      return false;
  }
  return true;
}

/** Offscreen or temporarily unmounted nodes still have authoritative Rete origins. */
export function resolveFlowCommentPosition(
  position: CommentPoint | null | undefined,
  context: ResolvableFlowCommentContext | null | undefined,
  area: FlowCommentArea,
  container: HTMLElement,
): CommentPoint | null {
  if (context?.type === "flow_node") {
    const target = container.querySelector<HTMLElement>(
      `[data-flow-comment-node="${CSS.escape(context.id)}"]`,
    );
    if (target && !renderedTarget(target)) return position ?? null;
  }
  return contextualCommentPoint(position, context, area.nodeViews);
}
