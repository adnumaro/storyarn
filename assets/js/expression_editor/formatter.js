/**
 * Expression formatter for the Storyarn expression editor.
 *
 * Formats multi-line expressions with consistent 2-space indentation and
 * operators (|| / &&) at the end of the preceding line, fitting a ~55 char/line width.
 *
 * Works at the string level (no Lezer dependency) — safe to call even when
 * the expression has syntax errors.
 */

const DEFAULT_MAX_WIDTH = 55;
const INDENT_SPACES = 2;

// =============================================================================
// Public API
// =============================================================================

/**
 * Format an expression or assignment block.
 *
 * @param {string} text - Raw editor content
 * @param {string} mode - "expression" | "assignments"
 * @param {number} maxWidth - Target max column width (default 55)
 * @returns {string} Formatted text
 */
export function formatExpression(text, mode, maxWidth = DEFAULT_MAX_WIDTH) {
  if (!text || !text.trim()) return text;

  if (mode === "assignments") {
    return formatAssignments(text);
  }

  return formatConditionExpression(text, maxWidth);
}

// =============================================================================
// Assignment mode
// =============================================================================

/**
 * Normalize assignment text: one assignment per line, trimmed.
 */
function formatAssignments(text) {
  return text
    .split("\n")
    .map((line) => line.trim())
    .filter((line) => line.length > 0)
    .join("\n");
}

// =============================================================================
// Condition expression mode
// =============================================================================

function formatConditionExpression(text, maxWidth) {
  const normalized = normalize(text);
  if (!normalized) return text;
  return formatNode(normalized, 0, maxWidth);
}

/**
 * Collapse all whitespace to single spaces and trim.
 */
function normalize(text) {
  return text.replace(/\s+/g, " ").trim();
}

/**
 * Recursively format a single expression node.
 *
 * @param {string} text - Normalized expression fragment
 * @param {number} depth - Current indent depth (0 = top level)
 * @param {number} maxWidth - Max column width
 * @returns {string}
 */
function formatNode(text, depth, maxWidth) {
  const indent = " ".repeat(depth * INDENT_SPACES);
  const available = maxWidth - indent.length;

  // Fits on one line — done
  if (text.length <= available) {
    return indent + text;
  }

  // Try splitting by || (top-level only)
  const orParts = splitTopLevel(text, "||");
  if (orParts.length > 1) {
    return orParts
      .map((part, i) => {
        const suffix = i < orParts.length - 1 ? " ||" : "";
        const formatted = formatNode(part.trim(), depth, maxWidth);
        return formatted + suffix;
      })
      .join("\n");
  }

  // Try splitting by && (top-level only)
  const andParts = splitTopLevel(text, "&&");
  if (andParts.length > 1) {
    return andParts
      .map((part, i) => {
        const suffix = i < andParts.length - 1 ? " &&" : "";
        const formatted = formatNode(part.trim(), depth, maxWidth);
        return formatted + suffix;
      })
      .join("\n");
  }

  // Try unwrapping outer parens and formatting inner content with more indent
  if (isWrappedInParens(text)) {
    const inner = text.slice(1, -1).trim();
    const innerFormatted = formatNode(inner, depth + 1, maxWidth);
    return `${indent}(\n${innerFormatted}\n${indent})`;
  }

  // Can't break further — return as-is with current indent
  return indent + text;
}

/**
 * Split text by a top-level operator (|| or &&), skipping operators inside
 * quoted strings or parentheses.
 *
 * @param {string} text
 * @param {string} op - "||" or "&&"
 * @returns {string[]} Parts without the operator
 */
function splitTopLevel(text, op) {
  const parts = [];
  let depth = 0;
  let inString = false;
  let stringChar = "";
  let start = 0;
  let i = 0;

  while (i < text.length) {
    const ch = text[i];

    if (inString) {
      if (ch === "\\" && i + 1 < text.length) {
        // Skip escaped character
        i += 2;
        continue;
      }
      if (ch === stringChar) {
        inString = false;
      }
      i++;
      continue;
    }

    if (ch === '"' || ch === "'") {
      inString = true;
      stringChar = ch;
      i++;
      continue;
    }

    if (ch === "(") {
      depth++;
      i++;
      continue;
    }

    if (ch === ")") {
      depth--;
      i++;
      continue;
    }

    if (depth === 0 && text.startsWith(op, i)) {
      parts.push(text.slice(start, i));
      i += op.length;
      start = i;
      continue;
    }

    i++;
  }

  parts.push(text.slice(start));
  return parts.length > 1 ? parts : [text];
}

/**
 * Returns true if the entire text is wrapped in a matching pair of parens.
 * E.g. "(a && b)" → true, "(a) || (b)" → false
 */
function isWrappedInParens(text) {
  if (!text.startsWith("(") || !text.endsWith(")")) return false;

  let depth = 0;
  let inString = false;
  let stringChar = "";

  for (let i = 0; i < text.length; i++) {
    const ch = text[i];

    if (inString) {
      if (ch === "\\" && i + 1 < text.length) {
        i++;
        continue;
      }
      if (ch === stringChar) inString = false;
      continue;
    }

    if (ch === '"' || ch === "'") {
      inString = true;
      stringChar = ch;
      continue;
    }

    if (ch === "(") depth++;
    else if (ch === ")") {
      depth--;
      // If the opening paren closes before the end, this isn't a single wrapper
      if (depth === 0 && i < text.length - 1) return false;
    }
  }

  return depth === 0;
}
