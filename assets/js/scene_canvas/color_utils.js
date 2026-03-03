/** Returns true if `c` is a valid CSS hex color (#RGB, #RRGGBB, or #RRGGBBAA). */
export function isValidHexColor(c) {
  return typeof c === "string" && /^#[0-9a-fA-F]{3}([0-9a-fA-F]{3}([0-9a-fA-F]{2})?)?$/.test(c);
}

/**
 * Returns `c` if it is a valid hex color, otherwise returns `fallback`.
 * Replaces the old strip-based sanitizeColor which broke with daisyUI v5 oklch values.
 */
export function sanitizeColor(c, fallback = "#6b7280") {
  return isValidHexColor(c) ? c : fallback;
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
