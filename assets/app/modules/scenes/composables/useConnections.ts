import { computed, type ComputedRef, type Ref } from "vue";
import { PIN_SIZES } from "../lib/pin-icons";
import { useHiddenLayerIds, type LayerData } from "./useLayerVisibility";

const DEFAULT_COLOR = "#ffffff";
const DEFAULT_WIDTH = 3;
const DEFAULT_OPACITY = 1;
const ARROW_POINTER_LENGTH = 8;
const ARROW_POINTER_WIDTH = 12;
const LABEL_COLOR = "#d1d5db";
const EDGE_GAP = 4;

const DASH_PATTERNS: Record<string, number[] | null> = {
  solid: null,
  dashed: [10, 6],
  dotted: [3, 6],
};

interface PixelPoint {
  x: number;
  y: number;
}

interface Waypoint {
  x: number;
  y: number;
}

interface ConnectionData {
  id: number | string;
  fromPinId: number | string;
  toPinId: number | string;
  waypoints: Waypoint[] | null;
  color: string | null;
  lineWidth: number | null;
  lineStyle: string | null;
  label: string | null;
  showLabel: boolean;
  bidirectional: boolean;
}

interface PinData {
  id: number | string;
  positionX: number;
  positionY: number;
  size: string | null;
  layerId: number | string | null;
}

interface WaypointEditOverride {
  connectionId: number | string;
  waypoints: Waypoint[];
}

interface LabelConfig {
  text: string;
  x: number;
  y: number;
  offsetX: number;
  offsetY: number;
  rotation: number;
  fill: string;
  fontSize: number;
  fontStyle: string;
  align: string;
  width: number;
  shadowColor: string;
  shadowBlur: number;
  shadowOpacity: number;
  listening: boolean;
}

export interface ConnectionConfig {
  id: number | string;
  points: number[];
  stroke: string;
  fill: string;
  strokeWidth: number;
  dash: number[] | null;
  opacity: number;
  pointerLength: number;
  pointerWidth: number;
  pointerAtBeginning: boolean;
  pointerAtEnding: boolean;
  labelConfig: LabelConfig | null;
  isSelected: boolean;
  listening: boolean;
  hitStrokeWidth: number;
}

type MaybeComputedRef<T> = Ref<T> | ComputedRef<T>;

interface UseConnectionsOpts {
  connections: MaybeComputedRef<ConnectionData[]>;
  pins: MaybeComputedRef<PinData[]>;
  layers: MaybeComputedRef<LayerData[]>;
  percentToPixel: (pctX: number, pctY: number) => PixelPoint;
  selectedType?: MaybeComputedRef<string | null>;
  selectedId?: MaybeComputedRef<number | string | null>;
  isSelectMode?: MaybeComputedRef<boolean>;
  dragOverrides?: MaybeComputedRef<Record<string | number, PixelPoint>>;
  waypointEditOverride?: MaybeComputedRef<WaypointEditOverride | null>;
}

/** Build label config at the midpoint of a pixel path, or null */
function buildLabelConfig(conn: ConnectionData, pixelPath: PixelPoint[]): LabelConfig | null {
  if (conn.showLabel === false || !conn.label) return null;
  const mid = pathMidpointAndAngle(pixelPath);
  if (!mid) return null;
  return {
    text: conn.label,
    x: mid.x,
    y: mid.y,
    offsetX: 60,
    offsetY: 10,
    rotation: mid.angle,
    fill: LABEL_COLOR,
    fontSize: 13,
    fontStyle: "600",
    align: "center",
    width: 120,
    shadowColor: "black",
    shadowBlur: 3,
    shadowOpacity: 0.8,
    listening: false,
  };
}

/** Build a single ConnectionConfig from connection data and resolved paths */
function buildConnectionConfig(
  conn: ConnectionData,
  points: number[],
  pixelPath: PixelPoint[],
  isSelected: boolean,
  listening: boolean,
): ConnectionConfig {
  const color = conn.color || DEFAULT_COLOR;
  const strokeWidth = conn.lineWidth || DEFAULT_WIDTH;
  return {
    id: conn.id,
    points,
    stroke: color,
    fill: color,
    strokeWidth: isSelected ? Math.max(strokeWidth, 4) : strokeWidth,
    dash: DASH_PATTERNS[conn.lineStyle || "solid"] || null,
    opacity: isSelected ? 1 : DEFAULT_OPACITY,
    pointerLength: ARROW_POINTER_LENGTH,
    pointerWidth: ARROW_POINTER_WIDTH,
    pointerAtBeginning: !!conn.bidirectional,
    pointerAtEnding: true,
    labelConfig: buildLabelConfig(conn, pixelPath),
    isSelected,
    listening,
    hitStrokeWidth: 20,
  };
}

/**
 * Composable for computing connection render configs.
 * Handles pin position lookup, waypoint conversion, arrowheads, and label placement.
 */
export function useConnections({
  connections,
  pins,
  layers,
  percentToPixel,
  selectedType,
  selectedId,
  isSelectMode,
  dragOverrides,
  waypointEditOverride,
}: UseConnectionsOpts) {
  // Pin pixel positions keyed by id -- uses drag overrides for real-time connection updates
  const pinPositions = computed<Record<string | number, PixelPoint>>(() => {
    const overrides = dragOverrides?.value || {};
    const map: Record<string | number, PixelPoint> = {};
    for (const pin of pins.value) {
      // If pin is being dragged, use the live pixel position from drag
      map[pin.id] = overrides[pin.id] || percentToPixel(pin.positionX, pin.positionY);
    }
    return map;
  });

  // Pin radii keyed by id -- used to offset arrow endpoints to circle edge
  const pinRadii = computed<Record<string | number, number>>(() => {
    const map: Record<string | number, number> = {};
    for (const pin of pins.value) {
      const dims = PIN_SIZES[pin.size || "md"] || PIN_SIZES.md;
      map[pin.id] = dims.diameter / 2;
    }
    return map;
  });

  const hiddenLayerIds = useHiddenLayerIds(layers);

  // Pin visibility by id (true if pin's layer is visible or pin has no layer)
  const pinVisible = computed<Record<string | number, boolean>>(() => {
    const vis: Record<string | number, boolean> = {};
    for (const pin of pins.value) {
      vis[pin.id] = !pin.layerId || !hiddenLayerIds.value.has(pin.layerId);
    }
    return vis;
  });

  function isConnectionVisible(conn: ConnectionData): boolean {
    const fromPos = pinPositions.value[conn.fromPinId];
    const toPos = pinPositions.value[conn.toPinId];
    if (!fromPos || !toPos) return false;

    const fromVis = pinVisible.value[conn.fromPinId] !== false;
    const toVis = pinVisible.value[conn.toPinId] !== false;
    return fromVis || toVis;
  }

  function resolveWaypoints(conn: ConnectionData): Waypoint[] {
    const override = waypointEditOverride?.value;
    if (override && override.connectionId === conn.id) return override.waypoints;
    return conn.waypoints || [];
  }

  function buildPixelPath(conn: ConnectionData, fromPos: PixelPoint, toPos: PixelPoint): PixelPoint[] {
    const waypoints = resolveWaypoints(conn);
    const rawPath: PixelPoint[] = [fromPos];
    for (const wp of waypoints) {
      rawPath.push(percentToPixel(wp.x, wp.y));
    }
    rawPath.push(toPos);

    const fromRadius = pinRadii.value[conn.fromPinId] || 0;
    const toRadius = pinRadii.value[conn.toPinId] || 0;
    return offsetEndpoints(rawPath, fromRadius, toRadius);
  }

  function flattenPath(pixelPath: PixelPoint[]): number[] {
    const points: number[] = [];
    for (const p of pixelPath) {
      points.push(p.x, p.y);
    }
    return points;
  }

  const connectionConfigs = computed<ConnectionConfig[]>(() => {
    const result: ConnectionConfig[] = [];

    for (const conn of connections.value) {
      if (!isConnectionVisible(conn)) continue;

      const fromPos = pinPositions.value[conn.fromPinId];
      const toPos = pinPositions.value[conn.toPinId];
      const pixelPath = buildPixelPath(conn, fromPos, toPos);
      const points = flattenPath(pixelPath);

      const isSelected = selectedType?.value === "connection" && selectedId?.value === conn.id;
      result.push(buildConnectionConfig(conn, points, pixelPath, isSelected, isSelectMode?.value ?? false));
    }

    return result;
  });

  return { connectionConfigs };
}

// --- Geometry helpers ---

function offsetEndpoints(path: PixelPoint[], fromRadius: number, toRadius: number): PixelPoint[] {
  if (path.length < 2) {
    return path;
  }

  const result = path.slice();

  if (fromRadius > 0) {
    const first = path[0];
    const second = path[1];
    const dx = second.x - first.x;
    const dy = second.y - first.y;
    const dist = Math.sqrt(dx * dx + dy * dy);
    if (dist > 0) {
      const offset = (fromRadius + EDGE_GAP) / dist;
      result[0] = { x: first.x + dx * offset, y: first.y + dy * offset };
    }
  }

  if (toRadius > 0) {
    const last = path[path.length - 1];
    const prev = path[path.length - 2];
    const dx = prev.x - last.x;
    const dy = prev.y - last.y;
    const dist = Math.sqrt(dx * dx + dy * dy);
    if (dist > 0) {
      const offset = (toRadius + EDGE_GAP) / dist;
      result[result.length - 1] = {
        x: last.x + dx * offset,
        y: last.y + dy * offset,
      };
    }
  }

  return result;
}

interface MidpointResult {
  x: number;
  y: number;
  angle: number;
}

function pathMidpointAndAngle(pixelPath: PixelPoint[]): MidpointResult | null {
  if (pixelPath.length < 2) {
    return null;
  }

  const segLens: number[] = [];
  let total = 0;
  for (let i = 1; i < pixelPath.length; i++) {
    const dx = pixelPath[i].x - pixelPath[i - 1].x;
    const dy = pixelPath[i].y - pixelPath[i - 1].y;
    const d = Math.sqrt(dx * dx + dy * dy);
    segLens.push(d);
    total += d;
  }

  if (total === 0) {
    return { x: pixelPath[0].x, y: pixelPath[0].y, angle: 0 };
  }

  let remaining = total / 2;
  let segIdx = 0;
  for (; segIdx < segLens.length - 1; segIdx++) {
    if (remaining <= segLens[segIdx]) {
      break;
    }
    remaining -= segLens[segIdx];
  }

  const ratio = segLens[segIdx] > 0 ? remaining / segLens[segIdx] : 0;
  const x = pixelPath[segIdx].x + (pixelPath[segIdx + 1].x - pixelPath[segIdx].x) * ratio;
  const y = pixelPath[segIdx].y + (pixelPath[segIdx + 1].y - pixelPath[segIdx].y) * ratio;

  const dx = pixelPath[segIdx + 1].x - pixelPath[segIdx].x;
  const dy = pixelPath[segIdx + 1].y - pixelPath[segIdx].y;
  let angle = (Math.atan2(dy, dx) * 180) / Math.PI;

  if (angle > 90) {
    angle -= 180;
  }
  if (angle < -90) {
    angle += 180;
  }

  return { x, y, angle: Math.round(angle * 10) / 10 };
}
