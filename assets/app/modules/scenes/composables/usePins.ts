import { computed, type ComputedRef, type Ref } from "vue";
import {
  DEFAULT_PIN_COLOR,
  PIN_SIZES,
  renderInitialsCanvas,
  renderLockBadge,
  renderPinIcon,
} from "../lib/pin-icons";
import { useImageLoader } from "./useImageLoader";
import { useHiddenLayerIds, type LayerData } from "./useLayerVisibility";

interface PinData {
  id: number | string;
  positionX: number;
  positionY: number;
  size: string | null;
  color: string | null;
  opacity: number | null;
  pinType: string;
  label: string | null;
  locked: boolean;
  layerId: number | string | null;
  hidden: boolean;
  iconAssetUrl: string | null;
  sheetAvatarUrl: string | null;
  sheetId: number | string | null;
  position: number | null;
}

interface EntityLock {
  userId: number | string;
}

interface PixelPoint {
  x: number;
  y: number;
}

export interface PinConfig {
  id: number | string;
  x: number;
  y: number;
  radius: number;
  diameter: number;
  color: string;
  opacity: number;
  image: HTMLImageElement | null;
  iconCanvas: HTMLCanvasElement | null;
  initialsCanvas: HTMLCanvasElement | null;
  label: string | null;
  isLockedByOther: boolean;
  lockBadge: HTMLCanvasElement | null;
  isSelected: boolean;
  listening: boolean;
  draggable: boolean;
}

type MaybeComputedRef<T> = Ref<T> | ComputedRef<T>;

interface UsePinsOpts {
  pins: MaybeComputedRef<PinData[]>;
  layers: MaybeComputedRef<LayerData[]>;
  entityLocks: MaybeComputedRef<Record<string, EntityLock>>;
  currentUserId: MaybeComputedRef<number | string>;
  percentToPixel: (pctX: number, pctY: number) => PixelPoint;
  activeTool?: MaybeComputedRef<string>;
  selectedType?: MaybeComputedRef<string | null>;
  selectedId?: MaybeComputedRef<number | string | null>;
  isSelectMode?: MaybeComputedRef<boolean>;
  editMode?: MaybeComputedRef<boolean>;
  canEdit?: MaybeComputedRef<boolean>;
}

/**
 * Composable for computing pin render configs from raw pin data.
 * Handles layer filtering, coordinate conversion, image resolution, and lock state.
 */
export function usePins({
  pins,
  layers,
  entityLocks,
  currentUserId,
  percentToPixel,
  activeTool,
  selectedType,
  selectedId,
  isSelectMode,
  editMode,
  canEdit,
}: UsePinsOpts) {
  const hiddenLayerIds = useHiddenLayerIds(layers);

  const visiblePins = computed(() =>
    pins.value.filter((pin) => {
      // hidden field is for exploration mode, not editor -- don't filter by it
      if (pin.layerId && hiddenLayerIds.value.has(pin.layerId)) {
        return false;
      }
      return true;
    }),
  );

  // Collect URLs for pins that need async image loading
  const pinImageUrls = computed(() => {
    const map = new Map<number | string, string | null>();
    for (const pin of visiblePins.value) {
      const url = pin.iconAssetUrl || pin.sheetAvatarUrl || null;
      if (url) {
        map.set(pin.id, url);
      }
    }
    return map;
  });

  const { images: loadedImages } = useImageLoader(pinImageUrls);

  const pinConfigs = computed<PinConfig[]>(() =>
    visiblePins.value
      .slice()
      .sort((a, b) => (a.position || 0) - (b.position || 0))
      .map((pin) => {
        const pos = percentToPixel(pin.positionX, pin.positionY);
        const sizeKey = pin.size || "md";
        const dims = PIN_SIZES[sizeKey] || PIN_SIZES.md;
        const color = pin.color || DEFAULT_PIN_COLOR;
        const opacity = pin.opacity ?? 1;
        const radius = dims.diameter / 2;

        // Lock state
        const lock = entityLocks.value[String(pin.id)];
        const isLockedByOther = !!lock && String(lock.userId) !== String(currentUserId.value);

        // Determine render mode: image > initials > icon
        const loadedImg = loadedImages.value[pin.id] || null;
        let image: HTMLImageElement | null = null;
        let iconCanvas: HTMLCanvasElement | null = null;
        let initialsCanvas: HTMLCanvasElement | null = null;

        if (loadedImg) {
          image = loadedImg;
        } else if (pin.sheetId && !pin.sheetAvatarUrl) {
          const initials = (pin.label || "?").slice(0, 2).toUpperCase();
          initialsCanvas = renderInitialsCanvas(initials, color, sizeKey, opacity);
        } else {
          iconCanvas = renderPinIcon(pin.pinType, color, sizeKey, opacity);
        }

        return {
          id: pin.id,
          x: pos.x,
          y: pos.y,
          radius,
          diameter: dims.diameter,
          color,
          opacity,
          image,
          iconCanvas,
          initialsCanvas,
          label: pin.label,
          isLockedByOther,
          lockBadge: isLockedByOther ? renderLockBadge() : null,
          isSelected: selectedType?.value === "pin" && selectedId?.value === pin.id,
          listening: (isSelectMode?.value || activeTool?.value === "connector") ?? false,
          draggable: !!(
            isSelectMode?.value &&
            editMode?.value &&
            canEdit?.value &&
            !pin.locked &&
            !isLockedByOther
          ),
        };
      }),
  );

  return { pinConfigs };
}
