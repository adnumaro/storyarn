/**
 * CodeMirror autocomplete extension for Storyarn variables.
 *
 * Suggests sheet shortcuts and variable names from the project's variable list.
 * When the user types a partial sheet shortcut, suggests matching sheets.
 * After typing "sheet.", suggests variables from that sheet.
 */
import { autocompletion } from "@codemirror/autocomplete";

/**
 * Creates an autocomplete extension for Storyarn variables.
 * @param {Array<{sheet_shortcut: string, variable_name: string, block_type: string}>} variables
 * @returns {import("@codemirror/state").Extension}
 */
export function variableAutocomplete(variables) {
  const source = createVariableCompletionSource(variables);
  return autocompletion({ override: [source] });
}

/**
 * Creates a completion source function for testing and reuse.
 * @param {Array} variables
 * @returns {Function} CompletionContext => CompletionResult | null
 */
export function createVariableCompletionSource(variables) {
  const { sheets, bySheet } = groupBySheet(variables);
  return (context) => completeVariable(context, sheets, bySheet);
}

function groupBySheet(variables) {
  const bySheet = new Map();
  const sheetSet = new Set();

  for (const v of variables) {
    sheetSet.add(v.sheet_shortcut);
    if (!bySheet.has(v.sheet_shortcut)) {
      bySheet.set(v.sheet_shortcut, []);
    }
    bySheet.get(v.sheet_shortcut).push(v);
  }

  const sheets = Array.from(sheetSet).sort();
  return { sheets, bySheet };
}

function completeVariable(context, sheets, bySheet) {
  // Match identifiers with dots (variable references)
  const word = context.matchBefore(/[a-zA-Z_][a-zA-Z0-9_.]*/);
  if (!word && !context.explicit) return null;

  const text = word ? word.text : "";
  const from = word ? word.from : context.pos;

  // Find the longest sheet that the text starts with (requires dot after sheet)
  let matchedSheet = null;
  for (const sheet of sheets) {
    if (text.startsWith(`${sheet}.`)) {
      if (!matchedSheet || sheet.length > matchedSheet.length) {
        matchedSheet = sheet;
      }
    }
  }

  if (matchedSheet) {
    return completeAfterSheet(text, from, matchedSheet, bySheet);
  }

  // No sheet matched — check for partial sheet matches (e.g., "mc.jai")
  const lastDotIdx = text.lastIndexOf(".");
  if (lastDotIdx > 0) {
    const prefix = text.slice(0, lastDotIdx);
    const partialSheetMatches = sheets.filter((s) => s.startsWith(`${prefix}.`) || s === prefix);
    if (partialSheetMatches.length > 0) {
      const options = [];
      for (const sheet of partialSheetMatches) {
        if (sheet === prefix) continue;
        options.push({
          label: sheet,
          apply: `${sheet}.`,
          type: "namespace",
          boost: 1,
        });
      }
      return options.length > 0 ? { from, options } : null;
    }
  }

  // No dot or no partial match — suggest sheet shortcuts
  const lowerText = text.toLowerCase();
  const options = sheets
    .filter((s) => s.toLowerCase().startsWith(lowerText))
    .map((s) => ({
      label: s,
      apply: `${s}.`,
      type: "namespace",
    }));

  return options.length > 0 ? { from, options } : null;
}

/**
 * Completes after a known sheet prefix, handling regular vars and table paths.
 * Levels: sheet. → vars + tables | sheet.table. → rows | sheet.table.row. → columns
 */
function completeAfterSheet(text, from, matchedSheet, bySheet) {
  const sheetVars = bySheet.get(matchedSheet) || [];
  const endsWithDot = text.endsWith(".");

  // Extract text after "sheet." and split into parts
  const afterSheet = text.slice(matchedSheet.length + 1); // skip "sheet."
  // Strip trailing dot for clean splitting
  const cleanAfter = endsWithDot && afterSheet.endsWith(".") ? afterSheet.slice(0, -1) : afterSheet;
  const parts = cleanAfter ? cleanAfter.split(".") : [];

  const regularVars = sheetVars.filter((v) => !v.table_name);
  const tableNames = [...new Set(sheetVars.filter((v) => v.table_name).map((v) => v.table_name))];
  const baseFrom = from + matchedSheet.length + 1;

  // Level 1: after "sheet." or "sheet.prefix" — show regular vars + table names
  if (parts.length === 0 || (parts.length === 1 && !endsWithDot)) {
    const prefix = parts.length === 1 ? parts[0].toLowerCase() : "";
    const options = [];

    for (const v of regularVars) {
      if (v.variable_name.toLowerCase().startsWith(prefix)) {
        options.push({
          label: v.variable_name,
          detail: `(${v.block_type})`,
          type: "variable",
        });
      }
    }

    for (const t of tableNames) {
      if (t.toLowerCase().startsWith(prefix)) {
        options.push({
          label: t,
          apply: `${t}.`,
          detail: "table \u2192",
          type: "namespace",
          boost: -1,
        });
      }
    }

    return options.length > 0 ? { from: baseFrom, options } : null;
  }

  // Check if parts[0] is a known table name
  const tableName = parts[0];
  const tableVars = sheetVars.filter((v) => v.table_name === tableName);

  if (tableVars.length > 0) {
    const tableFrom = baseFrom + tableName.length + 1;

    // Level 2: after "sheet.table." or "sheet.table.prefix" — show row names
    if (parts.length === 1 && endsWithDot) {
      const rowNames = [...new Set(tableVars.map((v) => v.row_name))];
      return {
        from: tableFrom,
        options: rowNames.map((r) => ({
          label: r,
          apply: `${r}.`,
          type: "namespace",
        })),
      };
    }

    if (parts.length === 2 && !endsWithDot) {
      const rowPrefix = parts[1].toLowerCase();
      const rowNames = [...new Set(tableVars.map((v) => v.row_name))];
      const options = rowNames
        .filter((r) => r.toLowerCase().startsWith(rowPrefix))
        .map((r) => ({
          label: r,
          apply: `${r}.`,
          type: "namespace",
        }));
      return options.length > 0 ? { from: tableFrom, options } : null;
    }

    const rowName = parts[1];
    const rowVars = tableVars.filter((v) => v.row_name === rowName);

    if (rowVars.length > 0) {
      const rowFrom = tableFrom + rowName.length + 1;

      // Level 3: after "sheet.table.row." or "sheet.table.row.prefix" — show columns
      if (parts.length === 2 && endsWithDot) {
        return {
          from: rowFrom,
          options: rowVars.map((v) => ({
            label: v.column_name,
            detail: `(${v.block_type})`,
            type: "variable",
          })),
        };
      }

      if (parts.length === 3) {
        const colPrefix = parts[2].toLowerCase();
        const options = rowVars
          .filter((v) => v.column_name.toLowerCase().startsWith(colPrefix))
          .map((v) => ({
            label: v.column_name,
            detail: `(${v.block_type})`,
            type: "variable",
          }));
        return options.length > 0 ? { from: rowFrom, options } : null;
      }
    }
  }

  // Fallback: filter regular variables by what's after the sheet dot
  const varPrefix = afterSheet.toLowerCase();
  const options = regularVars
    .filter((v) => v.variable_name.toLowerCase().startsWith(varPrefix))
    .map((v) => ({
      label: v.variable_name,
      detail: `(${v.block_type})`,
      type: "variable",
    }));
  return options.length > 0 ? { from: baseFrom, options } : null;
}
