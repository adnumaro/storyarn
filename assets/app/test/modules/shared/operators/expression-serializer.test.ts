import {
  serializeCondition,
  serializeAssignments,
} from "../../../../shared/domain/operators/expression-serializer";

describe("serializeCondition", () => {
  describe("null/empty handling", () => {
    it("returns empty string for null", () => {
      expect(serializeCondition(null)).toBe("");
    });

    it("returns empty string for undefined", () => {
      expect(serializeCondition(undefined)).toBe("");
    });

    it("returns empty string for empty object", () => {
      expect(serializeCondition({})).toBe("");
    });

    it("returns empty string for empty blocks array", () => {
      expect(serializeCondition({ logic: "all", blocks: [] })).toBe("");
    });
  });

  describe("single rule conditions", () => {
    it("serializes equals operator", () => {
      const condition = {
        logic: "all" as const,
        blocks: [
          {
            logic: "all" as const,
            rules: [{ sheet: "char", variable: "name", operator: "equals", value: "Alice" }],
          },
        ],
      };
      expect(serializeCondition(condition)).toBe('char.name == "Alice"');
    });

    it("serializes not_equals operator", () => {
      const condition = {
        logic: "all" as const,
        blocks: [
          {
            logic: "all" as const,
            rules: [{ sheet: "char", variable: "hp", operator: "not_equals", value: 0 }],
          },
        ],
      };
      expect(serializeCondition(condition)).toBe("char.hp != 0");
    });

    it("serializes greater_than operator", () => {
      const condition = {
        logic: "all" as const,
        blocks: [
          {
            logic: "all" as const,
            rules: [{ sheet: "char", variable: "hp", operator: "greater_than", value: 50 }],
          },
        ],
      };
      expect(serializeCondition(condition)).toBe("char.hp > 50");
    });

    it("serializes less_than operator", () => {
      const condition = {
        logic: "all" as const,
        blocks: [
          {
            logic: "all" as const,
            rules: [{ sheet: "char", variable: "hp", operator: "less_than", value: 10 }],
          },
        ],
      };
      expect(serializeCondition(condition)).toBe("char.hp < 10");
    });

    it("serializes greater_than_or_equal operator", () => {
      const condition = {
        logic: "all" as const,
        blocks: [
          {
            logic: "all" as const,
            rules: [{ sheet: "s", variable: "v", operator: "greater_than_or_equal", value: 5 }],
          },
        ],
      };
      expect(serializeCondition(condition)).toBe("s.v >= 5");
    });

    it("serializes less_than_or_equal operator", () => {
      const condition = {
        logic: "all" as const,
        blocks: [
          {
            logic: "all" as const,
            rules: [{ sheet: "s", variable: "v", operator: "less_than_or_equal", value: 100 }],
          },
        ],
      };
      expect(serializeCondition(condition)).toBe("s.v <= 100");
    });

    it("serializes contains operator", () => {
      const condition = {
        logic: "all" as const,
        blocks: [
          {
            logic: "all" as const,
            rules: [{ sheet: "s", variable: "v", operator: "contains", value: "hello" }],
          },
        ],
      };
      expect(serializeCondition(condition)).toBe('s.v contains "hello"');
    });

    it("serializes starts_with operator", () => {
      const condition = {
        logic: "all" as const,
        blocks: [
          {
            logic: "all" as const,
            rules: [{ sheet: "s", variable: "v", operator: "starts_with", value: "pre" }],
          },
        ],
      };
      expect(serializeCondition(condition)).toBe('s.v starts_with "pre"');
    });

    it("serializes ends_with operator", () => {
      const condition = {
        logic: "all" as const,
        blocks: [
          {
            logic: "all" as const,
            rules: [{ sheet: "s", variable: "v", operator: "ends_with", value: "suf" }],
          },
        ],
      };
      expect(serializeCondition(condition)).toBe('s.v ends_with "suf"');
    });

    it("serializes not_contains operator", () => {
      const condition = {
        logic: "all" as const,
        blocks: [
          {
            logic: "all" as const,
            rules: [{ sheet: "s", variable: "v", operator: "not_contains", value: "bad" }],
          },
        ],
      };
      expect(serializeCondition(condition)).toBe('s.v not_contains "bad"');
    });

    it("serializes before operator (date)", () => {
      const condition = {
        logic: "all" as const,
        blocks: [
          {
            logic: "all" as const,
            rules: [{ sheet: "s", variable: "v", operator: "before", value: "2024-01-01" }],
          },
        ],
      };
      expect(serializeCondition(condition)).toBe('s.v < "2024-01-01"');
    });

    it("serializes after operator (date)", () => {
      const condition = {
        logic: "all" as const,
        blocks: [
          {
            logic: "all" as const,
            rules: [{ sheet: "s", variable: "v", operator: "after", value: "2024-01-01" }],
          },
        ],
      };
      expect(serializeCondition(condition)).toBe('s.v > "2024-01-01"');
    });
  });

  describe("special operators (no value)", () => {
    it("serializes is_true as bare reference", () => {
      const condition = {
        logic: "all" as const,
        blocks: [
          {
            logic: "all" as const,
            rules: [{ sheet: "char", variable: "alive", operator: "is_true" }],
          },
        ],
      };
      expect(serializeCondition(condition)).toBe("char.alive");
    });

    it("serializes is_false with negation prefix", () => {
      const condition = {
        logic: "all" as const,
        blocks: [
          {
            logic: "all" as const,
            rules: [{ sheet: "char", variable: "dead", operator: "is_false" }],
          },
        ],
      };
      expect(serializeCondition(condition)).toBe("!char.dead");
    });

    it("serializes is_nil as equals nil", () => {
      const condition = {
        logic: "all" as const,
        blocks: [
          {
            logic: "all" as const,
            rules: [{ sheet: "char", variable: "weapon", operator: "is_nil" }],
          },
        ],
      };
      expect(serializeCondition(condition)).toBe("char.weapon == nil");
    });

    it("serializes is_empty as equals empty string", () => {
      const condition = {
        logic: "all" as const,
        blocks: [
          {
            logic: "all" as const,
            rules: [{ sheet: "char", variable: "notes", operator: "is_empty" }],
          },
        ],
      };
      expect(serializeCondition(condition)).toBe('char.notes == ""');
    });
  });

  describe("value formatting", () => {
    it("formats numeric values without quotes", () => {
      const condition = {
        logic: "all" as const,
        blocks: [
          {
            logic: "all" as const,
            rules: [{ sheet: "s", variable: "v", operator: "equals", value: 42 }],
          },
        ],
      };
      expect(serializeCondition(condition)).toBe("s.v == 42");
    });

    it("formats string-numeric values without quotes", () => {
      const condition = {
        logic: "all" as const,
        blocks: [
          {
            logic: "all" as const,
            rules: [{ sheet: "s", variable: "v", operator: "equals", value: "42" }],
          },
        ],
      };
      expect(serializeCondition(condition)).toBe("s.v == 42");
    });

    it("formats non-numeric strings with quotes", () => {
      const condition = {
        logic: "all" as const,
        blocks: [
          {
            logic: "all" as const,
            rules: [{ sheet: "s", variable: "v", operator: "equals", value: "hello" }],
          },
        ],
      };
      expect(serializeCondition(condition)).toBe('s.v == "hello"');
    });

    it("formats null value as ?", () => {
      const condition = {
        logic: "all" as const,
        blocks: [
          {
            logic: "all" as const,
            rules: [{ sheet: "s", variable: "v", operator: "equals", value: null }],
          },
        ],
      };
      expect(serializeCondition(condition)).toBe("s.v == ?");
    });

    it("formats undefined value as ?", () => {
      const condition = {
        logic: "all" as const,
        blocks: [
          {
            logic: "all" as const,
            rules: [{ sheet: "s", variable: "v", operator: "equals" }],
          },
        ],
      };
      expect(serializeCondition(condition)).toBe("s.v == ?");
    });

    it("escapes quotes in string values", () => {
      const condition = {
        logic: "all" as const,
        blocks: [
          {
            logic: "all" as const,
            rules: [{ sheet: "s", variable: "v", operator: "equals", value: 'say "hi"' }],
          },
        ],
      };
      expect(serializeCondition(condition)).toBe('s.v == "say \\"hi\\""');
    });

    it("escapes backslashes in string values", () => {
      const condition = {
        logic: "all" as const,
        blocks: [
          {
            logic: "all" as const,
            rules: [{ sheet: "s", variable: "v", operator: "equals", value: "path\\to" }],
          },
        ],
      };
      expect(serializeCondition(condition)).toBe('s.v == "path\\\\to"');
    });
  });

  describe("multiple rules with logic", () => {
    it("joins rules with && for 'all' logic", () => {
      const condition = {
        logic: "all" as const,
        blocks: [
          {
            logic: "all" as const,
            rules: [
              { sheet: "s", variable: "a", operator: "equals", value: 1 },
              { sheet: "s", variable: "b", operator: "equals", value: 2 },
            ],
          },
        ],
      };
      expect(serializeCondition(condition)).toBe("(s.a == 1 && s.b == 2)");
    });

    it("joins rules with || for 'any' logic", () => {
      const condition = {
        logic: "all" as const,
        blocks: [
          {
            logic: "any" as const,
            rules: [
              { sheet: "s", variable: "a", operator: "equals", value: 1 },
              { sheet: "s", variable: "b", operator: "equals", value: 2 },
            ],
          },
        ],
      };
      expect(serializeCondition(condition)).toBe("(s.a == 1 || s.b == 2)");
    });
  });

  describe("multiple blocks (top-level logic)", () => {
    it("joins blocks with && for top-level 'all' logic", () => {
      const condition = {
        logic: "all" as const,
        blocks: [
          { logic: "all" as const, rules: [{ sheet: "s", variable: "a", operator: "is_true" }] },
          { logic: "all" as const, rules: [{ sheet: "s", variable: "b", operator: "is_false" }] },
        ],
      };
      expect(serializeCondition(condition)).toBe("s.a && !s.b");
    });

    it("joins blocks with || for top-level 'any' logic", () => {
      const condition = {
        logic: "any" as const,
        blocks: [
          { logic: "all" as const, rules: [{ sheet: "s", variable: "a", operator: "is_true" }] },
          { logic: "all" as const, rules: [{ sheet: "s", variable: "b", operator: "is_true" }] },
        ],
      };
      expect(serializeCondition(condition)).toBe("s.a || s.b");
    });
  });

  describe("nested groups", () => {
    it("serializes a nested group block", () => {
      const condition = {
        logic: "all" as const,
        blocks: [
          {
            type: "group" as const,
            logic: "any" as const,
            blocks: [
              {
                logic: "all" as const,
                rules: [{ sheet: "s", variable: "a", operator: "is_true" }],
              },
              {
                logic: "all" as const,
                rules: [{ sheet: "s", variable: "b", operator: "is_true" }],
              },
            ],
          },
        ],
      };
      expect(serializeCondition(condition)).toBe("(s.a || s.b)");
    });

    it("wraps nested group in parens when multiple children", () => {
      const condition = {
        logic: "all" as const,
        blocks: [
          {
            type: "group" as const,
            logic: "all" as const,
            blocks: [
              {
                logic: "all" as const,
                rules: [{ sheet: "s", variable: "x", operator: "equals", value: 1 }],
              },
              {
                logic: "all" as const,
                rules: [{ sheet: "s", variable: "y", operator: "equals", value: 2 }],
              },
            ],
          },
        ],
      };
      expect(serializeCondition(condition)).toBe("(s.x == 1 && s.y == 2)");
    });

    it("does not wrap single-child group in parens", () => {
      const condition = {
        logic: "all" as const,
        blocks: [
          {
            type: "group" as const,
            logic: "any" as const,
            blocks: [
              {
                logic: "all" as const,
                rules: [{ sheet: "s", variable: "a", operator: "is_true" }],
              },
            ],
          },
        ],
      };
      expect(serializeCondition(condition)).toBe("s.a");
    });
  });

  describe("skipping incomplete rules", () => {
    it("skips rules with empty sheet", () => {
      const condition = {
        logic: "all" as const,
        blocks: [
          {
            logic: "all" as const,
            rules: [
              { sheet: "", variable: "v", operator: "equals", value: 1 },
              { sheet: "s", variable: "v", operator: "equals", value: 2 },
            ],
          },
        ],
      };
      expect(serializeCondition(condition)).toBe("s.v == 2");
    });

    it("skips rules with empty variable", () => {
      const condition = {
        logic: "all" as const,
        blocks: [
          {
            logic: "all" as const,
            rules: [
              { sheet: "s", variable: "", operator: "equals", value: 1 },
              { sheet: "s", variable: "v", operator: "equals", value: 2 },
            ],
          },
        ],
      };
      expect(serializeCondition(condition)).toBe("s.v == 2");
    });

    it("returns empty string when all rules are incomplete", () => {
      const condition = {
        logic: "all" as const,
        blocks: [
          {
            logic: "all" as const,
            rules: [{ sheet: "", variable: "", operator: "equals", value: 1 }],
          },
        ],
      };
      expect(serializeCondition(condition)).toBe("");
    });
  });
});

describe("serializeAssignments", () => {
  describe("null/empty handling", () => {
    it("returns empty string for null", () => {
      expect(serializeAssignments(null)).toBe("");
    });

    it("returns empty string for undefined", () => {
      expect(serializeAssignments(undefined)).toBe("");
    });

    it("returns empty string for empty array", () => {
      expect(serializeAssignments([])).toBe("");
    });
  });

  describe("basic operators", () => {
    it("serializes set operator", () => {
      const result = serializeAssignments([
        { operator: "set", sheet: "char", variable: "hp", value: 100 },
      ]);
      expect(result).toBe("char.hp = 100");
    });

    it("serializes add operator", () => {
      const result = serializeAssignments([
        { operator: "add", sheet: "char", variable: "hp", value: 10 },
      ]);
      expect(result).toBe("char.hp += 10");
    });

    it("serializes subtract operator", () => {
      const result = serializeAssignments([
        { operator: "subtract", sheet: "char", variable: "hp", value: 5 },
      ]);
      expect(result).toBe("char.hp -= 5");
    });
  });

  describe("fixed value operators", () => {
    it("serializes set_true", () => {
      const result = serializeAssignments([
        { operator: "set_true", sheet: "char", variable: "alive" },
      ]);
      expect(result).toBe("char.alive = true");
    });

    it("serializes set_false", () => {
      const result = serializeAssignments([
        { operator: "set_false", sheet: "char", variable: "dead" },
      ]);
      expect(result).toBe("char.dead = false");
    });

    it("serializes toggle", () => {
      const result = serializeAssignments([
        { operator: "toggle", sheet: "flags", variable: "active" },
      ]);
      expect(result).toBe("toggle flags.active");
    });

    it("serializes clear", () => {
      const result = serializeAssignments([
        { operator: "clear", sheet: "char", variable: "notes" },
      ]);
      expect(result).toBe("clear char.notes");
    });
  });

  describe("variable reference values", () => {
    it("serializes variable_ref value type", () => {
      const result = serializeAssignments([
        {
          operator: "set",
          sheet: "char",
          variable: "hp",
          value: "max_hp",
          value_type: "variable_ref",
          value_sheet: "stats",
        },
      ]);
      expect(result).toBe("char.hp = stats.max_hp");
    });

    it("falls back to formatValue when value_sheet is missing for variable_ref", () => {
      const result = serializeAssignments([
        {
          operator: "set",
          sheet: "char",
          variable: "hp",
          value: "max_hp",
          value_type: "variable_ref",
          value_sheet: "",
        },
      ]);
      expect(result).toBe('char.hp = "max_hp"');
    });
  });

  describe("multiple assignments", () => {
    it("joins multiple assignments with newlines", () => {
      const result = serializeAssignments([
        { operator: "set", sheet: "char", variable: "hp", value: 100 },
        { operator: "set_true", sheet: "char", variable: "alive" },
        { operator: "add", sheet: "char", variable: "xp", value: 50 },
      ]);
      expect(result).toBe("char.hp = 100\nchar.alive = true\nchar.xp += 50");
    });
  });

  describe("skipping incomplete assignments", () => {
    it("skips assignments with empty sheet", () => {
      const result = serializeAssignments([
        { operator: "set", sheet: "", variable: "hp", value: 100 },
        { operator: "set", sheet: "char", variable: "hp", value: 50 },
      ]);
      expect(result).toBe("char.hp = 50");
    });

    it("skips assignments with empty variable", () => {
      const result = serializeAssignments([
        { operator: "set", sheet: "char", variable: "", value: 100 },
        { operator: "set", sheet: "char", variable: "hp", value: 50 },
      ]);
      expect(result).toBe("char.hp = 50");
    });
  });

  describe("value formatting in assignments", () => {
    it("formats string values with quotes", () => {
      const result = serializeAssignments([
        { operator: "set", sheet: "char", variable: "name", value: "Alice" },
      ]);
      expect(result).toBe('char.name = "Alice"');
    });

    it("formats null value as ?", () => {
      const result = serializeAssignments([
        { operator: "set", sheet: "char", variable: "hp", value: null },
      ]);
      expect(result).toBe("char.hp = ?");
    });

    it("formats numeric string without quotes", () => {
      const result = serializeAssignments([
        { operator: "set", sheet: "char", variable: "hp", value: "42" },
      ]);
      expect(result).toBe("char.hp = 42");
    });

    it("uses fallback = for unknown operators", () => {
      const result = serializeAssignments([
        { operator: "unknown_op", sheet: "char", variable: "hp", value: 10 },
      ]);
      expect(result).toBe("char.hp = 10");
    });
  });
});
