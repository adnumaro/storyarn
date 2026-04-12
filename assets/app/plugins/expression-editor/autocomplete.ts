/**
 * CodeMirror autocomplete extension for Storyarn variables.
 *
 * Suggests sheet shortcuts and variable names from the project's variable list.
 * After typing "sheet.", suggests variables from that sheet.
 * Supports 3-level table paths: sheet.table.row.column
 */

import { autocompletion, type CompletionContext, type CompletionResult } from "@codemirror/autocomplete";
import type { Extension } from "@codemirror/state";
import type { Variable } from "@modules/shared/variables";

export function variableAutocomplete(variables: Variable[]): Extension {
  const source = createVariableCompletionSource(variables);
  return autocompletion({ override: [source] });
}

export function createVariableCompletionSource(
  variables: Variable[],
): (context: CompletionContext) => CompletionResult | null {
  const { sheets, bySheet } = groupBySheet(variables);
  return (context) => completeVariable(context, sheets, bySheet);
}

function groupBySheet(variables: Variable[]): {
  sheets: string[];
  bySheet: Map<string, Variable[]>;
} {
  const bySheet = new Map<string, Variable[]>();
  const sheetSet = new Set<string>();

  for (const v of variables) {
    sheetSet.add(v.sheet_shortcut);
    if (!bySheet.has(v.sheet_shortcut)) {
      bySheet.set(v.sheet_shortcut, []);
    }
    bySheet.get(v.sheet_shortcut)!.push(v);
  }

  return { sheets: Array.from(sheetSet).sort(), bySheet };
}

function findLongestMatchingSheet(text: string, sheets: string[]): string | null {
  let matched: string | null = null;
  for (const sheet of sheets) {
    if (text.startsWith(`${sheet}.`)) {
      if (!matched || sheet.length > matched.length) {
        matched = sheet;
      }
    }
  }
  return matched;
}

function completePartialSheet(text: string, from: number, sheets: string[]): CompletionResult | null {
  const lastDotIdx = text.lastIndexOf(".");
  if (lastDotIdx <= 0) return null;

  const prefix = text.slice(0, lastDotIdx);
  const partialMatches = sheets.filter((s) => s.startsWith(`${prefix}.`) || s === prefix);
  if (partialMatches.length === 0) return null;

  const options = partialMatches
    .filter((sheet) => sheet !== prefix)
    .map((sheet) => ({ label: sheet, apply: `${sheet}.`, type: "namespace" as const, boost: 1 }));
  return options.length > 0 ? { from, options } : null;
}

function completeSheetShortcuts(text: string, from: number, sheets: string[]): CompletionResult | null {
  const lowerText = text.toLowerCase();
  const options = sheets
    .filter((s) => s.toLowerCase().startsWith(lowerText))
    .map((s) => ({ label: s, apply: `${s}.`, type: "namespace" as const }));
  return options.length > 0 ? { from, options } : null;
}

function completeVariable(
  context: CompletionContext,
  sheets: string[],
  bySheet: Map<string, Variable[]>,
): CompletionResult | null {
  const word = context.matchBefore(/[a-zA-Z_][a-zA-Z0-9_\-.]*/);
  if (!word && !context.explicit) return null;

  const text = word ? word.text : "";
  const from = word ? word.from : context.pos;

  const matchedSheet = findLongestMatchingSheet(text, sheets);
  if (matchedSheet) return completeAfterSheet(text, from, matchedSheet, bySheet);

  return completePartialSheet(text, from, sheets) || completeSheetShortcuts(text, from, sheets);
}

/** Level 1: after "sheet." — show regular vars + table names */
function completeVarsAndTables(
  baseFrom: number,
  prefix: string,
  regularVars: Variable[],
  tableNames: string[],
): CompletionResult | null {
  const options = [
    ...regularVars
      .filter((v) => v.variable_name.toLowerCase().startsWith(prefix))
      .map((v) => ({ label: v.variable_name, detail: `(${v.block_type})`, type: "variable" as const })),
    ...tableNames
      .filter((t) => t.toLowerCase().startsWith(prefix))
      .map((t) => ({ label: t, apply: `${t}.`, detail: "table \u2192", type: "namespace" as const, boost: -1 })),
  ];
  return options.length > 0 ? { from: baseFrom, options } : null;
}

/** Level 2: after "sheet.table." — show row names */
function completeTableRows(
  tableFrom: number,
  tableVars: Variable[],
  rowPrefix: string,
): CompletionResult | null {
  const rowNames = [...new Set(tableVars.map((v) => v.row_name!))];
  if (!rowPrefix) {
    return { from: tableFrom, options: rowNames.map((r) => ({ label: r, apply: `${r}.`, type: "namespace" as const })) };
  }
  const options = rowNames
    .filter((r) => r.toLowerCase().startsWith(rowPrefix))
    .map((r) => ({ label: r, apply: `${r}.`, type: "namespace" as const }));
  return options.length > 0 ? { from: tableFrom, options } : null;
}

/** Level 3: after "sheet.table.row." — show column names */
function completeTableColumns(
  rowFrom: number,
  rowVars: Variable[],
  colPrefix: string,
): CompletionResult | null {
  if (!colPrefix) {
    return { from: rowFrom, options: rowVars.map((v) => ({ label: v.column_name!, detail: `(${v.block_type})`, type: "variable" as const })) };
  }
  const options = rowVars
    .filter((v) => v.column_name!.toLowerCase().startsWith(colPrefix))
    .map((v) => ({ label: v.column_name!, detail: `(${v.block_type})`, type: "variable" as const }));
  return options.length > 0 ? { from: rowFrom, options } : null;
}

function completeTablePath(
  parts: string[],
  endsWithDot: boolean,
  baseFrom: number,
  sheetVars: Variable[],
): CompletionResult | null {
  const tableName = parts[0];
  const tableVars = sheetVars.filter((v) => v.table_name === tableName);
  if (tableVars.length === 0) return null;

  const tableFrom = baseFrom + tableName.length + 1;

  if (parts.length === 1 && endsWithDot) return completeTableRows(tableFrom, tableVars, "");
  if (parts.length === 2 && !endsWithDot) return completeTableRows(tableFrom, tableVars, parts[1].toLowerCase());

  const rowName = parts[1];
  const rowVars = tableVars.filter((v) => v.row_name === rowName);
  if (rowVars.length === 0) return null;

  const rowFrom = tableFrom + rowName.length + 1;
  if (parts.length === 2 && endsWithDot) return completeTableColumns(rowFrom, rowVars, "");
  if (parts.length === 3) return completeTableColumns(rowFrom, rowVars, parts[2].toLowerCase());

  return null;
}

function parseAfterSheetParts(text: string, matchedSheet: string): { parts: string[]; afterSheet: string; endsWithDot: boolean } {
  const endsWithDot = text.endsWith(".");
  const afterSheet = text.slice(matchedSheet.length + 1);
  const cleanAfter = endsWithDot && afterSheet.endsWith(".") ? afterSheet.slice(0, -1) : afterSheet;
  const parts = cleanAfter ? cleanAfter.split(".") : [];
  return { parts, afterSheet, endsWithDot };
}

function completeFallbackVars(baseFrom: number, prefix: string, regularVars: Variable[]): CompletionResult | null {
  const options = regularVars
    .filter((v) => v.variable_name.toLowerCase().startsWith(prefix))
    .map((v) => ({ label: v.variable_name, detail: `(${v.block_type})`, type: "variable" as const }));
  return options.length > 0 ? { from: baseFrom, options } : null;
}

function completeAfterSheet(
  text: string,
  from: number,
  matchedSheet: string,
  bySheet: Map<string, Variable[]>,
): CompletionResult | null {
  const sheetVars = bySheet.get(matchedSheet) || [];
  const { parts, afterSheet, endsWithDot } = parseAfterSheetParts(text, matchedSheet);

  const regularVars = sheetVars.filter((v) => !v.table_name);
  const tableNames = [...new Set(sheetVars.filter((v) => v.table_name).map((v) => v.table_name!))];
  const baseFrom = from + matchedSheet.length + 1;

  if (parts.length === 0 || (parts.length === 1 && !endsWithDot)) {
    const prefix = parts.length === 1 ? parts[0].toLowerCase() : "";
    return completeVarsAndTables(baseFrom, prefix, regularVars, tableNames);
  }

  return completeTablePath(parts, endsWithDot, baseFrom, sheetVars)
    || completeFallbackVars(baseFrom, afterSheet.toLowerCase(), regularVars);
}
