/**
 * Strips non-hex characters from a CSS color value.
 * Only preserves # and hexadecimal digits.
 */
export function sanitizeColor(c) {
  return c.replace(/[^#a-fA-F0-9]/g, "");
}
