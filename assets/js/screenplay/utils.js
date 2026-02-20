/**
 * Shared utilities for screenplay editor JS modules.
 */

/** Escape HTML special characters in text content. */
export function escapeHtml(text) {
  return text.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");
}

/** Escape an HTML attribute value (includes quotes). */
export function escapeAttr(str) {
  if (str == null) return "";
  return String(str)
    .replace(/&/g, "&amp;")
    .replace(/"/g, "&quot;")
    .replace(/'/g, "&#39;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;");
}

/**
 * Position a floating popup below the cursor using TipTap's clientRect.
 * @param {HTMLElement} popup
 * @param {{ clientRect?: () => DOMRect | null }} props
 * @param {{ offsetY?: number, minWidth?: string, maxWidth?: string }} opts
 */
export function positionPopup(popup, props, opts = {}) {
  if (!popup || !props.clientRect) return;
  const rect = props.clientRect();
  if (!rect) return;

  popup.style.left = `${rect.left}px`;
  popup.style.top = `${rect.bottom + (opts.offsetY ?? 4)}px`;
  if (opts.minWidth) popup.style.minWidth = opts.minWidth;
  if (opts.maxWidth) popup.style.maxWidth = opts.maxWidth;
}
