/**
 * Storyarn expression language definition for CodeMirror.
 *
 * Wraps the Lezer-generated parser with syntax highlighting tags
 * and provides a language instance per mode (condition vs instruction).
 */

import { LRLanguage, LanguageSupport } from "@codemirror/language";
import { styleTags, tags as t } from "@lezer/highlight";
import { parser } from "./parser-generated.js";

const storyarnStyleTags = styleTags({
  Identifier: t.variableName,
  VariableRef: t.variableName,
  StringLiteral: t.string,
  Number: t.number,
  Boolean: t.keyword,
  Null: t.keyword,
  "SetOp AddOp SubOp SetIfUnsetOp": t.definitionOperator,
  "Eq Neq Gte Lte Gt Lt": t.compareOperator,
  "StartsWithOp EndsWithOp ContainsOp NotContainsOp": t.compareOperator,
  "And Or": t.logicOperator,
  Not: t.logicOperator,
  "( )": t.paren,
  LineComment: t.lineComment,
});

const configuredParser = parser.configure({ props: [storyarnStyleTags] });

/** Language for condition/expression mode (single boolean expression). */
export const expressionLanguage = LRLanguage.define({
  name: "storyarn-expression",
  parser: configuredParser.configure({ top: "ExpressionProgram" }),
  languageData: {
    commentTokens: { line: "//" },
  },
});

/** Language for assignment/instruction mode (multi-line assignments). */
export const assignmentLanguage = LRLanguage.define({
  name: "storyarn-assignment",
  parser: configuredParser.configure({ top: "AssignmentProgram" }),
  languageData: {
    commentTokens: { line: "//" },
  },
});

/** Get the appropriate LanguageSupport for the given mode. */
export function storyarnLanguage(mode: "condition" | "instruction"): LanguageSupport {
  const lang = mode === "condition" ? expressionLanguage : assignmentLanguage;
  return new LanguageSupport(lang);
}
