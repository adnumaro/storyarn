import {
  operatorsForType,
  typesForOperator,
  getTemplate,
  expandTemplateForVariableRef,
  NO_VALUE_OPERATORS,
  ALL_OPERATORS,
  OPERATORS_BY_TYPE,
  OPERATOR_VERB_KEYS,
  OPERATOR_DROPDOWN_LABEL_KEYS,
} from "../../../../shared/domain/operators/instruction-operators";
import enCommon from "../../../../locales/en/common.json";
import esCommon from "../../../../locales/es/common.json";

type Messages = { [key: string]: string | Messages };

// Reads a translation straight from a locale file, so a missing key fails.
function message(messages: Messages, key: string): string | undefined {
  let node: string | Messages | undefined = messages;
  for (const part of key.split(".")) node = typeof node === "object" ? node[part] : undefined;
  return typeof node === "string" ? node : undefined;
}

const en = enCommon as Messages;
const es = esCommon as Messages;

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
    expect(template[0]).toEqual({ type: "verb" });
    expect(template.find((t) => t.key === "sheet")).toBeDefined();
    expect(template.find((t) => t.key === "variable")).toBeDefined();
    expect(template.find((t) => t.key === "value")).toBeDefined();
  });

  it("returns the add template with value before variable", () => {
    const template = getTemplate("add");
    expect(template[0]).toEqual({ type: "verb" });
    const valueIdx = template.findIndex((t) => t.key === "value");
    const sheetIdx = template.findIndex((t) => t.key === "sheet");
    expect(valueIdx).toBeLessThan(sheetIdx);
  });

  it("returns the subtract template", () => {
    const template = getTemplate("subtract");
    expect(template[0]).toEqual({ type: "verb" });
    expect(
      template.some(
        (t) => t.type === "text" && t.label === "common.instruction_operators.text.subtract_from",
      ),
    ).toBe(true);
  });

  it("returns set_true template without value slot", () => {
    const template = getTemplate("set_true");
    expect(template.find((t) => t.key === "value")).toBeUndefined();
    expect(
      template.some(
        (t) => t.type === "text" && t.label === "common.instruction_operators.text.to_true",
      ),
    ).toBe(true);
  });

  it("returns set_false template without value slot", () => {
    const template = getTemplate("set_false");
    expect(template.find((t) => t.key === "value")).toBeUndefined();
    expect(
      template.some(
        (t) => t.type === "text" && t.label === "common.instruction_operators.text.to_false",
      ),
    ).toBe(true);
  });

  it("returns toggle template without value slot", () => {
    const template = getTemplate("toggle");
    expect(template[0]).toEqual({ type: "verb" });
    expect(template.find((t) => t.key === "value")).toBeUndefined();
  });

  it("returns clear template without value slot", () => {
    const template = getTemplate("clear");
    expect(template[0]).toEqual({ type: "verb" });
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
    expect(valueSheetSlot!.placeholder).toBe("common.condition_builder.placeholders.sheet");

    const valueSlot = expanded.find((t) => t.key === "value");
    expect(valueSlot).toBeDefined();
    expect(valueSlot!.placeholder).toBe("common.condition_builder.placeholders.variable");
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

describe("OPERATOR_VERB_KEYS and OPERATOR_DROPDOWN_LABEL_KEYS", () => {
  it("translate every operator in English and Spanish", () => {
    for (const op of ALL_OPERATORS) {
      for (const messages of [en, es]) {
        expect(message(messages, OPERATOR_VERB_KEYS[op])).toBeTruthy();
        expect(message(messages, OPERATOR_DROPDOWN_LABEL_KEYS[op])).toBeTruthy();
      }
    }
  });

  it("read in the viewer's language", () => {
    expect(message(en, OPERATOR_VERB_KEYS.add)).toBe("Add");
    expect(message(es, OPERATOR_VERB_KEYS.add)).toBe("Sumar");
    expect(message(en, OPERATOR_DROPDOWN_LABEL_KEYS.subtract)).toBe("Subtract \u2026 from");
    expect(message(es, OPERATOR_DROPDOWN_LABEL_KEYS.subtract)).toBe("Restar \u2026 de");
  });

  it("translate every text and placeholder of every sentence template", () => {
    for (const op of ALL_OPERATORS) {
      const template = expandTemplateForVariableRef(getTemplate(op));
      for (const item of template) {
        for (const key of [item.label, item.placeholder]) {
          if (!key) continue;
          expect(message(en, key)).toBeTruthy();
          expect(message(es, key)).toBeTruthy();
        }
      }
    }
  });
});
