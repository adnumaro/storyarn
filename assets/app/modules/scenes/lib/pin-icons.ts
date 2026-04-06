/**
 * Renders Lucide icons and initials to offscreen canvas for Konva image sources.
 * Konva cannot render Vue components, so we render lucide-vue-next icons
 * to a temporary DOM element, extract the SVG, and draw to canvas.
 */

import { Lock, MapPin, Star, User, Zap } from "lucide-vue-next";
import { type Component, createApp, h } from "vue";

const PIN_TYPE_COMPONENTS: Record<string, Component> = {
  location: MapPin,
  character: User,
  event: Zap,
  custom: Star,
};

export interface PinSizeDims {
  diameter: number;
  iconScale: number;
  initialsScale: number;
}

export const PIN_SIZES: Record<string, PinSizeDims> = {
  sm: { diameter: 28, iconScale: 0.55, initialsScale: 0.38 },
  md: { diameter: 36, iconScale: 0.55, initialsScale: 0.38 },
  lg: { diameter: 44, iconScale: 0.55, initialsScale: 0.38 },
};

export const DEFAULT_PIN_COLOR = "#3b82f6";

const iconCache = new Map<string, HTMLCanvasElement>();

function hexToRgba(hex: string, opacity: number): string {
  const r = Number.parseInt(hex.slice(1, 3), 16);
  const g = Number.parseInt(hex.slice(3, 5), 16);
  const b = Number.parseInt(hex.slice(5, 7), 16);
  return `rgba(${r},${g},${b},${opacity ?? 1})`;
}

function drawCircleShadow(
  ctx: CanvasRenderingContext2D,
  cx: number,
  cy: number,
  radius: number,
  fillColor: string,
): void {
  ctx.save();
  ctx.shadowColor = "rgba(0,0,0,0.3)";
  ctx.shadowBlur = 6;
  ctx.shadowOffsetY = 2;
  ctx.beginPath();
  ctx.arc(cx, cy, radius, 0, Math.PI * 2);
  ctx.fillStyle = fillColor;
  ctx.fill();
  ctx.restore();
}

/**
 * Renders a lucide-vue-next icon component to an SVG Image element.
 * Uses a temporary Vue app to render the component, extracts the SVG markup,
 * and creates a data URL Image.
 */
function renderIconToImage(
  IconComponent: Component,
  size: number,
  color: string,
  strokeWidth: number,
): HTMLImageElement {
  const container = document.createElement("div");
  const app = createApp({
    render: () =>
      h(IconComponent, {
        size,
        color,
        strokeWidth,
      }),
  });
  app.mount(container);
  const svgEl = container.querySelector("svg")!;
  const svgStr = new XMLSerializer().serializeToString(svgEl);
  app.unmount();

  const img = new Image();
  img.src = `data:image/svg+xml;base64,${btoa(svgStr)}`;
  return img;
}

/**
 * Renders a pin icon (colored circle + white Lucide icon) to an offscreen canvas.
 */
export function renderPinIcon(
  pinType: string,
  color: string,
  sizeKey: string,
  opacity: number,
): HTMLCanvasElement {
  const key = `icon-${pinType}-${color}-${sizeKey}-${opacity ?? 1}`;
  if (iconCache.has(key)) return iconCache.get(key)!;

  const dims = PIN_SIZES[sizeKey] || PIN_SIZES.md;
  const d = dims.diameter;
  const padding = 8;
  const canvasSize = d + padding * 2;

  const canvas = document.createElement("canvas");
  canvas.width = canvasSize;
  canvas.height = canvasSize;
  const ctx = canvas.getContext("2d")!;

  const cx = canvasSize / 2;
  const cy = canvasSize / 2;
  const fillColor = hexToRgba(color, opacity ?? 1);
  drawCircleShadow(ctx, cx, cy, d / 2, fillColor);

  const IconComponent = PIN_TYPE_COMPONENTS[pinType] || MapPin;
  const iconSize = Math.round(d * dims.iconScale);
  const img = renderIconToImage(IconComponent, iconSize, "#ffffff", 2.5);
  ctx.drawImage(img, cx - iconSize / 2, cy - iconSize / 2, iconSize, iconSize);

  iconCache.set(key, canvas);
  return canvas;
}

/**
 * Renders initials (sheet-linked pin without avatar) to an offscreen canvas.
 */
export function renderInitialsCanvas(
  initials: string,
  color: string,
  sizeKey: string,
  opacity: number,
): HTMLCanvasElement {
  const key = `initials-${initials}-${color}-${sizeKey}-${opacity ?? 1}`;
  if (iconCache.has(key)) return iconCache.get(key)!;

  const dims = PIN_SIZES[sizeKey] || PIN_SIZES.md;
  const d = dims.diameter;
  const padding = 8;
  const canvasSize = d + padding * 2;

  const canvas = document.createElement("canvas");
  canvas.width = canvasSize;
  canvas.height = canvasSize;
  const ctx = canvas.getContext("2d")!;

  const cx = canvasSize / 2;
  const cy = canvasSize / 2;
  const fillColor = hexToRgba(color, opacity ?? 1);
  drawCircleShadow(ctx, cx, cy, d / 2, fillColor);

  const fontSize = Math.round(d * dims.initialsScale);
  ctx.fillStyle = "#ffffff";
  ctx.font = `600 ${fontSize}px system-ui, sans-serif`;
  ctx.textAlign = "center";
  ctx.textBaseline = "middle";
  ctx.fillText(initials, cx, cy);

  iconCache.set(key, canvas);
  return canvas;
}

let lockBadgeCanvas: HTMLCanvasElement | null = null;

/**
 * Renders a 14x14 lock badge (gray circle + white Lock icon).
 */
export function renderLockBadge(): HTMLCanvasElement {
  if (lockBadgeCanvas) return lockBadgeCanvas;

  const size = 14;
  const canvas = document.createElement("canvas");
  canvas.width = size;
  canvas.height = size;
  const ctx = canvas.getContext("2d")!;

  ctx.beginPath();
  ctx.arc(size / 2, size / 2, size / 2, 0, Math.PI * 2);
  ctx.fillStyle = "#64748b";
  ctx.fill();

  const img = renderIconToImage(Lock, 8, "#ffffff", 3);
  ctx.drawImage(img, 3, 3, 8, 8);

  lockBadgeCanvas = canvas;
  return canvas;
}
