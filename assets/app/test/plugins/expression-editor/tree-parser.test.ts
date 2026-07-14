import { describe, it, expect } from "vitest";
import { parseCondition, parseAssignments } from "@plugins/expression-editor/tree-parser";

describe("parseCondition", () => {
  it("returns empty condition for empty text", () => {
    const { condition, errors } = parseCondition("");
    expect(condition.logic).toBe("all");
    expect(condition.rules).toHaveLength(0);
    expect(errors).toHaveLength(0);
  });

  it("parses a simple comparison", () => {
    const { condition, errors } = parseCondition("mc.health > 50");
    expect(errors).toHaveLength(0);
    expect(condition.rules).toHaveLength(1);
    expect(condition.rules[0].sheet).toBe("mc");
    expect(condition.rules[0].variable).toBe("health");
    expect(condition.rules[0].operator).toBe("greater_than");
    expect(condition.rules[0].value).toBe("50");
  });

  it("parses equals with string value", () => {
    const { condition } = parseCondition('mc.name == "Alice"');
    expect(condition.rules[0].operator).toBe("equals");
    expect(condition.rules[0].value).toBe("Alice");
  });

  it("parses bare variable ref as is_true", () => {
    const { condition } = parseCondition("mc.alive");
    expect(condition.rules[0].operator).toBe("is_true");
    expect(condition.rules[0].value).toBeNull();
  });

  it("parses negated variable as is_false", () => {
    const { condition } = parseCondition("!mc.dead");
    expect(condition.rules[0].operator).toBe("is_false");
  });

  it("parses AND conditions", () => {
    const { condition } = parseCondition("mc.health > 50 && mc.alive");
    expect(condition.logic).toBe("all");
    expect(condition.rules).toHaveLength(2);
  });

  it("parses OR conditions", () => {
    const { condition } = parseCondition("mc.health > 50 || mc.mana > 30");
    expect(condition.logic).toBe("any");
    expect(condition.rules).toHaveLength(2);
  });

  it("parses string operators", () => {
    const { condition } = parseCondition('mc.name starts_with "Al"');
    expect(condition.rules[0].operator).toBe("starts_with");
    expect(condition.rules[0].value).toBe("Al");
  });

  it("parses nil comparison", () => {
    const { condition } = parseCondition("mc.weapon == nil");
    expect(condition.rules[0].value).toBe("nil");
  });

  it("parses boolean value", () => {
    const { condition } = parseCondition("mc.flag == true");
    expect(condition.rules[0].value).toBe("true");
  });

  it("negates comparison operators", () => {
    const { condition } = parseCondition("!(mc.health > 50)");
    expect(condition.rules[0].operator).toBe("less_than_or_equal");
  });

  it("reports syntax errors", () => {
    const { errors } = parseCondition("mc.health >");
    expect(errors.length).toBeGreaterThan(0);
  });

  it("parses with known variables for disambiguation", () => {
    const vars = [{ sheet_shortcut: "mc", variable_name: "health", block_type: "number" }];
    const { condition } = parseCondition("mc.health > 50", vars);
    expect(condition.rules[0].sheet).toBe("mc");
    expect(condition.rules[0].variable).toBe("health");
  });

  it("generates stable IDs for identical parses", () => {
    const first = parseCondition("mc.health > 50 && mc.alive");
    const second = parseCondition("mc.health > 50 && mc.alive");

    expect(second.condition.rules.map((rule) => rule.id)).toEqual(
      first.condition.rules.map((rule) => rule.id),
    );
  });
});

describe("parseAssignments", () => {
  it("returns empty for empty text", () => {
    const { assignments, errors } = parseAssignments("");
    expect(assignments).toHaveLength(0);
    expect(errors).toHaveLength(0);
  });

  it("parses a set assignment", () => {
    const { assignments, errors } = parseAssignments("mc.health = 100");
    expect(errors).toHaveLength(0);
    expect(assignments).toHaveLength(1);
    expect(assignments[0].sheet).toBe("mc");
    expect(assignments[0].variable).toBe("health");
    expect(assignments[0].operator).toBe("set");
    expect(assignments[0].value).toBe("100");
  });

  it("parses add assignment", () => {
    const { assignments } = parseAssignments("mc.health += 10");
    expect(assignments[0].operator).toBe("add");
    expect(assignments[0].value).toBe("10");
  });

  it("parses subtract assignment", () => {
    const { assignments } = parseAssignments("mc.health -= 5");
    expect(assignments[0].operator).toBe("subtract");
  });

  it("parses set_true from boolean", () => {
    const { assignments } = parseAssignments("mc.alive = true");
    expect(assignments[0].operator).toBe("set_true");
    expect(assignments[0].value).toBeNull();
  });

  it("parses set_false from boolean", () => {
    const { assignments } = parseAssignments("mc.alive = false");
    expect(assignments[0].operator).toBe("set_false");
  });

  it("parses variable ref value", () => {
    const { assignments } = parseAssignments("mc.health = stats.max_hp");
    expect(assignments[0].value_type).toBe("variable_ref");
    expect(assignments[0].value_sheet).toBe("stats");
    expect(assignments[0].value).toBe("max_hp");
  });

  it("parses string value", () => {
    const { assignments } = parseAssignments('mc.name = "Alice"');
    expect(assignments[0].value).toBe("Alice");
  });

  it("parses multiple assignments on separate lines", () => {
    const { assignments } = parseAssignments("mc.hp = 100\nmc.mana += 50");
    expect(assignments).toHaveLength(2);
    expect(assignments[0].variable).toBe("hp");
    expect(assignments[1].variable).toBe("mana");
  });

  it("reports syntax errors with positions", () => {
    const { errors } = parseAssignments("mc.health = ");
    expect(errors.length).toBeGreaterThanOrEqual(0);
  });

  it("generates stable IDs for identical parses", () => {
    const first = parseAssignments("mc.hp = 100\nmc.mana += 50");
    const second = parseAssignments("mc.hp = 100\nmc.mana += 50");

    expect(second.assignments.map((assignment) => assignment.id)).toEqual(
      first.assignments.map((assignment) => assignment.id),
    );
  });
});
