/**
 * Shared utilities for screenplay builders (condition, instruction, response).
 */

import { MapPin, Pentagon } from "lucide";
import { createIconHTML } from "../../flow_canvas/node_config.js";

const PIN_ICON = createIconHTML(MapPin, { size: 12 });
const ZONE_ICON = createIconHTML(Pentagon, { size: 12 });

/**
 * Returns icon HTML for a source type, or null for sheets.
 */
export function sourceTypeIconHtml(sourceType) {
  if (sourceType === "pin") return PIN_ICON;
  if (sourceType === "zone") return ZONE_ICON;
  return null;
}

/**
 * Groups a flat variable list into sheets with their variables.
 *
 * @param {Array} variables - Flat list of { sheet_shortcut, sheet_name, variable_name, block_type, options }
 * @returns {Array} Sorted array of { shortcut, name, vars: [{ variable_name, block_type, options }] }
 */
export function groupVariablesBySheet(variables) {
  const sheetMap = new Map();

  for (const v of variables) {
    const key = v.sheet_shortcut;
    if (!sheetMap.has(key)) {
      sheetMap.set(key, {
        shortcut: v.sheet_shortcut,
        name: v.sheet_name || v.sheet_shortcut,
        source_type: v.source_type || "sheet",
        vars: [],
      });
    }
    sheetMap.get(key).vars.push({
      variable_name: v.variable_name,
      block_type: v.block_type,
      options: v.options,
      table_name: v.table_name || null,
    });
  }

  return Array.from(sheetMap.values()).sort((a, b) => a.name.localeCompare(b.name));
}
