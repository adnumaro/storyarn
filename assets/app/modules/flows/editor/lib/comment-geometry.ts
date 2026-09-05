import type { FlowCommentThread } from "../../types/comments";
export { commentPopoverPosition } from "@components/comments/commentGeometry";

export interface CommentPoint {
  x: number;
  y: number;
}

export interface CommentViewport extends CommentPoint {
  k: number;
}

export interface CommentNodeView {
  position: CommentPoint;
}

/** Rete stores sequence children in absolute canvas coordinates as well. */
export function commentCanvasPoint(
  thread: FlowCommentThread,
  views: ReadonlyMap<string, CommentNodeView>,
  position = thread.position,
): CommentPoint | null {
  if (thread.source.status !== "available") return null;
  if (thread.source.type === "flow_canvas") return position ?? null;
  const node = views.get(`node-${thread.source.id}`);
  if (!node) return null;
  // Older, node-only threads did not store an offset.
  const offset = position ?? { x: 16, y: 16 };
  return { x: node.position.x + offset.x, y: node.position.y + offset.y };
}

export function commentScreenPoint(point: CommentPoint, viewport: CommentViewport): CommentPoint {
  return { x: point.x * viewport.k + viewport.x, y: point.y * viewport.k + viewport.y };
}

export function commentPointFromClient(
  point: CommentPoint,
  rect: Pick<DOMRect, "left" | "top">,
  viewport: CommentViewport,
): CommentPoint {
  const zoom = viewport.k || 1;
  return {
    x: (point.x - rect.left - viewport.x) / zoom,
    y: (point.y - rect.top - viewport.y) / zoom,
  };
}

export function commentPlacement(
  point: CommentPoint,
  nodeId: number | null,
  views: ReadonlyMap<string, CommentNodeView>,
): { node_id: number | null; x: number; y: number } {
  const node = nodeId == null ? null : views.get(`node-${nodeId}`);
  return {
    node_id: node ? nodeId : null,
    x: point.x - (node?.position.x ?? 0),
    y: point.y - (node?.position.y ?? 0),
  };
}

export function draftCommentCanvasPoint(
  position: CommentPoint,
  nodeId: number | null,
  views: ReadonlyMap<string, CommentNodeView>,
): CommentPoint | null {
  if (nodeId == null) return position;
  const node = views.get(`node-${nodeId}`);
  if (!node) return null;
  return { x: position.x + node.position.x, y: position.y + node.position.y };
}
