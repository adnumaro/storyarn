/**
 * TipTap Mention Extension — # trigger for referencing sheets/flows.
 * Uses VueRenderer for popup rendering.
 */

import Mention from "@tiptap/extension-mention";
import { VueRenderer } from "@tiptap/vue-3";
import type { SuggestionProps, SuggestionKeyDownProps } from "@tiptap/suggestion";
import type { Node } from "@tiptap/core";
import type { MentionOptions } from "@tiptap/extension-mention";
import MentionList from "./MentionList.vue";

import type { LiveInterface } from "@composables/useLive";

interface MentionItem {
  id: string | number;
  name?: string;
  label?: string;
  ref?: string;
  [key: string]: string | number | boolean | undefined;
}

type PushEventFn = LiveInterface["pushEvent"];
type PushEventToFn = (target: string, event: string, payload: Record<string, unknown>) => void;

interface MentionExtensionOptions {
  pushEvent: PushEventFn;
  pushEventTo?: PushEventToFn;
  phxTarget?: string;
}

interface MentionExtensionReturn {
  extension: Node<MentionOptions>;
  resolveMentions: (items: MentionItem[]) => void;
}

type MentionResolve = ((items: MentionItem[]) => void) | null;

function escapeAttr(str: string | undefined | null): string {
  return (str || "")
    .replace(/&/g, "&amp;")
    .replace(/"/g, "&quot;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;");
}

export function createMentionExtension(
  { pushEvent, pushEventTo, phxTarget }: MentionExtensionOptions = {} as MentionExtensionOptions,
): MentionExtensionReturn {
  let mentionDebounce: ReturnType<typeof setTimeout> | null = null;
  let mentionResolve: MentionResolve = null;

  return {
    extension: Mention.extend({
      renderHTML({ node }) {
        return [
          "span",
          {
            class: "mention",
            "data-type": escapeAttr(node.attrs.type || "sheet"),
            "data-id": escapeAttr(node.attrs.id),
            "data-label": escapeAttr(node.attrs.label),
            contenteditable: "false",
          },
          `#${escapeAttr(node.attrs.label || "")}`,
        ];
      },

      parseHTML() {
        return [
          {
            tag: "span.mention",
            getAttrs: (dom) => ({
              id: (dom as HTMLElement).getAttribute("data-id"),
              label: (dom as HTMLElement).getAttribute("data-label"),
              type: (dom as HTMLElement).getAttribute("data-type"),
            }),
          },
        ];
      },
    }).configure({
      HTMLAttributes: { class: "mention" },
      suggestion: {
        char: "#",
        allowSpaces: false,

        command: ({ editor, range, props }) => {
          const item = props as MentionItem;
          const $from = editor.state.doc.resolve(range.from);
          const blockNode = $from.parent;

          if (blockNode.type.name === "character") {
            const blockStart = $from.start();
            const blockEnd = $from.end();
            const blockPos = $from.before();

            editor
              .chain()
              .focus()
              .command(({ tr, dispatch }) => {
                if (dispatch) {
                  const nameText = editor.schema.text(
                    (item.name || item.label || "").toUpperCase(),
                  );
                  tr.replaceWith(blockStart, blockEnd, nameText);
                  tr.setNodeMarkup(blockPos, undefined, {
                    ...blockNode.attrs,
                    sheetId: String(item.id),
                  });
                }
                return true;
              })
              .run();

            const elementId = blockNode.attrs.elementId;
            if (elementId) {
              pushEvent("set_character_sheet", {
                id: String(elementId),
                sheet_id: String(item.id),
              });
            }
            return;
          }

          editor
            .chain()
            .focus()
            .deleteRange(range)
            .insertContent([
              {
                type: "mention",
                attrs: { id: item.id, label: item.label || item.name },
              },
              { type: "text", text: " " },
            ])
            .run();
        },

        items: ({ query }: { query: string }) => {
          return new Promise<MentionItem[]>((resolve) => {
            if (mentionDebounce) clearTimeout(mentionDebounce);
            if (mentionResolve) mentionResolve([]);

            const wrappedResolve = (serverItems: MentionItem[]): void => {
              resolve(
                (serverItems || []).map((item) => ({
                  ...item,
                  label: item.label || item.name,
                })),
              );
            };
            mentionResolve = wrappedResolve;

            mentionDebounce = setTimeout(() => {
              const push =
                phxTarget && pushEventTo
                  ? (ev: string, payload: Record<string, unknown>) => pushEventTo(phxTarget, ev, payload)
                  : pushEvent;
              push("mention_suggestions", { query });

              setTimeout(() => {
                if (mentionResolve === wrappedResolve) {
                  mentionResolve = null;
                  resolve([]);
                }
              }, 2000);
            }, 300);
          });
        },

        render: () => {
          let component: VueRenderer | undefined;

          return {
            onStart(props: SuggestionProps<MentionItem>) {
              component = new VueRenderer(MentionList, {
                props,
                editor: props.editor,
              });
              if (!props.clientRect) return;
              const rect = props.clientRect();
              if (!rect) return;
              (component.element as HTMLElement).style.cssText = `position:absolute;left:${rect.left}px;top:${rect.bottom + 8}px;z-index:50;`;
              document.body.appendChild(component.element!);
            },
            onUpdate(props: SuggestionProps<MentionItem>) {
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

    /** Call when server responds with mention suggestions */
    resolveMentions(items: MentionItem[]): void {
      if (mentionResolve) {
        mentionResolve(items);
        mentionResolve = null;
      }
    },
  };
}
