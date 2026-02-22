/**
 * CodeMirror editor factory for Storyarn expression DSL.
 *
 * Creates a configured CodeMirror 6 instance with syntax highlighting,
 * appropriate top rule (assignments or expression), and change callbacks.
 */

import { defaultKeymap, history, historyKeymap } from "@codemirror/commands";
import { LanguageSupport, LRLanguage } from "@codemirror/language";
import { EditorState } from "@codemirror/state";
import { EditorView, keymap, placeholder as placeholderExt, tooltips } from "@codemirror/view";
import { styleTags, tags } from "@lezer/highlight";
import { variableAutocomplete } from "./autocomplete.js";
import { expressionLinter } from "./linter.js";
import { parser as exprParser } from "./parser_generated.js";
import { storyarnEditorTheme, storyarnHighlighting } from "./theme.js";

/**
 * Create a CodeMirror editor instance.
 * @param {Object} opts
 * @param {HTMLElement} opts.container - DOM element to mount editor into
 * @param {string} opts.content - Initial text
 * @param {"assignments"|"expression"} opts.mode - Parser mode
 * @param {boolean} opts.editable - Whether content is editable
 * @param {Function} opts.onChange - Callback when content changes: (text) => void
 * @param {string} [opts.placeholderText] - Placeholder text
 * @param {Array} [opts.variables] - Variable list for autocomplete
 * @param {Array} [opts.extraExtensions] - Additional CodeMirror extensions
 * @returns {{ view: EditorView, destroy: Function, getContent: Function, setContent: Function }}
 */
export function createExpressionEditor(opts) {
  const {
    container,
    content = "",
    mode = "expression",
    editable = true,
    onChange,
    placeholderText = "",
    variables = [],
    extraExtensions = [],
  } = opts;

  // Configure parser for the right top rule, with syntax highlighting tags
  const topRule = mode === "assignments" ? "AssignmentProgram" : "ExpressionProgram";
  const configuredParser = exprParser.configure({
    top: topRule,
    props: [
      styleTags({
        Identifier: tags.variableName,
        Number: tags.number,
        StringLiteral: tags.string,
        Boolean: tags.bool,
        SetOp: tags.operator,
        AddOp: tags.operator,
        SubOp: tags.operator,
        SetIfUnsetOp: tags.operator,
        Eq: tags.compareOperator,
        Neq: tags.compareOperator,
        Gte: tags.compareOperator,
        Lte: tags.compareOperator,
        Gt: tags.compareOperator,
        Lt: tags.compareOperator,
        And: tags.keyword,
        Or: tags.keyword,
        Not: tags.keyword,
        LineComment: tags.lineComment,
        "( )": tags.paren,
      }),
    ],
  });

  const language = LRLanguage.define({
    parser: configuredParser,
    languageData: {
      commentTokens: { line: "//" },
    },
  });

  const languageSupport = new LanguageSupport(language);

  // Debounced onChange
  let debounceTimer = null;
  const debouncedOnChange = onChange
    ? (text) => {
        clearTimeout(debounceTimer);
        debounceTimer = setTimeout(() => onChange(text), 300);
      }
    : null;

  const extensions = [
    languageSupport,
    storyarnEditorTheme,
    storyarnHighlighting,
    history(),
    keymap.of([...defaultKeymap, ...historyKeymap]),
    EditorView.editable.of(editable),
    EditorState.readOnly.of(!editable),
    // Prevent Enter from inserting newlines in single-line expression mode
    ...(mode === "expression"
      ? [
          keymap.of([
            {
              key: "Enter",
              run: () => true, // consume the key, don't insert newline
            },
          ]),
        ]
      : []),
    // Variable autocomplete
    ...(variables.length > 0 ? [variableAutocomplete(variables)] : []),
    // Linting: syntax errors always, undefined variable warnings when variables available
    expressionLinter(mode, variables),
    // Render tooltips in document.body so they aren't clipped by overflow containers
    tooltips({ parent: document.body }),
    ...extraExtensions,
  ];

  if (placeholderText) {
    extensions.push(placeholderExt(placeholderText));
  }

  if (debouncedOnChange) {
    extensions.push(
      EditorView.updateListener.of((update) => {
        if (update.docChanged) {
          debouncedOnChange(update.state.doc.toString());
        }
      }),
    );
  }

  const state = EditorState.create({
    doc: content,
    extensions,
  });

  const view = new EditorView({
    state,
    parent: container,
  });

  return {
    view,
    getContent() {
      return view.state.doc.toString();
    },
    setContent(text) {
      const currentText = view.state.doc.toString();
      if (currentText === text) return;
      view.dispatch({
        changes: { from: 0, to: currentText.length, insert: text },
      });
    },
    destroy() {
      clearTimeout(debounceTimer);
      view.destroy();
    },
  };
}
