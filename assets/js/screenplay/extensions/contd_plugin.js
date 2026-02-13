/**
 * ContdPlugin — TipTap extension that displays (CONT'D) widget decorations
 * after character nodes when the same speaker appears again without a
 * scene-breaking element in between.
 *
 * Mirrors the server-side ElementGrouping.compute_continuations/2 algorithm
 * so the edit-mode editor matches read-mode rendering.
 *
 * The decoration is read-only (not editable text) — it uses ProseMirror's
 * DecorationSet with widget decorations appended after character node content.
 */

import { Decoration, DecorationSet } from "@tiptap/pm/view";
import { createDecorationPlugin } from "./create_decoration_plugin.js";

// Types that reset the speaker context (same as @continuation_breakers in element_grouping.ex)
const CONTINUATION_BREAKERS = new Set([
  "sceneHeading",
  "transition",
  "conditional",
  "instruction",
  "response",
  "dualDialogue",
  "hubMarker",
  "jumpMarker",
]);

// Extensions like (V.O.), (O.S.), (CONT'D) — stripped for base name comparison
const EXTENSION_PATTERN = /\s*\([^)]+\)/g;

/**
 * Extract the base character name from a node's text content.
 * Strips parenthetical extensions and uppercases for comparison.
 * "JAIME (V.O.) (CONT'D)" → "JAIME"
 */
function baseName(textContent) {
  return textContent.replace(EXTENSION_PATTERN, "").trim().toUpperCase();
}

/**
 * Check if text content already includes a CONT'D extension.
 * "JAIME (CONT'D)" → true, "JAIME (V.O.)" → false
 */
function hasContd(textContent) {
  const matches = textContent.matchAll(/\(([^)]+)\)/g);
  for (const m of matches) {
    if (m[1].trim().toUpperCase() === "CONT'D") return true;
  }
  return false;
}

/**
 * Compute CONT'D decorations for the document.
 * Single-pass O(n) scan matching element_grouping.ex logic.
 */
function computeContdDecorations(doc) {
  const decorations = [];
  let lastSpeaker = null;

  doc.forEach((node, pos) => {
    const type = node.type.name;

    if (type === "character") {
      const text = node.textContent || "";
      const currentBase = baseName(text);

      if (currentBase && lastSpeaker && currentBase === lastSpeaker) {
        // Same speaker after non-breaking elements → show (CONT'D)
        // Only if the content doesn't already include (CONT'D)
        if (!hasContd(text)) {
          // Place inside the character node (end of inline content),
          // not after the closing boundary (which would float between blocks).
          const widgetPos = pos + node.nodeSize - 1;
          const widget = Decoration.widget(widgetPos, () => {
            const span = document.createElement("span");
            span.className = "sp-contd";
            span.textContent = "(CONT'D)";
            return span;
          }, { side: 1 });
          decorations.push(widget);
        }
      }

      lastSpeaker = currentBase || null;
    } else if (CONTINUATION_BREAKERS.has(type)) {
      lastSpeaker = null;
    }
    // action, dialogue, parenthetical, note, section, pageBreak → keep lastSpeaker
  });

  return DecorationSet.create(doc, decorations);
}

export const ContdPlugin = createDecorationPlugin(
  "contdPlugin",
  computeContdDecorations,
);
