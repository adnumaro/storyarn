import type { ExplorationZone, PixelPoint, Vertex } from "../types";

const EPSILON = 1e-7;

type WalkablePolygon = Pick<ExplorationZone, "vertices">;

function cross(a: PixelPoint, b: PixelPoint): number {
  return a.x * b.y - a.y * b.x;
}

function subtract(a: PixelPoint, b: PixelPoint): PixelPoint {
  return { x: a.x - b.x, y: a.y - b.y };
}

function dot(a: PixelPoint, b: PixelPoint): number {
  return a.x * b.x + a.y * b.y;
}

function distance(a: PixelPoint, b: PixelPoint): number {
  return Math.hypot(b.x - a.x, b.y - a.y);
}

function pointsEqual(a: PixelPoint, b: PixelPoint): boolean {
  return distance(a, b) <= EPSILON;
}

function pointAt(a: PixelPoint, b: PixelPoint, t: number): PixelPoint {
  return {
    x: a.x + (b.x - a.x) * t,
    y: a.y + (b.y - a.y) * t,
  };
}

function collinearIntersectionParameters(
  start: PixelPoint,
  segment: PixelPoint,
  edgeStart: PixelPoint,
  edgeEnd: PixelPoint,
): number[] {
  const lengthSquared = dot(segment, segment);
  if (lengthSquared <= EPSILON) {
    return pointsEqual(start, edgeStart) || pointsEqual(start, edgeEnd) ? [0] : [];
  }

  const first = dot(subtract(edgeStart, start), segment) / lengthSquared;
  const second = dot(subtract(edgeEnd, start), segment) / lengthSquared;
  const overlapStart = Math.max(0, Math.min(first, second));
  const overlapEnd = Math.min(1, Math.max(first, second));

  return overlapStart <= overlapEnd + EPSILON ? [overlapStart, overlapEnd] : [];
}

function pointOnSegment(point: PixelPoint, start: PixelPoint, end: PixelPoint): boolean {
  const segment = subtract(end, start);
  const lengthSquared = dot(segment, segment);

  if (lengthSquared <= EPSILON * EPSILON) {
    return pointsEqual(point, start);
  }

  const offset = subtract(point, start);

  if (Math.abs(cross(segment, offset)) > EPSILON) {
    return false;
  }

  const projection = dot(offset, segment);
  return projection >= -EPSILON && projection <= lengthSquared + EPSILON;
}

function pointInPolygon(point: PixelPoint, vertices: Vertex[]): boolean {
  let inside = false;

  for (let i = 0, j = vertices.length - 1; i < vertices.length; j = i++) {
    const current = vertices[i];
    const previous = vertices[j];

    if (pointOnSegment(point, previous, current)) {
      return true;
    }

    const intersects =
      current.y > point.y !== previous.y > point.y &&
      point.x <
        ((previous.x - current.x) * (point.y - current.y)) / (previous.y - current.y) + current.x;

    if (intersects) {
      inside = !inside;
    }
  }

  return inside;
}

export function isPointInWalkableArea(
  point: PixelPoint,
  polygons: readonly WalkablePolygon[],
): boolean {
  return polygons.some(
    (polygon) =>
      polygon.vertices && polygon.vertices.length >= 3 && pointInPolygon(point, polygon.vertices),
  );
}

/**
 * Returns the positions on start→end where it intersects an edge. Collinear
 * overlaps contribute both overlap limits so the intervals between them can
 * be classified independently.
 */
function segmentIntersectionParameters(
  start: PixelPoint,
  end: PixelPoint,
  edgeStart: PixelPoint,
  edgeEnd: PixelPoint,
): number[] {
  const segment = subtract(end, start);
  const edge = subtract(edgeEnd, edgeStart);
  const offset = subtract(edgeStart, start);
  const denominator = cross(segment, edge);

  if (Math.abs(denominator) <= EPSILON) {
    if (Math.abs(cross(offset, segment)) > EPSILON) {
      return [];
    }
    return collinearIntersectionParameters(start, segment, edgeStart, edgeEnd);
  }

  const t = cross(offset, edge) / denominator;
  const u = cross(offset, segment) / denominator;

  if (t < -EPSILON || t > 1 + EPSILON || u < -EPSILON || u > 1 + EPSILON) {
    return [];
  }

  return [Math.max(0, Math.min(1, t))];
}

function polygonEdges(vertices: Vertex[]): [Vertex, Vertex][] {
  return vertices.map((vertex, index) => [vertex, vertices[(index + 1) % vertices.length]]);
}

function boundingBoxesOverlap(
  firstStart: PixelPoint,
  firstEnd: PixelPoint,
  secondStart: PixelPoint,
  secondEnd: PixelPoint,
): boolean {
  return (
    Math.max(Math.min(firstStart.x, firstEnd.x), Math.min(secondStart.x, secondEnd.x)) <=
      Math.min(Math.max(firstStart.x, firstEnd.x), Math.max(secondStart.x, secondEnd.x)) +
        EPSILON &&
    Math.max(Math.min(firstStart.y, firstEnd.y), Math.min(secondStart.y, secondEnd.y)) <=
      Math.min(Math.max(firstStart.y, firstEnd.y), Math.max(secondStart.y, secondEnd.y)) + EPSILON
  );
}

function segmentBoundaryParameters(
  start: PixelPoint,
  end: PixelPoint,
  polygons: readonly WalkablePolygon[],
): number[] {
  const intersections = [0, 1];

  for (const polygon of polygons) {
    if (!polygon.vertices || polygon.vertices.length < 3) {
      continue;
    }

    for (const [edgeStart, edgeEnd] of polygonEdges(polygon.vertices)) {
      intersections.push(...segmentIntersectionParameters(start, end, edgeStart, edgeEnd));
    }
  }

  intersections.sort((a, b) => a - b);
  return intersections.filter(
    (value, index) => index === 0 || Math.abs(value - intersections[index - 1]) > EPSILON,
  );
}

function segmentIntervalsAreWalkable(
  start: PixelPoint,
  end: PixelPoint,
  boundaries: number[],
  polygons: readonly WalkablePolygon[],
): boolean {
  for (let index = 1; index < boundaries.length; index++) {
    const from = boundaries[index - 1];
    const to = boundaries[index];

    if (
      to - from > EPSILON &&
      !isPointInWalkableArea(pointAt(start, end, (from + to) / 2), polygons)
    ) {
      return false;
    }
  }

  return true;
}

/**
 * A segment is inside the union when every interval separated by a polygon
 * boundary lies inside (or on the edge of) at least one walkable polygon.
 */
export function isSegmentInWalkableArea(
  start: PixelPoint,
  end: PixelPoint,
  polygons: readonly WalkablePolygon[],
): boolean {
  if (!isPointInWalkableArea(start, polygons) || !isPointInWalkableArea(end, polygons)) {
    return false;
  }

  if (pointsEqual(start, end)) {
    return true;
  }

  return segmentIntervalsAreWalkable(
    start,
    end,
    segmentBoundaryParameters(start, end, polygons),
    polygons,
  );
}

function addUniqueCandidate(
  candidate: PixelPoint,
  candidates: PixelPoint[],
  buckets: Map<string, PixelPoint[]>,
): void {
  const bucketX = Math.floor(candidate.x / EPSILON);
  const bucketY = Math.floor(candidate.y / EPSILON);

  for (let offsetX = -1; offsetX <= 1; offsetX++) {
    for (let offsetY = -1; offsetY <= 1; offsetY++) {
      const nearby = buckets.get(`${bucketX + offsetX}:${bucketY + offsetY}`) || [];
      if (nearby.some((point) => pointsEqual(point, candidate))) {
        return;
      }
    }
  }

  const key = `${bucketX}:${bucketY}`;
  const bucket = buckets.get(key);
  if (bucket) {
    bucket.push(candidate);
  } else {
    buckets.set(key, [candidate]);
  }
  candidates.push(candidate);
}

function collectEdgeIntersections(
  firstEdges: [Vertex, Vertex][],
  secondEdges: [Vertex, Vertex][],
  candidates: PixelPoint[],
  buckets: Map<string, PixelPoint[]>,
): void {
  for (const [start, end] of firstEdges) {
    for (const [edgeStart, edgeEnd] of secondEdges) {
      if (!boundingBoxesOverlap(start, end, edgeStart, edgeEnd)) {
        continue;
      }

      const parameters = segmentIntersectionParameters(start, end, edgeStart, edgeEnd);
      for (const parameter of parameters) {
        addUniqueCandidate(pointAt(start, end, parameter), candidates, buckets);
      }
    }
  }
}

function collectCandidateVertices(polygons: readonly WalkablePolygon[]): PixelPoint[] {
  const candidates: PixelPoint[] = [];
  const buckets = new Map<string, PixelPoint[]>();
  const edgesByPolygon: [Vertex, Vertex][][] = [];

  for (const polygon of polygons) {
    if (!polygon.vertices || polygon.vertices.length < 3) {
      continue;
    }

    for (const vertex of polygon.vertices) {
      addUniqueCandidate(vertex, candidates, buckets);
    }
    edgesByPolygon.push(polygonEdges(polygon.vertices));
  }

  // Intersections are vertices of the union boundary and can be required by
  // the shortest path when several walkable polygons overlap.
  for (let first = 0; first < edgesByPolygon.length; first++) {
    for (let second = first + 1; second < edgesByPolygon.length; second++) {
      collectEdgeIntersections(edgesByPolygon[first], edgesByPolygon[second], candidates, buckets);
    }
  }

  return candidates;
}

function closestUnvisitedNode(scores: number[], visited: boolean[]): number {
  let closest = -1;

  for (let index = 0; index < scores.length; index++) {
    if (!visited[index] && (closest === -1 || scores[index] < scores[closest])) {
      closest = index;
    }
  }

  return closest;
}

function reconstructGraphPath(previous: number[], target: number): number[] | null {
  const path: number[] = [];

  for (let current = target; current !== 0; current = previous[current]) {
    if (current === -1) {
      return null;
    }
    path.push(current);
  }

  return path.reverse();
}

/**
 * Runs A* over the implicit visibility graph. Edges are checked only while a
 * node is expanded, avoiding the eager O(n²) graph construction for routes
 * that reach the target after visiting a small portion of the candidates.
 */
function shortestVisiblePath(
  nodes: PixelPoint[],
  polygons: readonly WalkablePolygon[],
): number[] | null {
  const target = 1;
  const distances = nodes.map(() => Number.POSITIVE_INFINITY);
  const scores = nodes.map(() => Number.POSITIVE_INFINITY);
  const previous = nodes.map(() => -1);
  const visited = nodes.map(() => false);
  distances[0] = 0;
  scores[0] = distance(nodes[0], nodes[target]);

  for (let iteration = 0; iteration < nodes.length; iteration++) {
    const current = closestUnvisitedNode(scores, visited);

    if (current === -1 || !Number.isFinite(distances[current])) {
      break;
    }
    if (current === target) {
      return reconstructGraphPath(previous, target);
    }

    visited[current] = true;
    for (let next = 0; next < nodes.length; next++) {
      if (
        next === current ||
        visited[next] ||
        !isSegmentInWalkableArea(nodes[current], nodes[next], polygons)
      ) {
        continue;
      }

      const nextDistance = distances[current] + distance(nodes[current], nodes[next]);
      if (nextDistance + EPSILON < distances[next]) {
        distances[next] = nextDistance;
        scores[next] = nextDistance + distance(nodes[next], nodes[target]);
        previous[next] = current;
      }
    }
  }

  return null;
}

/**
 * Finds the shortest Euclidean route within the union of the walkable
 * polygons. The returned path excludes `start` and includes `target`.
 */
export function findShortestWalkablePath(
  start: PixelPoint,
  target: PixelPoint,
  polygons: readonly WalkablePolygon[],
): PixelPoint[] | null {
  if (!isPointInWalkableArea(start, polygons) || !isPointInWalkableArea(target, polygons)) {
    return null;
  }

  if (isSegmentInWalkableArea(start, target, polygons)) {
    return [{ ...target }];
  }

  const candidates = collectCandidateVertices(polygons).filter(
    (point) => !pointsEqual(point, start) && !pointsEqual(point, target),
  );
  const nodes = [{ ...start }, { ...target }, ...candidates];
  const path = shortestVisiblePath(nodes, polygons);

  return path?.map((index) => ({ ...nodes[index] })) ?? null;
}
