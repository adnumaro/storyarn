import { computed, type Ref } from "vue";
import { renderLockBadge } from "../lib/pin-icons";
import { useHiddenLayerIds, type LayerData } from "./useLayerVisibility";

const FOLD_SIZE = 12;
const DEFAULT_COLOR = "#fbbf24";
const BG_OPACITY = 0.75;
const _TEXT_COLOR = "#111827";

interface AnnotationSizeDims {
  width: number;
  minHeight: number;
  fontSize: number;
  padLeft: number;
  padRight: number;
  padTop: number;
  padBottom: number;
}

const ANNOTATION_SIZES: Record<string, AnnotationSizeDims> = {
  sm: {
    width: 140,
    minHeight: 100,
    fontSize: 11,
    padLeft: 6,
    padRight: 18,
    padTop: 2,
    padBottom: 2,
  },
  md: {
    width: 200,
    minHeight: 150,
    fontSize: 14,
    padLeft: 8,
    padRight: 20,
    padTop: 4,
    padBottom: 4,
  },
  lg: {
    width: 260,
    minHeight: 190,
    fontSize: 16,
    padLeft: 10,
    padRight: 22,
    padTop: 5,
    padBottom: 5,
  },
};

interface AnnotationData {
  id: number | string;
  positionX: number;
  positionY: number;
  text: string | null;
  color: string | null;
  fontSize: string;
  position: number | null;
  layerId: number | string | null;
  locked: boolean;
}

interface EntityLock {
  userId: number | string;
}

interface PixelPoint {
  x: number;
  y: number;
}

export interface AnnotationConfig {
  id: number | string;
  x: number;
  y: number;
  text: string;
  color: string;
  bgOpacity: number;
  width: number;
  height: number;
  fontSize: number;
  padLeft: number;
  padRight: number;
  padTop: number;
  bodyPoints: number[];
  foldPoints: number[];
  textWidth: number;
  locked: boolean;
  isLockedByOther: boolean;
  lockBadge: HTMLCanvasElement | null;
  isSelected: boolean;
  listening: boolean;
  draggable: boolean;
}

interface UseAnnotationsOpts {
  annotations: Ref<AnnotationData[]>;
  layers: Ref<LayerData[]>;
  entityLocks: Ref<Record<string, EntityLock>>;
  currentUserId: Ref<number | string>;
  percentToPixel: (pctX: number, pctY: number) => PixelPoint;
  selectedType: Ref<string | null>;
  selectedId: Ref<number | string | null>;
  isSelectMode: Ref<boolean>;
  editMode: Ref<boolean>;
  canEdit: Ref<boolean>;
}

/** Build shape geometry (body + fold polygons) for an annotation */
function buildAnnotationShape(dims: AnnotationSizeDims): { bodyPoints: number[]; foldPoints: number[] } {
  const w = dims.width;
  const h = dims.minHeight;
  const f = FOLD_SIZE;
  return {
    bodyPoints: [0, 0, w - f, 0, w, f, w, h, 0, h],
    foldPoints: [w - f, 0, w, f, w - f, f],
  };
}

/** Build a single AnnotationConfig from annotation data */
function buildAnnotationConfig(
  ann: AnnotationData,
  pos: PixelPoint,
  dims: AnnotationSizeDims,
  color: string,
  shape: { bodyPoints: number[]; foldPoints: number[] },
  isLockedByOther: boolean,
  isSelected: boolean,
  listening: boolean,
  draggable: boolean,
): AnnotationConfig {
  return {
    id: ann.id,
    x: pos.x,
    y: pos.y,
    text: ann.text || "",
    color,
    bgOpacity: BG_OPACITY,
    width: dims.width,
    height: dims.minHeight,
    fontSize: dims.fontSize,
    padLeft: dims.padLeft,
    padRight: dims.padRight,
    padTop: dims.padTop,
    bodyPoints: shape.bodyPoints,
    foldPoints: shape.foldPoints,
    textWidth: dims.width - dims.padLeft - dims.padRight,
    locked: !!ann.locked,
    isLockedByOther,
    lockBadge: isLockedByOther ? renderLockBadge() : null,
    isSelected,
    listening,
    draggable,
  };
}

/**
 * Composable for computing annotation render configs.
 * Annotations are sticky-note shapes with a folded corner.
 */
export function useAnnotations({
  annotations,
  layers,
  entityLocks,
  currentUserId,
  percentToPixel,
  selectedType,
  selectedId,
  isSelectMode,
  editMode,
  canEdit,
}: UseAnnotationsOpts) {
  const hiddenLayerIds = useHiddenLayerIds(layers);

  const visibleAnnotations = computed(() =>
    annotations.value.filter((ann) => !(ann.layerId && hiddenLayerIds.value.has(ann.layerId))),
  );

  function resolveAnnotationAppearance(ann: AnnotationData) {
    const sizeKey = ANNOTATION_SIZES[ann.fontSize] ? ann.fontSize : "md";
    const dims = ANNOTATION_SIZES[sizeKey];
    const color = ann.color || DEFAULT_COLOR;
    const shape = buildAnnotationShape(dims);
    return { dims, color, shape };
  }

  function checkAnnotationLock(ann: AnnotationData): boolean {
    const lock = entityLocks.value[String(ann.id)];
    return !!lock && String(lock.userId) !== String(currentUserId.value);
  }

  function isAnnotationSelected(ann: AnnotationData): boolean {
    return selectedType?.value === "annotation" && selectedId?.value === ann.id;
  }

  function isAnnotationDraggable(ann: AnnotationData, isLockedByOther: boolean): boolean {
    return !!(isSelectMode?.value && editMode?.value && canEdit?.value && !ann.locked && !isLockedByOther);
  }

  const annotationConfigs = computed<AnnotationConfig[]>(() =>
    visibleAnnotations.value
      .slice()
      .sort((a, b) => (a.position || 0) - (b.position || 0))
      .map((ann) => {
        const pos = percentToPixel(ann.positionX, ann.positionY);
        const { dims, color, shape } = resolveAnnotationAppearance(ann);
        const isLockedByOther = checkAnnotationLock(ann);

        return buildAnnotationConfig(
          ann, pos, dims, color, shape, isLockedByOther,
          isAnnotationSelected(ann), isSelectMode?.value ?? false, isAnnotationDraggable(ann, isLockedByOther),
        );
      }),
  );

  return { annotationConfigs };
}
