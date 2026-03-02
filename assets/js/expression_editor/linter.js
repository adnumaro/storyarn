/**
 * CodeMirror linter extension for Storyarn expression editor.
 *
 * Validates expression text using the parser and reports:
 * - Syntax errors from the Lezer parse tree (severity: error)
 * - Undefined variable references (severity: warning)
 */
import { linter } from "@codemirror/lint";
import { OPERATOR_SYMBOLS, operatorsForType } from "../instruction_builder/sentence_templates.js";
import { parseAssignments, parseCondition } from "./parser.js";

/**
 * Creates a linter extension for the expression editor.
 * @param {"assignments"|"expression"} mode
 * @param {Array<{sheet_shortcut: string, variable_name: string}>} variables
 * @returns {import("@codemirror/state").Extension}
 */
export function expressionLinter(mode, variables, translations = {}) {
  const source = createLintSource(mode, variables, translations);
  return linter(source, { delay: 500 });
}

/**
 * Creates a lint source function for testing and reuse.
 * @param {"assignments"|"expression"} mode
 * @param {Array} variables
 * @param {Object} translations
 * @returns {Function}
 */
export function createLintSource(mode, variables, translations = {}) {
  const t = translations;
  const variableSet = new Set(variables.map((v) => `${v.sheet_shortcut}.${v.variable_name}`));
  const variableTypeMap = new Map(
    variables.map((v) => [`${v.sheet_shortcut}.${v.variable_name}`, v.block_type]),
  );

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
        message: t.syntax_error || err.message,
      });
    }

    // Undefined variable warnings
    if (mode === "assignments" && result.assignments) {
      for (const a of result.assignments) {
        checkVariableRef(diagnostics, variableSet, a.sheet, a.variable, a.ref_from, a.ref_to, t);
        if (a.value_type === "variable_ref" && a.value_sheet) {
          checkVariableRef(
            diagnostics,
            variableSet,
            a.value_sheet,
            a.value,
            a.value_ref_from,
            a.value_ref_to,
            t,
          );
        }
        // Warn if operator is incompatible with the variable's type
        if (a.sheet && a.variable && a.operator && a.ref_from !== undefined) {
          const blockType = variableTypeMap.get(`${a.sheet}.${a.variable}`);
          if (blockType) {
            const validOps = operatorsForType(blockType);
            if (!validOps.includes(a.operator)) {
              const invalidFor = t.invalid_operator_for_type || "is not a valid operator for";
              const validLabel = t.valid_operators || "valid";
              const opSymbol = OPERATOR_SYMBOLS[a.operator] || a.operator;
              const validSymbols = validOps.map((op) => OPERATOR_SYMBOLS[op] || op).join(", ");
              diagnostics.push({
                from: a.ref_from,
                to: a.ref_to,
                severity: "warning",
                message: `"${opSymbol}" ${invalidFor} ${blockType} (${validLabel}: ${validSymbols})`,
              });
            }
          }
        }
      }
    }

    if (mode === "expression" && result.condition?.rules) {
      for (const r of result.condition.rules) {
        checkVariableRef(diagnostics, variableSet, r.sheet, r.variable, r.ref_from, r.ref_to, t);
      }
    }

    return diagnostics;
  };
}

function checkVariableRef(diagnostics, variableSet, sheet, variable, from, to, t = {}) {
  if (!sheet || !variable || from === undefined || to === undefined) return;
  const fullRef = `${sheet}.${variable}`;
  if (!variableSet.has(fullRef)) {
    diagnostics.push({
      from,
      to,
      severity: "warning",
      message: `${t.unknown_variable || "Unknown variable"}: ${fullRef}`,
    });
  }
}
