/**
 * @vitest-environment jsdom
 */

import { EditorState } from "@codemirror/state";
import { EditorView } from "@codemirror/view";
import { describe, expect, it } from "vitest";
import { createLintSource } from "../../expression_editor/linter.js";

const TEST_VARIABLES = [
  { sheet_shortcut: "mc.jaime", variable_name: "health" },
  { sheet_shortcut: "mc.jaime", variable_name: "class" },
  { sheet_shortcut: "mc.jaime", variable_name: "alive" },
  { sheet_shortcut: "mc.link", variable_name: "sword" },
  { sheet_shortcut: "global", variable_name: "quest_progress" },
];

function lint(mode, text, variables = TEST_VARIABLES) {
  const source = createLintSource(mode, variables);
  const state = EditorState.create({ doc: text });
  const view = new EditorView({ state });
  const result = source(view);
  view.destroy();
  return result;
}

describe("expressionLinter", () => {
  describe("empty input", () => {
    it("returns no diagnostics for empty text", () => {
      expect(lint("assignments", "")).toEqual([]);
      expect(lint("expression", "")).toEqual([]);
    });

    it("returns no diagnostics for whitespace-only", () => {
      expect(lint("assignments", "   ")).toEqual([]);
      expect(lint("expression", "  \t  ")).toEqual([]);
    });
  });

  describe("assignments mode — syntax errors", () => {
    it("reports no errors for valid assignment", () => {
      const diags = lint("assignments", "mc.jaime.health = 50");
      const errors = diags.filter((d) => d.severity === "error");
      expect(errors).toHaveLength(0);
    });

    it("reports no errors for valid multi-assignment", () => {
      const diags = lint("assignments", "mc.jaime.health = 50; mc.jaime.alive = true");
      const errors = diags.filter((d) => d.severity === "error");
      expect(errors).toHaveLength(0);
    });

    it("reports syntax error for incomplete assignment", () => {
      const diags = lint("assignments", "mc.jaime.health =");
      const errors = diags.filter((d) => d.severity === "error");
      expect(errors.length).toBeGreaterThan(0);
    });

    it("reports syntax error for bare number", () => {
      const diags = lint("assignments", "42");
      const errors = diags.filter((d) => d.severity === "error");
      expect(errors.length).toBeGreaterThan(0);
    });
  });

  describe("expression mode — syntax errors", () => {
    it("reports no errors for valid expression", () => {
      const diags = lint("expression", "mc.jaime.health > 50");
      const errors = diags.filter((d) => d.severity === "error");
      expect(errors).toHaveLength(0);
    });

    it("reports no errors for valid compound expression", () => {
      const diags = lint("expression", "mc.jaime.health > 50 && mc.jaime.alive");
      const errors = diags.filter((d) => d.severity === "error");
      expect(errors).toHaveLength(0);
    });

    it("reports syntax error for dangling operator", () => {
      const diags = lint("expression", "mc.jaime.health >");
      const errors = diags.filter((d) => d.severity === "error");
      expect(errors.length).toBeGreaterThan(0);
    });
  });

  describe("assignments mode — undefined variable warnings", () => {
    it("no warnings for known LHS variable", () => {
      const diags = lint("assignments", "mc.jaime.health = 50");
      const warnings = diags.filter((d) => d.severity === "warning");
      expect(warnings).toHaveLength(0);
    });

    it("warns for unknown LHS variable", () => {
      const diags = lint("assignments", "mc.jaime.unknown_var = 50");
      const warnings = diags.filter((d) => d.severity === "warning");
      expect(warnings).toHaveLength(1);
      expect(warnings[0].message).toContain("mc.jaime.unknown_var");
    });

    it("warns for unknown RHS variable ref", () => {
      const diags = lint("assignments", "mc.jaime.health = mc.jaime.unknown_var");
      const warnings = diags.filter((d) => d.severity === "warning");
      expect(warnings).toHaveLength(1);
      expect(warnings[0].message).toContain("mc.jaime.unknown_var");
    });

    it("no warnings when both LHS and RHS are known", () => {
      const diags = lint("assignments", "mc.jaime.health = mc.link.sword");
      const warnings = diags.filter((d) => d.severity === "warning");
      expect(warnings).toHaveLength(0);
    });

    it("warns for both unknown LHS and RHS", () => {
      const diags = lint("assignments", "mc.jaime.missing = mc.link.missing");
      const warnings = diags.filter((d) => d.severity === "warning");
      expect(warnings).toHaveLength(2);
    });

    it("no warning for literal value assignment", () => {
      const diags = lint("assignments", 'mc.jaime.class = "warrior"');
      const warnings = diags.filter((d) => d.severity === "warning");
      expect(warnings).toHaveLength(0);
    });
  });

  describe("expression mode — undefined variable warnings", () => {
    it("no warnings for known variable in condition", () => {
      const diags = lint("expression", "mc.jaime.health > 50");
      const warnings = diags.filter((d) => d.severity === "warning");
      expect(warnings).toHaveLength(0);
    });

    it("warns for unknown variable in condition", () => {
      const diags = lint("expression", "mc.jaime.unknown_var > 50");
      const warnings = diags.filter((d) => d.severity === "warning");
      expect(warnings).toHaveLength(1);
      expect(warnings[0].message).toContain("mc.jaime.unknown_var");
    });

    it("warns for unknown variable in compound condition", () => {
      const diags = lint("expression", "mc.jaime.health > 50 && mc.jaime.missing == true");
      const warnings = diags.filter((d) => d.severity === "warning");
      expect(warnings).toHaveLength(1);
      expect(warnings[0].message).toContain("mc.jaime.missing");
    });

    it("no warnings for bare known variable (is_true pattern)", () => {
      const diags = lint("expression", "mc.jaime.alive");
      const warnings = diags.filter((d) => d.severity === "warning");
      expect(warnings).toHaveLength(0);
    });
  });

  describe("diagnostic positions", () => {
    it("error positions point to correct text range", () => {
      const diags = lint("assignments", "mc.jaime.health =");
      const errors = diags.filter((d) => d.severity === "error");
      expect(errors.length).toBeGreaterThan(0);
      for (const err of errors) {
        expect(err.from).toBeGreaterThanOrEqual(0);
        expect(err.to).toBeGreaterThanOrEqual(err.from);
      }
    });

    it("warning positions cover the full variable ref", () => {
      const text = "mc.jaime.missing = 50";
      const diags = lint("assignments", text);
      const warnings = diags.filter((d) => d.severity === "warning");
      expect(warnings).toHaveLength(1);
      const refText = text.slice(warnings[0].from, warnings[0].to);
      expect(refText).toBe("mc.jaime.missing");
    });
  });

  describe("edge cases", () => {
    it("handles empty variable list", () => {
      const diags = lint("assignments", "mc.jaime.health = 50", []);
      // With no known variables, every ref is unknown
      const warnings = diags.filter((d) => d.severity === "warning");
      expect(warnings.length).toBeGreaterThan(0);
    });

    it("handles single-segment sheet shortcuts", () => {
      const diags = lint("expression", "global.quest_progress > 5");
      const warnings = diags.filter((d) => d.severity === "warning");
      expect(warnings).toHaveLength(0);
    });

    it("handles add/subtract operators without false warnings", () => {
      const diags = lint("assignments", "mc.jaime.health += 10");
      const warnings = diags.filter((d) => d.severity === "warning");
      expect(warnings).toHaveLength(0);
    });

    it("handles set_if_unset operator", () => {
      const diags = lint("assignments", "mc.jaime.health ?= 100");
      const warnings = diags.filter((d) => d.severity === "warning");
      expect(warnings).toHaveLength(0);
    });
  });
});
