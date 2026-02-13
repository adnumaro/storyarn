/**
 * AutoDetectRules — TipTap extension that converts block types on the fly
 * as the user types recognized screenplay patterns.
 *
 * Patterns mirror the server-side AutoDetect module for consistency:
 *   - "INT. " / "EXT. " prefixes → scene heading (from action blocks)
 *   - "CUT TO:" / "FADE IN:" etc. → transition (from action blocks)
 *   - "(text)" → parenthetical (from dialogue blocks)
 *
 * Character ALL CAPS detection is intentionally omitted — it's too aggressive
 * as an InputRule and would fire on any uppercase text.
 */

import { Extension, InputRule } from "@tiptap/core";

// Scene heading prefixes: INT. / EXT. / INT./EXT. / I/E. / EST.
// Triggers on the space after the prefix. Case insensitive to match server.
const SCENE_HEADING_PATTERN =
  /^(INT\.|EXT\.|INT\.\/EXT\.|I\/E\.?|EST\.)\s$/i;

// Known transitions (exact match, full block content)
const KNOWN_TRANSITIONS = new Set([
  "FADE IN:",
  "FADE OUT.",
  "FADE TO BLACK.",
  "INTERCUT:",
]);

// Generic transition: ALL CAPS + "TO:" (e.g. "CUT TO:", "DISSOLVE TO:")
const GENERIC_TRANSITION_PATTERN = /^[A-Z\s]+TO:$/;

// Parenthetical: wrapped in () — triggers on closing paren
const PARENTHETICAL_PATTERN = /^\(.*\)$/;

export const AutoDetectRules = Extension.create({
  name: "autoDetectRules",

  addInputRules() {
    const schema = this.editor.schema;

    return [
      // Scene heading: "INT. " at start of action block
      new InputRule({
        find: SCENE_HEADING_PATTERN,
        handler: ({ state, range }) => {
          const $from = state.doc.resolve(range.from);
          if ($from.parent.type.name !== "action") return null;

          const nodeType = schema.nodes.sceneHeading;
          if (!nodeType) return null;

          state.tr.setBlockType(range.from, range.to, nodeType);
        },
      }),

      // Transition: known phrases or "X TO:" pattern in action block.
      // find triggers on ALL-CAPS text ending with ":" or "." — the handler
      // then validates against known transitions / generic pattern.
      new InputRule({
        find: /^[A-Z][A-Z\s.]*[:.]$/,
        handler: ({ state, range, match }) => {
          const $from = state.doc.resolve(range.from);
          if ($from.parent.type.name !== "action") return null;

          const text = match[0];
          if (
            !KNOWN_TRANSITIONS.has(text) &&
            !GENERIC_TRANSITION_PATTERN.test(text)
          )
            return null;

          const nodeType = schema.nodes.transition;
          if (!nodeType) return null;

          state.tr.setBlockType(range.from, range.to, nodeType);
        },
      }),

      // Parenthetical: "(text)" in dialogue block
      new InputRule({
        find: PARENTHETICAL_PATTERN,
        handler: ({ state, range }) => {
          const $from = state.doc.resolve(range.from);
          if ($from.parent.type.name !== "dialogue") return null;

          const nodeType = schema.nodes.parenthetical;
          if (!nodeType) return null;

          state.tr.setBlockType(range.from, range.to, nodeType);
        },
      }),
    ];
  },
});
