import type { NoteBounds, Point } from "../composables/useCanvasViewport";

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
    x: (left + right) / 2 - 140,
    y: (top + bottom) / 2 - 130,
    width: 280,
    height: 260,
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

/** Arrow tips sit outside the destination, including when notes grow while typing. */
export function connectionEndpoints(source: NoteBounds, target: NoteBounds, gap = 6) {
  const a = { x: source.x + source.width / 2, y: source.y + source.height / 2 };
  const b = { x: target.x + target.width / 2, y: target.y + target.height / 2 };
  const dx = b.x - a.x;
  const dy = b.y - a.y;
  const distance = Math.hypot(dx, dy);
  if (!distance) return null;
  const edge = (rect: NoteBounds) =>
    Math.min(
      dx ? rect.width / 2 / Math.abs(dx) : Infinity,
      dy ? rect.height / 2 / Math.abs(dy) : Infinity,
    );
  const from = edge(source) + gap / distance;
  const to = 1 - edge(target) - gap / distance;
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
