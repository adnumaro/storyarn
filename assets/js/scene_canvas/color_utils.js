/**
 * Strips non-hex characters from a CSS color value.
 * Only preserves # and hexadecimal digits.
 */
export function sanitizeColor(c) {
  return c.replace(/[^#a-fA-F0-9]/g, "");
}

/**
 * Reads a CSS custom property value from the document root.
 * Falls back to the provided default if the variable is empty.
 * @param {string} name - Variable name including -- prefix (e.g. "--color-primary")
 * @param {string} [fallback] - Optional fallback value
 * @returns {string} The computed value, trimmed
 */
export function getCssVar(name, fallback = "") {
  const val = getComputedStyle(document.documentElement).getPropertyValue(name).trim();
  return val || fallback;
}
