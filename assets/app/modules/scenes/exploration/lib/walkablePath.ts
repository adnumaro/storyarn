import type { ExplorationZone, PixelPoint, Vertex } from "../types";

const EPSILON = 1e-7;

type WalkablePolygon = Pick<ExplorationZone, "vertices">;

interface GraphEdge {
  to: number;
  distance: number;
}

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
  const offset = subtract(point, start);

  if (Math.abs(cross(segment, offset)) > EPSILON) {
    return false;
  }

  const projection = dot(offset, segment);
  const lengthSquared = dot(segment, segment);
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

function collectCandidateVertices(polygons: readonly WalkablePolygon[]): PixelPoint[] {
  const candidates: PixelPoint[] = [];
  const edgesByPolygon: [Vertex, Vertex][][] = [];

  for (const polygon of polygons) {
    if (!polygon.vertices || polygon.vertices.length < 3) {
      continue;
    }

    candidates.push(...polygon.vertices);
    edgesByPolygon.push(polygonEdges(polygon.vertices));
  }

  // Intersections are vertices of the union boundary and can be required by
  // the shortest path when several walkable polygons overlap.
  for (let first = 0; first < edgesByPolygon.length; first++) {
    for (let second = first + 1; second < edgesByPolygon.length; second++) {
      for (const [start, end] of edgesByPolygon[first]) {
        for (const [edgeStart, edgeEnd] of edgesByPolygon[second]) {
          const parameters = segmentIntersectionParameters(start, end, edgeStart, edgeEnd);
          candidates.push(...parameters.map((parameter) => pointAt(start, end, parameter)));
        }
      }
    }
  }

  return candidates.filter(
    (candidate, index) => candidates.findIndex((other) => pointsEqual(candidate, other)) === index,
  );
}

function buildVisibilityGraph(
  nodes: PixelPoint[],
  polygons: readonly WalkablePolygon[],
): GraphEdge[][] {
  const graph = nodes.map<GraphEdge[]>(() => []);

  for (let first = 0; first < nodes.length; first++) {
    for (let second = first + 1; second < nodes.length; second++) {
      if (!isSegmentInWalkableArea(nodes[first], nodes[second], polygons)) {
        continue;
      }

      const edgeDistance = distance(nodes[first], nodes[second]);
      graph[first].push({ to: second, distance: edgeDistance });
      graph[second].push({ to: first, distance: edgeDistance });
    }
  }

  return graph;
}

function closestUnvisitedNode(distances: number[], visited: boolean[]): number {
  let closest = -1;

  for (let index = 0; index < distances.length; index++) {
    if (!visited[index] && (closest === -1 || distances[index] < distances[closest])) {
      closest = index;
    }
  }

  return closest;
}

function relaxGraphEdges(
  current: number,
  graph: GraphEdge[][],
  distances: number[],
  previous: number[],
): void {
  for (const edge of graph[current]) {
    const nextDistance = distances[current] + edge.distance;
    if (nextDistance + EPSILON < distances[edge.to]) {
      distances[edge.to] = nextDistance;
      previous[edge.to] = current;
    }
  }
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

function shortestGraphPath(graph: GraphEdge[][], target: number): number[] | null {
  const distances = graph.map(() => Number.POSITIVE_INFINITY);
  const previous = graph.map(() => -1);
  const visited = graph.map(() => false);
  distances[0] = 0;

  for (let iteration = 0; iteration < graph.length; iteration++) {
    const current = closestUnvisitedNode(distances, visited);

    if (current === -1 || !Number.isFinite(distances[current])) {
      break;
    }
    if (current === target) {
      break;
    }

    visited[current] = true;
    relaxGraphEdges(current, graph, distances, previous);
  }

  if (!Number.isFinite(distances[target])) {
    return null;
  }

  return reconstructGraphPath(previous, target);
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
  const graph = buildVisibilityGraph(nodes, polygons);
  const path = shortestGraphPath(graph, 1);

  return path?.map((index) => ({ ...nodes[index] })) ?? null;
}
