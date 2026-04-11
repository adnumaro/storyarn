/**
 * Shared rendering utilities for flow node Vue components.
 * Port of assets/js/flow_canvas/nodes/render_helpers.js to Vue-compatible functions.
 */

import type { NodeData } from "./node-configs";
import type { SheetMapEntry } from "../types";

export interface HubInfo {
  color_hex?: string | null;
  label?: string;
  jumpCount?: number;
}

/**
 * CSS gradient for node headers -- solid left fading to lighter right.
 */
export function headerStyle(color: string): string {
  return `background: linear-gradient(to right, ${color} 40%, color-mix(in oklch, ${color} 85%, white) 100%)`;
}

/**
 * Resolve node color from type-specific data, falling back to config default.
 */

type ColorResolver = (
  d: NodeData,
  sheetsMap: Record<string, SheetMapEntry> | null,
  hubsMap: Record<string, HubInfo> | null,
) => string | null;

const NODE_COLOR_RESOLVERS: Record<string, ColorResolver> = {
  dialogue: (d, sheetsMap) => {
    if (!d.speaker_sheet_id) return null;
    return sheetsMap?.[String(d.speaker_sheet_id)]?.color ?? null;
  },
  slug_line: (d, sheetsMap) => {
    if (!d.location_sheet_id) return null;
    return sheetsMap?.[String(d.location_sheet_id)]?.color ?? null;
  },
  hub: (d) => (d.color_hex as string) || null,
  exit: (d) => (d.color_hex as string) || (d.outcome_color as string) || null,
  jump: (d, _sheetsMap, hubsMap) => {
    if (!d.target_hub_id || !hubsMap) return null;
    return hubsMap[d.target_hub_id as string]?.color_hex ?? null;
  },
  annotation: (d) => (d.color as string) || "#fbbf24",
};

export function resolveNodeColor(
  nodeType: string,
  nodeData: NodeData | null,
  configColor: string,
  sheetsMap: Record<string, SheetMapEntry> | null,
  hubsMap: Record<string, HubInfo> | null,
): string {
  const d = nodeData || {};
  const resolver = NODE_COLOR_RESOLVERS[nodeType];
  return resolver?.(d, sheetsMap, hubsMap) ?? configColor;
}

/**
 * Strip HTML tags and extract plain text for preview.
 */
export function stripHtml(html: string | null | undefined): string {
  if (!html) {
    return "";
  }
  return html
    .replace(/<br\s*\/?>/gi, "\n")
    .replace(/<\/p>\s*<p[^>]*>/gi, "\n")
    .replace(/<[^>]*>/g, "")
    .replace(/&amp;/g, "&")
    .replace(/&lt;/g, "<")
    .replace(/&gt;/g, ">")
    .replace(/&nbsp;/g, " ")
    .trim();
}

/**
 * Truncate text for node preview.
 */
export function previewText(text: string | null | undefined, maxLen: number = 120): string {
  const stripped = stripHtml(text);
  if (!stripped) {
    return "";
  }
  return stripped.length > maxLen ? `${stripped.slice(0, maxLen)}\u2026` : stripped;
}
