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

interface PinRenderMode {
  image: HTMLImageElement | null;
  iconCanvas: HTMLCanvasElement | null;
  initialsCanvas: HTMLCanvasElement | null;
}

/** Determine pin visual: loaded image > initials canvas > icon canvas */
function determinePinRenderMode(
  pin: PinData,
  loadedImg: HTMLImageElement | null,
  color: string,
  sizeKey: string,
  opacity: number,
): PinRenderMode {
  if (loadedImg) {
    return { image: loadedImg, iconCanvas: null, initialsCanvas: null };
  }
  if (pin.sheetId && !pin.sheetAvatarUrl) {
    const initials = (pin.label || "?").slice(0, 2).toUpperCase();
    return { image: null, iconCanvas: null, initialsCanvas: renderInitialsCanvas(initials, color, sizeKey, opacity) };
  }
  return { image: null, iconCanvas: renderPinIcon(pin.pinType, color, sizeKey, opacity), initialsCanvas: null };
}

/** Build a single PinConfig from pin data */
function buildPinConfig(
  pin: PinData,
  pos: PixelPoint,
  render: PinRenderMode,
  dims: { diameter: number },
  color: string,
  opacity: number,
  isLockedByOther: boolean,
  isSelected: boolean,
  listening: boolean,
  draggable: boolean,
): PinConfig {
  return {
    id: pin.id,
    x: pos.x,
    y: pos.y,
    radius: dims.diameter / 2,
    diameter: dims.diameter,
    color,
    opacity,
    image: render.image,
    iconCanvas: render.iconCanvas,
    initialsCanvas: render.initialsCanvas,
    label: pin.label,
    isLockedByOther,
    lockBadge: isLockedByOther ? renderLockBadge() : null,
    isSelected,
    listening,
    draggable,
  };
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

  function resolvePinAppearance(pin: PinData) {
    const sizeKey = pin.size || "md";
    const dims = PIN_SIZES[sizeKey] || PIN_SIZES.md;
    const color = pin.color || DEFAULT_PIN_COLOR;
    const opacity = pin.opacity ?? 1;
    const loadedImg = loadedImages.value[pin.id] || null;
    const render = determinePinRenderMode(pin, loadedImg, color, sizeKey, opacity);
    return { dims, color, opacity, render };
  }

  function isPinSelected(pin: PinData): boolean {
    return selectedType?.value === "pin" && selectedId?.value === pin.id;
  }

  function isPinListening(): boolean {
    return (isSelectMode?.value || activeTool?.value === "connector") ?? false;
  }

  function isPinDraggable(pin: PinData, isLockedByOther: boolean): boolean {
    return !!(isSelectMode?.value && editMode?.value && canEdit?.value && !pin.locked && !isLockedByOther);
  }

  function checkPinLock(pin: PinData): boolean {
    const lock = entityLocks.value[String(pin.id)];
    return !!lock && String(lock.userId) !== String(currentUserId.value);
  }

  const pinConfigs = computed<PinConfig[]>(() =>
    visiblePins.value
      .slice()
      .sort((a, b) => (a.position || 0) - (b.position || 0))
      .map((pin) => {
        const pos = percentToPixel(pin.positionX, pin.positionY);
        const { dims, color, opacity, render } = resolvePinAppearance(pin);
        const isLockedByOther = checkPinLock(pin);

        return buildPinConfig(
          pin, pos, render, dims, color, opacity, isLockedByOther,
          isPinSelected(pin), isPinListening(), isPinDraggable(pin, isLockedByOther),
        );
      }),
  );

  return { pinConfigs };
}
