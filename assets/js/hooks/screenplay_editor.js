/**
 * ScreenplayEditor — unified Phoenix LiveView hook for the TipTap screenplay editor.
 *
 * Assembles all screenplay extensions into a single TipTap editor instance.
 * Replaces ScreenplayEditorPage, ScreenplayElement, ScreenplayTiptapElement,
 * and SlashCommand hooks.
 *
 * This hook is intentionally thin — all behavior is delegated to extensions:
 *   - ScreenplayKeymap: keyboard shortcuts (Enter, Tab, Backspace, Escape)
 *   - LiveViewBridge: debounced client↔server sync
 *   - SlashCommands: "/" command palette
 *   - MentionExtension: "#" sheet/flow references
 *   - ScreenplayPlaceholder: per-type placeholder text
 */

import { Editor } from "@tiptap/core";
import StarterKit from "@tiptap/starter-kit";

// Custom screenplay nodes
import {
  ScreenplayDoc,
  SceneHeading,
  Action,
  Character,
  Dialogue,
  Parenthetical,
  Transition,
  Note,
  Section,
  PageBreak,
} from "../screenplay/nodes/index.js";

// Screenplay extensions
import { ScreenplayKeymap } from "../screenplay/extensions/screenplay_keymap.js";
import { ScreenplayPlaceholder } from "../screenplay/extensions/screenplay_placeholder.js";
import { SlashCommands } from "../screenplay/extensions/slash_commands.js";
import { LiveViewBridge } from "../screenplay/extensions/liveview_bridge.js";

// Shared extensions
import { createMentionExtension } from "../tiptap/mention_extension.js";

export const ScreenplayEditor = {
  mounted() {
    this._destroyed = false;

    const contentJson = this.el.dataset.content;
    const canEdit = this.el.dataset.canEdit === "true";

    let initialContent;
    try {
      initialContent = contentJson ? JSON.parse(contentJson) : undefined;
    } catch {
      initialContent = undefined;
    }

    // Listen for mention suggestions from server
    this.handleEvent("mention_suggestions_result", ({ items }) => {
      if (this.mentionResolve) {
        this.mentionResolve(items);
        this.mentionResolve = null;
      }
    });

    // Store hook reference so NodeViews/extensions can push events to server
    const liveViewHook = this;

    this.editor = new Editor({
      element: this.el,
      extensions: [
        // Custom doc node restricts content to screenplayBlock+
        ScreenplayDoc,

        // StarterKit provides Text, HardBreak, History, Bold, Italic, Strike.
        // Disable everything else — screenplay nodes replace paragraphs/headings.
        StarterKit.configure({
          document: false,
          paragraph: false,
          heading: false,
          bulletList: false,
          orderedList: false,
          listItem: false,
          codeBlock: false,
          code: false,
          blockquote: false,
          horizontalRule: false,
          dropcursor: false,
          gapcursor: false,
        }),

        // Text block nodes (Action first = default block type for ProseMirror)
        Action,
        SceneHeading,
        Character.configure({ liveViewHook }),
        Dialogue,
        Parenthetical,
        Transition,
        Note,
        Section,

        // Atom nodes
        PageBreak,

        // Behavior extensions
        ScreenplayKeymap,
        ScreenplayPlaceholder,
        SlashCommands,
        LiveViewBridge.configure({ liveViewHook }),
        createMentionExtension({ liveViewHook }),
      ],
      content: initialContent,
      editable: canEdit,
      editorProps: {
        attributes: {
          class: "screenplay-prosemirror",
        },
      },
    });

    // Server can request focus (e.g. after element creation)
    this.handleEvent("focus_editor", () => {
      if (this._destroyed || !this.editor) return;
      this.editor.commands.focus("end");
    });

    // Ctrl/Cmd+Click on inline mentions → navigate to sheet
    this.el.addEventListener("click", (e) => {
      if (!e.metaKey && !e.ctrlKey) return;
      const mention = e.target.closest(".mention");
      if (!mention) return;

      e.preventDefault();
      const sheetId = mention.dataset.id;
      if (sheetId) {
        this.pushEvent("navigate_to_sheet", { sheet_id: sheetId });
      }
    });

    // Click on empty page area → focus editor at end
    const page = this.el.closest(".screenplay-page");
    if (page) {
      this._pageClickHandler = (e) => {
        if (this._destroyed || !this.editor) return;
        // Only handle clicks directly on the page or editor container
        // (not on existing content, buttons, etc.)
        if (e.target === page || e.target === this.el) {
          this.editor.commands.focus("end");
        }
      };
      page.addEventListener("click", this._pageClickHandler);
    }
  },

  destroyed() {
    this._destroyed = true;

    if (this._pageClickHandler) {
      const page = this.el.closest(".screenplay-page");
      if (page) page.removeEventListener("click", this._pageClickHandler);
      this._pageClickHandler = null;
    }

    if (this.editor) {
      this.editor.destroy();
      this.editor = null;
    }
  },
};
