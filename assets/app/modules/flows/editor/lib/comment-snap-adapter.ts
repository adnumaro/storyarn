import type { AreaPlugin } from "rete-area-plugin";
import type {
  CommentMagneticAdapter,
  CommentSnapCandidate,
} from "@components/comments/commentMagnetism";
import { commentPointFromClient, commentScreenPoint } from "./comment-geometry";
import type { FlowAreaExtra, FlowSchemes } from "./rete-schemes";

/** Rete owns geometry; comments retain a Flow owner and an optional node reference. */
export function flowCommentSnapAdapter(
  area: AreaPlugin<FlowSchemes, FlowAreaExtra>,
  container: HTMLElement,
): CommentMagneticAdapter {
  return {
    candidates() {
      const viewport = container.getBoundingClientRect();
      const candidates: CommentSnapCandidate[] = [];
      for (const element of container.querySelectorAll<HTMLElement>("[data-flow-comment-node]")) {
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
  const sized = rect.width > 0 && rect.height > 0;
  const intersects =
    rect.right >= viewport.left &&
    rect.left <= viewport.right &&
    rect.bottom >= viewport.top &&
    rect.top <= viewport.bottom;
  return sized && intersects && !element.closest('[hidden], [aria-hidden="true"]');
}
