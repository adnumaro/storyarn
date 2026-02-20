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

  // Check if we have a dot — suggesting variables within a sheet
  const lastDotIdx = text.lastIndexOf(".");
  if (lastDotIdx > 0) {
    const prefix = text.slice(0, lastDotIdx);

    // Try to find a sheet that matches the prefix
    const matchingSheet = sheets.find((s) => s === prefix);
    if (matchingSheet) {
      const vars = bySheet.get(matchingSheet) || [];
      const variablePrefix = text.slice(lastDotIdx + 1).toLowerCase();

      return {
        from: from + lastDotIdx + 1,
        options: vars
          .filter((v) => v.variable_name.toLowerCase().startsWith(variablePrefix))
          .map((v) => ({
            label: v.variable_name,
            detail: `(${v.block_type})`,
            type: "variable",
          })),
      };
    }

    // Prefix might be a partial sheet with a partial variable
    // e.g., "mc.jai" when sheet is "mc.jaime"
    // Look for sheets that start with prefix + "."
    const partialSheetMatches = sheets.filter((s) => s.startsWith(`${prefix}.`) || s === prefix);
    if (partialSheetMatches.length > 0) {
      // Still in sheet territory — suggest longer sheet segments
      const options = [];
      for (const sheet of partialSheetMatches) {
        if (sheet === prefix) continue; // Already handled above
        options.push({
          label: sheet,
          apply: `${sheet}.`,
          type: "namespace",
          boost: 1,
        });
      }
      // Also suggest variables if the prefix matches a sheet
      return options.length > 0 ? { from, options } : null;
    }
  }

  // No dot — suggest sheet shortcuts
  const lowerText = text.toLowerCase();
  const options = sheets
    .filter((s) => s.toLowerCase().startsWith(lowerText))
    .map((s) => ({
      label: s,
      apply: `${s}.`,
      type: "namespace",
    }));

  if (options.length === 0) return null;

  return { from, options };
}
