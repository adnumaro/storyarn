/**
 * Tests for the escapeHtml utility.
 *
 * The function uses the browser's textContent→innerHTML technique, which
 * escapes characters that are unsafe in HTML text nodes: <, >, and &.
 * Quotes (" and ') are NOT escaped because they are safe in text nodes
 * (only special inside attribute values).
 *
 * Covers: basic HTML entity escaping, pass-through for safe strings,
 * empty string, multiple special characters, and full HTML tag escaping.
 *
 * @vitest-environment jsdom
 */

import { describe, expect, it } from "vitest";
import { escapeHtml } from "../../utils/escape_html.js";

describe("escapeHtml", () => {
  // ===========================================================================
  // Individual special characters
  // ===========================================================================

  describe("individual special characters", () => {
    it("escapes < to &lt;", () => {
      expect(escapeHtml("<")).toBe("&lt;");
    });

    it("escapes > to &gt;", () => {
      expect(escapeHtml(">")).toBe("&gt;");
    });

    it("escapes & to &amp;", () => {
      expect(escapeHtml("&")).toBe("&amp;");
    });

    it("passes through double quotes (safe in text nodes)", () => {
      expect(escapeHtml('"')).toBe('"');
    });

    it("passes through single quotes (safe in text nodes)", () => {
      expect(escapeHtml("'")).toBe("'");
    });
  });

  // ===========================================================================
  // Pass-through for safe strings
  // ===========================================================================

  describe("strings without special characters", () => {
    it("returns plain text unchanged", () => {
      expect(escapeHtml("hello world")).toBe("hello world");
    });

    it("returns numbers unchanged", () => {
      expect(escapeHtml("12345")).toBe("12345");
    });

    it("returns alphanumeric with spaces unchanged", () => {
      expect(escapeHtml("The quick brown fox")).toBe("The quick brown fox");
    });
  });

  // ===========================================================================
  // Empty string
  // ===========================================================================

  describe("empty string", () => {
    it("returns empty string for empty input", () => {
      expect(escapeHtml("")).toBe("");
    });
  });

  // ===========================================================================
  // Multiple special characters
  // ===========================================================================

  describe("strings with multiple special characters", () => {
    it("escapes <, >, and & in a mixed string", () => {
      const result = escapeHtml('a < b & c > d "e"');
      expect(result).toContain("&lt;");
      expect(result).toContain("&amp;");
      expect(result).toContain("&gt;");
      expect(result).not.toContain("<");
      expect(result).not.toContain(">");
      // & should only appear as part of escape sequences
      expect(result.replace(/&(lt|gt|amp);/g, "")).not.toContain("&");
    });

    it("escapes consecutive angle brackets", () => {
      const result = escapeHtml("<<>>");
      expect(result).toBe("&lt;&lt;&gt;&gt;");
    });

    it("escapes ampersands that look like entities", () => {
      const result = escapeHtml("&amp; &lt;");
      expect(result).toBe("&amp;amp; &amp;lt;");
    });
  });

  // ===========================================================================
  // HTML tags
  // ===========================================================================

  describe("HTML tags", () => {
    it("escapes a script tag (XSS prevention)", () => {
      const result = escapeHtml("<script>alert('xss')</script>");
      expect(result).toContain("&lt;script&gt;");
      expect(result).toContain("&lt;/script&gt;");
      expect(result).not.toContain("<script>");
    });

    it("escapes HTML with attributes", () => {
      const result = escapeHtml('<div class="test">content</div>');
      expect(result).toContain("&lt;div");
      expect(result).toContain("&lt;/div&gt;");
      expect(result).not.toContain("<div");
    });

    it("escapes self-closing tags", () => {
      const result = escapeHtml("<br />");
      expect(result).toBe("&lt;br /&gt;");
    });

    it("escapes nested HTML", () => {
      const result = escapeHtml("<p><strong>bold</strong></p>");
      expect(result).not.toContain("<p>");
      expect(result).not.toContain("<strong>");
      expect(result).toContain("&lt;p&gt;");
      expect(result).toContain("&lt;strong&gt;");
    });

    it("escapes an img tag with onerror handler", () => {
      const result = escapeHtml('<img src=x onerror="alert(1)">');
      expect(result).toContain("&lt;img");
      expect(result).not.toContain("<img");
    });
  });
});
