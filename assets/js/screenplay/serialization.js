/**
 * Screenplay Serialization — bidirectional conversion between TipTap doc JSON
 * and flat element arrays for server sync.
 *
 * TipTap uses camelCase node names (sceneHeading), the server uses snake_case
 * (scene_heading). This module handles the mapping in both directions.
 */

import { escapeAttr, escapeHtml } from "./utils.js";

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

const REVERSE_MAP = Object.fromEntries(Object.entries(NODE_TYPE_MAP).map(([k, v]) => [v, k]));

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
 * When marks, hard breaks, or mentions are present, content is serialized
 * as HTML so rich formatting survives the round-trip.
 */
function getNodeText(node) {
  if (!node.content || node.content.size === 0) return "";

  // Check if we need HTML serialization (mentions, marks, hard breaks)
  let needsHtml = false;
  node.content.forEach((child) => {
    if (child.type.name === "mention" || child.type.name === "hardBreak") needsHtml = true;
    if (child.marks && child.marks.length > 0) needsHtml = true;
  });

  // No rich content: plain text (backward compatible, no encoding overhead)
  if (!needsHtml) {
    return node.textContent || "";
  }

  // Serialize as HTML
  let html = "";
  node.content.forEach((child) => {
    if (child.type.name === "text") {
      let text = escapeHtml(child.text || "");
      if (child.marks && child.marks.length > 0) {
        text = wrapMarks(text, child.marks);
      }
      html += text;
    } else if (child.type.name === "hardBreak") {
      html += "<br>";
    } else if (child.type.name === "mention") {
      const { id, label, type } = child.attrs;
      html += `<span class="mention" data-type="${escapeAttr(type || "sheet")}" data-id="${escapeAttr(id)}" data-label="${escapeAttr(label)}">#${escapeHtml(label || "")}</span>`;
    } else {
      html += escapeHtml(child.textContent || "");
    }
  });

  return html;
}

/** Wrap HTML text in mark tags (bold → <strong>, italic → <em>, strike → <s>). */
function wrapMarks(html, marks) {
  for (const mark of marks) {
    switch (mark.type.name) {
      case "bold":
        html = `<strong>${html}</strong>`;
        break;
      case "italic":
        html = `<em>${html}</em>`;
        break;
      case "strike":
        html = `<s>${html}</s>`;
        break;
    }
  }
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

  const sorted = [...elements].sort((a, b) => (a.position ?? 0) - (b.position ?? 0));

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

// Tags that trigger HTML parsing (mentions, marks, hard breaks)
const HTML_TAG_PATTERN = /<(?:span|strong|em|[bis]|del|br)\b/i;

/**
 * Converts an HTML string to TipTap inline content nodes.
 *
 * Plain text (no HTML tags) is wrapped in a single text node for
 * backward compatibility. HTML with marks, mentions, or hard breaks
 * is parsed into structured TipTap nodes with marks.
 */
function htmlToInlineContent(html) {
  if (!html || html.trim() === "") return [];

  // No HTML tags: plain text (backward compat + fast path)
  if (!HTML_TAG_PATTERN.test(html)) {
    return [{ type: "text", text: html }];
  }

  // Parse as HTML fragment using a <template> (no resource loading)
  const template = document.createElement("template");
  template.innerHTML = html;
  const nodes = parseInlineNodes(template.content.childNodes, []);

  return nodes.length > 0 ? nodes : [{ type: "text", text: html }];
}

/** Recursively parse DOM nodes into TipTap inline content, accumulating marks. */
function parseInlineNodes(childNodes, marks) {
  const nodes = [];

  for (const child of childNodes) {
    if (child.nodeType === 3) {
      // Text node
      if (child.textContent) {
        const node = { type: "text", text: child.textContent };
        if (marks.length > 0) {
          node.marks = marks.map((m) => ({ type: m }));
        }
        nodes.push(node);
      }
    } else if (child.nodeType === 1) {
      const tag = child.tagName.toLowerCase();

      if (child.classList.contains("mention")) {
        nodes.push({
          type: "mention",
          attrs: {
            id: child.getAttribute("data-id") || "",
            label: child.getAttribute("data-label") || "",
            type: child.getAttribute("data-type") || "sheet",
          },
        });
      } else if (tag === "br") {
        nodes.push({ type: "hardBreak" });
      } else if (tag === "strong" || tag === "b") {
        nodes.push(...parseInlineNodes(child.childNodes, [...marks, "bold"]));
      } else if (tag === "em" || tag === "i") {
        nodes.push(...parseInlineNodes(child.childNodes, [...marks, "italic"]));
      } else if (tag === "s" || tag === "del") {
        nodes.push(...parseInlineNodes(child.childNodes, [...marks, "strike"]));
      } else {
        // Unknown element: recurse into children preserving marks
        nodes.push(...parseInlineNodes(child.childNodes, marks));
      }
    }
  }

  return nodes;
}
