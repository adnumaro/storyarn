import { Editor } from "@tiptap/core";
import StarterKit from "@tiptap/starter-kit";
import { createMentionExtension } from "../tiptap/mention_extension.js";
import { createVariableRefExtension } from "../tiptap/variable_ref_extension.js";

export const TiptapEditor = {
  mounted() {
    const content = this.el.dataset.content || "";
    const editable = this.el.dataset.editable === "true";
    const blockId = this.el.dataset.blockId;
    const nodeId = this.el.dataset.nodeId;
    const mode = this.el.dataset.mode || "default"; // "default" or "screenplay"
    const variablesEnabled = this.el.dataset.variablesEnabled === "true";

    // Create editor container
    const editorEl = document.createElement("div");
    const classMap = {
      screenplay: "tiptap-content tiptap-screenplay prose prose-lg max-w-none",
      "dialogue-screenplay": "tiptap-content tiptap-dialogue-screenplay",
    };
    editorEl.className = classMap[mode] || "tiptap-content prose prose-sm max-w-none";
    this.el.appendChild(editorEl);

    // Determine which event to push based on whether this is a block or node editor
    const target = this.el.dataset.phxTarget;
    const pushUpdate = (html) => {
      if (nodeId) {
        if (target) {
          this.pushEventTo(target, "update_node_text", { id: nodeId, content: html });
        } else {
          this.pushEvent("update_node_text", { id: nodeId, content: html });
        }
      } else if (blockId) {
        if (target) {
          this.pushEventTo(target, "update_rich_text", { id: blockId, content: html });
        } else {
          this.pushEvent("update_rich_text", { id: blockId, content: html });
        }
      }
    };

    // Listen for mention suggestions from server
    this.handleEvent("mention_suggestions_result", ({ items }) => {
      if (this.mentionResolve) {
        this.mentionResolve(items);
        this.mentionResolve = null;
      }
    });

    // Build extensions array conditionally
    const extensions = [StarterKit, createMentionExtension(this)];
    if (variablesEnabled) {
      extensions.push(createVariableRefExtension(this));

      // Listen for variable suggestions from server
      this.handleEvent("variable_suggestions_result", ({ items }) => {
        if (this.variableResolve) {
          this.variableResolve(items);
          this.variableResolve = null;
        }
      });

      // Listen for default value resolution
      this.handleEvent("variable_defaults_resolved", ({ defaults }) => {
        this.updateVariableDefaults(defaults);
      });
    }

    this.editor = new Editor({
      element: editorEl,
      extensions: extensions,
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

    // Create toolbar if editable and not in screenplay mode
    if (editable && mode !== "screenplay" && mode !== "dialogue-screenplay") {
      this.createToolbar();
    }

    // Request variable defaults after mount
    if (variablesEnabled) {
      this.requestVariableDefaults();
    }
  },

  /**
   * Scan editor for variableRef nodes and request their default values.
   */
  requestVariableDefaults() {
    if (!this.editor) return;

    const refs = new Set();
    this.editor.state.doc.descendants((node) => {
      if (node.type.name === "variableRef" && node.attrs.id) {
        refs.add(node.attrs.id);
      }
    });

    if (refs.size === 0) return;

    const target = this.el.dataset.phxTarget;
    const payload = { refs: Array.from(refs) };
    if (target) {
      this.pushEventTo(target, "resolve_variable_defaults", payload);
    } else {
      this.pushEvent("resolve_variable_defaults", payload);
    }
  },

  /**
   * Update displayed default values next to variable-ref elements.
   */
  updateVariableDefaults(defaults) {
    if (!this.editor) return;

    const editorEl = this.editor.view.dom;
    const varRefs = editorEl.querySelectorAll(".variable-ref");

    for (const el of varRefs) {
      const ref = el.getAttribute("data-ref");
      if (!ref || !(ref in defaults)) continue;

      const value = defaults[ref];
      const displayValue = value != null ? `(${value})` : "";

      // Find or create the default-value span (sibling after the variable-ref)
      let defaultEl = el.nextElementSibling;
      if (defaultEl?.classList.contains("variable-ref-default")) {
        defaultEl.textContent = displayValue;
      } else if (displayValue) {
        defaultEl = document.createElement("span");
        defaultEl.className = "variable-ref-default";
        defaultEl.contentEditable = "false";
        defaultEl.textContent = displayValue;
        el.after(defaultEl);
      }
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

  disconnected() {
    if (this.editor) {
      this._wasEditable = this.editor.isEditable;
      this.editor.setEditable(false);
    }
  },

  reconnected() {
    if (this.editor && this._wasEditable) {
      this.editor.setEditable(true);
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
    if (this.mentionDebounce) {
      clearTimeout(this.mentionDebounce);
    }
    if (this.variableDebounce) {
      clearTimeout(this.variableDebounce);
    }
    if (this.editor) {
      this.editor.destroy();
    }
  },
};
