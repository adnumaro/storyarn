/**
 * Screenplay Serialization — bidirectional conversion between TipTap doc JSON
 * and flat element arrays for server sync.
 *
 * TipTap uses camelCase node names (sceneHeading), the server uses snake_case
 * (scene_heading). This module handles the mapping in both directions.
 */

import { escapeHtml, escapeAttr } from "./utils.js";

// -- Type mapping (camelCase <-> snake_case) -----------------------------------

const NODE_TYPE_MAP = {
  sceneHeading: "scene_heading",
  action: "action",
  character: "character",
  dialogue: "dialogue",
  parenthetical: "parenthetical",
  transition: "transition",
  note: "note",
  section: "section",
  pageBreak: "page_break",
  dualDialogue: "dual_dialogue",
  conditional: "conditional",
  instruction: "instruction",
  response: "response",
  hubMarker: "hub_marker",
  jumpMarker: "jump_marker",
  titlePage: "title_page",
};

const REVERSE_MAP = Object.fromEntries(
  Object.entries(NODE_TYPE_MAP).map(([k, v]) => [v, k]),
);

const ATOM_TYPES = new Set([
  "pageBreak",
  "dualDialogue",
  "conditional",
  "instruction",
  "response",
  "hubMarker",
  "jumpMarker",
  "titlePage",
]);

/**
 * Convert a TipTap node type to a server element type.
 * Returns the input unchanged for unknown types.
 */
export function toServerType(tiptapType) {
  return NODE_TYPE_MAP[tiptapType] || tiptapType;
}

/**
 * Convert a server element type to a TipTap node type.
 * Returns the input unchanged for unknown types.
 */
export function toTiptapType(serverType) {
  return REVERSE_MAP[serverType] || serverType;
}

// -- Doc -> Elements (client -> server) ----------------------------------------

/**
 * Extracts a flat element list from the TipTap editor's document.
 *
 * Each element has: { type, position, content, data, element_id }
 * where `type` is snake_case and `content` is the node's text or HTML.
 *
 * @param {import("@tiptap/core").Editor} editor - TipTap editor instance
 * @returns {Array<Object>} Element list ready for server sync
 */
export function docToElements(editor) {
  const doc = editor.state.doc;
  const elements = [];
  let position = 0;

  doc.forEach((node) => {
    const tiptapType = node.type.name;
    const serverType = toServerType(tiptapType);
    const isAtom = ATOM_TYPES.has(tiptapType);

    const data = { ...(node.attrs.data || {}) };

    // Sync character sheet reference to server data
    if (tiptapType === "character" && node.attrs.sheetId) {
      data.sheet_id = node.attrs.sheetId;
    }

    const element = {
      type: serverType,
      position,
      content: isAtom ? "" : getNodeText(node),
      data,
      element_id: node.attrs.elementId || null,
    };

    elements.push(element);
    position++;
  });

  return elements;
}

/**
 * Get the content of a node as a string.
 *
 * Pure text nodes are returned as-is (backward compatible plain text).
 * When inline mention nodes are present, content is serialized as HTML
 * with `<span class="mention">` tags so mentions survive the round-trip.
 */
function getNodeText(node) {
  if (!node.content || node.content.size === 0) return "";

  // Check for inline mention nodes
  let hasMentions = false;
  node.content.forEach((child) => {
    if (child.type.name === "mention") hasMentions = true;
  });

  // No mentions: plain text (backward compatible, no encoding overhead)
  if (!hasMentions) {
    return node.textContent || "";
  }

  // Has mentions: serialize as HTML
  let html = "";
  node.content.forEach((child) => {
    if (child.type.name === "text") {
      html += escapeHtml(child.text || "");
    } else if (child.type.name === "mention") {
      const { id, label, type } = child.attrs;
      html += `<span class="mention" data-type="${escapeAttr(type || "sheet")}" data-id="${escapeAttr(id)}" data-label="${escapeAttr(label)}">#${escapeHtml(label || "")}</span>`;
    } else {
      html += escapeHtml(child.textContent || "");
    }
  });

  return html;
}

// -- Elements -> Doc (server -> client) ----------------------------------------

/**
 * Converts a flat element list from the server into a TipTap-compatible
 * document JSON object.
 *
 * @param {Array<Object>} elements - Server elements with { type, content, data, id }
 * @param {import("prosemirror-model").Schema} schema - The editor's ProseMirror schema
 * @returns {Object} TipTap document JSON
 */
export function elementsToDoc(elements, schema) {
  if (!elements || elements.length === 0) {
    return {
      type: "doc",
      content: [
        {
          type: "action",
          attrs: { elementId: null, data: {} },
          content: [],
        },
      ],
    };
  }

  const sorted = [...elements].sort(
    (a, b) => (a.position ?? 0) - (b.position ?? 0),
  );

  const content = sorted.map((el) => {
    const tiptapType = toTiptapType(el.type);
    const isAtom = ATOM_TYPES.has(tiptapType);

    // Verify the node type exists in the schema; fall back to action
    const resolvedType = schema.nodes[tiptapType] ? tiptapType : "action";

    const attrs = {
      elementId: el.id || el.element_id || null,
      data: el.data || {},
    };

    // Copy extra attributes (e.g. sheetId for character)
    if (el.type === "character" && el.data?.sheet_id) {
      attrs.sheetId = el.data.sheet_id;
    }

    const node = { type: resolvedType, attrs };

    if (!isAtom) {
      node.content = htmlToInlineContent(el.content);
    }

    return node;
  });

  return { type: "doc", content };
}

/**
 * Converts an HTML string to TipTap inline content nodes.
 *
 * Plain text (no mention spans) is wrapped in a single text node for
 * backward compatibility. HTML with `<span class="mention">` tags is
 * parsed into mixed text + mention nodes.
 */
function htmlToInlineContent(html) {
  if (!html || html.trim() === "") return [];

  // No mention spans: plain text (backward compat + fast path)
  if (!html.includes("<span")) {
    return [{ type: "text", text: html }];
  }

  // Parse as HTML fragment using a <template> (no resource loading)
  const template = document.createElement("template");
  template.innerHTML = html;
  const nodes = [];

  for (const child of template.content.childNodes) {
    if (child.nodeType === 3) {
      // Text node
      if (child.textContent) {
        nodes.push({ type: "text", text: child.textContent });
      }
    } else if (
      child.nodeType === 1 &&
      child.classList.contains("mention")
    ) {
      // Mention span
      nodes.push({
        type: "mention",
        attrs: {
          id: child.getAttribute("data-id") || "",
          label: child.getAttribute("data-label") || "",
          type: child.getAttribute("data-type") || "sheet",
        },
      });
    } else if (child.nodeType === 1) {
      // Unknown element: extract text content
      if (child.textContent) {
        nodes.push({ type: "text", text: child.textContent });
      }
    }
  }

  return nodes.length > 0 ? nodes : [{ type: "text", text: html }];
}
