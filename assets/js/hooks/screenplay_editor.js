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
import { Plugin, PluginKey } from "prosemirror-state";
import { Decoration, DecorationSet } from "prosemirror-view";
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
  HubMarker,
  JumpMarker,
  TitlePage,
  Conditional,
  Instruction,
  Response,
  DualDialogue,
} from "../screenplay/nodes/index.js";

// Screenplay extensions
import { ScreenplayKeymap } from "../screenplay/extensions/screenplay_keymap.js";
import { ScreenplayPlaceholder } from "../screenplay/extensions/screenplay_placeholder.js";
import { SlashCommands } from "../screenplay/extensions/slash_commands.js";
import { LiveViewBridge } from "../screenplay/extensions/liveview_bridge.js";
import { AutoDetectRules } from "../screenplay/extensions/auto_detect_rules.js";
import { ContdPlugin } from "../screenplay/extensions/contd_plugin.js";
import { TransitionAlignPlugin } from "../screenplay/extensions/transition_align_plugin.js";

// Shared extensions
import { createMentionExtension } from "../tiptap/mention_extension.js";

/** Dispatch a transaction while suppressing LiveViewBridge sync. */
function suppressedDispatch(editor, tr) {
  const bridge = editor.extensionManager.extensions.find(
    (e) => e.name === "liveViewBridge",
  );
  if (bridge) bridge.storage.suppressUpdate = true;
  editor.view.dispatch(tr);
  requestAnimationFrame(() => {
    if (bridge) bridge.storage.suppressUpdate = false;
  });
}

/** ProseMirror plugin that applies a node decoration via transaction meta. */
const highlightPluginKey = new PluginKey("highlightElement");

function createHighlightPlugin() {
  return new Plugin({
    key: highlightPluginKey,
    state: {
      init() {
        return DecorationSet.empty;
      },
      apply(tr, set) {
        const id = tr.getMeta(highlightPluginKey);
        if (id !== undefined) {
          if (id === null) return DecorationSet.empty;

          let targetPos = null;
          tr.doc.forEach((node, pos) => {
            if (targetPos !== null) return;
            if (node.attrs.elementId === id) targetPos = pos;
          });

          if (targetPos !== null) {
            const node = tr.doc.nodeAt(targetPos);
            const deco = Decoration.node(
              targetPos,
              targetPos + node.nodeSize,
              { class: "sp-highlight-flash" },
            );
            return DecorationSet.create(tr.doc, [deco]);
          }
          return DecorationSet.empty;
        }
        return set.map(tr.mapping, tr.doc);
      },
    },
    props: {
      decorations(state) {
        return highlightPluginKey.getState(state);
      },
    },
  });
}

export const ScreenplayEditor = {
  mounted() {
    this._destroyed = false;

    const contentJson = this.el.dataset.content;
    const canEdit = this.el.dataset.canEdit === "true";
    const readMode = this.el.dataset.readMode === "true";

    // Parse shared data for interactive NodeViews
    let variables = [];
    let linkedPages = {};
    try {
      variables = JSON.parse(this.el.dataset.variables || "[]");
    } catch { /* ignore */ }
    try {
      linkedPages = JSON.parse(this.el.dataset.linkedPages || "{}");
    } catch { /* ignore */ }

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
        Character,
        Dialogue,
        Parenthetical,
        Transition,
        Note,
        Section,

        // Atom nodes
        PageBreak,
        HubMarker,
        JumpMarker,
        TitlePage.configure({ liveViewHook, canEdit }),

        // Interactive atom nodes (Phase 2)
        Conditional.configure({ liveViewHook, variables, canEdit }),
        Instruction.configure({ liveViewHook, variables, canEdit }),
        Response.configure({ liveViewHook, variables, canEdit, linkedPages }),
        DualDialogue.configure({ liveViewHook, canEdit }),

        // Behavior extensions
        ScreenplayKeymap,
        ScreenplayPlaceholder,
        SlashCommands,
        AutoDetectRules,
        ContdPlugin,
        TransitionAlignPlugin,
        LiveViewBridge.configure({ liveViewHook }),
        createMentionExtension({ liveViewHook }),
      ],
      content: initialContent,
      editable: canEdit && !readMode,
      editorProps: {
        attributes: {
          class: "screenplay-prosemirror",
        },
      },
    });

    // Apply initial read mode CSS class if starting in read mode
    if (readMode) {
      const pm = this.el.querySelector(".ProseMirror");
      if (pm) pm.classList.add("sp-read-mode");
    }

    // Server pushes read mode toggle
    this.handleEvent("set_read_mode", ({ read_mode }) => {
      if (this._destroyed || !this.editor) return;
      this.editor.setEditable(!read_mode && canEdit);

      const pm = this.el.querySelector(".ProseMirror");
      if (pm) pm.classList.toggle("sp-read-mode", read_mode);
    });

    // Server can request focus (e.g. after element creation)
    this.handleEvent("focus_editor", () => {
      if (this._destroyed || !this.editor) return;
      this.editor.commands.focus("end");
    });

    // Scroll to and highlight a specific element (navigated from a backlink).
    // Uses a ProseMirror decoration so the class survives re-renders.
    const highlightId = parseInt(this.el.dataset.highlightElement, 10);
    if (highlightId) {
      // Register the decoration plugin
      this.editor.registerPlugin(createHighlightPlugin());

      // Dispatch a transaction that triggers the decoration
      const tr = this.editor.state.tr.setMeta(highlightPluginKey, highlightId);
      this.editor.view.dispatch(tr);

      // Scroll after ProseMirror applies the decoration to the DOM
      requestAnimationFrame(() => {
        if (this._destroyed || !this.editor) return;

        let targetPos = null;
        this.editor.state.doc.forEach((node, pos) => {
          if (targetPos !== null) return;
          if (node.attrs.elementId === highlightId) targetPos = pos;
        });

        if (targetPos !== null) {
          const domNode = this.editor.view.nodeDOM(targetPos);
          if (domNode) {
            domNode.scrollIntoView({ behavior: "smooth", block: "center" });
          }
        }
      });
    }

    // Server pushes updated element data after interactive block mutations.
    // Find the node by elementId and update its `data` attribute so the
    // NodeView's update() callback re-renders with fresh data.
    this.handleEvent("element_data_updated", ({ element_id, data }) => {
      if (this._destroyed || !this.editor) return;

      const { doc, tr } = this.editor.state;
      let found = false;

      doc.forEach((node, pos) => {
        if (found) return;
        if (node.attrs.elementId === element_id) {
          tr.setNodeMarkup(pos, undefined, { ...node.attrs, data });
          found = true;
        }
      });

      if (found) {
        suppressedDispatch(this.editor, tr);
      }
    });

    // Server pushes updated linked pages data (for response NodeViews).
    // Update stored data AND trigger re-render of all response NodeViews
    // so page names refresh without waiting for element_data_updated.
    this.handleEvent("linked_pages_updated", ({ linked_pages }) => {
      if (this._destroyed || !this.editor) return;
      this._linkedPages = linked_pages || {};

      // Touch all response nodes to trigger NodeView.update() with fresh linked pages
      const { doc, tr } = this.editor.state;
      let touched = false;

      doc.forEach((node, pos) => {
        if (node.type.name === "response") {
          tr.setNodeMarkup(pos, undefined, { ...node.attrs });
          touched = true;
        }
      });

      if (touched) {
        suppressedDispatch(this.editor, tr);
      }
    });

    // Ctrl/Cmd+Click on mentions or character references → navigate to sheet
    this.el.addEventListener("click", (e) => {
      if (!e.metaKey && !e.ctrlKey) return;

      // Inline mention: <span class="mention" data-id="...">
      const mention = e.target.closest(".mention");
      if (mention) {
        e.preventDefault();
        const sheetId = mention.dataset.id;
        if (sheetId) this.pushEvent("navigate_to_sheet", { sheet_id: sheetId });
        return;
      }

      // Character block with sheet reference: <div class="sp-character" data-sheet-id="...">
      const character = e.target.closest(".sp-character[data-sheet-id]");
      if (character) {
        e.preventDefault();
        this.pushEvent("navigate_to_sheet", {
          sheet_id: character.dataset.sheetId,
        });
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
