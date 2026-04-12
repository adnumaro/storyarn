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

export function formatExpression(
  text: string,
  mode: "condition" | "instruction",
  maxWidth: number = DEFAULT_MAX_WIDTH,
): string {
  if (!text || !text.trim()) return text;
  if (mode === "instruction") return formatAssignments(text);
  return formatConditionExpression(text, maxWidth);
}

function formatAssignments(text: string): string {
  return text
    .split("\n")
    .map((line) => line.trim())
    .filter((line) => line.length > 0)
    .join("\n");
}

function formatConditionExpression(text: string, maxWidth: number): string {
  const normalized = text.replace(/\s+/g, " ").trim();
  if (!normalized) return text;
  return formatNode(normalized, 0, maxWidth);
}

function formatNode(text: string, depth: number, maxWidth: number): string {
  const indent = " ".repeat(depth * INDENT_SPACES);
  const available = maxWidth - indent.length;

  if (text.length <= available) return indent + text;

  const orParts = splitTopLevel(text, "||");
  if (orParts.length > 1) {
    return orParts
      .map((part, i) => {
        const suffix = i < orParts.length - 1 ? " ||" : "";
        return formatNode(part.trim(), depth, maxWidth) + suffix;
      })
      .join("\n");
  }

  const andParts = splitTopLevel(text, "&&");
  if (andParts.length > 1) {
    return andParts
      .map((part, i) => {
        const suffix = i < andParts.length - 1 ? " &&" : "";
        return formatNode(part.trim(), depth, maxWidth) + suffix;
      })
      .join("\n");
  }

  if (isWrappedInParens(text)) {
    const inner = text.slice(1, -1).trim();
    const innerFormatted = formatNode(inner, depth + 1, maxWidth);
    return `${indent}(\n${innerFormatted}\n${indent})`;
  }

  return indent + text;
}

/** Shared string-tracking state for expression scanners. */
interface StringScanState {
  inString: boolean;
  stringChar: string;
}

/**
 * Handle string-literal tracking for the current character.
 * Returns "escape" if inside a string and hit a backslash (caller must skip +1),
 * "consumed" if the character is part of a string literal,
 * or "normal" if the character is outside any string.
 */
function scanStringChar(ch: string, nextCh: string | undefined, state: StringScanState): "escape" | "consumed" | "normal" {
  if (state.inString) {
    if (ch === "\\" && nextCh !== undefined) return "escape";
    if (ch === state.stringChar) state.inString = false;
    return "consumed";
  }
  if (ch === '"' || ch === "'") {
    state.inString = true;
    state.stringChar = ch;
    return "consumed";
  }
  return "normal";
}

function splitTopLevel(text: string, op: string): string[] {
  const parts: string[] = [];
  const ss: StringScanState = { inString: false, stringChar: "" };
  let depth = 0;
  let start = 0;
  let i = 0;

  while (i < text.length) {
    const ch = text[i];
    const scan = scanStringChar(ch, text[i + 1], ss);
    if (scan === "escape") { i += 2; continue; }
    if (scan === "consumed") { i++; continue; }

    if (ch === "(") { depth++; i++; continue; }
    if (ch === ")") { depth--; i++; continue; }

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

function isWrappedInParens(text: string): boolean {
  if (!text.startsWith("(") || !text.endsWith(")")) return false;

  const ss: StringScanState = { inString: false, stringChar: "" };
  let depth = 0;

  for (let i = 0; i < text.length; i++) {
    const ch = text[i];
    const scan = scanStringChar(ch, text[i + 1], ss);
    if (scan === "escape") { i++; continue; }
    if (scan === "consumed") continue;

    if (ch === "(") depth++;
    else if (ch === ")") {
      depth--;
      if (depth === 0 && i < text.length - 1) return false;
    }
  }

  return depth === 0;
}
