/**
 * Vue composable wrapping a CodeMirror 6 editor for Storyarn expressions.
 *
 * Handles lifecycle (mount/destroy), reactivity (disabled, variables),
 * debounced onChange with parse → structured data emission, and formatting.
 */

import { onMounted, onUnmounted, watch, type Ref, toValue } from "vue";
import { EditorView, keymap, placeholder as cmPlaceholder } from "@codemirror/view";
import { EditorState, Compartment } from "@codemirror/state";
import { defaultKeymap, history, historyKeymap } from "@codemirror/commands";
import { lineNumbers } from "@codemirror/view";
import { tooltips } from "@codemirror/view";
import { storyarnLanguage } from "@plugins/expression-editor/parser";
import { storyarnEditorTheme, storyarnHighlighting } from "@plugins/expression-editor/theme";
import { variableAutocomplete } from "@plugins/expression-editor/autocomplete";
import { expressionLinter } from "@plugins/expression-editor/linter";
import { formatExpression } from "@plugins/expression-editor/formatter";
import { parseCondition, parseAssignments } from "@plugins/expression-editor/tree-parser";
import type { ParsedCondition, ParsedAssignment } from "@plugins/expression-editor/tree-parser";
import type { Variable } from "@modules/shared/variables";

export interface CodeEditorOptions {
  mode: Ref<"condition" | "instruction"> | "condition" | "instruction";
  variables: Ref<Variable[]> | Variable[];
  disabled: Ref<boolean> | boolean;
  placeholder?: string;
  onConditionChange?: (condition: ParsedCondition) => void;
  onAssignmentsChange?: (assignments: ParsedAssignment[]) => void;
}

export interface UseCodeEditorReturn {
  setContent: (text: string) => void;
  getContent: () => string;
  format: () => void;
}

const DEBOUNCE_MS = 300;

export function useCodeEditor(
  containerRef: Ref<HTMLElement | null>,
  options: CodeEditorOptions,
): UseCodeEditorReturn {
  let view: EditorView | null = null;
  let debounceTimer: ReturnType<typeof setTimeout> | null = null;

  const editableCompartment = new Compartment();
  const autocompleteCompartment = new Compartment();
  const linterCompartment = new Compartment();

  function getMode(): "condition" | "instruction" {
    return toValue(options.mode);
  }

  function getVariables(): Variable[] {
    return toValue(options.variables);
  }

  function isDisabled(): boolean {
    return toValue(options.disabled);
  }

  function handleChange(text: string): void {
    if (debounceTimer) clearTimeout(debounceTimer);
    debounceTimer = setTimeout(() => {
      const mode = getMode();
      const variables = getVariables();

      if (mode === "instruction") {
        const { assignments, errors } = parseAssignments(text, variables);
        if (errors.length === 0 && options.onAssignmentsChange) {
          options.onAssignmentsChange(assignments);
        }
      } else {
        const { condition, errors } = parseCondition(text, variables);
        if (errors.length === 0 && options.onConditionChange) {
          options.onConditionChange(condition);
        }
      }
    }, DEBOUNCE_MS);
  }

  function createView(container: HTMLElement): void {
    const mode = getMode();
    const variables = getVariables();

    const state = EditorState.create({
      doc: "",
      extensions: [
        lineNumbers(),
        history(),
        keymap.of([...defaultKeymap, ...historyKeymap]),
        storyarnLanguage(mode),
        storyarnEditorTheme,
        storyarnHighlighting,
        autocompleteCompartment.of(variableAutocomplete(variables)),
        linterCompartment.of(expressionLinter(mode, variables)),
        editableCompartment.of(EditorView.editable.of(!isDisabled())),
        tooltips({ parent: document.body }),
        EditorView.updateListener.of((update) => {
          if (update.docChanged) {
            handleChange(update.state.doc.toString());
          }
        }),
        ...(options.placeholder ? [cmPlaceholder(options.placeholder)] : []),
      ],
    });

    view = new EditorView({ state, parent: container });
  }

  onMounted(() => {
    const container = containerRef.value;
    if (container) createView(container);
  });

  onUnmounted(() => {
    if (debounceTimer) clearTimeout(debounceTimer);
    view?.destroy();
    view = null;
  });

  // React to disabled changes
  watch(
    () => isDisabled(),
    (disabled) => {
      view?.dispatch({
        effects: editableCompartment.reconfigure(EditorView.editable.of(!disabled)),
      });
    },
  );

  // React to variable changes
  watch(
    () => getVariables(),
    (variables) => {
      if (!view) return;
      const mode = getMode();
      view.dispatch({
        effects: [
          autocompleteCompartment.reconfigure(variableAutocomplete(variables)),
          linterCompartment.reconfigure(expressionLinter(mode, variables)),
        ],
      });
    },
  );

  function setContent(text: string): void {
    if (!view) return;
    view.dispatch({
      changes: { from: 0, to: view.state.doc.length, insert: text },
    });
  }

  function getContent(): string {
    return view?.state.doc.toString() ?? "";
  }

  function format(): void {
    if (!view) return;
    const text = view.state.doc.toString();
    const formatted = formatExpression(text, getMode());
    if (formatted !== text) {
      setContent(formatted);
    }
  }

  return { setContent, getContent, format };
}
