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
import { parser as generatedParser } from "./parser_generated.js";

// -- Operator mappings --

const ASSIGN_OPS = new Set(["SetOp", "AddOp", "SubOp", "SetIfUnsetOp"]);

const ASSIGN_OP_MAP = {
  SetOp: "set",
  AddOp: "add",
  SubOp: "subtract",
  SetIfUnsetOp: "set_if_unset",
};

const COMPARE_OPS = new Set(["Eq", "Neq", "Gt", "Lt", "Gte", "Lte"]);

const COMPARE_OP_MAP = {
  Eq: "equals",
  Neq: "not_equals",
  Gt: "greater_than",
  Lt: "less_than",
  Gte: "greater_than_or_equal",
  Lte: "less_than_or_equal",
};

const NEGATE_OP = {
  equals: "not_equals",
  not_equals: "equals",
  greater_than: "less_than_or_equal",
  less_than: "greater_than_or_equal",
  greater_than_or_equal: "less_than",
  less_than_or_equal: "greater_than",
};

const VALUE_TYPES = new Set(["VariableRef", "Number", "StringLiteral", "Boolean"]);

// -- ID generation --

let idCounter = 0;

function generateId(prefix) {
  idCounter += 1;
  return `${prefix}_${Date.now()}_${idCounter}`;
}

// -- Helpers --

function getDirectChildren(node) {
  const children = [];
  const cursor = node.cursor();
  if (!cursor.firstChild()) return children;
  do {
    children.push({
      name: cursor.name,
      from: cursor.from,
      to: cursor.to,
      node: cursor.node,
    });
  } while (cursor.nextSibling());
  return children;
}

function extractVariableRef(node, text, knownLookup) {
  const ids = [];
  const cursor = node.cursor();
  if (cursor.firstChild()) {
    do {
      if (cursor.name === "Identifier") {
        ids.push(text.slice(cursor.from, cursor.to));
      }
    } while (cursor.nextSibling());
  }
  if (ids.length < 2) return null;

  // Try matching against known variables (handles 4-level table paths)
  // Requires both a known sheet shortcut AND a known variable key to disambiguate
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

  // Fallback: last segment = variable, rest = sheet
  return {
    sheet: ids.slice(0, -1).join("."),
    variable: ids[ids.length - 1],
    from: node.from,
    to: node.to,
  };
}

function buildKnownLookup(knownVariables) {
  if (!knownVariables) return null;
  return {
    keys: new Set(knownVariables.map((v) => `${v.sheet_shortcut}.${v.variable_name}`)),
    sheets: new Set(knownVariables.map((v) => v.sheet_shortcut)),
  };
}

function extractLiteralValue(child, text) {
  const raw = text.slice(child.from, child.to);
  if (child.name === "StringLiteral") {
    return raw.slice(1, -1).replace(/\\"/g, '"').replace(/\\\\/g, "\\");
  }
  return raw; // Number or Boolean
}

function collectErrors(tree) {
  const errors = [];
  tree.iterate({
    enter(node) {
      if (node.type.isError) {
        errors.push({
          from: node.from,
          to: Math.max(node.to, node.from + 1),
          message: "Syntax error",
        });
      }
    },
  });
  return errors;
}

// =============================================================================
// parseAssignments
// =============================================================================

/**
 * Parse assignment program text into Storyarn assignments array.
 * @param {string} text
 * @param {Array<{sheet_shortcut: string, variable_name: string}>} [knownVariables]
 * @returns {{ assignments: Array, errors: Array }}
 */
export function parseAssignments(text, knownVariables) {
  if (!text || !text.trim()) return { assignments: [], errors: [] };

  const knownLookup = buildKnownLookup(knownVariables);

  const tree = generatedParser.configure({ top: "AssignmentProgram" }).parse(text);
  const errors = collectErrors(tree);
  const children = getDirectChildren(tree.topNode);

  // Split children into assignment groups.
  // Each assignment starts with a VariableRef followed by an assign op.
  // The semicolon separator is consumed by the grammar but not visible in the tree.
  // We look ahead: a VariableRef starts a new assignment only if the NEXT token is an assign op.
  const groups = [];
  let current = [];
  for (let i = 0; i < children.length; i++) {
    const child = children[i];
    if (child.name === "⚠") continue;

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

  const assignments = [];
  for (const group of groups) {
    const a = parseAssignmentGroup(group, text, knownLookup);
    if (a) assignments.push(a);
  }

  return { assignments, errors };
}

function parseAssignmentGroup(children, text, knownLookup) {
  // Expected: VariableRef, AssignOp, then value tokens
  const varRefChild = children.find((c) => c.name === "VariableRef");
  if (!varRefChild) return null;

  const ref = extractVariableRef(varRefChild.node, text, knownLookup);
  if (!ref) return null;

  // Find assignment operator
  const opChild = children.find((c) => ASSIGN_OPS.has(c.name));
  const operator = opChild ? ASSIGN_OP_MAP[opChild.name] : "set";

  // Find value token (first value-type child after the operator)
  const opIdx = opChild ? children.indexOf(opChild) : -1;
  const valueChildren = opIdx >= 0 ? children.slice(opIdx + 1) : [];
  const valueChild = valueChildren.find((c) => VALUE_TYPES.has(c.name));

  if (!valueChild) {
    return buildAssignment(ref, operator, null);
  }

  // Boolean = true/false with SetOp maps to set_true/set_false
  if (valueChild.name === "Boolean" && operator === "set") {
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

  // Variable ref value
  if (valueChild.name === "VariableRef") {
    const valRef = extractVariableRef(valueChild.node, text, knownLookup);
    if (valRef) {
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
  }

  // Literal value (Number, StringLiteral)
  const value = extractLiteralValue(valueChild, text);
  return buildAssignment(ref, operator, value);
}

function buildAssignment(ref, operator, value) {
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

/**
 * Parse boolean expression text into Storyarn condition object.
 * @param {string} text
 * @param {Array<{sheet_shortcut: string, variable_name: string}>} [knownVariables]
 * @returns {{ condition: Object, errors: Array }}
 */
export function parseCondition(text, knownVariables) {
  if (!text || !text.trim()) return { condition: { logic: "all", rules: [] }, errors: [] };

  const knownLookup = buildKnownLookup(knownVariables);

  const tree = generatedParser.configure({ top: "ExpressionProgram" }).parse(text);
  const errors = collectErrors(tree);
  const children = getDirectChildren(tree.topNode);

  const result = parseConditionChildren(children, text, knownLookup);
  return { condition: result, errors };
}

function parseConditionChildren(children, text, knownLookup) {
  // Check for OR operators — they split into "any" logic
  const hasOr = children.some((c) => c.name === "Or");
  const hasAnd = children.some((c) => c.name === "And");

  if (hasOr) {
    // Split by Or, each group is AND-ed internally
    const groups = splitBy(children, "Or");
    const rules = [];
    for (const group of groups) {
      const groupRules = parseAndGroup(group, text, knownLookup);
      rules.push(...groupRules);
    }
    return { logic: "any", rules };
  }

  if (hasAnd) {
    const groups = splitBy(children, "And");
    const rules = [];
    for (const group of groups) {
      const rule = parseSingleComparison(group, text, false, knownLookup);
      if (rule) rules.push(rule);
    }
    return { logic: "all", rules };
  }

  // Single comparison or bare value
  const rule = parseSingleComparison(children, text, false, knownLookup);
  return { logic: "all", rules: rule ? [rule] : [] };
}

function parseAndGroup(children, text, knownLookup) {
  // Within an OR group, split further by AND
  const hasAnd = children.some((c) => c.name === "And");
  if (hasAnd) {
    const groups = splitBy(children, "And");
    const rules = [];
    for (const group of groups) {
      const rule = parseSingleComparison(group, text, false, knownLookup);
      if (rule) rules.push(rule);
    }
    return rules;
  }
  const rule = parseSingleComparison(children, text, false, knownLookup);
  return rule ? [rule] : [];
}

function parseSingleComparison(children, text, negated, knownLookup) {
  // Check for Not operator
  const notChild = children.find((c) => c.name === "Not");
  if (notChild) {
    const rest = children.filter((c) => c.name !== "Not");
    return parseSingleComparison(rest, text, !negated, knownLookup);
  }

  // Check for ParenExpr — descend into it
  const parenChild = children.find((c) => c.name === "ParenExpr");
  if (parenChild) {
    const innerChildren = getDirectChildren(parenChild.node);
    // Filter out literal paren tokens (they appear as unnamed nodes)
    const meaningful = innerChildren.filter(
      (c) => c.name !== "⚠" && c.name !== "(" && c.name !== ")",
    );
    return parseSingleComparison(meaningful, text, negated, knownLookup);
  }

  // Find variable ref (left side)
  const varRefChild = children.find((c) => c.name === "VariableRef");
  if (!varRefChild) return null;

  const ref = extractVariableRef(varRefChild.node, text, knownLookup);
  if (!ref) return null;

  // Find comparison operator
  const opChild = children.find((c) => COMPARE_OPS.has(c.name));

  if (!opChild) {
    // Bare variable ref — is_true or is_false
    return {
      id: generateId("rule"),
      sheet: ref.sheet,
      variable: ref.variable,
      operator: negated ? "is_false" : "is_true",
      value: null,
      ref_from: ref.from,
      ref_to: ref.to,
    };
  }

  let operator = COMPARE_OP_MAP[opChild.name];
  if (negated) operator = NEGATE_OP[operator] || operator;

  // Find value (right side) — first value-type after the comparison operator
  const opIdx = children.indexOf(opChild);
  const rhsChildren = children.slice(opIdx + 1);
  const valueChild = rhsChildren.find((c) => VALUE_TYPES.has(c.name));

  if (!valueChild) {
    // Incomplete comparison
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

  let value;
  const rule = {
    id: generateId("rule"),
    sheet: ref.sheet,
    variable: ref.variable,
    operator,
    ref_from: ref.from,
    ref_to: ref.to,
  };

  if (valueChild.name === "VariableRef") {
    const valRef = extractVariableRef(valueChild.node, text, knownLookup);
    value = valRef
      ? `${valRef.sheet}.${valRef.variable}`
      : text.slice(valueChild.from, valueChild.to);
    rule.value_from = valueChild.from;
    rule.value_to = valueChild.to;
  } else {
    value = extractLiteralValue(valueChild, text);
    rule.value_from = valueChild.from;
    rule.value_to = valueChild.to;
  }

  rule.value = value;
  return rule;
}

function splitBy(children, tokenName) {
  const groups = [];
  let current = [];
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
