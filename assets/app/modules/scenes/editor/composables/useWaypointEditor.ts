import { computed, onMounted, onUnmounted, ref, watch, type Ref } from "vue";
import { useLive } from "@shared/composables/useLive";
import type {
  RouteMidpointAnchorConfig,
  RouteWaypointAnchorConfig,
  RouteWaypointEditorConfigs,
  SceneRouteConnectionBase,
  SceneRouteWaypoint,
} from "@modules/scenes/types/routes";
import type { KonvaEventObject } from "konva/lib/Node";

const WAYPOINT_RADIUS = 6;
const MIDPOINT_RADIUS = 4;
const WAYPOINT_FILL = "#ffffff";
const WAYPOINT_STROKE = "#f97316"; // orange-500
const MIDPOINT_FILL = "#fed7aa"; // orange-200
const MIDPOINT_STROKE = "#ea580c"; // orange-600

interface PixelPoint {
  x: number;
  y: number;
}

interface PinData {
  id: number | string;
  positionX: number;
  positionY: number;
}

interface UseWaypointEditorOpts {
  connections: Ref<SceneRouteConnectionBase[]>;
  pins: Ref<PinData[]>;
  pixelToPercent: (pixelX: number, pixelY: number) => PixelPoint;
  percentToPixel: (pctX: number, pctY: number) => PixelPoint;
  selectedType: Ref<string | null>;
  selectedId: Ref<number | string | null>;
}

/**
 * Composable for editing connection path waypoints via draggable anchor points.
 *
 * Activated by double-clicking a connection. Shows waypoint handles (drag to reshape)
 * and midpoint handles on every segment (click to insert new waypoint).
 * Ctrl+click removes a waypoint when the route would still keep at least two points.
 */
export function useWaypointEditor({
  connections,
  pins,
  pixelToPercent,
  percentToPixel,
  selectedType,
  selectedId,
}: UseWaypointEditorOpts) {
  const live = useLive();

  const editingConnectionId = ref<number | string | null>(null);
  const editingWaypoints = ref<SceneRouteWaypoint[]>([]); // [{x, y}] in percent coords

  const isEditing = computed(() => editingConnectionId.value !== null);

  // --- The connection being edited ---
  const editingConnection = computed(() => {
    if (!editingConnectionId.value) {
      return null;
    }
    return connections.value.find((c) => c.id === editingConnectionId.value) || null;
  });

  // --- Start/stop editing ---

  function startEditing(connectionId: number | string): void {
    const conn = connections.value.find((c) => c.id === connectionId);
    if (!conn) {
      return;
    }
    editingConnectionId.value = connectionId;
    editingWaypoints.value = (conn.waypoints || []).map((w) => ({
      x: w.x,
      y: w.y,
      stop: !!w.stop,
      pauseMs: w.pauseMs ?? w.pause_ms ?? null,
    }));
  }

  function stopEditing(): void {
    editingConnectionId.value = null;
    editingWaypoints.value = [];
  }

  // --- Drag waypoint ---

  function onWaypointDragMove(index: number, e: KonvaEventObject<DragEvent>): void {
    const node = e.target;
    const pos = pixelToPercent(node.x(), node.y());
    const wps = [...editingWaypoints.value];
    wps[index] = { ...wps[index], x: pos.x, y: pos.y };
    editingWaypoints.value = wps;
  }

  function onWaypointDragEnd(): void {
    persistWaypoints();
  }

  // --- Insert waypoint at midpoint click ---

  function insertWaypoint(segmentIndex: number, e?: KonvaEventObject<MouseEvent>): void {
    if (e) {
      e.cancelBubble = true;
    }

    // Build the full path: [fromPin, ...waypoints, toPin] in percent coords
    const fullPath = getFullPathPercent();
    if (!fullPath) {
      return;
    }

    // segmentIndex refers to the segment between fullPath[segmentIndex] and fullPath[segmentIndex+1]
    const a = fullPath[segmentIndex];
    const b = fullPath[segmentIndex + 1];
    if (!a || !b) {
      return;
    }

    const mid = { x: (a.x + b.x) / 2, y: (a.y + b.y) / 2 };

    // If the route has no pinned start, the first full-path point is already
    // the first waypoint, so insert after it.
    const waypointInsertIndex = editingConnection.value?.fromPinId
      ? segmentIndex
      : segmentIndex + 1;
    const wps = [...editingWaypoints.value];
    wps.splice(waypointInsertIndex, 0, { ...mid, stop: false });
    editingWaypoints.value = wps;
    persistWaypoints();
  }

  // --- Remove waypoint (Ctrl+click) ---

  function onWaypointClick(index: number, e: KonvaEventObject<MouseEvent>): void {
    if (e) {
      e.cancelBubble = true;
    }
    const nativeEvt = e.evt;
    if (nativeEvt.ctrlKey || nativeEvt.metaKey) {
      const wps = [...editingWaypoints.value];
      wps.splice(index, 1);
      if (!routeHasEnoughPoints(wps)) {
        return;
      }
      editingWaypoints.value = wps;
      persistWaypoints();
    }
  }

  // --- Persist to server ---

  function persistWaypoints(): void {
    if (!editingConnectionId.value) {
      return;
    }
    const waypoints = editingWaypoints.value.map((w) => ({
      x: Math.round(w.x * 100) / 100,
      y: Math.round(w.y * 100) / 100,
      stop: !!w.stop,
      pauseMs: w.pauseMs ?? w.pause_ms ?? null,
    }));
    live.pushEvent("update_connection_waypoints", {
      id: String(editingConnectionId.value),
      waypoints,
    });
  }

  // --- Full path in percent coords (from_pin + waypoints + to_pin) ---

  function getFullPathPercent(): SceneRouteWaypoint[] | null {
    const conn = editingConnection.value;
    if (!conn) {
      return null;
    }

    const fromPin = findEndpointPin(conn.fromPinId);
    const toPin = findEndpointPin(conn.toPinId);
    if (endpointMissing(conn.fromPinId, fromPin) || endpointMissing(conn.toPinId, toPin)) {
      return null;
    }

    const path: SceneRouteWaypoint[] = [];
    appendPinPoint(path, fromPin);
    path.push(...editingWaypoints.value);
    appendPinPoint(path, toPin);

    return path.length >= 2 ? path : null;
  }

  function findEndpointPin(pinId: number | string | null): PinData | null {
    return pinId === null ? null : pins.value.find((p) => p.id === pinId) || null;
  }

  function endpointMissing(pinId: number | string | null, pin: PinData | null): boolean {
    return pinId !== null && !pin;
  }

  function appendPinPoint(path: SceneRouteWaypoint[], pin: PinData | null): void {
    if (pin) path.push({ x: pin.positionX, y: pin.positionY });
  }

  function routeHasEnoughPoints(waypoints: SceneRouteWaypoint[]): boolean {
    const conn = editingConnection.value;
    if (!conn) {
      return false;
    }

    const endpointCount = (conn.fromPinId !== null ? 1 : 0) + (conn.toPinId !== null ? 1 : 0);
    return endpointCount + waypoints.length >= 2;
  }

  // --- Computed Konva configs for anchors ---

  const waypointEditorConfigs = computed<RouteWaypointEditorConfigs | null>(() => {
    if (!isEditing.value) {
      return null;
    }

    const fullPath = getFullPathPercent();
    if (!fullPath) {
      return null;
    }

    const pixelPath = fullPath.map((p) => percentToPixel(p.x, p.y));
    const wps = editingWaypoints.value;
    const pixelWps = wps.map((w) => percentToPixel(w.x, w.y));

    // Waypoint anchors (draggable)
    const waypointAnchors: RouteWaypointAnchorConfig[] = pixelWps.map((p, i) => ({
      x: p.x,
      y: p.y,
      radius: WAYPOINT_RADIUS,
      fill: WAYPOINT_FILL,
      stroke: WAYPOINT_STROKE,
      strokeWidth: 2,
      index: i,
    }));

    // Midpoint anchors on every segment of the full path (including pin->wp and wp->pin)
    const midpointAnchors: RouteMidpointAnchorConfig[] = [];
    for (let i = 0; i < pixelPath.length - 1; i++) {
      const a = pixelPath[i];
      const b = pixelPath[i + 1];
      midpointAnchors.push({
        x: (a.x + b.x) / 2,
        y: (a.y + b.y) / 2,
        radius: MIDPOINT_RADIUS,
        fill: MIDPOINT_FILL,
        stroke: MIDPOINT_STROKE,
        strokeWidth: 1,
        segmentIndex: i,
      });
    }

    return { waypointAnchors, midpointAnchors };
  });

  // --- Auto-exit on selection change ---

  watch([selectedType, selectedId], ([type, id]) => {
    if (!isEditing.value) {
      return;
    }
    if (type !== "connection" || id !== editingConnectionId.value) {
      stopEditing();
    }
  });

  // --- Escape to exit ---

  function onKeyDown(e: KeyboardEvent): void {
    if (e.key === "Escape" && isEditing.value) {
      e.preventDefault();
      stopEditing();
    }
  }

  onMounted(() => window.addEventListener("keydown", onKeyDown));
  onUnmounted(() => window.removeEventListener("keydown", onKeyDown));

  return {
    editingConnectionId,
    editingWaypoints,
    isEditing,
    startEditing,
    stopEditing,
    onWaypointDragMove,
    onWaypointDragEnd,
    onWaypointClick,
    insertWaypoint,
    waypointEditorConfigs,
  };
}
