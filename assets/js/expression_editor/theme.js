/**
 * CodeMirror theme for Storyarn expression editor.
 * Uses CSS variables from daisyUI theme for consistency.
 */

import { HighlightStyle, syntaxHighlighting } from "@codemirror/language";
import { EditorView } from "@codemirror/view";
import { tags } from "@lezer/highlight";

export const storyarnEditorTheme = EditorView.theme({
  "&": {
    fontSize: "13px",
    fontFamily: "ui-monospace, SFMono-Regular, 'SF Mono', Menlo, monospace",
  },
  ".cm-content": {
    padding: "8px 0",
    caretColor: "oklch(var(--bc))",
  },
  ".cm-line": {
    padding: "0 8px",
  },
  "&.cm-focused .cm-cursor": {
    borderLeftColor: "oklch(var(--bc))",
  },
  "&.cm-focused .cm-selectionBackground, .cm-selectionBackground": {
    backgroundColor: "oklch(var(--bc) / 0.15)",
  },
  ".cm-activeLine": {
    backgroundColor: "oklch(var(--bc) / 0.05)",
  },
  ".cm-gutters": {
    display: "none",
  },
  ".cm-placeholder": {
    color: "oklch(var(--bc) / 0.35)",
    fontStyle: "italic",
  },
  ".cm-tooltip": {
    backgroundColor: "oklch(var(--b1))",
    border: "1px solid oklch(var(--b3))",
    borderRadius: "0.5rem",
    boxShadow: "0 4px 6px -1px rgb(0 0 0 / 0.1)",
  },
  ".cm-tooltip-autocomplete ul li": {
    padding: "2px 8px",
  },
  ".cm-tooltip-autocomplete ul li[aria-selected]": {
    backgroundColor: "oklch(var(--p) / 0.15)",
    color: "oklch(var(--bc))",
  },
  ".cm-diagnostic-error": {
    borderBottom: "2px solid oklch(var(--er))",
  },
  ".cm-diagnostic-warning": {
    borderBottom: "2px solid oklch(var(--wa))",
  },
});

const highlightStyle = HighlightStyle.define([
  // Variable refs (identifiers)
  { tag: tags.variableName, color: "oklch(var(--in))" },
  { tag: tags.name, color: "oklch(var(--in))" },
  // Operators
  { tag: tags.operator, color: "oklch(var(--s))" },
  { tag: tags.compareOperator, color: "oklch(var(--s))" },
  // Strings
  { tag: tags.string, color: "oklch(var(--su))" },
  // Numbers
  { tag: tags.number, color: "oklch(var(--wa))" },
  // Booleans / keywords
  { tag: tags.bool, color: "oklch(var(--a))" },
  { tag: tags.keyword, color: "oklch(var(--a))" },
  // Punctuation (dots, parens)
  { tag: tags.punctuation, color: "oklch(var(--bc) / 0.5)" },
  // Comments
  { tag: tags.lineComment, color: "oklch(var(--bc) / 0.4)", fontStyle: "italic" },
]);

export const storyarnHighlighting = syntaxHighlighting(highlightStyle);
