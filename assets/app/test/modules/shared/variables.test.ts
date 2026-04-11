import { groupVariablesBySheet, findVariable, generateId } from "@modules/shared/variables";
import type { Variable } from "@modules/shared/variables";

const makeVariable = (overrides: Partial<Variable> = {}): Variable => ({
  sheet_shortcut: "char",
  sheet_name: "Characters",
  variable_name: "health",
  block_type: "number",
  ...overrides,
});

describe("groupVariablesBySheet", () => {
  it("returns empty array for empty input", () => {
    expect(groupVariablesBySheet([])).toEqual([]);
  });

  it("groups variables by sheet_shortcut", () => {
    const variables: Variable[] = [
      makeVariable({ sheet_shortcut: "char", sheet_name: "Characters", variable_name: "health" }),
      makeVariable({ sheet_shortcut: "char", sheet_name: "Characters", variable_name: "mana" }),
      makeVariable({ sheet_shortcut: "items", sheet_name: "Items", variable_name: "count" }),
    ];

    const result = groupVariablesBySheet(variables);
    expect(result).toHaveLength(2);

    const charGroup = result.find((g) => g.shortcut === "char");
    expect(charGroup).toBeDefined();
    expect(charGroup!.name).toBe("Characters");
    expect(charGroup!.vars).toHaveLength(2);
    expect(charGroup!.vars[0].variable_name).toBe("health");
    expect(charGroup!.vars[1].variable_name).toBe("mana");

    const itemsGroup = result.find((g) => g.shortcut === "items");
    expect(itemsGroup).toBeDefined();
    expect(itemsGroup!.vars).toHaveLength(1);
  });

  it("uses sheet_shortcut as name when sheet_name is missing", () => {
    const variables: Variable[] = [
      makeVariable({ sheet_shortcut: "stats", sheet_name: undefined, variable_name: "hp" }),
    ];

    const result = groupVariablesBySheet(variables);
    expect(result[0].name).toBe("stats");
  });

  it("sorts groups alphabetically by name", () => {
    const variables: Variable[] = [
      makeVariable({ sheet_shortcut: "z_sheet", sheet_name: "Zebra", variable_name: "a" }),
      makeVariable({ sheet_shortcut: "a_sheet", sheet_name: "Alpha", variable_name: "b" }),
      makeVariable({ sheet_shortcut: "m_sheet", sheet_name: "Middle", variable_name: "c" }),
    ];

    const result = groupVariablesBySheet(variables);
    expect(result.map((g) => g.name)).toEqual(["Alpha", "Middle", "Zebra"]);
  });

  it("preserves options in grouped vars", () => {
    const options = [{ key: "opt1", value: "Option 1" }];
    const variables: Variable[] = [
      makeVariable({ variable_name: "choice", block_type: "select", options }),
    ];

    const result = groupVariablesBySheet(variables);
    expect(result[0].vars[0].options).toEqual(options);
  });

  it("includes block_type in grouped vars", () => {
    const variables: Variable[] = [
      makeVariable({ variable_name: "hp", block_type: "number" }),
      makeVariable({ variable_name: "name", block_type: "text" }),
    ];

    const result = groupVariablesBySheet(variables);
    expect(result[0].vars[0].block_type).toBe("number");
    expect(result[0].vars[1].block_type).toBe("text");
  });
});

describe("findVariable", () => {
  const variables: Variable[] = [
    makeVariable({ sheet_shortcut: "char", variable_name: "health" }),
    makeVariable({ sheet_shortcut: "char", variable_name: "mana" }),
    makeVariable({ sheet_shortcut: "items", variable_name: "count" }),
  ];

  it("finds a variable by sheet shortcut and variable name", () => {
    const result = findVariable(variables, "char", "health");
    expect(result).toBeDefined();
    expect(result!.sheet_shortcut).toBe("char");
    expect(result!.variable_name).toBe("health");
  });

  it("returns undefined when variable does not exist", () => {
    const result = findVariable(variables, "char", "nonexistent");
    expect(result).toBeUndefined();
  });

  it("returns null when sheetShortcut is null", () => {
    expect(findVariable(variables, null, "health")).toBeNull();
  });

  it("returns null when variableName is null", () => {
    expect(findVariable(variables, "char", null)).toBeNull();
  });

  it("returns null when sheetShortcut is undefined", () => {
    expect(findVariable(variables, undefined, "health")).toBeNull();
  });

  it("returns null when variableName is undefined", () => {
    expect(findVariable(variables, "char", undefined)).toBeNull();
  });

  it("returns null when both are empty strings", () => {
    expect(findVariable(variables, "", "")).toBeNull();
  });

  it("works with empty variable list", () => {
    expect(findVariable([], "char", "health")).toBeUndefined();
  });
});

describe("generateId", () => {
  it("generates an id with the default prefix", () => {
    const id = generateId();
    expect(id).toMatch(/^block_\d+_[a-z0-9]+$/);
  });

  it("generates an id with a custom prefix", () => {
    const id = generateId("condition");
    expect(id).toMatch(/^condition_\d+_[a-z0-9]+$/);
  });

  it("generates unique ids on successive calls", () => {
    const id1 = generateId();
    const id2 = generateId();
    expect(id1).not.toBe(id2);
  });

  it("includes a timestamp component", () => {
    const before = Date.now();
    const id = generateId("test");
    const after = Date.now();

    const parts = id.split("_");
    const timestamp = parseInt(parts[1], 10);
    expect(timestamp).toBeGreaterThanOrEqual(before);
    expect(timestamp).toBeLessThanOrEqual(after);
  });

  it("has a random suffix of 5 characters", () => {
    const id = generateId("x");
    const parts = id.split("_");
    // parts: ["x", timestamp, randomSuffix]
    expect(parts[2].length).toBe(5);
  });
});
