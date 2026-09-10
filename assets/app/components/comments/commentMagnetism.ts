import type { CommentContextReference, CommentPosition } from "./types";

export type { CommentContextReference } from "./types";

export type CommentSnapGeometry =
  | { kind: "rect"; left: number; top: number; width: number; height: number }
  | { kind: "point"; x: number; y: number }
  | { kind: "polyline"; points: CommentPosition[]; closed?: boolean };

export interface CommentSnapCandidate {
  context: CommentContextReference;
  label: string;
  /** Geometry is always in current client pixels, independent of canvas zoom. */
  geometry: CommentSnapGeometry;
  priority?: number;
}

export interface CommentMagneticAdapter {
  /** null means unsupported; an empty list means supported with no nearby targets. */
  candidates(): readonly CommentSnapCandidate[] | null;
  toScreen(position: CommentPosition): CommentPosition;
  fromScreen(point: CommentPosition): CommentPosition;
  clamp(position: CommentPosition): CommentPosition;
  context(candidate: CommentSnapCandidate, position: CommentPosition): CommentContextReference;
  moveContext?(
    context: CommentContextReference,
    position: CommentPosition,
  ): CommentContextReference;
}

export interface CommentMagneticInitial {
  position: CommentPosition;
  context: CommentContextReference | null;
}

export interface CommentMagneticPreview extends CommentMagneticInitial {
  candidate: CommentSnapCandidate | null;
  candidates: readonly CommentSnapCandidate[];
  screen: CommentPosition;
}

export const COMMENT_SNAP_ENTER_PX = 18;
export const COMMENT_SNAP_EXIT_PX = 28;

interface MeasuredCandidate {
  candidate: CommentSnapCandidate;
  key: string;
  screen: CommentPosition;
  distance: number;
  area: number;
}

function finitePoint(point: CommentPosition): boolean {
  return Number.isFinite(point.x) && Number.isFinite(point.y);
}

function copyContext(context: CommentContextReference): CommentContextReference {
  return {
    ...context,
    ...(context.offset ? { offset: { ...context.offset } } : {}),
  };
}

function copyInitial(initial: CommentMagneticInitial): CommentMagneticInitial {
  return {
    position: { ...initial.position },
    context: initial.context ? copyContext(initial.context) : null,
  };
}

function copyCandidate(candidate: CommentSnapCandidate): CommentSnapCandidate {
  return {
    ...candidate,
    context: copyContext(candidate.context),
    geometry:
      candidate.geometry.kind === "polyline"
        ? {
            ...candidate.geometry,
            points: candidate.geometry.points.map((point) => ({ ...point })),
          }
        : { ...candidate.geometry },
  };
}

function contextKey(context: CommentContextReference): string {
  return JSON.stringify([context.type, context.id]);
}

function segmentProjection(
  point: CommentPosition,
  start: CommentPosition,
  end: CommentPosition,
): CommentPosition {
  const dx = end.x - start.x;
  const dy = end.y - start.y;
  const length = Math.hypot(dx, dy);
  if (length === 0) return { ...start };

  const ux = dx / length;
  const uy = dy / length;
  const along = Math.max(0, Math.min(length, (point.x - start.x) * ux + (point.y - start.y) * uy));
  return { x: start.x + along * ux, y: start.y + along * uy };
}

function insidePolygon(point: CommentPosition, points: CommentPosition[]): boolean {
  let inside = false;
  for (let index = 0, previous = points.length - 1; index < points.length; previous = index++) {
    const start = points[previous];
    const end = points[index];
    if (
      start.y > point.y !== end.y > point.y &&
      point.x < ((end.x - start.x) * (point.y - start.y)) / (end.y - start.y) + start.x
    ) {
      inside = !inside;
    }
  }
  return inside;
}

function nearestPolylinePoint(
  point: CommentPosition,
  points: CommentPosition[],
  closed = false,
): CommentPosition | null {
  let closest: CommentPosition | null = null;
  let distance = Number.POSITIVE_INFINITY;
  const segments = closed ? points.length : points.length - 1;
  for (let index = 0; index < segments; index++) {
    const start = points[index];
    const end = points[(index + 1) % points.length];
    if (start.x === end.x && start.y === end.y) continue;
    const projected = segmentProjection(point, start, end);
    const nextDistance = Math.hypot(point.x - projected.x, point.y - projected.y);
    if (nextDistance < distance) {
      closest = projected;
      distance = nextDistance;
    }
  }
  return closest;
}

function polylineProjection(
  point: CommentPosition,
  geometry: Extract<CommentSnapGeometry, { kind: "polyline" }>,
): { screen: CommentPosition; area: number } | null {
  const { points, closed } = geometry;
  if (points.length < (closed ? 3 : 2) || !points.every(finitePoint)) return null;

  const closest = nearestPolylinePoint(point, points, closed);
  if (!closest || !finitePoint(closest)) return null;
  const bounds = points.reduce(
    (current, next) => ({
      left: Math.min(current.left, next.x),
      right: Math.max(current.right, next.x),
      top: Math.min(current.top, next.y),
      bottom: Math.max(current.bottom, next.y),
    }),
    { left: points[0].x, right: points[0].x, top: points[0].y, bottom: points[0].y },
  );
  const area = (bounds.right - bounds.left) * (bounds.bottom - bounds.top);
  if (!Number.isFinite(area)) return null;

  return {
    screen: closed && insidePolygon(point, points) ? { ...point } : closest,
    area,
  };
}

function rectProjection(
  point: CommentPosition,
  geometry: Extract<CommentSnapGeometry, { kind: "rect" }>,
): { screen: CommentPosition; area: number } | null {
  const { left, top, width, height } = geometry;
  const right = left + width;
  const bottom = top + height;
  const area = width * height;
  if (![left, top, right, bottom, area].every(Number.isFinite) || width <= 0 || height <= 0) {
    return null;
  }
  return {
    screen: {
      x: Math.max(left, Math.min(right, point.x)),
      y: Math.max(top, Math.min(bottom, point.y)),
    },
    area,
  };
}

function projectCandidate(
  point: CommentPosition,
  candidate: CommentSnapCandidate,
): MeasuredCandidate | null {
  if (!candidate.context.type || !candidate.context.id) return null;
  const geometry = candidate.geometry;
  let projection: { screen: CommentPosition; area: number } | null;

  switch (geometry.kind) {
    case "rect":
      projection = rectProjection(point, geometry);
      break;
    case "point":
      projection = finitePoint(geometry)
        ? { screen: { x: geometry.x, y: geometry.y }, area: 0 }
        : null;
      break;
    case "polyline":
      projection = polylineProjection(point, geometry);
      break;
  }

  if (!projection) return null;
  return {
    candidate,
    key: contextKey(candidate.context),
    ...projection,
    distance: Math.hypot(point.x - projection.screen.x, point.y - projection.screen.y),
  };
}

function compareCandidates(left: MeasuredCandidate, right: MeasuredCandidate): number {
  const leftPriority = Number.isFinite(left.candidate.priority) ? left.candidate.priority! : 0;
  const rightPriority = Number.isFinite(right.candidate.priority) ? right.candidate.priority! : 0;
  const rank =
    left.distance - right.distance || rightPriority - leftPriority || left.area - right.area;
  if (rank !== 0 || left.key === right.key) return rank;
  return left.key < right.key ? -1 : 1;
}

/** One drag owns only its preview. The caller commits position and context together on release. */
export class CommentMagneticDrag {
  private readonly initial: CommentMagneticInitial;
  private readonly grabOffset: CommentPosition;
  private pointer: CommentPosition;
  private suppressed = false;
  private selectedKey: string | null;
  private current: CommentMagneticPreview;
  private measured: MeasuredCandidate[] = [];

  constructor(
    private readonly adapter: CommentMagneticAdapter,
    initial: CommentMagneticInitial,
    pointerStart: CommentPosition,
  ) {
    this.initial = copyInitial(initial);
    const screen = this.screen(initial.position);
    this.pointer = finitePoint(pointerStart) ? { ...pointerStart } : { ...screen };
    this.grabOffset = { x: this.pointer.x - screen.x, y: this.pointer.y - screen.y };
    this.selectedKey = initial.context ? contextKey(initial.context) : null;
    this.current = { ...copyInitial(this.initial), candidate: null, candidates: [], screen };
  }

  get preview(): CommentMagneticPreview {
    return {
      ...copyInitial(this.current),
      candidate: this.current.candidate ? copyCandidate(this.current.candidate) : null,
      candidates: this.current.candidates.map(copyCandidate),
      screen: { ...this.current.screen },
    };
  }

  update(pointer: CommentPosition, suppress = false): CommentMagneticPreview {
    if (!finitePoint(pointer)) return this.preview;
    this.pointer = { ...pointer };
    this.suppressed = suppress;
    const screen = { x: pointer.x - this.grabOffset.x, y: pointer.y - this.grabOffset.y };
    const position = this.position(screen);
    const freeScreen = this.screen(position);
    const candidates = suppress ? [] : this.adapter.candidates();

    if (candidates === null) {
      this.preserveContext(position, freeScreen);
      return this.preview;
    }

    this.measured = candidates
      .map((candidate) => projectCandidate(freeScreen, candidate))
      .filter((candidate): candidate is MeasuredCandidate => candidate !== null)
      .filter(
        ({ key, distance }) =>
          distance <= (key === this.selectedKey ? COMMENT_SNAP_EXIT_PX : COMMENT_SNAP_ENTER_PX),
      )
      .sort(compareCandidates)
      .filter(
        (candidate, index, all) => all.findIndex(({ key }) => key === candidate.key) === index,
      );

    const selected = this.measured.find(({ key }) => key === this.selectedKey) ?? this.measured[0];
    this.apply(selected, position, freeScreen);
    return this.preview;
  }

  cycle(direction: 1 | -1): CommentMagneticPreview {
    this.update(this.pointer, this.suppressed);
    if (this.measured.length < 2) return this.preview;
    const index = this.measured.findIndex(({ key }) => key === this.selectedKey);
    const next = (index + direction + this.measured.length) % this.measured.length;
    this.apply(this.measured[next], this.current.position, this.current.screen);
    return this.preview;
  }

  cancel(): CommentMagneticInitial {
    this.selectedKey = this.initial.context ? contextKey(this.initial.context) : null;
    this.measured = [];
    this.current = {
      ...copyInitial(this.initial),
      candidate: null,
      candidates: [],
      screen: this.screen(this.initial.position),
    };
    return copyInitial(this.initial);
  }

  private apply(
    selected: MeasuredCandidate | undefined,
    freePosition: CommentPosition,
    freeScreen: CommentPosition,
  ): void {
    this.selectedKey = selected?.key ?? null;
    const position = selected ? this.position(selected.screen) : freePosition;
    this.current = {
      position,
      context: selected
        ? copyContext(this.adapter.context(copyCandidate(selected.candidate), { ...position }))
        : null,
      candidate: selected ? copyCandidate(selected.candidate) : null,
      candidates: this.measured.map(({ candidate }) => copyCandidate(candidate)),
      screen: selected ? this.screen(position) : freeScreen,
    };
  }

  private preserveContext(position: CommentPosition, screen: CommentPosition): void {
    const context = this.initial.context
      ? (this.adapter.moveContext?.(copyContext(this.initial.context), { ...position }) ??
        this.initial.context)
      : null;
    this.selectedKey = context ? contextKey(context) : null;
    this.measured = [];
    this.current = {
      position,
      context: context ? copyContext(context) : null,
      candidate: null,
      candidates: [],
      screen,
    };
  }

  private screen(position: CommentPosition): CommentPosition {
    const screen = this.adapter.toScreen({ ...position });
    return finitePoint(screen) ? { ...screen } : { ...position };
  }

  private position(screen: CommentPosition): CommentPosition {
    const position = this.adapter.fromScreen({ ...screen });
    const clamped = finitePoint(position) ? this.adapter.clamp(position) : this.current.position;
    return finitePoint(clamped) ? { ...clamped } : { ...this.current.position };
  }
}
