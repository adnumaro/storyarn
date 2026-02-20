import { describe, expect, it } from "vitest";
import { parseAssignments, parseCondition } from "../../expression_editor/parser.js";
import { serializeAssignments, serializeCondition } from "../../expression_editor/serializer.js";

describe("serializeAssignments", () => {
  it("serializes set assignment", () => {
    const result = serializeAssignments([
      {
        sheet: "mc.jaime",
        variable: "health",
        operator: "set",
        value: "50",
        value_type: "literal",
      },
    ]);
    expect(result).toBe("mc.jaime.health = 50");
  });

  it("serializes add assignment", () => {
    const result = serializeAssignments([
      {
        sheet: "mc.jaime",
        variable: "health",
        operator: "add",
        value: "10",
        value_type: "literal",
      },
    ]);
    expect(result).toBe("mc.jaime.health += 10");
  });

  it("serializes subtract assignment", () => {
    const result = serializeAssignments([
      {
        sheet: "mc.jaime",
        variable: "health",
        operator: "subtract",
        value: "5",
        value_type: "literal",
      },
    ]);
    expect(result).toBe("mc.jaime.health -= 5");
  });

  it("serializes set_if_unset assignment", () => {
    const result = serializeAssignments([
      {
        sheet: "party",
        variable: "present",
        operator: "set_if_unset",
        value: "true",
        value_type: "literal",
      },
    ]);
    expect(result).toBe("party.present ?= true");
  });

  it("serializes variable ref value", () => {
    const result = serializeAssignments([
      {
        sheet: "mc.link",
        variable: "sword",
        operator: "set",
        value: "done",
        value_type: "variable_ref",
        value_sheet: "global.quests",
      },
    ]);
    expect(result).toBe("mc.link.sword = global.quests.done");
  });

  it("serializes set_true", () => {
    const result = serializeAssignments([
      { sheet: "mc.jaime", variable: "alive", operator: "set_true" },
    ]);
    expect(result).toBe("mc.jaime.alive = true");
  });

  it("serializes set_false", () => {
    const result = serializeAssignments([
      { sheet: "mc.jaime", variable: "alive", operator: "set_false" },
    ]);
    expect(result).toBe("mc.jaime.alive = false");
  });

  it("serializes toggle", () => {
    const result = serializeAssignments([
      { sheet: "mc.jaime", variable: "alive", operator: "toggle" },
    ]);
    expect(result).toBe("toggle mc.jaime.alive");
  });

  it("serializes clear", () => {
    const result = serializeAssignments([
      { sheet: "mc.jaime", variable: "text", operator: "clear" },
    ]);
    expect(result).toBe("clear mc.jaime.text");
  });

  it("serializes multiple assignments joined by newline", () => {
    const result = serializeAssignments([
      {
        sheet: "mc.jaime",
        variable: "health",
        operator: "set",
        value: "50",
        value_type: "literal",
      },
      { sheet: "global", variable: "quest", operator: "add", value: "1", value_type: "literal" },
    ]);
    expect(result).toBe("mc.jaime.health = 50\nglobal.quest += 1");
  });

  it("skips incomplete assignments (no sheet)", () => {
    const result = serializeAssignments([
      { sheet: "", variable: "health", operator: "set", value: "50" },
      { sheet: "mc.jaime", variable: "health", operator: "set", value: "50" },
    ]);
    expect(result).toBe("mc.jaime.health = 50");
  });

  it("skips incomplete assignments (no variable)", () => {
    const result = serializeAssignments([
      { sheet: "mc.jaime", variable: "", operator: "set", value: "50" },
    ]);
    expect(result).toBe("");
  });

  it("returns empty for null/empty input", () => {
    expect(serializeAssignments(null)).toBe("");
    expect(serializeAssignments([])).toBe("");
    expect(serializeAssignments(undefined)).toBe("");
  });

  it("quotes string values", () => {
    const result = serializeAssignments([
      {
        sheet: "mc.jaime",
        variable: "class",
        operator: "set",
        value: "warrior",
        value_type: "literal",
      },
    ]);
    expect(result).toBe('mc.jaime.class = "warrior"');
  });
});

describe("serializeCondition", () => {
  it("serializes AND condition", () => {
    const result = serializeCondition({
      logic: "all",
      rules: [
        { sheet: "mc.jaime", variable: "health", operator: "greater_than", value: "50" },
        { sheet: "global", variable: "quest", operator: "less_than", value: "10" },
      ],
    });
    expect(result).toBe("mc.jaime.health > 50 && global.quest < 10");
  });

  it("serializes OR condition", () => {
    const result = serializeCondition({
      logic: "any",
      rules: [
        { sheet: "a", variable: "b", operator: "greater_than", value: "1" },
        { sheet: "c", variable: "d", operator: "less_than", value: "2" },
      ],
    });
    expect(result).toBe("a.b > 1 || c.d < 2");
  });

  it("serializes is_true", () => {
    const result = serializeCondition({
      logic: "all",
      rules: [{ sheet: "party", variable: "present", operator: "is_true" }],
    });
    expect(result).toBe("party.present");
  });

  it("serializes is_false", () => {
    const result = serializeCondition({
      logic: "all",
      rules: [{ sheet: "mc.jaime", variable: "dead", operator: "is_false" }],
    });
    expect(result).toBe("!mc.jaime.dead");
  });

  it("serializes string value with quotes", () => {
    const result = serializeCondition({
      logic: "all",
      rules: [{ sheet: "mc.jaime", variable: "class", operator: "equals", value: "warrior" }],
    });
    expect(result).toBe('mc.jaime.class == "warrior"');
  });

  it("serializes all comparison operators", () => {
    const cases = [
      ["equals", "=="],
      ["not_equals", "!="],
      ["greater_than", ">"],
      ["less_than", "<"],
      ["greater_than_or_equal", ">="],
      ["less_than_or_equal", "<="],
    ];

    for (const [op, symbol] of cases) {
      const result = serializeCondition({
        logic: "all",
        rules: [{ sheet: "a", variable: "b", operator: op, value: "10" }],
      });
      expect(result).toBe(`a.b ${symbol} 10`);
    }
  });

  it("serializes is_nil", () => {
    const result = serializeCondition({
      logic: "all",
      rules: [{ sheet: "mc.jaime", variable: "class", operator: "is_nil" }],
    });
    expect(result).toBe("mc.jaime.class == nil");
  });

  it("serializes is_empty", () => {
    const result = serializeCondition({
      logic: "all",
      rules: [{ sheet: "mc.jaime", variable: "name", operator: "is_empty" }],
    });
    expect(result).toBe('mc.jaime.name == ""');
  });

  it("serializes text operators with function syntax", () => {
    const result = serializeCondition({
      logic: "all",
      rules: [{ sheet: "mc.jaime", variable: "name", operator: "contains", value: "Annah" }],
    });
    expect(result).toBe('contains(mc.jaime.name, "Annah")');
  });

  it("returns empty for null/empty input", () => {
    expect(serializeCondition(null)).toBe("");
    expect(serializeCondition({ logic: "all", rules: [] })).toBe("");
  });

  it("skips rules with missing sheet or variable", () => {
    const result = serializeCondition({
      logic: "all",
      rules: [
        { sheet: "", variable: "health", operator: "equals", value: "50" },
        { sheet: "mc.jaime", variable: "health", operator: "equals", value: "50" },
      ],
    });
    expect(result).toBe("mc.jaime.health == 50");
  });

  it("serializes block format with single block", () => {
    const result = serializeCondition({
      logic: "all",
      blocks: [
        {
          id: "block_1",
          type: "block",
          logic: "all",
          rules: [{ sheet: "mc.jaime", variable: "health", operator: "greater_than", value: "50" }],
        },
      ],
    });
    expect(result).toBe("mc.jaime.health > 50");
  });

  it("serializes block format with multiple blocks", () => {
    const result = serializeCondition({
      logic: "all",
      blocks: [
        {
          id: "block_1",
          type: "block",
          logic: "all",
          rules: [{ sheet: "mc.jaime", variable: "health", operator: "greater_than", value: "50" }],
        },
        {
          id: "block_2",
          type: "block",
          logic: "all",
          rules: [{ sheet: "mc.jaime", variable: "alive", operator: "is_true" }],
        },
      ],
    });
    expect(result).toBe("mc.jaime.health > 50 && mc.jaime.alive");
  });

  it("serializes block format with multi-rule blocks using parens", () => {
    const result = serializeCondition({
      logic: "any",
      blocks: [
        {
          id: "block_1",
          type: "block",
          logic: "all",
          rules: [
            { sheet: "mc.jaime", variable: "health", operator: "greater_than", value: "50" },
            { sheet: "mc.jaime", variable: "alive", operator: "is_true" },
          ],
        },
        {
          id: "block_2",
          type: "block",
          logic: "all",
          rules: [{ sheet: "global", variable: "override", operator: "is_true" }],
        },
      ],
    });
    expect(result).toBe("(mc.jaime.health > 50 && mc.jaime.alive) || global.override");
  });

  it("serializes block format with group", () => {
    const result = serializeCondition({
      logic: "all",
      blocks: [
        {
          id: "group_1",
          type: "group",
          logic: "any",
          blocks: [
            {
              id: "block_1",
              type: "block",
              logic: "all",
              rules: [
                { sheet: "mc.jaime", variable: "health", operator: "greater_than", value: "50" },
              ],
            },
            {
              id: "block_2",
              type: "block",
              logic: "all",
              rules: [{ sheet: "global", variable: "override", operator: "is_true" }],
            },
          ],
        },
      ],
    });
    expect(result).toBe("(mc.jaime.health > 50 || global.override)");
  });

  it("returns empty for block format with empty blocks", () => {
    expect(serializeCondition({ logic: "all", blocks: [] })).toBe("");
  });
});

describe("Round-trip", () => {
  it("assignments: serialize(parse(text)) produces equivalent text", () => {
    const original = "mc.jaime.health = 50";
    const { assignments } = parseAssignments(original);
    const reserialized = serializeAssignments(assignments);
    expect(reserialized).toBe(original);
  });

  it("assignments: multiple lines round-trip", () => {
    // Parser uses ";" but serializer uses "\n", so we test semantic equivalence
    const original = "mc.jaime.health = 50; global.quest += 1";
    const { assignments } = parseAssignments(original);
    const reserialized = serializeAssignments(assignments);

    // Reparse the serialized output and compare structure
    const { assignments: reparsed } = parseAssignments(reserialized.replace(/\n/g, "; "));
    expect(reparsed).toHaveLength(assignments.length);
    expect(reparsed[0].sheet).toBe(assignments[0].sheet);
    expect(reparsed[0].variable).toBe(assignments[0].variable);
    expect(reparsed[0].operator).toBe(assignments[0].operator);
    expect(reparsed[0].value).toBe(assignments[0].value);
    expect(reparsed[1].sheet).toBe(assignments[1].sheet);
    expect(reparsed[1].operator).toBe(assignments[1].operator);
  });

  it("conditions: serialize(parse(text)) produces equivalent text", () => {
    const original = "mc.jaime.health > 50";
    const { condition } = parseCondition(original);
    const reserialized = serializeCondition(condition);
    expect(reserialized).toBe(original);
  });

  it("conditions: AND condition round-trip", () => {
    const original = "a.b > 1 && c.d < 2";
    const { condition } = parseCondition(original);
    const reserialized = serializeCondition(condition);
    expect(reserialized).toBe(original);
  });

  it("conditions: OR condition round-trip", () => {
    const original = "a.b > 1 || c.d < 2";
    const { condition } = parseCondition(original);
    const reserialized = serializeCondition(condition);
    expect(reserialized).toBe(original);
  });

  it("conditions: boolean variable round-trip", () => {
    const original = "party.present";
    const { condition } = parseCondition(original);
    const reserialized = serializeCondition(condition);
    expect(reserialized).toBe(original);
  });

  it("conditions: negated variable round-trip", () => {
    const original = "!party.present";
    const { condition } = parseCondition(original);
    const reserialized = serializeCondition(condition);
    expect(reserialized).toBe(original);
  });

  it("conditions: string value round-trip", () => {
    const original = 'mc.jaime.class == "warrior"';
    const { condition } = parseCondition(original);
    const reserialized = serializeCondition(condition);
    expect(reserialized).toBe(original);
  });
});
