import { describe, expect, it } from "vitest";
import { parser } from "../../expression_editor/parser_generated.js";

function parseAssignment(text) {
  return parser.configure({ top: "AssignmentProgram" }).parse(text);
}

function parseExpression(text) {
  return parser.configure({ top: "ExpressionProgram" }).parse(text);
}

function hasErrors(tree) {
  let found = false;
  tree.iterate({
    enter(node) {
      if (node.type.isError) found = true;
    },
  });
  return found;
}

function collectNodeTypes(tree) {
  const types = [];
  tree.iterate({
    enter(node) {
      types.push(node.name);
    },
  });
  return types;
}

function getNodeTexts(tree, text, typeName) {
  const results = [];
  tree.iterate({
    enter(node) {
      if (node.name === typeName) {
        results.push(text.slice(node.from, node.to));
      }
    },
  });
  return results;
}

describe("Storyarn Expression Grammar", () => {
  describe("Assignment mode", () => {
    it("parses a simple set assignment", () => {
      const text = "mc.jaime.health = 50";
      const tree = parseAssignment(text);
      expect(hasErrors(tree)).toBe(false);

      const types = collectNodeTypes(tree);
      expect(types).toContain("AssignmentProgram");
      expect(types).toContain("VariableRef");
      expect(types).toContain("SetOp");
      expect(types).toContain("Number");
    });

    it("parses an add assignment (+=)", () => {
      const text = "mc.jaime.health += 10";
      const tree = parseAssignment(text);
      expect(hasErrors(tree)).toBe(false);
      expect(collectNodeTypes(tree)).toContain("AddOp");
    });

    it("parses a subtract assignment (-=)", () => {
      const text = "mc.jaime.health -= 5";
      const tree = parseAssignment(text);
      expect(hasErrors(tree)).toBe(false);
      expect(collectNodeTypes(tree)).toContain("SubOp");
    });

    it("parses set_if_unset assignment (?=)", () => {
      const text = "party.present ?= true";
      const tree = parseAssignment(text);
      expect(hasErrors(tree)).toBe(false);
      expect(collectNodeTypes(tree)).toContain("SetIfUnsetOp");
      expect(collectNodeTypes(tree)).toContain("Boolean");
    });

    it("parses string value assignment", () => {
      const text = 'mc.jaime.class = "warrior"';
      const tree = parseAssignment(text);
      expect(hasErrors(tree)).toBe(false);

      const strings = getNodeTexts(tree, text, "StringLiteral");
      expect(strings).toEqual(['"warrior"']);
    });

    it("parses boolean true assignment", () => {
      const text = "mc.jaime.alive = true";
      const tree = parseAssignment(text);
      expect(hasErrors(tree)).toBe(false);
      expect(getNodeTexts(tree, text, "Boolean")).toEqual(["true"]);
    });

    it("parses boolean false assignment", () => {
      const text = "mc.jaime.alive = false";
      const tree = parseAssignment(text);
      expect(hasErrors(tree)).toBe(false);
      expect(getNodeTexts(tree, text, "Boolean")).toEqual(["false"]);
    });

    it("parses variable ref as value (right-hand side)", () => {
      const text = "mc.link.sword = global.quests.done";
      const tree = parseAssignment(text);
      expect(hasErrors(tree)).toBe(false);

      const refs = getNodeTexts(tree, text, "VariableRef");
      expect(refs).toHaveLength(2);
      expect(refs[0]).toBe("mc.link.sword");
      expect(refs[1]).toBe("global.quests.done");
    });

    it("parses multiple assignments separated by semicolons", () => {
      const text = "mc.jaime.health = 50; global.quest += 1";
      const tree = parseAssignment(text);
      expect(hasErrors(tree)).toBe(false);

      const setOps = getNodeTexts(tree, text, "SetOp");
      const addOps = getNodeTexts(tree, text, "AddOp");
      expect(setOps.length + addOps.length).toBe(2);
    });

    it("parses decimal number values", () => {
      const text = "mc.jaime.health = 3.14";
      const tree = parseAssignment(text);
      expect(hasErrors(tree)).toBe(false);
      expect(getNodeTexts(tree, text, "Number")).toEqual(["3.14"]);
    });

    it("parses empty program", () => {
      const tree = parseAssignment("");
      expect(hasErrors(tree)).toBe(false);
    });

    it("parses multi-dot variable refs (sheet.variable format)", () => {
      const text = "mc.jaime.health = 50";
      const tree = parseAssignment(text);
      expect(hasErrors(tree)).toBe(false);

      const refs = getNodeTexts(tree, text, "VariableRef");
      expect(refs).toEqual(["mc.jaime.health"]);

      // Should contain 3 identifiers: mc, jaime, health
      const ids = getNodeTexts(tree, text, "Identifier");
      expect(ids).toContain("mc");
      expect(ids).toContain("jaime");
      expect(ids).toContain("health");
    });

    it("handles line comments", () => {
      const text = "mc.jaime.health = 50 // set health";
      const tree = parseAssignment(text);
      expect(hasErrors(tree)).toBe(false);
      expect(collectNodeTypes(tree)).toContain("SetOp");
    });
  });

  describe("Expression mode", () => {
    it("parses a simple comparison", () => {
      const text = "mc.jaime.health > 50";
      const tree = parseExpression(text);
      expect(hasErrors(tree)).toBe(false);
      expect(collectNodeTypes(tree)).toContain("ExpressionProgram");
      expect(collectNodeTypes(tree)).toContain("Gt");
    });

    it("parses string equality", () => {
      const text = 'mc.jaime.class == "warrior"';
      const tree = parseExpression(text);
      expect(hasErrors(tree)).toBe(false);
      expect(collectNodeTypes(tree)).toContain("Eq");
      expect(getNodeTexts(tree, text, "StringLiteral")).toEqual(['"warrior"']);
    });

    it("parses AND condition", () => {
      const text = "a.b > 1 && c.d < 2";
      const tree = parseExpression(text);
      expect(hasErrors(tree)).toBe(false);
      expect(collectNodeTypes(tree)).toContain("And");
      expect(collectNodeTypes(tree)).toContain("Gt");
      expect(collectNodeTypes(tree)).toContain("Lt");
    });

    it("parses OR condition", () => {
      const text = "a.b > 1 || c.d < 2";
      const tree = parseExpression(text);
      expect(hasErrors(tree)).toBe(false);
      expect(collectNodeTypes(tree)).toContain("Or");
    });

    it("parses negation with parentheses", () => {
      const text = "!(mc.jaime.dead)";
      const tree = parseExpression(text);
      expect(hasErrors(tree)).toBe(false);
      expect(collectNodeTypes(tree)).toContain("Not");
      expect(collectNodeTypes(tree)).toContain("ParenExpr");
    });

    it("parses bare boolean variable reference (is_true)", () => {
      const text = "party.present";
      const tree = parseExpression(text);
      expect(hasErrors(tree)).toBe(false);
      expect(collectNodeTypes(tree)).toContain("VariableRef");
    });

    it("parses negated boolean variable (is_false)", () => {
      const text = "!party.present";
      const tree = parseExpression(text);
      expect(hasErrors(tree)).toBe(false);
      expect(collectNodeTypes(tree)).toContain("Not");
      expect(collectNodeTypes(tree)).toContain("VariableRef");
    });

    it("parses compound AND/OR expression", () => {
      const text = "a.b > 50 && c.d >= 3 || e.f == true";
      const tree = parseExpression(text);
      expect(hasErrors(tree)).toBe(false);
      expect(collectNodeTypes(tree)).toContain("And");
      expect(collectNodeTypes(tree)).toContain("Or");
    });

    it("parses grouped expression with parentheses", () => {
      const text = "(a.b > 1 || c.d < 2) && e.f == true";
      const tree = parseExpression(text);
      expect(hasErrors(tree)).toBe(false);
      expect(collectNodeTypes(tree)).toContain("ParenExpr");
      expect(collectNodeTypes(tree)).toContain("And");
    });

    it("parses all comparison operators", () => {
      const operators = [
        ["==", "Eq"],
        ["!=", "Neq"],
        [">", "Gt"],
        ["<", "Lt"],
        [">=", "Gte"],
        ["<=", "Lte"],
      ];

      for (const [symbol, nodeName] of operators) {
        const text = `a.b ${symbol} 10`;
        const tree = parseExpression(text);
        expect(hasErrors(tree)).toBe(false);
        expect(collectNodeTypes(tree)).toContain(nodeName);
      }
    });

    it("parses multi-segment variable refs in expressions", () => {
      const text = "mc.jaime.health > 50 && global.quest.progress >= 3";
      const tree = parseExpression(text);
      expect(hasErrors(tree)).toBe(false);

      const refs = getNodeTexts(tree, text, "VariableRef");
      expect(refs).toContain("mc.jaime.health");
      expect(refs).toContain("global.quest.progress");
    });

    it("handles line comments in expressions", () => {
      const text = "a.b > 1 // check threshold";
      const tree = parseExpression(text);
      expect(hasErrors(tree)).toBe(false);
    });

    it("detects syntax errors gracefully", () => {
      const text = "mc.jaime.health >";
      const tree = parseExpression(text);
      // Lezer is error-tolerant, so it should still produce a tree
      expect(hasErrors(tree)).toBe(true);
      // But should still have some structure
      expect(collectNodeTypes(tree)).toContain("ExpressionProgram");
    });
  });
});
