import { Editor } from "@tiptap/core";
import StarterKit from "@tiptap/starter-kit";

export const TiptapEditor = {
  mounted() {
    const content = this.el.dataset.content || "";
    const editable = this.el.dataset.editable === "true";
    const blockId = this.el.dataset.blockId;

    // Create editor container
    const editorEl = document.createElement("div");
    editorEl.className = "tiptap-content prose prose-sm max-w-none";
    this.el.appendChild(editorEl);

    this.editor = new Editor({
      element: editorEl,
      extensions: [StarterKit],
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
          const html = editor.getHTML();
          this.pushEvent("update_rich_text", {
            id: blockId,
            content: html,
          });
        }, 500);
      },
      onBlur: ({ editor }) => {
        // Save immediately on blur
        if (this.updateTimeout) {
          clearTimeout(this.updateTimeout);
        }
        const html = editor.getHTML();
        this.pushEvent("update_rich_text", {
          id: blockId,
          content: html,
        });
      },
    });

    // Create toolbar if editable
    if (editable) {
      this.createToolbar();
    }
  },

  createToolbar() {
    const toolbar = document.createElement("div");
    toolbar.className =
      "tiptap-toolbar flex items-center gap-1 mb-2 p-1";

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
        action: () =>
          this.editor.chain().focus().toggleHeading({ level: 1 }).run(),
        isActive: () => this.editor.isActive("heading", { level: 1 }),
      },
      {
        icon: "H2",
        title: "Heading 2",
        action: () =>
          this.editor.chain().focus().toggleHeading({ level: 2 }).run(),
        isActive: () => this.editor.isActive("heading", { level: 2 }),
      },
      {
        icon: "H3",
        title: "Heading 3",
        action: () =>
          this.editor.chain().focus().toggleHeading({ level: 3 }).run(),
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

    buttons.forEach((btn) => {
      if (btn.type === "divider") {
        const divider = document.createElement("div");
        divider.className = "w-px h-5 bg-base-300";
        toolbar.appendChild(divider);
      } else {
        const button = document.createElement("button");
        button.type = "button";
        button.className =
          "btn btn-ghost btn-xs font-mono text-xs px-2 min-h-0 h-7";
        button.title = btn.title;
        button.textContent = btn.icon;
        button.addEventListener("click", (e) => {
          e.preventDefault();
          btn.action();
          this.updateToolbarState(buttons, toolbar);
        });
        toolbar.appendChild(button);
      }
    });

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
    toolbar.childNodes.forEach((node) => {
      if (node.tagName === "BUTTON") {
        const btn = buttons[buttonIndex];
        while (buttons[buttonIndex]?.type === "divider") {
          buttonIndex++;
        }
        if (buttons[buttonIndex] && buttons[buttonIndex].isActive) {
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
    });
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
