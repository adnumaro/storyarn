import {
  inject,
  onBeforeUnmount,
  onMounted,
  provide,
  ref,
  watch,
  type InjectionKey,
  type Ref,
} from "vue";
import { useLive } from "@shared/composables/useLive";

export type SceneElementType = "annotation" | "connection" | "pin" | "zone";

export type SceneElementPatch = Record<string, unknown>;

interface SceneElementData {
  id: number | string;
}

interface PendingPatch {
  values: SceneElementPatch;
  timers: Map<string, number>;
}

interface OptimisticSceneElementsOptions<
  TPin extends SceneElementData,
  TZone extends SceneElementData,
  TConnection extends SceneElementData,
  TAnnotation extends SceneElementData,
> {
  pins: () => TPin[];
  zones: () => TZone[];
  connections: () => TConnection[];
  annotations: () => TAnnotation[];
}

interface OptimisticSceneElements<
  TPin extends SceneElementData,
  TZone extends SceneElementData,
  TConnection extends SceneElementData,
  TAnnotation extends SceneElementData,
> {
  pinItems: Ref<TPin[]>;
  zoneItems: Ref<TZone[]>;
  connectionItems: Ref<TConnection[]>;
  annotationItems: Ref<TAnnotation[]>;
  updateElement: SceneElementOptimisticUpdater;
}

export type SceneElementOptimisticUpdater = (
  type: SceneElementType,
  id: number | string,
  patch: SceneElementPatch,
) => void;

export const sceneElementOptimisticUpdaterKey: InjectionKey<SceneElementOptimisticUpdater> = Symbol(
  "scene-element-optimistic-updater",
);

export function useSceneElementOptimisticUpdater(): SceneElementOptimisticUpdater {
  return inject(sceneElementOptimisticUpdaterKey, () => {});
}

const EVENT_FIELD_ALIASES: Record<string, string> = {
  action_data: "actionData",
  action_type: "actionType",
  avatar_url: "sheetAvatarUrl",
  bidirectional: "bidirectional",
  border_color: "borderColor",
  border_style: "borderStyle",
  border_width: "borderWidth",
  color: "color",
  fill_color: "fillColor",
  flow_id: "flowId",
  font_size: "fontSize",
  from_pause_ms: "fromPauseMs",
  from_pin_id: "fromPinId",
  from_stop: "fromStop",
  hidden: "hidden",
  icon_asset_url: "iconAssetUrl",
  id: "id",
  is_leader: "isLeader",
  is_playable: "isPlayable",
  is_walkable: "isWalkable",
  label: "label",
  label_font_family: "labelFontFamily",
  label_font_size: "labelFontSize",
  label_font_style: "labelFontStyle",
  label_font_weight: "labelFontWeight",
  label_icon_asset_id: "labelIconAssetId",
  label_icon_asset_url: "labelIconAssetUrl",
  label_mode: "labelMode",
  layer_id: "layerId",
  line_style: "lineStyle",
  line_width: "lineWidth",
  locked: "locked",
  name: "name",
  opacity: "opacity",
  patrol_mode: "patrolMode",
  patrol_pause_ms: "patrolPauseMs",
  patrol_speed: "patrolSpeed",
  pin_type: "pinType",
  position: "position",
  position_x: "positionX",
  position_y: "positionY",
  sheet_id: "sheetId",
  show_label: "showLabel",
  size: "size",
  target_id: "targetId",
  target_type: "targetType",
  text: "text",
  to_pin_id: "toPinId",
  to_pause_ms: "toPauseMs",
  to_stop: "toStop",
  vertices: "vertices",
  waypoints: "waypoints",
};

const REMOTE_DRAG_CLEAR_TIMEOUT_MS = 1500;
const EVENT_METADATA_FIELDS = new Set(["user_id", "user_email", "user_color"]);

function itemId(item: SceneElementData): string {
  return String(item.id);
}

function cloneItem<T extends SceneElementData>(item: T): T {
  return { ...item };
}

function valuesMatch(a: unknown, b: unknown): boolean {
  if (
    (typeof a === "number" || typeof a === "string" || typeof a === "boolean") &&
    (typeof b === "number" || typeof b === "string" || typeof b === "boolean")
  ) {
    return String(a) === String(b);
  }

  return JSON.stringify(a) === JSON.stringify(b);
}

function normalizeServerPayload<T extends SceneElementData>(payload: Record<string, unknown>): T {
  const normalized: Record<string, unknown> = {};

  for (const [key, value] of Object.entries(payload)) {
    normalized[EVENT_FIELD_ALIASES[key] || key] = value;
  }

  return normalized as T;
}

export function useOptimisticSceneElements<
  TPin extends SceneElementData,
  TZone extends SceneElementData,
  TConnection extends SceneElementData,
  TAnnotation extends SceneElementData,
>({
  pins,
  zones,
  connections,
  annotations,
}: OptimisticSceneElementsOptions<TPin, TZone, TConnection, TAnnotation>): OptimisticSceneElements<
  TPin,
  TZone,
  TConnection,
  TAnnotation
> {
  const live = useLive();
  const pinItems = ref<TPin[]>([]) as Ref<TPin[]>;
  const zoneItems = ref<TZone[]>([]) as Ref<TZone[]>;
  const connectionItems = ref<TConnection[]>([]) as Ref<TConnection[]>;
  const annotationItems = ref<TAnnotation[]>([]) as Ref<TAnnotation[]>;

  const pendingPatches: Record<SceneElementType, Map<string, PendingPatch>> = {
    annotation: new Map(),
    connection: new Map(),
    pin: new Map(),
    zone: new Map(),
  };
  const remoteDragTimers: Record<SceneElementType, Map<string, number>> = {
    annotation: new Map(),
    connection: new Map(),
    pin: new Map(),
    zone: new Map(),
  };

  const listRefs = {
    annotation: annotationItems,
    connection: connectionItems,
    pin: pinItems,
    zone: zoneItems,
  };

  function clearPendingValue(type: SceneElementType, id: string, field: string): void {
    const pending = pendingPatches[type].get(id);
    if (!pending) return;

    const timer = pending.timers.get(field);
    if (timer) window.clearTimeout(timer);

    pending.timers.delete(field);
    delete pending.values[field];

    if (Object.keys(pending.values).length === 0) {
      pendingPatches[type].delete(id);
    }
  }

  function applyPending<T extends SceneElementData>(type: SceneElementType, incoming: T): T {
    const id = itemId(incoming);
    const pending = pendingPatches[type].get(id);

    if (!pending) {
      return cloneItem(incoming);
    }

    for (const [field, value] of Object.entries(pending.values)) {
      if (valuesMatch((incoming as Record<string, unknown>)[field], value)) {
        clearPendingValue(type, id, field);
      }
    }

    const remaining = pendingPatches[type].get(id)?.values || {};
    return { ...incoming, ...remaining };
  }

  function reconcileList<T extends SceneElementData>(
    type: SceneElementType,
    target: Ref<T[]>,
    incoming: T[],
  ): void {
    target.value = incoming.map((item) => applyPending(type, item));
  }

  function refreshTypeFromProps(type: SceneElementType): void {
    switch (type) {
      case "annotation":
        reconcileList(type, annotationItems, annotations());
        break;
      case "connection":
        reconcileList(type, connectionItems, connections());
        break;
      case "pin":
        reconcileList(type, pinItems, pins());
        break;
      case "zone":
        reconcileList(type, zoneItems, zones());
        break;
    }
  }

  function clearRemoteDragTimer(type: SceneElementType, id: string): void {
    const timer = remoteDragTimers[type].get(id);
    if (!timer) return;

    window.clearTimeout(timer);
    remoteDragTimers[type].delete(id);
  }

  function scheduleRemoteDragClear(type: SceneElementType, id: string): void {
    clearRemoteDragTimer(type, id);

    remoteDragTimers[type].set(
      id,
      window.setTimeout(() => {
        remoteDragTimers[type].delete(id);
        refreshTypeFromProps(type);
      }, REMOTE_DRAG_CLEAR_TIMEOUT_MS),
    );
  }

  function rememberPendingPatch(
    type: SceneElementType,
    id: string,
    patch: SceneElementPatch,
  ): void {
    const pending = pendingPatches[type].get(id) || { values: {}, timers: new Map() };

    for (const [field, value] of Object.entries(patch)) {
      const existingTimer = pending.timers.get(field);
      if (existingTimer) window.clearTimeout(existingTimer);

      pending.values[field] = value;
      pending.timers.set(
        field,
        window.setTimeout(() => {
          clearPendingValue(type, id, field);
          refreshTypeFromProps(type);
        }, 5000),
      );
    }

    pendingPatches[type].set(id, pending);
  }

  function patchLocalElement(
    type: SceneElementType,
    id: number | string,
    patch: SceneElementPatch,
  ): void {
    const target = listRefs[type];
    const normalizedId = String(id);
    let matched = false;

    target.value = target.value.map((item) => {
      if (itemId(item) !== normalizedId) {
        return item;
      }

      matched = true;
      return { ...item, ...patch };
    });

    if (matched) {
      rememberPendingPatch(type, normalizedId, patch);
    }
  }

  function upsertServerElement<T extends SceneElementData>(
    type: SceneElementType,
    target: Ref<T[]>,
    payload: Record<string, unknown>,
  ): void {
    const incoming = normalizeServerPayload<T>(payload);
    const normalizedId = itemId(incoming);
    let matched = false;
    const next = applyPending(type, incoming);
    clearRemoteDragTimer(type, normalizedId);

    target.value = target.value.map((item) => {
      if (itemId(item) !== normalizedId) {
        return item;
      }

      matched = true;
      return next;
    });

    if (!matched) {
      target.value = [...target.value, next];
    }
  }

  function removeServerElement<T extends SceneElementData>(
    type: SceneElementType,
    target: Ref<T[]>,
    payload: Record<string, unknown>,
  ): void {
    const id = payload.id;
    if (id === undefined || id === null) return;

    pendingPatches[type].delete(String(id));
    clearRemoteDragTimer(type, String(id));
    target.value = target.value.filter((item) => itemId(item) !== String(id));
  }

  function remoteDragPatch(payload: Record<string, unknown>): SceneElementPatch {
    const normalized = normalizeServerPayload<SceneElementData & Record<string, unknown>>(payload);
    const patch: SceneElementPatch = {};

    for (const [field, value] of Object.entries(normalized)) {
      if (field === "id" || EVENT_METADATA_FIELDS.has(field)) continue;
      patch[field] = value;
    }

    return patch;
  }

  function applyRemoteDragPatch<T extends SceneElementData>(
    type: SceneElementType,
    target: Ref<T[]>,
    payload: Record<string, unknown>,
  ): void {
    const id = payload.id;
    if (id === undefined || id === null) return;

    const normalizedId = String(id);
    const patch = remoteDragPatch(payload);
    if (Object.keys(patch).length === 0) return;

    target.value = target.value.map((item) => {
      if (itemId(item) !== normalizedId) {
        return item;
      }

      return { ...item, ...patch };
    });

    scheduleRemoteDragClear(type, normalizedId);
  }

  watch(pins, (next) => reconcileList("pin", pinItems, next), { immediate: true, deep: true });

  watch(zones, (next) => reconcileList("zone", zoneItems, next), { immediate: true, deep: true });

  watch(connections, (next) => reconcileList("connection", connectionItems, next), {
    immediate: true,
    deep: true,
  });

  watch(annotations, (next) => reconcileList("annotation", annotationItems, next), {
    immediate: true,
    deep: true,
  });

  onMounted(() => {
    live.handleEvent("pin_created", (payload) => upsertServerElement("pin", pinItems, payload));
    live.handleEvent("pin_updated", (payload) => upsertServerElement("pin", pinItems, payload));
    live.handleEvent("pin_drag_update", (payload) =>
      applyRemoteDragPatch("pin", pinItems, payload),
    );
    live.handleEvent("pin_deleted", (payload) => removeServerElement("pin", pinItems, payload));
    live.handleEvent("zone_created", (payload) => upsertServerElement("zone", zoneItems, payload));
    live.handleEvent("zone_updated", (payload) => upsertServerElement("zone", zoneItems, payload));
    live.handleEvent("zone_vertices_updated", (payload) =>
      upsertServerElement("zone", zoneItems, payload),
    );
    live.handleEvent("zone_drag_update", (payload) =>
      applyRemoteDragPatch("zone", zoneItems, payload),
    );
    live.handleEvent("zone_deleted", (payload) => removeServerElement("zone", zoneItems, payload));
    live.handleEvent("connection_created", (payload) =>
      upsertServerElement("connection", connectionItems, payload),
    );
    live.handleEvent("connection_updated", (payload) =>
      upsertServerElement("connection", connectionItems, payload),
    );
    live.handleEvent("connection_deleted", (payload) =>
      removeServerElement("connection", connectionItems, payload),
    );
    live.handleEvent("annotation_created", (payload) =>
      upsertServerElement("annotation", annotationItems, payload),
    );
    live.handleEvent("annotation_updated", (payload) =>
      upsertServerElement("annotation", annotationItems, payload),
    );
    live.handleEvent("annotation_drag_update", (payload) =>
      applyRemoteDragPatch("annotation", annotationItems, payload),
    );
    live.handleEvent("annotation_deleted", (payload) =>
      removeServerElement("annotation", annotationItems, payload),
    );
  });

  onBeforeUnmount(() => {
    for (const timers of Object.values(remoteDragTimers)) {
      for (const timer of timers.values()) {
        window.clearTimeout(timer);
      }

      timers.clear();
    }
  });

  provide(sceneElementOptimisticUpdaterKey, patchLocalElement);

  return {
    annotationItems,
    connectionItems,
    pinItems,
    updateElement: patchLocalElement,
    zoneItems,
  };
}
