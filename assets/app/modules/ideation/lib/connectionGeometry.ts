import type { NoteBounds, Point } from "../composables/useCanvasViewport";
import type { CanvasPlacement, ConnectionChange, LinkDirection, NoteShape } from "../types";

export type ConnectionDirection = "up" | "right" | "down" | "left";

const GAP = 64;

function overlaps(a: NoteBounds, b: NoteBounds): boolean {
  return (
    a.x < b.x + b.width + GAP &&
    a.x + a.width + GAP > b.x &&
    a.y < b.y + b.height + GAP &&
    a.y + a.height + GAP > b.y
  );
}

function movePast(note: NoteBounds, obstacles: NoteBounds[], direction: ConnectionDirection) {
  switch (direction) {
    case "left":
      note.x = Math.min(...obstacles.map((other) => other.x)) - note.width - GAP;
      break;
    case "right":
      note.x = Math.max(...obstacles.map((other) => other.x + other.width)) + GAP;
      break;
    case "up":
      note.y = Math.min(...obstacles.map((other) => other.y)) - note.height - GAP;
      break;
    case "down":
      note.y = Math.max(...obstacles.map((other) => other.y + other.height)) + GAP;
      break;
  }
}

/** Keep the new idea outside the sources and find room without moving existing notes. */
export function connectedPlacement(
  sources: NoteBounds[],
  obstacles: NoteBounds[],
  direction: ConnectionDirection,
): Point | null {
  if (!sources.length) return null;
  const left = Math.min(...sources.map((note) => note.x));
  const top = Math.min(...sources.map((note) => note.y));
  const right = Math.max(...sources.map((note) => note.x + note.width));
  const bottom = Math.max(...sources.map((note) => note.y + note.height));
  const note = {
    x: (left + right) / 2 - 80,
    y: (top + bottom) / 2 - 22,
    width: 160,
    height: 44,
  };
  movePast(note, [{ x: left, y: top, width: right - left, height: bottom - top }], direction);

  // Each pass advances past an obstacle in the chosen direction. It cannot
  // encounter that obstacle again, so the search is bounded by the note count.
  for (let attempt = 0; attempt <= obstacles.length; attempt++) {
    const blocked = obstacles.filter((other) => overlaps(note, other));
    if (!blocked.length) return { x: note.x, y: note.y };
    movePast(note, blocked, direction);
  }
  return null;
}

interface ShapedNoteBounds extends NoteBounds {
  shape?: NoteShape;
}

function outlineIntersection(note: ShapedNoteBounds, dx: number, dy: number) {
  const x = Math.abs(dx) / (note.width / 2);
  const y = Math.abs(dy) / (note.height / 2);
  if (note.shape === "ellipse") return 1 / Math.hypot(x, y);
  if (note.shape === "diamond") return 1 / (x + y);
  return 1 / Math.max(x, y);
}

/** Arrow tips sit outside each visible shape, including when notes grow while typing. */
export function connectionEndpoints(source: ShapedNoteBounds, target: ShapedNoteBounds, gap = 6) {
  const a = { x: source.x + source.width / 2, y: source.y + source.height / 2 };
  const b = { x: target.x + target.width / 2, y: target.y + target.height / 2 };
  const dx = b.x - a.x;
  const dy = b.y - a.y;
  const distance = Math.hypot(dx, dy);
  if (!distance) return null;
  const from = outlineIntersection(source, dx, dy) + gap / distance;
  const to = 1 - outlineIntersection(target, dx, dy) - gap / distance;
  if (from >= to) return null;
  return { x1: a.x + dx * from, y1: a.y + dy * from, x2: a.x + dx * to, y2: a.y + dy * to };
}

export function readableViewport(
  rect: NoteBounds,
  view: { x: number; y: number; zoom: number; width: number; height: number },
) {
  const zoom = Math.max(view.zoom, 0.85);
  const marginX = Math.min(64, view.width / 8);
  const top = Math.min(96, view.height / 5);
  const bottom = Math.max(top + 1, view.height - 120);
  let x = view.x;
  let y = view.y;
  const left = x + rect.x * zoom;
  const right = left + rect.width * zoom;
  if (right > view.width - marginX) x -= right - (view.width - marginX);
  if (x + rect.x * zoom < marginX) x = marginX - rect.x * zoom;
  const floor = y + (rect.y + rect.height) * zoom;
  if (floor > bottom) y -= floor - bottom;
  if (y + rect.y * zoom < top) y = top - rect.y * zoom;
  return { x, y, zoom };
}

export interface DisplayConnection {
  key: string;
  source: number;
  target: number;
  direction: LinkDirection;
  edges: ConnectionChange[];
}

/** Reciprocal records represent one visible association while retaining their write identities. */
export function displayConnections(
  notes: Array<{ id: number; canvas?: CanvasPlacement }>,
): DisplayConnection[] {
  const visible = new Set(notes.map((note) => note.id));
  const pairs = new Map<string, DisplayConnection>();
  for (const note of notes) {
    for (const target of note.canvas?.links ?? []) {
      if (target === note.id || !visible.has(target)) continue;
      appendDisplayConnection(pairs, note, target);
    }
  }
  return [...pairs.values()];
}

function appendDisplayConnection(
  pairs: Map<string, DisplayConnection>,
  note: { id: number; canvas?: CanvasPlacement },
  target: number,
) {
  const sourceId = Math.min(note.id, target);
  const targetId = Math.max(note.id, target);
  const key = `${sourceId}-${targetId}`;
  const direction = note.canvas?.link_directions?.[target] ?? "forward";
  const edge = { source_id: note.id, target_id: target, connected: true, direction };
  const relative = note.id === sourceId ? direction : reverseDirection(direction);
  const pair = pairs.get(key);
  if (pair) {
    pair.edges.push(edge);
    pair.direction = combineDirections(pair.direction, relative);
  } else {
    pairs.set(key, {
      key,
      source: sourceId,
      target: targetId,
      direction: relative,
      edges: [edge],
    });
  }
}

function reverseDirection(direction: LinkDirection): LinkDirection {
  if (direction === "forward") return "backward";
  if (direction === "backward") return "forward";
  return direction;
}

function combineDirections(a: LinkDirection, b: LinkDirection): LinkDirection {
  const forward = [a, b].some((direction) => direction === "forward" || direction === "both");
  const backward = [a, b].some((direction) => direction === "backward" || direction === "both");
  if (forward && backward) return "both";
  if (forward) return "forward";
  if (backward) return "backward";
  return "none";
}

export function connectionStyleChanges(
  connection: DisplayConnection,
  direction: LinkDirection,
): ConnectionChange[] {
  const changes: ConnectionChange[] = [
    {
      source_id: connection.source,
      target_id: connection.target,
      connected: true,
      direction,
    },
  ];
  for (const edge of connection.edges) {
    if (edge.source_id !== connection.source) changes.push({ ...edge, connected: false });
  }
  return changes;
}

export function noteContainsPoint(note: ShapedNoteBounds, point: Point): boolean {
  const dx = Math.abs(point.x - note.x - note.width / 2) / (note.width / 2);
  const dy = Math.abs(point.y - note.y - note.height / 2) / (note.height / 2);
  if (note.shape === "ellipse") return dx * dx + dy * dy <= 1;
  if (note.shape === "diamond") return dx + dy <= 1;
  return dx <= 1 && dy <= 1;
}
