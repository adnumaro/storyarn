/**
 * Map export utilities — PNG (raster) and SVG (vector).
 *
 * PNG uses modern-screenshot to capture the Leaflet container.
 * SVG iterates visible Leaflet layers and serializes geometries.
 */

import { domToPng } from "modern-screenshot";
import { sanitizeColor } from "./color_utils.js";

/** Maps pin size keys to pixel values. */
const PIN_SIZE_MAP = { sm: 16, md: 24, lg: 32 };

// ---------------------------------------------------------------------------
// PNG Export
// ---------------------------------------------------------------------------

/**
 * Captures the Leaflet map container as a PNG and triggers a download.
 * @param {Object} hook - The SceneCanvas hook instance
 * @param {string} filename - Base filename (without extension)
 */
export async function exportPNG(hook, filename = "map") {
  const container = hook.el.querySelector("#scene-canvas-container");
  if (!container) return;

  // Temporarily hide controls/UI that shouldn't appear in export
  const controlElements = container.querySelectorAll(".leaflet-control-container");
  controlElements.forEach((el) => {
    el.style.display = "none";
  });

  try {
    const dataUrl = await domToPng(container, {
      scale: 2, // Retina-quality
      backgroundColor: null,
    });

    const res = await fetch(dataUrl);
    const blob = await res.blob();
    downloadBlob(blob, `${filename}.png`);
  } finally {
    // Restore hidden controls
    controlElements.forEach((el) => {
      el.style.display = "";
    });
  }
}

// ---------------------------------------------------------------------------
// SVG Export
// ---------------------------------------------------------------------------

/**
 * Builds an SVG document from visible map elements and triggers a download.
 * Respects layer visibility — hidden layers are excluded.
 * @param {Object} hook - The SceneCanvas hook instance
 * @param {string} filename - Base filename (without extension)
 */
export function exportSVG(hook, filename = "map") {
  const width = hook.canvasWidth || 1000;
  const height = hook.canvasHeight || 1000;

  const elements = [];

  // Background rectangle
  elements.push(`<rect width="${width}" height="${height}" fill="#f9fafb" />`);

  // Zones (polygons) — from zone_handler.polygons Map
  if (hook.zoneHandler?.polygons) {
    for (const [, polygon] of hook.zoneHandler.polygons) {
      const zone = polygon.zoneData;
      if (!zone) continue;
      if (isLayerHidden(hook, zone.layer_id)) continue;

      const points = (zone.vertices || [])
        .map((v) => `${(v.x / 100) * width},${(v.y / 100) * height}`)
        .join(" ");

      if (points) {
        const fill = sanitizeColor(zone.fill_color || "#3b82f6");
        const stroke = sanitizeColor(zone.border_color || "#1e40af");
        const strokeWidth = zone.border_width || 2;
        const opacity = zone.opacity || 0.3;
        const dashArray =
          zone.border_style === "dashed"
            ? ` stroke-dasharray="8 4"`
            : zone.border_style === "dotted"
              ? ` stroke-dasharray="2 4"`
              : "";

        elements.push(
          `<polygon points="${points}" fill="${fill}" fill-opacity="${opacity}" stroke="${stroke}" stroke-width="${strokeWidth}"${dashArray} />`,
        );
      }
    }
  }

  // Connections (polylines) — from connection_handler.lines Map
  if (hook.connectionHandler?.lines) {
    for (const [, line] of hook.connectionHandler.lines) {
      const conn = line.connData;
      if (!conn) continue;

      // Hide if either endpoint pin is on a hidden layer
      if (isPinOnHiddenLayer(hook, conn.from_pin_id)) continue;
      if (isPinOnHiddenLayer(hook, conn.to_pin_id)) continue;

      const latlngs = line.getLatLngs();
      const points = latlngs.map((ll) => `${ll.lng},${-ll.lat}`).join(" ");

      if (points) {
        const color = sanitizeColor(conn.color || "#6b7280");
        const dashArray =
          conn.line_style === "dashed"
            ? ` stroke-dasharray="8 4"`
            : conn.line_style === "dotted"
              ? ` stroke-dasharray="2 4"`
              : "";

        elements.push(
          `<polyline points="${points}" fill="none" stroke="${color}" stroke-width="2"${dashArray} />`,
        );

        // Label at midpoint
        if (conn.label && latlngs.length >= 2) {
          const mid = latlngs[Math.floor(latlngs.length / 2)];
          elements.push(
            `<text x="${mid.lng}" y="${-mid.lat}" text-anchor="middle" font-size="12" fill="${color}">${escapeXml(conn.label)}</text>`,
          );
        }
      }
    }
  }

  // Pins (circles + labels) — from pin_handler.markers Map
  if (hook.pinHandler?.markers) {
    for (const [, marker] of hook.pinHandler.markers) {
      const pin = marker.pinData;
      if (!pin) continue;
      if (isLayerHidden(hook, pin.layer_id)) continue;

      const cx = (pin.position_x / 100) * width;
      const cy = (pin.position_y / 100) * height;
      const color = sanitizeColor(pin.color || "#ef4444");
      const r = (PIN_SIZE_MAP[pin.size] || 24) / 2;

      elements.push(
        `<circle cx="${cx}" cy="${cy}" r="${r}" fill="${color}" stroke="white" stroke-width="2" />`,
      );

      if (pin.label) {
        elements.push(
          `<text x="${cx}" y="${cy + r + 12}" text-anchor="middle" font-size="11" font-weight="600" fill="#374151">${escapeXml(pin.label)}</text>`,
        );
      }
    }
  }

  // Annotations (text) — from annotation_handler.markers Map
  if (hook.annotationHandler?.markers) {
    for (const [, marker] of hook.annotationHandler.markers) {
      const data = marker.annotationData;
      if (!data) continue;
      if (isLayerHidden(hook, data.layer_id)) continue;

      const x = (data.position_x / 100) * width;
      const y = (data.position_y / 100) * height;
      const color = sanitizeColor(data.color || "#374151");
      const fontSize = fontSizeToPixels(data.font_size);

      elements.push(
        `<text x="${x}" y="${y}" font-size="${fontSize}" fill="${color}">${escapeXml(data.text || "")}</text>`,
      );
    }
  }

  const svg = [
    `<?xml version="1.0" encoding="UTF-8"?>`,
    `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 ${width} ${height}" width="${width}" height="${height}">`,
    ...elements.map((e) => `  ${e}`),
    `</svg>`,
  ].join("\n");

  const blob = new Blob([svg], { type: "image/svg+xml;charset=utf-8" });
  downloadBlob(blob, `${filename}.svg`);
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/** Checks if a layer is hidden via the layer handler. */
function isLayerHidden(hook, layerId) {
  if (!layerId) return false; // null layer_id = always visible
  if (!hook.layerHandler || !hook.layerHandler.isLayerHidden) return false;
  return hook.layerHandler.isLayerHidden(layerId);
}

/** Checks if a pin is on a hidden layer. */
function isPinOnHiddenLayer(hook, pinId) {
  if (!hook.pinHandler || !hook.pinHandler.markers) return false;
  const marker = hook.pinHandler.markers.get(pinId);
  if (!marker || !marker.pinData) return false;
  return isLayerHidden(hook, marker.pinData.layer_id);
}

function downloadBlob(blob, filename) {
  const url = URL.createObjectURL(blob);
  const a = document.createElement("a");
  a.href = url;
  a.download = filename;
  document.body.appendChild(a);
  a.click();
  document.body.removeChild(a);
  URL.revokeObjectURL(url);
}

function escapeXml(str) {
  return (
    str
      // Strip characters invalid in XML 1.0
      // biome-ignore lint/suspicious/noControlCharactersInRegex: intentional stripping of XML 1.0 invalid control characters
      .replace(/[\x00-\x08\x0B\x0C\x0E-\x1F]/g, "")
      .replace(/&/g, "&amp;")
      .replace(/</g, "&lt;")
      .replace(/>/g, "&gt;")
      .replace(/"/g, "&quot;")
      .replace(/'/g, "&#39;")
  );
}

function fontSizeToPixels(size) {
  switch (size) {
    case "xs":
      return 10;
    case "sm":
      return 12;
    case "md":
      return 14;
    case "lg":
      return 18;
    case "xl":
      return 24;
    default:
      return 14;
  }
}
