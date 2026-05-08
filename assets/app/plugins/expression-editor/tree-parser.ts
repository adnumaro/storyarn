/**
 * Storyarn Expression Parser
 *
 * Transforms Lezer parse trees into Storyarn structured data:
 * - Assignments mode: array of assignment objects (instruction node format)
 * - Expression mode: condition object with logic + rules (condition node format)
 *
 * Note: Lezer inlines lowercase grammar rules, so the tree is flat.
 * We work with direct children of top-level nodes.
 */

import type { SyntaxNode, Tree } from "@lezer/common";
import { i18n } from "@app/i18n";
import { parser as generatedParser } from "./parser-generated.js";
import type { Variable } from "../../shared/domain/variables";

// -- Types --

export interface ParsedRule {
  id: string;
  sheet: string;
  variable: string;
  operator: string;
  value: string | null;
  ref_from?: number;
  ref_to?: number;
  value_from?: number;
  value_to?: number;
}

export interface ParsedCondition {
  logic: "all" | "any";
  rules: ParsedRule[];
}

export interface ParsedAssignment {
  id: string;
  sheet: string;
  variable: string;
  operator: string;
  value: string | null;
  value_type: "literal" | "variable_ref";
  value_sheet: string | null;
  ref_from?: number;
  ref_to?: number;
  value_ref_from?: number;
  value_ref_to?: number;
}

export interface ParseError {
  from: number;
  to: number;
  message: string;
}

// -- Operator mappings --

const ASSIGN_OPS = new Set(["SetOp", "AddOp", "SubOp", "SetIfUnsetOp"]);

const ASSIGN_OP_MAP: Record<string, string> = {
  SetOp: "set",
  AddOp: "add",
  SubOp: "subtract",
  SetIfUnsetOp: "set_if_unset",
};

const COMPARE_OPS = new Set([
  "Eq",
  "Neq",
  "Gt",
  "Lt",
  "Gte",
  "Lte",
  "StartsWithOp",
  "EndsWithOp",
  "ContainsOp",
  "NotContainsOp",
]);

const COMPARE_OP_MAP: Record<string, string> = {
  Eq: "equals",
  Neq: "not_equals",
  Gt: "greater_than",
  Lt: "less_than",
  Gte: "greater_than_or_equal",
  Lte: "less_than_or_equal",
  StartsWithOp: "starts_with",
  EndsWithOp: "ends_with",
  ContainsOp: "contains",
  NotContainsOp: "not_contains",
};

const NEGATE_OP: Record<string, string> = {
  equals: "not_equals",
  not_equals: "equals",
  greater_than: "less_than_or_equal",
  less_than: "greater_than_or_equal",
  greater_than_or_equal: "less_than",
  less_than_or_equal: "greater_than",
  contains: "not_contains",
  not_contains: "contains",
};

const VALUE_TYPES = new Set(["VariableRef", "Number", "StringLiteral", "Boolean", "Null"]);

// -- ID generation --

let idCounter = 0;

function generateId(prefix: string): string {
  idCounter += 1;
  return `${prefix}_${Date.now()}_${idCounter}`;
}

// -- Helpers --

interface ChildInfo {
  name: string;
  from: number;
  to: number;
  node: SyntaxNode;
}

interface VarRef {
  sheet: string;
  variable: string;
  from: number;
  to: number;
}

interface KnownLookup {
  keys: Set<string>;
  sheets: Set<string>;
}

function getDirectChildren(node: SyntaxNode): ChildInfo[] {
  const children: ChildInfo[] = [];
  const cursor = node.cursor();
  if (!cursor.firstChild()) return children;
  do {
    children.push({ name: cursor.name, from: cursor.from, to: cursor.to, node: cursor.node });
  } while (cursor.nextSibling());
  return children;
}

function extractVariableRef(
  node: SyntaxNode,
  text: string,
  knownLookup: KnownLookup | null,
): VarRef | null {
  const ids: string[] = [];
  const cursor = node.cursor();
  if (cursor.firstChild()) {
    do {
      if (cursor.name === "Identifier") {
        ids.push(text.slice(cursor.from, cursor.to));
      }
    } while (cursor.nextSibling());
  }
  if (ids.length < 2) return null;

  if (knownLookup) {
    for (let i = 1; i < ids.length; i++) {
      const sheet = ids.slice(0, i).join(".");
      if (!knownLookup.sheets.has(sheet)) continue;
      const variable = ids.slice(i).join(".");
      if (knownLookup.keys.has(`${sheet}.${variable}`)) {
        return { sheet, variable, from: node.from, to: node.to };
      }
    }
  }

  return {
    sheet: ids.slice(0, -1).join("."),
    variable: ids[ids.length - 1],
    from: node.from,
    to: node.to,
  };
}

function buildKnownLookup(knownVariables: Variable[] | undefined): KnownLookup | null {
  if (!knownVariables) return null;
  return {
    keys: new Set(knownVariables.map((v) => `${v.sheet_shortcut}.${v.variable_name}`)),
    sheets: new Set(knownVariables.map((v) => v.sheet_shortcut)),
  };
}

function extractLiteralValue(child: ChildInfo, text: string): string {
  const raw = text.slice(child.from, child.to);
  if (child.name === "StringLiteral") {
    return raw.slice(1, -1).replace(/\\"/g, '"').replace(/\\\\/g, "\\");
  }
  return raw;
}

function collectErrors(tree: Tree): ParseError[] {
  const errors: ParseError[] = [];
  tree.iterate({
    enter(node) {
      if (node.type.isError) {
        errors.push({
          from: node.from,
          to: Math.max(node.to, node.from + 1),
          message: i18n.global.t("common.expression_editor.syntax_error"),
        });
      }
    },
  });
  return errors;
}

// =============================================================================
// parseAssignments
// =============================================================================

export function parseAssignments(
  text: string,
  knownVariables?: Variable[],
): { assignments: ParsedAssignment[]; errors: ParseError[] } {
  if (!text || !text.trim()) return { assignments: [], errors: [] };

  const knownLookup = buildKnownLookup(knownVariables);
  const allErrors: ParseError[] = [];
  const allAssignments: ParsedAssignment[] = [];

  const rawLines = text.split("\n");
  let offset = 0;

  for (const rawLine of rawLines) {
    const line = rawLine.trim();
    const lineOffset = offset + (rawLine.length - rawLine.trimStart().length);

    if (line) {
      const tree = generatedParser.configure({ top: "AssignmentProgram" }).parse(line);

      tree.iterate({
        enter(node) {
          if (node.type.isError) {
            allErrors.push({
              from: lineOffset + node.from,
              to: lineOffset + Math.max(node.to, node.from + 1),
              message: i18n.global.t("common.expression_editor.syntax_error"),
            });
          }
        },
      });

      const children = getDirectChildren(tree.topNode);
      const groups = splitIntoAssignmentGroups(children);

      for (const group of groups) {
        const a = parseAssignmentGroup(group, line, knownLookup);
        if (a) {
          if (a.ref_from !== undefined) {
            a.ref_from += lineOffset;
            a.ref_to! += lineOffset;
          }
          if (a.value_ref_from !== undefined) {
            a.value_ref_from += lineOffset;
            a.value_ref_to! += lineOffset;
          }
          allAssignments.push(a);
        }
      }
    }

    offset += rawLine.length + 1;
  }

  return { assignments: allAssignments, errors: allErrors };
}

function splitIntoAssignmentGroups(children: ChildInfo[]): ChildInfo[][] {
  const groups: ChildInfo[][] = [];
  let current: ChildInfo[] = [];
  for (let i = 0; i < children.length; i++) {
    const child = children[i];
    if (child.name === "\u26A0") continue;

    if (
      child.name === "VariableRef" &&
      current.length > 0 &&
      i + 1 < children.length &&
      ASSIGN_OPS.has(children[i + 1].name)
    ) {
      groups.push(current);
      current = [];
    }
    current.push(child);
  }
  if (current.length) groups.push(current);
  return groups;
}

function buildBooleanAssignment(
  ref: VarRef,
  valueChild: ChildInfo,
  text: string,
): ParsedAssignment {
  const boolVal = text.slice(valueChild.from, valueChild.to);
  return {
    id: generateId("assign"),
    sheet: ref.sheet,
    variable: ref.variable,
    operator: boolVal === "true" ? "set_true" : "set_false",
    value: null,
    value_type: "literal",
    value_sheet: null,
    ref_from: ref.from,
    ref_to: ref.to,
  };
}

function buildVariableRefAssignment(
  ref: VarRef,
  operator: string,
  valRef: VarRef,
): ParsedAssignment {
  return {
    id: generateId("assign"),
    sheet: ref.sheet,
    variable: ref.variable,
    operator,
    value: valRef.variable,
    value_type: "variable_ref",
    value_sheet: valRef.sheet,
    ref_from: ref.from,
    ref_to: ref.to,
    value_ref_from: valRef.from,
    value_ref_to: valRef.to,
  };
}

function resolveAssignmentValue(
  ref: VarRef,
  operator: string,
  valueChild: ChildInfo,
  text: string,
  knownLookup: KnownLookup | null,
): ParsedAssignment {
  if (valueChild.name === "Boolean" && operator === "set") {
    return buildBooleanAssignment(ref, valueChild, text);
  }
  if (valueChild.name === "VariableRef") {
    const valRef = extractVariableRef(valueChild.node, text, knownLookup);
    if (valRef) return buildVariableRefAssignment(ref, operator, valRef);
  }
  return buildAssignment(ref, operator, extractLiteralValue(valueChild, text));
}

function parseAssignmentGroup(
  children: ChildInfo[],
  text: string,
  knownLookup: KnownLookup | null,
): ParsedAssignment | null {
  const varRefChild = children.find((c) => c.name === "VariableRef");
  if (!varRefChild) return null;

  const ref = extractVariableRef(varRefChild.node, text, knownLookup);
  if (!ref) return null;

  const opChild = children.find((c) => ASSIGN_OPS.has(c.name));
  const operator = opChild ? ASSIGN_OP_MAP[opChild.name] : "set";

  const opIdx = opChild ? children.indexOf(opChild) : -1;
  const valueChildren = opIdx >= 0 ? children.slice(opIdx + 1) : [];
  const valueChild = valueChildren.find((c) => VALUE_TYPES.has(c.name));

  if (!valueChild) return buildAssignment(ref, operator, null);
  return resolveAssignmentValue(ref, operator, valueChild, text, knownLookup);
}

function buildAssignment(ref: VarRef, operator: string, value: string | null): ParsedAssignment {
  return {
    id: generateId("assign"),
    sheet: ref.sheet,
    variable: ref.variable,
    operator,
    value,
    value_type: "literal",
    value_sheet: null,
    ref_from: ref.from,
    ref_to: ref.to,
  };
}

// =============================================================================
// parseCondition
// =============================================================================

export function parseCondition(
  text: string,
  knownVariables?: Variable[],
): { condition: ParsedCondition; errors: ParseError[] } {
  if (!text || !text.trim()) return { condition: { logic: "all", rules: [] }, errors: [] };

  const knownLookup = buildKnownLookup(knownVariables);
  const tree = generatedParser.configure({ top: "ExpressionProgram" }).parse(text);
  const errors = collectErrors(tree);
  const children = getDirectChildren(tree.topNode);
  const result = parseConditionChildren(children, text, knownLookup);

  return { condition: result, errors };
}

function parseConditionChildren(
  children: ChildInfo[],
  text: string,
  knownLookup: KnownLookup | null,
): ParsedCondition {
  const hasOr = children.some((c) => c.name === "Or");
  const hasAnd = children.some((c) => c.name === "And");

  if (hasOr) {
    const groups = splitBy(children, "Or");
    const rules: ParsedRule[] = [];
    for (const group of groups) {
      rules.push(...parseAndGroup(group, text, knownLookup));
    }
    return { logic: "any", rules };
  }

  if (hasAnd) {
    const groups = splitBy(children, "And");
    const rules: ParsedRule[] = [];
    for (const group of groups) {
      const rule = parseSingleComparison(group, text, false, knownLookup);
      if (rule) rules.push(rule);
    }
    return { logic: "all", rules };
  }

  const rule = parseSingleComparison(children, text, false, knownLookup);
  return { logic: "all", rules: rule ? [rule] : [] };
}

function parseAndGroup(
  children: ChildInfo[],
  text: string,
  knownLookup: KnownLookup | null,
): ParsedRule[] {
  const hasAnd = children.some((c) => c.name === "And");
  if (hasAnd) {
    const groups = splitBy(children, "And");
    const rules: ParsedRule[] = [];
    for (const group of groups) {
      const rule = parseSingleComparison(group, text, false, knownLookup);
      if (rule) rules.push(rule);
    }
    return rules;
  }
  const rule = parseSingleComparison(children, text, false, knownLookup);
  return rule ? [rule] : [];
}

function buildRuleBase(ref: VarRef, operator: string): ParsedRule {
  return {
    id: generateId("rule"),
    sheet: ref.sheet,
    variable: ref.variable,
    operator,
    value: null,
    ref_from: ref.from,
    ref_to: ref.to,
  };
}

function buildRuleWithValue(
  ref: VarRef,
  operator: string,
  valueChild: ChildInfo,
  text: string,
  knownLookup: KnownLookup | null,
): ParsedRule {
  const rule = buildRuleBase(ref, operator);
  rule.value_from = valueChild.from;
  rule.value_to = valueChild.to;

  if (valueChild.name === "VariableRef") {
    const valRef = extractVariableRef(valueChild.node, text, knownLookup);
    rule.value = valRef
      ? `${valRef.sheet}.${valRef.variable}`
      : text.slice(valueChild.from, valueChild.to);
  } else {
    rule.value = extractLiteralValue(valueChild, text);
  }

  return rule;
}

/** Unwrap Not / ParenExpr wrappers before comparing. */
function unwrapComparison(
  children: ChildInfo[],
  negated: boolean,
): { children: ChildInfo[]; negated: boolean } {
  const notChild = children.find((c) => c.name === "Not");
  if (notChild) {
    const rest = children.filter((c) => c.name !== "Not");
    return unwrapComparison(rest, !negated);
  }

  const parenChild = children.find((c) => c.name === "ParenExpr");
  if (parenChild) {
    const innerChildren = getDirectChildren(parenChild.node);
    const meaningful = innerChildren.filter(
      (c) => c.name !== "\u26A0" && c.name !== "(" && c.name !== ")",
    );
    return unwrapComparison(meaningful, negated);
  }

  return { children, negated };
}

function parseSingleComparison(
  children: ChildInfo[],
  text: string,
  negated: boolean,
  knownLookup: KnownLookup | null,
): ParsedRule | null {
  const unwrapped = unwrapComparison(children, negated);
  children = unwrapped.children;
  negated = unwrapped.negated;

  const varRefChild = children.find((c) => c.name === "VariableRef");
  if (!varRefChild) return null;

  const ref = extractVariableRef(varRefChild.node, text, knownLookup);
  if (!ref) return null;

  const opChild = children.find((c) => COMPARE_OPS.has(c.name));
  if (!opChild) return buildRuleBase(ref, negated ? "is_false" : "is_true");

  let operator = COMPARE_OP_MAP[opChild.name];
  if (negated) operator = NEGATE_OP[operator] || operator;

  const opIdx = children.indexOf(opChild);
  const valueChild = children.slice(opIdx + 1).find((c) => VALUE_TYPES.has(c.name));
  if (!valueChild) return buildRuleBase(ref, operator);

  return buildRuleWithValue(ref, operator, valueChild, text, knownLookup);
}

function splitBy(children: ChildInfo[], tokenName: string): ChildInfo[][] {
  const groups: ChildInfo[][] = [];
  let current: ChildInfo[] = [];
  for (const child of children) {
    if (child.name === tokenName) {
      if (current.length) groups.push(current);
      current = [];
    } else {
      current.push(child);
    }
  }
  if (current.length) groups.push(current);
  return groups;
}
