import {
  operatorsForType,
  typesForOperator,
  getTemplate,
  expandTemplateForVariableRef,
  NO_VALUE_OPERATORS,
  ALL_OPERATORS,
  OPERATORS_BY_TYPE,
  OPERATOR_VERBS,
  OPERATOR_DROPDOWN_LABELS,
} from "@modules/shared/operators/instruction-operators";

describe("operatorsForType", () => {
  it("returns number operators", () => {
    expect(operatorsForType("number")).toEqual(["set", "add", "subtract"]);
  });

  it("returns boolean operators", () => {
    expect(operatorsForType("boolean")).toEqual(["set_true", "set_false", "toggle"]);
  });

  it("returns text operators", () => {
    expect(operatorsForType("text")).toEqual(["set", "clear"]);
  });

  it("returns rich_text operators", () => {
    expect(operatorsForType("rich_text")).toEqual(["set", "clear"]);
  });

  it("returns select operators", () => {
    expect(operatorsForType("select")).toEqual(["set"]);
  });

  it("returns multi_select operators", () => {
    expect(operatorsForType("multi_select")).toEqual(["set"]);
  });

  it("returns date operators", () => {
    expect(operatorsForType("date")).toEqual(["set"]);
  });

  it("returns reference operators", () => {
    expect(operatorsForType("reference")).toEqual(["set"]);
  });

  it("falls back to text operators for unknown types", () => {
    expect(operatorsForType("unknown")).toEqual(OPERATORS_BY_TYPE.text);
  });
});

describe("typesForOperator", () => {
  it("returns null for 'set' (all types accepted)", () => {
    expect(typesForOperator("set")).toBeNull();
  });

  it("returns ['number'] for 'add'", () => {
    expect(typesForOperator("add")).toEqual(["number"]);
  });

  it("returns ['number'] for 'subtract'", () => {
    expect(typesForOperator("subtract")).toEqual(["number"]);
  });

  it("returns ['boolean'] for 'set_true'", () => {
    expect(typesForOperator("set_true")).toEqual(["boolean"]);
  });

  it("returns ['boolean'] for 'set_false'", () => {
    expect(typesForOperator("set_false")).toEqual(["boolean"]);
  });

  it("returns ['boolean'] for 'toggle'", () => {
    expect(typesForOperator("toggle")).toEqual(["boolean"]);
  });

  it("returns ['text', 'rich_text'] for 'clear'", () => {
    expect(typesForOperator("clear")).toEqual(["text", "rich_text"]);
  });

  it("returns null for unknown operator", () => {
    expect(typesForOperator("nonexistent")).toBeNull();
  });
});

describe("getTemplate", () => {
  it("returns the set template", () => {
    const template = getTemplate("set");
    expect(template[0]).toEqual({ type: "verb", value: "Set" });
    expect(template.find((t) => t.key === "sheet")).toBeDefined();
    expect(template.find((t) => t.key === "variable")).toBeDefined();
    expect(template.find((t) => t.key === "value")).toBeDefined();
  });

  it("returns the add template with value before variable", () => {
    const template = getTemplate("add");
    expect(template[0]).toEqual({ type: "verb", value: "Add" });
    const valueIdx = template.findIndex((t) => t.key === "value");
    const sheetIdx = template.findIndex((t) => t.key === "sheet");
    expect(valueIdx).toBeLessThan(sheetIdx);
  });

  it("returns the subtract template", () => {
    const template = getTemplate("subtract");
    expect(template[0]).toEqual({ type: "verb", value: "Subtract" });
    expect(template.some((t) => t.type === "text" && t.value === "from")).toBe(true);
  });

  it("returns set_true template without value slot", () => {
    const template = getTemplate("set_true");
    expect(template.find((t) => t.key === "value")).toBeUndefined();
    expect(template.some((t) => t.type === "text" && t.value === "to true")).toBe(true);
  });

  it("returns set_false template without value slot", () => {
    const template = getTemplate("set_false");
    expect(template.find((t) => t.key === "value")).toBeUndefined();
    expect(template.some((t) => t.type === "text" && t.value === "to false")).toBe(true);
  });

  it("returns toggle template without value slot", () => {
    const template = getTemplate("toggle");
    expect(template[0]).toEqual({ type: "verb", value: "Toggle" });
    expect(template.find((t) => t.key === "value")).toBeUndefined();
  });

  it("returns clear template without value slot", () => {
    const template = getTemplate("clear");
    expect(template[0]).toEqual({ type: "verb", value: "Clear" });
    expect(template.find((t) => t.key === "value")).toBeUndefined();
  });

  it("falls back to set template for unknown operator", () => {
    expect(getTemplate("unknown")).toEqual(getTemplate("set"));
  });
});

describe("expandTemplateForVariableRef", () => {
  it("expands the value slot into value_sheet + separator + value", () => {
    const template = getTemplate("set");
    const expanded = expandTemplateForVariableRef(template);

    const valueSheetSlot = expanded.find((t) => t.key === "value_sheet");
    expect(valueSheetSlot).toBeDefined();
    expect(valueSheetSlot!.placeholder).toBe("sheet");

    const valueSlot = expanded.find((t) => t.key === "value");
    expect(valueSlot).toBeDefined();
    expect(valueSlot!.placeholder).toBe("variable");
  });

  it("inserts a middle-dot separator between value_sheet and value", () => {
    const template = getTemplate("set");
    const expanded = expandTemplateForVariableRef(template);

    const valueSheetIdx = expanded.findIndex((t) => t.key === "value_sheet");
    expect(expanded[valueSheetIdx + 1]).toEqual({ type: "text", value: "\u00b7" });
    expect(expanded[valueSheetIdx + 2].key).toBe("value");
  });

  it("does not modify templates without a value slot", () => {
    const template = getTemplate("toggle");
    const expanded = expandTemplateForVariableRef(template);
    expect(expanded).toEqual(template);
  });

  it("expands add template correctly (value slot comes before sheet)", () => {
    const template = getTemplate("add");
    const expanded = expandTemplateForVariableRef(template);

    const valueSheetIdx = expanded.findIndex((t) => t.key === "value_sheet");
    const sheetIdx = expanded.findIndex((t) => t.key === "sheet");
    // In add template, value comes before sheet, so expanded value_sheet should too
    expect(valueSheetIdx).toBeLessThan(sheetIdx);
  });

  it("does not mutate the original template", () => {
    const template = getTemplate("set");
    const originalLength = template.length;
    expandTemplateForVariableRef(template);
    expect(template.length).toBe(originalLength);
  });
});

describe("NO_VALUE_OPERATORS", () => {
  it("contains set_true, set_false, toggle, clear", () => {
    expect(NO_VALUE_OPERATORS.has("set_true")).toBe(true);
    expect(NO_VALUE_OPERATORS.has("set_false")).toBe(true);
    expect(NO_VALUE_OPERATORS.has("toggle")).toBe(true);
    expect(NO_VALUE_OPERATORS.has("clear")).toBe(true);
  });

  it("does not contain set, add, subtract", () => {
    expect(NO_VALUE_OPERATORS.has("set")).toBe(false);
    expect(NO_VALUE_OPERATORS.has("add")).toBe(false);
    expect(NO_VALUE_OPERATORS.has("subtract")).toBe(false);
  });

  it("has exactly 4 entries", () => {
    expect(NO_VALUE_OPERATORS.size).toBe(4);
  });
});

describe("ALL_OPERATORS", () => {
  it("contains all 7 operators", () => {
    expect(ALL_OPERATORS).toHaveLength(7);
    expect(ALL_OPERATORS).toContain("set");
    expect(ALL_OPERATORS).toContain("add");
    expect(ALL_OPERATORS).toContain("subtract");
    expect(ALL_OPERATORS).toContain("set_true");
    expect(ALL_OPERATORS).toContain("set_false");
    expect(ALL_OPERATORS).toContain("toggle");
    expect(ALL_OPERATORS).toContain("clear");
  });
});

describe("OPERATOR_VERBS", () => {
  it("has a verb for every operator in ALL_OPERATORS", () => {
    for (const op of ALL_OPERATORS) {
      expect(OPERATOR_VERBS[op]).toBeDefined();
      expect(typeof OPERATOR_VERBS[op]).toBe("string");
    }
  });

  it("has correct specific verbs", () => {
    expect(OPERATOR_VERBS.set).toBe("Set");
    expect(OPERATOR_VERBS.add).toBe("Add");
    expect(OPERATOR_VERBS.subtract).toBe("Subtract");
    expect(OPERATOR_VERBS.toggle).toBe("Toggle");
    expect(OPERATOR_VERBS.clear).toBe("Clear");
  });
});

describe("OPERATOR_DROPDOWN_LABELS", () => {
  it("has a label for every operator in ALL_OPERATORS", () => {
    for (const op of ALL_OPERATORS) {
      expect(OPERATOR_DROPDOWN_LABELS[op]).toBeDefined();
      expect(typeof OPERATOR_DROPDOWN_LABELS[op]).toBe("string");
    }
  });

  it("has descriptive labels", () => {
    expect(OPERATOR_DROPDOWN_LABELS.set).toBe("Set \u2026 to");
    expect(OPERATOR_DROPDOWN_LABELS.add).toBe("Add \u2026 to");
    expect(OPERATOR_DROPDOWN_LABELS.subtract).toBe("Subtract \u2026 from");
    expect(OPERATOR_DROPDOWN_LABELS.toggle).toBe("Toggle");
    expect(OPERATOR_DROPDOWN_LABELS.clear).toBe("Clear");
  });
});
