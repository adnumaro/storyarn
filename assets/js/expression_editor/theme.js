/**
 * CodeMirror theme for Storyarn expression editor.
 * Uses CSS variables from daisyUI v5 / Tailwind v4 theme for consistency.
 */

import { HighlightStyle, syntaxHighlighting } from "@codemirror/language";
import { EditorView } from "@codemirror/view";
import { tags } from "@lezer/highlight";

/** Base editor theme: fonts, cursor, selection, tooltip, and diagnostic styles. */
export const storyarnEditorTheme = EditorView.theme({
  "&": {
    fontSize: "13px",
    fontFamily: "ui-monospace, SFMono-Regular, 'SF Mono', Menlo, monospace",
  },
  ".cm-content": {
    padding: "8px 0",
    caretColor: "var(--color-base-content)",
  },
  ".cm-line": {
    padding: "0 8px",
  },
  "&.cm-focused .cm-cursor": {
    borderLeftColor: "var(--color-base-content)",
  },
  "&.cm-focused .cm-selectionBackground, .cm-selectionBackground": {
    backgroundColor: "color-mix(in oklch, var(--color-base-content) 15%, transparent)",
  },
  ".cm-activeLine": {
    backgroundColor: "color-mix(in oklch, var(--color-base-content) 5%, transparent)",
  },
  ".cm-gutters": {
    display: "none",
  },
  ".cm-placeholder": {
    color: "color-mix(in oklch, var(--color-base-content) 35%, transparent)",
    fontStyle: "italic",
  },
  ".cm-tooltip": {
    backgroundColor: "var(--color-base-100)",
    border: "1px solid var(--color-base-300)",
    borderRadius: "0.5rem",
    boxShadow: "0 4px 6px -1px rgb(0 0 0 / 0.1)",
  },
  ".cm-tooltip-autocomplete ul li": {
    padding: "2px 8px",
  },
  ".cm-tooltip-autocomplete ul li[aria-selected]": {
    backgroundColor: "color-mix(in oklch, var(--color-primary) 15%, transparent)",
    color: "var(--color-base-content)",
  },
  ".cm-diagnostic-error": {
    borderBottom: "2px solid var(--color-error)",
  },
  ".cm-diagnostic-warning": {
    borderBottom: "2px solid var(--color-warning)",
  },
});

const highlightStyle = HighlightStyle.define([
  // Variable refs (identifiers)
  { tag: tags.variableName, color: "var(--color-info)" },
  { tag: tags.name, color: "var(--color-info)" },
  // Operators
  { tag: tags.operator, color: "var(--color-secondary)" },
  { tag: tags.compareOperator, color: "var(--color-secondary)" },
  // Strings
  { tag: tags.string, color: "var(--color-success)" },
  // Numbers
  { tag: tags.number, color: "var(--color-warning)" },
  // Booleans / keywords
  { tag: tags.bool, color: "var(--color-accent)" },
  { tag: tags.keyword, color: "var(--color-accent)" },
  // Punctuation (dots, parens)
  {
    tag: tags.punctuation,
    color: "color-mix(in oklch, var(--color-base-content) 50%, transparent)",
  },
  // Comments
  {
    tag: tags.lineComment,
    color: "color-mix(in oklch, var(--color-base-content) 40%, transparent)",
    fontStyle: "italic",
  },
]);

/** Syntax highlighting extension mapping language tokens to daisyUI CSS variables. */
export const storyarnHighlighting = syntaxHighlighting(highlightStyle);
