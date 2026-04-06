/**
 * TipTap Variable Reference Extension — $ trigger for variable refs.
 * Uses VueRenderer for popup rendering.
 */

import Mention from "@tiptap/extension-mention";
import { VueRenderer } from "@tiptap/vue-3";
import type { SuggestionProps, SuggestionKeyDownProps } from "@tiptap/suggestion";
import type { Node } from "@tiptap/core";
import type { MentionOptions } from "@tiptap/extension-mention";
import VariableList from "./VariableList.vue";

interface VariableItem {
  id?: string | number;
  ref: string;
  name?: string;
  label?: string;
  block_type?: string;
  [key: string]: unknown;
}

type PushEventFn = (event: string, payload: Record<string, unknown>) => void;
type PushEventToFn = (target: string, event: string, payload: Record<string, unknown>) => void;

interface VariableRefExtensionOptions {
  pushEvent: PushEventFn;
  pushEventTo?: PushEventToFn;
  phxTarget?: string;
}

interface VariableRefExtensionReturn {
  extension: Node<MentionOptions>;
  resolveVariables: (items: VariableItem[]) => void;
}

type VariableResolve = ((items: VariableItem[]) => void) | null;

function escapeAttr(str: string | undefined | null): string {
  return (str || "")
    .replace(/&/g, "&amp;")
    .replace(/"/g, "&quot;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;");
}

export function createVariableRefExtension(
  { pushEvent, pushEventTo, phxTarget }: VariableRefExtensionOptions = {} as VariableRefExtensionOptions,
): VariableRefExtensionReturn {
  let variableDebounce: ReturnType<typeof setTimeout> | null = null;
  let variableResolve: VariableResolve = null;

  return {
    extension: Mention.extend({
      name: "variableRef",

      renderHTML({ node }) {
        return [
          "span",
          {
            class: "variable-ref",
            "data-ref": escapeAttr(node.attrs.id || ""),
            "data-block-type": escapeAttr(node.attrs.blockType || "text"),
            contenteditable: "false",
          },
          `$${escapeAttr(node.attrs.id || "")}`,
        ];
      },

      parseHTML() {
        return [
          {
            tag: "span.variable-ref",
            getAttrs: (dom) => ({
              id: (dom as HTMLElement).getAttribute("data-ref"),
              label: (dom as HTMLElement).getAttribute("data-ref"),
              blockType: (dom as HTMLElement).getAttribute("data-block-type"),
            }),
          },
        ];
      },
    }).configure({
      HTMLAttributes: { class: "variable-ref" },
      suggestion: {
        char: "$",
        allowSpaces: false,

        command: ({ editor, range, props }) => {
          const item = props as unknown as VariableItem;
          editor
            .chain()
            .focus()
            .deleteRange(range)
            .insertContent([
              {
                type: "variableRef",
                attrs: {
                  id: item.ref,
                  label: item.ref,
                  blockType: item.block_type,
                },
              },
              { type: "text", text: " " },
            ])
            .run();
        },

        items: ({ query }: { query: string }) => {
          return new Promise<VariableItem[]>((resolve) => {
            if (variableDebounce) clearTimeout(variableDebounce);
            if (variableResolve) variableResolve([]);

            const wrappedResolve = (serverItems: VariableItem[]): void => {
              resolve(
                (serverItems || []).map((item) => ({
                  ...item,
                  label: item.ref,
                })),
              );
            };
            variableResolve = wrappedResolve;

            variableDebounce = setTimeout(() => {
              const push: PushEventFn =
                phxTarget && pushEventTo
                  ? (ev: string, payload: Record<string, unknown>) => pushEventTo(phxTarget, ev, payload)
                  : pushEvent;
              push("variable_suggestions", { query });

              setTimeout(() => {
                if (variableResolve === wrappedResolve) {
                  variableResolve = null;
                  resolve([]);
                }
              }, 2000);
            }, 300);
          });
        },

        render: () => {
          let component: VueRenderer | undefined;

          return {
            onStart(props: SuggestionProps<VariableItem>) {
              component = new VueRenderer(VariableList, {
                props,
                editor: props.editor,
              });
              if (!props.clientRect) return;
              const rect = props.clientRect();
              if (!rect) return;
              (component.element as HTMLElement).style.cssText = `position:absolute;left:${rect.left}px;top:${rect.bottom + 8}px;z-index:50;`;
              document.body.appendChild(component.element!);
            },
            onUpdate(props: SuggestionProps<VariableItem>) {
              component?.updateProps(props);
              if (!props.clientRect) return;
              const rect = props.clientRect();
              if (rect && component?.element) {
                (component.element as HTMLElement).style.left = `${rect.left}px`;
                (component.element as HTMLElement).style.top = `${rect.bottom + 8}px`;
              }
            },
            onKeyDown(props: SuggestionKeyDownProps) {
              if (props.event.key === "Escape") {
                component?.destroy();
                return true;
              }
              return component?.ref?.onKeyDown(props) || false;
            },
            onExit() {
              component?.destroy();
            },
          };
        },
      },

    }),

    /** Call when server responds with variable suggestions */
    resolveVariables(items: VariableItem[]): void {
      if (variableResolve) {
        variableResolve(items);
        variableResolve = null;
      }
    },
  };
}
