/**
 * CodeMirror theme for Storyarn expression editor.
 *
 * Theme-adaptive: reads --cm-* CSS custom properties from app.css,
 * which are set per [data-theme] (light / dark).
 */

import { HighlightStyle, syntaxHighlighting } from "@codemirror/language";
import { EditorView } from "@codemirror/view";
import { tags } from "@lezer/highlight";

/** Theme-adaptive palette — reads CSS custom properties set per data-theme. */
const COLORS = {
  bg: "var(--cm-bg)",
  gutterBg: "var(--cm-gutter-bg)",
  gutterFg: "var(--cm-gutter-fg)",
  gutterBorder: "var(--cm-gutter-border)",
  activeLine: "var(--cm-active-line)",
  activeGutter: "var(--cm-active-gutter)",
  selection: "var(--cm-selection)",
  cursor: "var(--cm-cursor)",
  text: "var(--cm-text)",
  placeholder: "var(--cm-placeholder)",
  // Syntax
  variable: "var(--cm-variable)", // identifiers / variable refs
  string: "var(--cm-string)",     // string literals
  number: "var(--cm-number)",     // numbers
  keyword: "var(--cm-keyword)",   // &&, ||, !, true, false, nil
  operator: "var(--cm-operator)", // ==, !=, >, <, +=, =, …
  paren: "var(--cm-paren)",       // ( )
  punct: "var(--cm-punct)",       // dots, other punctuation
  comment: "var(--cm-comment)",   // // comments
  // Tooltips
  tooltipBg: "var(--cm-tooltip-bg)",
  tooltipBorder: "var(--cm-tooltip-border)",
};

/** Base editor theme: layout, cursor, selection, gutters, tooltips. */
export const storyarnEditorTheme = EditorView.theme({
  "&": {
    fontSize: "13px",
    fontFamily: "ui-monospace, SFMono-Regular, 'SF Mono', Menlo, monospace",
    backgroundColor: COLORS.bg,
    color: COLORS.text,
  },
  ".cm-scroller": {
    fontFamily: "inherit",
  },
  ".cm-content": {
    padding: "8px 0",
    caretColor: COLORS.cursor,
  },
  ".cm-line": {
    padding: "0 8px",
  },
  "&.cm-focused .cm-cursor": {
    borderLeftColor: COLORS.cursor,
  },
  "&.cm-focused .cm-selectionBackground, .cm-selectionBackground": {
    backgroundColor: COLORS.selection,
  },
  ".cm-activeLine": {
    backgroundColor: COLORS.activeLine,
  },
  // Gutters (line numbers)
  ".cm-gutters": {
    backgroundColor: COLORS.gutterBg,
    color: COLORS.gutterFg,
    border: "none",
    borderRight: `1px solid ${COLORS.gutterBorder}`,
  },
  ".cm-lineNumbers .cm-gutterElement": {
    padding: "0 8px 0 4px",
    minWidth: "2rem",
    textAlign: "right",
    fontSize: "11px",
  },
  ".cm-activeLineGutter": {
    backgroundColor: COLORS.activeGutter,
    color: COLORS.text,
  },
  // Placeholder
  ".cm-placeholder": {
    color: COLORS.placeholder,
    fontStyle: "italic",
  },
  // Autocomplete tooltip — z-index above sidebars (z-1010)
  ".cm-tooltip": {
    backgroundColor: COLORS.tooltipBg,
    border: `1px solid ${COLORS.tooltipBorder}`,
    borderRadius: "0.5rem",
    boxShadow: "0 4px 6px -1px rgb(0 0 0 / 0.4)",
    zIndex: "2000",
  },
  ".cm-tooltip-autocomplete ul li": {
    padding: "2px 8px",
    color: COLORS.text,
  },
  ".cm-tooltip-autocomplete ul li[aria-selected]": {
    backgroundColor: COLORS.activeLine,
    color: COLORS.variable,
  },
  // Diagnostics (linting underlines)
  ".cm-diagnostic-error": {
    borderBottom: "2px solid #e06c75",
  },
  ".cm-diagnostic-warning": {
    borderBottom: "2px solid #e5c07b",
  },
});

const highlightStyle = HighlightStyle.define([
  // Variable refs / identifiers — blue
  { tag: tags.variableName, color: COLORS.variable },
  { tag: tags.name, color: COLORS.variable },
  // Assignment operators (=, +=, -=, ?=) — cyan
  { tag: tags.operator, color: COLORS.operator },
  // Compare operators (==, !=, >, <, >=, <=) — cyan
  { tag: tags.compareOperator, color: COLORS.operator },
  // Strings — green
  { tag: tags.string, color: COLORS.string },
  // Numbers — orange
  { tag: tags.number, color: COLORS.number },
  // Booleans (true, false) — purple
  { tag: tags.bool, color: COLORS.keyword },
  // Null (nil) — purple
  { tag: tags.null, color: COLORS.keyword },
  // Keywords (&&, ||, !) — purple
  { tag: tags.keyword, color: COLORS.keyword },
  // Parentheses ( ) — yellow
  { tag: tags.paren, color: COLORS.paren },
  // Other punctuation (dots, separators) — text color
  { tag: tags.punctuation, color: COLORS.punct },
  // Comments — gray italic
  { tag: tags.lineComment, color: COLORS.comment, fontStyle: "italic" },
]);

/** Syntax highlighting extension. */
export const storyarnHighlighting = syntaxHighlighting(highlightStyle);
