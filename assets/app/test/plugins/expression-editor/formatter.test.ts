import { describe, it, expect } from "vitest";
import { formatExpression } from '@plugins/expression-editor/formatter.ts';

describe("formatExpression", () => {
  describe("instruction mode", () => {
    it("normalizes one assignment per line", () => {
      expect(formatExpression("mc.hp = 100\nmc.mana += 50", "instruction")).toBe(
        "mc.hp = 100\nmc.mana += 50",
      );
    });

    it("trims whitespace from lines", () => {
      expect(formatExpression("  mc.hp = 100  \n  mc.mana += 50  ", "instruction")).toBe(
        "mc.hp = 100\nmc.mana += 50",
      );
    });

    it("removes empty lines", () => {
      expect(formatExpression("mc.hp = 100\n\n\nmc.mana += 50", "instruction")).toBe(
        "mc.hp = 100\nmc.mana += 50",
      );
    });

    it("returns empty/whitespace text as-is", () => {
      expect(formatExpression("", "instruction")).toBe("");
      expect(formatExpression("   ", "instruction")).toBe("   ");
    });
  });

  describe("condition mode", () => {
    it("keeps short expressions on one line", () => {
      expect(formatExpression("mc.hp > 50", "condition")).toBe("mc.hp > 50");
    });

    it("splits long OR expressions", () => {
      const input = "mc.hp > 50 || mc.mana > 30 || mc.stamina > 20 || mc.alive";
      const result = formatExpression(input, "condition", 40);
      expect(result).toContain("||");
      expect(result.split("\n").length).toBeGreaterThan(1);
    });

    it("splits long AND expressions", () => {
      const input = "mc.hp > 50 && mc.mana > 30 && mc.stamina > 20 && mc.alive";
      const result = formatExpression(input, "condition", 40);
      expect(result).toContain("&&");
      expect(result.split("\n").length).toBeGreaterThan(1);
    });

    it("unwraps and re-indents parenthesized expressions", () => {
      const input =
        "(mc.hp > 50 && mc.mana > 30 && mc.stamina > 20 && mc.alive && mc.level > 10)";
      const result = formatExpression(input, "condition", 40);
      expect(result).toContain("(");
      expect(result).toContain(")");
    });

    it("preserves strings with operators inside", () => {
      const input = 'mc.name == "a || b" && mc.alive';
      const result = formatExpression(input, "condition");
      expect(result).toContain('"a || b"');
    });
  });
});
