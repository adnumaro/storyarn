export interface SceneRouteWaypoint {
  x: number;
  y: number;
  stop?: boolean;
  pauseMs?: number | null;
  pause_ms?: number | null;
}

export interface SceneRouteConnectionBase {
  id: number | string;
  fromPinId: number | string | null;
  toPinId: number | string | null;
  waypoints: SceneRouteWaypoint[] | null;
}

export interface SceneRouteConnection extends SceneRouteConnectionBase {
  color: string | null;
  lineWidth: number | null;
  lineStyle: string | null;
  label: string | null;
  showLabel: boolean;
  bidirectional: boolean;
}

export interface SceneRouteStopFields {
  fromStop?: boolean;
  toStop?: boolean;
  fromPauseMs?: number | null;
  toPauseMs?: number | null;
}

export interface ScenePatrolRoutePoint {
  x: number;
  y: number;
  isPinStop?: boolean;
  isStop?: boolean;
  pauseMs?: number | null;
}

export interface RouteWaypointAnchorConfig {
  x: number;
  y: number;
  radius: number;
  fill: string;
  stroke: string;
  strokeWidth: number;
  index: number;
}

export interface RouteMidpointAnchorConfig {
  x: number;
  y: number;
  radius: number;
  fill: string;
  stroke: string;
  strokeWidth: number;
  segmentIndex: number;
}

export interface RouteWaypointEditorConfigs {
  waypointAnchors: RouteWaypointAnchorConfig[];
  midpointAnchors: RouteMidpointAnchorConfig[];
}
