/**
 * ScreenplayKeymap — TipTap extension for screenplay-specific keyboard behavior.
 *
 * Handles Enter (create next block with correct type), Tab/Shift-Tab (cycle type),
 * Backspace (convert or delete empty blocks), and Escape (blur editor).
 *
 * All keyboard logic is self-contained here — no server events, no DOM
 * manipulation, no styling. Pure ProseMirror transaction commands.
 */

import { Extension } from "@tiptap/core";

/**
 * Maps the current block type to the type created by pressing Enter.
 * Types not in this map produce "action" (the default screenplay block).
 */
const NEXT_TYPE = {
  sceneHeading: "action",
  action: "action",
  character: "dialogue",
  parenthetical: "dialogue",
  dialogue: "action",
  transition: "sceneHeading",
};

/**
 * The ordered list of types Tab/Shift-Tab cycles through.
 * Note and section are excluded — they're utility types inserted via slash command.
 */
const TYPE_CYCLE = [
  "action",
  "sceneHeading",
  "character",
  "dialogue",
  "parenthetical",
  "transition",
];

/**
 * Enter: split block and set next type, or convert empty non-action to action.
 */
function handleEnter(editor) {
  const { $from } = editor.state.selection;
  const currentNode = $from.parent;
  const currentType = currentNode.type.name;

  // Not a text block we manage → let default handle it
  if (!(currentType in NEXT_TYPE) && !TYPE_CYCLE.includes(currentType)) {
    return false;
  }

  // Empty non-action text block → convert to action instead of splitting
  if (currentNode.textContent === "" && currentType !== "action") {
    return editor.commands.setNode("action");
  }

  const nextType = NEXT_TYPE[currentType] || "action";

  // If splitting a CHARACTER with sheetId at the start, the original block
  // becomes empty but inherits sheetId — clear it to avoid ghost references.
  const atStart = $from.parentOffset === 0;
  const hasSheetId =
    currentType === "character" && currentNode.attrs.sheetId;

  const chain = editor.chain().splitBlock().setNode(nextType);

  if (hasSheetId && atStart) {
    // After split, cursor is in the new (second) block. The first block
    // is the empty one that inherited sheetId — clear it via transaction.
    chain.command(({ tr, state, dispatch }) => {
      if (dispatch) {
        // Find the block before the current selection (the empty original)
        const $pos = state.selection.$from;
        const prevPos = $pos.before($pos.depth) - 1;
        if (prevPos >= 0) {
          const resolvedPrev = state.doc.resolve(prevPos);
          const prevNode = resolvedPrev.parent;
          if (
            prevNode.type.name === "character" &&
            prevNode.attrs.sheetId
          ) {
            const prevBlockPos = resolvedPrev.before(resolvedPrev.depth);
            tr.setNodeMarkup(prevBlockPos, undefined, {
              ...prevNode.attrs,
              sheetId: null,
            });
          }
        }
      }
      return true;
    });
  }

  return chain.run();
}

/**
 * Tab/Shift-Tab: cycle block type through TYPE_CYCLE.
 */
function handleTab(editor, direction) {
  const { $from } = editor.state.selection;
  const currentType = $from.parent.type.name;
  const idx = TYPE_CYCLE.indexOf(currentType);

  // Not a cyclable type → do nothing (prevent default Tab behavior)
  if (idx === -1) return true;

  const nextIdx = (idx + direction + TYPE_CYCLE.length) % TYPE_CYCLE.length;
  const nextType = TYPE_CYCLE[nextIdx];

  return editor.commands.setNode(nextType);
}

/**
 * Backspace at start of empty block: convert non-action to action,
 * otherwise let ProseMirror handle merge/deletion.
 */
function handleBackspace(editor) {
  const { $from, empty: selEmpty } = editor.state.selection;

  // Only intercept when cursor is collapsed and at start of block
  if (!selEmpty || $from.parentOffset !== 0) return false;

  const currentNode = $from.parent;
  const currentType = currentNode.type.name;

  // Non-action empty text block → convert to action first
  if (
    currentNode.textContent === "" &&
    currentType !== "action" &&
    TYPE_CYCLE.includes(currentType)
  ) {
    return editor.commands.setNode("action");
  }

  // Empty action at the start of the document → nothing to do
  // (prevents ProseMirror from lifting/converting to the default block type)
  if (currentNode.textContent === "" && currentType === "action") {
    const index = $from.index($from.depth - 1);
    if (index === 0) return true;
  }

  // Otherwise let default backspace handle it (join, delete atom, etc.)
  return false;
}

export const ScreenplayKeymap = Extension.create({
  name: "screenplayKeymap",

  addKeyboardShortcuts() {
    return {
      Enter: ({ editor }) => handleEnter(editor),
      Tab: ({ editor }) => handleTab(editor, 1),
      "Shift-Tab": ({ editor }) => handleTab(editor, -1),
      Backspace: ({ editor }) => handleBackspace(editor),
      Escape: ({ editor }) => {
        editor.commands.blur();
        return true;
      },
    };
  },
});
