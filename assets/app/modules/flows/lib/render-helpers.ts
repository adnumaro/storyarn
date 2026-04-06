/**
 * Shared rendering utilities for flow node Vue components.
 * Port of assets/js/flow_canvas/nodes/render_helpers.js to Vue-compatible functions.
 */

import type { NodeData } from "./node-configs";
import type { SheetMapEntry } from "../types";

/**
 * Re-export as SheetInfo for backward compatibility.
 * Canonical definition is SheetMapEntry in types.ts.
 */
export type SheetInfo = SheetMapEntry;

export interface HubInfo {
  color_hex?: string | null;
  label?: string;
  jumpCount?: number;
}

export interface ConditionRule {
  variable_ref?: string;
  operator: string;
  value_type?: string;
  value_ref?: string;
  value?: string | number | boolean | null;
}

export interface InstructionAssignment {
  variable_ref?: string;
  operator?: string;
  value_type?: string;
  value_ref?: string;
  value?: string | number | boolean | null;
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
export function resolveNodeColor(
  nodeType: string,
  nodeData: NodeData | null,
  configColor: string,
  sheetsMap: Record<string, SheetMapEntry> | null,
  hubsMap: Record<string, HubInfo> | null,
): string {
  const d = nodeData || {};

  if (nodeType === "dialogue" && d.speaker_sheet_id) {
    const sheet = sheetsMap?.[String(d.speaker_sheet_id)];
    if (sheet?.color) {
      return sheet.color;
    }
  }

  if (nodeType === "slug_line" && d.location_sheet_id) {
    const sheet = sheetsMap?.[String(d.location_sheet_id)];
    if (sheet?.color) {
      return sheet.color;
    }
  }

  if ((nodeType === "hub" || nodeType === "exit") && d.color_hex) {
    return d.color_hex as string;
  }

  if (nodeType === "exit" && d.outcome_color) {
    return d.outcome_color as string;
  }

  if (nodeType === "jump" && d.target_hub_id && hubsMap) {
    const hub = hubsMap[d.target_hub_id as string];
    if (hub?.color_hex) {
      return hub.color_hex;
    }
  }

  if (nodeType === "annotation") {
    return (d.color as string) || "#fbbf24";
  }

  return configColor;
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

/**
 * Format condition operator to symbol.
 */
const OPERATOR_SYMBOLS: Record<string, string> = {
  equals: "=",
  not_equals: "\u2260",
  greater_than: ">",
  less_than: "<",
  greater_than_or_equal: "\u2265",
  less_than_or_equal: "\u2264",
  contains: "\u220B",
  not_contains: "\u220C",
  starts_with: "\u22A2",
  ends_with: "\u22A3",
  is_empty: "is empty",
  is_not_empty: "is not empty",
  is_true: "is true",
  is_false: "is false",
};

export function getOperatorSymbol(op: string): string {
  return OPERATOR_SYMBOLS[op] || op;
}

/**
 * Format a condition rule to readable string.
 */
export function formatRule(rule: ConditionRule): string {
  const ref = rule.variable_ref || "?";
  const parts = ref.split(".");
  const sheet = parts.length > 1 ? parts[0] : "";
  const variable = parts.length > 1 ? parts.slice(1).join(".") : ref;
  const symbol = getOperatorSymbol(rule.operator);
  const noValueOps = ["is_empty", "is_not_empty", "is_true", "is_false"];

  if (noValueOps.includes(rule.operator)) {
    return sheet ? `${sheet}.${variable} ${symbol}` : `${variable} ${symbol}`;
  }

  const val =
    rule.value_type === "variable" && rule.value_ref ? rule.value_ref : (rule.value ?? "");

  return sheet ? `${sheet}.${variable} ${symbol} ${val}` : `${variable} ${symbol} ${val}`;
}

/**
 * Format a condition rule to short string (variable + symbol + truncated value).
 */
export function formatRuleShort(rule: ConditionRule): string {
  const ref = rule.variable_ref || "?";
  const parts = ref.split(".");
  const variable = parts.length > 1 ? parts.slice(1).join(".") : ref;
  const symbol = getOperatorSymbol(rule.operator);
  const noValueOps = ["is_empty", "is_not_empty", "is_true", "is_false"];

  if (noValueOps.includes(rule.operator)) {
    return `${variable} ${symbol}`;
  }

  let val =
    rule.value_type === "variable" && rule.value_ref ? rule.value_ref : String(rule.value ?? "");
  if (val.length > 10) {
    val = `${val.slice(0, 10)}\u2026`;
  }

  return `${variable} ${symbol} ${val}`;
}

/**
 * Format an instruction assignment to readable string.
 */
export function formatAssignment(assignment: InstructionAssignment): string {
  const ref = assignment.variable_ref || "?";
  const op = assignment.operator || "set";

  if (op === "toggle") {
    return `Toggle ${ref}`;
  }
  if (op === "clear") {
    return `Clear ${ref}`;
  }

  let val: string;
  if (assignment.value_type === "variable" && assignment.value_ref) {
    val = assignment.value_ref;
  } else if (typeof assignment.value === "boolean") {
    val = assignment.value ? "true" : "false";
  } else {
    val = String(assignment.value ?? "");
  }

  const opLabels: Record<string, string> = {
    set: "Set",
    add: "Add",
    subtract: "Subtract",
    multiply: "Multiply",
    divide: "Divide",
    append: "Append",
    prepend: "Prepend",
  };

  const label = opLabels[op] || "Set";

  if (op === "set") {
    return `${label} ${ref} to ${val}`;
  }
  if (["add", "subtract"].includes(op)) {
    return `${label} ${val} to ${ref}`;
  }
  return `${label} ${ref} by ${val}`;
}
