import { computed, type ComputedRef, type Ref } from "vue";
import { renderLockBadge } from "../lib/pin-icons";
import { useHiddenLayerIds, type LayerData } from "./useLayerVisibility";

const DEFAULT_FILL_COLOR = "#3b82f6";
const DEFAULT_BORDER_COLOR = "#1e40af";

const DASH_PATTERNS: Record<string, number[] | null> = {
  solid: null,
  dashed: [10, 6],
  dotted: [3, 6],
};

interface Vertex {
  x: number;
  y: number;
}

interface PixelPoint {
  x: number;
  y: number;
}

interface ZoneData {
  id: number | string;
  name: string;
  vertices: Vertex[] | null;
  fillColor: string | null;
  borderColor: string | null;
  borderWidth: number | null;
  borderStyle: string | null;
  opacity: number | null;
  position: number | null;
  layerId: number | string | null;
  locked: boolean;
}

interface EntityLock {
  userId: number | string;
}

interface ZoneDragOverride {
  id: number | string;
  vertices: Vertex[];
}

export interface ZoneConfig {
  id: number | string;
  name: string;
  points: number[];
  centroidX: number;
  centroidY: number;
  fill: string;
  stroke: string;
  strokeWidth: number;
  dash: number[] | null;
  opacity: number;
  isLockedByOther: boolean;
  lockBadge: HTMLCanvasElement | null;
  lockBadgeX: number;
  lockBadgeY: number;
  isSelected: boolean;
  listening: boolean;
  hitStrokeWidth: number;
}

type MaybeComputedRef<T> = Ref<T> | ComputedRef<T>;

interface UseZonesOpts {
  zones: MaybeComputedRef<ZoneData[]>;
  layers: MaybeComputedRef<LayerData[]>;
  entityLocks: MaybeComputedRef<Record<string, EntityLock>>;
  currentUserId: MaybeComputedRef<number | string>;
  percentToPixel: (pctX: number, pctY: number) => PixelPoint;
  selectedType?: MaybeComputedRef<string | null>;
  selectedId?: MaybeComputedRef<number | string | null>;
  isSelectMode?: MaybeComputedRef<boolean>;
  zoneDragOverride?: MaybeComputedRef<ZoneDragOverride | null>;
  editingZoneId?: MaybeComputedRef<number | string | null>;
  editingVertices?: MaybeComputedRef<Vertex[]>;
}

/** Resolve which vertices to use: editing > drag override > zone data */
function resolveZoneVertices(
  zone: ZoneData,
  editingZoneId: UseZonesOpts["editingZoneId"],
  editingVertices: UseZonesOpts["editingVertices"],
  zoneDragOverride: UseZonesOpts["zoneDragOverride"],
): Vertex[] {
  if (editingZoneId?.value === zone.id && editingVertices?.value?.length) {
    return editingVertices!.value;
  }
  const override = zoneDragOverride?.value;
  if (override && override.id === zone.id) {
    return override.vertices;
  }
  return zone.vertices || [];
}

interface CentroidResult {
  points: number[];
  centroidX: number;
  centroidY: number;
  maxX: number;
  minY: number;
}

/** Convert vertices to flat points array and compute centroid + extremes */
function calculateZoneGeometry(pixelCoords: PixelPoint[]): CentroidResult {
  const points: number[] = [];
  let sumX = 0;
  let sumY = 0;
  let maxX = -Infinity;
  let minY = Infinity;

  for (const p of pixelCoords) {
    points.push(p.x, p.y);
    sumX += p.x;
    sumY += p.y;
    if (p.x > maxX) maxX = p.x;
    if (p.y < minY) minY = p.y;
  }

  const count = pixelCoords.length || 1;
  return { points, centroidX: sumX / count, centroidY: sumY / count, maxX, minY };
}

/** Build a single ZoneConfig from zone data and precomputed geometry */
function buildZoneConfig(
  zone: ZoneData,
  geo: CentroidResult,
  isLockedByOther: boolean,
  isSelected: boolean,
  listening: boolean,
): ZoneConfig {
  return {
    id: zone.id,
    name: zone.name,
    points: geo.points,
    centroidX: geo.centroidX,
    centroidY: geo.centroidY,
    fill: zone.fillColor || DEFAULT_FILL_COLOR,
    stroke: zone.borderColor || DEFAULT_BORDER_COLOR,
    strokeWidth: zone.borderWidth ?? 2,
    dash: DASH_PATTERNS[zone.borderStyle || "solid"] || null,
    opacity: zone.opacity ?? 0.3,
    isLockedByOther,
    lockBadge: isLockedByOther ? renderLockBadge() : null,
    lockBadgeX: geo.maxX - 4,
    lockBadgeY: geo.minY - 10,
    isSelected,
    listening,
    hitStrokeWidth: 20,
  };
}

/**
 * Composable for computing zone render configs from raw zone data.
 * Handles layer filtering, vertex coordinate conversion, style mapping, and lock state.
 */
export function useZones({
  zones,
  layers,
  entityLocks,
  currentUserId,
  percentToPixel,
  selectedType,
  selectedId,
  isSelectMode,
  zoneDragOverride,
  editingZoneId,
  editingVertices,
}: UseZonesOpts) {
  const hiddenLayerIds = useHiddenLayerIds(layers);

  const visibleZones = computed(() =>
    zones.value.filter((zone) => !(zone.layerId && hiddenLayerIds.value.has(zone.layerId))),
  );

  const zoneConfigs = computed<ZoneConfig[]>(() =>
    visibleZones.value
      .slice()
      .sort((a, b) => (a.position || 0) - (b.position || 0))
      .map((zone) => {
        const vertices = resolveZoneVertices(zone, editingZoneId, editingVertices, zoneDragOverride);
        const pixelCoords = vertices.map((v) => percentToPixel(v.x, v.y));
        const geo = calculateZoneGeometry(pixelCoords);

        const lock = entityLocks.value[String(zone.id)];
        const isLockedByOther = !!lock && String(lock.userId) !== String(currentUserId.value);
        const isSelected = selectedType?.value === "zone" && selectedId?.value === zone.id;

        return buildZoneConfig(zone, geo, isLockedByOther, isSelected, isSelectMode?.value ?? false);
      }),
  );

  return { zoneConfigs };
}
