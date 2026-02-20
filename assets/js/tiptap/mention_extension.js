/**
 * TipTap Mention Extension - # trigger character for referencing sheets/flows.
 * Fetches suggestions from the server via LiveView events.
 */

import Mention from "@tiptap/extension-mention";
import { FileText, Zap } from "lucide";
import { createIconHTML } from "../flow_canvas/node_config.js";
import { escapeAttr, escapeHtml, positionPopup } from "../screenplay/utils.js";

// Pre-create icon HTML strings for mention popup
const SHEET_ICON_SM = createIconHTML(FileText, { size: 14 });
const FLOW_ICON_SM = createIconHTML(Zap, { size: 14 });

/**
 * Update popup content with current items and selection.
 */
function updatePopup(popup, items, selectedIndex, props) {
  if (!popup) return;

  if (items.length === 0) {
    popup.innerHTML = `
      <div class="text-base-content/50 text-sm px-3 py-2">
        No results found
      </div>
    `;
    return;
  }

  popup.innerHTML = items
    .map(
      (item, index) => `
      <button
        type="button"
        class="w-full text-left px-2 py-1.5 rounded flex items-center gap-2 text-sm ${
          index === selectedIndex ? "bg-primary/20" : "hover:bg-base-200"
        }"
        data-index="${index}"
      >
        <span class="flex-shrink-0 size-5 rounded flex items-center justify-center text-xs ${
          item.type === "sheet" ? "bg-primary/20 text-primary" : "bg-secondary/20 text-secondary"
        }">
          ${item.type === "sheet" ? SHEET_ICON_SM : FLOW_ICON_SM}
        </span>
        <span class="truncate">${escapeHtml(item.name)}</span>
        ${item.shortcut ? `<span class="text-base-content/50 text-xs ml-auto">#${escapeHtml(item.shortcut)}</span>` : ""}
      </button>
    `,
    )
    .join("");

  for (const button of popup.querySelectorAll("button")) {
    button.addEventListener("click", () => {
      const index = Number.parseInt(button.dataset.index, 10);
      if (items[index]) {
        props.command(items[index]);
      }
    });
  }
}

/**
 * Creates a custom mention extension with # as trigger character.
 *
 * Accepts either:
 * - A hook directly: createMentionExtension(hook)
 * - An options object: createMentionExtension({ liveViewHook: hook })
 */
export function createMentionExtension(hookOrOptions) {
  const hook = hookOrOptions?.liveViewHook || hookOrOptions;
  return Mention.configure({
    HTMLAttributes: {
      class: "mention",
    },
    suggestion: {
      char: "#",
      allowSpaces: false,

      command: ({ editor, range, props: item }) => {
        const $from = editor.state.doc.resolve(range.from);
        const blockNode = $from.parent;

        // CHARACTER block: set sheet reference instead of inserting inline mention
        if (blockNode.type.name === "character") {
          const blockStart = $from.start();
          const blockEnd = $from.end();
          const blockPos = $from.before();

          editor
            .chain()
            .focus()
            .command(({ tr, dispatch }) => {
              if (dispatch) {
                // Replace entire block content with uppercase sheet name
                const nameText = editor.schema.text((item.name || item.label || "").toUpperCase());
                tr.replaceWith(blockStart, blockEnd, nameText);

                // Set sheetId attribute on the CHARACTER block node
                tr.setNodeMarkup(blockPos, undefined, {
                  ...blockNode.attrs,
                  sheetId: String(item.id),
                });
              }
              return true;
            })
            .run();

          // Persist immediately to server — don't rely on debounced sync
          // (if the user navigates away quickly, the debounce may be canceled)
          const elementId = blockNode.attrs.elementId;
          if (elementId && hook) {
            hook.pushEvent("set_character_sheet", {
              id: String(elementId),
              sheet_id: String(item.id),
            });
          }
          return;
        }

        // Default: insert inline mention node
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

      items: async ({ query }) => {
        return new Promise((resolve) => {
          if (hook.mentionDebounce) {
            clearTimeout(hook.mentionDebounce);
          }
          if (hook.mentionResolve) {
            hook.mentionResolve([]);
          }

          const wrappedResolve = (serverItems) => {
            resolve(
              (serverItems || []).map((item) => ({
                ...item,
                label: item.label || item.name,
              })),
            );
          };
          hook.mentionResolve = wrappedResolve;

          hook.mentionDebounce = setTimeout(() => {
            const target = hook.el.dataset.phxTarget;
            if (target) {
              hook.pushEventTo(target, "mention_suggestions", { query });
            } else {
              hook.pushEvent("mention_suggestions", { query });
            }

            setTimeout(() => {
              if (hook.mentionResolve === wrappedResolve) {
                hook.mentionResolve = null;
                resolve([]);
              }
            }, 2000);
          }, 300);
        });
      },
      render: () => {
        let popup;
        let selectedIndex = 0;
        let items = [];
        let commandFn = null;

        return {
          onStart: (props) => {
            items = props.items;
            commandFn = props.command;
            selectedIndex = 0;

            popup = document.createElement("div");
            popup.className =
              "mention-popup bg-base-100 border border-base-300 rounded-lg shadow-lg p-1 max-h-60 overflow-y-auto z-50";
            popup.style.position = "absolute";

            updatePopup(popup, items, selectedIndex, { command: commandFn });
            document.body.appendChild(popup);
            positionPopup(popup, props, { offsetY: 8, minWidth: "200px", maxWidth: "300px" });
          },

          onUpdate: (props) => {
            items = props.items;
            commandFn = props.command;
            selectedIndex = 0;
            updatePopup(popup, items, selectedIndex, { command: commandFn });
            positionPopup(popup, props, { offsetY: 8, minWidth: "200px", maxWidth: "300px" });
          },

          onKeyDown: ({ event }) => {
            if (event.key === "ArrowUp") {
              selectedIndex = (selectedIndex - 1 + items.length) % items.length;
              updatePopup(popup, items, selectedIndex, { command: commandFn });
              return true;
            }

            if (event.key === "ArrowDown") {
              selectedIndex = (selectedIndex + 1) % items.length;
              updatePopup(popup, items, selectedIndex, { command: commandFn });
              return true;
            }

            if (event.key === "Enter") {
              if (items[selectedIndex] && commandFn) {
                commandFn(items[selectedIndex]);
              }
              return true;
            }

            if (event.key === "Escape") {
              popup?.remove();
              return true;
            }

            return false;
          },

          onExit: () => {
            popup?.remove();
          },
        };
      },
    },
    renderHTML({ node }) {
      const attrs = node.attrs;
      return [
        "span",
        {
          class: "mention",
          "data-type": escapeAttr(attrs.type || "sheet"),
          "data-id": escapeAttr(attrs.id),
          "data-label": escapeAttr(attrs.label),
          contenteditable: "false",
        },
        `#${escapeAttr(attrs.label || "")}`,
      ];
    },
    parseHTML() {
      return [
        {
          tag: "span.mention",
          getAttrs: (dom) => ({
            id: dom.getAttribute("data-id"),
            label: dom.getAttribute("data-label"),
            type: dom.getAttribute("data-type"),
          }),
        },
      ];
    },
  });
}
