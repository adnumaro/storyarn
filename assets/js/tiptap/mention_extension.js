/**
 * TipTap Mention Extension - # trigger character for referencing pages/flows.
 * Fetches suggestions from the server via LiveView events.
 */

import Mention from "@tiptap/extension-mention";

/**
 * Escape HTML attribute values to prevent XSS.
 */
function escapeAttr(str) {
  if (str == null) return "";
  return String(str)
    .replace(/&/g, "&amp;")
    .replace(/"/g, "&quot;")
    .replace(/'/g, "&#39;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;");
}

/**
 * Escape HTML to prevent XSS.
 */
function escapeHtml(text) {
  const div = document.createElement("div");
  div.textContent = text;
  return div.innerHTML;
}

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
          item.type === "page" ? "bg-primary/20 text-primary" : "bg-secondary/20 text-secondary"
        }">
          ${
            item.type === "page"
              ? '<svg class="size-3.5" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 12h6m-6 4h6m2 5H7a2 2 0 01-2-2V5a2 2 0 012-2h5.586a1 1 0 01.707.293l5.414 5.414a1 1 0 01.293.707V19a2 2 0 01-2 2z"></path></svg>'
              : '<svg class="size-3.5" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M13 10V3L4 14h7v7l9-11h-7z"></path></svg>'
          }
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
 * Position popup near the cursor.
 */
function positionPopup(popup, props) {
  if (!popup || !props.clientRect) return;

  const rect = props.clientRect();
  if (!rect) return;

  popup.style.left = `${rect.left}px`;
  popup.style.top = `${rect.bottom + 8}px`;
  popup.style.minWidth = "200px";
  popup.style.maxWidth = "300px";
}

/**
 * Creates a custom mention extension with # as trigger character.
 */
export function createMentionExtension(hook) {
  return Mention.configure({
    HTMLAttributes: {
      class: "mention",
    },
    suggestion: {
      char: "#",
      allowSpaces: false,
      items: async ({ query }) => {
        return new Promise((resolve) => {
          if (hook.mentionDebounce) {
            clearTimeout(hook.mentionDebounce);
          }
          if (hook.mentionResolve) {
            hook.mentionResolve([]);
          }

          hook.mentionResolve = resolve;

          hook.mentionDebounce = setTimeout(() => {
            const target = hook.el.dataset.phxTarget;
            if (target) {
              hook.pushEventTo(target, "mention_suggestions", { query });
            } else {
              hook.pushEvent("mention_suggestions", { query });
            }

            setTimeout(() => {
              if (hook.mentionResolve === resolve) {
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

        return {
          onStart: (props) => {
            items = props.items;
            selectedIndex = 0;

            popup = document.createElement("div");
            popup.className =
              "mention-popup bg-base-100 border border-base-300 rounded-lg shadow-lg p-1 max-h-60 overflow-y-auto z-50";
            popup.style.position = "absolute";

            updatePopup(popup, items, selectedIndex, props);
            document.body.appendChild(popup);
            positionPopup(popup, props);
          },

          onUpdate: (props) => {
            items = props.items;
            selectedIndex = 0;
            updatePopup(popup, items, selectedIndex, props);
            positionPopup(popup, props);
          },

          onKeyDown: (props) => {
            if (props.event.key === "ArrowUp") {
              selectedIndex = (selectedIndex - 1 + items.length) % items.length;
              updatePopup(popup, items, selectedIndex, props);
              return true;
            }

            if (props.event.key === "ArrowDown") {
              selectedIndex = (selectedIndex + 1) % items.length;
              updatePopup(popup, items, selectedIndex, props);
              return true;
            }

            if (props.event.key === "Enter") {
              if (items[selectedIndex]) {
                props.command(items[selectedIndex]);
              }
              return true;
            }

            if (props.event.key === "Escape") {
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
          class:
            "mention inline-flex items-center gap-1 px-1.5 py-0.5 rounded bg-primary/20 text-primary font-medium cursor-pointer hover:bg-primary/30",
          "data-type": escapeAttr(attrs.type || "page"),
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
