import { describe, expect, it } from "vitest";
import { parseAssignments, parseCondition } from "../../expression_editor/parser.js";

describe("parseAssignments", () => {
  it("parses simple set assignment", () => {
    const { assignments, errors } = parseAssignments("mc.jaime.health = 50");
    expect(errors).toHaveLength(0);
    expect(assignments).toHaveLength(1);

    const a = assignments[0];
    expect(a.sheet).toBe("mc.jaime");
    expect(a.variable).toBe("health");
    expect(a.operator).toBe("set");
    expect(a.value).toBe("50");
    expect(a.value_type).toBe("literal");
  });

  it("parses add assignment", () => {
    const { assignments, errors } = parseAssignments("mc.jaime.health += 10");
    expect(errors).toHaveLength(0);
    expect(assignments[0].operator).toBe("add");
    expect(assignments[0].value).toBe("10");
  });

  it("parses subtract assignment", () => {
    const { assignments, errors } = parseAssignments("mc.jaime.health -= 5");
    expect(errors).toHaveLength(0);
    expect(assignments[0].operator).toBe("subtract");
    expect(assignments[0].value).toBe("5");
  });

  it("parses set_if_unset assignment", () => {
    const { assignments, errors } = parseAssignments("party.present ?= true");
    expect(errors).toHaveLength(0);
    expect(assignments[0].operator).toBe("set_if_unset");
  });

  it("parses variable_ref value", () => {
    const { assignments, errors } = parseAssignments("mc.link.sword = global.quests.done");
    expect(errors).toHaveLength(0);

    const a = assignments[0];
    expect(a.sheet).toBe("mc.link");
    expect(a.variable).toBe("sword");
    expect(a.value_type).toBe("variable_ref");
    expect(a.value_sheet).toBe("global.quests");
    expect(a.value).toBe("done");
  });

  it("parses boolean true as set_true", () => {
    const { assignments, errors } = parseAssignments("mc.jaime.alive = true");
    expect(errors).toHaveLength(0);
    expect(assignments[0].operator).toBe("set_true");
    expect(assignments[0].value).toBeNull();
  });

  it("parses boolean false as set_false", () => {
    const { assignments, errors } = parseAssignments("mc.jaime.alive = false");
    expect(errors).toHaveLength(0);
    expect(assignments[0].operator).toBe("set_false");
  });

  it("parses string value", () => {
    const { assignments, errors } = parseAssignments('mc.jaime.class = "warrior"');
    expect(errors).toHaveLength(0);
    expect(assignments[0].value).toBe("warrior");
    expect(assignments[0].value_type).toBe("literal");
  });

  it("parses multiple assignments separated by semicolons", () => {
    const { assignments, errors } = parseAssignments("mc.jaime.health = 50; global.quest += 1");
    expect(errors).toHaveLength(0);
    expect(assignments).toHaveLength(2);
    expect(assignments[0].operator).toBe("set");
    expect(assignments[1].operator).toBe("add");
  });

  it("generates unique IDs for each assignment", () => {
    const { assignments } = parseAssignments("a.b = 1; c.d = 2");
    expect(assignments[0].id).toMatch(/^assign_/);
    expect(assignments[1].id).toMatch(/^assign_/);
    expect(assignments[0].id).not.toBe(assignments[1].id);
  });

  it("returns empty for empty input", () => {
    const { assignments, errors } = parseAssignments("");
    expect(assignments).toHaveLength(0);
    expect(errors).toHaveLength(0);
  });

  it("returns empty for whitespace input", () => {
    const { assignments, errors } = parseAssignments("   ");
    expect(assignments).toHaveLength(0);
    expect(errors).toHaveLength(0);
  });

  it("includes position metadata for variable refs", () => {
    const text = "mc.jaime.health = 50";
    const { assignments } = parseAssignments(text);
    const a = assignments[0];
    expect(a.ref_from).toBe(0);
    expect(a.ref_to).toBe(15); // "mc.jaime.health".length
  });

  it("handles decimal numbers", () => {
    const { assignments, errors } = parseAssignments("mc.jaime.health = 3.14");
    expect(errors).toHaveLength(0);
    expect(assignments[0].value).toBe("3.14");
  });

  it("reports errors for incomplete assignments", () => {
    const { errors } = parseAssignments("mc.jaime.health = ");
    expect(errors.length).toBeGreaterThan(0);
  });
});

describe("parseCondition", () => {
  it("parses simple greater_than comparison", () => {
    const { condition, errors } = parseCondition("mc.jaime.health > 50");
    expect(errors).toHaveLength(0);
    expect(condition.logic).toBe("all");
    expect(condition.rules).toHaveLength(1);

    const r = condition.rules[0];
    expect(r.sheet).toBe("mc.jaime");
    expect(r.variable).toBe("health");
    expect(r.operator).toBe("greater_than");
    expect(r.value).toBe("50");
  });

  it("parses equals comparison", () => {
    const { condition, errors } = parseCondition("mc.jaime.health == 100");
    expect(errors).toHaveLength(0);
    expect(condition.rules[0].operator).toBe("equals");
  });

  it("parses not_equals comparison", () => {
    const { condition, errors } = parseCondition('mc.jaime.class != "warrior"');
    expect(errors).toHaveLength(0);
    expect(condition.rules[0].operator).toBe("not_equals");
    expect(condition.rules[0].value).toBe("warrior");
  });

  it("parses less_than comparison", () => {
    const { condition } = parseCondition("mc.jaime.health < 10");
    expect(condition.rules[0].operator).toBe("less_than");
  });

  it("parses greater_than_or_equal comparison", () => {
    const { condition } = parseCondition("mc.jaime.health >= 50");
    expect(condition.rules[0].operator).toBe("greater_than_or_equal");
  });

  it("parses less_than_or_equal comparison", () => {
    const { condition } = parseCondition("mc.jaime.health <= 50");
    expect(condition.rules[0].operator).toBe("less_than_or_equal");
  });

  it("parses AND condition (logic: all)", () => {
    const { condition, errors } = parseCondition("a.b > 1 && c.d < 2");
    expect(errors).toHaveLength(0);
    expect(condition.logic).toBe("all");
    expect(condition.rules).toHaveLength(2);
    expect(condition.rules[0].operator).toBe("greater_than");
    expect(condition.rules[1].operator).toBe("less_than");
  });

  it("parses OR condition (logic: any)", () => {
    const { condition, errors } = parseCondition("a.b > 1 || c.d < 2");
    expect(errors).toHaveLength(0);
    expect(condition.logic).toBe("any");
    expect(condition.rules).toHaveLength(2);
  });

  it("parses bare variable as is_true", () => {
    const { condition, errors } = parseCondition("party.present");
    expect(errors).toHaveLength(0);
    expect(condition.rules[0].operator).toBe("is_true");
    expect(condition.rules[0].sheet).toBe("party");
    expect(condition.rules[0].variable).toBe("present");
    expect(condition.rules[0].value).toBeNull();
  });

  it("parses negated variable as is_false", () => {
    const { condition, errors } = parseCondition("!party.present");
    expect(errors).toHaveLength(0);
    expect(condition.rules[0].operator).toBe("is_false");
    expect(condition.rules[0].sheet).toBe("party");
    expect(condition.rules[0].variable).toBe("present");
  });

  it("parses parenthesized negation", () => {
    const { condition, errors } = parseCondition("!(mc.jaime.dead)");
    expect(errors).toHaveLength(0);
    expect(condition.rules[0].operator).toBe("is_false");
    expect(condition.rules[0].sheet).toBe("mc.jaime");
    expect(condition.rules[0].variable).toBe("dead");
  });

  it("parses string comparison", () => {
    const { condition, errors } = parseCondition('mc.jaime.class == "warrior"');
    expect(errors).toHaveLength(0);
    expect(condition.rules[0].value).toBe("warrior");
  });

  it("parses boolean comparison", () => {
    const { condition, errors } = parseCondition("mc.jaime.alive == true");
    expect(errors).toHaveLength(0);
    expect(condition.rules[0].value).toBe("true");
  });

  it("generates unique IDs for rules", () => {
    const { condition } = parseCondition("a.b > 1 && c.d < 2");
    expect(condition.rules[0].id).toMatch(/^rule_/);
    expect(condition.rules[1].id).toMatch(/^rule_/);
    expect(condition.rules[0].id).not.toBe(condition.rules[1].id);
  });

  it("returns empty condition for empty input", () => {
    const { condition, errors } = parseCondition("");
    expect(condition.logic).toBe("all");
    expect(condition.rules).toHaveLength(0);
    expect(errors).toHaveLength(0);
  });

  it("includes position metadata for variable refs", () => {
    const text = "mc.jaime.health > 50";
    const { condition } = parseCondition(text);
    expect(condition.rules[0].ref_from).toBe(0);
    expect(condition.rules[0].ref_to).toBe(15);
  });

  it("handles multi-segment variable refs", () => {
    const { condition, errors } = parseCondition(
      "mc.jaime.health > 50 && global.quest.progress >= 3",
    );
    expect(errors).toHaveLength(0);
    expect(condition.rules[0].sheet).toBe("mc.jaime");
    expect(condition.rules[0].variable).toBe("health");
    expect(condition.rules[1].sheet).toBe("global.quest");
    expect(condition.rules[1].variable).toBe("progress");
  });

  it("reports syntax errors with positions", () => {
    const { errors } = parseCondition("mc.jaime.health >");
    expect(errors.length).toBeGreaterThan(0);
    expect(errors[0]).toHaveProperty("from");
    expect(errors[0]).toHaveProperty("to");
    expect(errors[0]).toHaveProperty("message");
  });
});
