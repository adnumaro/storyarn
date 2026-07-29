/**
 * Classifies command-palette reference patterns without resolving them.
 *
 * Resolution remains server-owned because a dotted path can have different
 * sheet/variable boundaries in different authorized projects. This module
 * only decides whether the root palette input belongs to the guided door or
 * to the reference-pattern door, and whether a pattern is ready to request.
 */

import { parser as generatedParser } from "./parser-generated.js";

export type ReferencePatternKind = "exact" | "partial" | "deep_wildcard" | "deep_wildcard_partial";

export type ReferencePatternSegment =
  | { kind: "identifier"; value: string }
  | { kind: "partial"; value: string }
  | { kind: "deep_wildcard" };

export interface ReferencePattern {
  raw: string;
  kind: ReferencePatternKind;
  segments: ReferencePatternSegment[];
}

export type ReferencePatternClassification =
  | { state: "normal" }
  | { state: "incomplete"; raw: string }
  | { state: "invalid"; raw: string }
  | { state: "ready"; pattern: ReferencePattern };

const identifierPattern = /^[a-zA-Z_][a-zA-Z0-9_-]*$/;
const partialIdentifierPattern = /^[a-zA-Z0-9_-]+$/;
const patternParser = generatedParser.configure({ top: "ReferencePatternProgram" });

/**
 * Classifies one unmodified input value.
 *
 * Whitespace is intentionally not trimmed. Dotted references are an atomic
 * symbolic language, and accepting comments/spacing here would make the
 * palette grammar differ from the notation displayed throughout Storyarn.
 */
export function classifyReferencePattern(input: string): ReferencePatternClassification {
  if (!patternIntent(input)) return { state: "normal" };

  if (containsForbiddenSyntax(input)) return { state: "invalid", raw: input };

  // The bare global partial would otherwise request every visible reference.
  // Keep the reference-pattern door open, but wait for a search term.
  if (input === "?") return { state: "incomplete", raw: input };

  if (validReferencePattern(input) && supportedReferencePattern(input)) {
    return { state: "ready", pattern: buildReferencePattern(input) };
  }

  if (incompleteReferencePattern(input)) {
    return { state: "incomplete", raw: input };
  }

  return { state: "invalid", raw: input };
}

function patternIntent(input: string): boolean {
  if (input === "") return false;
  const candidate = input.trimStart();

  // `?heal` is the global partial-identifier form. A leading quote is
  // reserved for the later content-search door and is invalid in this slice.
  if (
    candidate.startsWith("?") ||
    candidate.startsWith('"') ||
    candidate.startsWith("'") ||
    candidate.startsWith("`") ||
    candidate.startsWith("/")
  ) {
    return true;
  }

  // Once the first identifier is followed by a dot, the pattern door owns the
  // interaction, including incomplete and malformed forms such as `mc.`.
  return /^[a-zA-Z_][a-zA-Z0-9_-]*\s*\./.test(candidate);
}

function containsForbiddenSyntax(input: string): boolean {
  return /\s|["'`/]/.test(input);
}

function validReferencePattern(input: string): boolean {
  const tree = patternParser.parse(input);
  let hasError = false;

  tree.iterate({
    enter(node) {
      if (node.type.isError) hasError = true;
    },
  });

  return !hasError && tree.length === input.length;
}

function incompleteReferencePattern(input: string): boolean {
  if (input === "?" || input === "sheets.**" || input === "sheets.**." || input === "sheets.**.?") {
    return true;
  }

  if (!input.endsWith(".")) return false;

  const segments = input.slice(0, -1).split(".");
  return segments.length > 0 && segments.every((segment) => identifierPattern.test(segment));
}

function supportedReferencePattern(input: string): boolean {
  if (input.startsWith("?")) {
    return partialIdentifierPattern.test(input.slice(1));
  }

  const segments = input.split(".");

  if (segments[0] === "sheets" && segments[1] === "**") {
    if (segments.length !== 3) return false;

    const variable = segments[2] ?? "";
    return variable.startsWith("?")
      ? partialIdentifierPattern.test(variable.slice(1))
      : identifierPattern.test(variable);
  }

  if (segments.at(-1) === "?") {
    return (
      segments.length >= 2 &&
      segments.slice(0, -1).every((segment) => identifierPattern.test(segment))
    );
  }

  return segments.length >= 2 && segments.every((segment) => identifierPattern.test(segment));
}

function buildReferencePattern(raw: string): ReferencePattern {
  const segments = raw.split(".").map((segment): ReferencePatternSegment => {
    if (segment === "**") return { kind: "deep_wildcard" };
    if (segment.startsWith("?")) return { kind: "partial", value: segment.slice(1) };
    return { kind: "identifier", value: segment };
  });
  const hasWildcard = segments.some((segment) => segment.kind === "deep_wildcard");
  const hasPartial = segments.at(-1)?.kind === "partial";
  let kind: ReferencePatternKind;

  if (hasWildcard) {
    kind = hasPartial ? "deep_wildcard_partial" : "deep_wildcard";
  } else {
    kind = hasPartial ? "partial" : "exact";
  }

  return {
    raw,
    kind,
    segments,
  };
}
