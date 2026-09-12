import type {
  CommentContextReference,
  CommentMagneticAdapter,
  CommentSnapCandidate,
  CommentSnapGeometry,
} from "@components/comments/commentMagnetism";
import type { CommentPosition } from "@components/comments/types";
import type { PinConfig } from "../../canvas/composables/usePins";
import type { ZoneConfig } from "../../canvas/composables/useZones";
import type { ConnectionConfig } from "../../canvas/composables/useConnections";
import type { AnnotationConfig } from "../composables/useAnnotations";
import {
  clampSceneCommentPosition,
  sceneCommentPointFromClient,
  sceneCommentScreenPoint,
  type SceneCommentProjection,
  type SceneCommentStageTransform,
} from "./comment-geometry";

type TargetId = number | string;

type SceneCommentZoneTarget = Pick<ZoneConfig, "id" | "points" | "name" | "layerId" | "opacity"> &
  Partial<
    Pick<
      ZoneConfig,
      | "labelText"
      | "showLabelText"
      | "labelX"
      | "labelTextX"
      | "labelY"
      | "labelWidth"
      | "labelHeight"
      | "labelIconCanvas"
      | "labelIconX"
      | "labelIconY"
      | "labelIconSize"
    >
  >;

export interface SceneCommentOrigin {
  type: string;
  id: TargetId;
  position: CommentPosition;
}

/** The same configs rendered by Konva, including local drag/edit overrides. */
export interface SceneCommentTargets {
  pins: readonly Pick<PinConfig, "id" | "x" | "y" | "radius" | "label" | "layerId" | "opacity">[];
  zones: readonly SceneCommentZoneTarget[];
  connections: readonly (Pick<
    ConnectionConfig,
    "id" | "points" | "connectedLayerIds" | "opacity"
  > & {
    /** Percent coordinates: raw from-pin, otherwise first waypoint, otherwise to-pin. */
    origin: CommentPosition;
    label?: string | null;
    freeEndpoint?: boolean;
  })[];
  annotations: readonly Pick<
    AnnotationConfig,
    "id" | "x" | "y" | "width" | "height" | "text" | "layerId"
  >[];
  layers?: readonly { id: TargetId; visible: boolean }[];
  /** Raw origins retain context navigation while the local view hides a layer. */
  origins?: readonly SceneCommentOrigin[];
}

export interface SceneCommentSnapOptions {
  container(): HTMLElement | null;
  stage(): SceneCommentStageTransform;
  projection(): SceneCommentProjection;
  targets(): SceneCommentTargets;
}

interface ResolvableSceneContext extends CommentContextReference {
  status?: "available" | "unavailable";
}

function finitePoint(point: CommentPosition): boolean {
  return Number.isFinite(point.x) && Number.isFinite(point.y);
}

function hiddenLayers(targets: SceneCommentTargets): Set<string> {
  return new Set(
    targets.layers?.filter((layer) => !layer.visible).map((layer) => String(layer.id)),
  );
}

function visibleLayer(layerId: TargetId | null, hidden: Set<string>): boolean {
  return layerId === null || !hidden.has(String(layerId));
}

function flatPoints(points: readonly number[], minimum: number): CommentPosition[] {
  if (points.length < minimum * 2 || points.length % 2 !== 0 || !points.every(Number.isFinite)) {
    return [];
  }
  const result: CommentPosition[] = [];
  for (let index = 0; index < points.length; index += 2) {
    result.push({ x: points[index], y: points[index + 1] });
  }
  return result;
}

function targetLabel(value: string | null | undefined, fallback: string, id: TargetId): string {
  return value?.replace(/\s+/g, " ").trim().slice(0, 120) || `${fallback} #${id}`;
}

function geometryPoints(geometry: CommentSnapGeometry): CommentPosition[] {
  if (geometry.kind === "polyline") return geometry.points;
  if (geometry.kind === "point") return [geometry];
  return [
    { x: geometry.left, y: geometry.top },
    { x: geometry.left + geometry.width, y: geometry.top + geometry.height },
  ];
}

function intersectsViewport(geometry: CommentSnapGeometry, rect: DOMRect): boolean {
  const points = geometryPoints(geometry);
  if (points.length === 0 || !points.every(finitePoint)) return false;
  const xs = points.map((point) => point.x);
  const ys = points.map((point) => point.y);
  return (
    Math.max(...xs) >= rect.left &&
    Math.min(...xs) <= rect.right &&
    Math.max(...ys) >= rect.top &&
    Math.min(...ys) <= rect.bottom
  );
}

interface CandidateFrame {
  targets: SceneCommentTargets;
  hidden: Set<string>;
  screen(point: CommentPosition): CommentPosition;
  stage: SceneCommentStageTransform;
  add(type: string, id: TargetId, label: string, geometry: CommentSnapGeometry): void;
}

function includeZoneText(
  zone: SceneCommentZoneTarget,
  include: (x: number, y: number, width: number, height: number) => void,
): void {
  if (!zone.showLabelText || !zone.labelText) return;
  const x = zone.labelTextX ?? Number.NaN;
  const width = (zone.labelWidth ?? Number.NaN) - (x - (zone.labelX ?? Number.NaN));
  include(x, zone.labelY ?? Number.NaN, width, zone.labelHeight ?? Number.NaN);
}

function zoneLabelRect(
  zone: SceneCommentZoneTarget,
  screen: CandidateFrame["screen"],
): CommentSnapGeometry | null {
  const corners: CommentPosition[] = [];
  function include(x: number, y: number, width: number, height: number) {
    if (![x, y, width, height].every(Number.isFinite) || width <= 0 || height <= 0) return;
    corners.push(screen({ x, y }), screen({ x: x + width, y: y + height }));
  }
  includeZoneText(zone, include);
  if (zone.labelIconCanvas) {
    const size = zone.labelIconSize ?? Number.NaN;
    include(zone.labelIconX ?? Number.NaN, zone.labelIconY ?? Number.NaN, size, size);
  }
  if (corners.length === 0) return null;
  const xs = corners.map((point) => point.x);
  const ys = corners.map((point) => point.y);
  return {
    kind: "rect",
    left: Math.min(...xs),
    top: Math.min(...ys),
    width: Math.max(...xs) - Math.min(...xs),
    height: Math.max(...ys) - Math.min(...ys),
  };
}

function appendZoneCandidates({ targets, hidden, screen, add }: CandidateFrame): void {
  for (const zone of targets.zones) {
    if (!visibleLayer(zone.layerId, hidden)) continue;
    const label = targetLabel(zone.name, "Zone", zone.id);
    if (zone.opacity <= 0) {
      // Polygon opacity does not hide the separately rendered text/icon label.
      const geometry = zoneLabelRect(zone, screen);
      if (geometry) add("scene_zone", zone.id, label, geometry);
      continue;
    }
    const points = flatPoints(zone.points, 3);
    if (points.length === 0) continue;
    add("scene_zone", zone.id, label, {
      kind: "polyline",
      points: points.map(screen),
      closed: true,
    });
  }
}

function appendConnectionCandidates({ targets, hidden, screen, add }: CandidateFrame): void {
  for (const connection of targets.connections) {
    if (
      connection.opacity <= 0 ||
      (!connection.freeEndpoint &&
        connection.connectedLayerIds.length > 0 &&
        connection.connectedLayerIds.every((id) => hidden.has(String(id))))
    )
      continue;
    const points = flatPoints(connection.points, 2);
    if (points.length === 0 || !finitePoint(connection.origin)) continue;
    // Konva renders these exact segments, including waypoint and pin-edge adjustments.
    add(
      "scene_connection",
      connection.id,
      targetLabel(connection.label, "Connection", connection.id),
      {
        kind: "polyline",
        points: points.map(screen),
      },
    );
  }
}

function appendPinCandidates({ targets, hidden, screen, stage, add }: CandidateFrame): void {
  for (const pin of targets.pins) {
    if (!visibleLayer(pin.layerId, hidden) || !Number.isFinite(pin.radius) || pin.radius <= 0)
      continue;
    const center = screen(pin);
    const rx = pin.radius * stage.scaleX;
    const ry = pin.radius * stage.scaleY;
    if (!finitePoint(center) || !Number.isFinite(rx) || !Number.isFinite(ry)) continue;
    // Approximate the visible circle to within half a client pixel, even at high zoom.
    const radius = Math.max(Math.abs(rx), Math.abs(ry));
    const segments = Math.max(
      24,
      Math.min(256, Math.ceil(Math.PI / Math.acos(1 - Math.min(0.5 / radius, 1)))),
    );
    const points = Array.from({ length: segments }, (_, index) => {
      const angle = (index * 2 * Math.PI) / segments;
      return { x: center.x + Math.cos(angle) * rx, y: center.y + Math.sin(angle) * ry };
    });
    add("scene_pin", pin.id, targetLabel(pin.label, "Pin", pin.id), {
      kind: "polyline",
      points,
      closed: true,
    });
  }
}

function appendAnnotationCandidates({ targets, hidden, screen, add }: CandidateFrame): void {
  for (const annotation of targets.annotations) {
    if (
      !visibleLayer(annotation.layerId, hidden) ||
      annotation.width <= 0 ||
      annotation.height <= 0
    )
      continue;
    const start = screen(annotation);
    const end = screen({
      x: annotation.x + annotation.width,
      y: annotation.y + annotation.height,
    });
    add(
      "scene_annotation",
      annotation.id,
      targetLabel(annotation.text, "Annotation", annotation.id),
      {
        kind: "rect",
        left: Math.min(start.x, end.x),
        top: Math.min(start.y, end.y),
        width: Math.abs(end.x - start.x),
        height: Math.abs(end.y - start.y),
      },
    );
  }
}

/** Geometry is measured in client pixels; offsets remain in Scene percent coordinates. */
export function sceneCommentSnapAdapter(options: SceneCommentSnapOptions): CommentMagneticAdapter {
  return {
    candidates() {
      const container = options.container();
      if (!container) return [];
      const rect = container.getBoundingClientRect();
      const stage = options.stage();
      const targets = options.targets();
      const hidden = hiddenLayers(targets);
      const screen = (point: CommentPosition): CommentPosition => ({
        x: rect.left + stage.x + point.x * stage.scaleX,
        y: rect.top + stage.y + point.y * stage.scaleY,
      });
      const candidates: CommentSnapCandidate[] = [];
      // Match the canvas stacking order when equally close candidates overlap.
      function add(type: string, id: TargetId, label: string, geometry: CommentSnapGeometry) {
        if (!intersectsViewport(geometry, rect)) return;
        candidates.push({
          context: { type, id: String(id) },
          label,
          geometry,
          priority: candidates.length,
        });
      }

      const frame = { targets, hidden, screen, stage, add };
      appendZoneCandidates(frame);
      appendConnectionCandidates(frame);
      appendPinCandidates(frame);
      appendAnnotationCandidates(frame);
      return candidates;
    },
    toScreen(position) {
      const rect = options.container()?.getBoundingClientRect();
      const point = sceneCommentScreenPoint(position, options.stage(), options.projection());
      return { x: point.x + (rect?.left ?? 0), y: point.y + (rect?.top ?? 0) };
    },
    fromScreen(point) {
      return sceneCommentPointFromClient(
        point,
        options.container()?.getBoundingClientRect() ?? { left: 0, top: 0 },
        options.stage(),
        options.projection(),
      );
    },
    clamp: clampSceneCommentPosition,
    context(candidate, position) {
      const origin = contextOrigin(candidate.context, options.targets(), options.projection());
      return {
        ...candidate.context,
        offset: origin ? { x: position.x - origin.x, y: position.y - origin.y } : null,
      };
    },
  };
}

function zoneOrigin(
  target: SceneCommentTargets["zones"][number] | undefined,
  hidden: Set<string>,
  projection: SceneCommentProjection,
): CommentPosition | null {
  if (!target || !visibleLayer(target.layerId, hidden)) return null;
  const points = flatPoints(target.points, 3);
  return points.length > 0
    ? projection.pixelToPercent(
        Math.min(...points.map((point) => point.x)),
        Math.min(...points.map((point) => point.y)),
      )
    : null;
}

function renderedConnectionOrigin(
  target: SceneCommentTargets["connections"][number] | undefined,
  hidden: Set<string>,
): CommentPosition | null {
  if (!target) return null;
  const visible =
    target.freeEndpoint ||
    target.connectedLayerIds.length === 0 ||
    target.connectedLayerIds.some((id) => !hidden.has(String(id)));
  return visible ? target.origin : null;
}

function renderedOrigin(
  context: CommentContextReference,
  targets: SceneCommentTargets,
  projection: SceneCommentProjection,
): CommentPosition | null {
  const matches = (target: { id: TargetId }) => String(target.id) === context.id;
  const hidden = hiddenLayers(targets);
  switch (context.type) {
    case "scene_pin":
    case "scene_annotation": {
      const target = (context.type === "scene_pin" ? targets.pins : targets.annotations).find(
        matches,
      );
      return target && visibleLayer(target.layerId, hidden)
        ? projection.pixelToPercent(target.x, target.y)
        : null;
    }
    case "scene_zone":
      return zoneOrigin(targets.zones.find(matches), hidden, projection);
    case "scene_connection":
      return renderedConnectionOrigin(targets.connections.find(matches), hidden);
    default:
      return null;
  }
}

function contextOrigin(
  context: CommentContextReference,
  targets: SceneCommentTargets,
  projection: SceneCommentProjection,
): CommentPosition | null {
  return (
    renderedOrigin(context, targets, projection) ??
    targets.origins?.find(
      (origin) => origin.type === context.type && String(origin.id) === context.id,
    )?.position ??
    null
  );
}

/** Missing or unavailable targets retain the last saved free position. */
export function resolveSceneCommentPosition(
  position: CommentPosition | null | undefined,
  context: ResolvableSceneContext | null | undefined,
  targets: SceneCommentTargets,
  projection: SceneCommentProjection,
): CommentPosition | null {
  const fallback = position && finitePoint(position) ? clampSceneCommentPosition(position) : null;
  if (!context?.offset || context.status === "unavailable" || !finitePoint(context.offset))
    return fallback;
  const origin = contextOrigin(context, targets, projection);
  return origin && finitePoint(origin)
    ? clampSceneCommentPosition({ x: origin.x + context.offset.x, y: origin.y + context.offset.y })
    : fallback;
}
