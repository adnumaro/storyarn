import { computed, type ComputedRef, type Ref } from "vue";
import { renderLockBadge } from "../lib/pin-icons";
import { useImageLoader } from "./useImageLoader";
import { useHiddenLayerIds, type LayerData } from "./useLayerVisibility";

const DEFAULT_FILL_COLOR = "#3b82f6";
const DEFAULT_BORDER_COLOR = "#1e40af";
const LABEL_MIN_WIDTH = 40;
const LABEL_MAX_WIDTH = 180;
const LABEL_LINE_HEIGHT = 16;
const LABEL_PADDING_X = 8;
const LABEL_ICON_GAP = 4;
let labelMeasureContext: CanvasRenderingContext2D | null | undefined;

const FONT_FAMILIES: Record<string, string> = {
  system: "system-ui, sans-serif",
  serif: "serif",
  mono: "ui-monospace, monospace",
  display: "Georgia, serif",
};

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
  actionType?: string | null;
  actionData?: { display_mode?: string | null } | null;
  displayValue?: string | null;
  labelMode?: string | null;
  labelFontSize?: number | null;
  labelFontFamily?: string | null;
  labelFontWeight?: string | null;
  labelFontStyle?: string | null;
  labelIconAssetUrl?: string | null;
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
  labelX: number;
  labelY: number;
  labelWidth: number;
  labelHeight: number;
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
  labelText: string | null;
  labelFontSize: number;
  labelFontFamily: string;
  labelFontStyle: string;
  labelIconCanvas: HTMLCanvasElement | HTMLImageElement | null;
  labelIconSize: number;
  labelIconX: number;
  labelIconY: number;
  labelTextX: number;
  showLabelText: boolean;
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
  showEditorLabels?: boolean;
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

function getLabelMeasureContext(): CanvasRenderingContext2D | null {
  if (labelMeasureContext !== undefined) {
    return labelMeasureContext;
  }

  if (typeof document === "undefined") {
    labelMeasureContext = null;
    return labelMeasureContext;
  }

  const canvas = document.createElement("canvas");
  labelMeasureContext = canvas.getContext("2d");
  return labelMeasureContext;
}

function labelFont(zone: ZoneData): {
  size: number;
  family: string;
  style: string;
  weight: string;
} {
  const size = zone.labelFontSize || 12;
  const family = FONT_FAMILIES[zone.labelFontFamily || "system"] || FONT_FAMILIES.system;
  const style = zone.labelFontStyle || "normal";
  const weight = zone.labelFontWeight || "600";

  return { size, family, style, weight };
}

function konvaFontStyle(font: { style: string; weight: string }): string {
  const style = font.style === "italic" ? "italic" : "";
  return [style, font.weight].filter(Boolean).join(" ") || "normal";
}

function fontString(zone: ZoneData): string {
  const font = labelFont(zone);
  return `${konvaFontStyle(font)} ${font.size}px ${font.family}`;
}

function measureTextWidth(text: string, font: string): number {
  const context = getLabelMeasureContext();

  if (!context) {
    return text.length * 7;
  }

  context.font = font;
  return context.measureText(text).width;
}

function wrapLabelLines(name: string, font: string): string[] {
  const words = name.trim().split(/\s+/);
  const contentMaxWidth = LABEL_MAX_WIDTH - LABEL_PADDING_X;

  if (words.length <= 1 || measureTextWidth(name, font) <= contentMaxWidth) {
    return [name];
  }

  const lines: string[] = [];
  let currentLine = "";

  for (const word of words) {
    const nextLine = currentLine ? `${currentLine} ${word}` : word;

    if (!currentLine || measureTextWidth(nextLine, font) <= contentMaxWidth) {
      currentLine = nextLine;
    } else {
      lines.push(currentLine);
      currentLine = word;
    }
  }

  if (currentLine) {
    lines.push(currentLine);
  }

  return lines;
}

function displayValueText(zone: ZoneData): string | null {
  return zone.displayValue != null && zone.displayValue !== "" ? String(zone.displayValue) : null;
}

function displayZoneLabelText(zone: ZoneData): string | null {
  const displayValue = displayValueText(zone);

  if (zone.actionData?.display_mode === "label_value" && zone.name && displayValue) {
    return `${zone.name}: ${displayValue}`;
  }

  return displayValue || zone.name || null;
}

function zoneLabelText(zone: ZoneData): string | null {
  return zone.actionType === "display" ? displayZoneLabelText(zone) : zone.name || null;
}

function textOnlyLabelVisibility(labelText: string | null) {
  return {
    showText: !!labelText,
    showIcon: false,
  };
}

function nonDisplayLabelVisibility(
  zone: ZoneData,
  labelText: string | null,
  showEditorLabels: boolean,
) {
  const mode = zone.labelMode || "text";

  if (mode === "none" && showEditorLabels && zone.name) {
    return {
      showText: true,
      showIcon: false,
    };
  }

  return {
    showText: (mode === "text" || mode === "both") && !!labelText,
    showIcon: (mode === "icon" || mode === "both") && !!zone.labelIconAssetUrl,
  };
}

function labelVisibility(zone: ZoneData, labelText: string | null, showEditorLabels: boolean) {
  return zone.actionType === "display"
    ? textOnlyLabelVisibility(labelText)
    : nonDisplayLabelVisibility(zone, labelText, showEditorLabels);
}

function textBlockSize(labelText: string, font: string, iconSize: number) {
  const lines = wrapLabelLines(labelText, font);
  const widestLine = Math.max(...lines.map((line) => measureTextWidth(line, font)));

  return {
    width: widestLine,
    height: lines.length * Math.max(LABEL_LINE_HEIGHT, iconSize + 2),
  };
}

function calculateZoneLabelSize(
  zone: ZoneData,
  labelText: string | null,
  showEditorLabels: boolean,
) {
  const { showText, showIcon } = labelVisibility(zone, labelText, showEditorLabels);
  if (!showText && !showIcon) return { width: 0, height: 0 };

  const iconSize = zone.labelFontSize || 12;
  const textSize = showText
    ? textBlockSize(labelText || "", fontString(zone), iconSize)
    : { width: 0, height: 0 };
  const iconWidth = showIcon ? iconSize : 0;
  const gap = showIcon && showText ? LABEL_ICON_GAP : 0;
  const naturalWidth = textSize.width + iconWidth + gap + LABEL_PADDING_X;

  return {
    width: Math.ceil(Math.min(LABEL_MAX_WIDTH, Math.max(LABEL_MIN_WIDTH, naturalWidth))),
    height: Math.max(textSize.height, showIcon ? iconSize : 0),
  };
}

function zoneLabelLayout(
  zone: ZoneData,
  geo: CentroidResult,
  labelSize: { width: number; height: number },
) {
  const font = labelFont(zone);
  const iconSize = font.size;
  const labelX = geo.centroidX - labelSize.width / 2;
  const labelY = geo.centroidY - labelSize.height / 2;
  const iconX = labelX + LABEL_PADDING_X / 2;
  const iconY = geo.centroidY - iconSize / 2;

  return {
    font,
    iconSize,
    labelX,
    labelY,
    iconX,
    iconY,
  };
}

function resolveZoneIconCanvas(
  zone: ZoneData,
  showIcon: boolean,
  iconSize: number,
  iconAssetImage: HTMLImageElement | null,
) {
  if (!showIcon) return null;
  return iconAssetImage;
}

/** Build a single ZoneConfig from zone data and precomputed geometry */
function buildZoneConfig(
  zone: ZoneData,
  geo: CentroidResult,
  isLockedByOther: boolean,
  isSelected: boolean,
  listening: boolean,
  showEditorLabels: boolean,
  iconAssetImage: HTMLImageElement | null,
): ZoneConfig {
  const labelText = zoneLabelText(zone);
  const labelSize = calculateZoneLabelSize(zone, labelText, showEditorLabels);
  const { showText, showIcon } = labelVisibility(zone, labelText, showEditorLabels);
  const layout = zoneLabelLayout(zone, geo, labelSize);
  const iconCanvas = resolveZoneIconCanvas(
    zone,
    showIcon,
    layout.iconSize,
    iconAssetImage,
  );
  const textX = iconCanvas ? layout.iconX + layout.iconSize + LABEL_ICON_GAP : layout.labelX;

  return {
    id: zone.id,
    name: zone.name,
    points: geo.points,
    centroidX: geo.centroidX,
    centroidY: geo.centroidY,
    labelX: layout.labelX,
    labelY: layout.labelY,
    labelWidth: labelSize.width,
    labelHeight: labelSize.height,
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
    labelText,
    labelFontSize: layout.font.size,
    labelFontFamily: layout.font.family,
    labelFontStyle: konvaFontStyle(layout.font),
    labelIconCanvas: iconCanvas,
    labelIconSize: layout.iconSize,
    labelIconX: layout.iconX,
    labelIconY: layout.iconY,
    labelTextX: textX,
    showLabelText: showText,
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
  showEditorLabels = false,
}: UseZonesOpts) {
  const hiddenLayerIds = useHiddenLayerIds(layers);

  const visibleZones = computed(() =>
    zones.value.filter((zone) => !(zone.layerId && hiddenLayerIds.value.has(zone.layerId))),
  );

  const zoneIconUrls = computed(() => {
    const map = new Map<number | string, string | null>();
    for (const zone of visibleZones.value) {
      if (zone.labelIconAssetUrl) {
        map.set(zone.id, zone.labelIconAssetUrl);
      }
    }
    return map;
  });

  const { images: loadedIconImages } = useImageLoader(zoneIconUrls);

  const zoneConfigs = computed<ZoneConfig[]>(() => {
    return visibleZones.value
      .slice()
      .sort((a, b) => (a.position || 0) - (b.position || 0))
      .map((zone) => {
        const vertices = resolveZoneVertices(
          zone,
          editingZoneId,
          editingVertices,
          zoneDragOverride,
        );
        const pixelCoords = vertices.map((v) => percentToPixel(v.x, v.y));
        const geo = calculateZoneGeometry(pixelCoords);

        const lock = entityLocks.value[String(zone.id)];
        const isLockedByOther = !!lock && String(lock.userId) !== String(currentUserId.value);
        const isSelected =
          selectedType?.value === "zone" && String(selectedId?.value) === String(zone.id);

        return buildZoneConfig(
          zone,
          geo,
          isLockedByOther,
          isSelected,
          isSelectMode?.value ?? false,
          showEditorLabels,
          loadedIconImages.value[zone.id] || null,
        );
      });
  });

  return { zoneConfigs };
}
