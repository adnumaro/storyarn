import { computed, ref, watch } from "vue";
import type { CommentContextReference, CommentPosition } from "@components/comments/types";
import type { SceneRouteConnection } from "../../types/routes";
import type { ConnectionConfig } from "../../canvas/composables/useConnections";
import type { SceneCommentProjection } from "../lib/comment-geometry";
import type { SceneCommentOrigin, SceneCommentTargets } from "../lib/comment-snap-adapter";

type Id = number | string;
interface Layer {
  id: Id;
  visible: boolean;
}
interface PointTarget {
  id: Id;
  positionX: number;
  positionY: number;
  layerId: Id | null;
}
interface ZoneTarget {
  id: Id;
  vertices: CommentPosition[] | null;
  layerId: Id | null;
}
interface Context extends CommentContextReference {
  status?: "available" | "unavailable";
}
interface LocalDrag {
  type: "pin" | "annotation";
  id: Id;
  position: CommentPosition;
}

interface SceneCommentTargetOptions<TLayer extends Layer> {
  sceneId(): Id | null | undefined;
  userId(): Id;
  layers(): readonly TLayer[];
  pins(): readonly PointTarget[];
  zones(): readonly ZoneTarget[];
  connections(): readonly SceneRouteConnection[];
  annotations(): readonly PointTarget[];
  pinConfigs(): SceneCommentTargets["pins"];
  zoneConfigs(): SceneCommentTargets["zones"];
  connectionConfigs(): readonly Pick<
    ConnectionConfig,
    "id" | "points" | "connectedLayerIds" | "opacity"
  >[];
  annotationConfigs(): SceneCommentTargets["annotations"];
  projection(): SceneCommentProjection;
  context(): Context | null | undefined;
  waypointOverride?(): { connectionId: Id; waypoints: CommentPosition[] } | null;
}

function pointOrigin(target: PointTarget): CommentPosition {
  return { x: target.positionX, y: target.positionY };
}

function connectionOrigin(
  connection: SceneRouteConnection,
  pins: ReadonlyMap<string, CommentPosition>,
  waypoints = connection.waypoints,
): CommentPosition | null {
  const start = connection.fromPinId === null ? null : pins.get(String(connection.fromPinId));
  const end = connection.toPinId === null ? null : pins.get(String(connection.toPinId));
  return start ?? waypoints?.[0] ?? end ?? null;
}

/** Context visibility is a local viewing choice; shared layer visibility is untouched. */
export function useSceneCommentTargets<TLayer extends Layer>(
  options: SceneCommentTargetOptions<TLayer>,
) {
  const revealedLayers = ref<Set<string>>(new Set());
  const localDrag = ref<LocalDrag | null>(null);
  const effectiveLayers = computed(() =>
    options.layers().map((layer) => ({
      ...layer,
      visible: layer.visible || revealedLayers.value.has(String(layer.id)),
    })),
  );
  const draftStorageKey = computed(() => {
    const id = options.sceneId();
    return id == null ? null : `storyarn:scene-comment-draft:${options.userId()}:${id}`;
  });

  watch(
    () => [options.sceneId(), options.userId()],
    () => {
      revealedLayers.value = new Set();
      localDrag.value = null;
    },
  );

  function dragPosition(
    type: LocalDrag["type"],
    id: Id,
    fallback: CommentPosition,
  ): CommentPosition {
    const drag = localDrag.value;
    return drag?.type === type && String(drag.id) === String(id) ? drag.position : fallback;
  }

  const rawPinOrigins = computed(
    () => new Map(options.pins().map((pin) => [String(pin.id), pointOrigin(pin)])),
  );
  const livePinOrigins = computed(() => {
    const origins = new Map(rawPinOrigins.value);
    for (const pin of options.pinConfigs()) {
      const pixel = dragPosition("pin", pin.id, pin);
      origins.set(String(pin.id), options.projection().pixelToPercent(pixel.x, pixel.y));
    }
    return origins;
  });

  const origins = computed<SceneCommentOrigin[]>(() => {
    const entries: SceneCommentOrigin[] = [];
    for (const pin of options.pins())
      entries.push({ type: "scene_pin", id: pin.id, position: pointOrigin(pin) });
    for (const annotation of options.annotations())
      entries.push({
        type: "scene_annotation",
        id: annotation.id,
        position: pointOrigin(annotation),
      });
    for (const zone of options.zones()) {
      if (!zone.vertices?.length) continue;
      entries.push({
        type: "scene_zone",
        id: zone.id,
        position: {
          x: Math.min(...zone.vertices.map((point) => point.x)),
          y: Math.min(...zone.vertices.map((point) => point.y)),
        },
      });
    }
    for (const connection of options.connections()) {
      const position = connectionOrigin(connection, rawPinOrigins.value);
      if (position) entries.push({ type: "scene_connection", id: connection.id, position });
    }
    return entries;
  });

  const targets = computed<SceneCommentTargets>(() => {
    const connections = new Map(
      options.connections().map((connection) => [String(connection.id), connection]),
    );
    const override = options.waypointOverride?.();
    const renderedConnections: SceneCommentTargets["connections"][number][] = [];
    for (const config of options.connectionConfigs()) {
      const connection = connections.get(String(config.id));
      if (!connection) continue;
      const waypoints =
        override && String(override.connectionId) === String(config.id)
          ? override.waypoints
          : connection.waypoints;
      const origin = connectionOrigin(connection, livePinOrigins.value, waypoints);
      if (origin)
        renderedConnections.push({
          ...config,
          origin,
          label: connection.label,
          freeEndpoint: connection.fromPinId === null || connection.toPinId === null,
        });
    }
    return {
      pins: options.pinConfigs().map((pin) => ({ ...pin, ...dragPosition("pin", pin.id, pin) })),
      zones: options.zoneConfigs(),
      connections: renderedConnections,
      annotations: options.annotationConfigs().map((annotation) => ({
        ...annotation,
        ...dragPosition("annotation", annotation.id, annotation),
      })),
      layers: effectiveLayers.value,
      origins: origins.value,
    };
  });

  function contextLayers(context: Context): Id[] {
    const matches = (target: { id: Id }) => String(target.id) === context.id;
    const simpleTargets = {
      scene_pin: options.pins(),
      scene_zone: options.zones(),
      scene_annotation: options.annotations(),
    };
    if (Object.hasOwn(simpleTargets, context.type)) {
      const target = simpleTargets[context.type as keyof typeof simpleTargets].find(matches);
      return target?.layerId == null ? [] : [target.layerId];
    }
    if (context.type !== "scene_connection") return [];
    const connection = options.connections().find(matches);
    // A free endpoint keeps the route visible regardless of the other endpoint's layer.
    if (!connection || connection.fromPinId === null || connection.toPinId === null) return [];
    const pinIds = new Set([String(connection.fromPinId), String(connection.toPinId)]);
    const endpoints = options.pins().filter((pin) => pinIds.has(String(pin.id)));
    if (endpoints.some((pin) => pin.layerId == null)) return [];
    return endpoints.flatMap((pin) => (pin.layerId == null ? [] : [pin.layerId]));
  }

  const hiddenLayerIds = computed(() => {
    const context = options.context();
    if (!context || context.status === "unavailable") return [];
    const ids = contextLayers(context);
    const layers = new Map(effectiveLayers.value.map((layer) => [String(layer.id), layer.visible]));
    // Connections render when either endpoint is visible.
    if (context.type === "scene_connection" && ids.some((id) => layers.get(String(id)) !== false))
      return [];
    return ids.filter((id) => layers.get(String(id)) === false);
  });
  const hiddenContext = computed(() => hiddenLayerIds.value.length > 0);
  const locallyRevealed = computed(() =>
    options.layers().some((layer) => !layer.visible && revealedLayers.value.has(String(layer.id))),
  );

  function revealContext() {
    revealedLayers.value = new Set([...revealedLayers.value, ...hiddenLayerIds.value.map(String)]);
  }
  function resetLocalLayers() {
    revealedLayers.value = new Set();
  }
  function trackDrag(type: string, id: Id, position: CommentPosition) {
    if (type === "pin" || type === "annotation") localDrag.value = { type, id, position };
  }
  function clearDrag() {
    localDrag.value = null;
  }

  return {
    targets,
    effectiveLayers,
    draftStorageKey,
    hiddenContext,
    locallyRevealed,
    revealContext,
    resetLocalLayers,
    trackDrag,
    clearDrag,
  };
}
