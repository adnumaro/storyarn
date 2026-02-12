/**
 * SlashCommands — TipTap extension for the "/" command palette.
 *
 * Uses TipTap's Suggestion API to show a floating menu when the user
 * types "/" in an empty block. All filtering and rendering happens
 * client-side — no server round-trip needed.
 */

import { Extension } from "@tiptap/core";
import { Suggestion } from "@tiptap/suggestion";
import { PluginKey } from "@tiptap/pm/state";
import { slashMenuRenderer } from "./slash_menu_renderer.js";

const COMMANDS = [
  // Screenplay
  { type: "sceneHeading", label: "Scene Heading", desc: "INT./EXT. Location - Time", icon: "clapperboard", group: "screenplay", mode: "setNode" },
  { type: "action", label: "Action", desc: "Narrative description", icon: "align-left", group: "screenplay", mode: "setNode" },
  { type: "character", label: "Character", desc: "Character name (ALL CAPS)", icon: "user", group: "screenplay", mode: "setNode" },
  { type: "dialogue", label: "Dialogue", desc: "Spoken text", icon: "message-square", group: "screenplay", mode: "setNode" },
  { type: "parenthetical", label: "Parenthetical", desc: "(acting direction)", icon: "parentheses", group: "screenplay", mode: "setNode" },
  { type: "transition", label: "Transition", desc: "CUT TO:, FADE IN:", icon: "arrow-right", group: "screenplay", mode: "setNode" },
  // Interactive
  { type: "conditional", label: "Condition", desc: "Branch based on variable", icon: "git-branch", group: "interactive", mode: "insertAtom" },
  { type: "instruction", label: "Instruction", desc: "Modify a variable", icon: "zap", group: "interactive", mode: "insertAtom" },
  { type: "response", label: "Responses", desc: "Player choices", icon: "list", group: "interactive", mode: "insertAtom" },
  // Utility
  { type: "note", label: "Note", desc: "Writer's note (not exported)", icon: "sticky-note", group: "utility", mode: "setNode" },
  { type: "section", label: "Section", desc: "Outline header", icon: "heading", group: "utility", mode: "setNode" },
  { type: "pageBreak", label: "Page Break", desc: "Force page break", icon: "scissors", group: "utility", mode: "insertAtom" },
];

const slashPluginKey = new PluginKey("slash-commands");

export const SlashCommands = Extension.create({
  name: "slashCommands",

  addProseMirrorPlugins() {
    return [
      Suggestion({
        editor: this.editor,
        char: "/",
        pluginKey: slashPluginKey,
        startOfLine: false,

        allow: ({ state, range }) => {
          // Only allow when the current block text is empty or just the "/"
          const $from = state.doc.resolve(range.from);
          const blockText = $from.parent.textContent;
          return blockText.trim() === "" || blockText.trim() === "/";
        },

        items: ({ query }) => {
          const q = query.toLowerCase();
          if (!q) return COMMANDS;
          return COMMANDS.filter(
            (c) =>
              c.label.toLowerCase().includes(q) ||
              c.desc.toLowerCase().includes(q),
          );
        },

        command: ({ editor, range, props: item }) => {
          // Delete the "/" trigger text first
          editor.chain().focus().deleteRange(range).run();

          if (item.mode === "setNode") {
            editor.commands.setNode(item.type);
          } else if (item.mode === "insertAtom") {
            // For atom nodes, check if the schema has this node type
            // Interactive blocks (conditional, instruction, response) are Phase 2 —
            // only insert if the node type exists in the schema
            const nodeType = editor.schema.nodes[item.type];
            if (nodeType) {
              editor.commands.insertContent({ type: item.type });
            }
          }
        },

        render: slashMenuRenderer,
      }),
    ];
  },
});
