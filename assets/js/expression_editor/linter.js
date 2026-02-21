/**
 * CodeMirror linter extension for Storyarn expression editor.
 *
 * Validates expression text using the parser and reports:
 * - Syntax errors from the Lezer parse tree (severity: error)
 * - Undefined variable references (severity: warning)
 */
import { linter } from "@codemirror/lint";
import { parseAssignments, parseCondition } from "./parser.js";

/**
 * Creates a linter extension for the expression editor.
 * @param {"assignments"|"expression"} mode
 * @param {Array<{sheet_shortcut: string, variable_name: string}>} variables
 * @returns {import("@codemirror/state").Extension}
 */
export function expressionLinter(mode, variables) {
  const source = createLintSource(mode, variables);
  return linter(source, { delay: 500 });
}

/**
 * Creates a lint source function for testing and reuse.
 * @param {"assignments"|"expression"} mode
 * @param {Array} variables
 * @returns {Function}
 */
export function createLintSource(mode, variables) {
  const variableSet = new Set(variables.map((v) => `${v.sheet_shortcut}.${v.variable_name}`));

  return (view) => {
    const text = view.state.doc.toString();
    if (!text.trim()) return [];

    const diagnostics = [];
    const result =
      mode === "assignments" ? parseAssignments(text, variables) : parseCondition(text, variables);

    // Syntax errors from parser
    for (const err of result.errors) {
      diagnostics.push({
        from: err.from,
        to: err.to,
        severity: "error",
        message: err.message,
      });
    }

    // Undefined variable warnings
    if (mode === "assignments" && result.assignments) {
      for (const a of result.assignments) {
        checkVariableRef(diagnostics, variableSet, a.sheet, a.variable, a.ref_from, a.ref_to);
        if (a.value_type === "variable_ref" && a.value_sheet) {
          checkVariableRef(
            diagnostics,
            variableSet,
            a.value_sheet,
            a.value,
            a.value_ref_from,
            a.value_ref_to,
          );
        }
      }
    }

    if (mode === "expression" && result.condition?.rules) {
      for (const r of result.condition.rules) {
        checkVariableRef(diagnostics, variableSet, r.sheet, r.variable, r.ref_from, r.ref_to);
      }
    }

    return diagnostics;
  };
}

function checkVariableRef(diagnostics, variableSet, sheet, variable, from, to) {
  if (!sheet || !variable || from === undefined || to === undefined) return;
  const fullRef = `${sheet}.${variable}`;
  if (!variableSet.has(fullRef)) {
    diagnostics.push({
      from,
      to,
      severity: "warning",
      message: `Unknown variable: ${fullRef}`,
    });
  }
}
