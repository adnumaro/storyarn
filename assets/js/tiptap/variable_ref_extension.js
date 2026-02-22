/**
 * TipTap Variable Reference Extension - $ trigger for inserting variable refs.
 * Fetches suggestions from the server via LiveView events.
 *
 * Follows the same pattern as mention_extension.js (#-trigger for sheets/flows).
 */

import Mention from "@tiptap/extension-mention";
import { Calendar, Hash, List, ToggleLeft, Type } from "lucide";
import { createIconHTML } from "../flow_canvas/node_config.js";
import { escapeAttr, escapeHtml, positionPopup } from "../screenplay/utils.js";

// Pre-create icon HTML strings by block type
const TYPE_ICONS = {
  number: createIconHTML(Hash, { size: 14 }),
  text: createIconHTML(Type, { size: 14 }),
  rich_text: createIconHTML(Type, { size: 14 }),
  boolean: createIconHTML(ToggleLeft, { size: 14 }),
  select: createIconHTML(List, { size: 14 }),
  multi_select: createIconHTML(List, { size: 14 }),
  date: createIconHTML(Calendar, { size: 14 }),
};

const DEFAULT_ICON = createIconHTML(Hash, { size: 14 });

function getTypeIcon(blockType) {
  return TYPE_ICONS[blockType] || DEFAULT_ICON;
}

/**
 * Update popup content with current items and selection.
 */
function updatePopup(popup, items, selectedIndex, props) {
  if (!popup) return;

  if (items.length === 0) {
    popup.innerHTML = `
      <div class="text-base-content/50 text-sm px-3 py-2">
        No variables found
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
        <span class="flex-shrink-0 size-5 rounded flex items-center justify-center text-xs bg-info/20 text-info">
          ${getTypeIcon(item.block_type)}
        </span>
        <span class="truncate">${escapeHtml(item.ref)}</span>
        <span class="text-base-content/40 text-xs ml-auto">${escapeHtml(item.block_type)}</span>
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
 * Creates a variable reference extension with $ as trigger character.
 *
 * Accepts either:
 * - A hook directly: createVariableRefExtension(hook)
 * - An options object: createVariableRefExtension({ liveViewHook: hook })
 */
export function createVariableRefExtension(hookOrOptions) {
  const hook = hookOrOptions?.liveViewHook || hookOrOptions;

  return Mention.extend({ name: "variableRef" }).configure({
    HTMLAttributes: {
      class: "variable-ref",
    },
    suggestion: {
      char: "$",
      allowSpaces: false,

      command: ({ editor, range, props: item }) => {
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

      items: async ({ query }) => {
        return new Promise((resolve) => {
          if (hook.variableDebounce) {
            clearTimeout(hook.variableDebounce);
          }
          if (hook.variableResolve) {
            hook.variableResolve([]);
          }

          const wrappedResolve = (serverItems) => {
            resolve(
              (serverItems || []).map((item) => ({
                ...item,
                label: item.ref,
              })),
            );
          };
          hook.variableResolve = wrappedResolve;

          hook.variableDebounce = setTimeout(() => {
            const target = hook.el.dataset.phxTarget;
            if (target) {
              hook.pushEventTo(target, "variable_suggestions", { query });
            } else {
              hook.pushEvent("variable_suggestions", { query });
            }

            setTimeout(() => {
              if (hook.variableResolve === wrappedResolve) {
                hook.variableResolve = null;
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
              "variable-ref-popup bg-base-100 border border-base-300 rounded-lg shadow-lg p-1 max-h-60 overflow-y-auto z-50";
            popup.style.position = "absolute";

            updatePopup(popup, items, selectedIndex, { command: commandFn });
            document.body.appendChild(popup);
            positionPopup(popup, props, {
              offsetY: 8,
              minWidth: "220px",
              maxWidth: "360px",
            });
          },

          onUpdate: (props) => {
            items = props.items;
            commandFn = props.command;
            selectedIndex = 0;
            updatePopup(popup, items, selectedIndex, { command: commandFn });
            positionPopup(popup, props, {
              offsetY: 8,
              minWidth: "220px",
              maxWidth: "360px",
            });
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
          class: "variable-ref",
          "data-ref": escapeAttr(attrs.id || ""),
          "data-block-type": escapeAttr(attrs.blockType || "text"),
          contenteditable: "false",
        },
        `$${escapeAttr(attrs.id || "")}`,
      ];
    },

    parseHTML() {
      return [
        {
          tag: "span.variable-ref",
          getAttrs: (dom) => ({
            id: dom.getAttribute("data-ref"),
            label: dom.getAttribute("data-ref"),
            blockType: dom.getAttribute("data-block-type"),
          }),
        },
      ];
    },
  });
}
