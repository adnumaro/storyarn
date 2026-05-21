/**
 * CodeMirror theme for Storyarn expression editor.
 *
 * Reads --cm-* CSS custom properties from app.css,
 * which are set per [data-theme] (light / dark).
 */

import { HighlightStyle, syntaxHighlighting } from "@codemirror/language";
import { EditorView } from "@codemirror/view";
import { tags } from "@lezer/highlight";

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
  variable: "var(--cm-variable)",
  string: "var(--cm-string)",
  number: "var(--cm-number)",
  keyword: "var(--cm-keyword)",
  operator: "var(--cm-operator)",
  paren: "var(--cm-paren)",
  punct: "var(--cm-punct)",
  comment: "var(--cm-comment)",
  tooltipBg: "var(--cm-tooltip-bg)",
  tooltipBorder: "var(--cm-tooltip-border)",
};

export const storyarnEditorTheme = EditorView.theme({
  "&": {
    fontSize: "13px",
    fontFamily: "ui-monospace, SFMono-Regular, 'SF Mono', Menlo, monospace",
    backgroundColor: COLORS.bg,
    color: COLORS.text,
  },
  ".cm-scroller": { fontFamily: "inherit" },
  ".cm-content": { padding: "8px 0", caretColor: COLORS.cursor },
  ".cm-line": { padding: "0 8px" },
  "&.cm-focused .cm-cursor": { borderLeftColor: COLORS.cursor },
  "&.cm-focused .cm-selectionBackground, .cm-selectionBackground": {
    backgroundColor: COLORS.selection,
  },
  ".cm-activeLine": { backgroundColor: COLORS.activeLine },
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
  ".cm-placeholder": { color: COLORS.placeholder, fontStyle: "italic" },
  ".cm-tooltip": {
    backgroundColor: COLORS.tooltipBg,
    border: `1px solid ${COLORS.tooltipBorder}`,
    borderRadius: "0.5rem",
    boxShadow: "0 4px 6px -1px rgb(0 0 0 / 0.4)",
    zIndex: "2000",
  },
  ".cm-tooltip-autocomplete ul li": { padding: "2px 8px", color: COLORS.text },
  ".cm-tooltip-autocomplete ul li[aria-selected]": {
    backgroundColor: COLORS.activeLine,
    color: COLORS.variable,
  },
  ".cm-diagnostic-error": { borderBottom: "2px solid #e06c75" },
  ".cm-diagnostic-warning": { borderBottom: "2px solid #e5c07b" },
});

const highlightStyle = HighlightStyle.define([
  { tag: tags.variableName, color: COLORS.variable },
  { tag: tags.name, color: COLORS.variable },
  { tag: tags.operator, color: COLORS.operator },
  { tag: tags.compareOperator, color: COLORS.operator },
  { tag: tags.string, color: COLORS.string },
  { tag: tags.number, color: COLORS.number },
  { tag: tags.bool, color: COLORS.keyword },
  { tag: tags.null, color: COLORS.keyword },
  { tag: tags.keyword, color: COLORS.keyword },
  { tag: tags.paren, color: COLORS.paren },
  { tag: tags.punctuation, color: COLORS.punct },
  { tag: tags.lineComment, color: COLORS.comment, fontStyle: "italic" },
]);

export const storyarnHighlighting = syntaxHighlighting(highlightStyle);
