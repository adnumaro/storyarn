import { Editor } from "@tiptap/core";
import Mention from "@tiptap/extension-mention";
import StarterKit from "@tiptap/starter-kit";

/**
 * Escape HTML attribute values to prevent XSS.
 * Used for data attributes in rendered mention nodes.
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
 * Creates a custom mention extension with # as trigger character.
 * Fetches suggestions from the server via LiveView events.
 */
function createMentionExtension(hook) {
  return Mention.configure({
    HTMLAttributes: {
      class: "mention",
    },
    suggestion: {
      char: "#",
      allowSpaces: false,
      // Fetch suggestions from server
      items: async ({ query }) => {
        return new Promise((resolve) => {
          // Store the resolve function to be called when server responds
          hook.mentionResolve = resolve;
          hook.pushEvent("mention_suggestions", { query });

          // Timeout after 2 seconds
          setTimeout(() => {
            if (hook.mentionResolve === resolve) {
              hook.mentionResolve = null;
              resolve([]);
            }
          }, 2000);
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
    // Custom rendering for the mention node
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
    // Parse mentions from existing HTML
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

  // Add click handlers
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
 * Escape HTML to prevent XSS.
 */
function escapeHtml(text) {
  const div = document.createElement("div");
  div.textContent = text;
  return div.innerHTML;
}

export const TiptapEditor = {
  mounted() {
    const content = this.el.dataset.content || "";
    const editable = this.el.dataset.editable === "true";
    const blockId = this.el.dataset.blockId;
    const nodeId = this.el.dataset.nodeId;

    // Create editor container
    const editorEl = document.createElement("div");
    editorEl.className = "tiptap-content prose prose-sm max-w-none";
    this.el.appendChild(editorEl);

    // Determine which event to push based on whether this is a block or node editor
    const pushUpdate = (html) => {
      if (nodeId) {
        this.pushEvent("update_node_text", { id: nodeId, content: html });
      } else if (blockId) {
        this.pushEvent("update_rich_text", { id: blockId, content: html });
      }
    };

    // Listen for mention suggestions from server
    this.handleEvent("mention_suggestions_result", ({ items }) => {
      if (this.mentionResolve) {
        this.mentionResolve(items);
        this.mentionResolve = null;
      }
    });

    this.editor = new Editor({
      element: editorEl,
      extensions: [StarterKit, createMentionExtension(this)],
      content: content,
      editable: editable,
      editorProps: {
        attributes: {
          class: "", // Styles handled by CSS .tiptap-content .ProseMirror
        },
      },
      onUpdate: ({ editor }) => {
        // Debounce updates to avoid too many server calls
        if (this.updateTimeout) {
          clearTimeout(this.updateTimeout);
        }
        this.updateTimeout = setTimeout(() => {
          pushUpdate(editor.getHTML());
        }, 500);
      },
      onBlur: ({ editor }) => {
        // Save immediately on blur
        if (this.updateTimeout) {
          clearTimeout(this.updateTimeout);
        }
        pushUpdate(editor.getHTML());
      },
    });

    // Create toolbar if editable
    if (editable) {
      this.createToolbar();
    }
  },

  createToolbar() {
    const toolbar = document.createElement("div");
    toolbar.className = "tiptap-toolbar flex items-center gap-1 mb-2 p-1";

    const buttons = [
      {
        icon: "B",
        title: "Bold",
        action: () => this.editor.chain().focus().toggleBold().run(),
        isActive: () => this.editor.isActive("bold"),
      },
      {
        icon: "I",
        title: "Italic",
        action: () => this.editor.chain().focus().toggleItalic().run(),
        isActive: () => this.editor.isActive("italic"),
      },
      {
        icon: "S",
        title: "Strike",
        action: () => this.editor.chain().focus().toggleStrike().run(),
        isActive: () => this.editor.isActive("strike"),
      },
      { type: "divider" },
      {
        icon: "H1",
        title: "Heading 1",
        action: () => this.editor.chain().focus().toggleHeading({ level: 1 }).run(),
        isActive: () => this.editor.isActive("heading", { level: 1 }),
      },
      {
        icon: "H2",
        title: "Heading 2",
        action: () => this.editor.chain().focus().toggleHeading({ level: 2 }).run(),
        isActive: () => this.editor.isActive("heading", { level: 2 }),
      },
      {
        icon: "H3",
        title: "Heading 3",
        action: () => this.editor.chain().focus().toggleHeading({ level: 3 }).run(),
        isActive: () => this.editor.isActive("heading", { level: 3 }),
      },
      { type: "divider" },
      {
        icon: "UL",
        title: "Bullet List",
        action: () => this.editor.chain().focus().toggleBulletList().run(),
        isActive: () => this.editor.isActive("bulletList"),
      },
      {
        icon: "OL",
        title: "Ordered List",
        action: () => this.editor.chain().focus().toggleOrderedList().run(),
        isActive: () => this.editor.isActive("orderedList"),
      },
      { type: "divider" },
      {
        icon: "Q",
        title: "Blockquote",
        action: () => this.editor.chain().focus().toggleBlockquote().run(),
        isActive: () => this.editor.isActive("blockquote"),
      },
      {
        icon: "—",
        title: "Horizontal Rule",
        action: () => this.editor.chain().focus().setHorizontalRule().run(),
        isActive: () => false,
      },
    ];

    for (const btn of buttons) {
      if (btn.type === "divider") {
        const divider = document.createElement("div");
        divider.className = "w-px h-5 bg-base-300";
        toolbar.appendChild(divider);
      } else {
        const button = document.createElement("button");
        button.type = "button";
        button.className = "btn btn-ghost btn-xs font-mono text-xs px-2 min-h-0 h-7";
        button.title = btn.title;
        button.textContent = btn.icon;
        button.addEventListener("click", (e) => {
          e.preventDefault();
          btn.action();
          this.updateToolbarState(buttons, toolbar);
        });
        toolbar.appendChild(button);
      }
    }

    // Insert toolbar before editor
    this.el.insertBefore(toolbar, this.el.firstChild);
    this.toolbar = toolbar;
    this.toolbarButtons = buttons;

    // Update toolbar state on selection change
    this.editor.on("selectionUpdate", () => {
      this.updateToolbarState(buttons, toolbar);
    });
    this.editor.on("transaction", () => {
      this.updateToolbarState(buttons, toolbar);
    });
  },

  updateToolbarState(buttons, toolbar) {
    let buttonIndex = 0;
    for (const node of toolbar.childNodes) {
      if (node.tagName === "BUTTON") {
        while (buttons[buttonIndex]?.type === "divider") {
          buttonIndex++;
        }
        if (buttons[buttonIndex]?.isActive) {
          if (buttons[buttonIndex].isActive()) {
            node.classList.add("btn-active");
          } else {
            node.classList.remove("btn-active");
          }
        }
        buttonIndex++;
      } else {
        buttonIndex++;
      }
    }
  },

  updated() {
    // Handle content updates from server if needed
    const newContent = this.el.dataset.content;
    if (newContent && this.editor && !this.editor.isFocused) {
      const currentContent = this.editor.getHTML();
      if (currentContent !== newContent) {
        this.editor.commands.setContent(newContent, false);
      }
    }
  },

  destroyed() {
    if (this.updateTimeout) {
      clearTimeout(this.updateTimeout);
    }
    if (this.editor) {
      this.editor.destroy();
    }
  },
};
