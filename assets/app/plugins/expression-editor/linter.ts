/**
 * CodeMirror linter extension for Storyarn expression editor.
 *
 * Validates expression text using the parser and reports:
 * - Syntax errors from the Lezer parse tree (severity: error)
 * - Undefined variable references (severity: warning)
 * - Operator type-mismatch warnings (severity: warning)
 */

import { linter, type Diagnostic } from "@codemirror/lint";
import type { EditorView } from "@codemirror/view";
import type { Extension } from "@codemirror/state";
import {
  operatorsForType as instructionOpsForType,
  OPERATOR_VERBS,
} from "@modules/shared/operators/instruction-operators";
import { parseAssignments, parseCondition } from "./tree-parser";
import type { Variable } from "@modules/shared/variables";

export function expressionLinter(
  mode: "condition" | "instruction",
  variables: Variable[],
): Extension {
  const source = createLintSource(mode, variables);
  return linter(source, { delay: 500 });
}

export function createLintSource(
  mode: "condition" | "instruction",
  variables: Variable[],
): (view: EditorView) => Diagnostic[] {
  const variableSet = new Set(variables.map((v) => `${v.sheet_shortcut}.${v.variable_name}`));
  const variableTypeMap = new Map(
    variables.map((v) => [`${v.sheet_shortcut}.${v.variable_name}`, v.block_type]),
  );

  return (view) => {
    const text = view.state.doc.toString();
    if (!text.trim()) return [];

    const diagnostics: Diagnostic[] = [];
    const parserMode = mode === "condition" ? "expression" : "assignments";

    if (parserMode === "assignments") {
      const result = parseAssignments(text, variables);

      for (const err of result.errors) {
        diagnostics.push({ from: err.from, to: err.to, severity: "error", message: err.message });
      }

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
        checkOperatorType(
          diagnostics,
          variableTypeMap,
          a.sheet,
          a.variable,
          a.operator,
          a.ref_from,
          a.ref_to,
        );
      }
    } else {
      const result = parseCondition(text, variables);

      for (const err of result.errors) {
        diagnostics.push({ from: err.from, to: err.to, severity: "error", message: err.message });
      }

      for (const r of result.condition.rules) {
        checkVariableRef(diagnostics, variableSet, r.sheet, r.variable, r.ref_from, r.ref_to);
      }
    }

    return diagnostics;
  };
}

function checkVariableRef(
  diagnostics: Diagnostic[],
  variableSet: Set<string>,
  sheet: string | null,
  variable: string | null,
  from: number | undefined,
  to: number | undefined,
): void {
  if (!sheet || !variable || from === undefined || to === undefined) return;
  const fullRef = `${sheet}.${variable}`;
  if (!variableSet.has(fullRef)) {
    diagnostics.push({ from, to, severity: "warning", message: `Unknown variable: ${fullRef}` });
  }
}

function checkOperatorType(
  diagnostics: Diagnostic[],
  variableTypeMap: Map<string, string>,
  sheet: string | null,
  variable: string | null,
  operator: string,
  from: number | undefined,
  to: number | undefined,
): void {
  if (!sheet || !variable || !operator || from === undefined || to === undefined) return;
  const blockType = variableTypeMap.get(`${sheet}.${variable}`);
  if (!blockType) return;

  const validOps = instructionOpsForType(blockType);
  if (!validOps.includes(operator as never)) {
    const opLabel = OPERATOR_VERBS[operator as keyof typeof OPERATOR_VERBS] || operator;
    const validLabels = validOps.map((op) => OPERATOR_VERBS[op] || op).join(", ");
    diagnostics.push({
      from,
      to,
      severity: "warning",
      message: `"${opLabel}" is not valid for ${blockType} (valid: ${validLabels})`,
    });
  }
}
